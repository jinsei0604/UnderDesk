// Phase 5 — オンライン版「未挑戦」— クリアをSteamユーザー単位で記録する。
//
// record-challenge-attemptと同じ信頼境界・同じatomic increment方針
// (rpc("record_boss_challenge_clear", ...)、boss_challenge_records
// migration参照)。
//
// §6(ユーザー確定仕様): attempt行が何らかの理由で存在しなくても、
// clear記録だけで安全に行を作成できる——ただしその場合もchallenge_countは
// 勝手に+1しない。既存ローカルのRBMLocalStageRepository.record_challenge_clear()
// が「clear_countだけを独立して加算し、challenge_countには一切触れない」
// という既存の防御的仕様を踏襲したもの(DB関数record_boss_challenge_clear()
// 側で保証、Godot側は既存のまま無改修)。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

export interface RecordChallengeClearRequestBody {
  ticket?: unknown;
  boss_id?: unknown;
}

export interface RecordChallengeClearResponseBody {
  ok: boolean;
  clear_count?: number;
  error_kind?: string;
  message?: string;
}

const UUID_PATTERN = /^[0-9a-fA-F-]{36}$/;

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: RecordChallengeClearResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface BossExistsRow {
  id: string;
}

interface ChallengeRecordRow {
  clear_count: number;
}

export async function handleRecordChallengeClear(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: RecordChallengeClearRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }

  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  if (typeof body.boss_id !== "string" || !UUID_PATTERN.test(body.boss_id)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'boss_id' must be a valid boss id" }, 400);
  }
  const bossId = body.boss_id;

  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const challengerSteamId = verification.steamId as string;

  const bossLookup = await db.select<BossExistsRow>(
    "bosses",
    `id=eq.${bossId}&is_published=eq.true&select=id`,
  );
  if (!bossLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: bossLookup.errorMessage ?? "" }, 502);
  }
  if (bossLookup.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "not_found", message: "Boss not found or not published" }, 404);
  }

  const recorded = await db.rpc<ChallengeRecordRow>("record_boss_challenge_clear", {
    p_boss_id: bossId,
    p_steam_id: challengerSteamId,
  });
  if (!recorded.ok || recorded.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: recorded.errorMessage ?? "" }, 502);
  }

  return jsonResponse({ ok: true, clear_count: recorded.rows[0].clear_count }, 200);
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
    return await handleRecordChallengeClear(req, verifier, db, expectedAppId);
  });
}
