// Phase 4D — 公開済みボス一覧の取得。
//
// 一覧では概要のみを返す(§4D-2「巨大なpayloadを一覧取得時に毎回全部
// 落とす必要がないなら、一覧用queryと詳細取得を分ける」)——full payload
// はget-bossでのみ返す。認証は不要(公開済みデータの閲覧のみ、RLSの
// bosses_select_published_onlyポリシーと同じ「公開済みのみ」条件を
// アプリ層でも明示する)。
//
// 挑戦ハブ SIMPLE/HARDCORE連携（2026-09）— boss_name等と違い、
// creator_mode(SIMPLE/HARDCORE)はbossesテーブルの独立カラムではなく
// payload.draft_fields.creator_mode(jsonb)にのみ存在する。DBスキーマは
// 変更せず、このEdge Function側でpayloadから抽出したcreator_modeだけを
// レスポンスへ足す——full payload自体は従来どおり一覧レスポンスへ含めない
// (「summary rows never include the full payload field」契約を維持)。
// 任意のmode(simple/advanced)フィルタもここで行う。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const DEFAULT_CREATOR_MODE = "simple";
const VALID_MODES = new Set(["simple", "advanced"]);

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
}

export interface ListBossesResponseBody {
  ok: boolean;
  bosses?: BossSummaryRow[];
  error_kind?: string;
  message?: string;
}

interface BossRowWithPayload {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  payload?: Record<string, unknown>;
}

function jsonResponse(body: ListBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// payload.draft_fields.creator_modeが欠けている/不正な形の既存データは、
// クライアント側の既存フォールバック規約(RBMCreatorDraft.CREATOR_MODE_SIMPLE
// が既定)と一致させ、SIMPLE扱いにする。
function extractCreatorMode(payload: unknown): string {
  if (typeof payload !== "object" || payload === null) return DEFAULT_CREATOR_MODE;
  const draftFields = (payload as Record<string, unknown>).draft_fields;
  if (typeof draftFields !== "object" || draftFields === null) return DEFAULT_CREATOR_MODE;
  const mode = (draftFields as Record<string, unknown>).creator_mode;
  return VALID_MODES.has(String(mode)) ? String(mode) : DEFAULT_CREATOR_MODE;
}

export async function handleListBosses(req: Request, db: SupabaseRestClient): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }

  const url = new URL(req.url);
  const requestedLimit = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
  const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
    ? Math.min(requestedLimit, MAX_LIMIT)
    : DEFAULT_LIMIT;

  const requestedMode = url.searchParams.get("mode");
  const modeFilter = requestedMode !== null && VALID_MODES.has(requestedMode) ? requestedMode : null;

  // creator_modeはjsonb内にしかないため、mode絞り込み前にDB側のlimitで
  // 打ち切ると取りこぼす(新しい20件がたまたま全てHARDCOREだと、SIMPLE絞り
  // 込み結果が本来より少なく見える)。そのため常にサーバー上限(MAX_LIMIT)
  // まで取得し、mode絞り込みとクライアント指定limitの適用はこの関数の中で
  // 行う。
  const result = await db.select<BossRowWithPayload>(
    "bosses",
    `is_published=eq.true&select=id,boss_name,author_name,published_at,revision,payload&order=published_at.desc&limit=${MAX_LIMIT}`,
  );
  if (!result.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: result.errorMessage ?? "" }, 502);
  }

  let bosses: BossSummaryRow[] = result.rows.map((row) => ({
    id: row.id,
    boss_name: row.boss_name,
    author_name: row.author_name,
    published_at: row.published_at,
    revision: row.revision,
    creator_mode: extractCreatorMode(row.payload),
  }));

  if (modeFilter !== null) {
    bosses = bosses.filter((boss) => boss.creator_mode === modeFilter);
  }
  bosses = bosses.slice(0, limit);

  return jsonResponse({ ok: true, bosses }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleListBosses(req, db);
  });
}
