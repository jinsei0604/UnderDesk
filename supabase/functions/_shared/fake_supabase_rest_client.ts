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
}
