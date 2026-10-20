// 2026-10-17 プレイ体験監査 PX-03 — 公開ボスの検索(search-bosses)とランダム挑戦(random-boss)が共有する、
// PostgRESTへの問い合わせの組み立て。
//
// 既存の一覧(list-bosses など)は公開中の全ボスを payload ごと読んでから関数の中で絞るが、この2つは
// Supabaseの無料枠への負荷を抑えるため、絞り込み・並べ替え・件数の打ち切りをPostgREST(DB)に任せ、
// 一覧のカードに要る列だけを読む(payload全体は読まない。creator_mode・appearance_idはJSONの中の値だけを取り出す)。
//
// 公開ID: 公開ボスのid(UUID、サーバーが付ける)の先頭8文字(小文字の16進)。ゲームは詳細と作者の保存一覧に
// 「公開ID」として出し、検索欄に入れると、そのidで始まるボスを探す(UUIDの範囲で探すので主キーの索引が効く)。

import { ChallengeStats } from "./boss_card_fields.ts";

export const DEFAULT_CREATOR_MODE = "simple";
export const VALID_MODES = new Set(["simple", "advanced"]);
export const PUBLIC_ID_LENGTH = 8;

// 一覧のカードに要る列だけ(list-bossesの行と同じ項目。payloadそのものは読まない)。
export const BOSS_SUMMARY_SELECT = [
  "id",
  "boss_name",
  "author_name",
  "published_at",
  "revision",
  "creator_mode:payload->draft_fields->>creator_mode",
  // 外見IDはJSONの値のまま読む(->> だと数などが文字に変わるため。文字でなければ空にする、一覧のこれまでの規約。2026-10-18)
  "appearance_id:payload->draft_fields->appearance_id",
].join(",");

// DBから読んだ1行(creator_mode・appearance_idはJSONの中に無ければnull。appearance_idはJSONの値のまま)。
export interface BossSummaryDbRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string | null;
  appearance_id: unknown;
}

// 応答の1行(list-bossesの行と同じ形)。
export interface PublicBossRow {
  id: string;
  boss_name: string;
  author_name: string;
  published_at: string;
  revision: number;
  creator_mode: string;
  appearance_id: string;
  unique_challengers: number;
  unique_clearers: number;
}

export interface PublicBossListResponseBody {
  ok: boolean;
  bosses?: PublicBossRow[];
  has_more?: boolean;
  next_cursor?: string;
  error_kind?: string;
  message?: string;
}

export function jsonResponse(body: PublicBossListResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// 要求のmode(simple/advanced)。それ以外・無しは絞り込みなし(list-bossesと同じ扱い)。
export function requestedMode(url: URL): string | null {
  const mode = url.searchParams.get("mode");
  return mode !== null && VALID_MODES.has(mode) ? mode : null;
}

// modeの条件(and=(...)の中に入れる形)。creator_modeが無い・不正な既存データはSIMPLE扱い
// (list-bossesのextractCreatorMode()・ゲームの既定と同じ)。
export function modeCondition(mode: string): string {
  const path = "payload->draft_fields->>creator_mode";
  return mode === "advanced" ? `${path}.eq.advanced` : `or(${path}.is.null,${path}.neq.advanced)`;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PUBLIC_ID_PATTERN = /^[0-9a-f]{8}$/;

export function isUuid(text: string): boolean {
  return UUID_PATTERN.test(text);
}

// 検索語が公開ID(8文字)・UUIDなら、そのidの条件。違えばnull。
export function idCondition(query: string): string | null {
  const text = query.toLowerCase();
  if (isUuid(text)) return `id.eq.${text}`;
  if (PUBLIC_ID_PATTERN.test(text)) {
    return `and(id.gte.${text}-0000-0000-0000-000000000000,id.lte.${text}-ffff-ffff-ffff-ffffffffffff)`;
  }
  return null;
}

// 検索語を、PostgRESTの "..." で囲んだilikeの値へ入れる。引用符の中では \ がエスケープ(\\ → \、\" → ")で、
// その後のSQLのLIKEでも \ がエスケープになる。
//   % と _ → 文字そのもの(LIKEの \% \_)
//   \ → 文字そのもの(LIKEの \\)
//   " → 文字そのもの(引用符の中の \")
//   * → PostgRESTが % に変えるため文字そのものでは探せない。1文字の何でも(_)にする
export function ilikeValue(query: string): string {
  let out = "";
  for (const char of query) {
    if (char === "%" || char === "_") out += "\\\\" + char;
    else if (char === "\\") out += "\\\\\\\\";
    else if (char === '"') out += '\\"';
    else if (char === "*") out += "_";
    else out += char;
  }
  return out;
}

// ボス名・作者名の部分一致(大文字小文字を区別しない)と、公開IDの条件のどれか。
export function searchCondition(query: string): string {
  const pattern = `"*${ilikeValue(query)}*"`;
  const parts = [`boss_name.ilike.${pattern}`, `author_name.ilike.${pattern}`];
  const id = idCondition(query);
  if (id !== null) parts.push(id);
  return `or(${parts.join(",")})`;
}

// 一覧の並び(公開日時の新しい順、同じ公開日時ならid順)の上で、その位置より「後ろ」(より古い、または同じ
// 公開日時でidが大きい)の条件。publishedAt・idは確かめた値だけを渡す(list-bossesのcursor・DBが返した行)。
export function afterPositionCondition(publishedAt: string, id: string): string {
  return `or(published_at.lt."${publishedAt}",and(published_at.eq."${publishedAt}",id.gt.${id}))`;
}

// 公開ボスを読む問い合わせ。conditionsは and=(...) の中に並べる条件。
export function publicBossQuery(conditions: string[], tail: string): string {
  const params = [`select=${encodeURIComponent(BOSS_SUMMARY_SELECT)}`, "is_published=eq.true", "published_at=not.is.null"];
  if (conditions.length > 0) params.push(`and=${encodeURIComponent(`(${conditions.join(",")})`)}`);
  if (tail.length > 0) params.push(tail);
  return params.join("&");
}

// 件数だけを数える時の絞り込み(selectを付けない)。
export function publicBossFilter(conditions: string[]): string {
  const params = ["is_published=eq.true", "published_at=not.is.null"];
  if (conditions.length > 0) params.push(`and=${encodeURIComponent(`(${conditions.join(",")})`)}`);
  return params.join("&");
}

export function toPublicRow(row: BossSummaryDbRow, stats: ChallengeStats): PublicBossRow {
  return {
    id: String(row.id),
    boss_name: String(row.boss_name ?? ""),
    author_name: String(row.author_name ?? ""),
    published_at: String(row.published_at ?? ""),
    revision: Number(row.revision ?? 1),
    creator_mode: row.creator_mode !== null && VALID_MODES.has(String(row.creator_mode)) ? String(row.creator_mode) : DEFAULT_CREATOR_MODE,
    appearance_id: typeof row.appearance_id === "string" ? row.appearance_id : "",
    unique_challengers: stats.uniqueChallengers,
    unique_clearers: stats.uniqueClearers,
  };
}

// DBの失敗。PostgRESTのエラー文(列名・SQLの断片などを含みうる)は利用者へ返さず、関数のログにだけ残す
// (2026-10-17 ユーザー指示)。ゲームは error_kind だけを見て、人が読める文を出す(RBMOnlineErrorText)。
export const DB_ERROR_PUBLIC_MESSAGE = "The server could not read the boss data.";

export function dbError(result: { errorMessage?: string }): Response {
  console.error(`db_error: ${result.errorMessage ?? ""}`);
  return jsonResponse({ ok: false, error_kind: "db_error", message: DB_ERROR_PUBLIC_MESSAGE }, 502);
}
