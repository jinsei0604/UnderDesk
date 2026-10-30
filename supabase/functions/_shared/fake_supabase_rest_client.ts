// Phase 4B/4C/4D/4E — SupabaseRestClientのテスト専用インメモリ実装。
// 実Supabaseへは一切出ない。PostgRESTのクエリ文字列のうち、このプロジェクト
// が実際に発行する範囲(column=eq.value、column=gt.value、column=in.(a,b)、
// order=column.asc|desc、limit=N、select=col1,col2)だけをサポートする最小限のパーサー。
//
// 人気/高難度ランキングの全件取得(_shared/select_all_pages.ts)のテスト用に、
// PostgRESTの「1回の応答の行数上限」(Supabaseの「Max rows」)を真似る
// setMaxRowsPerResponse()と、指定した回のselectを失敗させるfailSelectCall()を持つ。

import { RestResult, SupabaseRestClient } from "./supabase_rest_client.ts";

export interface UniqueConstraint {
  table: string;
  columns: string[];
}

export class FakeSupabaseRestClient implements SupabaseRestClient {
  private tables: Map<string, Record<string, unknown>[]> = new Map();
  private uniqueConstraints: UniqueConstraint[] = [];
  private nextId = 1;
  private maxRowsPerResponse: number | undefined;
  private failingSelects: { table: string; call: number }[] = [];
  // 発行されたselectの記録(テーブルごとの回数を数えるため)。
  selectCalls: { table: string; query: string }[] = [];
  // 2026-10-23: 呼ばれた RPC の記録と、失敗させる RPC（名前・何回目か）。時計（チケットの期限・発行の上限を試すため）。
  rpcCalls: { name: string; params: Record<string, unknown> }[] = [];
  private failingRpcs: { name: string; call: number }[] = [];
  nowMs: number | null = null;

  failRpcCall(name: string, call: number): void {
    this.failingRpcs.push({ name, call });
  }

  private now(): number {
    return this.nowMs ?? Date.now();
  }

  addUniqueConstraint(constraint: UniqueConstraint): void {
    this.uniqueConstraints.push(constraint);
  }

  // PostgRESTの応答行数の上限(limitを大きくしても、これより多くは返さない)。
  setMaxRowsPerResponse(maxRows: number): void {
    this.maxRowsPerResponse = maxRows;
  }

  // tableへのcall回目(1始まり)のselectを、通信/DBの失敗として返す。
  failSelectCall(table: string, call: number): void {
    this.failingSelects.push({ table, call });
  }

  seed(table: string, rows: Record<string, unknown>[]): void {
    this.tables.set(table, [...(this.tables.get(table) ?? []), ...rows]);
  }

  rowsOf(table: string): Record<string, unknown>[] {
    return this.tables.get(table) ?? [];
  }

  private parseQuery(query: string): {
    filters: [string, string][];
    greaterThan: [string, string][];
    oneOf: [string, Set<string>][];
    order?: { column: string; desc: boolean };
    limit?: number;
    select?: string[];
  } {
    const params = new URLSearchParams(query);
    const filters: [string, string][] = [];
    const greaterThan: [string, string][] = [];
    const oneOf: [string, Set<string>][] = [];
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
      } else if (value.startsWith("gt.")) {
        greaterThan.push([key, value.slice(3)]);
      } else if (value.startsWith("in.(") && value.endsWith(")")) {
        oneOf.push([key, new Set(value.slice(4, -1).split(","))]);
      }
    }
    return { filters, greaterThan, oneOf, order, limit, select };
  }

  async select<T>(table: string, query: string): Promise<RestResult<T>> {
    this.selectCalls.push({ table, query });
    const call = this.selectCalls.filter((c) => c.table === table).length;
    if (this.failingSelects.some((f) => f.table === table && f.call === call)) {
      return Promise.resolve({ ok: false, rows: [], status: 503, errorMessage: `fake failure on ${table} select #${call}` });
    }
    const { filters, greaterThan, oneOf, order, limit, select } = this.parseQuery(query);
    let rows = this.rowsOf(table).filter((row) =>
      filters.every(([col, val]) => String(row[col]) === val) &&
      greaterThan.every(([col, val]) => String(row[col]) > val) &&
      oneOf.every(([col, values]) => values.has(String(row[col])))
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
    if (this.maxRowsPerResponse !== undefined) {
      rows = rows.slice(0, this.maxRowsPerResponse);
    }
    if (select) {
      rows = rows.map((row) => {
        const projected: Record<string, unknown> = {};
        for (const col of select!) {
          // 2026-10-29: 「別名:payload->draft_fields->>キー」（JSON の値を別名で取り出す。_shared/edition.ts の
          // demoBossRejection が使う）。無ければ null（PostgREST と同じ）。
          const alias = col.match(/^([a-z_]+):([a-z_]+)((?:->>?[a-z_]+)+)$/);
          if (alias) {
            let value: unknown = row[alias[2]];
            for (const key of alias[3].split(/->>?/).filter((k) => k.length > 0)) {
              value = typeof value === "object" && value !== null ? (value as Record<string, unknown>)[key] : undefined;
            }
            projected[alias[1]] = value === undefined ? null : value;
            continue;
          }
          projected[col] = row[col];
        }
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
    this.rpcCalls.push({ name: functionName, params });
    const call = this.rpcCalls.filter((c) => c.name === functionName).length;
    if (this.failingRpcs.some((f) => f.name === functionName && f.call === call)) {
      return Promise.resolve({ ok: false, rows: [], status: 503, errorMessage: `fake failure on rpc ${functionName} #${call}` });
    }
    if (functionName === "issue_boss_battle_ticket") {
      return Promise.resolve({ ok: true, rows: [this.issueTicket(params) as T], status: 200 });
    }
    if (functionName === "submit_boss_battle_result") {
      return Promise.resolve({ ok: true, rows: [this.submitResult(params) as T], status: 200 });
    }
    if (functionName === "record_boss_challenge_attempt") {
      return this.upsertChallengeRecord(params, "attempt") as Promise<RestResult<T>>;
    }
    if (functionName === "claim_demo_challenge_slot") {
      return Promise.resolve({ ok: true, rows: [this.claimDemoSlot(params) as T], status: 200 });
    }
    if (functionName === "demo_challenge_status") {
      const steamId = String(params.p_steam_id ?? "");
      const mine = this.rowsOf("demo_challenge_slots").filter((r) => r.steam_id === steamId);
      return Promise.resolve({ ok: true, rows: [{ used: mine.length, slot_limit: 15, boss_ids: mine.map((r) => String(r.boss_id)) } as T], status: 200 });
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
    const now = new Date(this.now()).toISOString();
    let row = rows.find((r) => r.boss_id === bossId && r.challenger_steam_id === steamId);
    if (!row) {
      row = {
        id: `fake-id-${this.nextId++}`,
        boss_id: bossId,
        challenger_steam_id: steamId,
        challenge_count: 0,
        clear_count: 0,
        result_count: 0,
        result_clear_count: 0,
        first_clear_challengers: null,
        first_clear_clearers: null,
        hard_awarded_at: null,
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
    // 本物の DB のトリガー（boss_challenge_records_set_by_owner、2026-10-22）と同じ: 挑戦者がボスの作者なら true
    row.by_owner = this.rowsOf("bosses").some((b) => b.id === bossId && b.owner_steam_id === steamId);
    row.updated_at = now;
    return Promise.resolve({ ok: true, rows: [row], status: 200 });
  }

  // 本物の DB の claim_demo_challenge_slot() と同じ（2026-10-29）: 挑戦済みなら already、公開中でなければ not_found、
  // 15体に達していれば limit、それ以外は1行足して claimed。ボスへの外部キーは無い（ボスが消えても行は残る）。
  private claimDemoSlot(params: Record<string, unknown>): Record<string, unknown> {
    const bossId = String(params.p_boss_id ?? "");
    const steamId = String(params.p_steam_id ?? "");
    const rows = this.rowsOf("demo_challenge_slots");
    const mine = () => rows.filter((r) => r.steam_id === steamId).length;
    if (rows.some((r) => r.steam_id === steamId && r.boss_id === bossId)) return { status: "already", used: mine(), slot_limit: 15 };
    if (!this.rowsOf("bosses").some((b) => b.id === bossId && b.is_published === true)) return { status: "not_found", used: mine(), slot_limit: 15 };
    if (mine() >= 15) return { status: "limit", used: mine(), slot_limit: 15 };
    rows.push({ steam_id: steamId, boss_id: bossId, claimed_at: new Date(this.now()).toISOString() });
    this.tables.set("demo_challenge_slots", rows);
    return { status: "claimed", used: mine(), slot_limit: 15 };
  }

  // 本物の DB の issue_boss_battle_ticket() と同じ（2026-10-23）: 公開中のボスだけ。1人×1ボスで1時間に60枚・1人で24時間に600枚まで。
  // 期限は30日。モード・版は DB（bosses）の値。
  private issueTicket(params: Record<string, unknown>): Record<string, unknown> {
    const bossId = String(params.p_boss_id ?? "");
    const steamId = String(params.p_steam_id ?? "");
    const boss = this.rowsOf("bosses").find((b) => b.id === bossId && b.is_published === true);
    if (!boss) return { status: "not_found", ticket_id: null, expires_at: null };
    const now = this.now();
    const tickets = this.rowsOf("boss_battle_tickets");
    const issuedMs = (t: Record<string, unknown>) => Date.parse(String(t.issued_at));
    if (tickets.filter((t) => t.challenger_steam_id === steamId && t.boss_id === bossId && issuedMs(t) > now - 3600_000).length >= 60) {
      return { status: "rate_limited", ticket_id: null, expires_at: null };
    }
    if (tickets.filter((t) => t.challenger_steam_id === steamId && issuedMs(t) > now - 24 * 3600_000).length >= 600) {
      return { status: "daily_limit", ticket_id: null, expires_at: null };
    }
    const draftFields = ((boss.payload ?? {}) as Record<string, unknown>).draft_fields as Record<string, unknown> | undefined;
    const ticket = {
      id: crypto.randomUUID(),
      boss_id: bossId,
      challenger_steam_id: steamId,
      creator_mode: typeof draftFields?.creator_mode === "string" ? draftFields.creator_mode : "simple",
      boss_revision: boss.revision ?? 1,
      issued_at: new Date(now).toISOString(),
      expires_at: new Date(now + 30 * 24 * 3600_000).toISOString(),
      used_at: null,
      outcome: null,
      result_id: null,
    };
    this.tables.set("boss_battle_tickets", [...tickets, ticket]);
    return { status: "issued", ticket_id: ticket.id, expires_at: ticket.expires_at };
  }

  // 本物の DB の submit_boss_battle_result() と同じ（2026-10-23）。
  private submitResult(params: Record<string, unknown>): Record<string, unknown> {
    const reject = (status: string) => ({
      status,
      by_owner: null,
      hard_awarded: null,
      clear_count: null,
      first_clear_challengers: null,
      first_clear_clearers: null,
    });
    const ticketId = String(params.p_ticket_id ?? "");
    const bossId = String(params.p_boss_id ?? "");
    const steamId = String(params.p_steam_id ?? "");
    const resultId = params.p_result_id === null || params.p_result_id === undefined ? null : String(params.p_result_id);
    const outcome = String(params.p_outcome ?? "");
    if ((outcome !== "clear" && outcome !== "loss") || resultId === null) return reject("invalid");
    const tickets = this.rowsOf("boss_battle_tickets");
    const ticket = tickets.find((t) => t.id === ticketId);
    if (!ticket || ticket.challenger_steam_id !== steamId || ticket.boss_id !== bossId) return reject("invalid");
    const state = (status: string) => {
      const rec = this.rowsOf("boss_challenge_records").find((r) => r.boss_id === bossId && r.challenger_steam_id === steamId);
      return {
        status,
        by_owner: rec ? rec.by_owner === true : null,
        hard_awarded: rec ? rec.hard_awarded_at !== null && rec.hard_awarded_at !== undefined : null,
        clear_count: rec ? Number(rec.clear_count ?? 0) : null,
        first_clear_challengers: rec?.first_clear_challengers ?? null,
        first_clear_clearers: rec?.first_clear_clearers ?? null,
      };
    };
    if (ticket.used_at) {
      return ticket.result_id === resultId && ticket.outcome === outcome ? state("duplicate") : reject("used");
    }
    const now = this.now();
    if (Date.parse(String(ticket.expires_at)) < now) return reject("expired");
    if (tickets.some((t) => t.result_id === resultId)) return reject("used");
    ticket.used_at = new Date(now).toISOString();
    ticket.outcome = outcome;
    ticket.result_id = resultId;

    const rows = this.rowsOf("boss_challenge_records");
    let rec = rows.find((r) => r.boss_id === bossId && r.challenger_steam_id === steamId);
    const iso = new Date(now).toISOString();
    if (!rec) {
      rec = {
        id: `fake-id-${this.nextId++}`,
        boss_id: bossId,
        challenger_steam_id: steamId,
        challenge_count: 0,
        clear_count: 0,
        result_count: 0,
        result_clear_count: 0,
        first_clear_challengers: null,
        first_clear_clearers: null,
        hard_awarded_at: null,
        created_at: iso,
      };
      rows.push(rec);
      this.tables.set("boss_challenge_records", rows);
    }
    rec.by_owner = this.rowsOf("bosses").some((b) => b.id === bossId && b.owner_steam_id === steamId);
    if (outcome === "clear") {
      // 初めて結果でクリアした時だけ、その時の「ほかの人」（作者・本人を除く、結果のある人）の数を残す
      if (Number(rec.result_clear_count ?? 0) === 0 && (rec.first_clear_challengers ?? null) === null) {
        const others = this.hardDefeatStats(bossId, steamId);
        rec.first_clear_challengers = others.challengers;
        rec.first_clear_clearers = others.clearers;
      }
      rec.clear_count = Number(rec.clear_count ?? 0) + 1;
      rec.result_clear_count = Number(rec.result_clear_count ?? 0) + 1;
      if (!rec.first_cleared_at) rec.first_cleared_at = iso;
      rec.last_cleared_at = iso;
    }
    rec.result_count = Number(rec.result_count ?? 0) + 1;
    rec.updated_at = iso;
    this.awardHardDefeats(bossId, iso);
    return state("counted");
  }

  // 本物の DB の boss_hard_defeat_stats() と同じ: 作者本人（by_owner）を除き、決着した結果がある人の数・そのうち勝った人の数・結果の合計。
  hardDefeatStats(bossId: string, excludeSteamId: string | null): { results: number; challengers: number; clearers: number } {
    const rows = this.rowsOf("boss_challenge_records").filter((r) =>
      r.boss_id === bossId && r.by_owner !== true && (excludeSteamId === null || r.challenger_steam_id !== excludeSteamId)
    );
    const withResults = rows.filter((r) => Number(r.result_count ?? 0) > 0);
    return {
      results: rows.reduce((sum, r) => sum + Number(r.result_count ?? 0), 0),
      challengers: withResults.length,
      clearers: withResults.filter((r) => Number(r.result_clear_count ?? 0) > 0).length,
    };
  }

  // 本物の DB の award_hard_defeats() と同じ: ボスが条件（結果50回・挑戦者10人・5%以下）を満たしたら、初回クリアの時に5%以下だった人
  // （ほかに0人だった最初のクリアは保留していて、ここで認定）を認定する。一度ついた認定は消さない。
  private awardHardDefeats(bossId: string, now: string): void {
    const s = this.hardDefeatStats(bossId, null);
    if (!(s.results >= 50 && s.challengers >= 10 && s.clearers * 20 <= s.challengers)) return;
    for (const r of this.rowsOf("boss_challenge_records")) {
      if (r.boss_id !== bossId || r.by_owner === true || Number(r.result_clear_count ?? 0) <= 0) continue;
      if (r.hard_awarded_at || r.first_clear_challengers === null || r.first_clear_challengers === undefined) continue;
      if (Number(r.first_clear_challengers) === 0 || Number(r.first_clear_clearers) * 20 <= Number(r.first_clear_challengers)) {
        r.hard_awarded_at = now;
      }
    }
  }
}
