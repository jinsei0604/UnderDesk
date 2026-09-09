// Phase 4A-1 — Steam Web APIの生HTTPレスポンス(steam_web_api_client.ts)を
// 解釈するだけの層。RBMSupabaseResponse(Godot側、rbm_supabase_response.gd)
// と同じ考え方——通信を行う層と解釈する層を分離し、解釈ロジックだけを
// ネットワーク無しでテストできるようにする。
//
// 重要: ここが返すsteamIdだけが「サーバー側で検証済みのSteamID64」。
// クライアントから送られてきたsteam_id(index.ts参照)は本人確認の根拠に
// 一切使わない。

import {
  AuthenticateUserTicketParams,
  SteamWebApiClient,
} from "./steam_web_api_client.ts";

export type SteamVerificationErrorKind =
  | ""
  | "not_configured"
  | "invalid_ticket"
  | "expired_or_invalid_response"
  | "http_4xx"
  | "http_5xx"
  | "network_error"
  | "malformed_json"
  | "missing_steam_id"
  | "identity_mismatch"
  | "appid_mismatch";

export interface SteamVerificationResult {
  ok: boolean;
  steamId: string | null;
  errorKind: SteamVerificationErrorKind;
  message: string;
}

function fail(
  errorKind: SteamVerificationErrorKind,
  message: string,
): SteamVerificationResult {
  return { ok: false, steamId: null, errorKind, message };
}

export interface SteamTicketVerifierOptions {
  client: SteamWebApiClient;
  // Phase 4A-2で正式に設定される。undefined/空文字の間は常にnot_configured
  // を返し、実HTTP呼び出しへは進まない(ダミー鍵をコードに書く必要がない
  // 設計、ユーザー確定方針)。
  publisherWebApiKey: string | undefined;
}

export class SteamTicketVerifier {
  private readonly client: SteamWebApiClient;
  private readonly publisherWebApiKey: string | undefined;

  constructor(options: SteamTicketVerifierOptions) {
    this.client = options.client;
    this.publisherWebApiKey = options.publisherWebApiKey;
  }

  async verifyTicket(
    ticketHex: string,
    appId: number,
    identity: string,
  ): Promise<SteamVerificationResult> {
    if (!this.publisherWebApiKey) {
      return fail(
        "not_configured",
        "STEAM_PUBLISHER_WEB_API_KEY is not set. Real Steam verification is not available until Phase 4A-2.",
      );
    }

    const params: AuthenticateUserTicketParams = {
      publisherWebApiKey: this.publisherWebApiKey,
      appId,
      ticketHex,
      identity,
    };

    const raw = await this.client.authenticateUserTicket(params);

    if (raw.networkError !== undefined) {
      return fail("network_error", `Network error contacting Steam: ${raw.networkError}`);
    }

    const status = raw.status ?? 0;
    const bodyText = raw.body ?? "";

    if (status >= 500) {
      return fail("http_5xx", `Steam Web API returned HTTP ${status}`);
    }
    if (status >= 400) {
      return fail("http_4xx", `Steam Web API returned HTTP ${status}`);
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(bodyText);
    } catch {
      return fail("malformed_json", "Steam Web API response body was not valid JSON");
    }

    return this.interpretBody(parsed);
  }

  // Steamの成功形: {"response":{"params":{"result":"OK","steamid":"765...",
  //   "ownersteamid":"...","vacbanned":false,"publisherbanned":false}}}
  // 失敗形: {"response":{"error":{"errorcode":N,"errordesc":"..."}}}
  private interpretBody(parsed: unknown): SteamVerificationResult {
    if (typeof parsed !== "object" || parsed === null) {
      return fail("malformed_json", "Steam Web API response was not a JSON object");
    }
    const response = (parsed as Record<string, unknown>)["response"];
    if (typeof response !== "object" || response === null) {
      return fail("malformed_json", "Steam Web API response was missing the 'response' field");
    }
    const responseObj = response as Record<string, unknown>;

    const error = responseObj["error"];
    if (typeof error === "object" && error !== null) {
      const errorObj = error as Record<string, unknown>;
      const description = String(errorObj["errordesc"] ?? "");
      const lowered = description.toLowerCase();
      if (lowered.includes("identity")) {
        return fail("identity_mismatch", description || "Ticket identity does not match");
      }
      if (lowered.includes("app")) {
        return fail("appid_mismatch", description || "Ticket AppID does not match");
      }
      return fail("invalid_ticket", description || "Steam reported the ticket as invalid");
    }

    const params = responseObj["params"];
    if (typeof params !== "object" || params === null) {
      return fail("expired_or_invalid_response", "Steam response had neither 'params' nor 'error'");
    }
    const paramsObj = params as Record<string, unknown>;
    const result = String(paramsObj["result"] ?? "");
    if (result !== "OK") {
      return fail("expired_or_invalid_response", `Steam reported result=${result || "(missing)"}`);
    }

    const steamId = paramsObj["steamid"];
    if (typeof steamId !== "string" || steamId.length === 0) {
      return fail("missing_steam_id", "Steam's success response did not include a steamid");
    }

    return { ok: true, steamId, errorKind: "", message: "" };
  }
}
