// Phase 4A-1 — Steam認証Edge Functionの雛形。
//
// 役割: Godotから {"ticket": "...hex...", "steam_id"?: "..."} を受け取り、
// 将来的に Steam の AuthenticateUserTicket でticketを検証してSteamID64を
// 返す。今回は正式AppID/Publisher Web API Keyがまだ存在しないため、実際に
// Steamへ問い合わせる経路(RealSteamWebApiClient)は書いてあるが、
// STEAM_PUBLISHER_WEB_API_KEY が未設定の間は必ず not_configured を返し、
// 本番動作はしない(Phase 4A-2で鍵を登録した時点で自動的に動き出す設計)。
//
// §重要「SteamIDをクライアントから信用しない」: レスポンスのsteam_idは
// 常にSteam Web APIの検証結果から来た値のみ。クライアントが送ってきた
// steam_idは client_steam_id_matched というデバッグ比較フィールドにしか
// 使わない。
//
// §重要「秘密情報をGodotクライアントへ置かない」: STEAM_PUBLISHER_WEB_API_KEY
// や Supabase の secret/service_role 系キーはこのEdge Function内の環境
// 変数としてのみ読む。Godot側のコードには一切登場しない。
//
// 処理の流れ(interfaceで分離、mock可能):
//   request validation → SteamTicketVerifier(ticket verification) →
//   SteamID extraction → response creation

import {
  SteamTicketVerifier,
  SteamVerificationResult,
} from "./steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "./steam_web_api_client.ts";

// クライアント(Godot)側のRBMSteamAuth.WEB_API_IDENTITYと必ず一致させる
// 固定値。GodotScriptとDenoは別ランタイムのため定数を共有できず、
// 両側にそれぞれ書く(片方だけ変更すると認証が壊れるので変更時は要注意)。
export const WEB_API_IDENTITY = "makers-and-challengers-backend";

export interface SteamAuthRequestBody {
  ticket?: unknown;
  steam_id?: unknown;
}

export interface SteamAuthResponseBody {
  ok: boolean;
  steam_id?: string;
  client_steam_id_matched?: boolean;
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

function jsonResponse(body: SteamAuthResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// テスト可能にするため、実際のHTTPハンドラ本体をexportする——Deno.serve()
// はこれをラップするだけ。テストはverifier/appIdを差し替えてこの関数を
// 直接呼ぶ(実サーバーを起動しない)。
export async function handleRequest(
  req: Request,
  verifier: SteamTicketVerifier,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  // --- request validation ---
  let body: SteamAuthRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(
      { ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" },
      400,
    );
  }

  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse(
      { ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" },
      400,
    );
  }
  const ticketHex = body.ticket as string;

  // §重要: steam_idはあってもデバッグ比較用途のみ、無くても構わない。
  const clientSteamId = typeof body.steam_id === "string" ? body.steam_id : null;

  // --- Steam ticket verification ---
  const result: SteamVerificationResult = await verifier.verifyTicket(
    ticketHex,
    expectedAppId,
    WEB_API_IDENTITY,
  );

  if (!result.ok) {
    const status = result.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse(
      { ok: false, error_kind: result.errorKind, message: result.message },
      status,
    );
  }

  // --- SteamID extraction ---
  // 信用できるのはresult.steamIdだけ。clientSteamIdは比較にしか使わない。
  const verifiedSteamId = result.steamId as string;

  // --- response creation ---
  return jsonResponse(
    {
      ok: true,
      steam_id: verifiedSteamId,
      client_steam_id_matched: clientSteamId !== null && clientSteamId === verifiedSteamId,
    },
    200,
  );
}

// 実サーバー起動(Supabase Edge Functionsのランタイムがこのファイルを
// 読み込んだ時に実行される)。STEAM_PUBLISHER_WEB_API_KEYが無い間は
// verifierが常にnot_configuredを返すだけで、実Steamへは出ない。
if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const verifier = new SteamTicketVerifier({
      client: new RealSteamWebApiClient(),
      publisherWebApiKey: Deno.env.get("STEAM_PUBLISHER_WEB_API_KEY"),
    });
    const expectedAppId = Number(Deno.env.get("STEAM_APP_ID") ?? "0");
    return await handleRequest(req, verifier, expectedAppId);
  });
}
