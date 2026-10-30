// 2026-10-23 — 戦闘チケットを1枚出す（「もう一度挑戦」などで次の戦闘を始める時。最初の戦闘のチケットは
// record-challenge-attempt が、結果を送った後の次のチケットは submit-battle-result が同じ応答で返すので、
// これを呼ぶのはそれが届かなかった時だけ）。
//
// チケットは Steam で確かめた本人・ボス・そのボスのモードと版（DB の値）に結びつく（_shared/battle_tickets.ts）。
// リクエストの steam_id・モードは使わない。公開中のボスだけ。発行の上限（1人×1ボスで1時間に60枚・1人で24時間に600枚）を
// 超えたら 429（ゲームは戦闘を止めない。その戦闘の結果が数えられないだけ）。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { claimDemoChallengeSlot, DEMO_CHALLENGE_LIMIT_ERROR, demoBossRejection, DEMO_EDITION } from "../_shared/edition.ts";
import { isUuid, issueBattleTicket } from "../_shared/battle_tickets.ts";

export interface IssueBattleTicketRequestBody {
  ticket?: unknown;
  boss_id?: unknown;
}

export interface IssueBattleTicketResponseBody {
  ok: boolean;
  battle_ticket?: string;
  expires_at?: string;
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: IssueBattleTicketResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleIssueBattleTicket(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: IssueBattleTicketRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }
  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  if (!isUuid(body.boss_id)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'boss_id' must be a valid boss id" }, 400);
  }
  const bossId = body.boss_id;

  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const steamId = verification.steamId as string;
  if (!/^[0-9]+$/.test(steamId)) {
    return jsonResponse({ ok: false, error_kind: "invalid_ticket", message: "Steam returned an unexpected id" }, 401);
  }
  // 体験版のチケットで、体験版の範囲外のボスは記録しない(2026-10-28、_shared/edition.ts)。
  const demoRejected = await demoBossRejection(db, bossId, verification.edition);
  if (demoRejected !== null) {
    return jsonResponse({ ok: false, error_kind: demoRejected, message: "This boss is not available in the trial version" }, demoRejected === "db_error" ? 502 : 403);
  }

  // 2026-10-29 体験版: 異なるオンラインボスへの挑戦は累計15体まで。挑戦済みのボスはそのまま出す（枠を使わない）。
  // 15体に達していて新しいボスなら断る（record-challenge-attempt を通さずにここを直接呼んでも16体目は通らない）。
  if (verification.edition === DEMO_EDITION) {
    const slot = await claimDemoChallengeSlot(db, bossId, steamId);
    if (!slot.ok) {
      console.error("issue-battle-ticket: demo slot error", slot.errorMessage);
      return jsonResponse({ ok: false, error_kind: "db_error", message: "The server could not check the trial challenge limit" }, 502);
    }
    if (slot.status === "limit") {
      return jsonResponse({ ok: false, error_kind: DEMO_CHALLENGE_LIMIT_ERROR, message: "The trial version can challenge up to 15 different online bosses" }, 403);
    }
    if (slot.status === "not_found") {
      return jsonResponse({ ok: false, error_kind: "not_found", message: "Boss not found or not published" }, 404);
    }
  }

  const issued = await issueBattleTicket(db, bossId, steamId);
  if (!issued.ok) {
    console.error("issue-battle-ticket: db error", issued.errorMessage);
    return jsonResponse({ ok: false, error_kind: "db_error", message: "The server could not issue a battle ticket" }, 502);
  }
  if (issued.status === "not_found") {
    return jsonResponse({ ok: false, error_kind: "not_found", message: "Boss not found or not published" }, 404);
  }
  if (issued.status !== "issued" || issued.ticketId === null || issued.expiresAt === null) {
    return jsonResponse({ ok: false, error_kind: issued.status, message: "Too many battles were started; try again later" }, 429);
  }
  return jsonResponse({ ok: true, battle_ticket: issued.ticketId, expires_at: issued.expiresAt }, 200);
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
    return await handleIssueBattleTicket(req, verifier, db, expectedAppId);
  });
}
