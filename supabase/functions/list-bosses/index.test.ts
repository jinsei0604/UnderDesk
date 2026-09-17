import { assertEquals } from "jsr:@std/assert";
import { handleListBosses, ListBossesResponseBody } from "./index.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

function dbWithBosses(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "1", boss_name: "古いボス", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: "2", boss_name: "新しいボス", author_name: "B", published_at: "2026-02-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced" } } },
    { id: "3", boss_name: "非公開ボス", author_name: "C", published_at: "2026-03-01T00:00:00Z", revision: 1, is_published: false, payload: { draft_fields: { creator_mode: "simple" } } },
  ]);
  return db;
}

function dbWithBossesMissingCreatorMode(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    // draft_fields自体が無い(旧形式)/creator_modeが無い/payloadが無い、の
    // いずれもSIMPLEへフォールバックすることを確認する。
    { id: "1", boss_name: "旧形式ボスA", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: {} } },
    { id: "2", boss_name: "旧形式ボスB", author_name: "B", published_at: "2026-02-01T00:00:00Z", revision: 1, is_published: true, payload: {} },
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

Deno.test("each summary row includes creator_mode extracted from payload.draft_fields", async () => {
  const req = new Request("http://localhost/list-bosses", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  const byName = new Map(body.bosses!.map((b) => [b.boss_name, b.creator_mode]));
  assertEquals(byName.get("古いボス"), "simple");
  assertEquals(byName.get("新しいボス"), "advanced");
});

Deno.test("creator_mode falls back to simple when draft_fields or creator_mode is missing", async () => {
  const req = new Request("http://localhost/list-bosses", { method: "GET" });
  const res = await handleListBosses(req, dbWithBossesMissingCreatorMode());
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 2);
  for (const boss of body.bosses!) {
    assertEquals(boss.creator_mode, "simple");
  }
});

Deno.test("mode=simple filters out advanced bosses", async () => {
  const req = new Request("http://localhost/list-bosses?mode=simple", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 1);
  assertEquals(body.bosses![0].boss_name, "古いボス");
});

Deno.test("mode=advanced filters out simple bosses", async () => {
  const req = new Request("http://localhost/list-bosses?mode=advanced", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 1);
  assertEquals(body.bosses![0].boss_name, "新しいボス");
});

Deno.test("an unrecognized mode value is ignored (no filter applied)", async () => {
  const req = new Request("http://localhost/list-bosses?mode=nonsense", { method: "GET" });
  const res = await handleListBosses(req, dbWithBosses());
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 2);
});

Deno.test("mode filter and limit compose correctly (limit applies after filtering)", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "1", boss_name: "S1", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced" } } },
    { id: "2", boss_name: "S2", author_name: "A", published_at: "2026-02-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: "3", boss_name: "S3", author_name: "A", published_at: "2026-03-01T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
  ]);
  // 新着順(published_at desc)はS3,S2,S1。limit=1をmode=simpleと組み合わせても、
  // advancedのS1に食われて0件になってはならない(先にmode絞り込み、その後limit)。
  const req = new Request("http://localhost/list-bosses?mode=simple&limit=1", { method: "GET" });
  const res = await handleListBosses(req, db);
  const body: ListBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 1);
  assertEquals(body.bosses![0].boss_name, "S3");
});
