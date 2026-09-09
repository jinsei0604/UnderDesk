// Phase 4A-1 — Steam Web API への実HTTP呼び出しをinterface化したもの。
// 正式AppID/Publisher Web API Keyがまだ存在しないため、RealSteamWebApiClient
// は「呼ばれても本番動作させない」ことを最優先にしている。実際に
// AuthenticateUserTicket を叩く経路自体はここに実装済みだが、
// STEAM_PUBLISHER_WEB_API_KEY が未設定の間は index.ts 側が
// SteamTicketVerifier 経由でこのクライアントに到達する前に
// "not_configured" として弾く(Phase 4A-2で鍵が入るまで実通信は発生しない)。
//
// テストは全てMockSteamWebApiClientを使い、実Steamへは一切出ない
// (ユーザー確定方針: 「Steam Web APIへのHTTP部分をinterface化し、
// mock可能にする」)。

export interface RawHttpResult {
  // ネットワーク自体が失敗した場合(DNS失敗、タイムアウト等)はnetworkErrorのみ
  // が入り、status/bodyは存在しない。
  networkError?: string;
  status?: number;
  body?: string;
}

export interface AuthenticateUserTicketParams {
  publisherWebApiKey: string;
  appId: number;
  ticketHex: string;
  identity: string;
}

export interface SteamWebApiClient {
  authenticateUserTicket(
    params: AuthenticateUserTicketParams,
  ): Promise<RawHttpResult>;
}

const AUTHENTICATE_USER_TICKET_URL =
  "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/";

// Steam公式ドキュメントの ISteamUserAuth/AuthenticateUserTicket を実際に
// 叩く実装。正式なSTEAM_PUBLISHER_WEB_API_KEYが用意されるPhase 4A-2まで、
// この関数が実際に呼ばれることはない(呼び出し側のSteamTicketVerifierが
// キー未設定を先に検出して弾くため)。
export class RealSteamWebApiClient implements SteamWebApiClient {
  async authenticateUserTicket(
    params: AuthenticateUserTicketParams,
  ): Promise<RawHttpResult> {
    const url = new URL(AUTHENTICATE_USER_TICKET_URL);
    url.searchParams.set("key", params.publisherWebApiKey);
    url.searchParams.set("appid", String(params.appId));
    url.searchParams.set("ticket", params.ticketHex);
    url.searchParams.set("identity", params.identity);

    try {
      const response = await fetch(url.toString(), { method: "GET" });
      const body = await response.text();
      return { status: response.status, body };
    } catch (error) {
      return { networkError: error instanceof Error ? error.message : String(error) };
    }
  }
}
