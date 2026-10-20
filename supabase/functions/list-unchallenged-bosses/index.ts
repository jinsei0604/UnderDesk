// Phase 5 — オンライン版「未挑戦」— 現在のSteamユーザーが一度も挑戦して
// いない公開ボスだけを返す。
//
// list-bossesと違い匿名GETにはできない——「誰にとっての未挑戦か」を
// サーバー側で確定させる必要があるため、publish-boss/unpublish-bossと
// 同じSteam ticket検証付きのPOSTにする(§重要「SteamIDをクライアントから
// 信用しない」、ここでも同様)。
//
// レスポンス形式はlist-bossesの一覧の行と完全に一致させる
// (id/boss_name/author_name/published_at/revision/creator_mode、2026-10からは
// 挑戦画面のカード用にappearance_id/unique_challengers/unique_clearersも)——
// challenger_steam_id・挑戦記録そのもの・payload全文は一切含めない。
//
// Supabaseの無料枠への負荷(2026-10-18): 以前は公開中の全ボスを payload ごと読んでから絞っていた
// (1,000件で約2.6MB)。今は公開ボスを、DBで並べた順(公開日時の新しい順)に SCAN_PAGE 件ずつ、カードに
// 要る列だけ読み(_shared/public_boss_query.ts。modeもDBで絞る)、自分が挑戦済みのボスを除いて limit 件
// 集まったところで読むのをやめる。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, RestResult, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { selectAllPages } from "../_shared/select_all_pages.ts";
import { loadChallengeStats } from "../_shared/boss_card_fields.ts";
import {
  afterPositionCondition,
  BossSummaryDbRow,
  dbError,
  modeCondition,
  publicBossQuery,
  toPublicRow,
} from "../_shared/public_boss_query.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const VALID_MODES = new Set(["simple", "advanced"]);
// 公開ボスを1回の問い合わせで読む件数(挑戦済みを除いた後に limit 件集まるまで、この単位で続きを読む)。
export const SCAN_PAGE = 100;

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
  appearance_id: string;
}

// 一覧の1行: 概要+カードに出す挑戦者数・クリア者数(返すボスの分だけ数える、全員の記録)。
export interface UnchallengedBossRow extends BossSummaryRow {
  unique_challengers: number;
  unique_clearers: number;
}

export interface ListUnchallengedBossesRequestBody {
  ticket?: unknown;
  mode?: unknown;
  limit?: unknown;
}

export interface ListUnchallengedBossesResponseBody {
  ok: boolean;
  bosses?: UnchallengedBossRow[];
  error_kind?: string;
  message?: string;
}

interface ChallengeRecordLookupRow {
  id: string;
  boss_id: string;
  challenge_count: number;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: ListUnchallengedBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleListUnchallengedBosses(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: ListUnchallengedBossesRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }

  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }

  const requestedLimit = typeof body.limit === "number" ? body.limit : DEFAULT_LIMIT;
  const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
    ? Math.min(requestedLimit, MAX_LIMIT)
    : DEFAULT_LIMIT;

  const modeFilter = typeof body.mode === "string" && VALID_MODES.has(body.mode) ? body.mode : null;

  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const challengerSteamId = verification.steamId as string;

  // このSteamユーザー自身の挑戦記録だけを取得する(challenger_steam_id=eq.
  // <検証済み自分のSteamID>で厳密に絞り込む——他のSteamユーザーの挑戦履歴は
  // 一切参照しない)。challenge_count>0の絞り込みは、PostgRESTのgt演算子を
  // 使わずここ(Edge Function側)で行う——list-bossesのcreator_mode抽出と
  // 同じ理由(テスト用FakeSupabaseRestClientが素朴にサポートするeq./
  // order/limit/selectの範囲だけでこの関数を実装し切るため)。
  // 1人の挑戦記録が1回の応答の上限を超えても欠けないよう、全件をページングして読む
  // (2026-10、_shared/select_all_pages.ts)。
  const challengedLookup = await selectAllPages<ChallengeRecordLookupRow>(
    db,
    "boss_challenge_records",
    `challenger_steam_id=eq.${challengerSteamId}&select=id,boss_id,challenge_count`,
  );
  if (!challengedLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: challengedLookup.errorMessage ?? "" }, 502);
  }
  const challengedBossIds = new Set(
    challengedLookup.rows.filter((row) => Number(row.challenge_count) > 0).map((row) => row.boss_id),
  );

  // 全件対象(2026-10): 古い未挑戦のボスも取りこぼさない。公開ボスを公開日時の新しい順(同じ日時ならid順)に
  // DBで並べ、SCAN_PAGE件ずつ読んで、自分が挑戦済みのものを除き、limit件集まるか最後まで読んだら終わる
  // (modeはDBで絞る。payloadは読まない)。
  const conditions: string[] = modeFilter !== null ? [modeCondition(modeFilter)] : [];
  const page: BossSummaryDbRow[] = [];
  let after: BossSummaryDbRow | null = null;
  while (page.length < limit) {
    const scan: string[] = after === null ? conditions : [...conditions, afterPositionCondition(String(after.published_at), String(after.id))];
    const found: RestResult<BossSummaryDbRow> = await db.select<BossSummaryDbRow>("bosses", publicBossQuery(scan, `order=published_at.desc,id.asc&limit=${SCAN_PAGE}`));
    if (!found.ok) return dbError(found);
    for (const row of found.rows) {
      if (challengedBossIds.has(String(row.id))) continue;
      page.push(row);
      if (page.length >= limit) break;
    }
    if (found.rows.length < SCAN_PAGE) break; // 最後まで読んだ
    after = found.rows[found.rows.length - 1];
  }

  const statsLookup = await loadChallengeStats(db, page.map((row) => String(row.id)));
  if (!statsLookup.ok) return dbError(statsLookup);
  const bosses: UnchallengedBossRow[] = page.map((row) => toPublicRow(row, statsLookup.stats.get(String(row.id))!));

  return jsonResponse({ ok: true, bosses }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const verifier = new SteamTicketVerifier({
      client: new RealSteamWebApiClient(),
      publisherWebApiKey: Deno.env.get("STEAM_PUBLISHER_WEB_API_KEY"),
    });
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const expectedAppId = Number(Deno.env.get("STEAM_APP_ID") ?? "0");
    return await handleListUnchallengedBosses(req, verifier, db, expectedAppId);
  });
}
