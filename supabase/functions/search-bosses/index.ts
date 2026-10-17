// 2026-10-17 プレイ体験監査 PX-03 — 公開ボスの検索。挑戦トップの「ボスを検索」から呼ぶ。
//
// q(検索語)で、ボス名・作者名の部分一致(大文字小文字を区別しない)と、公開ID(idの先頭8文字)・
// id(UUID全体)を探す。mode(simple/advanced)で絞れる。並びは list-bosses と同じ
// 「公開日時の新しい順、同じ公開日時ならid順」。続きは cursor で読む(list-bossesと同じく位置で続きを
// 決めるので、閲覧中に新しいボスが公開されても続きに重複・飛ばしが起きない)。
//
// 負荷(Supabaseの無料枠): 公開中の全ボスを読まない。絞り込み・並べ替え・件数の打ち切りをDBで行い
// (1回の問い合わせで limit+1 件まで)、カードに要る列だけを読む。挑戦者数・クリアした人数は
// 返すページのボスの分だけ数える(_shared/boss_card_fields.ts、list-bossesと同じ)。ゲームは文字を
// 打つたびには呼ばない(検索ボタン・Enterの時だけ)。
//
// 認証は不要(公開済みのボスの閲覧だけ。list-bossesと同じ)。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { loadChallengeStats } from "../_shared/boss_card_fields.ts";
import {
  BossSummaryDbRow,
  dbError,
  jsonResponse,
  modeCondition,
  PublicBossListResponseBody,
  publicBossQuery,
  requestedMode,
  searchCondition,
  toPublicRow,
} from "../_shared/public_boss_query.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
export const MAX_QUERY_LENGTH = 50;

// 並び順の上での位置(公開日時はDBが返した文字列のまま。ミリ秒へ丸めると、同じミリ秒の中の行を飛ばすため)。
export interface SearchCursorPosition {
  publishedAt: string;
  id: string;
}

export function encodeSearchCursor(position: SearchCursorPosition): string {
  const bytes = new TextEncoder().encode(JSON.stringify({ p: position.publishedAt, i: position.id }));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

// 壊れたcursorならnull。問い合わせの文字列へ入れるので、公開日時・idの形も確かめる。
export function decodeSearchCursor(cursor: string): SearchCursorPosition | null {
  if (!/^[A-Za-z0-9_-]+$/.test(cursor)) return null;
  try {
    const base64 = cursor.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - cursor.length % 4) % 4);
    const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (typeof parsed !== "object" || parsed === null) return null;
    const { p, i } = parsed as Record<string, unknown>;
    if (typeof p !== "string" || !/^[0-9T:.+\- Z]+$/.test(p) || !Number.isFinite(Date.parse(p))) return null;
    if (typeof i !== "string" || !/^[0-9a-f-]{1,36}$/.test(i)) return null;
    return { publishedAt: p, id: i };
  } catch {
    return null;
  }
}

// cursorの位置より「後ろ」(より古い、または同じ公開日時でidが大きい)。
function afterCondition(position: SearchCursorPosition): string {
  return `or(published_at.lt."${position.publishedAt}",and(published_at.eq."${position.publishedAt}",id.gt.${position.id}))`;
}

export async function handleSearchBosses(req: Request, db: SupabaseRestClient): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }
  const url = new URL(req.url);
  const query = (url.searchParams.get("q") ?? "").trim();
  if (query.length === 0) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'q' is required" }, 400);
  }
  if (query.length > MAX_QUERY_LENGTH) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: `'q' is longer than ${MAX_QUERY_LENGTH} characters` }, 400);
  }
  const requestedLimit = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
  const limit = Number.isFinite(requestedLimit) && requestedLimit > 0 ? Math.min(Math.floor(requestedLimit), MAX_LIMIT) : DEFAULT_LIMIT;
  const mode = requestedMode(url);

  const cursorParam = url.searchParams.get("cursor") ?? "";
  let after: SearchCursorPosition | null = null;
  if (cursorParam !== "") {
    after = decodeSearchCursor(cursorParam);
    if (after === null) {
      return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'cursor' is not a valid search cursor" }, 400);
    }
  }

  const conditions = [searchCondition(query)];
  if (mode !== null) conditions.push(modeCondition(mode));
  if (after !== null) conditions.push(afterCondition(after));
  // 続きがあるかを知るため、1件多く読む。
  const found = await db.select<BossSummaryDbRow>("bosses", publicBossQuery(conditions, `order=published_at.desc,id.asc&limit=${limit + 1}`));
  if (!found.ok) return dbError(found);

  const page = found.rows.slice(0, limit);
  const statsLookup = await loadChallengeStats(db, page.map((row) => String(row.id)));
  if (!statsLookup.ok) return dbError(statsLookup);
  const body: PublicBossListResponseBody = {
    ok: true,
    bosses: page.map((row) => toPublicRow(row, statsLookup.stats.get(String(row.id))!)),
    has_more: found.rows.length > limit,
  };
  if (body.has_more) {
    const last = page[page.length - 1];
    body.next_cursor = encodeSearchCursor({ publishedAt: String(last.published_at), id: String(last.id) });
  }
  return jsonResponse(body, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    return await handleSearchBosses(req, db);
  });
}
