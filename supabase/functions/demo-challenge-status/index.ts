// 2026-10-29 — 体験版のオンライン挑戦の使用状況（異なるオンラインボスへの挑戦は累計15体まで）。読むだけ。
//
// 体験版のオンライン一覧の「オンライン挑戦 ○ / 15体」と、挑戦済みのボス（15体に達した後も挑戦できる）の見分けに使う。
// 本人は Steam のチケットで確かめた SteamID だけ（リクエストの steam_id は使わない）。版も Steam のチケットのアプリで決める
// （ゲームが送る edition は使わない）。製品版のチケットなら limited: false だけを返す（製品版には制限が無い）。
// 枠を使う（数える）のは record-challenge-attempt・issue-battle-ticket だけ（DB の claim_demo_challenge_slot()）。
// SteamID は返さない。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { DEMO_EDITION, demoChallengeStatus } from "../_shared/edition.ts";

export interface DemoChallengeStatusRequestBody {
  ticket?: unknown;
}

export interface DemoChallengeStatusResponseBody {
  ok: boolean;
  limited?: boolean;
  used?: number;
  limit?: number;
  challenged_boss_ids?: string[];
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: DemoChallengeStatusResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleDemoChallengeStatus(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }
  let body: DemoChallengeStatusRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }
  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  if (verification.edition !== DEMO_EDITION) {
    return jsonResponse({ ok: true, limited: false }, 200);
  }
  const steamId = verification.steamId as string;
  if (!/^[0-9]+$/.test(steamId)) {
    return jsonResponse({ ok: false, error_kind: "invalid_ticket", message: "Steam returned an unexpected id" }, 401);
  }
  const status = await demoChallengeStatus(db, steamId);
  if (!status.ok) {
    console.error("demo-challenge-status: db error", status.errorMessage);
    return jsonResponse({ ok: false, error_kind: "db_error", message: "The server could not read the trial challenge count" }, 502);
  }
  return jsonResponse({ ok: true, limited: true, used: status.used, limit: status.limit, challenged_boss_ids: status.bossIds }, 200);
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
    return await handleDemoChallengeStatus(req, verifier, db, expectedAppId);
  });
}
