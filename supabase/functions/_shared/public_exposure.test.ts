// 公開情報の確認（2026-10-18）: 読み取りの関数すべてで、公開した人・挑戦した人の SteamID と、
// 内部の列（owner_steam_id・challenger_steam_id・battle_hash・idempotency_key）が応答に出ないこと。
// 同じ偽の DB（PostgREST と同じ絞り込み）に、見分けやすい SteamID を入れて、各関数をそのまま動かす。
// 実際の Supabase・Steam へは出ない。実行: このフォルダの親（supabase/functions）で deno test。

import { assert, assertEquals } from "jsr:@std/assert";
import { FakePostgrestClient } from "./fake_postgrest_client.ts";
import { handleListBosses } from "../list-bosses/index.ts";
import { handleListPopularBosses } from "../list-popular-bosses/index.ts";
import { handleListHardBosses } from "../list-hard-bosses/index.ts";
import { handleListUnchallengedBosses } from "../list-unchallenged-bosses/index.ts";
import { handleSearchBosses } from "../search-bosses/index.ts";
import { handleRandomBoss } from "../random-boss/index.ts";
import { handleGetBoss } from "../get-boss/index.ts";
import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { AuthenticateUserTicketParams, RawHttpResult, SteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";

const OWNER = "76561190000000111";
const CHALLENGER = "76561190000000222";
const CALLER = "76561190000000333";
const BOSS_ID = "11111111-2222-4333-8444-555555555555";
const FORBIDDEN = [OWNER, CHALLENGER, CALLER, "7656119000000099", "owner_steam_id", "challenger_steam_id", "battle_hash", "idempotency_key", "secret-hash-value"];

class StubSteamClient implements SteamWebApiClient {
  authenticateUserTicket(_params: AuthenticateUserTicketParams): Promise<RawHttpResult> {
    return Promise.resolve({ status: 200, body: JSON.stringify({ response: { params: { result: "OK", steamid: CALLER } } }) });
  }
}

function db(): FakePostgrestClient {
  const fake = new FakePostgrestClient();
  fake.seed("bosses", [{
    id: BOSS_ID,
    boss_name: "公開の確認のボス",
    author_name: "作者",
    owner_steam_id: OWNER,
    battle_hash: "secret-hash-value",
    idempotency_key: "secret-hash-value",
    published_at: "2026-10-01T00:00:00Z",
    revision: 3,
    is_published: true,
    payload: { draft_fields: { creator_mode: "simple", appearance_id: "appearance_golem", boss_name: "公開の確認のボス" } },
  }]);
  // 高難度は挑戦者5人以上のボスだけを出すので、5人分（1人目が見分けやすい SteamID）
  fake.seed("boss_challenge_records", [0, 1, 2, 3, 4].map((i) => ({
    id: `r${i}`,
    boss_id: BOSS_ID,
    challenger_steam_id: i === 0 ? CHALLENGER : `7656119000000099${i}`,
    challenge_count: 2,
    clear_count: i === 0 ? 1 : 0,
  })));
  return fake;
}

async function bodyOf(res: Response): Promise<{ status: number; text: string }> {
  return { status: res.status, text: await res.text() };
}

const get = (path: string) => new Request(`http://localhost/${path}`, { method: "GET" });

const cases: { name: string; run: () => Promise<Response> }[] = [
  { name: "list-bosses", run: () => handleListBosses(get("list-bosses?limit=5"), db()) },
  { name: "list-popular-bosses", run: () => handleListPopularBosses(get("list-popular-bosses?limit=5"), db()) },
  { name: "list-hard-bosses", run: () => handleListHardBosses(get("list-hard-bosses?limit=5"), db()) },
  { name: "search-bosses", run: () => handleSearchBosses(get(`search-bosses?q=${encodeURIComponent("公開")}`), db()) },
  { name: "random-boss", run: () => handleRandomBoss(get("random-boss"), db(), () => 0) },
  { name: "get-boss", run: () => handleGetBoss(get(`get-boss?id=${BOSS_ID}`), db()) },
  {
    name: "list-unchallenged-bosses",
    run: () =>
      handleListUnchallengedBosses(
        new Request("http://localhost/list-unchallenged-bosses", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", limit: 5 }) }),
        new SteamTicketVerifier({ client: new StubSteamClient(), publisherWebApiKey: "dummy-test-key" }),
        db(),
        480,
      ),
  },
];

for (const c of cases) {
  Deno.test(`${c.name}: never returns a SteamID or an internal column`, async () => {
    const { status, text } = await bodyOf(await c.run());
    assertEquals(status, 200, `${c.name} answered`);
    assert(text.includes(BOSS_ID), `${c.name} returned the public boss (the check is not vacuous)`);
    for (const word of FORBIDDEN) {
      assert(!text.includes(word), `${c.name} must not return "${word}"`);
    }
  });
}
