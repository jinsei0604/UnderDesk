// Phase 5 — list-unchallenged-bossesのmockテスト。実Steam/実Supabaseへは
// 一切出ない。実行方法: deno test supabase/functions/list-unchallenged-bosses/

import { assertEquals } from "jsr:@std/assert";
import { handleListUnchallengedBosses, ListUnchallengedBossesResponseBody } from "./index.ts";
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
  return new SteamTicketVerifier({
    client: new StubSteamClient({ status: 200, body }),
    publisherWebApiKey: "dummy-test-key",
  });
}

function verifierRejectingTicket(): SteamTicketVerifier {
  const body = JSON.stringify({ response: { error: { errorcode: 101, errordesc: "Invalid ticket" } } });
  return new SteamTicketVerifier({
    client: new StubSteamClient({ status: 200, body }),
    publisherWebApiKey: "dummy-test-key",
  });
}

const VALID_HEX_TICKET = "aabbcc";
const ME = "76561198000000001";
const SOMEONE_ELSE = "76561198000000002";

function postJson(payload: unknown): Request {
  return new Request("http://localhost/list-unchallenged-bosses", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "1", boss_name: "未挑戦ボスA", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: "2", boss_name: "挑戦済みボスB", author_name: "B", published_at: "2026-02-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: "3", boss_name: "未挑戦ボスC", author_name: "C", published_at: "2026-03-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced" } } },
    { id: "4", boss_name: "非公開ボスD", author_name: "D", published_at: "2026-04-01T00:00:00Z", revision: 1, is_published: false, payload: { draft_fields: { creator_mode: "simple" } } },
  ]);
  return db;
}

Deno.test("returns only bosses this Steam user has never challenged", async () => {
  const db = dbWithBosses();
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "2", challenger_steam_id: ME, challenge_count: 1, clear_count: 0 },
  ]);
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), db, 480);
  assertEquals(res.status, 200);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  assertEquals(body.ok, true);
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names.includes("挑戦済みボスB"), false, "a boss with challenge_count>0 for this user must be excluded");
  assertEquals(names.includes("未挑戦ボスA"), true);
  assertEquals(names.includes("未挑戦ボスC"), true);
});

Deno.test("a boss with a zero-challenge_count record is still treated as unchallenged", async () => {
  const db = dbWithBosses();
  // A record can exist (e.g. created defensively by a clear without a prior
  // attempt) with challenge_count still at 0 -- that must not count as
  // "challenged".
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "2", challenger_steam_id: ME, challenge_count: 0, clear_count: 1 },
  ]);
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), db, 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names.includes("挑戦済みボスB"), true, "challenge_count=0 must still count as unchallenged regardless of clear_count");
});

Deno.test("another Steam user's challenge history never excludes a boss for me", async () => {
  const db = dbWithBosses();
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "2", challenger_steam_id: SOMEONE_ELSE, challenge_count: 5, clear_count: 1 },
  ]);
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), db, 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names.includes("挑戦済みボスB"), true, "someone else's challenge history must not affect my own unchallenged list");
});

Deno.test("mode=simple filters to only simple unchallenged bosses", async () => {
  const res = await handleListUnchallengedBosses(
    postJson({ ticket: VALID_HEX_TICKET, mode: "simple" }),
    verifierSucceedingAs(ME),
    dbWithBosses(),
    480,
  );
  const body: ListUnchallengedBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names, ["挑戦済みボスB", "未挑戦ボスA"], "newest first, simple only");
});

Deno.test("mode=advanced filters to only advanced unchallenged bosses", async () => {
  const res = await handleListUnchallengedBosses(
    postJson({ ticket: VALID_HEX_TICKET, mode: "advanced" }),
    verifierSucceedingAs(ME),
    dbWithBosses(),
    480,
  );
  const body: ListUnchallengedBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names, ["未挑戦ボスC"]);
});

Deno.test("creator_mode falls back to simple when draft_fields or creator_mode is missing", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "1", boss_name: "旧形式ボス", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: {} },
  ]);
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), db, 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  assertEquals(body.bosses![0].creator_mode, "simple");
});

Deno.test("results are ordered newest published first", async () => {
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), dbWithBosses(), 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["未挑戦ボスC", "挑戦済みボスB", "未挑戦ボスA"]);
});

Deno.test("unpublished bosses are excluded even if never challenged", async () => {
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), dbWithBosses(), 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names.includes("非公開ボスD"), false);
});

Deno.test("summary rows never include payload, challenger_steam_id, or the raw challenge record", async () => {
  const db = dbWithBosses();
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "2", challenger_steam_id: ME, challenge_count: 1, clear_count: 0 },
  ]);
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierSucceedingAs(ME), db, 480);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  for (const boss of body.bosses!) {
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "payload"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "challenger_steam_id"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "challenge_count"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "clear_count"), false);
  }
});

Deno.test("invalid ticket is rejected before any boss data is returned", async () => {
  const res = await handleListUnchallengedBosses(postJson({ ticket: VALID_HEX_TICKET }), verifierRejectingTicket(), dbWithBosses(), 480);
  assertEquals(res.status, 401);
  const body: ListUnchallengedBossesResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "invalid_ticket");
  assertEquals(body.bosses, undefined);
});

Deno.test("non-POST requests are rejected", async () => {
  const req = new Request("http://localhost/list-unchallenged-bosses", { method: "GET" });
  const res = await handleListUnchallengedBosses(req, verifierSucceedingAs(ME), dbWithBosses(), 480);
  assertEquals(res.status, 405);
});

Deno.test("missing ticket is rejected as invalid_request", async () => {
  const res = await handleListUnchallengedBosses(postJson({}), verifierSucceedingAs(ME), dbWithBosses(), 480);
  assertEquals(res.status, 400);
});
