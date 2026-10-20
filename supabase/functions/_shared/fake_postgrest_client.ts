// 2026-10-17 — search-bosses・random-boss のテスト専用のインメモリ実装。実Supabaseへは一切出ない。
//
// 既存の FakeSupabaseRestClient(eq/gt/in/order/limit/selectだけ)は変えずに、この2つが発行する
// PostgRESTの問い合わせを、PostgRESTと同じ意味で解釈する:
//   - select: 列、別名(alias:列)、JSONの値(payload->draft_fields->>creator_mode。->>は文字列、無ければnull)
//   - 絞り込み: 列=eq/neq/gt/gte/lt/lte/ilike/is.値、not.is.null、in.(...)
//   - 論理: and=(...)・or=(...) と、その中の and(...)・or(...)。値は "..." で囲める(中の , . : ( ) はそのまま)
//   - ilike: * は %(何文字でも)、_ は1文字。大文字小文字を区別しない
//   - order(複数の列、asc/desc)、offset、limit
//   - count(): 条件に合う行の数(Prefer: count=exact と同じ)
// SQLと同じく、nullとの比較(is以外)は偽。公開日時(_at)は時刻として比べる。

import { CountResult, RestResult, SupabaseCountingRestClient } from "./supabase_rest_client.ts";

type Row = Record<string, unknown>;

// 失敗の時のDBの内部の文（PostgRESTの文に似せる。関数が利用者へ返さないことを確かめる）。
export const FAKE_INTERNAL_ERROR = '{"code":"42703","message":"column bosses.owner_steam_id does not exist"}';

export class FakePostgrestClient implements SupabaseCountingRestClient {
  private tables: Map<string, Row[]> = new Map();
  private failing: { kind: "select" | "count"; table: string; call: number }[] = [];
  private callCounts = new Map<string, number>();
  selectCalls: { table: string; query: string }[] = [];
  countCalls: { table: string; query: string }[] = [];
  // count()の直後に行を消す(数えた後に取り下げられた場合を試すため)。
  afterCount: (() => void) | null = null;
  // PostgRESTの応答行数の上限(Supabaseの「Max rows」。limitを大きくしても、これより多くは返さない)。
  private maxRowsPerResponse: number | undefined;

  seed(table: string, rows: Row[]): void {
    this.tables.set(table, [...(this.tables.get(table) ?? []), ...rows]);
  }

  remove(table: string, predicate: (row: Row) => boolean): void {
    this.tables.set(table, (this.tables.get(table) ?? []).filter((row) => !predicate(row)));
  }

  // tableへのcall回目(1始まり)のselect/countを失敗させる。
  fail(kind: "select" | "count", table: string, call: number): void {
    this.failing.push({ kind, table, call });
  }

  // FakeSupabaseRestClient と同じ名前の入口(一覧の関数のテストを、こちらの偽物でも同じ形で書けるように。2026-10-18)。
  failSelectCall(table: string, call: number): void {
    this.fail("select", table, call);
  }

  setMaxRowsPerResponse(maxRows: number): void {
    this.maxRowsPerResponse = maxRows;
  }

  rowsOf(table: string): Row[] {
    return this.tables.get(table) ?? [];
  }

  private shouldFail(kind: "select" | "count", table: string): boolean {
    const key = `${kind}:${table}`;
    const call = (this.callCounts.get(key) ?? 0) + 1;
    this.callCounts.set(key, call);
    return this.failing.some((f) => f.kind === kind && f.table === table && f.call === call);
  }

  select<T>(table: string, query: string): Promise<RestResult<T>> {
    this.selectCalls.push({ table, query });
    if (this.shouldFail("select", table)) return Promise.resolve({ ok: false, rows: [], status: 500, errorMessage: FAKE_INTERNAL_ERROR });
    const params = new URLSearchParams(query);
    let rows = (this.tables.get(table) ?? []).filter((row) => matchesAll(row, params));
    const order = params.get("order");
    if (order !== null) rows = sortRows(rows, order);
    const offset = Number(params.get("offset") ?? 0);
    const limit = params.has("limit") ? Number(params.get("limit")) : rows.length;
    rows = rows.slice(offset, offset + limit);
    if (this.maxRowsPerResponse !== undefined) rows = rows.slice(0, this.maxRowsPerResponse);
    const select = params.get("select");
    const out = select === null ? rows : rows.map((row) => project(row, select));
    return Promise.resolve({ ok: true, rows: out as T[], status: 200 });
  }

  count(table: string, query: string): Promise<CountResult> {
    this.countCalls.push({ table, query });
    if (this.shouldFail("count", table)) return Promise.resolve({ ok: false, count: 0, status: 500, errorMessage: FAKE_INTERNAL_ERROR });
    const params = new URLSearchParams(query);
    const total = (this.tables.get(table) ?? []).filter((row) => matchesAll(row, params)).length;
    const after = this.afterCount;
    this.afterCount = null;
    if (after !== null) after();
    return Promise.resolve({ ok: true, count: total, status: 200 });
  }

  insert<T>(): Promise<RestResult<T>> {
    throw new Error("FakePostgrestClient: insert is not supported");
  }

  update<T>(): Promise<RestResult<T>> {
    throw new Error("FakePostgrestClient: update is not supported");
  }

  rpc<T>(): Promise<RestResult<T>> {
    throw new Error("FakePostgrestClient: rpc is not supported");
  }
}

const RESERVED = new Set(["select", "order", "limit", "offset", "and", "or"]);

function matchesAll(row: Row, params: URLSearchParams): boolean {
  for (const [key, value] of params.entries()) {
    if (key === "and" || key === "or") {
      if (!evaluateGroup(row, key, value)) return false;
    } else if (!RESERVED.has(key)) {
      if (!evaluateFilter(row, key, value)) return false;
    }
  }
  return true;
}

// "(a,b,or(c,d))" の中身をトップレベルの , で分ける(引用符と括弧の中は分けない)。
function splitTopLevel(inner: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quoted = false;
  let current = "";
  for (let i = 0; i < inner.length; i++) {
    const char = inner[i];
    if (quoted) {
      current += char;
      if (char === "\\" && i + 1 < inner.length) {
        current += inner[++i];
      } else if (char === '"') {
        quoted = false;
      }
      continue;
    }
    if (char === '"') quoted = true;
    if (char === "(") depth++;
    if (char === ")") depth--;
    if (char === "," && depth === 0) {
      parts.push(current);
      current = "";
    } else {
      current += char;
    }
  }
  if (current.length > 0) parts.push(current);
  return parts;
}

function evaluateGroup(row: Row, operator: string, group: string): boolean {
  if (!group.startsWith("(") || !group.endsWith(")")) throw new Error(`bad logic group: ${group}`);
  const results = splitTopLevel(group.slice(1, -1)).map((item) => evaluateItem(row, item));
  return operator === "and" ? results.every(Boolean) : results.some(Boolean);
}

function evaluateItem(row: Row, item: string): boolean {
  if (item.startsWith("and(")) return evaluateGroup(row, "and", item.slice(3));
  if (item.startsWith("or(")) return evaluateGroup(row, "or", item.slice(2));
  const dot = item.indexOf(".");
  return evaluateFilter(row, item.slice(0, dot), item.slice(dot + 1));
}

function unquote(value: string): string {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.slice(1, -1).replace(/\\(.)/g, "$1");
  }
  return value;
}

function evaluateFilter(row: Row, field: string, expression: string): boolean {
  if (expression.startsWith("not.")) return !evaluateFilter(row, field, expression.slice(4));
  const dot = expression.indexOf(".");
  const op = expression.slice(0, dot);
  const raw = expression.slice(dot + 1);
  const actual = readPath(row, field);
  if (op === "is") {
    if (raw === "null") return actual === null;
    if (raw === "true") return actual === true;
    if (raw === "false") return actual === false;
    throw new Error(`bad is value: ${raw}`);
  }
  if (actual === null) return false;
  if (op === "in") {
    const values = raw.slice(1, -1).split(",").map(unquote);
    return values.some((value) => compare(field, actual, value) === 0);
  }
  const value = unquote(raw);
  switch (op) {
    case "eq":
      return compare(field, actual, value) === 0;
    case "neq":
      return compare(field, actual, value) !== 0;
    case "gt":
      return compare(field, actual, value) > 0;
    case "gte":
      return compare(field, actual, value) >= 0;
    case "lt":
      return compare(field, actual, value) < 0;
    case "lte":
      return compare(field, actual, value) <= 0;
    case "ilike":
      return likeToRegExp(value.replaceAll("*", "%")).test(String(actual));
    default:
      throw new Error(`unsupported operator: ${op}`);
  }
}

// SQLのLIKEの模様: % は何文字でも、_ は1文字、\ の次の文字はその文字そのもの。
function likeToRegExp(pattern: string): RegExp {
  let source = "";
  const chars = [...pattern];
  for (let i = 0; i < chars.length; i++) {
    let char = chars[i];
    if (char === "\\" && i + 1 < chars.length) {
      char = chars[++i];
      source += char.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    } else if (char === "%") source += "[\\s\\S]*";
    else if (char === "_") source += "[\\s\\S]";
    else source += char.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${source}$`, "iu");
}

function compare(field: string, actual: unknown, value: string): number {
  if (field.endsWith("_at")) {
    const a = Date.parse(String(actual));
    const b = Date.parse(value);
    return a === b ? 0 : a < b ? -1 : 1;
  }
  if (typeof actual === "number") {
    const b = Number(value);
    return actual === b ? 0 : actual < b ? -1 : 1;
  }
  if (typeof actual === "boolean") return String(actual) === value ? 0 : 1;
  const a = String(actual).toLowerCase();
  const b = value.toLowerCase();
  return a === b ? 0 : a < b ? -1 : 1;
}

// 列、または payload->draft_fields->>creator_mode のようなJSONの値。->> は文字列にする。無ければnull。
function readPath(row: Row, path: string): unknown {
  const tokens = path.split(/(->>|->)/);
  let current: unknown = row[tokens[0]];
  if (current === undefined) current = null;
  for (let i = 1; i < tokens.length; i += 2) {
    const arrow = tokens[i];
    const key = tokens[i + 1];
    if (typeof current !== "object" || current === null || Array.isArray(current)) return null;
    const next = (current as Row)[key];
    if (next === undefined || next === null) return null;
    current = arrow === "->>" ? (typeof next === "string" ? next : JSON.stringify(next)) : next;
  }
  return current;
}

function project(row: Row, select: string): Row {
  const out: Row = {};
  for (const item of select.split(",")) {
    const colon = item.indexOf(":");
    const alias = colon >= 0 ? item.slice(0, colon) : item.split(/->>|->/).pop()!;
    const path = colon >= 0 ? item.slice(colon + 1) : item;
    out[alias] = readPath(row, path);
  }
  return out;
}

function sortRows(rows: Row[], order: string): Row[] {
  const keys = order.split(",").map((part) => {
    const [column, direction] = part.split(".");
    return { column, desc: direction === "desc" };
  });
  return [...rows].sort((a, b) => {
    for (const key of keys) {
      const av = a[key.column];
      const bv = b[key.column];
      const c = compare(key.column, av, String(bv));
      if (c !== 0) return key.desc ? -c : c;
    }
    return 0;
  });
}
