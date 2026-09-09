// Phase 4C — Makerのオンライン公開を受け取るEdge Function。
//
// 処理順序(§4C-3): request validation → Steam ticket verification
// (steam-authと同じSteamTicketVerifierを再利用) → SteamID extraction
// → payload保存(DB)。
//
// §重要「SteamIDをクライアントから信用しない」: ownerとしてDBへ書き込む
// SteamIDは、常にSteamTicketVerifierの検証結果(result.steamId)のみ。
// リクエストにsteam_idが含まれていても一切参照しない。
//
// §重要「service_role/secret keyをGodotへ置かない」: このファイルが読む
// STEAM_PUBLISHER_WEB_API_KEY / SUPABASE_SERVICE_ROLE_KEYはこのDeno実行
// 環境の環境変数としてのみ存在し、Godotクライアント側のコードには一切
// 登場しない。
//
// Phase 4A-2待ちの間: STEAM_PUBLISHER_WEB_API_KEY未設定の間、
// SteamTicketVerifierは常にnot_configuredを返す(steam_ticket_verifier.ts
// 参照)。このEdge Function自身はfakeへ差し替え可能な設計にしてあり、
// 正式キー設定後は接続するだけで本番動作する。

import { SteamTicketVerifier } from "../steam-auth/steam_ticket_verifier.ts";
import { RealSteamWebApiClient } from "../steam-auth/steam_web_api_client.ts";
import { WEB_API_IDENTITY } from "../steam-auth/index.ts";
import { RealSupabaseRestClient, SupabaseRestClient } from "../_shared/supabase_rest_client.ts";

const BATTLE_HASH_PATTERN = /^[0-9a-f]{64}$/;
const MAX_PAYLOAD_BYTES = 262144; // 256KiB -- generous for a single boss definition, rejects abuse.

export interface PublishRequestBody {
  ticket?: unknown;
  boss_id?: unknown;
  payload?: unknown;
}

export interface PublishResponseBody {
  ok: boolean;
  boss_id?: string;
  revision?: number;
  error_kind?: string;
  message?: string;
}

function isValidHexTicket(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && /^[0-9a-fA-F]+$/.test(value) &&
    value.length % 2 === 0;
}

interface ParsedPayload {
  schema_version: number;
  boss_name: string;
  author_name: string;
  draft_fields: Record<string, unknown>;
  clear_check_success_snapshot: Record<string, unknown>;
  battle_hash: string;
}

function validatePayloadShape(value: unknown): ParsedPayload | null {
  if (typeof value !== "object" || value === null) return null;
  const p = value as Record<string, unknown>;
  if (typeof p.schema_version !== "number" || p.schema_version < 1) return null;
  if (typeof p.boss_name !== "string" || p.boss_name.length === 0) return null;
  if (typeof p.author_name !== "string") return null;
  if (typeof p.draft_fields !== "object" || p.draft_fields === null) return null;
  if (typeof p.clear_check_success_snapshot !== "object" || p.clear_check_success_snapshot === null) {
    return null;
  }
  if (typeof p.battle_hash !== "string" || !BATTLE_HASH_PATTERN.test(p.battle_hash)) return null;
  return {
    schema_version: p.schema_version,
    boss_name: p.boss_name,
    author_name: p.author_name,
    draft_fields: p.draft_fields as Record<string, unknown>,
    clear_check_success_snapshot: p.clear_check_success_snapshot as Record<string, unknown>,
    battle_hash: p.battle_hash,
  };
}

async function sha256Hex(text: string): Promise<string> {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(body: PublishResponseBody, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface BossRow {
  id: string;
  owner_steam_id: string;
  revision: number;
  payload?: Record<string, unknown>;
}

// Key-order-independent deep equality. Used to detect a resent request whose
// payload is byte-for-byte the same *content* as what is already stored --
// e.g. the client never received the success response (dropped connection)
// and retried the identical publish. jsonb round-tripping through Postgres
// (and the in-memory fake DB) is not guaranteed to preserve object key order,
// so a plain JSON.stringify comparison is not safe here.
function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== typeof b) return false;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((v, i) => deepEqual(v, b[i]));
  }
  if (typeof a === "object" && typeof b === "object") {
    const ao = a as Record<string, unknown>;
    const bo = b as Record<string, unknown>;
    const ak = Object.keys(ao);
    const bk = Object.keys(bo);
    if (ak.length !== bk.length) return false;
    return ak.every((k) => Object.prototype.hasOwnProperty.call(bo, k) && deepEqual(ao[k], bo[k]));
  }
  return false;
}

export async function handlePublish(
  req: Request,
  verifier: SteamTicketVerifier,
  db: SupabaseRestClient,
  expectedAppId: number,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error_kind: "invalid_method", message: "POST only" }, 405);
  }

  const rawBody = await req.text();
  if (rawBody.length > MAX_PAYLOAD_BYTES) {
    return jsonResponse({ ok: false, error_kind: "payload_too_large", message: "Payload exceeds size limit" }, 413);
  }

  let body: PublishRequestBody;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ ok: false, error_kind: "malformed_request", message: "Request body was not valid JSON" }, 400);
  }

  if (!isValidHexTicket(body.ticket)) {
    return jsonResponse({ ok: false, error_kind: "invalid_request", message: "'ticket' must be a non-empty hex string" }, 400);
  }
  const payload = validatePayloadShape(body.payload);
  if (payload === null) {
    return jsonResponse({ ok: false, error_kind: "invalid_payload", message: "'payload' is missing required fields" }, 400);
  }
  const bossId = typeof body.boss_id === "string" && body.boss_id.length > 0 ? body.boss_id : null;

  // --- Steam ticket verification (SteamID extraction happens only here) ---
  const verification = await verifier.verifyTicket(body.ticket, expectedAppId, WEB_API_IDENTITY);
  if (!verification.ok) {
    const status = verification.errorKind === "not_configured" ? 503 : 401;
    return jsonResponse({ ok: false, error_kind: verification.errorKind, message: verification.message }, status);
  }
  const ownerSteamId = verification.steamId as string;

  // --- ownership + revision resolution ---
  let revision = 1;
  if (bossId !== null) {
    const existing = await db.select<BossRow>("bosses", `id=eq.${bossId}&select=id,owner_steam_id,revision,payload`);
    if (!existing.ok) {
      return jsonResponse({ ok: false, error_kind: "db_error", message: existing.errorMessage ?? "" }, 502);
    }
    if (existing.rows.length === 0) {
      return jsonResponse({ ok: false, error_kind: "not_found", message: "boss_id does not exist" }, 404);
    }
    const existingRow = existing.rows[0];
    if (existingRow.owner_steam_id !== ownerSteamId) {
      return jsonResponse({ ok: false, error_kind: "forbidden", message: "You do not own this boss" }, 403);
    }
    // Resent request whose content exactly matches what is already stored
    // (e.g. the client never saw the previous success response and retried
    // the identical publish). This must return the already-committed
    // revision unchanged rather than computing existingRow.revision + 1
    // again, which would bump the revision a second time for one logical
    // publish -- the idempotency_key below cannot catch this by itself
    // because it is derived from `revision`, which has already advanced in
    // the DB by the time the retry arrives.
    if (deepEqual(existingRow.payload ?? null, payload)) {
      return jsonResponse({ ok: true, boss_id: existingRow.id, revision: existingRow.revision }, 200);
    }
    revision = existingRow.revision + 1;
  }

  const idempotencyKey = await sha256Hex(`${ownerSteamId}:${payload.battle_hash}:${revision}`);

  // Idempotent replay: an identical (owner, battle_hash, revision) request
  // that was already committed returns the same success result instead of
  // writing a duplicate row (prevents double-publish from a double-tap or a
  // retried network request, per Phase 4E-4).
  const alreadyCommitted = await db.select<BossRow>(
    "bosses",
    `idempotency_key=eq.${idempotencyKey}&select=id,owner_steam_id,revision`,
  );
  if (alreadyCommitted.ok && alreadyCommitted.rows.length > 0) {
    const row = alreadyCommitted.rows[0];
    return jsonResponse({ ok: true, boss_id: row.id, revision: row.revision }, 200);
  }

  const now = new Date().toISOString();
  if (bossId === null) {
    const inserted = await db.insert<BossRow>("bosses", {
      owner_steam_id: ownerSteamId,
      author_name: payload.author_name,
      boss_name: payload.boss_name,
      schema_version: payload.schema_version,
      revision,
      payload: payload,
      battle_hash: payload.battle_hash,
      is_published: true,
      published_at: now,
      idempotency_key: idempotencyKey,
    });
    if (!inserted.ok || inserted.rows.length === 0) {
      return jsonResponse({ ok: false, error_kind: "db_error", message: inserted.errorMessage ?? "" }, 502);
    }
    return jsonResponse({ ok: true, boss_id: inserted.rows[0].id, revision }, 201);
  }

  const updated = await db.update<BossRow>("bosses", `id=eq.${bossId}`, {
    author_name: payload.author_name,
    boss_name: payload.boss_name,
    schema_version: payload.schema_version,
    revision,
    payload: payload,
    battle_hash: payload.battle_hash,
    is_published: true,
    published_at: now,
    idempotency_key: idempotencyKey,
  });
  if (!updated.ok || updated.rows.length === 0) {
    return jsonResponse({ ok: false, error_kind: "db_error", message: updated.errorMessage ?? "" }, 502);
  }
  return jsonResponse({ ok: true, boss_id: bossId, revision }, 200);
}

if (import.meta.main) {
  Deno.serve(async (req: Request) => {
    const verifier = new SteamTicketVerifier({
      client: new RealSteamWebApiClient(),
      publisherWebApiKey: Deno.env.get("STEAM_PUBLISHER_WEB_API_KEY"),
    });
    const db = new RealSupabaseRestClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    const expectedAppId = Number(Deno.env.get("STEAM_APP_ID") ?? "0");
    return await handlePublish(req, verifier, db, expectedAppId);
  });
}
