// Phase 4D — 公開済みボス一覧の取得。
//
// 一覧では概要のみを返す(§4D-2「巨大なpayloadを一覧取得時に毎回全部
// 落とす必要がないなら、一覧用queryと詳細取得を分ける」)——full payload
// はget-bossでのみ返す。認証は不要(公開済みデータの閲覧のみ、RLSの
// bosses_select_published_onlyポリシーと同じ「公開済みのみ」条件を
// アプリ層でも明示する)。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
}

export interface ListBossesResponseBody {
  ok: boolean;
  bosses?: BossSummaryRow[];
  error_kind?: string;
  message?: string;
}

function jsonResponse(body: ListBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

  const result = await db.select<BossSummaryRow>(
    "bosses",
    `is_published=eq.true&select=id,boss_name,author_name,published_at,revision&order=published_at.desc&limit=${limit}`,
  );
  if (!result.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: result.errorMessage ?? "" }, 502);
  }
  return jsonResponse({ ok: true, bosses: result.rows }, 200);
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
