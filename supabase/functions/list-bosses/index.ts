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
//
// 全件対象とページ送り(2026-10): 以前は新しい50件だけを取ってからmodeで絞って
// いたため、新しい50件に無いSIMPLE/HARDCOREのボスを取りこぼした。今は公開中の
// 全ボスを_shared/select_all_pages.tsで読み、modeで絞り、
//   公開日時の新しい順(published_at DESC)、同じ公開日時ならid順(id ASC)
// に並べてから、limit件(既定20、最大50)を返す。
//   - cursorを付けない要求(新着・オンラインの1ページ目、既存の呼び出し)は従来どおり
//     最新の先頭ページを返す。
//   - 続きがあればhas_more=trueと、そのページの最後の行の位置(published_at, id)を
//     表すnext_cursorを返す。次の要求でcursorにそれを渡すと、その位置より「後ろ」
//     (より古い、または同じ公開日時でidが大きい)の行から返す。位置で続きを決める
//     ので、閲覧中に新しいボスが公開されても(先頭側に入るだけで)続きのページに
//     重複や飛ばしが起きない。
//   - cursorが壊れている場合は400(invalid_request)。黙って先頭ページを返すと、
//     ゲーム側で同じボスを重ねて追加してしまうため。
//
// 挑戦画面のボスカード用の項目(2026-10): 各行にappearance_id(外見ID、サムネイル用)と、
// unique_challengers/unique_clearers(挑戦者数・一度でもクリアした人数、クリア率の分母と分子)を
// 載せる。挑戦記録は返すページのボスの分だけ読む(_shared/boss_card_fields.ts)。

import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";
import { selectAllPages } from "../_shared/select_all_pages.ts";
import { extractAppearanceId, loadChallengeStats } from "../_shared/boss_card_fields.ts";

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

interface BossRowWithPayload {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  payload?: Record<string, unknown>;
}

// 並び順の上での位置(公開日時のミリ秒と、同じ公開日時の中での並びを決めるid)。
export interface ListCursorPosition {
  publishedAtMs: number;
  id: string;
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

function publishedAtMs(publishedAt: unknown): number {
  const ms = Date.parse(String(publishedAt ?? ""));
  return Number.isFinite(ms) ? ms : 0;
}

// 公開日時の新しい順、同じ公開日時ならid順。aがbより前なら負。
function compareNewestFirst(a: ListCursorPosition, b: ListCursorPosition): number {
  if (a.publishedAtMs !== b.publishedAtMs) return b.publishedAtMs - a.publishedAtMs;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

// cursorは「並び順の上での位置」を base64url(JSON) にした不透明な文字列。
export function encodeListCursor(position: ListCursorPosition): string {
  const bytes = new TextEncoder().encode(JSON.stringify({ p: position.publishedAtMs, i: position.id }));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

// 壊れたcursorならnull。
export function decodeListCursor(cursor: string): ListCursorPosition | null {
  if (!/^[A-Za-z0-9_-]+$/.test(cursor)) return null;
  try {
    const base64 = cursor.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - cursor.length % 4) % 4);
    const binary = atob(base64);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (typeof parsed !== "object" || parsed === null) return null;
    const { p, i } = parsed as Record<string, unknown>;
    if (typeof p !== "number" || !Number.isFinite(p) || typeof i !== "string" || i.length === 0) return null;
    return { publishedAtMs: p, id: i };
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

  const requestedMode = url.searchParams.get("mode");
  const modeFilter = requestedMode !== null && VALID_MODES.has(requestedMode) ? requestedMode : null;

  // 空のcursorは「指定なし」(先頭ページ)と同じに扱う。
  const cursorParam = url.searchParams.get("cursor") ?? "";
  let after: ListCursorPosition | null = null;
  if (cursorParam !== "") {
    after = decodeListCursor(cursorParam);
    if (after === null) {
      return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'cursor' is not a valid list cursor" }, 400);
    }
  }

  // creator_modeはjsonb内にしかないため、DB側で件数を打ち切ってからmodeで絞ると
  // 取りこぼす。公開中の全ボスを読んでから、この関数の中で絞り・並べ・切り出す。
  const result = await selectAllPages<BossRowWithPayload>(
    db,
    "bosses",
    "is_published=eq.true&select=id,boss_name,author_name,published_at,revision,payload",
  );
  if (!result.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: result.errorMessage ?? "" }, 502);
  }

  let entries = result.rows.map((row) => ({
    summary: {
      id: row.id,
      boss_name: row.boss_name,
      author_name: row.author_name,
      published_at: row.published_at,
      revision: row.revision,
      creator_mode: extractCreatorMode(row.payload),
      appearance_id: extractAppearanceId(row.payload),
    } as BossSummaryRow,
    position: { publishedAtMs: publishedAtMs(row.published_at), id: String(row.id) } as ListCursorPosition,
  }));

  if (modeFilter !== null) {
    entries = entries.filter((entry) => entry.summary.creator_mode === modeFilter);
  }
  entries.sort((a, b) => compareNewestFirst(a.position, b.position));
  if (after !== null) {
    const cursorPosition = after;
    entries = entries.filter((entry) => compareNewestFirst(entry.position, cursorPosition) > 0);
  }

  const page = entries.slice(0, limit);
  const statsLookup = await loadChallengeStats(db, page.map((entry) => entry.summary.id));
  if (!statsLookup.ok) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: statsLookup.errorMessage }, 502);
  }
  const rows: BossListRow[] = page.map((entry) => {
    const stats = statsLookup.stats.get(entry.summary.id)!;
    return { ...entry.summary, unique_challengers: stats.uniqueChallengers, unique_clearers: stats.uniqueClearers };
  });
  const body: ListBossesResponseBody = { ok: true, bosses: rows, has_more: entries.length > limit };
  if (body.has_more) {
    body.next_cursor = encodeListCursor(page[page.length - 1].position);
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
