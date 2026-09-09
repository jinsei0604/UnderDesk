// Phase 4E-7 — 自分の投稿だけを非公開にできるEdge Function。
// ハードDELETEではなくis_published=falseへの更新(ソフト削除)を採用——
// 元に戻せる操作を優先する。所有権の根拠は常にSteam
// AuthenticateUserTicketが返したSteamID64のみ、リクエストのboss_idを
// 誰でも指定できてもDB側のowner_steam_id一致が無ければ拒否する。
//
// Phase 4A-2待ちの間: publish-bossと同じSteamTicketVerifierを使うため、
// STEAM_PUBLISHER_WEB_API_KEY未設定の間は常にnot_configuredで拒否される。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

export interface UnpublishRequestBody {
  ticket?: unknown;
  boss_id?: unknown;
}

export interface UnpublishResponseBody {
  ok: boolean;
  error_kind?: string;
  message?: string;
}

interface BossOwnerRow {
  id: string;
  owner_steam_id: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: UnpublishResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleUnpublish(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: UnpublishRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }

  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  if (typeof body.boss_id !== "string" || body.boss_id.length === 0) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'boss_id' is required" }, 400);
  }
  const bossId = body.boss_id;

  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const ownerSteamId = verification.steamId as string;

  const existing = await db.select<BossOwnerRow>("bosses", `id=eq.${bossId}&select=id,owner_steam_id`);
  if (!existing.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: existing.errorMessage ?? "" }, 502);
  }
  if (existing.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "not_found", message: "boss_id does not exist" }, 404);
  }
  if (existing.rows[0].owner_steam_id !== ownerSteamId) {
    return jsonResponse({ ok: false, error_kind: "forbidden", message: "You do not own this boss" }, 403);
  }

  const updated = await db.update("bosses", `id=eq.${bossId}`, { is_published: false });
  if (!updated.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: updated.errorMessage ?? "" }, 502);
  }
  return jsonResponse({ ok: true }, 200);
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
    return await handleUnpublish(req, verifier, db, expectedAppId);
  });
}
