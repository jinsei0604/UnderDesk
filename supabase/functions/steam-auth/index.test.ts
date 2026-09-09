// Phase 4A-1 — handleRequest()自体のテスト。実サーバー(Deno.serve)は
// 起動せず、handleRequest()をverifierを差し替えて直接呼ぶ。
//
// 実行方法: deno test supabase/functions/steam-auth/

import { assertEquals } from "jsr:@std/assert";
import { handleRequest, SteamAuthResponseBody } from "./index.ts";
import { SteamTicketVerifier } from "./steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "./steam_web_api_client.ts";

class StubClient implements SteamWebApiClient {
  constructor(private readonly result: RawHttpResult) {}
  authenticateUserTicket(_params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    return Promise.resolve(this.result);
  }
}

function verifierAlwaysSucceedsWith(steamId: string): SteamTicketVerifier {
  const body = JSON.stringify({ response: { params: { result: "OK", steamid: steamId } } });
  return new SteamTicketVerifier({
    client: new StubClient({ status: 200, body }),
    publisherWebApiKey: "dummy-test-key",
  });
}

function verifierAlwaysFails(): SteamTicketVerifier {
  return new SteamTicketVerifier({
    client: new StubClient({ status: 200, body: "" }),
    publisherWebApiKey: undefined,
  });
}

async function postJson(payload: unknown): Promise<Request> {
  return new Request("http://localhost/steam-auth", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

Deno.test("non-POST requests are rejected", async () => {
  const req = new Request("http://localhost/steam-auth", { method: "GET" });
  const res = await handleRequest(req, verifierAlwaysFails(), 480);
  assertEquals(res.status, 405);
});

Deno.test("malformed JSON body is rejected as malformed_request", async () => {
  const req = new Request("http://localhost/steam-auth", {
    method: "POST",
    body: "{not json",
  });
  const res = await handleRequest(req, verifierAlwaysFails(), 480);
  assertEquals(res.status, 400);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.error_kind, "malformed_request");
});

Deno.test("missing ticket field is rejected as invalid_request", async () => {
  const req = await postJson({});
  const res = await handleRequest(req, verifierAlwaysFails(), 480);
  assertEquals(res.status, 400);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.error_kind, "invalid_request");
});

Deno.test("non-hex ticket field is rejected as invalid_request", async () => {
  const req = await postJson({ ticket: "not-hex!!" });
  const res = await handleRequest(req, verifierAlwaysFails(), 480);
  assertEquals(res.status, 400);
});

Deno.test("successful verification returns ok true with the verified steam_id", async () => {
  const req = await postJson({ ticket: "4af203" });
  const res = await handleRequest(req, verifierAlwaysSucceedsWith("76561198000000001"), 480);
  assertEquals(res.status, 200);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.steam_id, "76561198000000001");
});

Deno.test("client-supplied steam_id is never trusted as the response steam_id, only compared", async () => {
  const req = await postJson({ ticket: "4af203", steam_id: "1" });
  const res = await handleRequest(req, verifierAlwaysSucceedsWith("76561198000000001"), 480);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.steam_id, "76561198000000001");
  assertEquals(body.client_steam_id_matched, false);
});

Deno.test("matching client-supplied steam_id is reported as matched, for debug comparison only", async () => {
  const req = await postJson({ ticket: "4af203", steam_id: "76561198000000001" });
  const res = await handleRequest(req, verifierAlwaysSucceedsWith("76561198000000001"), 480);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.client_steam_id_matched, true);
});

Deno.test("verifier not_configured maps to HTTP 503, not a generic 401", async () => {
  const req = await postJson({ ticket: "4af203" });
  const res = await handleRequest(req, verifierAlwaysFails(), 480);
  assertEquals(res.status, 503);
  const body: SteamAuthResponseBody = await res.json();
  assertEquals(body.error_kind, "not_configured");
});
