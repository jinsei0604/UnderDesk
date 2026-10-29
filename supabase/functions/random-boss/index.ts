// 2026-10-17 プレイ体験監査 PX-03 — ランダム挑戦。挑戦トップの「ランダムで挑戦」から呼ぶ。
//
// 公開中のボス全体(mode=simple/advancedなら、そのモードのボス全体)から、どのボスも同じ確率で1件選ぶ。
// 未挑戦には限らない(ユーザー確定仕様)。exclude(今表示しているボスのid)を渡すと、それ以外から選ぶ
// (「もう一度引く」で同じボスが続かないように。それ以外が無ければ、そのボスを返す)。
//
// 負荷(Supabaseの無料枠): 公開中の全ボスを読まない。
//   1. 条件に合うボスの数だけを数える(HEAD + Prefer: count=exact。行は読まない)
//   2. 0〜数-1 の乱数の位置の1件だけを読む(id順の offset、limit=1。カードに要る列だけ)
//   3. そのボスの挑戦者数・クリアした人数を数える(_shared/boss_card_fields.ts)
// 1と2の間にボスが取り下げられて位置に行が無かった時だけ、もう一度だけ数え直す。
//
// 応答は list-bosses と同じ形の bosses(0件か1件)。認証は不要(公開済みのボスの閲覧だけ)。

import { RealSupabaseRestClient, SupabaseCountingRestClient } from "../_shared/supabase_rest_client.ts";
import { loadChallengeStats } from "../_shared/boss_card_fields.ts";
import {
  BossSummaryDbRow,
  dbError,
  isUuid,
  jsonResponse,
  modeCondition,
  publicBossFilter,
  publicBossQuery,
  requestedMode,
  toPublicRow,
} from "../_shared/public_boss_query.ts";
import { bodyRequestsDemo, demoCondition, isDemoPayload, requestedDemo } from "../_shared/edition.ts";

// 0以上1未満の乱数(テストでは決まった値を渡す)。
export type RandomSource = () => number;

export function cryptoRandom(): number {
  return crypto.getRandomValues(new Uint32Array(1))[0] / 0x1_0000_0000;
}

const MAX_ATTEMPTS = 2;

export async function handleRandomBoss(req: Request, db: SupabaseCountingRestClient, random: RandomSource = cryptoRandom): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }
  const url = new URL(req.url);
  const mode = requestedMode(url);
  const exclude = (url.searchParams.get("exclude") ?? "").toLowerCase();
  const base = mode !== null ? [modeCondition(mode)] : [];
  // 体験版(?edition=demo、2026-10-28): 体験版で挑戦できるボスだけから選ぶ。
  if (requestedDemo(url)) base.push(demoCondition());

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    let conditions = isUuid(exclude) ? [...base, `id.neq.${exclude}`] : base;
    let counted = await db.count("bosses", publicBossFilter(conditions));
    if (!counted.ok) return dbError(counted);
    if (counted.count === 0 && conditions !== base) {
      // 今のボスしか無い——そのボスをもう一度出す。
      conditions = base;
      counted = await db.count("bosses", publicBossFilter(conditions));
      if (!counted.ok) return dbError(counted);
    }
    if (counted.count === 0) {
      return jsonResponse({ ok: true, bosses: [] }, 200);
    }
    const offset = Math.min(counted.count - 1, Math.floor(random() * counted.count));
    const picked = await db.select<BossSummaryDbRow>("bosses", publicBossQuery(conditions, `order=id.asc&offset=${offset}&limit=1`));
    if (!picked.ok) return dbError(picked);
    if (picked.rows.length === 0) continue; // 数えた後に取り下げられた——数え直す
    const row = picked.rows[0];
    const statsLookup = await loadChallengeStats(db, [String(row.id)]);
    if (!statsLookup.ok) return dbError(statsLookup);
    return jsonResponse({ ok: true, bosses: [toPublicRow(row, statsLookup.stats.get(String(row.id))!)] }, 200);
  }
  return jsonResponse({ ok: true, bosses: [] }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleRandomBoss(req, db);
  });
}
