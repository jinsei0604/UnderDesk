// Phase 6 — Challenge Hub「高難度」— 補正クリア率が低いボスを返す。
//
// 対象条件(ユーザー確定仕様): ユニーク挑戦者数 >= 5 のbossのみ
// ランキング対象にする(1人挑戦・0人クリアのようなサンプル数が
// 少なすぎるケースが即座に最難関扱いになるのを防ぐ、既存ローカル版
// RBMChallengeUiKit.corrected_clear_rate()の補正式と同じ思想)。
//
// ユニーククリア者数 = boss_challenge_recordsのうちclear_count > 0の行数
// (「総クリア回数」ではなく「一度でもクリアしたユニーク人数」。
// 再挑戦後の勝利でclear_countがchallenge_countを超えることがあっても、
// 0より大きいかしか見ないので順位には影響しない)。
//
// 補正クリア率 = (unique_clearers + 1) / (unique_challengers + 2)。
// この値が低いほど高難度——値そのものはランキングの並び替え専用の内部値で、
// クライアントへは一切返さない。画面に出すクリア率は、レスポンスの
// unique_clearers / unique_challengers(通常の割合)からクライアントが計算する。
//
// 順位: 1. 補正クリア率 ASC 2. 同率ならユニーク挑戦者数 DESC
//       3. さらに同率ならpublished_at DESC
//       (それでも完全に同じなら、並びを毎回同じにするためだけにid ASC)
//
// 対象は公開中の全ボス(2026-10、新着50件だけを対象にしていた問題を修正)。
// 公開ボス・挑戦記録とも_shared/select_all_pages.tsで全件をページングして
// 読み、全体で順位を決めてから上位limit件(既定20)を返す。
//
// list-popular-bossesと同じ理由で認証不要・service_role経由の集計。
// レスポンスには一覧の概要行と集計値unique_challengers/unique_clearersだけを
// 載せ、challenger_steam_idなど個人に結びつく値・記録の行そのものは含めない。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { selectAllPages } from "../_shared/select_all_pages.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const DEFAULT_CREATOR_MODE = "simple";
const VALID_MODES = new Set(["simple", "advanced"]);
const MIN_UNIQUE_CHALLENGERS = 5;

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
}

// 高難度ランキングの1行: 一覧の概要行+表示用の集計値(クリア率の分母と分子)。
export interface HardBossRow extends BossSummaryRow {
  unique_challengers: number;
  unique_clearers: number;
}

export interface ListHardBossesResponseBody {
  ok: boolean;
  bosses?: HardBossRow[];
  error_kind?: string;
  message?: string;
}

interface BossRowWithPayload {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  payload?: Record<string, unknown>;
}

interface ChallengeRecordAggregateRow {
  id: string;
  boss_id: string;
  clear_count: number;
}

function jsonResponse(body: ListHardBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function extractCreatorMode(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return DEFAULT_CREATOR_MODE;
  const draftFields = (payload as Record<string, unknown>).draft_fields;
  if (typeof draftFields !== "object" || draftFields === null) return DEFAULT_CREATOR_MODE;
  const mode = (draftFields as Record<string, unknown>).creator_mode;
  return VALID_MODES.has(String(mode)) ? String(mode) : DEFAULT_CREATOR_MODE;
}

export async function handleListHardBosses(req: Request, db: SupabaseRestClient): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }

  const url = new URL(req.url);
  const requestedLimit = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
  const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
    ? Math.min(requestedLimit, MAX_LIMIT)
    : DEFAULT_LIMIT;

  const requestedMode = url.searchParams.get("mode");
  const modeFilter = requestedMode !== null && VALID_MODES.has(requestedMode) ? requestedMode : null;

  // 公開中の全ボス(新しい順の上限で打ち切らない)。
  const bossesLookup = await selectAllPages<BossRowWithPayload>(
    db,
    "bosses",
    "is_published=eq.true&select=id,boss_name,author_name,published_at,revision,payload",
  );
  if (!bossesLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: bossesLookup.errorMessage ?? "" }, 502);
  }

  const recordsLookup = await selectAllPages<ChallengeRecordAggregateRow>(
    db,
    "boss_challenge_records",
    "select=id,boss_id,clear_count",
  );
  if (!recordsLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: recordsLookup.errorMessage ?? "" }, 502);
  }

  // boss_id -> {uniqueChallengers, uniqueClearers}。
  const aggregates = new Map<string, { uniqueChallengers: number; uniqueClearers: number }>();
  for (const record of recordsLookup.rows) {
    const current = aggregates.get(record.boss_id) ?? { uniqueChallengers: 0, uniqueClearers: 0 };
    current.uniqueChallengers += 1;
    if (Number(record.clear_count) > 0) current.uniqueClearers += 1;
    aggregates.set(record.boss_id, current);
  }

  let bosses = bossesLookup.rows
    .map((row) => {
      const aggregate = aggregates.get(row.id) ?? { uniqueChallengers: 0, uniqueClearers: 0 };
      return {
        summary: {
          id: row.id,
          boss_name: row.boss_name,
          author_name: row.author_name,
          published_at: row.published_at,
          revision: row.revision,
          creator_mode: extractCreatorMode(row.payload),
        } as BossSummaryRow,
        uniqueChallengers: aggregate.uniqueChallengers,
        uniqueClearers: aggregate.uniqueClearers,
        correctedClearRate: (aggregate.uniqueClearers + 1) / (aggregate.uniqueChallengers + 2),
        publishedAtMs: Date.parse(row.published_at),
      };
    })
    // サンプル数が少なすぎるbossはランキング対象から除外する(未挑戦とは
    // 異なり、こちらは「一覧から除外して構わない」仕様)。
    .filter((entry) => entry.uniqueChallengers >= MIN_UNIQUE_CHALLENGERS);

  if (modeFilter !== null) {
    bosses = bosses.filter((entry) => entry.summary.creator_mode === modeFilter);
  }

  bosses.sort((a, b) => {
    if (a.correctedClearRate !== b.correctedClearRate) return a.correctedClearRate - b.correctedClearRate;
    if (b.uniqueChallengers !== a.uniqueChallengers) return b.uniqueChallengers - a.uniqueChallengers;
    if (b.publishedAtMs !== a.publishedAtMs) return b.publishedAtMs - a.publishedAtMs;
    return a.summary.id < b.summary.id ? -1 : a.summary.id > b.summary.id ? 1 : 0;
  });

  const rows: HardBossRow[] = bosses.slice(0, limit).map((entry) => ({
    ...entry.summary,
    unique_challengers: entry.uniqueChallengers,
    unique_clearers: entry.uniqueClearers,
  }));
  return jsonResponse({ ok: true, bosses: rows }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleListHardBosses(req, db);
  });
}
