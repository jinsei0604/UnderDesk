-- Phase 5 — オンライン版「未挑戦」— Steamユーザー×オンラインbossの挑戦履歴。
--
-- bosses(公開ボス本体)とは別テーブル。所有権の根拠がowner_steam_idである
-- bossesと違い、こちらは「誰が挑戦したか」という個人の挑戦履歴を保持する
-- ため、bossesの「SELECTのみ公開」ポリシーよりさらに厳しく、
-- anon/authenticatedへは一切のSELECT/INSERT/UPDATE/DELETEを許可しない
-- (ユーザー確定仕様)。読み書きは全てservice_role(RLSを迂回する)の
-- Edge Function経由に限定する。
--
-- challenger_steam_idはbosses.owner_steam_idと同じ理由(Steam
-- AuthenticateUserTicketが返した検証済みSteamID64、JavaScript Number/
-- PostgreSQLのbigintの安全整数範囲問題を避けるためtext)で保持する。

create table if not exists public.boss_challenge_records (
    id uuid primary key default gen_random_uuid(),

    boss_id uuid not null references public.bosses(id) on delete cascade,

    -- 所有権の根拠ではなく「挑戦した人」の識別子——bosses.owner_steam_idと
    -- 同じ検証済みSteamID64をEdge Function側でのみ設定する
    -- (クライアント自己申告のsteam_idは一切信用しない)。
    challenger_steam_id text not null,

    challenge_count integer not null default 0,
    clear_count integer not null default 0,

    first_challenged_at timestamptz,
    last_challenged_at timestamptz,
    first_cleared_at timestamptz,
    last_cleared_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint boss_challenge_records_steam_id_is_digits check (challenger_steam_id ~ '^[0-9]+$'),
    constraint boss_challenge_records_counts_nonnegative check (challenge_count >= 0 and clear_count >= 0),

    -- 1ユーザー×1bossにつき1行——record_boss_challenge_attempt/
    -- record_boss_challenge_clear(下記)のON CONFLICTターゲットでもある。
    constraint boss_challenge_records_unique_boss_challenger unique (boss_id, challenger_steam_id)
);

comment on table public.boss_challenge_records is
    'Steamユーザー×オンラインbossの挑戦履歴(挑戦回数・クリア回数・初回/最終日時)。個人の挑戦履歴のためanon/authenticatedへのSELECTも許可しない。読み書きはservice_role(Edge Function)経由のみ。';

create index if not exists boss_challenge_records_boss_id_idx
    on public.boss_challenge_records (boss_id);

create index if not exists boss_challenge_records_challenger_steam_id_idx
    on public.boss_challenge_records (challenger_steam_id);

-- bossesと同じ「更新漏れ防止の保険」トリガー。
create or replace function public.boss_challenge_records_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists boss_challenge_records_set_updated_at on public.boss_challenge_records;
create trigger boss_challenge_records_set_updated_at
    before update on public.boss_challenge_records
    for each row
    execute function public.boss_challenge_records_set_updated_at();

alter table public.boss_challenge_records enable row level security;

-- SELECT/INSERT/UPDATE/DELETEのいずれもanon/authenticatedへ一切許可しない
-- (ポリシーを1つも作らない——「ポリシーが無ければ拒否」がRLSの既定動作)。
-- bossesの「SELECTのみ公開」ポリシーとは異なり、個人の挑戦履歴は
-- Edge Function(service_role、RLSを迂回)経由の読み取りだけに限定し、
-- 直接のテーブルSELECTすら許可しない。

-- 新規プロジェクトの既定DEFAULT PRIVILEGESでもRLSが最終防御になるよう、
-- anon/authenticatedへはSELECTすら含め一切のGRANTを行わない
-- (bossesがSELECTだけ明示的にGRANTしているのとは対照的——個人の挑戦履歴を
-- 直接クライアントへ公開しないという設計をここでも二重に保証する)。

-- ---------------------------------------------------------------------------
-- atomic increment用のRPC関数(§4 — read-modify-writeの非atomic実装を禁止)。
-- INSERT ... ON CONFLICT (boss_id, challenger_steam_id) DO UPDATE ...
-- でchallenge_count/clear_countをDB側で加算する。SECURITY DEFINERで
-- 定義しowner(通常はpostgres/service_role相当)権限で実行されるが、
-- EXECUTE権限はservice_roleにのみ付与し、anon/authenticatedには一切
-- 与えない——Edge Function(service_roleキー)以外からは呼び出せない。
-- ---------------------------------------------------------------------------

create or replace function public.record_boss_challenge_attempt(
    p_boss_id uuid,
    p_steam_id text
)
returns public.boss_challenge_records
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.boss_challenge_records;
begin
    insert into public.boss_challenge_records (
        boss_id, challenger_steam_id, challenge_count, clear_count,
        first_challenged_at, last_challenged_at
    )
    values (p_boss_id, p_steam_id, 1, 0, now(), now())
    on conflict (boss_id, challenger_steam_id) do update
        set challenge_count = public.boss_challenge_records.challenge_count + 1,
            last_challenged_at = now()
    returning * into result;
    return result;
end;
$$;

comment on function public.record_boss_challenge_attempt(uuid, text) is
    '挑戦開始のatomic記録。存在しなければ1行作成、存在すればchallenge_countをDB側で+1する(read-modify-writeではなくON CONFLICT DO UPDATEで競合に強くする)。';

create or replace function public.record_boss_challenge_clear(
    p_boss_id uuid,
    p_steam_id text
)
returns public.boss_challenge_records
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.boss_challenge_records;
begin
    -- 既存ローカル(RBMLocalStageRepository.record_challenge_clear())と同じ
    -- 防御的仕様: attempt行が無くてもclear記録だけで安全に行を作成できるが、
    -- その場合challenge_countは0のまま(勝手に+1しない、ローカル版が
    -- clear_countだけを独立して加算しchallenge_countには触れないのと
    -- 同じ挙動)。
    insert into public.boss_challenge_records (
        boss_id, challenger_steam_id, challenge_count, clear_count,
        first_cleared_at, last_cleared_at
    )
    values (p_boss_id, p_steam_id, 0, 1, now(), now())
    on conflict (boss_id, challenger_steam_id) do update
        set clear_count = public.boss_challenge_records.clear_count + 1,
            first_cleared_at = coalesce(public.boss_challenge_records.first_cleared_at, now()),
            last_cleared_at = now()
    returning * into result;
    return result;
end;
$$;

comment on function public.record_boss_challenge_clear(uuid, text) is
    'クリアのatomic記録。attempt行が無くても安全に行を作成するが、その場合もchallenge_countは加算しない(ローカル版record_challenge_clear()と同じ、挑戦回数とクリア回数は独立したカウンタという既存方針を踏襲)。';

-- 関数自体の実行権限もservice_roleにのみ限定する
-- (PUBLICへのデフォルトEXECUTE権限を明示的に剥奪してから付与し直す)。
revoke all on function public.record_boss_challenge_attempt(uuid, text) from public;
revoke all on function public.record_boss_challenge_clear(uuid, text) from public;
grant execute on function public.record_boss_challenge_attempt(uuid, text) to service_role;
grant execute on function public.record_boss_challenge_clear(uuid, text) to service_role;
