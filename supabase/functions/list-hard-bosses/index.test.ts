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
