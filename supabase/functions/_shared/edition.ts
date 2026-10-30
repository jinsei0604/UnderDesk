// 2026-10-28 製品版／体験版。オンラインのDBは共通のまま、体験版の利用者にだけ制限をかける。
//
// 本人の版は「Steamのチケットがどちらのアプリのものとして確かめられたか」(SteamTicketVerifierの result.edition)で決める。
// ゲームが送る edition=demo(一覧の ?edition=demo、本文の "edition")は表示の範囲を絞るためだけに使い、権限には使わない。
// 製品版の利用者(製品版のチケット)には何も制限をかけない(今までどおり)。
//
// 体験版の範囲(ゲームの RBMEdition と同じ値): ボスは竜・スライム・幽霊・朽ちた機械武者、作成は SIMPLE だけ、
// オンライン公開は1人2体まで(公開中を非公開にすれば入れ替えられる)。

export const DEMO_EDITION = "demo";
export const DEMO_APPEARANCES = ["appearance_dragon", "appearance_slime", "appearance_ghost", "appearance_musha"];
export const DEMO_MAX_PUBLISHED = 2;

// 一覧などの ?edition=demo(表示の範囲だけ。権限ではない)。
export function requestedDemo(url: URL): boolean {
  return url.searchParams.get("edition") === DEMO_EDITION;
}

// 本文の "edition"(表示の範囲だけ)。
export function bodyRequestsDemo(body: unknown): boolean {
  return typeof body === "object" && body !== null && (body as Record<string, unknown>)["edition"] === DEMO_EDITION;
}

// 体験版で挑戦・公開できるボスか(creator_mode が advanced でなく、外見が体験版の4体)。
export function isDemoBoss(creatorMode: unknown, appearanceId: unknown): boolean {
  return creatorMode !== "advanced" && typeof appearanceId === "string" && DEMO_APPEARANCES.includes(appearanceId);
}

// 公開データ(payload)の draft_fields から判断する。
export function isDemoPayload(payload: unknown): boolean {
  if (typeof payload !== "object" || payload === null) return false;
  const fields = (payload as Record<string, unknown>)["draft_fields"];
  if (typeof fields !== "object" || fields === null) return false;
  const f = fields as Record<string, unknown>;
  return isDemoBoss(f["creator_mode"], f["appearance_id"]);
}

// PostgREST の and=(...) に入れる条件(公開中の一覧を体験版の範囲に絞る)。
export function demoCondition(): string {
  const mode = "payload->draft_fields->>creator_mode";
  const appearance = "payload->draft_fields->>appearance_id";
  return `or(${mode}.is.null,${mode}.neq.advanced),${appearance}.in.(${DEMO_APPEARANCES.join(",")})`;
}

// 体験版のチケット(verification.edition === "demo")で、体験版の範囲外のボスへの挑戦の記録・戦闘チケットを頼まれた時は断る
// (ゲームを改変して範囲外のボスに挑んでも、記録・ランキング・討伐には数えない)。製品版のチケットは何もしない。
// 戻り値: 断る時は error_kind、問題なければ null(ボスが無い・非公開の判断は各関数の今までの処理に任せる)。
export async function demoBossRejection(
  db: { select<T>(table: string, query: string): Promise<{ ok: boolean; rows: T[]; errorMessage?: string | null }> },
  bossId: string,
  edition: string | undefined,
): Promise<string | null> {
  if (edition !== DEMO_EDITION) return null;
  const found = await db.select<{ id: string; creator_mode: unknown; appearance_id: unknown }>(
    "bosses",
    `id=eq.${bossId}&select=id,creator_mode:payload->draft_fields->>creator_mode,appearance_id:payload->draft_fields->>appearance_id`,
  );
  if (!found.ok) return "db_error";
  if (found.rows.length === 0) return null;
  const row = found.rows[0];
  return isDemoBoss(row.creator_mode ?? undefined, row.appearance_id) ? null : "demo_unavailable";
}

// 2026-10-29 体験版のオンライン挑戦は、異なるボス累計15体まで（DB の claim_demo_challenge_slot()・
// migration 20261029000000_demo_challenge_slots.sql）。製品版のチケットには何もしない。
export const DEMO_MAX_CHALLENGED_BOSSES = 15;
export const DEMO_CHALLENGE_LIMIT_ERROR = "demo_challenge_limit";

export type DemoSlotStatus = "already" | "claimed" | "limit" | "not_found";

export type DemoSlotResult =
  | { ok: true; status: DemoSlotStatus; used: number; limit: number }
  | { ok: false; errorMessage: string };

interface DemoSlotRow {
  status: string;
  used: number;
  slot_limit: number;
}

type RpcClient = {
  rpc<T>(functionName: string, params: Record<string, unknown>): Promise<{ ok: boolean; rows: T[]; errorMessage?: string | null }>;
};

// 体験版の利用者が戦闘を始める時に、このボスの枠を確かめて（無ければ1つ使って）返す。体験版でなければ呼ばない。
export async function claimDemoChallengeSlot(db: RpcClient, bossId: string, steamId: string): Promise<DemoSlotResult> {
  const claimed = await db.rpc<DemoSlotRow>("claim_demo_challenge_slot", { p_boss_id: bossId, p_steam_id: steamId });
  if (!claimed.ok || claimed.rows.length === 0) return { ok: false, errorMessage: claimed.errorMessage ?? "" };
  const row = claimed.rows[0];
  const status = String(row.status) as DemoSlotStatus;
  if (!["already", "claimed", "limit", "not_found"].includes(status)) {
    return { ok: false, errorMessage: `unexpected demo slot status '${row.status}'` };
  }
  return { ok: true, status, used: Number(row.used ?? 0), limit: Number(row.slot_limit ?? DEMO_MAX_CHALLENGED_BOSSES) };
}

export type DemoStatusResult =
  | { ok: true; used: number; limit: number; bossIds: string[] }
  | { ok: false; errorMessage: string };

// 今の使用状況（読むだけ）。
export async function demoChallengeStatus(db: RpcClient, steamId: string): Promise<DemoStatusResult> {
  const read = await db.rpc<{ used: number; slot_limit: number; boss_ids: string[] | null }>("demo_challenge_status", { p_steam_id: steamId });
  if (!read.ok || read.rows.length === 0) return { ok: false, errorMessage: read.errorMessage ?? "" };
  const row = read.rows[0];
  return {
    ok: true,
    used: Number(row.used ?? 0),
    limit: Number(row.slot_limit ?? DEMO_MAX_CHALLENGED_BOSSES),
    bossIds: Array.isArray(row.boss_ids) ? row.boss_ids.map(String) : [],
  };
}
