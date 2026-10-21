// 2026-10-23 — issue-battle-ticket のテスト。実Steam/実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/issue-battle-ticket/

import { assertEquals } from "jsr:@std/assert";
import { handleIssueBattleTicket, IssueBattleTicketResponseBody } from "./index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "../steam-auth/steam_web_api_client.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

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

const BOSS = "11111111-1111-4111-8111-111111111111";
const OTHER_BOSS = "33333333-3333-4333-8333-333333333333";
const HIDDEN_BOSS = "22222222-2222-4222-8222-222222222222";
const ME = "76561198000000001";

function db(): FakeSupabaseRestClient {
  const fake = new FakeSupabaseRestClient();
  fake.seed("bosses", [
    { id: BOSS, boss_name: "公開ボス", is_published: true, revision: 2, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: OTHER_BOSS, boss_name: "別の公開ボス", is_published: true, revision: 1, payload: { draft_fields: { creator_mode: "advanced" } } },
    { id: HIDDEN_BOSS, boss_name: "非公開ボス", is_published: false, revision: 1, payload: {} },
  ]);
  fake.nowMs = Date.parse("2026-10-23T12:00:00Z");
  return fake;
}

function post(payload: unknown): Request {
  return new Request("http://localhost/issue-battle-ticket", { method: "POST", body: JSON.stringify(payload) });
}

async function issue(fake: FakeSupabaseRestClient, bossId = BOSS, steamId = ME): Promise<{ status: number; body: IssueBattleTicketResponseBody }> {
  const res = await handleIssueBattleTicket(post({ ticket: "aabbcc", boss_id: bossId }), verifierSucceedingAs(steamId), fake, 5482410);
  return { status: res.status, body: await res.json() };
}

Deno.test("a ticket is issued for a published boss, bound to the verified player (never the steam_id in the request), valid for 30 days", async () => {
  const fake = db();
  const res = await handleIssueBattleTicket(post({ ticket: "aabbcc", boss_id: BOSS, steam_id: "1" }), verifierSucceedingAs(ME), fake, 5482410);
  assertEquals(res.status, 200);
  const body: IssueBattleTicketResponseBody = await res.json();
  assertEquals(body.ok, true);
  const tickets = fake.rowsOf("boss_battle_tickets");
  assertEquals(tickets.length, 1);
  assertEquals([tickets[0].id, tickets[0].challenger_steam_id, tickets[0].boss_id, tickets[0].creator_mode, tickets[0].boss_revision], [body.battle_ticket, ME, BOSS, "simple", 2]);
  assertEquals(Date.parse(String(body.expires_at)) - (fake.nowMs as number), 30 * 24 * 3600_000);
  // 2枚目は別のチケット（1戦闘1枚）
  const second = await issue(fake);
  assertEquals(second.status, 200);
  assertEquals(second.body.battle_ticket === body.battle_ticket, false);
});

Deno.test("an unpublished or unknown boss gets 404 and no ticket", async () => {
  const fake = db();
  assertEquals((await issue(fake, HIDDEN_BOSS)).status, 404);
  assertEquals((await issue(fake, "44444444-4444-4444-8444-444444444444")).status, 404);
  assertEquals(fake.rowsOf("boss_battle_tickets").length, 0);
});

Deno.test("60 tickets per player per boss per hour, then 429; other bosses and other players are not limited; an hour later it works again", async () => {
  const fake = db();
  for (let i = 0; i < 60; i++) assertEquals((await issue(fake)).status, 200, `ticket ${i + 1}`);
  const limited = await issue(fake);
  assertEquals([limited.status, limited.body.error_kind], [429, "rate_limited"]);
  assertEquals((await issue(fake, OTHER_BOSS)).status, 200, "another boss");
  assertEquals((await issue(fake, BOSS, "76561198000000002")).status, 200, "another player");
  fake.nowMs = (fake.nowMs as number) + 3600_000 + 1;
  assertEquals((await issue(fake)).status, 200, "after an hour");
});

Deno.test("600 tickets per player per 24 hours across all bosses, then 429 daily_limit", async () => {
  const fake = db();
  const start = fake.nowMs as number;
  // 1時間ごとに同じボスで55枚ずつ（1時間の上限には届かない）を11時間 = 605枚の手前まで
  let issued = 0;
  for (let hour = 0; hour < 11 && issued < 600; hour++) {
    fake.nowMs = start + hour * 3600_000 + hour;
    for (let i = 0; i < 55 && issued < 600; i++) {
      assertEquals((await issue(fake)).status, 200);
      issued += 1;
    }
  }
  assertEquals(issued, 600);
  const limited = await issue(fake, OTHER_BOSS);
  assertEquals([limited.status, limited.body.error_kind], [429, "daily_limit"]);
  fake.nowMs = start + 24 * 3600_000 + 1;
  assertEquals((await issue(fake, OTHER_BOSS)).status, 200, "the oldest hour has left the 24-hour window");
});

Deno.test("an invalid Steam ticket is 401 and never reaches the database; a malformed boss id is 400", async () => {
  const fake = db();
  const rejected = await handleIssueBattleTicket(post({ ticket: "aabbcc", boss_id: BOSS }), verifierRejectingTicket(), fake, 5482410);
  assertEquals(rejected.status, 401);
  const malformed = await handleIssueBattleTicket(post({ ticket: "aabbcc", boss_id: "not-a-uuid" }), verifierSucceedingAs(ME), fake, 5482410);
  assertEquals(malformed.status, 400);
  const noTicket = await handleIssueBattleTicket(post({ boss_id: BOSS }), verifierSucceedingAs(ME), fake, 5482410);
  assertEquals(noTicket.status, 400);
  assertEquals(fake.rpcCalls.length, 0);
  assertEquals((await handleIssueBattleTicket(new Request("http://localhost/x", { method: "GET" }), verifierSucceedingAs(ME), fake, 5482410)).status, 405);
});

Deno.test("a database failure is 502 without the database's own message", async () => {
  const fake = db();
  fake.failRpcCall("issue_boss_battle_ticket", 1);
  const res = await handleIssueBattleTicket(post({ ticket: "aabbcc", boss_id: BOSS }), verifierSucceedingAs(ME), fake, 5482410);
  assertEquals(res.status, 502);
  const text = await res.text();
  assertEquals(JSON.parse(text).error_kind, "db_error");
  assertEquals(text.includes("fake failure"), false);
});
