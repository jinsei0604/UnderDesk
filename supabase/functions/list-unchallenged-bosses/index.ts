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

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { selectAllPages } from "../_shared/select_all_pages.ts";
import { extractAppearanceId, loadChallengeStats } from "../_shared/boss_card_fields.ts";

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

interface BossRowWithPayload {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  payload?: Record<string, unknown>;
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

// list-bossesのextractCreatorMode()と同じフォールバック規約
// (draft_fields/creator_modeが無い、または既知の2値以外ならsimple扱い)。
// list-bosses/index.tsとは意図的に独立させている——既存の、既にテスト済み
// のlist-bosses実装へ今回は一切触れない(各Edge Functionが自己完結する
// という既存の設計慣習、publish-boss/unpublish-boss/get-bossがそれぞれ
// isValidHexTicket()を個別に持つのと同じ理由)。
function extractCreatorMode(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return DEFAULT_CREATOR_MODE;
  const draftFields = (payload as Record<string, unknown>).draft_fields;
  if (typeof draftFields !== "object" || draftFields === null) return DEFAULT_CREATOR_MODE;
  const mode = (draftFields as Record<string, unknown>).creator_mode;
  return VALID_MODES.has(String(mode)) ? String(mode) : DEFAULT_CREATOR_MODE;
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

  // 全件対象(2026-10): 以前は新しい50件だけを取ってから未挑戦/modeで絞っていたため、
  // それより古い未挑戦のボスを取りこぼした。今は公開中の全ボスを読んでから、自分が
  // 挑戦済みのものを除き、modeで絞り、公開日時の新しい順(同じ日時ならid順)に
  // 並べて先頭limit件を返す。
  const bossesLookup = await selectAllPages<BossRowWithPayload>(
    db,
    "bosses",
    "is_published=eq.true&select=id,boss_name,author_name,published_at,revision,payload",
  );
  if (!bossesLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: bossesLookup.errorMessage ?? "" }, 502);
  }

  let entries = bossesLookup.rows
    .filter((row) => !challengedBossIds.has(row.id))
    .map((row) => ({
      summary: {
        id: row.id,
        boss_name: row.boss_name,
        author_name: row.author_name,
        published_at: row.published_at,
        revision: row.revision,
        creator_mode: extractCreatorMode(row.payload),
        appearance_id: extractAppearanceId(row.payload),
      } as BossSummaryRow,
      publishedAtMs: publishedAtMs(row.published_at),
    }));

  if (modeFilter !== null) {
    entries = entries.filter((entry) => entry.summary.creator_mode === modeFilter);
  }
  entries.sort((a, b) => {
    if (a.publishedAtMs !== b.publishedAtMs) return b.publishedAtMs - a.publishedAtMs;
    return a.summary.id < b.summary.id ? -1 : a.summary.id > b.summary.id ? 1 : 0;
  });
  const page = entries.slice(0, limit).map((entry) => entry.summary);
  const statsLookup = await loadChallengeStats(db, page.map((summary) => summary.id));
  if (!statsLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: statsLookup.errorMessage }, 502);
  }
  const bosses: UnchallengedBossRow[] = page.map((summary) => {
    const stats = statsLookup.stats.get(summary.id)!;
    return { ...summary, unique_challengers: stats.uniqueChallengers, unique_clearers: stats.uniqueClearers };
  });

  return jsonResponse({ ok: true, bosses }, 200);
}

function publishedAtMs(publishedAt: unknown): number {
  const ms = Date.parse(String(publishedAt ?? ""));
  return Number.isFinite(ms) ? ms : 0;
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
