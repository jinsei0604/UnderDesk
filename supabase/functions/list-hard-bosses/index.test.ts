// Phase 6 — list-hard-bossesのmockテスト。実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/list-hard-bosses/

import { assertEquals } from "jsr:@std/assert";
import { handleListHardBosses, ListHardBossesResponseBody } from "./index.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

function req(query = ""): Request {
  return new Request(`http://localhost/list-hard-bosses${query}`, { method: "GET" });
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
  count: number,
  clearedCount: number,
): void {
  const rows = [];
  for (let i = 0; i < count; i++) {
    rows.push({
      id: `${bossId}-rec-${i}`,
      boss_id: bossId,
      challenger_steam_id: `steam-${bossId}-${i}`,
      challenge_count: 1,
      clear_count: i < clearedCount ? 1 : 0,
    });
  }
  db.seed("boss_challenge_records", rows);
}

Deno.test("a boss with 4 or fewer unique challengers is excluded entirely", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "few", "少数挑戦ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "few", 4, 0);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 0, "fewer than 5 unique challengers must be excluded, not just ranked low");
});

Deno.test("a boss with exactly 5 unique challengers is included", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "five", "五人挑戦ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "five", 5, 0);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 1);
  assertEquals(body.bosses![0].boss_name, "五人挑戦ボス");
});

Deno.test("a lower corrected clear rate ranks first (harder)", async () => {
  const db = new FakeSupabaseRestClient();
  // 5 challengers, 0 clears -> (0+1)/(5+2) = 1/7 ≈ 0.143
  seedBoss(db, "hard", "高難度ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "hard", 5, 0);
  // 10 challengers, 2 clears -> (2+1)/(10+2) = 3/12 = 0.25
  seedBoss(db, "easier", "やや易しいボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "easier", 10, 2);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["高難度ボス", "やや易しいボス"]);
});

Deno.test("clear_count > 0 is counted once per player, not by total clear count", async () => {
  const db = new FakeSupabaseRestClient();
  // One boss: 5 unique challengers, one of whom cleared it many times (clear_count=50)
  // must count as exactly 1 unique clearer, not 50.
  db.seed("bosses", [{
    id: "grinded-clear",
    boss_name: "多重クリアボス",
    author_name: "A",
    published_at: "2026-01-01T00:00:00Z",
    revision: 1,
    is_published: true,
    payload: { draft_fields: { creator_mode: "simple" } },
  }]);
  db.seed("boss_challenge_records", [
    { id: "r0", boss_id: "grinded-clear", challenger_steam_id: "s0", challenge_count: 1, clear_count: 50 },
    { id: "r1", boss_id: "grinded-clear", challenger_steam_id: "s1", challenge_count: 1, clear_count: 0 },
    { id: "r2", boss_id: "grinded-clear", challenger_steam_id: "s2", challenge_count: 1, clear_count: 0 },
    { id: "r3", boss_id: "grinded-clear", challenger_steam_id: "s3", challenge_count: 1, clear_count: 0 },
    { id: "r4", boss_id: "grinded-clear", challenger_steam_id: "s4", challenge_count: 1, clear_count: 0 },
  ]);
  // Comparison boss: 5 unique challengers, 1 unique clearer each cleared once
  // -- must produce the identical corrected clear rate as the boss above
  // ((1+1)/(5+2) both), proving clear_count magnitude is irrelevant.
  seedBoss(db, "single-clear", "単純クリアボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "single-clear", 5, 1);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 2, "both bosses must qualify (5 unique challengers each)");
  // Equal corrected clear rate -> tie-break by unique challengers (equal too, 5 each)
  // -> tie-break by published_at desc -> 単純クリアボス(newer) first.
  assertEquals(body.bosses!.map((b) => b.boss_name), ["単純クリアボス", "多重クリアボス"]);
});

Deno.test("a tie on corrected clear rate is broken by more unique challengers first", async () => {
  const db = new FakeSupabaseRestClient();
  // (1+1)/(5+2) = 2/7 ≈ 0.2857
  seedBoss(db, "small", "少人数タイボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "small", 5, 1);
  // (3+1)/(19+2) = 4/21 ≈ 0.1905 -- not equal, use a genuinely matching tie instead:
  // (2+1)/(12+2) = 3/14 ≈ 0.2143, not equal either. Construct an exact tie:
  // (1+1)/(5+2) = 2/7. Need another with more challengers at the same ratio:
  // (3+1)/(12+2) = 4/14 = 2/7. Equal!
  seedBoss(db, "big", "多人数タイボス", "2026-01-02T00:00:00Z");
  seedChallengers(db, "big", 12, 3);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.map((b) => b.boss_name), ["多人数タイボス", "少人数タイボス"], "equal corrected clear rate must be broken by more unique challengers first");
});

Deno.test("mode=simple and mode=advanced filter correctly", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "s1", "SIMPLE高難度ボス", "2026-01-01T00:00:00Z", "simple");
  seedChallengers(db, "s1", 5, 0);
  seedBoss(db, "a1", "HARDCORE高難度ボス", "2026-01-02T00:00:00Z", "advanced");
  seedChallengers(db, "a1", 5, 0);

  const simpleRes = await handleListHardBosses(req("?mode=simple"), db);
  const simpleBody: ListHardBossesResponseBody = await simpleRes.json();
  assertEquals(simpleBody.bosses!.map((b) => b.boss_name), ["SIMPLE高難度ボス"]);

  const advancedRes = await handleListHardBosses(req("?mode=advanced"), db);
  const advancedBody: ListHardBossesResponseBody = await advancedRes.json();
  assertEquals(advancedBody.bosses!.map((b) => b.boss_name), ["HARDCORE高難度ボス"]);
});

Deno.test("unpublished bosses are excluded even with 5+ challengers", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "hidden", "非公開高難度ボス", "2026-01-01T00:00:00Z", "simple", false);
  seedChallengers(db, "hidden", 5, 0);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  assertEquals(body.bosses!.length, 0);
});

Deno.test("no per-user data or raw counts ever appear in the response", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b1", "確認ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b1", 5, 2);

  const res = await handleListHardBosses(req(), db);
  const body: ListHardBossesResponseBody = await res.json();
  const raw = JSON.stringify(body);
  assertEquals(raw.includes("steam-"), false, "no challenger identifier must leak");
  for (const boss of body.bosses!) {
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "challenger_steam_id"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "clear_count"), false);
    assertEquals(Object.prototype.hasOwnProperty.call(boss, "payload"), false);
  }
});

Deno.test("non-GET requests are rejected", async () => {
  const db = new FakeSupabaseRestClient();
  const res = await handleListHardBosses(new Request("http://localhost/list-hard-bosses", { method: "POST" }), db);
  assertEquals(res.status, 405);
});

// ---------------------------------------------------------------------------
// 2026-10 — 公開中の全ボスが対象(新着50件だけにしない)・挑戦記録の全件取得・
// 表示用のユニーク挑戦者数/ユニーククリア者数。
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

// bossIdへ別々のプレイヤーn人分の記録を入れ、先頭clearers人をクリア済みにする。
function seedPlayers(db: FakeSupabaseRestClient, bossId: string, n: number, clearers: number, idOf: (i: number) => string): void {
  const rows = [];
  for (let i = 0; i < n; i++) {
    rows.push({ id: idOf(i), boss_id: bossId, challenger_steam_id: `steam-${bossId}-${i}`, challenge_count: 1, clear_count: i < clearers ? 1 : 0 });
  }
  db.seed("boss_challenge_records", rows);
}

Deno.test("an old hard boss outside the newest 50 is still ranked", async () => {
  const db = new FakeSupabaseRestClient();
  seedManyBosses(db, 60);
  seedChallengers(db, "boss-0000", 5, 0);

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => b.id), ["boss-0000"]);
});

Deno.test("the top 20 of the ranking over every published boss is returned", async () => {
  const db = new FakeSupabaseRestClient();
  const ids = seedManyBosses(db, 25);
  // boss-iは30人中i人がクリア -> 補正クリア率(i+1)/32はiが小さいほど低い(難しい)。
  ids.forEach((id, i) => seedPlayers(db, id, 30, i, (n) => `${id}-r${String(n).padStart(3, "0")}`));

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  assertEquals(body.bosses!.length, 20);
  assertEquals(body.bosses!.map((b) => b.id), ids.slice(0, 20));
  assertEquals(body.bosses!.map((b) => b.unique_clearers), Array.from({ length: 20 }, (_, i) => i));
});

Deno.test("every challenge record counts even when the server returns at most 1000 rows per response", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedBoss(db, "hard", "難しいボス", "2026-01-01T00:00:00Z");
  seedBoss(db, "easy", "易しいボス", "2026-01-02T00:00:00Z");
  // idを交互にして、最初の1000行だけでは人数もクリア者数も違って見える並びにする。
  seedPlayers(db, "hard", 1200, 12, (i) => `rec-${String(i * 2).padStart(5, "0")}`);
  seedPlayers(db, "easy", 1100, 1000, (i) => `rec-${String(i * 2 + 1).padStart(5, "0")}`);

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  assertEquals(
    body.bosses!.map((b) => [b.id, b.unique_challengers, b.unique_clearers]),
    [["hard", 1200, 12], ["easy", 1100, 1000]],
  );
});

Deno.test("published bosses beyond the server's row cap are all considered", async () => {
  const db = new FakeSupabaseRestClient();
  db.setMaxRowsPerResponse(1000);
  seedManyBosses(db, 1200);
  seedChallengers(db, "boss-1150", 6, 0);

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => b.id), ["boss-1150"]);
});

Deno.test("the mode filter applies to every published boss, not just the newest 50", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "old-hc", "古いHARDCORE", isoDay(0), "advanced");
  seedChallengers(db, "old-hc", 5, 1);
  seedManyBosses(db, 60, "simple", "simple", 10);
  seedChallengers(db, "simple-0059", 5, 4);

  const advanced: ListHardBossesResponseBody = await (await handleListHardBosses(req("?mode=advanced"), db)).json();
  assertEquals(advanced.bosses!.map((b) => b.id), ["old-hc"]);
  const simple: ListHardBossesResponseBody = await (await handleListHardBosses(req("?mode=simple"), db)).json();
  assertEquals(simple.bosses!.map((b) => b.id), ["simple-0059"]);
});

Deno.test("a failure on any page returns an error instead of a partial ranking", async () => {
  for (const [table, call] of [["boss_challenge_records", 2], ["bosses", 1]] as const) {
    const db = new FakeSupabaseRestClient();
    db.setMaxRowsPerResponse(1000);
    seedBoss(db, "a", "A", "2026-01-01T00:00:00Z");
    seedPlayers(db, "a", 1500, 3, (i) => `rec-${String(i).padStart(5, "0")}`);
    db.failSelectCall(table, call);

    const res = await handleListHardBosses(req(), db);
    const body: ListHardBossesResponseBody = await res.json();
    assertEquals(res.status, 502, table);
    assertEquals(body.ok, false);
    assertEquals(body.error_kind, "db_error");
    assertEquals(body.bosses, undefined, `${table}: no partial ranking`);
  }
});

Deno.test("each row carries the plain clearer and challenger counts, never the corrected rate", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b1", "確認ボス", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b1", 25, 3);

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  const row = body.bosses![0];
  assertEquals([row.unique_challengers, row.unique_clearers], [25, 3], "3/25 = 12% is the clear rate to show");
  assertEquals(Object.keys(row).sort(), ["author_name", "boss_name", "creator_mode", "id", "published_at", "revision", "unique_challengers", "unique_clearers"]);
  assertEquals(JSON.stringify(body).includes(String(4 / 27)), false, "the corrected rate (3+1)/(25+2) is internal only");
});

Deno.test("a complete tie (rate, challengers and published_at) is ordered by id so the order never changes", async () => {
  const db = new FakeSupabaseRestClient();
  seedBoss(db, "b-second", "B", "2026-01-01T00:00:00Z");
  seedBoss(db, "a-first", "A", "2026-01-01T00:00:00Z");
  seedChallengers(db, "b-second", 5, 1);
  seedChallengers(db, "a-first", 5, 1);

  const body: ListHardBossesResponseBody = await (await handleListHardBosses(req(), db)).json();
  assertEquals(body.bosses!.map((b) => b.id), ["a-first", "b-second"]);
});
