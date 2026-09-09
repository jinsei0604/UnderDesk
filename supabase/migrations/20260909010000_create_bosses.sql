-- Phase 4B — 本番bosses schema。
--
-- boss_connection_tests（Steam認証導入前の接続確認PoC専用）とは完全に
-- 分離した、新規のテーブル・ポリシーです。PoCテーブルのrename/流用は
-- 行っていません。PoCテーブル・そのマイグレーション自体もこのマイグレー
-- ションでは一切変更しません。
--
-- 所有権の根拠はowner_steam_id(text、Steam AuthenticateUserTicketが
-- 返した検証済みSteamID64)だけです。author_nameは表示専用で、所有権判定
-- には使いません(ユーザー確定仕様)。
--
-- 直接のINSERT/UPDATE/DELETEはこのテーブルに対して一切許可しません。
-- 書き込みは全てservice_role(RLSを迂回する)で動くEdge Function経由に
-- 限定します——「Steam正式認証がまだ無いから匿名書き込みを許可する」
-- という回避は行っていません(ユーザー確定仕様、boss_connection_tests
-- のPoCポリシーはここへコピーしません)。

create table if not exists public.bosses (
    id uuid primary key default gen_random_uuid(),

    -- 所有権の唯一の根拠。Steam AuthenticateUserTicketの検証結果からのみ
    -- Edge Function側で設定される——クライアントの自己申告を信用しない
    -- (ユーザー確定仕様)。SteamID64はJavaScript Number/PostgreSQLの
    -- bigintの安全整数範囲問題を避けるため常にtextとして保持する。
    owner_steam_id text not null,

    -- 表示専用（persona name等）。所有権判定には一切使わない。
    author_name text not null default '',
    boss_name text not null,

    -- Godotクライアントが読めるdraft_fields/battle_hash形式のバージョン。
    -- 未知のschema_versionを受信した場合、クライアント側
    -- (RBMOnlineBossPayload.validate_for_challenge())がBattleへ渡す前に
    -- 安全に拒否する。
    schema_version integer not null,

    -- 初回公開=1、再Clear Check後の再公開で2,3,...と進める。
    revision integer not null default 1,

    -- RBMOnlineBossPayload.build_for_publish()が生成したpayload全体
    -- (schema_version/boss_name/author_name/draft_fields/
    -- clear_check_success_snapshot/battle_hashを含む)をそのまま格納する。
    -- 個別カラムへ分解しない——Godot側のpayload形式がそのまま正であり、
    -- スキーマの二重管理を避けるため。
    payload jsonb not null,

    -- payload.battle_hashの複製（クエリ・整合性チェック用に単独カラムでも
    -- 持つ）。Postgres側はこの値を再計算しない——正規化直列化の細部を
    -- GDScriptとSQL/Denoで一致させ続ける必要を作らないため、あくまで
    -- Godotクライアントが計算した値をそのまま保存するだけの不透明な文字列
    -- として扱う（Challenger側クライアントが再計算して突き合わせる）。
    battle_hash text not null,

    is_published boolean not null default false,
    published_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    -- ボタン連打・通信再送で同一revisionが複数行として投稿されるのを防ぐ
    -- (owner_steam_id + battle_hash + revisionが同じ投稿要求は、Edge
    -- Function側でこのキーへ正規化して衝突させる——ON CONFLICT DO NOTHING
    -- 相当)。
    idempotency_key text not null,

    -- Makerが自分のローカル保存(stage_id)とオンライン投稿を結び付けるため
    -- だけの参照——所有権判定には使わない（あくまでowner_steam_id）。
    local_stage_id text,

    constraint bosses_owner_steam_id_is_digits check (owner_steam_id ~ '^[0-9]+$'),
    constraint bosses_schema_version_positive check (schema_version >= 1),
    constraint bosses_revision_positive check (revision >= 1),
    constraint bosses_battle_hash_format check (battle_hash ~ '^[0-9a-f]{64}$'),
    constraint bosses_idempotency_key_unique unique (idempotency_key)
);

comment on table public.bosses is
    '本番の公開ボスデータ。boss_connection_tests(PoC専用)とは分離。書き込みはservice_role(Edge Function)経由のみ。';

create index if not exists bosses_is_published_published_at_idx
    on public.bosses (is_published, published_at desc)
    where is_published;

create index if not exists bosses_owner_steam_id_idx
    on public.bosses (owner_steam_id);

-- updated_atを自動更新するトリガー（Edge Function側での更新漏れを防ぐ
-- 保険——書き込みロジック自体は引き続きEdge Function側で完結させる）。
create or replace function public.bosses_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists bosses_set_updated_at on public.bosses;
create trigger bosses_set_updated_at
    before update on public.bosses
    for each row
    execute function public.bosses_set_updated_at();

alter table public.bosses enable row level security;

-- SELECT: 公開済みボスのみ、誰でも(anon/authenticated)取得可能。
drop policy if exists "bosses_select_published_only" on public.bosses;
create policy "bosses_select_published_only"
    on public.bosses
    for select
    to anon, authenticated
    using (is_published);

-- INSERT/UPDATE/DELETE用のポリシーは意図的に一切作成しない——
-- anon/authenticatedロールに対するデフォルトは「ポリシーが無ければ拒否」
-- のため、これらの操作はservice_role(RLSを迂回する、Edge Function内でのみ
-- 使用)経由でしか行えない。boss_connection_testsのような
-- 「匿名なら誰でも書き込める」ポリシーはここには一切存在しない。

-- 新規プロジェクトの既定DEFAULT PRIVILEGESでもRLSが最終防御になるよう、
-- SELECTのみ明示的にGRANTする（INSERT/UPDATE/DELETEは付与しない——
-- ポリシーが無いのでどのみち拒否されるが、権限自体も与えないことで
-- 「必要以上の権限を付与しない」を二重に保証する）。
grant select on public.bosses to anon, authenticated;
