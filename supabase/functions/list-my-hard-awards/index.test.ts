// 2026-10-23 — list-my-hard-awards のテスト。実Steam/実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/list-my-hard-awards/

import { assertEquals } from "jsr:@std/assert";
import { handleListMyHardAwards, ListMyHardAwardsResponseBody } from "./index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "../steam-auth/steam_web_api_client.ts";
import { FakePostgrestClient } from "../_shared/fake_postgrest_client.ts";

class StubSteamClient implements SteamWebApiClient {
  constructor(private readonly result: RawHttpResult) {}
  authenticateUserTicket(_params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    return Promise.resolve(this.result);
  }
}

function verifierSucceedingAs(steamId: string): SteamTicketVerifier {
  const body = JSON.stringify({ response: { params: { result: "OK", steamid: steamId } } });
  return new SteamTicketVerifier({ client: new StubSteamClient({ status: 200, body }), publisherWebApiKey: "dummy-test-key" });
}

function verifierRejectingTicket(): SteamTicketVerifier {
  const body = JSON.stringify({ response: { error: { errorcode: 101, errordesc: "Invalid ticket" } } });
  return new SteamTicketVerifier({ client: new StubSteamClient({ status: 200, body }), publisherWebApiKey: "dummy-test-key" });
}

const ME = "76561198000000001";
const OTHER = "76561198000000002";

function post(payload: unknown): Request {
  return new Request("http://localhost/list-my-hard-awards", { method: "POST", body: JSON.stringify(payload) });
}

function seedRecords(db: FakePostgrestClient): void {
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "boss-awarded", challenger_steam_id: ME, clear_count: 1, result_count: 1, hard_awarded_at: "2026-10-23T00:00:00Z" },
    { id: "r2", boss_id: "boss-held", challenger_steam_id: ME, clear_count: 1, result_count: 1, hard_awarded_at: null },
    { id: "r3", boss_id: "boss-lost", challenger_steam_id: ME, clear_count: 0, result_count: 3, hard_awarded_at: null },
    { id: "r4", boss_id: "boss-other", challenger_steam_id: OTHER, clear_count: 1, result_count: 1, hard_awarded_at: "2026-10-23T00:00:00Z" },
    { id: "r5", boss_id: "boss-mine", challenger_steam_id: ME, clear_count: 1, result_count: 1, hard_awarded_at: "2026-10-23T00:00:00Z", by_owner: true },
  ]);
}

Deno.test("returns only my awarded boss ids, never other players' awards, my own bosses or any SteamID", async () => {
  const db = new FakePostgrestClient();
  seedRecords(db);
  const res = await handleListMyHardAwards(post({ ticket: "aabbcc", steam_id: OTHER }), verifierSucceedingAs(ME), db, 5482410);
  assertEquals(res.status, 200);
  const text = await res.text();
  assertEquals(JSON.parse(text) as ListMyHardAwardsResponseBody, { ok: true, boss_ids: ["boss-awarded"] });
  assertEquals(text.includes(ME) || text.includes(OTHER), false);
});

Deno.test("a player with no awards gets an empty list", async () => {
  const db = new FakePostgrestClient();
  seedRecords(db);
  const res = await handleListMyHardAwards(post({ ticket: "aabbcc" }), verifierSucceedingAs("76561198000000009"), db, 5482410);
  assertEquals(await res.json(), { ok: true, boss_ids: [] });
});

Deno.test("every read is limited to my awarded rows (no full scan of the records)", async () => {
  const db = new FakePostgrestClient();
  seedRecords(db);
  await handleListMyHardAwards(post({ ticket: "aabbcc" }), verifierSucceedingAs(ME), db, 5482410);
  // ページ送り（selectAllPages）は空のページまで読むので、該当がある時は2回（2回目は空）
  assertEquals(db.selectCalls.length, 2);
  for (const call of db.selectCalls) {
    assertEquals(call.table, "boss_challenge_records");
    assertEquals(call.query.includes(`challenger_steam_id=eq.${ME}`), true);
    assertEquals(call.query.includes("hard_awarded_at=not.is.null"), true);
    assertEquals(call.query.includes("by_owner=is.false"), true);
  }
});

Deno.test("an invalid ticket is rejected before reading anything", async () => {
  const db = new FakePostgrestClient();
  seedRecords(db);
  const res = await handleListMyHardAwards(post({ ticket: "aabbcc" }), verifierRejectingTicket(), db, 5482410);
  assertEquals(res.status, 401);
  assertEquals(db.selectCalls.length, 0);
});

Deno.test("bad requests and database errors do not leak details", async () => {
  const db = new FakePostgrestClient();
  assertEquals((await handleListMyHardAwards(new Request("http://localhost/x", { method: "GET" }), verifierSucceedingAs(ME), db, 5482410)).status, 405);
  assertEquals((await handleListMyHardAwards(post({ ticket: "zz" }), verifierSucceedingAs(ME), db, 5482410)).status, 400);
  db.failSelectCall("boss_challenge_records", 1);
  const res = await handleListMyHardAwards(post({ ticket: "aabbcc" }), verifierSucceedingAs(ME), db, 5482410);
  assertEquals(res.status, 502);
  assertEquals((await res.text()).includes("42703"), false, "the database error text is not returned");
});
