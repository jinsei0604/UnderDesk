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
