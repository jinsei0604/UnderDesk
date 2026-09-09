import { assertEquals } from "jsr:@std/assert";
import { handleGetBoss, GetBossResponseBody } from "./index.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

const PUBLISHED_ID = "11111111-1111-1111-1111-111111111111";
const UNPUBLISHED_ID = "22222222-2222-2222-2222-222222222222";

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    {
      id: PUBLISHED_ID,
      boss_name: "公開ボス",
      author_name: "A",
      owner_steam_id: "1",
      revision: 1,
      published_at: "2026-01-01T00:00:00Z",
      payload: { schema_version: 1, battle_hash: "a".repeat(64) },
      is_published: true,
    },
    {
      id: UNPUBLISHED_ID,
      boss_name: "非公開ボス",
      author_name: "B",
      owner_steam_id: "2",
      revision: 1,
      published_at: "2026-01-01T00:00:00Z",
      payload: { schema_version: 1, battle_hash: "b".repeat(64) },
      is_published: false,
    },
  ]);
  return db;
}

Deno.test("returns the full payload for a published boss", async () => {
  const req = new Request(`http://localhost/get-boss?id=${PUBLISHED_ID}`, { method: "GET" });
  const res = await handleGetBoss(req, dbWithBosses());
  assertEquals(res.status, 200);
  const body: GetBossResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.boss!.payload.battle_hash, "a".repeat(64));
});

Deno.test("an unpublished boss is not found, even by direct id", async () => {
  const req = new Request(`http://localhost/get-boss?id=${UNPUBLISHED_ID}`, { method: "GET" });
  const res = await handleGetBoss(req, dbWithBosses());
  assertEquals(res.status, 404);
});

Deno.test("a non-existent id is not found", async () => {
  const req = new Request("http://localhost/get-boss?id=99999999-9999-9999-9999-999999999999", { method: "GET" });
  const res = await handleGetBoss(req, dbWithBosses());
  assertEquals(res.status, 404);
});

Deno.test("a malformed id is rejected before touching the DB", async () => {
  const db = dbWithBosses();
  const req = new Request("http://localhost/get-boss?id=not-a-uuid", { method: "GET" });
  const res = await handleGetBoss(req, db);
  assertEquals(res.status, 400);
});
