// 2026-10-28 製品版／体験版のサーバー側の制限のテスト。実Steam/実Supabaseへは一切出ない。
// 実行方法: deno test supabase/functions/_shared/edition.test.ts

import { assertEquals } from "jsr:@std/assert";
import { demoCondition, isDemoBoss, isDemoPayload } from "./edition.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import {
  AuthenticateUserTicketParams,
  RawHttpResult,
  SteamWebApiClient,
} from "../steam-auth/steam_web_api_client.ts";
import { handlePublish, PublishResponseBody } from "../publish-boss/index.ts";
import { FakeSupabaseRestClient } from "./fake_supabase_rest_client.ts";

const FULL_APP = 5482410;
const DEMO_APP = 9990001; // テスト用の値(本物の体験版のAppIDではない)

// チケットが ticketApp のアプリのものとして発行された時の Steam の応答を真似る。
class AppAwareSteamClient implements SteamWebApiClient {
  public calls: number[] = [];
  constructor(private readonly ticketApp: number, private readonly steamId = "76561198000000009") {}
  authenticateUserTicket(params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    this.calls.push(params.appId);
    if (params.appId === this.ticketApp) {
      return Promise.resolve({ status: 200, body: JSON.stringify({ response: { params: { result: "OK", steamid: this.steamId } } }) });
    }
    return Promise.resolve({ status: 200, body: JSON.stringify({ response: { error: { errorcode: 101, errordesc: "Invalid ticket" } } }) });
  }
}

function verifier(ticketApp: number, demoAppId: number) {
  const client = new AppAwareSteamClient(ticketApp);
  return { client, verifier: new SteamTicketVerifier({ client, publisherWebApiKey: "dummy-test-key", demoAppId }) };
}

let hashSeed = 0;
function payload(appearance: string, mode = "simple") {
  // 公開ごとに別の battle_hash(同じ値だと二重投稿の防止で同じ行が返る)。
  hashSeed = (hashSeed + 1) % 16;
  return {
    schema_version: 1,
    boss_name: "体験版のボス",
    author_name: "作者",
    draft_fields: { hp: 1000, atk: 100, spd: 50, appearance_id: appearance, creator_mode: mode },
    clear_check_success_snapshot: { hp: 1000 },
    battle_hash: hashSeed.toString(16).repeat(64),
  };
}

function publishRequest(body: unknown): Request {
  return new Request("http://localhost/publish-boss", { method: "POST", body: JSON.stringify(body) });
}

function freshDb(): FakeSupabaseRestClient {
  const db = new FakeSupabaseRestClient();
  db.addUniqueConstraint({ table: "bosses", columns: ["idempotency_key"] });
  return db;
}

Deno.test("a full-version ticket is verified once against the full AppID only, unchanged", async () => {
  const { client, verifier: v } = verifier(FULL_APP, DEMO_APP);
  const result = await v.verifyTicket("abcd", FULL_APP, "id");
  assertEquals(result.ok, true);
  assertEquals(result.edition, "full");
  assertEquals(client.calls, [FULL_APP]);
});

Deno.test("a trial ticket is accepted against the trial AppID and marked as demo", async () => {
  const { client, verifier: v } = verifier(DEMO_APP, DEMO_APP);
  const result = await v.verifyTicket("abcd", FULL_APP, "id");
  assertEquals(result.ok, true);
  assertEquals(result.edition, "demo");
  assertEquals(client.calls, [FULL_APP, DEMO_APP]);
});

Deno.test("without a trial AppID configured, a trial ticket is rejected as before", async () => {
  const { client, verifier: v } = verifier(DEMO_APP, 0);
  const result = await v.verifyTicket("abcd", FULL_APP, "id");
  assertEquals(result.ok, false);
  assertEquals(client.calls, [FULL_APP]);
});

Deno.test("demo boss rules: SIMPLE and one of the four trial bosses", () => {
  assertEquals(isDemoBoss("simple", "appearance_dragon"), true);
  assertEquals(isDemoBoss(undefined, "appearance_musha"), true, "old data without a mode is SIMPLE");
  assertEquals(isDemoBoss("advanced", "appearance_dragon"), false);
  assertEquals(isDemoBoss("simple", "appearance_golem"), false);
  assertEquals(isDemoPayload(payload("appearance_ghost")), true);
  assertEquals(demoCondition().includes("appearance_id.in.(appearance_dragon,appearance_slime,appearance_ghost,appearance_musha)"), true);
});

Deno.test("the trial can publish two bosses, a third is refused, and unpublishing frees a slot", async () => {
  const db = freshDb();
  const ids: string[] = [];
  for (const appearance of ["appearance_dragon", "appearance_slime"]) {
    const res = await handlePublish(publishRequest({ ticket: "abcd", payload: { ...payload(appearance), boss_name: appearance } }), verifier(DEMO_APP, DEMO_APP).verifier, db, FULL_APP);
    assertEquals(res.status, 201);
    ids.push(((await res.json()) as PublishResponseBody).boss_id as string);
  }
  const third = await handlePublish(publishRequest({ ticket: "abcd", payload: { ...payload("appearance_ghost"), boss_name: "third" } }), verifier(DEMO_APP, DEMO_APP).verifier, db, FULL_APP);
  assertEquals(third.status, 403);
  assertEquals(((await third.json()) as PublishResponseBody).error_kind, "demo_publish_limit");
  // 公開中のボスの更新は数えない
  const update = await handlePublish(publishRequest({ ticket: "abcd", boss_id: ids[0], payload: { ...payload("appearance_dragon"), boss_name: "updated" } }), verifier(DEMO_APP, DEMO_APP).verifier, db, FULL_APP);
  assertEquals(update.status, 200);
  // 1体を非公開にすると入れ替えられる
  await db.update("bosses", `id=eq.${ids[1]}`, { is_published: false });
  const swap = await handlePublish(publishRequest({ ticket: "abcd", payload: { ...payload("appearance_ghost"), boss_name: "swap" } }), verifier(DEMO_APP, DEMO_APP).verifier, db, FULL_APP);
  assertEquals(swap.status, 201);
});

Deno.test("the trial cannot publish a HARDCORE boss or a full-version-only boss", async () => {
  for (const [appearance, mode] of [["appearance_dragon", "advanced"], ["appearance_golem", "simple"]]) {
    const res = await handlePublish(publishRequest({ ticket: "abcd", payload: payload(appearance, mode) }), verifier(DEMO_APP, DEMO_APP).verifier, freshDb(), FULL_APP);
    assertEquals(res.status, 403);
    assertEquals(((await res.json()) as PublishResponseBody).error_kind, "demo_not_allowed");
  }
});

Deno.test("full-version users keep publishing without any trial limit", async () => {
  const db = freshDb();
  for (const appearance of ["appearance_golem", "appearance_knight", "appearance_wolf"]) {
    const res = await handlePublish(publishRequest({ ticket: "abcd", payload: { ...payload(appearance, "advanced"), boss_name: appearance } }), verifier(FULL_APP, DEMO_APP).verifier, db, FULL_APP);
    assertEquals(res.status, 201);
  }
});

Deno.test("trial tickets cannot record or get battle tickets for full-version-only bosses", async () => {
  const { demoBossRejection } = await import("./edition.ts");
  const { FakePostgrestClient } = await import("./fake_postgrest_client.ts");
  const db = new FakePostgrestClient();
  db.seed("bosses", [
    { id: "hard", boss_name: "h", author_name: "a", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: payload("appearance_dragon", "advanced") },
    { id: "golem", boss_name: "g", author_name: "a", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: payload("appearance_golem") },
    { id: "trial", boss_name: "t", author_name: "a", published_at: "2026-01-01T00:00:00Z", revision: 1, is_published: true, payload: payload("appearance_musha") },
  ]);
  assertEquals(await demoBossRejection(db, "hard", "demo"), "demo_unavailable");
  assertEquals(await demoBossRejection(db, "golem", "demo"), "demo_unavailable");
  assertEquals(await demoBossRejection(db, "trial", "demo"), null);
  assertEquals(await demoBossRejection(db, "hard", "full"), null, "full-version tickets are never limited");
  assertEquals(await demoBossRejection(db, "hard", undefined), null);
});
