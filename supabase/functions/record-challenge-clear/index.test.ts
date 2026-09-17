// Phase 5 — record-challenge-clearのmockテスト。実Steam/実Supabaseへは
// 一切出ない。実行方法: deno test supabase/functions/record-challenge-clear/

import { assertEquals } from "jsr:@std/assert";
import { handleRecordChallengeClear, RecordChallengeClearResponseBody } from "./index.ts";
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
const VALID_HEX_TICKET = "aabbcc";
const STEAM_ID = "76561198000000001";

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: PUBLISHED_BOSS_ID, boss_name: "公開ボス", is_published: true },
  ]);
  return db;
}

function postJson(payload: unknown): Request {
  return new Request("http://localhost/record-challenge-clear", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

Deno.test("valid ticket records the clear", async () => {
  const res = await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    dbWithBosses(),
    480,
  );
  assertEquals(res.status, 200);
  const body: RecordChallengeClearResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.clear_count, 1);
});

Deno.test("invalid ticket is rejected and never touches the database", async () => {
  const db = dbWithBosses();
  const res = await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierRejectingTicket(),
    db,
    480,
  );
  assertEquals(res.status, 401);
  const body: RecordChallengeClearResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "invalid_ticket");
  assertEquals(db.rowsOf("boss_challenge_records").length, 0);
});

Deno.test("the first clear creates a new record with clear_count=1 and no attempt record required", async () => {
  const db = dbWithBosses();
  await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].clear_count, 1);
  assertEquals(rows[0].challenge_count, 0, "clearing without a prior attempt must not fabricate a challenge_count");
  assertEquals(typeof rows[0].first_cleared_at, "string");
});

Deno.test("multiple clears increment clear_count on the same row", async () => {
  const db = dbWithBosses();
  await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const secondResponse = await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const body: RecordChallengeClearResponseBody = await secondResponse.json();
  assertEquals(body.clear_count, 2);
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1);
  assertEquals(rows[0].clear_count, 2);
});

Deno.test("clearing after a prior attempt preserves the existing challenge_count instead of resetting it", async () => {
  const db = dbWithBosses();
  db.seed("boss_challenge_records", [
    {
      id: "existing-1",
      boss_id: PUBLISHED_BOSS_ID,
      challenger_steam_id: STEAM_ID,
      challenge_count: 3,
      clear_count: 0,
      first_challenged_at: "2026-01-01T00:00:00Z",
      last_challenged_at: "2026-01-03T00:00:00Z",
      first_cleared_at: null,
      last_cleared_at: null,
    },
  ]);
  await handleRecordChallengeClear(
    postJson({ ticket: VALID_HEX_TICKET, boss_id: PUBLISHED_BOSS_ID }),
    verifierSucceedingAs(STEAM_ID),
    db,
    480,
  );
  const rows = db.rowsOf("boss_challenge_records");
  assertEquals(rows.length, 1, "must update the existing attempt row, not create a second one");
  assertEquals(rows[0].challenge_count, 3, "the existing attempt count must be preserved");
  assertEquals(rows[0].clear_count, 1);
});

Deno.test("non-POST requests are rejected", async () => {
  const req = new Request("http://localhost/record-challenge-clear", { method: "GET" });
  const res = await handleRecordChallengeClear(req, verifierSucceedingAs(STEAM_ID), dbWithBosses(), 480);
  assertEquals(res.status, 405);
});
