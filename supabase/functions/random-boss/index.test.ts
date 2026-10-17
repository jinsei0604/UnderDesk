import { assertEquals } from "jsr:@std/assert";
import { handleRandomBoss } from "./index.ts";
import { FakePostgrestClient } from "../_shared/fake_postgrest_client.ts";
import { DB_ERROR_PUBLIC_MESSAGE, PublicBossListResponseBody } from "../_shared/public_boss_query.ts";

const IDS = [
  "10000000-0000-4000-8000-000000000001",
  "20000000-0000-4000-8000-000000000002",
  "30000000-0000-4000-8000-000000000003",
  "40000000-0000-4000-8000-000000000004",
];

function db(): FakePostgrestClient {
  const fake = new FakePostgrestClient();
  fake.seed("bosses", [
    { id: IDS[0], boss_name: "A", author_name: "a", published_at: "2026-10-01T00:00:00+00:00", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "simple" } } },
    { id: IDS[1], boss_name: "B", author_name: "b", published_at: "2026-10-02T00:00:00+00:00", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced", appearance_id: "appearance_dragon" } } },
    { id: IDS[2], boss_name: "C", author_name: "c", published_at: "2026-10-03T00:00:00+00:00", revision: 1, is_published: true, payload: {} },
    { id: IDS[3], boss_name: "D", author_name: "d", published_at: "2026-10-04T00:00:00+00:00", revision: 1, is_published: false, payload: { draft_fields: { creator_mode: "advanced" } } },
  ]);
  fake.seed("boss_challenge_records", [{ id: "r1", boss_id: IDS[1], clear_count: 1 }]);
  return fake;
}

async function draw(fake: FakePostgrestClient, params: string, value: number): Promise<{ status: number; body: PublicBossListResponseBody }> {
  const res = await handleRandomBoss(new Request(`http://localhost/random-boss?${params}`, { method: "GET" }), fake, () => value);
  return { status: res.status, body: await res.json() };
}

Deno.test("every published boss can be drawn, each with an equal share of the random range", async () => {
  const picked: string[] = [];
  for (const value of [0, 0.34, 0.67, 0.999999]) {
    const { body } = await draw(db(), "", value);
    picked.push(body.bosses![0].boss_name);
  }
  assertEquals(picked, ["A", "B", "C", "C"], "公開中の3体を id 順に 1/3 ずつ。非公開は出ない");
});

Deno.test("mode draws only from that mode; a boss without creator_mode is SIMPLE", async () => {
  const simple = [(await draw(db(), "mode=simple", 0)).body.bosses![0].boss_name, (await draw(db(), "mode=simple", 0.9)).body.bosses![0].boss_name];
  assertEquals(simple, ["A", "C"]);
  const hard = await draw(db(), "mode=advanced", 0.5);
  assertEquals(hard.body.bosses![0].boss_name, "B");
  assertEquals(hard.body.bosses![0].creator_mode, "advanced");
  assertEquals(hard.body.bosses![0].unique_challengers, 1);
  assertEquals(hard.body.bosses![0].unique_clearers, 1);
});

Deno.test("exclude avoids the boss being shown, unless it is the only one", async () => {
  const other = await draw(db(), `exclude=${IDS[0]}`, 0);
  assertEquals(other.body.bosses![0].boss_name, "B");
  const only = await draw(db(), `mode=advanced&exclude=${IDS[1]}`, 0);
  assertEquals(only.body.bosses![0].boss_name, "B", "ほかに候補が無ければ同じボス");
});

Deno.test("no published boss returns an empty list, not an error", async () => {
  const fake = new FakePostgrestClient();
  const { status, body } = await draw(fake, "mode=advanced", 0.5);
  assertEquals(status, 200);
  assertEquals(body.ok, true);
  assertEquals(body.bosses, []);
});

Deno.test("reads one counted number and one row, never the whole table or the payload", async () => {
  const fake = db();
  await draw(fake, "mode=simple", 0.5);
  assertEquals(fake.countCalls.length, 1);
  const bossQueries = fake.selectCalls.filter((c) => c.table === "bosses");
  assertEquals(bossQueries.length, 1);
  const params = new URLSearchParams(bossQueries[0].query);
  assertEquals(params.get("limit"), "1");
  assertEquals(params.get("select")!.split(",").includes("payload"), false);
});

Deno.test("if the drawn position vanished after counting, counts again once", async () => {
  const fake = db();
  fake.afterCount = () => fake.remove("bosses", (row) => row.id === IDS[2]);
  const { body } = await draw(fake, "", 0.9);
  assertEquals(body.bosses![0].boss_name, "B", "数え直して、残った2体から選ぶ");
  assertEquals(fake.countCalls.length, 2);
});

Deno.test("database failures return db_error", async () => {
  const countFail = db();
  countFail.fail("count", "bosses", 1);
  assertEquals((await draw(countFail, "", 0)).status, 502);
  const selectFail = db();
  selectFail.fail("select", "bosses", 1);
  assertEquals((await draw(selectFail, "", 0)).body.error_kind, "db_error");
  const post = await handleRandomBoss(new Request("http://localhost/random-boss", { method: "POST" }), db());
  assertEquals(post.status, 405);
});

Deno.test("only published bosses are counted and drawn, with card fields only", async () => {
  const fake = db();
  for (const value of [0, 0.5, 0.99]) {
    const { body } = await draw(fake, "", value);
    assertEquals(body.bosses![0].boss_name === "D", false, "非公開は引かない");
    assertEquals(Object.keys(body.bosses![0]).sort(), ["appearance_id", "author_name", "boss_name", "creator_mode", "id", "published_at", "revision", "unique_challengers", "unique_clearers"]);
  }
  for (const call of [...fake.countCalls, ...fake.selectCalls.filter((c) => c.table === "bosses")]) {
    assertEquals(new URLSearchParams(call.query).get("is_published"), "eq.true");
  }
  const bad = await draw(db(), `exclude=${encodeURIComponent("x,id.gt.0")}&mode=${encodeURIComponent("simple),or(")}`, 0);
  assertEquals(bad.status, 200, "形の違う exclude・mode は使わない（絞り込みに入れない）");
});

Deno.test("database error details stay in the log, not in the response", async () => {
  for (const [kind, table] of [["count", "bosses"], ["select", "bosses"], ["select", "boss_challenge_records"]] as const) {
    const fake = db();
    fake.fail(kind, table, 1);
    const res = await handleRandomBoss(new Request("http://localhost/random-boss", { method: "GET" }), fake, () => 0.5);
    const text = await res.text();
    assertEquals(res.status, 502);
    assertEquals(text.includes("owner_steam_id") || text.includes("42703"), false, "DBの内部の文を返さない");
    assertEquals(JSON.parse(text).message, DB_ERROR_PUBLIC_MESSAGE);
  }
});
