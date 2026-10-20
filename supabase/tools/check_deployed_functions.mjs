// 本番の Edge Functions の読み取りだけの確認（2026-10-20、デプロイの前後で同じものを流す）。
// 接続先と公開用の鍵は supabase_poc.local.env から読む。値は出力しない（状態コード・項目の名前・件数だけ）。
// 書き込む関数は呼ばない。Steam の ticket が要る関数は、ticket 無し・形だけの ticket で入口の振る舞いだけを見る。
// 実行（リポジトリの直下）: node supabase/tools/check_deployed_functions.mjs [出力.json]
import fs from "node:fs";

const env = Object.fromEntries(
  fs.readFileSync("supabase_poc.local.env", "utf8").split(/\r?\n/)
    .filter((l) => l.includes("=") && !l.trim().startsWith("#"))
    .map((l) => [l.slice(0, l.indexOf("=")).trim(), l.slice(l.indexOf("=") + 1).trim()]),
);
const URL_BASE = env.SUPABASE_URL;
const KEY = env.SUPABASE_PUBLISHABLE_KEY;
if (!URL_BASE || !KEY) throw new Error("config missing");
const STEAM_ID_LIKE = /765611\d{11}/;

async function call(label, path, { method = "GET", body, key = KEY } = {}) {
  const res = await fetch(`${URL_BASE}${path}`, {
    method,
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  const entry = {
    label, status: res.status,
    keys: json && typeof json === "object" && !Array.isArray(json) ? Object.keys(json).sort() : (Array.isArray(json) ? ["<array>"] : []),
    bosses: json && Array.isArray(json.bosses) ? json.bosses.length : undefined,
    rows: Array.isArray(json) ? json.length : undefined,
    error_kind: json && json.error_kind ? json.error_kind : undefined,
    leaks_steam_id: STEAM_ID_LIKE.test(text) || text.includes("owner_steam_id") || text.includes("challenger_steam_id"),
  };
  console.log(JSON.stringify(entry));
  return entry;
}

const fn = (name) => `/functions/v1/${name}`;
const out = [];
// 読み取りの関数（正しい公開用の鍵）
out.push(await call("list-bosses", fn("list-bosses?limit=5")));
out.push(await call("list-bosses mode=simple", fn("list-bosses?limit=5&mode=simple")));
out.push(await call("list-bosses old cursor", fn(`list-bosses?limit=5&cursor=${encodeURIComponent(Buffer.from(JSON.stringify({ p: 1760000000000, i: "00000000-0000-4000-8000-000000000000" })).toString("base64url"))}`)));
out.push(await call("list-popular-bosses", fn("list-popular-bosses?limit=5")));
out.push(await call("list-hard-bosses", fn("list-hard-bosses?limit=5")));
out.push(await call("search-bosses", fn(`search-bosses?q=${encodeURIComponent("zz-check")}`)));
out.push(await call("random-boss", fn("random-boss")));
out.push(await call("get-boss missing id", fn("get-boss?id=00000000-0000-4000-8000-000000000000")));
out.push(await call("get-boss invalid id", fn("get-boss?id=not-a-uuid")));
// Steam の ticket が要る関数（入口だけ）
out.push(await call("list-unchallenged no ticket", fn("list-unchallenged-bosses"), { method: "POST", body: {} }));
out.push(await call("list-unchallenged fake ticket", fn("list-unchallenged-bosses"), { method: "POST", body: { ticket: "aabbcc", limit: 5 } }));
// 違う鍵（JWT の確認が効いているか）
const BAD = "sb_publishable_this_key_does_not_exist_0000";
out.push(await call("list-bosses bad key", fn("list-bosses?limit=5"), { key: BAD }));
out.push(await call("get-boss bad key", fn("get-boss?id=00000000-0000-4000-8000-000000000000"), { key: BAD }));
// 表を直接読めないか（公開範囲）
out.push(await call("REST bosses (direct)", "/rest/v1/bosses?select=id,owner_steam_id&limit=1"));
out.push(await call("REST boss_challenge_records (direct)", "/rest/v1/boss_challenge_records?select=boss_id,challenger_steam_id&limit=1"));
if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 2));
