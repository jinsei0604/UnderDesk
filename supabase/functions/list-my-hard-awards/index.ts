// 2026-10-23 — 自分（Steam で確かめた本人）が難関ボス討伐に認定されたボスの id の一覧。
// 認定は DB が決める（戦闘チケットで結果を受け付ける submit_boss_battle_result の中の award_hard_defeats。初めてクリアした時に条件に
// 届いていなかったボスも、後で条件を満たした時にさかのぼって認定される）。ゲームはこの一覧で手元・Steam Cloud の
// 討伐記録の「難関」を足す（一度足したら消さない）。
//
// 返すのはボスの id だけ（SteamID・回数・ほかの人の記録は返さない）。読むのは本人の行だけで、
// challenger_steam_id の索引で1回（とページ送り）。リクエストの steam_id は使わない。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { selectAllPages } from "../_shared/select_all_pages.ts";

export interface ListMyHardAwardsRequestBody {
  ticket?: unknown;
}

export interface ListMyHardAwardsResponseBody {
  ok: boolean;
  boss_ids?: string[];
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: ListMyHardAwardsResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface AwardRow {
  id: string;
  boss_id: string;
}

export async function handleListMyHardAwards(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: ListMyHardAwardsRequestBody;
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
  const steamId = verification.steamId as string;
  if (!/^[0-9]+$/.test(steamId)) {
    return jsonResponse({ ok: false, error_kind: "invalid_ticket", message: "Steam returned an unexpected id" }, 401);
  }

  const awards = await selectAllPages<AwardRow>(
    db,
    "boss_challenge_records",
    `challenger_steam_id=eq.${steamId}&by_owner=is.false&hard_awarded_at=not.is.null&select=id,boss_id`,
  );
  if (!awards.ok) {
    console.error("list-my-hard-awards: db error", awards.errorMessage ?? "");
    return jsonResponse({ ok: false, error_kind: "db_error", message: "The server could not read the awards" }, 502);
  }
  return jsonResponse({ ok: true, boss_ids: awards.rows.map((row) => String(row.boss_id)) }, 200);
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
    return await handleListMyHardAwards(req, verifier, db, expectedAppId);
  });
}
