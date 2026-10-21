// 2026-10-23 — submit-battle-result のテスト（戦闘チケットで結果を1回だけ受け付ける・送り直し・難関ボス討伐の認定）。
// 実Steam/実Supabaseへは一切出ない。偽の DB（FakeSupabaseRestClient）は本物の SQL の関数と同じ決まりを持つ
// （本物の SQL は supabase/tools の確かめ（verify_hard_defeat_checks.sql）で、本番の DB に対して ROLLBACK 付きで試す）。
// 実行方法: deno test supabase/functions/submit-battle-result/

import { assertEquals } from "jsr:@std/assert";
import { handleSubmitBattleResult, MAX_RESULTS_PER_REQUEST, SubmitBattleResultResponseBody } from "./index.ts";
import { handleIssueBattleTicket } from "../issue-battle-ticket/index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "../steam-auth/steam_web_api_client.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

class StubSteamClient implements SteamWebApiClient {
  constructor(private readonly result: RawHttpResult) {}
  authenticateUserTicket(_params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    return Promise.resolve(this.result);
  }
}

function verifierSucceedingAs(steamId: string): SteamTicketVerifier {
  const body = JSON.stringify({ response: { params: { result: "OK", steamid: steamId } } });
  return new SteamTicketVerifier({ client: new StubSteamClient({ status: 200, body }), publisherWebApiKey: "dummy-test-key" });
}

function verifierRejectingTicket(): SteamTicketVerifier {
  const body = JSON.stringify({ response: { error: { errorcode: 101, errordesc: "Invalid ticket" } } });
  return new SteamTicketVerifier({ client: new StubSteamClient({ status: 200, body }), publisherWebApiKey: "dummy-test-key" });
}

const BOSS = "11111111-1111-4111-8111-111111111111";
const OTHER_BOSS = "33333333-3333-4333-8333-333333333333";
const AUTHOR = "76561198000000900";
const ME = "76561198000000001";
const OTHER = "76561198000000002";

function db(): FakeSupabaseRestClient {
  const fake = new FakeSupabaseRestClient();
  fake.seed("bosses", [
    { id: BOSS, boss_name: "公開ボス", is_published: true, revision: 1, owner_steam_id: AUTHOR, payload: { draft_fields: { creator_mode: "advanced" } } },
    { id: OTHER_BOSS, boss_name: "別の公開ボス", is_published: true, revision: 1, owner_steam_id: AUTHOR, payload: {} },
  ]);
  fake.nowMs = Date.parse("2026-10-23T12:00:00Z");
  return fake;
}

async function ticketFor(fake: FakeSupabaseRestClient, steamId: string, bossId = BOSS): Promise<string> {
  const res = await handleIssueBattleTicket(
    new Request("http://localhost/issue-battle-ticket", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", boss_id: bossId }) }),
    verifierSucceedingAs(steamId),
    fake,
    5482410,
  );
  const body = await res.json();
  if (res.status !== 200) throw new Error(`ticket not issued: ${res.status}`);
  return body.battle_ticket;
}

interface Item {
  boss_id?: unknown;
  battle_ticket?: unknown;
  result_id?: unknown;
  outcome?: unknown;
}

async function submit(
  fake: FakeSupabaseRestClient,
  steamId: string,
  results: Item[],
  extra: Record<string, unknown> = {},
): Promise<{ status: number; body: SubmitBattleResultResponseBody; text: string }> {
  const res = await handleSubmitBattleResult(
    new Request("http://localhost/submit-battle-result", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", results, ...extra }) }),
    verifierSucceedingAs(steamId),
    fake,
    5482410,
  );
  const text = await res.text();
  return { status: res.status, body: JSON.parse(text), text };
}

// 1人が1回戦って結果を送る（新しいチケット・新しい結果の id）。
async function play(fake: FakeSupabaseRestClient, steamId: string, outcome: "clear" | "loss", bossId = BOSS) {
  const battleTicket = await ticketFor(fake, steamId, bossId);
  const r = await submit(fake, steamId, [{ boss_id: bossId, battle_ticket: battleTicket, result_id: crypto.randomUUID(), outcome }]);
  return r.body.results![0];
}

function recordOf(fake: FakeSupabaseRestClient, steamId: string, bossId = BOSS): Record<string, unknown> | undefined {
  return fake.rowsOf("boss_challenge_records").find((r) => r.boss_id === bossId && r.challenger_steam_id === steamId);
}

Deno.test("a result is counted once; resending the same result (lost response, restart) is a duplicate that returns the current state", async () => {
  const fake = db();
  const battleTicket = await ticketFor(fake, ME);
  const item = { boss_id: BOSS, battle_ticket: battleTicket, result_id: crypto.randomUUID(), outcome: "clear" };
  const first = await submit(fake, ME, [item]);
  assertEquals(first.status, 200);
  assertEquals(first.body.results, [{ result_id: item.result_id, status: "counted", by_owner: false, hard_awarded: false, clear_count: 1, first_clear_rate: null }]);
  for (let i = 0; i < 3; i++) {
    const again = await submit(fake, ME, [item]);
    assertEquals(again.body.results![0].status, "duplicate");
    assertEquals(again.body.results![0].by_owner, false);
  }
  const rec = recordOf(fake, ME)!;
  assertEquals([rec.result_count, rec.result_clear_count, rec.clear_count], [1, 1, 1], "counted only once");
});

Deno.test("a ticket cannot be reused for another result, and a result id cannot be reused with another ticket", async () => {
  const fake = db();
  const t1 = await ticketFor(fake, ME);
  const resultId = crypto.randomUUID();
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: t1, result_id: resultId, outcome: "loss" }])).body.results![0].status, "counted");
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: t1, result_id: crypto.randomUUID(), outcome: "loss" }])).body.results![0].status, "used");
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: t1, result_id: resultId, outcome: "clear" }])).body.results![0].status, "used", "a loss cannot be turned into a win");
  const t2 = await ticketFor(fake, ME);
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: t2, result_id: resultId, outcome: "loss" }])).body.results![0].status, "used");
  const rec = recordOf(fake, ME)!;
  assertEquals([rec.result_count, rec.result_clear_count], [1, 0]);
});

Deno.test("forged tickets, another player's ticket and a ticket for another boss are invalid and count nothing", async () => {
  const fake = db();
  const mine = await ticketFor(fake, ME);
  const cases: [string, Item][] = [
    ["a made-up ticket", { boss_id: BOSS, battle_ticket: crypto.randomUUID(), result_id: crypto.randomUUID(), outcome: "clear" }],
    ["another boss", { boss_id: OTHER_BOSS, battle_ticket: mine, result_id: crypto.randomUUID(), outcome: "clear" }],
    ["not a uuid", { boss_id: BOSS, battle_ticket: "ticket-1", result_id: crypto.randomUUID(), outcome: "clear" }],
    ["unknown outcome", { boss_id: BOSS, battle_ticket: mine, result_id: crypto.randomUUID(), outcome: "win" }],
    ["no result id", { boss_id: BOSS, battle_ticket: mine, outcome: "clear" }],
  ];
  for (const [label, item] of cases) {
    const r = await submit(fake, ME, [item]);
    assertEquals([r.status, r.body.results![0].status], [200, "invalid"], label);
  }
  // 別の人（OTHER）が ME のチケットを送っても数えない（チケットは Steam で確かめた本人に結びつく。リクエストの steam_id は使わない）
  const stolen = await submit(fake, OTHER, [{ boss_id: BOSS, battle_ticket: mine, result_id: crypto.randomUUID(), outcome: "clear" }], { steam_id: ME });
  assertEquals(stolen.body.results![0].status, "invalid");
  assertEquals(fake.rowsOf("boss_challenge_records").length, 0);
  // 本人の正しい送信は、まだ通る（失敗した試みでチケットは使われない）
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: mine, result_id: crypto.randomUUID(), outcome: "clear" }])).body.results![0].status, "counted");
});

Deno.test("a ticket is valid for 30 days: a result sent after 29 days counts, after 31 days it is expired", async () => {
  const fake = db();
  const early = await ticketFor(fake, ME);
  const late = await ticketFor(fake, ME);
  fake.nowMs = (fake.nowMs as number) + 29 * 24 * 3600_000;
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: early, result_id: crypto.randomUUID(), outcome: "clear" }])).body.results![0].status, "counted");
  fake.nowMs = (fake.nowMs as number) + 2 * 24 * 3600_000;
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: late, result_id: crypto.randomUUID(), outcome: "loss" }])).body.results![0].status, "expired");
  assertEquals(recordOf(fake, ME)!.result_count, 1);
});

Deno.test("several pending results go in one request; a database failure on one is 'error' (sent again later) and the others still count", async () => {
  const fake = db();
  const items: Item[] = [];
  for (let i = 0; i < 3; i++) {
    items.push({ boss_id: BOSS, battle_ticket: await ticketFor(fake, ME), result_id: crypto.randomUUID(), outcome: i === 2 ? "clear" : "loss" });
  }
  fake.failRpcCall("submit_boss_battle_result", 2);
  const first = await submit(fake, ME, items);
  assertEquals(first.status, 200);
  assertEquals(first.body.results!.map((r) => r.status), ["counted", "error", "counted"]);
  assertEquals(first.text.includes("fake failure"), false, "the DB's own message is not returned");
  assertEquals(recordOf(fake, ME)!.result_count, 2);
  // 次の機会に、まとめて送り直す → 失敗した1件だけが数えられる
  const again = await submit(fake, ME, items);
  assertEquals(again.body.results!.map((r) => r.status), ["duplicate", "counted", "duplicate"]);
  const rec = recordOf(fake, ME)!;
  assertEquals([rec.result_count, rec.result_clear_count], [3, 1]);
});

Deno.test("the request limits: at most 20 results, something to do, a valid Steam ticket", async () => {
  const fake = db();
  const tooMany = Array.from({ length: MAX_RESULTS_PER_REQUEST + 1 }, () => ({ boss_id: BOSS, battle_ticket: crypto.randomUUID(), result_id: crypto.randomUUID(), outcome: "loss" }));
  assertEquals((await submit(fake, ME, tooMany)).status, 400);
  assertEquals((await submit(fake, ME, [])).status, 400);
  assertEquals((await submit(fake, ME, [], { next_ticket_boss_id: "nope" })).status, 400);
  const rejected = await handleSubmitBattleResult(
    new Request("http://localhost/submit-battle-result", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", results: [] , next_ticket_boss_id: BOSS }) }),
    verifierRejectingTicket(),
    fake,
    5482410,
  );
  assertEquals(rejected.status, 401);
  assertEquals(fake.rpcCalls.length, 0);
});

Deno.test("the next battle's ticket can come back in the same response (no extra request for 'try again'); limits are reported, not fatal", async () => {
  const fake = db();
  const t1 = await ticketFor(fake, ME);
  const r = await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: t1, result_id: crypto.randomUUID(), outcome: "loss" }], { next_ticket_boss_id: BOSS });
  assertEquals(r.body.results![0].status, "counted");
  assertEquals(typeof r.body.next_battle_ticket, "string");
  assertEquals(typeof r.body.next_ticket_expires_at, "string");
  // 次のチケットで次の戦闘の結果が数えられる
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: r.body.next_battle_ticket, result_id: crypto.randomUUID(), outcome: "loss" }])).body.results![0].status, "counted");
  // 1時間の上限に達していれば、結果は数えたうえで理由だけ返す
  for (let i = 0; i < 58; i++) await ticketFor(fake, ME);
  const limited = await submit(fake, ME, [], { next_ticket_boss_id: BOSS });
  assertEquals([limited.status, limited.body.next_battle_ticket, limited.body.next_ticket_status], [200, undefined, "rate_limited"]);
});

Deno.test("a boss unpublished after the battle started still accepts that battle's result", async () => {
  const fake = db();
  const battleTicket = await ticketFor(fake, ME);
  fake.rowsOf("bosses").find((b) => b.id === BOSS)!.is_published = false;
  assertEquals((await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: battleTicket, result_id: crypto.randomUUID(), outcome: "clear" }])).body.results![0].status, "counted");
});

Deno.test("the author's results are recorded as by_owner, never enter the counts and are never awarded", async () => {
  const fake = db();
  const own = await play(fake, AUTHOR, "clear");
  assertEquals([own.status, own.by_owner, own.hard_awarded], ["counted", true, false]);
  for (let i = 0; i < 60; i++) await play(fake, AUTHOR, "loss", OTHER_BOSS);
  assertEquals(fake.hardDefeatStats(BOSS, null), { results: 0, challengers: 0, clearers: 0 });
  assertEquals(fake.hardDefeatStats(OTHER_BOSS, null), { results: 0, challengers: 0, clearers: 0 });
});

Deno.test("hard defeat: the first clear is held, awarded retroactively at exactly 50 results, and the award stays", async () => {
  const fake = db();
  const pioneer = await play(fake, ME, "clear");
  assertEquals([pioneer.status, pioneer.hard_awarded, pioneer.first_clear_rate], ["counted", false, null], "no other challengers yet: held, not 0%");
  // 19人が1回ずつ負ける（挑戦者20人・クリア1人 = 5%・結果20回）、作者の結果は数えない
  for (let i = 0; i < 19; i++) await play(fake, `7656119800000${1000 + i}`, "loss");
  for (let i = 0; i < 10; i++) await play(fake, AUTHOR, "loss");
  // 1人が負けを重ねて 49回 → まだ
  for (let i = 0; i < 29; i++) await play(fake, "76561198000001000", "loss");
  assertEquals(fake.hardDefeatStats(BOSS, null).results, 49);
  assertEquals(recordOf(fake, ME)!.hard_awarded_at, null, "49 results: not yet");
  await play(fake, "76561198000001000", "loss");
  assertEquals(typeof recordOf(fake, ME)!.hard_awarded_at, "string", "50 results: awarded retroactively");
  // 51回目・再クリアでも残る。応答でも分かる
  await play(fake, "76561198000001001", "loss");
  const again = await play(fake, ME, "clear");
  assertEquals([again.hard_awarded, again.first_clear_rate], [true, null]);
});

Deno.test("hard defeat: first clears at 5% or less of the others qualify when the boss reaches exactly 5%, above 5% never does", async () => {
  const fake = db();
  await play(fake, ME, "clear");
  for (let i = 0; i < 39; i++) await play(fake, `7656119800000${2000 + i}`, "loss");   // 40人・1人クリア
  const low = await play(fake, "76561198000003000", "clear");   // この人を除いたほかの人: 40人中1人 = 2.5%
  assertEquals(low.first_clear_rate, 1 / 40);
  const under5 = await play(fake, "76561198000003001", "clear");   // ほかの人: 41人中2人 = 4.9%
  assertEquals(under5.first_clear_rate, 2 / 41);
  // ほかの人: 42人中3人 = 7.1% → 対象外
  const over = await play(fake, "76561198000003002", "clear");
  assertEquals(over.first_clear_rate, 3 / 42);
  // 人を増やして、ボスを 80人中4人 = 5% ちょうど・結果80回にする → 条件を満たす
  for (let i = 0; i < 37; i++) await play(fake, `7656119800000${4000 + i}`, "loss");
  assertEquals(fake.hardDefeatStats(BOSS, null), { results: 80, challengers: 80, clearers: 4 });
  assertEquals(typeof recordOf(fake, ME)!.hard_awarded_at, "string", "the pioneer");
  assertEquals(typeof recordOf(fake, "76561198000003000")!.hard_awarded_at, "string", "2.5% at the first clear");
  assertEquals(typeof recordOf(fake, "76561198000003001")!.hard_awarded_at, "string", "4.9% at the first clear");
  assertEquals(recordOf(fake, "76561198000003002")!.hard_awarded_at, null, "7.1% at the first clear: never");
  // 81人目がクリアして 5/81 = 6.2% になっても、ついた認定は消えない
  await play(fake, "76561198000005000", "clear");
  assertEquals(typeof recordOf(fake, ME)!.hard_awarded_at, "string");
});

Deno.test("only battle-ticket results count: starting a challenge or an old game's clear record adds no result", async () => {
  const fake = db();
  await fake.rpc("record_boss_challenge_attempt", { p_boss_id: BOSS, p_steam_id: ME });
  await fake.rpc("record_boss_challenge_clear", { p_boss_id: BOSS, p_steam_id: OTHER });
  assertEquals(fake.hardDefeatStats(BOSS, null), { results: 0, challengers: 0, clearers: 0 });
  // 旧版のクリアの記録がある人が、チケットで初めてクリアすると、その時に初回の数が残る
  await play(fake, ME, "loss");
  const r = await play(fake, OTHER, "clear");
  assertEquals([r.status, r.first_clear_rate, r.clear_count], ["counted", 0, 2]);
});

Deno.test("responses never carry a SteamID or a ticket row's internal columns", async () => {
  const fake = db();
  const issued = await handleIssueBattleTicket(
    new Request("http://localhost/issue-battle-ticket", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", boss_id: BOSS }) }),
    verifierSucceedingAs(ME),
    fake,
    5482410,
  );
  const issuedText = await issued.text();
  const battleTicket = JSON.parse(issuedText).battle_ticket;
  const submitted = await submit(fake, ME, [{ boss_id: BOSS, battle_ticket: battleTicket, result_id: crypto.randomUUID(), outcome: "clear" }], { next_ticket_boss_id: BOSS });
  for (const text of [issuedText, submitted.text]) {
    for (const word of [ME, AUTHOR, "steam", "challenger", "owner_steam_id", "creator_mode", "boss_revision"]) {
      assertEquals(text.includes(word), false, `must not return "${word}"`);
    }
  }
});
