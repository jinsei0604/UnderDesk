// Phase 6 — Challenge Hub「人気」— 「多くの異なるプレイヤーに遊ばれている
// ボス」を返す。
//
// 順位(ユーザー確定仕様):
//   1. ユニーク挑戦者数 DESC
//   2. 同数なら総挑戦回数 DESC
//   3. さらに同数ならpublished_at DESC
//
// boss_challenge_recordsは(boss_id, challenger_steam_id)がUNIQUEなので、
// 「そのbossに対する行数」が既にユニーク挑戦者数そのもの——1人が何十回
// 挑戦しても行は1つのまま増えないため、連続挑戦だけで人気順位を水増し
// できない。総挑戦回数は各行のchallenge_countの合計(SUM)で求める。
//
// list-bosses/list-unchallenged-bossesと同様、認証は不要(このランキング
// 自体は特定ユーザーに紐づかない集計値であり、Steam ticketで本人確認する
// 必要がない)——ただしchallenge履歴の読み取り自体はservice_role経由の
// Edge Function内でのみ行い、challenger_steam_idを含む個人データは
// レスポンスへ一切含めない(集計値だけをレスポンスへ載せる設計にすれば、
// 個人データの漏洩自体が構造的に起こり得ない——今回はその集計値すら
// レスポンスへ含めず、既存list-bossesと同じ概要行だけを順序だけ変えて返す)。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const DEFAULT_CREATOR_MODE = "simple";
const VALID_MODES = new Set(["simple", "advanced"]);

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
}

export interface ListPopularBossesResponseBody {
  ok: boolean;
  bosses?: BossSummaryRow[];
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
  boss_id: string;
  challenge_count: number;
}

function jsonResponse(body: ListPopularBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// list-bosses/list-unchallenged-bossesと同じフォールバック規約。各Edge
// Functionが自己完結するという既存の設計慣習(publish-boss等がそれぞれ
// isValidHexTicket()を個別に持つのと同じ理由)に合わせ、今回も独立させる。
function extractCreatorMode(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return DEFAULT_CREATOR_MODE;
  const draftFields = (payload as Record<string, unknown>).draft_fields;
  if (typeof draftFields !== "object" || draftFields === null) return DEFAULT_CREATOR_MODE;
  const mode = (draftFields as Record<string, unknown>).creator_mode;
  return VALID_MODES.has(String(mode)) ? String(mode) : DEFAULT_CREATOR_MODE;
}

export async function handleListPopularBosses(req: Request, db: SupabaseRestClient): Promise<Response> {
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

  // list-bossesと同じ理由でmode絞り込み前にlimitで打ち切らない。
  const bossesLookup = await db.select<BossRowWithPayload>(
    "bosses",
    `is_published=eq.true&select=id,boss_name,author_name,published_at,revision,payload&order=published_at.desc&limit=${MAX_LIMIT}`,
  );
  if (!bossesLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: bossesLookup.errorMessage ?? "" }, 502);
  }

  // 全boss_challenge_records行から集計する(challenger_steam_id自体は
  // 取得すらしない——selectで指定した列以外はそもそもレスポンスに乗らない)。
  const recordsLookup = await db.select<ChallengeRecordAggregateRow>(
    "boss_challenge_records",
    `select=boss_id,challenge_count`,
  );
  if (!recordsLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: recordsLookup.errorMessage ?? "" }, 502);
  }

  // boss_id -> {uniqueChallengers, totalChallenges}。(boss_id,
  // challenger_steam_id)がUNIQUEなので、この行数自体がユニーク挑戦者数。
  const aggregates = new Map<string, { uniqueChallengers: number; totalChallenges: number }>();
  for (const record of recordsLookup.rows) {
    const current = aggregates.get(record.boss_id) ?? { uniqueChallengers: 0, totalChallenges: 0 };
    current.uniqueChallengers += 1;
    current.totalChallenges += Number(record.challenge_count) || 0;
    aggregates.set(record.boss_id, current);
  }

  let bosses = bossesLookup.rows.map((row) => {
    const aggregate = aggregates.get(row.id) ?? { uniqueChallengers: 0, totalChallenges: 0 };
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
      totalChallenges: aggregate.totalChallenges,
      publishedAtMs: Date.parse(row.published_at),
    };
  });

  if (modeFilter !== null) {
    bosses = bosses.filter((entry) => entry.summary.creator_mode === modeFilter);
  }

  // 挑戦履歴0件のbossも除外しない(ユーザー確定仕様) -- 単に人気の低い
  // 位置(このソートの末尾側)へ自然に並ぶ。
  bosses.sort((a, b) => {
    if (b.uniqueChallengers !== a.uniqueChallengers) return b.uniqueChallengers - a.uniqueChallengers;
    if (b.totalChallenges !== a.totalChallenges) return b.totalChallenges - a.totalChallenges;
    return b.publishedAtMs - a.publishedAtMs;
  });

  const summaries = bosses.slice(0, limit).map((entry) => entry.summary);
  return jsonResponse({ ok: true, bosses: summaries }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleListPopularBosses(req, db);
  });
}
