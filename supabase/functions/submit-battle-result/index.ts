// 2026-10-23 — 決着した戦闘の結果（勝ち・負け）を、戦闘チケットで受け付ける（_shared/battle_tickets.ts）。
// 挑戦者数・通常クリア率（一覧・検索・人気・高難度）と難関ボス討伐の認定は、ここで受け付けた結果だけで数える。
//
// - 1回のリクエストで最大20件（ゲームの送信待ちの結果をまとめて送る。Steam の確認とリクエストは1回）。
// - 1件ごとの答え: counted（今回数えた）・duplicate（同じ結果は数え済み。同じチケット・同じ結果の id・同じ勝敗の送り直し）・
//   invalid・used・expired（数えない。ゲームは送信待ちから外す）・error（DB に届かなかった。ゲームは後で送り直す）。
//   counted・duplicate の時は by_owner（作者本人か）・hard_awarded（難関ボス討伐の認定）・first_clear_rate（初めてクリアした時の
//   ほかの人のクリア率。挑戦者0人なら null）も返す（ゲームの討伐記録に使う）。
// - next_ticket_boss_id を渡すと、次の戦闘のチケットも同じ応答で返す（「もう一度挑戦」で通信を増やさないため）。
// - チケットは本人（Steam で確かめた SteamID）・ボスに結びつく。リクエストの steam_id は使わない。ボスがその後に非公開に
//   なっても、公開中に出したチケットの結果は受け付ける（削除されたボスはチケットも消えるので invalid）。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { demoBossRejection } from "../_shared/edition.ts";
import { firstClearRate, isUuid, issueBattleTicket, submitBattleResult } from "../_shared/battle_tickets.ts";

export const MAX_RESULTS_PER_REQUEST = 20;

export interface SubmitBattleResultRequestBody {
  ticket?: unknown;
  results?: unknown;
  next_ticket_boss_id?: unknown;
}

export interface SubmittedResultBody {
  result_id: string | null;
  status: string;
  by_owner?: boolean;
  hard_awarded?: boolean;
  clear_count?: number;
  first_clear_rate?: number | null;
}

export interface SubmitBattleResultResponseBody {
  ok: boolean;
  results?: SubmittedResultBody[];
  next_battle_ticket?: string;
  next_ticket_expires_at?: string;
  next_ticket_status?: string;
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: SubmitBattleResultResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export async function handleSubmitBattleResult(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  let body: SubmitBattleResultRequestBody;
  try {
    body = JSON.parse(await req.text());
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }
  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  if (!Array.isArray(body.results) || body.results.length > MAX_RESULTS_PER_REQUEST) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: `'results' must be an array of at most ${MAX_RESULTS_PER_REQUEST}` }, 400);
  }
  const nextBossId = body.next_ticket_boss_id;
  if (nextBossId !== undefined && nextBossId !== null && !isUuid(nextBossId)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'next_ticket_boss_id' must be a valid boss id" }, 400);
  }
  if (body.results.length === 0 && !isUuid(nextBossId)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "nothing to submit" }, 400);
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

  const results: SubmittedResultBody[] = [];
  for (const raw of body.results as unknown[]) {
    const item = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
    const resultId = isUuid(item.result_id) ? item.result_id : null;
    if (resultId === null || !isUuid(item.battle_ticket) || !isUuid(item.boss_id) || (item.outcome !== "clear" && item.outcome !== "loss")) {
      results.push({ result_id: typeof item.result_id === "string" && item.result_id.length <= 64 ? item.result_id : null, status: "invalid" });
      continue;
    }
    const submitted = await submitBattleResult(db, {
      ticketId: item.battle_ticket,
      bossId: item.boss_id,
      steamId,
      resultId,
      outcome: item.outcome,
    });
    if (!submitted.ok) {
      console.error("submit-battle-result: db error", submitted.errorMessage);
      results.push({ result_id: resultId, status: "error" });
      continue;
    }
    const r = submitted.result;
    const out: SubmittedResultBody = { result_id: resultId, status: r.status };
    if (r.status === "counted" || r.status === "duplicate") {
      out.by_owner = r.byOwner === true;
      out.hard_awarded = r.hardAwarded === true;
      if (r.clearCount !== null) out.clear_count = r.clearCount;
      out.first_clear_rate = firstClearRate(r.firstClearChallengers, r.firstClearClearers);
    }
    results.push(out);
  }

  const response: SubmitBattleResultResponseBody = { ok: true, results };
  // 体験版のチケットで範囲外のボスの次の戦闘チケットは出さない(2026-10-28、_shared/edition.ts)。
  const nextDemoRejected = isUuid(nextBossId) ? await demoBossRejection(db, nextBossId, verification.edition) : null;
  if (nextDemoRejected !== null) {
    response.next_ticket_status = nextDemoRejected;
  } else if (isUuid(nextBossId)) {
    const issued = await issueBattleTicket(db, nextBossId, steamId);
    if (!issued.ok) {
      console.error("submit-battle-result: ticket error", issued.errorMessage);
      response.next_ticket_status = "error";
    } else if (issued.status === "issued" && issued.ticketId !== null && issued.expiresAt !== null) {
      response.next_battle_ticket = issued.ticketId;
      response.next_ticket_expires_at = issued.expiresAt;
    } else {
      response.next_ticket_status = issued.status;
    }
  }
  return jsonResponse(response, 200);
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
    return await handleSubmitBattleResult(req, verifier, db, expectedAppId);
  });
}
