// 2026-10-29 体験版のオンライン挑戦「異なるボス累計15体まで」のテスト（demo-challenge-status・record-challenge-attempt・
// issue-battle-ticket）。実Steam/実Supabaseへは一切出ない（DB は FakeSupabaseRestClient。本物の SQL は
// migration 20261029000000_demo_challenge_slots.sql の claim_demo_challenge_slot() で、同じ決まりを再現している）。
// 実行方法: deno test supabase/functions/demo-challenge-status/

import { assertEquals } from "jsr:@std/assert";
import { DemoChallengeStatusResponseBody, handleDemoChallengeStatus } from "./index.ts";
import { handleRecordChallengeAttempt, RecordChallengeAttemptResponseBody } from "../record-challenge-attempt/index.ts";
import { handleIssueBattleTicket } from "../issue-battle-ticket/index.ts";
import { handleRecordChallengeClear } from "../record-challenge-clear/index.ts";
import { handleSubmitBattleResult } from "../submit-battle-result/index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { AuthenticateUserTicketParams, RawHttpResult, SteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { FakeSupabaseRestClient } from "../_shared/fake_supabase_rest_client.ts";

const FULL_APP = 5482410;
const DEMO_APP = 9990001; // テスト用の値（本物の体験版の AppID ではない）
const ME = "76561198000000001";
const OTHER = "76561198000000002";

// チケットが ticketApp のアプリのものとして発行された時の Steam の応答を真似る。
class AppAwareSteamClient implements SteamWebApiClient {
  constructor(private readonly ticketApp: number, private readonly steamId: string) {}
  authenticateUserTicket(params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    if (params.appId === this.ticketApp) {
      return Promise.resolve({ status: 200, body: JSON.stringify({ response: { params: { result: "OK", steamid: this.steamId } } }) });
    }
    return Promise.resolve({ status: 200, body: JSON.stringify({ response: { error: { errorcode: 101, errordesc: "Invalid ticket" } } }) });
  }
}

function demoPlayer(steamId = ME): SteamTicketVerifier {
  return new SteamTicketVerifier({ client: new AppAwareSteamClient(DEMO_APP, steamId), publisherWebApiKey: "dummy-test-key", demoAppId: DEMO_APP });
}

function fullPlayer(steamId = ME): SteamTicketVerifier {
  return new SteamTicketVerifier({ client: new AppAwareSteamClient(FULL_APP, steamId), publisherWebApiKey: "dummy-test-key", demoAppId: DEMO_APP });
}

function bossId(n: number): string {
  return `00000000-0000-4000-8000-${n.toString().padStart(12, "0")}`;
}

// 体験版の範囲（SIMPLE・体験版の4体）の公開ボスを count 体。名前はわざと全部同じ（名前では数えない）。
function db(count = 20): FakeSupabaseRestClient {
  const fake = new FakeSupabaseRestClient();
  const bosses = [];
  for (let i = 1; i <= count; i++) {
    bosses.push({ id: bossId(i), boss_name: "同じ名前のボス", is_published: true, revision: 1, payload: { draft_fields: { creator_mode: "simple", appearance_id: "appearance_slime" } } });
  }
  fake.seed("bosses", bosses);
  fake.nowMs = Date.parse("2026-10-29T12:00:00Z");
  return fake;
}

function post(path: string, payload: unknown): Request {
  return new Request(`http://localhost/${path}`, { method: "POST", body: JSON.stringify(payload) });
}

async function attempt(fake: FakeSupabaseRestClient, n: number, verifier = demoPlayer()): Promise<{ status: number; body: RecordChallengeAttemptResponseBody }> {
  const res = await handleRecordChallengeAttempt(post("record-challenge-attempt", { ticket: "aabbcc", boss_id: bossId(n), want_battle_ticket: true }), verifier, fake, FULL_APP);
  return { status: res.status, body: await res.json() };
}

async function status(fake: FakeSupabaseRestClient, verifier = demoPlayer()): Promise<{ status: number; body: DemoChallengeStatusResponseBody }> {
  const res = await handleDemoChallengeStatus(post("demo-challenge-status", { ticket: "aabbcc", steam_id: OTHER, edition: "full" }), verifier, fake, FULL_APP);
  return { status: res.status, body: await res.json() };
}

Deno.test("first challenge counts 1; re-challenging the same boss (any number of times, win or lose) does not count again", async () => {
  const fake = db();
  const first = await attempt(fake, 1);
  assertEquals([first.status, first.body.ok, first.body.demo_used, first.body.demo_limit], [200, true, 1, 15]);
  for (let i = 0; i < 10; i++) {
    const again = await attempt(fake, 1);
    assertEquals([again.status, again.body.demo_used], [200, 1]);
  }
  assertEquals((await attempt(fake, 2)).body.demo_used, 2);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 2);
  // 挑戦の記録・チケットは今までどおり（同じボスの challenge_count は増える）
  assertEquals(fake.rowsOf("boss_challenge_records").find((r) => r.boss_id === bossId(1))?.challenge_count, 11);
});

Deno.test("15 different bosses can be challenged; the 16th new boss is refused with no record and no ticket; the first 15 stay open", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) assertEquals((await attempt(fake, n)).status, 200);
  const ticketsBefore = fake.rowsOf("boss_battle_tickets").length;
  const recordsBefore = fake.rowsOf("boss_challenge_records").length;
  const refused = await attempt(fake, 16);
  assertEquals([refused.status, refused.body.ok, refused.body.error_kind, refused.body.demo_used, refused.body.demo_limit], [403, false, "demo_challenge_limit", 15, 15]);
  assertEquals(refused.body.battle_ticket, undefined);
  assertEquals(fake.rowsOf("boss_battle_tickets").length, ticketsBefore, "no ticket for the 16th");
  assertEquals(fake.rowsOf("boss_challenge_records").length, recordsBefore, "no challenge record for the 16th");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
  for (const n of [1, 7, 15]) assertEquals((await attempt(fake, n)).status, 200, `boss ${n} can still be re-challenged`);
});

Deno.test("calling issue-battle-ticket directly cannot open a 16th boss; tickets for already-challenged bosses still work", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) await attempt(fake, n);
  const direct = await handleIssueBattleTicket(post("issue-battle-ticket", { ticket: "aabbcc", boss_id: bossId(16) }), demoPlayer(), fake, FULL_APP);
  assertEquals(direct.status, 403);
  assertEquals((await direct.json()).error_kind, "demo_challenge_limit");
  const known = await handleIssueBattleTicket(post("issue-battle-ticket", { ticket: "aabbcc", boss_id: bossId(3) }), demoPlayer(), fake, FULL_APP);
  assertEquals(known.status, 200);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
});

Deno.test("an unknown or unpublished boss, or a refused trial boss, does not use a slot", async () => {
  const fake = db(2);
  fake.seed("bosses", [
    { id: bossId(90), boss_name: "非公開", is_published: false, revision: 1, payload: { draft_fields: { creator_mode: "simple", appearance_id: "appearance_slime" } } },
    { id: bossId(91), boss_name: "HARDCORE", is_published: true, revision: 1, payload: { draft_fields: { creator_mode: "advanced", appearance_id: "appearance_slime" } } },
  ]);
  assertEquals((await attempt(fake, 90)).status, 404);
  assertEquals((await attempt(fake, 99)).status, 404);
  assertEquals((await attempt(fake, 91)).status, 403, "outside the trial range");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 0);
});

Deno.test("a database failure while checking the slot refuses the challenge (502) without recording; a retry counts once", async () => {
  const fake = db();
  fake.failRpcCall("claim_demo_challenge_slot", 1);
  const failed = await attempt(fake, 1);
  assertEquals([failed.status, failed.body.error_kind], [502, "db_error"]);
  assertEquals(fake.rowsOf("boss_challenge_records").length, 0);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 0);
  const retry = await attempt(fake, 1);
  assertEquals([retry.status, retry.body.demo_used], [200, 1]);
  const retryAgain = await attempt(fake, 1);
  assertEquals(retryAgain.body.demo_used, 1, "retrying the same boss never uses another slot");
});

Deno.test("a slot is kept when the boss is later unpublished, republished, updated or deleted (slots do not come back)", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) await attempt(fake, n);
  // ボス1を消す・ボス2を非公開→再公開（同じ id）
  fake.seed("bosses", []);
  (fake as unknown as { tables: Map<string, Record<string, unknown>[]> }).tables.set(
    "bosses",
    fake.rowsOf("bosses").filter((b) => b.id !== bossId(1)),
  );
  const slotsAfterDelete = fake.rowsOf("demo_challenge_slots").length;
  assertEquals(slotsAfterDelete, 15, "deleting a boss does not free its slot");
  assertEquals((await attempt(fake, 16)).status, 403, "still at 15 after the deletion");
  const boss2 = fake.rowsOf("bosses").find((b) => b.id === bossId(2)) as Record<string, unknown>;
  boss2.is_published = false;
  boss2.is_published = true;
  boss2.revision = 2;
  const again = await attempt(fake, 2);
  assertEquals([again.status, again.body.demo_used], [200, 15], "the same id after an update/republish is not counted again");
});

Deno.test("the full version is never limited and never uses slots, even for a player who reached 15 in the trial", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) await attempt(fake, n);
  const full = await attempt(fake, 16, fullPlayer());
  assertEquals([full.status, full.body.ok, full.body.demo_used], [200, true, undefined]);
  for (let n = 17; n <= 20; n++) assertEquals((await attempt(fake, n, fullPlayer())).status, 200);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
  const fullStatus = await status(fake, fullPlayer());
  assertEquals([fullStatus.status, fullStatus.body.limited, fullStatus.body.used], [200, false, undefined]);
});

Deno.test("the count belongs to the verified Steam account (never a steam_id or edition in the request) and is shared across PCs", async () => {
  const fake = db();
  for (let n = 1; n <= 3; n++) await attempt(fake, n);
  await attempt(fake, 4, demoPlayer(OTHER));
  const mine = await status(fake);
  assertEquals([mine.status, mine.body.limited, mine.body.used, mine.body.limit], [200, true, 3, 15]);
  assertEquals(mine.body.challenged_boss_ids, [bossId(1), bossId(2), bossId(3)]);
  // 別の PC でも、同じ Steam アカウントなら同じ数（サーバーの記録だけで決まる）
  const otherPc = await status(fake, demoPlayer(ME));
  assertEquals(otherPc.body.used, 3);
  assertEquals((await status(fake, demoPlayer(OTHER))).body.used, 1);
});

Deno.test("status: bad requests and Steam failures are rejected, a database failure is an error (never 0)", async () => {
  const fake = db();
  assertEquals((await handleDemoChallengeStatus(new Request("http://localhost/x", { method: "GET" }), demoPlayer(), fake, FULL_APP)).status, 405);
  assertEquals((await handleDemoChallengeStatus(post("x", { ticket: "zz" }), demoPlayer(), fake, FULL_APP)).status, 400);
  fake.failRpcCall("demo_challenge_status", 1);
  const failed = await status(fake);
  assertEquals([failed.status, failed.body.ok, failed.body.used], [502, false, undefined]);
});

// 2026-10-30: 挑戦の記録・戦闘チケット以外の入口からも16体目を開けない（クリアの記録・続けて挑戦のチケット）。
Deno.test("record-challenge-clear also uses a slot: a clear for a 16th boss is refused and not recorded; challenged bosses are recorded", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) await attempt(fake, n);
  const clear = (n: number, verifier = demoPlayer()) =>
    handleRecordChallengeClear(post("record-challenge-clear", { ticket: "aabbcc", boss_id: bossId(n) }), verifier, fake, FULL_APP);
  const refused = await clear(16);
  const refusedBody = await refused.json();
  assertEquals([refused.status, refusedBody.error_kind, refusedBody.demo_used, refusedBody.demo_limit], [403, "demo_challenge_limit", 15, 15]);
  assertEquals(fake.rowsOf("boss_challenge_records").some((r) => r.boss_id === bossId(16)), false, "no record for the 16th");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
  const known = await clear(4);
  assertEquals(known.status, 200);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15, "a challenged boss does not use another slot");
  // 製品版は今までどおり
  assertEquals((await clear(17, fullPlayer())).status, 200);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
});

Deno.test("a clear sent without a challenge record counts as the first challenge of that boss (one slot, never two)", async () => {
  const fake = db();
  const clear = () => handleRecordChallengeClear(post("record-challenge-clear", { ticket: "aabbcc", boss_id: bossId(5) }), demoPlayer(), fake, FULL_APP);
  assertEquals((await clear()).status, 200);
  assertEquals((await clear()).status, 200);
  assertEquals((await attempt(fake, 5)).body.demo_used, 1);
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 1);
});

Deno.test("submit-battle-result: a next ticket for a 16th boss is not issued; the same boss (continue) still gets one", async () => {
  const fake = db();
  for (let n = 1; n <= 15; n++) await attempt(fake, n);
  const next = async (n: number, verifier = demoPlayer()) => {
    const res = await handleSubmitBattleResult(post("submit-battle-result", { ticket: "aabbcc", results: [], next_ticket_boss_id: bossId(n) }), verifier, fake, FULL_APP);
    return { status: res.status, body: await res.json() };
  };
  const ticketsBefore = fake.rowsOf("boss_battle_tickets").length;
  const refused = await next(16);
  assertEquals([refused.status, refused.body.next_battle_ticket, refused.body.next_ticket_status], [200, undefined, "demo_challenge_limit"]);
  assertEquals(fake.rowsOf("boss_battle_tickets").length, ticketsBefore, "no ticket for the 16th");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
  const same = await next(15);
  assertEquals(typeof same.body.next_battle_ticket, "string");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
  // 製品版は制限なし・枠を使わない
  assertEquals(typeof (await next(18, fullPlayer())).body.next_battle_ticket, "string");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 15);
});

Deno.test("submit-battle-result: a next ticket for a new boss under 15 uses one slot (it starts that boss's first battle)", async () => {
  const fake = db();
  await attempt(fake, 1);
  const res = await handleSubmitBattleResult(post("submit-battle-result", { ticket: "aabbcc", results: [], next_ticket_boss_id: bossId(2) }), demoPlayer(), fake, FULL_APP);
  assertEquals(typeof (await res.json()).next_battle_ticket, "string");
  assertEquals(fake.rowsOf("demo_challenge_slots").length, 2);
});
