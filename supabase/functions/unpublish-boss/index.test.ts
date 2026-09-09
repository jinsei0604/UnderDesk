import { assertEquals } from "jsr:@std/assert";
import { handleUnpublish, UnpublishResponseBody } from "./index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "../steam-auth/steam_web_api_client.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

class StubSteamClient implements SteamWebApiClient {
  constructor(private readonly result: RawHttpResult) {}
  authenticateUserTicket(_p: AuthenticateUserTicketParams): Promise<RawHttpResult> {
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

const BOSS_ID = "11111111-1111-1111-1111-111111111111";

function dbWithOwnedBoss(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [{ id: BOSS_ID, owner_steam_id: "76561198000000001", is_published: true }]);
  return db;
}

async function postJson(payload: unknown): Promise<Request> {
  return new Request("http://localhost/unpublish-boss", { method: "POST", body: JSON.stringify(payload) });
}

Deno.test("the owner can unpublish their own boss", async () => {
  const db = dbWithOwnedBoss();
  const req = await postJson({ ticket: "4af203", boss_id: BOSS_ID });
  const res = await handleUnpublish(req, verifierSucceedingAs("76561198000000001"), db, 480);
  assertEquals(res.status, 200);
  const body: UnpublishResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(db.rowsOf("bosses")[0].is_published, false);
});

Deno.test("a non-owner cannot unpublish someone else's boss (ownership enforced, mock verified)", async () => {
  const db = dbWithOwnedBoss();
  const req = await postJson({ ticket: "4af203", boss_id: BOSS_ID });
  const res = await handleUnpublish(req, verifierSucceedingAs("99999999999999999"), db, 480);
  assertEquals(res.status, 403);
  const body: UnpublishResponseBody = await res.json();
  assertEquals(body.ok, false);
  assertEquals(body.error_kind, "forbidden");
  assertEquals(db.rowsOf("bosses")[0].is_published, true, "the boss must remain published after a rejected attempt");
});

Deno.test("unpublishing a non-existent boss_id is not_found", async () => {
  const db = dbWithOwnedBoss();
  const req = await postJson({ ticket: "4af203", boss_id: "00000000-0000-0000-0000-000000000000" });
  const res = await handleUnpublish(req, verifierSucceedingAs("76561198000000001"), db, 480);
  assertEquals(res.status, 404);
});

Deno.test("missing boss_id is a validation error", async () => {
  const db = dbWithOwnedBoss();
  const req = await postJson({ ticket: "4af203" });
  const res = await handleUnpublish(req, verifierSucceedingAs("1"), db, 480);
  assertEquals(res.status, 400);
});
