// Phase 5 — オンライン版「未挑戦」— 挑戦開始をSteamユーザー単位で記録する。
//
// publish-boss/unpublish-bossと同じ信頼境界(§重要「SteamIDをクライアントから
// 信用しない」): challenger_steam_idとしてDBへ書き込むSteamIDは、常に
// SteamTicketVerifierの検証結果(verification.steamId)のみ。リクエストに
// steam_idが含まれていても一切参照しない。
//
// challenge_count/last_challenged_at等の更新は、boss_challenge_records
// migrationで定義したPostgres関数record_boss_challenge_attempt()への
// rpc()呼び出しで行う——SELECT→+1→UPDATEの非atomicなread-modify-writeは
// 行わない(競合に強いINSERT ... ON CONFLICT ... DO UPDATE ... = ... + 1、
// ユーザー確定仕様)。
//
// 挑戦記録はベストエフォート(クライアント側で戦闘開始をブロックしない)
// だが、サーバー側は普通にエラーを返す——「常に200を返す」ような設計には
// しない(呼び出し側が失敗を無視する判断をするだけで、サーバー自身は
// 正直にエラーを返す)。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

export interface RecordChallengeAttemptRequestBody {
  ticket?: unknown;
  boss_id?: unknown;
}

export interface RecordChallengeAttemptResponseBody {
  ok: boolean;
  challenge_count?: number;
  error_kind?: string;
  message?: string;
}

const UUID_PATTERN = /^[0-9a-fA-F-]{36}$/;

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: RecordChallengeAttemptResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface BossExistsRow {
  id: string;
}

interface ChallengeRecordRow {
  challenge_count: number;
}

export async function handleRecordChallengeAttempt(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: RecordChallengeAttemptRequestBody;
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

  // --- Steam ticket verification (SteamID extraction happens only here) ---
  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const challengerSteamId = verification.steamId as string;

  // 公開中のbossにしか挑戦記録を作らない——get-bossと同じ
  // 「存在しない」と「非公開」を区別しない安全な合成(not_foundへ統一)。
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

  const recorded = await db.rpc<ChallengeRecordRow>("record_boss_challenge_attempt", {
    p_boss_id: bossId,
    p_steam_id: challengerSteamId,
  });
  if (!recorded.ok || recorded.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: recorded.errorMessage ?? "" }, 502);
  }

  return jsonResponse({ ok: true, challenge_count: recorded.rows[0].challenge_count }, 200);
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
    return await handleRecordChallengeAttempt(req, verifier, db, expectedAppId);
  });
}
