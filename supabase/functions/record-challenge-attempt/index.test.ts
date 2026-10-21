// Phase 5 — record-challenge-attemptのmockテスト。実Steam/実Supabaseへは
// 一切出ない。実行方法: deno test supabase/functions/record-challenge-attempt/

import { assertEquals } from "jsr:@std/assert";
import { handleRecordChallengeAttempt, RecordChallengeAttemptResponseBody } from "./index.ts";
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

const PUBLISHED_BOSS_ID = "11111111-1111-1111-1111-111111111111";
const UNPUBLISHED_BOSS_ID = "22222222-2222-2222-2222-222222222222";
const VALID_HEX_TICKET = "aabbcc";
const STEAM_ID = "76561198000000001";

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: PUBLISHED_BOSS_ID, boss_name: "公開ボス", is_published: true },
    { id: UNPUBLISHED_BOSS_ID, boss_name: "非公開ボス", is_published: false },
  ]);
  return db;
}

function postJson(payload: unknown): Request {
  return new Request("http://localhost/record-challenge-attempt", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

Deno.test("valid ticket and published boss records the attempt", async () => {
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    dbWithBosses(),
    480,
  );
  assertEquals(res.status, 200);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.challenge_count, 1);
});

Deno.test("invalid ticket is rejected and never touches the database", async () => {
  const db = dbWithBosses();
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierRejectingTicket(),
    db,
    480,
  );
  assertEquals(res.status, 401);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "invalid_ticket");
  assertEquals(db.rowsOf("boss_challenge_records").length, 0);
});

Deno.test("a non-existent boss_id is rejected as not_found", async () => {
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: "99999999-9999-9999-9999-999999999999" }),
    verifierSucceedingAs(STEAM_ID),
    dbWithBosses(),
    480,
  );
  assertEquals(res.status, 404);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "not_found");
});

Deno.test("an unpublished boss is rejected as not_found (not distinguished from non-existent)", async () => {
  const db = dbWithBosses();
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: UNPUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  assertEquals(res.status, 404);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "not_found");
  assertEquals(db.rowsOf("boss_challenge_records").length, 0, "an unpublished boss must never get a challenge record");
});

Deno.test("the first attempt creates a new record with challenge_count=1", async () => {
  const db = dbWithBosses();
  await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].challenge_count, 1);
  assertEquals(rows[0].clear_count, 0);
  assertEquals(typeof rows[0].first_challenged_at, "string");
  assertEquals(rows[0].first_challenged_at, rows[0].last_challenged_at, "sanity: first and last are the same on the first attempt");
});

Deno.test("a second attempt from the same Steam user increments challenge_count instead of creating a second row", async () => {
  const db = dbWithBosses();
  await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const secondResponse = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const body: RecordChallengeAttemptResponseBody = await secondResponse.json();
  assertEquals(body.challenge_count, 2);
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1, "same (boss_id, steam_id) must update the existing row, not insert a second one");
  assertEquals(rows[0].challenge_count, 2);
});

Deno.test("the recorded challenger_steam_id always comes from the verified ticket, never from the request body", async () => {
  const db = dbWithBosses();
  const req = new Request("http://localhost/record-challenge-attempt", {
    method: "POST",
    // A client-supplied steam_id-like field must be ignored entirely --
    // there is no such field in the documented request shape, but this
    // guards against a future accidental read of an attacker-controlled body.
    body: JSON.stringify({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID, steam_id: "1" }),
  });
  await handleRecordChallengeAttempt(req, verifierSucceedingAs(STEAM_ID), db, 480);
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].challenger_steam_id, STEAM_ID, "must use the ticket-verified SteamID, not any client-supplied value");
});

Deno.test("non-POST requests are rejected", async () => {
  const req = new Request("http://localhost/record-challenge-attempt", { method: "GET" });
  const res = await handleRecordChallengeAttempt(req, verifierSucceedingAs(STEAM_ID), dbWithBosses(), 480);
  assertEquals(res.status, 405);
});

Deno.test("a malformed boss_id is rejected before touching Steam or the database", async () => {
  const db = dbWithBosses();
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: "not-a-uuid" }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  assertEquals(res.status, 400);
  assertEquals(db.rowsOf("boss_challenge_records").length, 0);
});

// 2026-10-22: 応答の by_owner（記録した本人がボスの作者か）。作者本人も挑戦でき、記録も今までどおり作られる。
Deno.test("the author can challenge their own boss and the attempt is reported as by_owner", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [{ id: PUBLISHED_BOSS_ID, boss_name: "作者のボス", is_published: true, owner_steam_id: STEAM_ID }]);
  const request = new Request("http://localhost/record-challenge-attempt", { method: "POST", body: JSON.stringify({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }) });
  const res = await handleRecordChallengeAttempt(request, verifierSucceedingAs(STEAM_ID), db, 480);
  assertEquals(res.status, 200);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body, { ok: true, challenge_count: 1, by_owner: true });
});

// 2026-10-23: 戦闘チケット。新しいゲームは want_battle_ticket を送り、最初の戦闘のチケットを同じ応答で受け取る。
Deno.test("with want_battle_ticket the first battle ticket comes back, bound to the verified player, the boss and its DB mode", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [{ id: PUBLISHED_BOSS_ID, boss_name: "公開ボス", is_published: true, revision: 3, payload: { draft_fields: { creator_mode: "advanced" } } }]);
  const res = await handleRecordChallengeAttempt(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID, want_battle_ticket: true, steam_id: "1", creator_mode: "simple" }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  assertEquals(res.status, 200);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.challenge_count, 1);
  assertEquals(typeof body.battle_ticket, "string");
  assertEquals(typeof body.ticket_expires_at, "string");
  assertEquals(body.ticket_status, undefined);
  const tickets = db.rowsOf("boss_battle_tickets");
  assertEquals(tickets.length, 1);
  assertEquals(tickets[0].id, body.battle_ticket);
  assertEquals(tickets[0].challenger_steam_id, STEAM_ID, "never the steam_id in the request");
  assertEquals(tickets[0].boss_id, PUBLISHED_BOSS_ID);
  assertEquals(tickets[0].creator_mode, "advanced", "the mode is the boss's mode in the DB, not the client's");
  assertEquals(tickets[0].boss_revision, 3);
});

Deno.test("an old game that does not ask for a battle ticket gets the same attempt response and no ticket is made", async () => {
  const db = dbWithBosses();
  const res = await handleRecordChallengeAttempt(postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }), verifierSucceedingAs(STEAM_ID), db, 480);
  assertEquals(await res.json(), { ok: true, challenge_count: 1, by_owner: false });
  assertEquals(db.rowsOf("boss_battle_tickets").length, 0);
});

Deno.test("when no ticket can be issued the attempt is still recorded and the reason is given (the battle is never blocked)", async () => {
  const limited = dbWithBosses();
  for (let i = 0; i < 60; i++) {
    await handleRecordChallengeAttempt(postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID, want_battle_ticket: true }), verifierSucceedingAs(STEAM_ID), limited, 480);
  }
  const res = await handleRecordChallengeAttempt(postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID, want_battle_ticket: true }), verifierSucceedingAs(STEAM_ID), limited, 480);
  assertEquals(res.status, 200);
  const body: RecordChallengeAttemptResponseBody = await res.json();
  assertEquals([body.ok, body.challenge_count, body.battle_ticket, body.ticket_status], [true, 61, undefined, "rate_limited"]);

  const failing = dbWithBosses();
  failing.failRpcCall("issue_boss_battle_ticket", 1);
  const failed = await handleRecordChallengeAttempt(postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID, want_battle_ticket: true }), verifierSucceedingAs(STEAM_ID), failing, 480);
  assertEquals(failed.status, 200);
  const text = await failed.text();
  assertEquals(JSON.parse(text), { ok: true, challenge_count: 1, by_owner: false, ticket_status: "error" });
  assertEquals(text.includes("fake failure"), false, "the DB's own message is not returned");
});
