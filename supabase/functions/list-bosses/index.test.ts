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

// ---------------------------------------------------------------------------
// 2026-10 — 公開中の全ボスが対象(新しい50件だけにしない)・cursorによるページ送り。
// ---------------------------------------------------------------------------

function isoDay(day: number): string {
  return new Date(Date.UTC(2025, 0, 1) + day * 86_400_000).toISOString();
}

// b-0000(最も古い)〜b-NNNN(最も新しい)をcount件公開する。sameTimeなら全部同じ公開日時。
function seedMany(
  db: FakeSupabaseRestClient,
  count: number,
  options: { prefix?: string; mode?: string; firstDay?: number; sameTime?: boolean } = {},
): string[] {
  const prefix = options.prefix ?? "b";
  const firstDay = options.firstDay ?? 0;
  const ids: string[] = [];
  const rows = [];
  for (let i = 0; i < count; i++) {
    const id = `${prefix}-${String(i).padStart(4, "0")}`;
    rows.push({
      id,
      boss_name: id,
      author_name: "A",
      published_at: isoDay(options.sameTime ? firstDay : firstDay + i),
      revision: 1,
      is_published: true,
      payload: { draft_fields: { creator_mode: options.mode ?? "simple" } },
    });
    ids.push(id);
  }
  db.seed("bosses", rows);
  return ids;
}

async function page(db: FakeSupabaseRestClient, query: string): Promise<{ status: number; body: ListBossesResponseBody }> {
  const res = await handleListBosses(new Request(`http://localhost/list-bosses${query}`, { method: "GET" }), db);
  return { status: res.status, body: await res.json() };
}

// cursorで最後のページまでたどり、返ったidを順に集める。
async function walkAllPages(db: FakeSupabaseRestClient, baseQuery: string): Promise<{ ids: string[]; pages: ListBossesResponseBody[] }> {
  const ids: string[] = [];
  const pages: ListBossesResponseBody[] = [];
  let cursor = "";
  for (let guard = 0; guard < 100; guard++) {
    const sep = baseQuery.includes("?") ? "&" : "?";
    const { body } = await page(db, cursor === "" ? baseQuery : `${baseQuery}${sep}cursor=${encodeURIComponent(cursor)}`);
    pages.push(body);
    ids.push(...body.bosses!.map((b) => b.id));
    if (!body.has_more) break;
    cursor = body.next_cursor!;
  }
  return { ids, pages };
}

function base64Url(text: string): string {
  return btoa(text).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

Deno.test("the first page without a cursor is still the newest 20, now with has_more and next_cursor", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedMany(db, 45);
  const { status, body } = await page(db, "");
  assertEquals(status, 200);
  assertEquals(body.bosses!.map((b) => b.id), ids.slice(25).reverse());
  assertEquals(body.has_more, true);
  assertEquals(typeof body.next_cursor, "string");
});

Deno.test("a cursor returns the next 20, then the last 5 with has_more=false and no next_cursor", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedMany(db, 45);
  const first = await page(db, "?limit=20");
  const second = await page(db, `?limit=20&cursor=${first.body.next_cursor}`);
  assertEquals(second.body.bosses!.map((b) => b.id), ids.slice(5, 25).reverse());
  assertEquals(second.body.has_more, true);
  const third = await page(db, `?limit=20&cursor=${second.body.next_cursor}`);
  assertEquals(third.body.bosses!.map((b) => b.id), ids.slice(0, 5).reverse());
  assertEquals(third.body.has_more, false);
  assertEquals(Object.prototype.hasOwnProperty.call(third.body, "next_cursor"), false);
  const firstIds = new Set(first.body.bosses!.map((b) => b.id));
  assertEquals(second.body.bosses!.some((b) => firstIds.has(b.id)), false, "no boss repeats between page 1 and page 2");
});

Deno.test("more than 100 published bosses (and a server row cap) can all be browsed page by page", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  const ids = seedMany(db, 1234);
  const { ids: seen, pages } = await walkAllPages(db, "?limit=50");
  assertEquals(seen.length, 1234);
  assertEquals(new Set(seen).size, 1234, "no duplicates across pages");
  assertEquals(seen, [...ids].reverse(), "newest first all the way down");
  assertEquals(pages[pages.length - 1].has_more, false);
});

Deno.test("an old HARDCORE boss outside the newest 50 is still listed under mode=advanced", async () => {
  const db = new FakeSupabaseRestClient();
  const old = seedMany(db, 3, { prefix: "old-hc", mode: "advanced", firstDay: 0 });
  seedMany(db, 60, { prefix: "new-simple", mode: "simple", firstDay: 10 });
  const { body } = await page(db, "?mode=advanced");
  assertEquals(body.bosses!.map((b) => b.id), [...old].reverse());
  assertEquals(body.has_more, false);
});

Deno.test("each mode pages through only its own bosses, and changing mode starts again from the top", async () => {
  const db = new FakeSupabaseRestClient();
  const simple = seedMany(db, 30, { prefix: "s", mode: "simple", firstDay: 0 });
  const advanced = seedMany(db, 25, { prefix: "a", mode: "advanced", firstDay: 100 });
  const simpleWalk = await walkAllPages(db, "?mode=simple&limit=20");
  assertEquals(simpleWalk.ids, [...simple].reverse());
  const advancedWalk = await walkAllPages(db, "?mode=advanced&limit=20");
  assertEquals(advancedWalk.ids, [...advanced].reverse());
  const all = await walkAllPages(db, "?limit=20");
  assertEquals(all.ids, [...advanced].reverse().concat([...simple].reverse()));
});

Deno.test("bosses with the same published_at are ordered by id and split across pages without overlap", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedMany(db, 30, { sameTime: true });
  const { ids: seen } = await walkAllPages(db, "?limit=7");
  assertEquals(seen, [...ids].sort(), "same timestamp -> id ascending, every boss exactly once");
});

Deno.test("a boss published while browsing never duplicates or skips rows on the next page", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedMany(db, 30);
  const first = await page(db, "?limit=10");
  seedMany(db, 1, { prefix: "brand-new", firstDay: 999 });
  const second = await page(db, `?limit=10&cursor=${first.body.next_cursor}`);
  assertEquals(second.body.bosses!.map((b) => b.id), ids.slice(10, 20).reverse(), "page 2 continues exactly where page 1 ended");
  const top = await page(db, "?limit=10");
  assertEquals(top.body.bosses![0].id, "brand-new-0000", "the new boss shows up at the top of a fresh first page");
});

Deno.test("an invalid cursor is rejected with 400 instead of silently restarting from the top", async () => {
  const db = new FakeSupabaseRestClient();
  seedMany(db, 30);
  const badCursors = [
    "not a cursor!",
    "%%%",
    base64Url("{}"),
    base64Url(JSON.stringify({ p: "x", i: "b-0001" })),
    base64Url(JSON.stringify({ p: 1, i: "" })),
    base64Url("[1,2]"),
    base64Url("nope"),
  ];
  for (const bad of badCursors) {
    const { status, body } = await page(db, `?cursor=${encodeURIComponent(bad)}`);
    assertEquals(status, 400, bad);
    assertEquals(body.ok, false);
    assertEquals(body.error_kind, "invalid_request");
    assertEquals(body.bosses, undefined);
  }
  const empty = await page(db, "?cursor=");
  assertEquals(empty.status, 200, "an empty cursor means the first page");
  assertEquals(empty.body.bosses!.length, 20);
});

Deno.test("limit boundaries: default 20, capped at 50, fractions floored, junk ignored", async () => {
  const db = new FakeSupabaseRestClient();
  seedMany(db, 80);
  const cases: [string, number][] = [["?limit=0", 20], ["?limit=-5", 20], ["?limit=abc", 20], ["?limit=51", 50], ["?limit=50", 50], ["?limit=1", 1], ["?limit=2.7", 2], ["", 20]];
  for (const [query, expected] of cases) {
    const { body } = await page(db, query);
    assertEquals(body.bosses!.length, expected, query);
    assertEquals(body.has_more, true, query);
  }
});

Deno.test("a failure on any page of the scan returns an error instead of a partial list", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedMany(db, 1500);
  db.failSelectCall("bosses", 2);
  const { status, body } = await page(db, "");
  assertEquals(status, 502);
  assertEquals(body.error_kind, "db_error");
  assertEquals(body.bosses, undefined);
});

// ---------------------------------------------------------------------------
// 2026-10 — カード用の項目: 外見IDと、このページのボスの挑戦者数・クリア者数。
// ---------------------------------------------------------------------------

Deno.test("each row carries the appearance id and the challenger/clearer counts for the boss card", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "b1", boss_name: "竜", author_name: "A", published_at: isoDay(2), revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced", appearance_id: "appearance_dragon" } } },
    { id: "b2", boss_name: "外見なし", author_name: "A", published_at: isoDay(1), revision: 1, is_published: true, payload: { draft_fields: {} } },
  ]);
  db.seed("boss_challenge_records", [
    { id: "r1", boss_id: "b1", challenger_steam_id: "76561198000000011", challenge_count: 3, clear_count: 1 },
    { id: "r2", boss_id: "b1", challenger_steam_id: "76561198000000012", challenge_count: 1, clear_count: 0 },
    { id: "r3", boss_id: "b1", challenger_steam_id: "76561198000000013", challenge_count: 2, clear_count: 5 },
  ]);

  const { status, body } = await page(db, "");
  assertEquals(status, 200);
  assertEquals(
    body.bosses!.map((b) => [b.id, b.appearance_id, b.unique_challengers, b.unique_clearers]),
    [["b1", "appearance_dragon", 3, 2], ["b2", "", 0, 0]],
    "players who cleared at least once, not clear counts; no records means 0",
  );
  assertEquals(JSON.stringify(body).includes("7656119800000001"), false, "no player id leaks");
  assertEquals(Object.prototype.hasOwnProperty.call(body.bosses![0], "payload"), false);
});

Deno.test("only the challenge records of the bosses on the returned page are read", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedMany(db, 30);
  db.seed("boss_challenge_records", ids.map((bossId, i) => ({ id: `r-${i}`, boss_id: bossId, challenger_steam_id: `p-${i}`, challenge_count: 1, clear_count: i % 2 })));

  const { body } = await page(db, "?limit=10");
  const recordQueries = db.selectCalls.filter((call) => call.table === "boss_challenge_records");
  assertEquals(recordQueries.length > 0, true);
  const pageIds = body.bosses!.map((b) => b.id).sort();
  for (const query of recordQueries) {
    const asked = decodeURIComponent(query.query).match(/boss_id=in\.\(([^)]*)\)/)![1].split(",");
    assertEquals(asked.sort(), pageIds, "every records query is limited to the 10 bosses on this page, not all 30");
  }
  assertEquals(body.bosses!.every((b) => b.unique_challengers === 1), true);
});

Deno.test("every record of a page boss counts even beyond the server row cap", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedMany(db, 1);
  db.seed("boss_challenge_records", Array.from({ length: 1500 }, (_, i) => ({ id: `r-${String(i).padStart(5, "0")}`, boss_id: "b-0000", challenger_steam_id: `p-${i}`, challenge_count: 1, clear_count: i < 300 ? 1 : 0 })));

  const { body } = await page(db, "");
  assertEquals([body.bosses![0].unique_challengers, body.bosses![0].unique_clearers], [1500, 300]);
});

Deno.test("an empty page reads no challenge records", async () => {
  const db = new FakeSupabaseRestClient();
  const { body } = await page(db, "");
  assertEquals(body.bosses, []);
  assertEquals(db.selectCalls.filter((call) => call.table === "boss_challenge_records").length, 0);
});

Deno.test("a failure while counting challengers returns an error instead of rows showing 0", async () => {
  const db = new FakeSupabaseRestClient();
  seedMany(db, 5);
  db.failSelectCall("boss_challenge_records", 1);
  const { status, body } = await page(db, "");
  assertEquals(status, 502);
  assertEquals(body.error_kind, "db_error");
  assertEquals(body.bosses, undefined);
});
