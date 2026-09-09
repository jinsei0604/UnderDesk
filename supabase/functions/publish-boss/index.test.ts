// Phase 4C — publish-bossのmockテスト。実Steam/実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/publish-boss/

import { assertEquals } from "jsr:@std/assert";
import { handlePublish, PublishResponseBody } from "./index.ts";
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

function verifierNotConfigured(): SteamTicketVerifier {
  return new SteamTicketVerifier({
    client: new StubSteamClient({ status: 200, body: "" }),
    publisherWebApiKey: undefined,
  });
}

function freshDb(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.addUniqueConstraint({ table: "bosses", columns: ["idempotency_key"] });
  return db;
}

const VALID_HASH = "a".repeat(64);

function validPayload(overrides: Record<string, unknown> = {}) {
  return {
    schema_version: 1,
    boss_name: "テストボス",
    author_name: "作者A",
    draft_fields: { hp: 1000, atk: 100, spd: 50 },
    clear_check_success_snapshot: { hp: 1000 },
    battle_hash: VALID_HASH,
    ...overrides,
  };
}

async function postJson(payload: unknown): Promise<Request> {
  return new Request("http://localhost/publish-boss", {
    method: "POST",
    body: JSON.stringify(payload),
  });
}

Deno.test("a well-formed first-time publish inserts a new row with revision 1", async () => {
  const db = freshDb();
  const req = await postJson({ ticket: "4af203", payload: validPayload() });
  const res = await handlePublish(req, verifierSucceedingAs("76561198000000001"), db, 480);
  assertEquals(res.status, 201);
  const body: PublishResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.revision, 1);
  assertEquals(db.rowsOf("bosses").length, 1);
  assertEquals(db.rowsOf("bosses")[0].owner_steam_id, "76561198000000001");
});

Deno.test("missing ticket is rejected before touching Steam or the DB", async () => {
  const db = freshDb();
  const req = await postJson({ payload: validPayload() });
  const res = await handlePublish(req, verifierSucceedingAs("1"), db, 480);
  assertEquals(res.status, 400);
  assertEquals(db.rowsOf("bosses").length, 0);
});

Deno.test("invalid payload shape (missing battle_hash) is rejected", async () => {
  const db = freshDb();
  const payload = validPayload();
  delete (payload as Record<string, unknown>).battle_hash;
  const req = await postJson({ ticket: "4af203", payload });
  const res = await handlePublish(req, verifierSucceedingAs("1"), db, 480);
  assertEquals(res.status, 400);
});

Deno.test("Steam auth failure is surfaced and nothing is written", async () => {
  const db = freshDb();
  const req = await postJson({ ticket: "4af203", payload: validPayload() });
  const failingVerifier = new SteamTicketVerifier({
    client: new StubSteamClient({ status: 200, body: JSON.stringify({ response: { error: { errordesc: "bad ticket" } } }) }),
    publisherWebApiKey: "dummy-test-key",
  });
  const res = await handlePublish(req, failingVerifier, db, 480);
  assertEquals(res.status, 401);
  const body: PublishResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(db.rowsOf("bosses").length, 0);
});

Deno.test("without STEAM_PUBLISHER_WEB_API_KEY, publish never succeeds (not a silent bypass)", async () => {
  const db = freshDb();
  const req = await postJson({ ticket: "4af203", payload: validPayload() });
  const res = await handlePublish(req, verifierNotConfigured(), db, 480);
  assertEquals(res.status, 503);
  const body: PublishResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "not_configured");
  assertEquals(db.rowsOf("bosses").length, 0);
});

Deno.test("a duplicate publish request (same owner/battle_hash/revision) is idempotent, not a duplicate row", async () => {
  const db = freshDb();
  const req1 = await postJson({ ticket: "4af203", payload: validPayload() });
  const res1 = await handlePublish(req1, verifierSucceedingAs("76561198000000001"), db, 480);
  const body1: PublishResponseBody = await res1.json();

  const req2 = await postJson({ ticket: "4af203", payload: validPayload() });
  const res2 = await handlePublish(req2, verifierSucceedingAs("76561198000000001"), db, 480);
  const body2: PublishResponseBody = await res2.json();

  assertEquals(body1.boss_id, body2.boss_id);
  assertEquals(db.rowsOf("bosses").length, 1, "a repeated identical publish must not create a second row");
});

Deno.test("republishing an existing boss_id as its owner bumps the revision", async () => {
  const db = freshDb();
  const req1 = await postJson({ ticket: "4af203", payload: validPayload() });
  const res1 = await handlePublish(req1, verifierSucceedingAs("76561198000000001"), db, 480);
  const body1: PublishResponseBody = await res1.json();

  const req2 = await postJson({
    ticket: "4af203",
    boss_id: body1.boss_id,
    payload: validPayload({ battle_hash: "b".repeat(64) }),
  });
  const res2 = await handlePublish(req2, verifierSucceedingAs("76561198000000001"), db, 480);
  const body2: PublishResponseBody = await res2.json();

  assertEquals(body2.ok, true);
  assertEquals(body2.revision, 2);
  assertEquals(db.rowsOf("bosses").length, 1);
});

Deno.test("resending an identical republish request (lost response) does not double-bump the revision", async () => {
  const db = freshDb();
  const req1 = await postJson({ ticket: "4af203", payload: validPayload() });
  const res1 = await handlePublish(req1, verifierSucceedingAs("76561198000000001"), db, 480);
  const body1: PublishResponseBody = await res1.json();

  const republishPayload = validPayload({ battle_hash: "b".repeat(64) });

  // First republish attempt: the server applies it (revision 1 -> 2) but we
  // simulate the client never receiving this response (e.g. dropped
  // connection) by not asserting on it here and instead resending below.
  const req2 = await postJson({ ticket: "4af203", boss_id: body1.boss_id, payload: republishPayload });
  const res2 = await handlePublish(req2, verifierSucceedingAs("76561198000000001"), db, 480);
  const body2: PublishResponseBody = await res2.json();
  assertEquals(body2.revision, 2);

  // Client resends the exact same logical request (same boss_id, same
  // payload content) because it never saw res2. This must be treated as an
  // idempotent replay, not a fresh republish.
  const req3 = await postJson({ ticket: "4af203", boss_id: body1.boss_id, payload: republishPayload });
  const res3 = await handlePublish(req3, verifierSucceedingAs("76561198000000001"), db, 480);
  const body3: PublishResponseBody = await res3.json();

  assertEquals(body3.ok, true);
  assertEquals(body3.revision, 2, "a resent identical republish must not advance revision to 3");
  assertEquals(db.rowsOf("bosses").length, 1);
  assertEquals(db.rowsOf("bosses")[0].revision, 2);
});

Deno.test("republishing someone else's boss_id is forbidden, ownership is enforced", async () => {
  const db = freshDb();
  const req1 = await postJson({ ticket: "4af203", payload: validPayload() });
  const res1 = await handlePublish(req1, verifierSucceedingAs("76561198000000001"), db, 480);
  const body1: PublishResponseBody = await res1.json();

  const req2 = await postJson({
    ticket: "4af203",
    boss_id: body1.boss_id,
    payload: validPayload({ battle_hash: "c".repeat(64) }),
  });
  const res2 = await handlePublish(req2, verifierSucceedingAs("99999999999999999"), db, 480);
  assertEquals(res2.status, 403);
  const body2: PublishResponseBody = await res2.json();
  assertEquals(body2.ok, false);
  assertEquals(body2.error_kind, "forbidden");
});

Deno.test("republishing a non-existent boss_id is not_found", async () => {
  const db = freshDb();
  const req = await postJson({ ticket: "4af203", boss_id: "00000000-0000-0000-0000-000000000000", payload: validPayload() });
  const res = await handlePublish(req, verifierSucceedingAs("1"), db, 480);
  assertEquals(res.status, 404);
});

Deno.test("payload larger than the size limit is rejected", async () => {
  const db = freshDb();
  const oversized = validPayload({ draft_fields: { blob: "x".repeat(300000) } });
  const req = await postJson({ ticket: "4af203", payload: oversized });
  const res = await handlePublish(req, verifierSucceedingAs("1"), db, 480);
  assertEquals(res.status, 413);
});
