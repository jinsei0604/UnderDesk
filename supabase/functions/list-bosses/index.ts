// Phase 4D — 公開済みボス一覧の取得。
//
// 一覧では概要のみを返す(§4D-2「巨大なpayloadを一覧取得時に毎回全部
// 落とす必要がないなら、一覧用queryと詳細取得を分ける」)——full payload
// はget-bossでのみ返す。認証は不要(公開済みデータの閲覧のみ、RLSの
// bosses_select_published_onlyポリシーと同じ「公開済みのみ」条件を
// アプリ層でも明示する)。
//
// 挑戦ハブ SIMPLE/HARDCORE連携（2026-09）— creator_mode(SIMPLE/HARDCORE)はbossesテーブルの
// 独立カラムではなく payload.draft_fields.creator_mode(jsonb)にのみ存在する。DBスキーマは変更せず、
// 一覧の行には creator_mode を足して返す(full payload自体は一覧の応答へ含めない、
// 「summary rows never include the full payload field」契約)。任意のmode(simple/advanced)で絞れる。
//
// 並びとページ送り(2026-10): 公開日時の新しい順(published_at DESC)、同じ公開日時ならid順(id ASC)。
// limit件(既定20、最大50)を返し、続きがあればhas_more=trueと、そのページの最後の行の位置
// (published_at, id)を表すnext_cursorを返す。次の要求でcursorにそれを渡すと、その位置より「後ろ」
// (より古い、または同じ公開日時でidが大きい)の行から返す。位置で続きを決めるので、閲覧中に新しい
// ボスが公開されても(先頭側に入るだけで)続きのページに重複や飛ばしが起きない。cursorが壊れている
// 場合は400(invalid_request)。黙って先頭ページを返すと、ゲーム側で同じボスを重ねて追加してしまうため。
//
// Supabaseの無料枠への負荷(2026-10-18): 以前は公開中の全ボスを payload ごと読み(1,000件で約2.6MB)、
// この関数の中で絞り・並べ・切り出していた。今は search-bosses と同じく、絞り込み(公開中・mode・
// cursorの位置)・並べ替え・件数の打ち切りをPostgREST(DB)に任せ(1回の問い合わせで limit+1 件まで)、
// カードに要る列だけを読む(creator_mode・appearance_id はJSONの中の値だけ。_shared/public_boss_query.ts)。
// 挑戦者数・クリアした人数は、返すページのボスの分だけ数える(_shared/boss_card_fields.ts)。
//
// 挑戦画面のボスカード用の項目(2026-10): 各行にappearance_id(外見ID、サムネイル用)と、
// unique_challengers/unique_clearers(挑戦者数・一度でもクリアした人数、クリア率の分母と分子)を載せる。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { loadChallengeStats } from "../_shared/boss_card_fields.ts";
import {
  afterPositionCondition,
  BossSummaryDbRow,
  dbError,
  modeCondition,
  publicBossQuery,
  requestedMode,
  toPublicRow,
} from "../_shared/public_boss_query.ts";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

export interface BossSummaryRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
  // 2026-10 挑戦画面のボスカード用(_shared/boss_card_fields.ts)。
  appearance_id: string;
}

// 一覧の1行: 概要+カードに出す挑戦者数・クリア者数(このページのボスの分だけ数える)。
export interface BossListRow extends BossSummaryRow {
  unique_challengers: number;
  unique_clearers: number;
}

export interface ListBossesResponseBody {
  ok: boolean;
  bosses?: BossListRow[];
  // 続きのページがあるか(2026-10追加。古いクライアントは無視してよい)。
  has_more?: boolean;
  // has_more=trueの時だけ付く、次のページの要求に渡す位置。
  next_cursor?: string;
  error_kind?: string;
  message?: string;
}

// 並び順の上での位置(公開日時はDBが返した文字列のまま。ミリ秒へ丸めると、同じミリ秒の中の行を飛ばすため)。
export interface ListCursorPosition {
  publishedAt: string;
  id: string;
}

function jsonResponse(body: ListBossesResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// cursorは「並び順の上での位置」を base64url(JSON) にした不透明な文字列。
export function encodeListCursor(position: ListCursorPosition): string {
  const bytes = new TextEncoder().encode(JSON.stringify({ p: position.publishedAt, i: position.id }));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

// 壊れたcursorならnull。問い合わせの文字列へ入れるので、公開日時・idの形も確かめる。
// 2026-10-18 より前のcursor(公開日時をミリ秒の数で持つ形)も、読み込み中の一覧の続きのために受け付ける。
export function decodeListCursor(cursor: string): ListCursorPosition | null {
  if (!/^[A-Za-z0-9_-]+$/.test(cursor)) return null;
  try {
    const base64 = cursor.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - cursor.length % 4) % 4);
    const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
    const { p, i } = parsed as Record<string, unknown>;
    if (typeof i !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(i)) return null;
    if (typeof p === "number") {
      return Number.isFinite(p) ? { publishedAt: new Date(p).toISOString(), id: i } : null;
    }
    if (typeof p !== "string" || !/^[0-9T:.+\- Z]+$/.test(p) || !Number.isFinite(Date.parse(p))) return null;
    return { publishedAt: p, id: i };
  } catch {
    return null;
  }
}

export async function handleListBosses(req: Request, db: SupabaseRestClient): Promise<Response> {
  if (req.method !== "GET") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "GET only" }, 405);
  }

  const url = new URL(req.url);
  const requestedLimit = Number(url.searchParams.get("limit") ?? DEFAULT_LIMIT);
  const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
    ? Math.min(Math.floor(requestedLimit), MAX_LIMIT)
    : DEFAULT_LIMIT;
  const mode = requestedMode(url);

  // 空のcursorは「指定なし」(先頭ページ)と同じに扱う。
  const cursorParam = url.searchParams.get("cursor") ?? "";
  let after: ListCursorPosition | null = null;
  if (cursorParam !== "") {
    after = decodeListCursor(cursorParam);
    if (after === null) {
      return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'cursor' is not a valid list cursor" }, 400);
    }
  }

  const conditions: string[] = [];
  if (mode !== null) conditions.push(modeCondition(mode));
  if (after !== null) conditions.push(afterPositionCondition(after.publishedAt, after.id));
  // 続きがあるかを知るため、1件多く読む。
  const found = await db.select<BossSummaryDbRow>("bosses", publicBossQuery(conditions, `order=published_at.desc,id.asc&limit=${limit + 1}`));
  if (!found.ok) return dbError(found);

  const page = found.rows.slice(0, limit);
  const statsLookup = await loadChallengeStats(db, page.map((row) => String(row.id)));
  if (!statsLookup.ok) return dbError(statsLookup);
  const body: ListBossesResponseBody = {
    ok: true,
    bosses: page.map((row) => toPublicRow(row, statsLookup.stats.get(String(row.id))!)),
    has_more: found.rows.length > limit,
  };
  if (body.has_more) {
    const last = page[page.length - 1];
    body.next_cursor = encodeListCursor({ publishedAt: String(last.published_at), id: String(last.id) });
  }
  return jsonResponse(body, 200);
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
