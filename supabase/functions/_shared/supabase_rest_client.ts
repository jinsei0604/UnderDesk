// Phase 4B/4C/4D/4E — 共有: PostgRESTへの生HTTPアクセスをinterface化した
// もの。supabase-jsのようなSDKを追加せず、既存のSupabase PoC
// (rbm_supabase_client.gd / steam-auth/steam_web_api_client.ts)と同じ
// 「Godot標準HTTPRequestのみ」「fetch()のみ」という最小依存の流儀を
// Edge Function側でも踏襲する。
//
// 全ての書き込み系Edge Function(publish-boss/unpublish-boss)は、
// SUPABASE_SERVICE_ROLE_KEYを使うこのクライアント経由でのみbossesテーブル
// へ触れる——service_roleはRLSを迂回するため、直接INSERT/UPDATE/DELETE
// ポリシーをbossesテーブルへ一切与えていない設計(migration参照)と対になる。
//
// テストは全てFakeSupabaseRestClientを使い、実Supabaseへは一切出ない。

export interface RestResult<T> {
  ok: boolean;
  rows: T[];
  status: number;
  errorMessage?: string;
}

export interface SupabaseRestClient {
  select<T>(table: string, query: string): Promise<RestResult<T>>;
  insert<T>(table: string, row: Record<string, unknown>): Promise<RestResult<T>>;
  // PostgRESTのfilter文字列（例: "id=eq.<uuid>"）で対象行を絞ってPATCHする。
  update<T>(
    table: string,
    filterQuery: string,
    patch: Record<string, unknown>,
  ): Promise<RestResult<T>>;
}

export class RealSupabaseRestClient implements SupabaseRestClient {
  constructor(
    private readonly supabaseUrl: string,
    private readonly serviceRoleKey: string,
  ) {}

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return {
      apikey: this.serviceRoleKey,
      Authorization: `Bearer ${this.serviceRoleKey}`,
      "Content-Type": "application/json",
      ...extra,
    };
  }

  async select<T>(table: string, query: string): Promise<RestResult<T>> {
    const url = `${this.supabaseUrl}/rest/v1/${table}?${query}`;
    return await this.request<T>(url, { method: "GET", headers: this.headers() });
  }

  async insert<T>(table: string, row: Record<string, unknown>): Promise<RestResult<T>> {
    const url = `${this.supabaseUrl}/rest/v1/${table}`;
    return await this.request<T>(url, {
      method: "POST",
      headers: this.headers({ Prefer: "return=representation" }),
      body: JSON.stringify(row),
    });
  }

  async update<T>(
    table: string,
    filterQuery: string,
    patch: Record<string, unknown>,
  ): Promise<RestResult<T>> {
    const url = `${this.supabaseUrl}/rest/v1/${table}?${filterQuery}`;
    return await this.request<T>(url, {
      method: "PATCH",
      headers: this.headers({ Prefer: "return=representation" }),
      body: JSON.stringify(patch),
    });
  }

  private async request<T>(url: string, init: RequestInit): Promise<RestResult<T>> {
    try {
      const response = await fetch(url, init);
      const status = response.status;
      const text = await response.text();
      if (status >= 400) {
        return { ok: false, rows: [], status, errorMessage: text };
      }
      if (text.trim().length === 0) {
        return { ok: true, rows: [], status };
      }
      const parsed = JSON.parse(text);
      const rows = Array.isArray(parsed) ? parsed : [parsed];
      return { ok: true, rows, status };
    } catch (error) {
      return {
        ok: false,
        rows: [],
        status: 0,
        errorMessage: error instanceof Error ? error.message : String(error),
      };
    }
  }
}
