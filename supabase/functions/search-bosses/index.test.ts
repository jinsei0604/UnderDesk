import { assert, assertEquals } from "jsr:@std/assert";
import { decodeSearchCursor, encodeSearchCursor, handleSearchBosses, MAX_QUERY_LENGTH } from "./index.ts";
import { FakePostgrestClient } from "../_shared/fake_postgrest_client.ts";
import { DB_ERROR_PUBLIC_MESSAGE, PublicBossListResponseBody } from "../_shared/public_boss_query.ts";

const ID_A = "1a2b3c4d-0000-4000-8000-000000000001";
const ID_B = "1a2b3c4d-ffff-4000-8000-000000000002";
const ID_C = "9f8e7d6c-1111-4000-8000-000000000003";
const ID_D = "0d0d0d0d-2222-4000-8000-000000000004";
const ID_HIDDEN = "aaaaaaaa-3333-4000-8000-000000000005";

function boss(id: string, name: string, author: string, publishedAt: string, payload: Record<string, unknown>, published = true) {
  return { id, boss_name: name, author_name: author, published_at: publishedAt, revision: 1, is_published: published, payload };
}

function db(): FakePostgrestClient {
  const fake = new FakePostgrestClient();
  fake.seed("bosses", [
    boss(ID_A, "黒炎竜ヴァルグ", "player_3", "2026-10-01T00:00:00.000001+00:00", { draft_fields: { creator_mode: "advanced", appearance_id: "appearance_dragon" } }),
    boss(ID_B, "Slime King", "Dragon Fan", "2026-10-02T00:00:00+00:00", { draft_fields: { creator_mode: "simple", appearance_id: "appearance_slime" } }),
    boss(ID_C, "月面の迷子", "宇宙の人", "2026-10-03T00:00:00+00:00", { draft_fields: {} }),
    boss(ID_D, "100% 竜(改)", "a_b", "2026-10-04T00:00:00+00:00", { draft_fields: { creator_mode: "weird" } }),
    boss(ID_HIDDEN, "非公開の竜", "player_9", "2026-10-05T00:00:00+00:00", { draft_fields: { creator_mode: "advanced" } }, false),
  ]);
  fake.seed("boss_challenge_records", [
    { id: "r1", boss_id: ID_A, clear_count: 0 },
    { id: "r2", boss_id: ID_A, clear_count: 2 },
    { id: "r3", boss_id: ID_B, clear_count: 1 },
  ]);
  return fake;
}

async function search(fake: FakePostgrestClient, params: string): Promise<{ status: number; body: PublicBossListResponseBody }> {
  const res = await handleSearchBosses(new Request(`http://localhost/search-bosses?${params}`, { method: "GET" }), fake);
  return { status: res.status, body: await res.json() };
}

function names(body: PublicBossListResponseBody): string[] {
  return body.bosses!.map((b) => b.boss_name);
}

Deno.test("finds bosses by part of the boss name, newest first, published only", async () => {
  const { status, body } = await search(db(), `q=${encodeURIComponent("竜")}`);
  assertEquals(status, 200);
  assertEquals(names(body), ["100% 竜(改)", "黒炎竜ヴァルグ"]);
});

Deno.test("matches ignore upper and lower case", async () => {
  const { body } = await search(db(), "q=slime%20KING");
  assertEquals(names(body), ["Slime King"]);
});

Deno.test("finds bosses by the author name", async () => {
  const { body } = await search(db(), `q=${encodeURIComponent("宇宙")}`);
  assertEquals(names(body), ["月面の迷子"]);
  const byDragonFan = await search(db(), "q=dragon");
  assertEquals(names(byDragonFan.body), ["Slime King"], "作者名 Dragon Fan に当たる");
});

Deno.test("finds bosses by the 8-character public id, and by the whole id", async () => {
  const byPublicId = await search(db(), "q=1A2B3C4D");
  assertEquals(byPublicId.body.bosses!.map((b) => b.id).sort(), [ID_A, ID_B].sort(), "先頭8文字が同じボスはすべて出る（大文字でも）");
  const byWholeId = await search(db(), `q=${ID_C}`);
  assertEquals(names(byWholeId.body), ["月面の迷子"]);
  const hidden = await search(db(), "q=aaaaaaaa");
  assertEquals(hidden.body.bosses!.length, 0, "非公開のボスは公開IDでも出ない");
});

Deno.test("mode narrows the results; missing or unknown creator_mode counts as SIMPLE", async () => {
  const simple = await search(db(), `q=${encodeURIComponent("の")}&mode=simple`);
  assertEquals(names(simple.body), ["月面の迷子"]);
  const anySimple = await search(db(), "q=a&mode=simple");
  assertEquals(names(anySimple.body), ["100% 竜(改)", "Slime King"], "creator_modeが不正・無いボスもSIMPLE");
  const hard = await search(db(), "q=a&mode=advanced");
  assertEquals(names(hard.body), ["黒炎竜ヴァルグ"]);
});

Deno.test("special characters in the query do not break the filter or match everything", async () => {
  for (const q of ["%", "_", '"', "\\", ",", "(", ")", ".", ":"]) {
    const { status, body } = await search(db(), `q=${encodeURIComponent(q)}`);
    assertEquals(status, 200, q);
    for (const row of body.bosses!) {
      assert(row.boss_name.includes(q) || row.author_name.includes(q), `「${q}」は文字そのものとして探す（${row.boss_name}）`);
    }
  }
  assertEquals((await search(db(), "q=*")).status, 200, "* は1文字の何でもとして扱う（エラーにしない）");
  const percent = await search(db(), `q=${encodeURIComponent("100%")}`);
  assertEquals(names(percent.body), ["100% 竜(改)"]);
  const paren = await search(db(), `q=${encodeURIComponent("竜(改)")}`);
  assertEquals(names(paren.body), ["100% 竜(改)"]);
  const underscore = await search(db(), "q=a_b");
  assertEquals(names(underscore.body), ["100% 竜(改)"]);
});

Deno.test("rows have the list-bosses fields, challenge counts, and never the payload", async () => {
  const fake = db();
  const { body } = await search(fake, `q=${encodeURIComponent("ヴァルグ")}`);
  const row = body.bosses![0];
  assertEquals(row.creator_mode, "advanced");
  assertEquals(row.appearance_id, "appearance_dragon");
  assertEquals(row.unique_challengers, 2);
  assertEquals(row.unique_clearers, 1);
  assertEquals(Object.prototype.hasOwnProperty.call(row, "payload"), false);
  const bossQueries = fake.selectCalls.filter((c) => c.table === "bosses");
  assertEquals(bossQueries.length, 1, "公開ボスの問い合わせは1回だけ");
  const select = new URLSearchParams(bossQueries[0].query).get("select")!;
  assertEquals(select.split(",").includes("payload"), false, "payload全体は読まない");
  assertEquals(new URLSearchParams(bossQueries[0].query).get("limit"), "21", "1ページ分+1件だけ読む");
});

Deno.test("pages with has_more and next_cursor, without gaps or repeats", async () => {
  const fake = new FakePostgrestClient();
  const rows = [];
  for (let i = 0; i < 7; i++) {
    // 2件ずつ同じ公開日時(マイクロ秒まで)にして、同じ時刻の中の並びも確かめる
    const at = `2026-10-0${1 + Math.floor(i / 2)}T00:00:00.000005+00:00`;
    rows.push(boss(`00000000-0000-4000-8000-00000000000${i}`, `竜${i}`, "x", at, { draft_fields: {} }));
  }
  fake.seed("bosses", rows);
  const seen: string[] = [];
  let cursor = "";
  for (let page = 0; page < 5; page++) {
    const { body } = await search(fake, `q=${encodeURIComponent("竜")}&limit=3${cursor ? `&cursor=${cursor}` : ""}`);
    seen.push(...body.bosses!.map((b) => b.id));
    if (!body.has_more) break;
    cursor = body.next_cursor!;
  }
  assertEquals(seen.length, 7);
  assertEquals(new Set(seen).size, 7);
});

Deno.test("cursor encodes the published_at text exactly", () => {
  const position = { publishedAt: "2026-10-01T00:00:00.123456+00:00", id: ID_A };
  assertEquals(decodeSearchCursor(encodeSearchCursor(position)), position);
  assertEquals(decodeSearchCursor("not a cursor"), null);
  assertEquals(decodeSearchCursor(encodeSearchCursor({ publishedAt: 'x",id.gt.0', id: ID_A })), null, "問い合わせを壊す文字は受け付けない");
});

Deno.test("rejects a missing, too long, or bad request", async () => {
  assertEquals((await search(db(), "q=%20%20")).status, 400);
  assertEquals((await search(db(), "")).status, 400);
  assertEquals((await search(db(), `q=${"a".repeat(MAX_QUERY_LENGTH + 1)}`)).status, 400);
  assertEquals((await search(db(), "q=a&cursor=%%%")).status, 400);
  const post = await handleSearchBosses(new Request("http://localhost/search-bosses?q=a", { method: "POST" }), db());
  assertEquals(post.status, 405);
});

Deno.test("a database failure returns db_error instead of an empty result", async () => {
  const fake = db();
  fake.fail("select", "bosses", 1);
  const { status, body } = await search(fake, "q=a");
  assertEquals(status, 502);
  assertEquals(body.error_kind, "db_error");
  const statsFail = db();
  statsFail.fail("select", "boss_challenge_records", 1);
  assertEquals((await search(statsFail, `q=${encodeURIComponent("ヴァルグ")}`)).status, 502);
});

Deno.test("only published bosses are ever read, and private columns never reach the response", async () => {
  const fake = db();
  fake.seed("bosses", [{ ...boss("1a2b3c4d-1234-4000-8000-00000000000f", "非公開の秘密", "player_x", "2026-10-09T00:00:00+00:00", { draft_fields: {} }, false), owner_steam_id: "76561198000000001", battle_hash: "a".repeat(64), local_stage_id: "0123456789", idempotency_key: "k" }]);
  for (const q of ["1a2b3c4d", "秘密", "player_x"]) {
    const { body } = await search(fake, `q=${encodeURIComponent(q)}`);
    assertEquals(body.bosses!.some((b) => b.boss_name === "非公開の秘密"), false, `非公開は出ない（${q}）`);
    for (const row of body.bosses!) {
      assertEquals(Object.keys(row).sort(), ["appearance_id", "author_name", "boss_name", "creator_mode", "id", "published_at", "revision", "unique_challengers", "unique_clearers"], "返すのはカードの項目だけ");
    }
  }
  for (const call of fake.selectCalls.filter((c) => c.table === "bosses")) {
    assertEquals(new URLSearchParams(call.query).get("is_published"), "eq.true", "公開ボスの問い合わせには必ず公開中の条件");
  }
});

Deno.test("a query cannot break out of the quoted search value", async () => {
  const fake = db();
  for (const q of ['竜",is_published.eq.false', "a),or(is_published.eq.false", '\\",id.gt.0']) {
    const { status, body } = await search(fake, `q=${encodeURIComponent(q)}`);
    assertEquals(status, 200, q);
    assertEquals(body.bosses!.length, 0, `文字そのものとして探すだけ（${q}）`);
  }
});

Deno.test("bosses sharing the first 8 characters each keep their own full id", async () => {
  const { body } = await search(db(), "q=1a2b3c4d");
  const byId = new Map(body.bosses!.map((b) => [b.id, b.boss_name]));
  assertEquals(byId.get(ID_A), "黒炎竜ヴァルグ");
  assertEquals(byId.get(ID_B), "Slime King");
});

Deno.test("database error details stay in the log, not in the response", async () => {
  for (const [table, call] of [["bosses", 1], ["boss_challenge_records", 1]] as const) {
    const fake = db();
    fake.fail("select", table, call);
    const res = await handleSearchBosses(new Request(`http://localhost/search-bosses?q=${encodeURIComponent("ヴァルグ")}`, { method: "GET" }), fake);
    const text = await res.text();
    assertEquals(res.status, 502);
    assertEquals(text.includes("owner_steam_id") || text.includes("42703"), false, "DBの内部の文を返さない");
    assertEquals(JSON.parse(text).message, DB_ERROR_PUBLIC_MESSAGE);
  }
});
