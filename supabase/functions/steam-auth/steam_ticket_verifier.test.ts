// Phase 4A-1 — SteamTicketVerifierのmockテスト。実Steam Web APIへは
// 一切出ない(SteamWebApiClientをMockSteamWebApiClientへ差し替える)。
// 正式AppID/Publisher Web API Keyが無くても`deno test`だけで実行できる。
//
// 実行方法: deno test supabase/functions/steam-auth/

import { assertEquals } from "jsr:@std/assert";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "./steam_web_api_client.ts";
import { SteamTicketVerifier } from "./steam_ticket_verifier.ts";

class MockSteamWebApiClient implements SteamWebApiClient {
  public lastParams: AuthenticateUserTicketParams | null = null;
  constructor(private readonly result: RawHttpResult) {}

  authenticateUserTicket(
    params: AuthenticateUserTicketParams,
  ): Promise<RawHttpResult> {
    this.lastParams = params;
    return Promise.resolve(this.result);
  }
}

function verifierWith(result: RawHttpResult, key = "dummy-test-key"): SteamTicketVerifier {
  return new SteamTicketVerifier({
    client: new MockSteamWebApiClient(result),
    publisherWebApiKey: key,
  });
}

const SUCCESS_BODY = JSON.stringify({
  response: {
    params: {
      result: "OK",
      steamid: "76561198000000001",
      ownersteamid: "76561198000000001",
      vacbanned: false,
      publisherbanned: false,
    },
  },
});

// 1. valid Steam response → 認証成功
Deno.test("valid Steam response results in success with the verified SteamID64", async () => {
  const verifier = verifierWith({ status: 200, body: SUCCESS_BODY });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, true);
  assertEquals(result.steamId, "76561198000000001");
  assertEquals(result.errorKind, "");
});

// 2. invalid ticket → 認証失敗
Deno.test("invalid ticket is reported as invalid_ticket", async () => {
  const body = JSON.stringify({
    response: { error: { errorcode: 101, errordesc: "Ticket is not valid." } },
  });
  const verifier = verifierWith({ status: 200, body });
  const result = await verifier.verifyTicket("00", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "invalid_ticket");
});

// 3. expired/invalid response（error無し・paramsのresultがOK以外）
Deno.test("a response without an OK result is expired_or_invalid_response", async () => {
  const body = JSON.stringify({ response: { params: { result: "Expired" } } });
  const verifier = verifierWith({ status: 200, body });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "expired_or_invalid_response");
});

// 4. Steam API 4xx
Deno.test("HTTP 4xx from Steam is reported as http_4xx", async () => {
  const verifier = verifierWith({ status: 403, body: "Forbidden" });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "http_4xx");
});

// 5. Steam API 5xx
Deno.test("HTTP 5xx from Steam is reported as http_5xx", async () => {
  const verifier = verifierWith({ status: 500, body: "Internal Server Error" });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "http_5xx");
});

// 6. timeout/network error
Deno.test("a network-level failure is reported as network_error", async () => {
  const verifier = verifierWith({ networkError: "connection timed out" });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "network_error");
});

// 7. malformed JSON
Deno.test("a non-JSON body is reported as malformed_json", async () => {
  const verifier = verifierWith({ status: 200, body: "<html>not json</html>" });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "malformed_json");
});

// 8. SteamID missing（Steamの成功形なのにsteamidフィールドが無い）
Deno.test("a success-shaped response missing steamid is missing_steam_id", async () => {
  const body = JSON.stringify({ response: { params: { result: "OK" } } });
  const verifier = verifierWith({ status: 200, body });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "missing_steam_id");
});

// 9. identity mismatchを想定した失敗
Deno.test("an identity-related Steam error is reported as identity_mismatch", async () => {
  const body = JSON.stringify({
    response: { error: { errorcode: 101, errordesc: "Ticket identity does not match" } },
  });
  const verifier = verifierWith({ status: 200, body });
  const result = await verifier.verifyTicket("4af203", 480, "wrong-identity");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "identity_mismatch");
});

// 10. AppID mismatchを想定した失敗
Deno.test("an appid-related Steam error is reported as appid_mismatch", async () => {
  const body = JSON.stringify({
    response: { error: { errorcode: 101, errordesc: "Ticket app id does not match" } },
  });
  const verifier = verifierWith({ status: 200, body });
  const result = await verifier.verifyTicket("4af203", 99999, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "appid_mismatch");
});

// 追加: Publisher Web API Key未設定時は実HTTPへ一切出ずnot_configuredを返す。
Deno.test("missing publisher web api key short-circuits to not_configured without any HTTP call", async () => {
  const client = new MockSteamWebApiClient({ status: 200, body: SUCCESS_BODY });
  const verifier = new SteamTicketVerifier({ client, publisherWebApiKey: undefined });
  const result = await verifier.verifyTicket("4af203", 480, "makers-and-challengers-backend");
  assertEquals(result.ok, false);
  assertEquals(result.errorKind, "not_configured");
  assertEquals(client.lastParams, null);
});
