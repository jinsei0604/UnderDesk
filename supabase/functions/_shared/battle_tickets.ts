// 2026-10-23 — 戦闘チケット（1戦闘1枚・1回限り）の共通部分。DB の issue_boss_battle_ticket()・submit_boss_battle_result()
// （migration 20261023000000_hard_defeat_award.sql）を呼ぶ関数（record-challenge-attempt・issue-battle-ticket・
// submit-battle-result）が使う。
//
// チケットは Steam で確かめた本人・ボス・そのボスのモードと版（DB の値）に結びつき、決着した結果（勝ち・負け）を1回だけ受け付ける。
// 同じ結果の送り直し（同じチケット・同じ結果の id・同じ勝敗）は数えずに、今の状態を返す（通信が切れた結果を安全に送り直せる）。
// 限界: チケットは「サーバーが戦闘の開始を知っている」「1つの結果を1回だけ数える」ことを保証するが、勝ったこと自体は確かめない
// （戦闘はゲームの中で決まる）。勝ちを確かめるには、戦闘の記録をサーバーで再計算する仕組みが要る（今後の改善）。

import { SupabaseRestClient } from "./supabase_rest_client.ts";

export const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

// 発行の結果: issued（ticketId・expiresAt あり）・not_found（公開中でない）・rate_limited（1人×1ボスで1時間に60枚）・
// daily_limit（1人で24時間に600枚）。DB に届かなければ ok: false。
export type IssueStatus = "issued" | "not_found" | "rate_limited" | "daily_limit";

export type IssueResult =
  | { ok: true; status: IssueStatus; ticketId: string | null; expiresAt: string | null }
  | { ok: false; errorMessage: string };

interface IssueRow {
  status: string;
  ticket_id: string | null;
  expires_at: string | null;
}

export async function issueBattleTicket(db: SupabaseRestClient, bossId: string, steamId: string): Promise<IssueResult> {
  const issued = await db.rpc<IssueRow>("issue_boss_battle_ticket", { p_boss_id: bossId, p_steam_id: steamId });
  if (!issued.ok || issued.rows.length === 0) return { ok: false, errorMessage: issued.errorMessage ?? "" };
  const row = issued.rows[0];
  const status = String(row.status) as IssueStatus;
  if (!["issued", "not_found", "rate_limited", "daily_limit"].includes(status)) {
    return { ok: false, errorMessage: `unexpected ticket status '${row.status}'` };
  }
  return { ok: true, status, ticketId: row.ticket_id ?? null, expiresAt: row.expires_at ?? null };
}

// 結果の受け付けの答え: counted（今回数えた）・duplicate（同じ結果は数え済み）・invalid（チケットが無い・本人やボスが違う・
// 値が違う）・used（チケットか結果の id が別の結果で使用済み）・expired（チケットの期限切れ）。
export type SubmitStatus = "counted" | "duplicate" | "invalid" | "used" | "expired";

export interface SubmittedResult {
  status: SubmitStatus;
  byOwner: boolean | null;
  hardAwarded: boolean | null;
  clearCount: number | null;
  firstClearChallengers: number | null;
  firstClearClearers: number | null;
}

interface SubmitRow {
  status: string;
  by_owner: boolean | null;
  hard_awarded: boolean | null;
  clear_count: number | null;
  first_clear_challengers: number | null;
  first_clear_clearers: number | null;
}

export async function submitBattleResult(
  db: SupabaseRestClient,
  params: { ticketId: string; bossId: string; steamId: string; resultId: string; outcome: string },
): Promise<{ ok: true; result: SubmittedResult } | { ok: false; errorMessage: string }> {
  const submitted = await db.rpc<SubmitRow>("submit_boss_battle_result", {
    p_ticket_id: params.ticketId,
    p_boss_id: params.bossId,
    p_steam_id: params.steamId,
    p_result_id: params.resultId,
    p_outcome: params.outcome,
  });
  if (!submitted.ok || submitted.rows.length === 0) return { ok: false, errorMessage: submitted.errorMessage ?? "" };
  const row = submitted.rows[0];
  const status = String(row.status) as SubmitStatus;
  if (!["counted", "duplicate", "invalid", "used", "expired"].includes(status)) {
    return { ok: false, errorMessage: `unexpected result status '${row.status}'` };
  }
  return {
    ok: true,
    result: {
      status,
      byOwner: typeof row.by_owner === "boolean" ? row.by_owner : null,
      hardAwarded: typeof row.hard_awarded === "boolean" ? row.hard_awarded : null,
      clearCount: typeof row.clear_count === "number" ? row.clear_count : null,
      firstClearChallengers: typeof row.first_clear_challengers === "number" ? row.first_clear_challengers : null,
      firstClearClearers: typeof row.first_clear_clearers === "number" ? row.first_clear_clearers : null,
    },
  };
}

// 初めてクリアした時の「ほかの人」のクリア率（挑戦者0人の時・まだ結果でクリアしていない時は null = 未集計）。
export function firstClearRate(challengers: number | null, clearers: number | null): number | null {
  if (challengers === null || clearers === null || challengers <= 0) return null;
  return clearers / challengers;
}
