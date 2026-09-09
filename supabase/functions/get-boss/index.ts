// Phase 4D — 選択したオンラインボスのpayload(全体)を取得する。
// 公開済み(is_published=true)のボスのみ返す——RLSのbosses_select_published_only
// ポリシーと同じ条件をアプリ層でも明示する。
//
// battle_hashの再計算・payload内容の意味検証はここでは行わない
// (Godotクライアント側のRBMOnlineBossPayload.validate_for_challenge()が
// schema_version確認→型検証→battle_hash再計算・突合を担う設計、
// §4D-3)。ここは「公開済みの該当行をそのまま返す」だけの単純な読み取り。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

export interface BossDetailRow {
  id: string;
  boss_name: string;
  author_name: string;
  owner_steam_id: string;
  revision: number;
  published_at: string;
  payload: Record<string, unknown>;
}

export interface GetBossResponseBody {
  ok: boolean;
  boss?: BossDetailRow;
  error_kind?: string;
  message?: string;
}

function jsonResponse(body: GetBossResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const UUID_PATTERN = /^[0-9a-fA-F-]{36}$/;

export async function handleGetBoss(req: Request, db: SupabaseRestClient): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }
  const url = new URL(req.url);
  const id = url.searchParams.get("id") ?? "";
  if (!UUID_PATTERN.test(id)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'id' must be a valid boss id" }, 400);
  }

  const result = await db.select<BossDetailRow>(
    "bosses",
    `id=eq.${id}&is_published=eq.true&select=id,boss_name,author_name,owner_steam_id,revision,published_at,payload`,
  );
  if (!result.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: result.errorMessage ?? "" }, 502);
  }
  if (result.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "not_found", message: "Boss not found or not published" }, 404);
  }
  return jsonResponse({ ok: true, boss: result.rows[0] }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleGetBoss(req, db);
  });
}
