// Phase 4B/4C/4D/4E — SupabaseRestClientのテスト専用インメモリ実装。
// 実Supabaseへは一切出ない。PostgRESTのクエリ文字列のうち、このプロジェクト
// が実際に発行する範囲(column=eq.value、order=column.asc|desc、limit=N、
// select=col1,col2)だけをサポートする最小限のパーサー。

import { RestResult, SupabaseRestClient } from "./supabase_rest_client.ts";

export interface UniqueConstraint {
  table: string;
  columns: string[];
}

export class FakeSupabaseRestClient implements SupabaseRestClient {
  private tables: Map<string, Record<string, unknown>[]> = new Map();
  private uniqueConstraints: UniqueConstraint[] = [];
  private nextId = 1;

  addUniqueConstraint(constraint: UniqueConstraint): void {
    this.uniqueConstraints.push(constraint);
  }

  seed(table: string, rows: Record<string, unknown>[]): void {
    this.tables.set(table, [...(this.tables.get(table) ?? []), ...rows]);
  }

  rowsOf(table: string): Record<string, unknown>[] {
    return this.tables.get(table) ?? [];
  }

  private parseQuery(query: string): {
    filters: [string, string][];
    order?: { column: string; desc: boolean };
    limit?: number;
    select?: string[];
  } {
    const params = new URLSearchParams(query);
    const filters: [string, string][] = [];
    let order: { column: string; desc: boolean } | undefined;
    let limit: number | undefined;
    let select: string[] | undefined;
    for (const [key, value] of params.entries()) {
      if (key === "order") {
        const [column, direction] = value.split(".");
        order = { column, desc: direction === "desc" };
      } else if (key === "limit") {
        limit = Number(value);
      } else if (key === "select") {
        select = value.split(",");
      } else if (value.startsWith("eq.")) {
        filters.push([key, value.slice(3)]);
      }
    }
    return { filters, order, limit, select };
  }

  async select<T>(table: string, query: string): Promise<RestResult<T>> {
    const { filters, order, limit, select } = this.parseQuery(query);
    let rows = this.rowsOf(table).filter((row) =>
      filters.every(([col, val]) => String(row[col]) === val)
    );
    if (order) {
      rows = [...rows].sort((a, b) => {
        const av = String(a[order.column]);
        const bv = String(b[order.column]);
        const cmp = av < bv ? -1 : av > bv ? 1 : 0;
        return order.desc ? -cmp : cmp;
      });
    }
    if (limit !== undefined) {
      rows = rows.slice(0, limit);
    }
    if (select) {
      rows = rows.map((row) => {
        const projected: Record<string, unknown> = {};
        for (const col of select!) projected[col] = row[col];
        return projected;
      });
    }
    return Promise.resolve({ ok: true, rows: rows as T[], status: 200 });
  }

  async insert<T>(table: string, row: Record<string, unknown>): Promise<RestResult<T>> {
    const existing = this.rowsOf(table);
    for (const constraint of this.uniqueConstraints.filter((c) => c.table === table)) {
      const conflict = existing.some((existingRow) =>
        constraint.columns.every((col) => existingRow[col] === row[col])
      );
      if (conflict) {
        return Promise.resolve({
          ok: false,
          rows: [],
          status: 409,
          errorMessage: `duplicate key value violates unique constraint (${constraint.columns.join(",")})`,
        });
      }
    }
    const now = new Date().toISOString();
    const fullRow: Record<string, unknown> = {
      id: row.id ?? `fake-id-${this.nextId++}`,
      created_at: row.created_at ?? now,
      updated_at: row.updated_at ?? now,
      ...row,
    };
    existing.push(fullRow);
    this.tables.set(table, existing);
    return Promise.resolve({ ok: true, rows: [fullRow as T], status: 201 });
  }

  async update<T>(
    table: string,
    filterQuery: string,
    patch: Record<string, unknown>,
  ): Promise<RestResult<T>> {
    const { filters } = this.parseQuery(filterQuery);
    const rows = this.rowsOf(table);
    const updated: Record<string, unknown>[] = [];
    for (const row of rows) {
      if (filters.every(([col, val]) => String(row[col]) === val)) {
        Object.assign(row, patch, { updated_at: new Date().toISOString() });
        updated.push(row);
      }
    }
    return Promise.resolve({ ok: true, rows: updated as T[], status: 200 });
  }

  // record_boss_challenge_attempt/record_boss_challenge_clear
  // (boss_challenge_records migration参照)専用の最小限のRPCシミュレーション。
  // 本物のPostgres関数と同じ「INSERT ... ON CONFLICT (boss_id,
  // challenger_steam_id) DO UPDATE ... = ... + 1」のatomic increment挙動を
  // インメモリで再現する——実SQLは実行しないため、この2関数の意味論だけを
  // 明示的にハードコードする(汎用的なSQL実行エンジンにはしない、この
  // プロジェクトが実際に呼ぶ範囲だけをサポートする既存方針を踏襲)。
  async rpc<T>(functionName: string, params: Record<string, unknown>): Promise<RestResult<T>> {
    if (functionName === "record_boss_challenge_attempt") {
      return this.upsertChallengeRecord(params, "attempt") as Promise<RestResult<T>>;
    }
    if (functionName === "record_boss_challenge_clear") {
      return this.upsertChallengeRecord(params, "clear") as Promise<RestResult<T>>;
    }
    return Promise.resolve({
      ok: false,
      rows: [],
      status: 404,
      errorMessage: `FakeSupabaseRestClient.rpc(): unknown function '${functionName}'`,
    });
  }

  private upsertChallengeRecord(
    params: Record<string, unknown>,
    kind: "attempt" | "clear",
  ): Promise<RestResult<Record<string, unknown>>> {
    const bossId = String(params.p_boss_id ?? "");
    const steamId = String(params.p_steam_id ?? "");
    const rows = this.rowsOf("boss_challenge_records");
    const now = new Date().toISOString();
    let row = rows.find((r) => r.boss_id === bossId && r.challenger_steam_id === steamId);
    if (!row) {
      row = {
        id: `fake-id-${this.nextId++}`,
        boss_id: bossId,
        challenger_steam_id: steamId,
        challenge_count: 0,
        clear_count: 0,
        first_challenged_at: null,
        last_challenged_at: null,
        first_cleared_at: null,
        last_cleared_at: null,
        created_at: now,
      };
      rows.push(row);
      this.tables.set("boss_challenge_records", rows);
    }
    if (kind === "attempt") {
      row.challenge_count = Number(row.challenge_count ?? 0) + 1;
      if (!row.first_challenged_at) row.first_challenged_at = now;
      row.last_challenged_at = now;
    } else {
      row.clear_count = Number(row.clear_count ?? 0) + 1;
      if (!row.first_cleared_at) row.first_cleared_at = now;
      row.last_cleared_at = now;
    }
    row.updated_at = now;
    return Promise.resolve({ ok: true, rows: [row], status: 200 });
  }
}
