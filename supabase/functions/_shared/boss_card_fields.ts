// 2026-10 — 挑戦画面のボスカード(サムネイル・挑戦者数・クリア率)のために、一覧の各行へ足す項目。
//
// - appearance_id: payload.draft_fields.appearance_id(外見ID)だけを取り出す。payloadそのものは
//   一覧へ返さない(「summary rows never include the full payload field」の契約はそのまま)。
// - unique_challengers / unique_clearers: 作者本人を除き、決着した戦闘の結果がある人の数（result_count > 0 の行数。
//   (boss_id, challenger_steam_id)がUNIQUEなので1人1行）と、そのうち勝ちの結果がある人の数（result_clear_count > 0）。
//   2026-10-23 から、一覧・検索・ランダム・未挑戦・人気・高難度・難関ボス討伐の認定で同じ数え方（戦闘チケットで受け付けた結果
//   だけ。挑戦を始めただけ・旧版のクリアの記録は数えない）。画面のクリア率は unique_clearers / unique_challengers
//   （挑戦者0人は未集計で、画面は「—」）。
//
// 一覧(list-bosses/list-unchallenged-bosses)は返すページのボスの分だけ記録を読む
// (boss_id=in.(...)で絞り、select_all_pages.tsで全件をページングする)。

import { SupabaseRestClient } from "./supabase_rest_client.ts";
import { selectAllPages } from "./select_all_pages.ts";

export interface ChallengeStats {
  uniqueChallengers: number;
  uniqueClearers: number;
}

interface StatsRecordRow {
  id: string;
  boss_id: string;
  result_clear_count: number;
}

// 1回の問い合わせに入れるboss_idの数(URLが長くなりすぎないように。一覧の1ページは最大50件)。
const IDS_PER_QUERY = 50;

export function extractAppearanceId(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return "";
  const draftFields = (payload as Record<string, unknown>).draft_fields;
  if (typeof draftFields !== "object" || draftFields === null) return "";
  const appearanceId = (draftFields as Record<string, unknown>).appearance_id;
  return typeof appearanceId === "string" ? appearanceId : "";
}

// 決着した結果がある記録の行(boss_id, result_clear_count)から、ボスごとの挑戦者数・クリア者数を数える。
export function countChallengeStats(records: { boss_id: string; result_clear_count: unknown }[]): Map<string, ChallengeStats> {
  const stats = new Map<string, ChallengeStats>();
  for (const record of records) {
    const current = stats.get(record.boss_id) ?? { uniqueChallengers: 0, uniqueClearers: 0 };
    current.uniqueChallengers += 1;
    if (Number(record.result_clear_count) > 0) current.uniqueClearers += 1;
    stats.set(record.boss_id, current);
  }
  return stats;
}

// 指定したボスだけの挑戦者数・クリア者数。記録が無いボスは0人。どこかで読み取りに失敗したら
// 途中までの数を返さずに失敗を返す(0人と誤って見せない)。
export async function loadChallengeStats(
  db: SupabaseRestClient,
  bossIds: string[],
): Promise<{ ok: true; stats: Map<string, ChallengeStats> } | { ok: false; errorMessage: string }> {
  const records: StatsRecordRow[] = [];
  for (let start = 0; start < bossIds.length; start += IDS_PER_QUERY) {
    const ids = bossIds.slice(start, start + IDS_PER_QUERY).map((id) => encodeURIComponent(id));
    const lookup = await selectAllPages<StatsRecordRow>(
      db,
      "boss_challenge_records",
      // 作者本人の挑戦（by_owner、DB のトリガーが決める）は数えない（2026-10-22）。決着した結果がある人だけ（2026-10-23）
      `boss_id=in.(${ids.join(",")})&by_owner=is.false&result_count=gt.0&select=id,boss_id,result_clear_count`,
    );
    if (!lookup.ok) return { ok: false, errorMessage: lookup.errorMessage ?? "" };
    records.push(...lookup.rows);
  }
  const counted = countChallengeStats(records);
  const stats = new Map<string, ChallengeStats>();
  for (const id of bossIds) stats.set(id, counted.get(id) ?? { uniqueChallengers: 0, uniqueClearers: 0 });
  return { ok: true, stats };
}
