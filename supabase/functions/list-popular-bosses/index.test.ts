// Phase 6 — list-popular-bossesのmockテスト。実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/list-popular-bosses/

import { assertEquals } from "jsr:@std/assert";
import { handleListPopularBosses, ListPopularBossesResponseBody } from "./index.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

function req(query = ""): Request {
  return new Request(`http://localhost/list-popular-bosses${query}`, { method: "GET" });
}

function seedBoss(
  db: FakeSupabaseRestClient,
  id: string,
  name: string,
  publishedAt: string,
  mode: string = "simple",
  isPublished = true,
): void {
  db.seed("bosses", [{
    id,
    boss_name: name,
    author_name: "A",
    published_at: publishedAt,
    revision: 1,
    is_published: isPublished,
    payload: { draft_fields: { creator_mode: mode } },
  }]);
}

function seedChallengers(
  db: FakeSupabaseRestClient,
  bossId: string,
  challengers: { steamId: string; challengeCount: number; clearCount?: number }[],
): void {
  db.seed(
    "boss_challenge_records",
    challengers.map((c, i) => ({
      id: `${bossId}-rec-${i}`,
      boss_id: bossId,
      challenger_steam_id: c.steamId,
      challenge_count: c.challengeCount,
      clear_count: c.clearCount ?? 0,
    })),
  );
}

Deno.test("a boss with more unique challengers ranks higher", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "few", "少数人気ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "few", [{ steamId: "1", challengeCount: 1 }]);
  seedBoss(db, "many", "多数人気ボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "many", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["多数人気ボス", "少数人気ボス"]);
});

Deno.test("a tie on unique challengers is broken by total challenge count", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "low-total", "低総挑戦ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "low-total", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);
  seedBoss(db, "high-total", "高総挑戦ボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "high-total", [{ steamId: "1", challengeCount: 10 }, { steamId: "2", challengeCount: 10 }]);

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["高総挑戦ボス", "低総挑戦ボス"]);
});

Deno.test("a full tie falls back to published_at descending", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "older", "先に公開", "2026-01-01T00:00:00Z");
  seedChallengers(db, "older", [{ steamId: "1", challengeCount: 3 }]);
  seedBoss(db, "newer", "後で公開", "2026-02-01T00:00:00Z");
  seedChallengers(db, "newer", [{ steamId: "1", challengeCount: 3 }]);

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["後で公開", "先に公開"]);
});

Deno.test("one player challenging repeatedly never outranks a boss with more unique challengers", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "grinded", "連続挑戦ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "grinded", [{ steamId: "1", challengeCount: 500 }]); // 1 unique challenger, huge total
  seedBoss(db, "wide", "広く遊ばれたボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "wide", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]); // 2 unique

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["広く遊ばれたボス", "連続挑戦ボス"], "unique challenger count must win over one player's repeated attempts");
});

Deno.test("bosses with zero challenge records are included, ranked lowest", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "played", "遊ばれたボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "played", [{ steamId: "1", challengeCount: 1 }]);
  seedBoss(db, "unplayed", "未挑戦ボス", "2026-01-02T00:00:00Z");
  // no challenge records at all for "unplayed"

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  const names = body.bosses!.map((b) => b.boss_name);
  assertEquals(names.length, 2, "a boss with zero challenge history must not be excluded from the list");
  assertEquals(names[0], "遊ばれたボス");
  assertEquals(names[1], "未挑戦ボス");
});

Deno.test("mode=simple and mode=advanced filter correctly", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "s1", "SIMPLEボス", "2026-01-01T00:00:00Z", "simple");
  seedChallengers(db, "s1", [{ steamId: "1", challengeCount: 1 }]);
  seedBoss(db, "a1", "HARDCOREボス", "2026-01-02T00:00:00Z", "advanced");
  seedChallengers(db, "a1", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);

  const simpleRes = await handleListPopularBosses(req("?mode=simple"), db);
  const simpleBody: ListPopularBossesResponseBody = await simpleRes.json();
  assertEquals(simpleBody.bosses!.map((b) => b.boss_name), ["SIMPLEボス"]);

  const advancedRes = await handleListPopularBosses(req("?mode=advanced"), db);
  const advancedBody: ListPopularBossesResponseBody = await advancedRes.json();
  assertEquals(advancedBody.bosses!.map((b) => b.boss_name), ["HARDCOREボス"]);
});

Deno.test("unpublished bosses are excluded from the popular ranking", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "hidden", "非公開ボス", "2026-01-01T00:00:00Z", "simple", false);
  seedChallengers(db, "hidden", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 0);
});

Deno.test("no per-user data (challenger_steam_id or raw counts) ever appears in the response", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b1", "確認ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b1", [{ steamId: "76561198000000001", challengeCount: 3, clearCount: 1 }]);

  const res = await handleListPopularBosses(req(), db);
  const body: ListPopularBossesResponseBody = await res.json();
  const raw = JSON.stringify(body);
  assertEquals(raw.includes("76561198000000001"), false, "a Steam ID must never leak into the response");
  for (const boss of body.bosses!) {
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "challenger_steam_id"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "challenge_count"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "payload"), false);
  }
});

Deno.test("non-GET requests are rejected", async () => {
  const db = new FakeSupabaseRestClient();
  const res = await handleListPopularBosses(new Request("http://localhost/list-popular-bosses", { method: "POST" }), db);
  assertEquals(res.status, 405);
});

// ---------------------------------------------------------------------------
// 2026-10 — 公開中の全ボスが対象(新着50件だけにしない)・挑戦記録の全件取得・
// 表示用のユニーク挑戦者数。
// ---------------------------------------------------------------------------

function isoDay(day: number): string {
  return new Date(Date.UTC(2025, 0, 1) + day * 86_400_000).toISOString();
}

// boss-0000(最も古い)〜boss-NNNN(最も新しい)をcount件公開する。
function seedManyBosses(db: FakeSupabaseRestClient, count: number, prefix = "boss", mode = "simple", firstDay = 0): string[] {
  const ids: string[] = [];
  for (let i = 0; i < count; i++) {
    const id = `${prefix}-${String(i).padStart(4, "0")}`;
    seedBoss(db, id, id, isoDay(firstDay + i), mode);
    ids.push(id);
  }
  return ids;
}

// bossIdへ別々のプレイヤーn人分の記録を入れる(idは${idPrefix}-00000形式)。
function seedUniqueChallengers(db: FakeSupabaseRestClient, bossId: string, n: number, idOf: (i: number) => string): void {
  const rows = [];
  for (let i = 0; i < n; i++) {
    rows.push({ id: idOf(i), boss_id: bossId, challenger_steam_id: `${bossId}-p${i}`, challenge_count: 1, clear_count: 0 });
  }
  db.seed("boss_challenge_records", rows);
}

Deno.test("an old popular boss outside the newest 50 is still ranked first", async () => {
  const db = new FakeSupabaseRestClient();
  seedManyBosses(db, 60);
  seedChallengers(db, "boss-0000", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }, { steamId: "3", challengeCount: 1 }]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses![0].id, "boss-0000", "the oldest of 60 published bosses is the most popular one");
  assertEquals(body.bosses![0].unique_challengers, 3);
});

Deno.test("the top 20 of the ranking over every published boss is returned", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedManyBosses(db, 30);
  ids.forEach((id, i) => seedUniqueChallengers(db, id, i + 1, (n) => `${id}-r${String(n).padStart(3, "0")}`));

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.length, 20);
  assertEquals(body.bosses!.map((b) => b.id), ids.slice(10).reverse());
  assertEquals(body.bosses!.map((b) => b.unique_challengers), Array.from({ length: 20 }, (_, i) => 30 - i));
});

Deno.test("every challenge record counts even when the server returns at most 1000 rows per response", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedBoss(db, "a", "記録が多いボス", "2026-01-01T00:00:00Z");
  seedBoss(db, "b", "記録が少し少ないボス", "2026-01-02T00:00:00Z");
  // idを交互にして、最初の1000行だけだと両方500人ずつに見える並びにする。
  seedUniqueChallengers(db, "a", 1500, (i) => `rec-${String(i * 2).padStart(5, "0")}`);
  seedUniqueChallengers(db, "b", 1200, (i) => `rec-${String(i * 2 + 1).padStart(5, "0")}`);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => [b.id, b.unique_challengers]), [["a", 1500], ["b", 1200]]);
  const recordPages = db.selectCalls.filter((c) => c.table === "boss_challenge_records").length;
  assertEquals(recordPages, 4, "three pages of records and one empty page that ends the paging");
});

Deno.test("a server row cap smaller than the page size never ends the paging early", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(300);
  seedBoss(db, "a", "A", "2026-01-01T00:00:00Z");
  seedBoss(db, "b", "B", "2026-01-02T00:00:00Z");
  seedUniqueChallengers(db, "a", 1000, (i) => `rec-${String(i * 2).padStart(5, "0")}`);
  seedUniqueChallengers(db, "b", 999, (i) => `rec-${String(i * 2 + 1).padStart(5, "0")}`);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => [b.id, b.unique_challengers]), [["a", 1000], ["b", 999]]);
});

Deno.test("published bosses beyond the server's row cap are all ranked", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedManyBosses(db, 1200);
  seedChallengers(db, "boss-1150", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses![0].id, "boss-1150");
  assertEquals(body.bosses!.length, 20);
});

Deno.test("the mode filter applies to every published boss, not just the newest 50", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "old-hc", "古いHARDCORE", isoDay(0), "advanced");
  seedChallengers(db, "old-hc", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);
  seedManyBosses(db, 60, "simple", "simple", 10);
  seedBoss(db, "new-hc", "新しいHARDCORE", isoDay(100), "advanced");
  seedChallengers(db, "new-hc", [{ steamId: "1", challengeCount: 1 }]);

  const advanced: ListPopularBossesResponseBody = await (await handleListPopularBosses(req("?mode=advanced"), db)).json();
  assertEquals(advanced.bosses!.map((b) => b.id), ["old-hc", "new-hc"]);
  const simple: ListPopularBossesResponseBody = await (await handleListPopularBosses(req("?mode=simple"), db)).json();
  assertEquals(simple.bosses!.length, 20);
  assertEquals(simple.bosses!.every((b) => b.creator_mode === "simple"), true);
});

Deno.test("a failure on any page returns an error instead of a partial ranking", async () => {
  for (const [table, call] of [["boss_challenge_records", 2], ["bosses", 1]] as const) {
    const db = new FakeSupabaseRestClient();
    db.setMaxRowsPerResponse(1000);
    seedBoss(db, "a", "A", "2026-01-01T00:00:00Z");
    seedUniqueChallengers(db, "a", 1500, (i) => `rec-${String(i).padStart(5, "0")}`);
    db.failSelectCall(table, call);

    const res = await handleListPopularBosses(req(), db);
    const body: ListPopularBossesResponseBody = await res.json();
    assertEquals(res.status, 502, table);
    assertEquals(body.ok, false);
    assertEquals(body.error_kind, "db_error");
    assertEquals(body.bosses, undefined, `${table}: no partial ranking`);
  }
});

Deno.test("each row carries the unique challenger count for display and nothing per player", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "played", "遊ばれたボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "played", [
    { steamId: "76561198000000001", challengeCount: 500 },
    { steamId: "76561198000000002", challengeCount: 1 },
    { steamId: "76561198000000003", challengeCount: 2 },
  ]);
  seedBoss(db, "unplayed", "未挑戦ボス", "2026-01-02T00:00:00Z");

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => [b.id, b.unique_challengers]), [["played", 3], ["unplayed", 0]]);
  assertEquals(Object.keys(body.bosses![0]).sort(), ["appearance_id", "author_name", "boss_name", "creator_mode", "id", "published_at", "revision", "unique_challengers", "unique_clearers"]);
  assertEquals(JSON.stringify(body).includes("7656119800000000"), false);
});

Deno.test("a complete tie (challengers, total challenges and published_at) is ordered by id so the order never changes", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b-second", "B", "2026-01-01T00:00:00Z");
  seedBoss(db, "a-first", "A", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b-second", [{ steamId: "1", challengeCount: 2 }]);
  seedChallengers(db, "a-first", [{ steamId: "1", challengeCount: 2 }]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => b.id), ["a-first", "b-second"]);
});

// ---------------------------------------------------------------------------
// 2026-10 — カード用に、一度でもクリアした人数(クリア率の分子)と外見IDも返す。順位は変えない。
// ---------------------------------------------------------------------------

Deno.test("each popular row carries how many players cleared it at least once", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b1", "確認ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b1", [
    { steamId: "1", challengeCount: 4, clearCount: 2 },
    { steamId: "2", challengeCount: 1, clearCount: 0 },
    { steamId: "3", challengeCount: 2, clearCount: 1 },
  ]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals([body.bosses![0].unique_challengers, body.bosses![0].unique_clearers], [3, 2], "players, not clear counts");
});

Deno.test("the clearer count never changes the popular order", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "more-players", "多人数", "2026-01-01T00:00:00Z");
  seedChallengers(db, "more-players", [{ steamId: "1", challengeCount: 1 }, { steamId: "2", challengeCount: 1 }]);
  seedBoss(db, "more-clears", "クリア多数", "2026-01-02T00:00:00Z");
  seedChallengers(db, "more-clears", [{ steamId: "1", challengeCount: 1, clearCount: 9 }]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => b.id), ["more-players", "more-clears"]);
});

Deno.test("each popular row carries the appearance id from the payload (empty when missing)", async () => {
  const db = new FakeSupabaseRestClient();
  db.seed("bosses", [
    { id: "with", boss_name: "武者", author_name: "A", published_at: "2026-01-02T00:00:00Z", revision: 1, is_published: true, payload: { draft_fields: { creator_mode: "advanced", appearance_id: "appearance_musha" } } },
    { id: "without", boss_name: "外見なし", author_name: "A", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: {} },
  ]);

  const body: ListPopularBossesResponseBody = await (await handleListPopularBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => [b.id, b.appearance_id]), [["with", "appearance_musha"], ["without", ""]]);
});
