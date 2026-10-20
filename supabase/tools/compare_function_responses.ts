// 変更前（HEAD）と変更後（作業ツリー）の読み取りの関数に、同じ偽の DB を渡して応答を比べる（2026-10-18）。
// 今のゲーム（クライアント）が読む項目が、名前・型・値とも変わっていないかを確かめる。
// 実行: deno run --allow-read compare_function_responses.ts <変更前の functions> <変更後の functions>
// 違ってよいもの: next_cursor の中身（ゲームはそのまま送り返すだけ）、get-boss の owner_steam_id（消した）。

const [oldRoot, newRoot] = Deno.args;
const toUrl = (root: string, rel: string) => new URL(`file:///${root.replace(/\\/g, "/")}/${rel}`).href;

async function load(root: string) {
  return {
    Fake: (await import(toUrl(root, "_shared/fake_postgrest_client.ts"))).FakePostgrestClient,
    listBosses: (await import(toUrl(root, "list-bosses/index.ts"))).handleListBosses,
    popular: (await import(toUrl(root, "list-popular-bosses/index.ts"))).handleListPopularBosses,
    hard: (await import(toUrl(root, "list-hard-bosses/index.ts"))).handleListHardBosses,
    unchallenged: (await import(toUrl(root, "list-unchallenged-bosses/index.ts"))).handleListUnchallengedBosses,
    getBoss: (await import(toUrl(root, "get-boss/index.ts"))).handleGetBoss,
    Verifier: (await import(toUrl(root, "steam-auth/steam_ticket_verifier.ts"))).SteamTicketVerifier,
  };
}

function seed(Fake: any) {
  const db = new Fake();
  const bosses = [];
  for (let i = 0; i < 30; i++) {
    bosses.push({
      id: `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
      boss_name: `ボス${i}`,
      author_name: `作者${i % 4}`,
      owner_steam_id: `7656119000000${String(i).padStart(4, "0")}`,
      published_at: new Date(Date.UTC(2026, 8, 1 + (i % 20), i % 24)).toISOString(),
      revision: 1 + (i % 3),
      is_published: i % 7 !== 3,
      payload: { draft_fields: { creator_mode: i % 2 ? "advanced" : "simple", appearance_id: i % 5 === 0 ? 42 : `appearance_${["slime", "wolf", "golem"][i % 3]}` } },
    });
  }
  db.seed("bosses", bosses);
  const records = [];
  for (let i = 0; i < 30; i++) {
    for (let j = 0; j < (i * 7) % 9; j++) {
      records.push({ id: `r${i}-${j}`, boss_id: bosses[i].id, challenger_steam_id: `76561190001${String(j).padStart(5, "0")}`, challenge_count: 1 + (j % 3), clear_count: (i + j) % 4 === 0 ? 1 : 0 });
    }
  }
  db.seed("boss_challenge_records", records);
  return { db, firstId: bosses[0].id };
}

const get = (path: string) => new Request(`http://localhost/${path}`, { method: "GET" });

async function run(mod: any) {
  const out: Record<string, unknown> = {};
  const call = async (name: string, f: (db: any) => Promise<Response>) => {
    const { db } = seed(mod.Fake);
    const res = await f(db);
    out[name] = { status: res.status, body: await res.json() };
  };
  const verifier = () => new mod.Verifier({
    client: { authenticateUserTicket: () => Promise.resolve({ status: 200, body: JSON.stringify({ response: { params: { result: "OK", steamid: "76561190001000001" } } }) }) },
    publisherWebApiKey: "dummy-test-key",
  });
  await call("list-bosses", (db) => mod.listBosses(get("list-bosses?limit=10"), db));
  await call("list-bosses simple", (db) => mod.listBosses(get("list-bosses?limit=10&mode=simple"), db));
  await call("list-bosses advanced", (db) => mod.listBosses(get("list-bosses?limit=10&mode=advanced"), db));
  await call("list-popular-bosses", (db) => mod.popular(get("list-popular-bosses?limit=10"), db));
  await call("list-hard-bosses", (db) => mod.hard(get("list-hard-bosses?limit=10"), db));
  await call("list-popular-bosses simple", (db) => mod.popular(get("list-popular-bosses?limit=10&mode=simple"), db));
  await call("list-unchallenged-bosses", (db) => mod.unchallenged(new Request("http://localhost/x", { method: "POST", body: JSON.stringify({ ticket: "aabbcc", limit: 10 }) }), verifier(), db, 480));
  await call("get-boss", (db) => mod.getBoss(get("get-boss?id=00000000-0000-4000-8000-000000000000"), db));
  // 2ページ目（それぞれ自分の next_cursor で）
  const page1 = out["list-bosses"] as any;
  if (page1.body.next_cursor) {
    await call("list-bosses page2", (db) => mod.listBosses(get(`list-bosses?limit=10&cursor=${encodeURIComponent(page1.body.next_cursor)}`), db));
  }
  return out;
}

const before = await run(await load(oldRoot));
const after = await run(await load(newRoot));
const diffs: string[] = [];
const IGNORE = new Set(["next_cursor"]);
function compare(path: string, a: unknown, b: unknown) {
  if (IGNORE.has(path.split(".").pop() ?? "")) return;
  if (typeof a !== typeof b || Array.isArray(a) !== Array.isArray(b)) {
    diffs.push(`${path}: type ${JSON.stringify(a)} -> ${JSON.stringify(b)}`);
    return;
  }
  if (a && typeof a === "object") {
    const keys = new Set([...Object.keys(a as object), ...Object.keys(b as object)]);
    for (const k of keys) compare(`${path}.${k}`, (a as any)[k], (b as any)[k]);
    return;
  }
  if (a !== b) diffs.push(`${path}: ${JSON.stringify(a)} -> ${JSON.stringify(b)}`);
}
for (const name of Object.keys(before)) compare(name, before[name], after[name]);
const summary = Object.fromEntries(Object.entries(after).map(([k, v]: [string, any]) => [k, { status: v.status, bosses: v.body.bosses?.length ?? (v.body.boss ? 1 : undefined), has_more: v.body.has_more }]));
console.log(JSON.stringify({ summary, diffs }, null, 2));

// 古い形の続きの印（変更前のサーバーが出した next_cursor）を、変更後のサーバーへ送っても同じ2ページ目になるか
// （デプロイの瞬間に一覧を開いていた人の「さらに表示」が壊れない）
{
  const oldMod = await load(oldRoot);
  const newMod = await load(newRoot);
  const oldCursor = (before["list-bosses"] as any).body.next_cursor;
  const r1 = await newMod.listBosses(get(`list-bosses?limit=10&cursor=${encodeURIComponent(oldCursor)}`), seed(newMod.Fake).db);
  const crossBody = await r1.json();
  const crossDiffs: string[] = [];
  const keep = diffs.length;
  compare("cross-cursor page2", (before["list-bosses page2"] as any).body, crossBody);
  crossDiffs.push(...diffs.splice(keep));
  console.log(JSON.stringify({ old_cursor_accepted_by_new_server: r1.status === 200, cross_cursor_diffs: crossDiffs }, null, 2));
  void oldMod;
}
