// 2026-10 — 挑戦画面のボスカード(サムネイル・挑戦者数・クリア率)のために、一覧の各行へ足す項目。
//
// - appearance_id: payload.draft_fields.appearance_id(外見ID)だけを取り出す。payloadそのものは
//   一覧へ返さない(「summary rows never include the full payload field」の契約はそのまま)。
// - unique_challengers / unique_clearers: boss_challenge_recordsの行数(=ユニーク挑戦者数、
//   (boss_id, challenger_steam_id)がUNIQUE)と、そのうちclear_count > 0の行数(=一度でもクリアした人数)。
//   人気/高難度のランキングと同じ数え方。画面のクリア率は unique_clearers / unique_challengers。
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
  clear_count: number;
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

// 記録の行(boss_id, clear_count)から、ボスごとの挑戦者数・クリア者数を数える。
export function countChallengeStats(records: { boss_id: string; clear_count: unknown }[]): Map<string, ChallengeStats> {
  const stats = new Map<string, ChallengeStats>();
  for (const record of records) {
    const current = stats.get(record.boss_id) ?? { uniqueChallengers: 0, uniqueClearers: 0 };
    current.uniqueChallengers += 1;
    if (Number(record.clear_count) > 0) current.uniqueClearers += 1;
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
      `boss_id=in.(${ids.join(",")})&select=id,boss_id,clear_count`,
    );
    if (!lookup.ok) return { ok: false, errorMessage: lookup.errorMessage ?? "" };
    records.push(...lookup.rows);
  }
  const counted = countChallengeStats(records);
  const stats = new Map<string, ChallengeStats>();
  for (const id of bossIds) stats.set(id, counted.get(id) ?? { uniqueChallengers: 0, uniqueClearers: 0 });
  return { ok: true, stats };
}
