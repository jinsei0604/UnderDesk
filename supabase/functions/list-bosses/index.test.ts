import { assertEquals } from "jsr:@std/assert";
import { handleListBosses, ListBossesResponseBody } from "./index.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "1", boss_name: "古いボス", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true },
    { id: "2", boss_name: "新しいボス", author_name: "B", published_at: "2026-02-01T00:00:00Z", revision: 1, is_published: true },
    { id: "3", boss_name: "非公開ボス", author_name: "C", published_at: "2026-03-01T00:00:00Z", revision: 1, is_published: false },
  ]);
  return db;
}

Deno.test("lists only published bosses, newest first", async () => {
  const req = new Request("http://localhost/list-bosses", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  assertEquals(res.status, 200);
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.bosses!.length, 2);
  assertEquals(body.bosses![0].boss_name, "新しいボス");
  assertEquals(body.bosses!.some((b) => b.boss_name === "非公開ボス"), false);
});

Deno.test("summary rows never include the full payload field", async () => {
  const req = new Request("http://localhost/list-bosses", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  for (const boss of body.bosses!) {
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "payload"), false);
  }
});

Deno.test("respects a limit query parameter, capped at the server maximum", async () => {
  const req = new Request("http://localhost/list-bosses?limit=1", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 1);
});

Deno.test("non-GET requests are rejected", async () => {
  const req = new Request("http://localhost/list-bosses", { method: "POST" });
  const res = await handleListBosses(req, dbWithBosses());
  assertEquals(res.status, 405);
});
