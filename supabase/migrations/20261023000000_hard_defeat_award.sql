-- 難関ボス討伐の認定と、戦闘チケットによる挑戦結果の記録（2026-10-23、ユーザー確定）。
--
-- 挑戦者・クリア率の基準（一覧・検索・ランダム・未挑戦・人気・高難度・認定で共通。Edge Functions が result_count > 0 で絞る）:
--   挑戦者 = 作者本人を除き、決着した戦闘（勝ち・負け）の結果が1回以上ある人
--   クリアした人 = そのうち、勝ちの結果が1回以上ある人。通常クリア率 = クリアした人 ÷ 挑戦者（挑戦者0人なら未集計）
-- 結果は、サーバーが戦闘の開始ごとに出す1回限りの戦闘チケット（boss_battle_tickets）でだけ受け付ける（submit_boss_battle_result）。
-- 同じ結果（チケット・結果の id）は1回しか数えない。旧版のゲームのクリアの記録（record_boss_challenge_clear）は今までどおり
-- clear_count だけを足し、挑戦結果・クリア率・認定には数えない（勝敗を確かめられないため）。この migration より前の記録も数えない。
--
-- 難関ボス = 作者を除いた挑戦結果50回以上・挑戦者10人以上・通常クリア率5%以下（20 × クリアした人 ≤ 挑戦者）。
-- 認定を受けるのは、初めて結果でクリアした時のほかの人（作者・本人を除く挑戦者）のクリア率が5%以下だった人。
-- ほかに挑戦者が0人だった時（最初のクリア）は 0% と決めつけず判定保留とし、ボスが条件を満たした時に認定する。
-- 初めてクリアした時に条件に届いていなければ保留し、後で満たした時にさかのぼって認定する。一度ついた認定は消さない（トリガー）。
-- 戻し方: supabase/rollback/20261023000000_drop_hard_defeat_award.sql

alter table public.boss_challenge_records
    add column if not exists result_count integer not null default 0,
    add column if not exists result_clear_count integer not null default 0,
    add column if not exists first_clear_challengers integer,
    add column if not exists first_clear_clearers integer,
    add column if not exists hard_awarded_at timestamptz;

alter table public.boss_challenge_records drop constraint if exists boss_challenge_records_hard_fields_valid;
alter table public.boss_challenge_records add constraint boss_challenge_records_hard_fields_valid check (
    result_count >= 0
    and result_clear_count >= 0
    and result_clear_count <= result_count
    and (first_clear_challengers is null) = (first_clear_clearers is null)
    and (first_clear_clearers is null or (first_clear_clearers >= 0 and first_clear_clearers <= first_clear_challengers))
);

-- 一度入った初回クリアの数と認定は変えない（null に戻す・書き換えることもできない）
create or replace function public.boss_challenge_records_keep_permanent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.hard_awarded_at is not null then
        new.hard_awarded_at := old.hard_awarded_at;
    end if;
    if old.first_clear_challengers is not null then
        new.first_clear_challengers := old.first_clear_challengers;
        new.first_clear_clearers := old.first_clear_clearers;
    end if;
    return new;
end;
$$;
revoke all on function public.boss_challenge_records_keep_permanent() from public, anon, authenticated;

drop trigger if exists boss_challenge_records_keep_permanent on public.boss_challenge_records;
create trigger boss_challenge_records_keep_permanent
    before update on public.boss_challenge_records
    for each row
    execute function public.boss_challenge_records_keep_permanent();

-- 戦闘チケット（1戦闘1枚、1回限り）。読み書きは下の SECURITY DEFINER の関数だけ（表への直接の権限は誰にも出さない）。
create table if not exists public.boss_battle_tickets (
    id uuid primary key default gen_random_uuid(),
    boss_id uuid not null references public.bosses(id) on delete cascade,
    challenger_steam_id text not null check (challenger_steam_id ~ '^[0-9]+$'),
    creator_mode text not null,
    boss_revision integer not null,
    issued_at timestamptz not null default now(),
    expires_at timestamptz not null,
    used_at timestamptz,
    outcome text check (outcome in ('clear', 'loss')),
    result_id uuid unique,
    constraint boss_battle_tickets_use_consistent check ((used_at is null) = (outcome is null) and (outcome is null) = (result_id is null))
);
create index if not exists boss_battle_tickets_challenger_boss_idx on public.boss_battle_tickets (challenger_steam_id, boss_id, issued_at);
create index if not exists boss_battle_tickets_expires_idx on public.boss_battle_tickets (expires_at);
alter table public.boss_battle_tickets enable row level security;
revoke all on table public.boss_battle_tickets from anon, authenticated, public, service_role;
comment on table public.boss_battle_tickets is '戦闘チケット（2026-10-23）。戦闘の開始ごとにサーバーが出し、決着した結果を1回だけ受け付ける。読み書きは issue_boss_battle_ticket・submit_boss_battle_result だけ。';

-- 作者本人を除いた、決着した結果の集計（1ボス分。boss_id の索引で、そのボスの行だけを読む）。
-- p_exclude_steam_id を渡すと、その人も除く（初めてクリアした時の「ほかの人」の数を取るため）。
create or replace function public.boss_hard_defeat_stats(p_boss_id uuid, p_exclude_steam_id text default null)
returns table (results bigint, challengers bigint, clearers bigint)
language sql
stable
set search_path = ''
as $$
    select coalesce(sum(r.result_count), 0)::bigint,
           count(*) filter (where r.result_count > 0),
           count(*) filter (where r.result_count > 0 and r.result_clear_count > 0)
    from public.boss_challenge_records r
    where r.boss_id = p_boss_id
      and not r.by_owner
      and (p_exclude_steam_id is null or r.challenger_steam_id <> p_exclude_steam_id);
$$;
revoke all on function public.boss_hard_defeat_stats(uuid, text) from public, anon, authenticated;

-- 難関ボスの条件（数だけで決まる。境界のテストのため独立させる）: 結果50回以上・挑戦者10人以上・通常クリア率5%以下。
create or replace function public.boss_hard_defeat_qualifies(p_results bigint, p_challengers bigint, p_clearers bigint)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select p_results >= 50 and p_challengers >= 10 and p_clearers * 20 <= p_challengers;
$$;
revoke all on function public.boss_hard_defeat_qualifies(bigint, bigint, bigint) from public, anon, authenticated;

-- ボスが今、難関の条件を満たすなら、まだ認定していない対象者を認定する（戻り値: 新しく認定した人数）。
create or replace function public.award_hard_defeats(p_boss_id uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
    s record;
    awarded integer := 0;
begin
    select * into s from public.boss_hard_defeat_stats(p_boss_id, null);
    if public.boss_hard_defeat_qualifies(s.results, s.challengers, s.clearers) then
        update public.boss_challenge_records r
            set hard_awarded_at = now()
            where r.boss_id = p_boss_id
              and not r.by_owner
              and r.result_clear_count > 0
              and r.hard_awarded_at is null
              and r.first_clear_challengers is not null
              and (r.first_clear_challengers = 0                          -- 最初のクリア: 判定保留 → ここで認定
                   or r.first_clear_clearers * 20 <= r.first_clear_challengers);   -- 初回クリア時のほかの人のクリア率が5%以下
        get diagnostics awarded = row_count;
    end if;
    return awarded;
end;
$$;
revoke all on function public.award_hard_defeats(uuid) from public, anon, authenticated;

-- 戦闘チケットを出す（戦闘の開始ごと。途中でやり直した戦闘は結果が出ていないので、ゲームは同じチケットを使い続ける）。
-- 公開中のボスだけ。モード・版は DB の値を残す（クライアントの値は使わない）。
-- 連続した不自然な発行を止める: 1人×1ボスで1時間に60枚まで・1人で24時間に600枚まで（どちらも結果1回につき1枚なので、
-- 結果を送れる回数の上限にもなる）。超えても戦闘は止めない（その戦闘の結果が数えられないだけ）。
-- 期限は30日（通信が切れた結果を後で送り直せるように）。期限から1日過ぎたチケットは、ここで消す（本人の分すべてと、
-- ほかの人の分を少しずつ。表を大きくしない）。
-- 戻り値の status: issued・not_found・rate_limited・daily_limit
create or replace function public.issue_boss_battle_ticket(p_boss_id uuid, p_steam_id text)
returns table (status text, ticket_id uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    boss record;
    recent integer;
    t public.boss_battle_tickets;
begin
    select b.id, b.revision, coalesce(b.payload -> 'draft_fields' ->> 'creator_mode', 'simple') as mode into boss
        from public.bosses b where b.id = p_boss_id and b.is_published;
    if not found then
        return query select 'not_found'::text, null::uuid, null::timestamptz;
        return;
    end if;
    delete from public.boss_battle_tickets k
        where k.challenger_steam_id = p_steam_id and k.expires_at < now() - interval '1 day';
    delete from public.boss_battle_tickets k
        where k.id in (select o.id from public.boss_battle_tickets o where o.expires_at < now() - interval '1 day' limit 100);
    select count(*) into recent from public.boss_battle_tickets k
        where k.challenger_steam_id = p_steam_id and k.boss_id = p_boss_id and k.issued_at > now() - interval '1 hour';
    if recent >= 60 then
        return query select 'rate_limited'::text, null::uuid, null::timestamptz;
        return;
    end if;
    select count(*) into recent from public.boss_battle_tickets k
        where k.challenger_steam_id = p_steam_id and k.issued_at > now() - interval '24 hours';
    if recent >= 600 then
        return query select 'daily_limit'::text, null::uuid, null::timestamptz;
        return;
    end if;
    insert into public.boss_battle_tickets (boss_id, challenger_steam_id, creator_mode, boss_revision, expires_at)
        values (p_boss_id, p_steam_id, boss.mode, boss.revision, now() + interval '30 days')
        returning * into t;
    return query select 'issued'::text, t.id, t.expires_at;
end;
$$;
revoke all on function public.issue_boss_battle_ticket(uuid, text) from public, anon, authenticated;
grant execute on function public.issue_boss_battle_ticket(uuid, text) to service_role;

-- 決着した結果を受け付ける（1チケット1回）。同じチケット・同じ結果の id・同じ勝敗の送り直しは数えずに duplicate を返す。
-- 戻り値の status: counted・duplicate・invalid（無い・本人やボスが違う・勝敗の値が違う）・used（別の結果で使用済み）・expired
create or replace function public.submit_boss_battle_result(
    p_ticket_id uuid,
    p_boss_id uuid,
    p_steam_id text,
    p_result_id uuid,
    p_outcome text
)
returns table (status text, by_owner boolean, hard_awarded boolean, clear_count integer,
               first_clear_challengers integer, first_clear_clearers integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    t public.boss_battle_tickets;
    rec public.boss_challenge_records;
    prior_clears integer;
    others_challengers integer;
    others_clearers integer;
begin
    if p_outcome is null or p_outcome not in ('clear', 'loss') or p_result_id is null then
        return query select 'invalid'::text, null::boolean, null::boolean, null::integer, null::integer, null::integer;
        return;
    end if;
    select * into t from public.boss_battle_tickets k where k.id = p_ticket_id for update;
    if not found or t.challenger_steam_id <> p_steam_id or t.boss_id <> p_boss_id then
        return query select 'invalid'::text, null::boolean, null::boolean, null::integer, null::integer, null::integer;
        return;
    end if;
    if t.used_at is not null then
        if t.result_id = p_result_id and t.outcome = p_outcome then
            select * into rec from public.boss_challenge_records r where r.boss_id = t.boss_id and r.challenger_steam_id = p_steam_id;
            return query select 'duplicate'::text, rec.by_owner, rec.hard_awarded_at is not null, rec.clear_count,
                rec.first_clear_challengers, rec.first_clear_clearers;
            return;
        end if;
        return query select 'used'::text, null::boolean, null::boolean, null::integer, null::integer, null::integer;
        return;
    end if;
    if t.expires_at < now() then
        return query select 'expired'::text, null::boolean, null::boolean, null::integer, null::integer, null::integer;
        return;
    end if;
    if exists (select 1 from public.boss_battle_tickets k where k.result_id = p_result_id) then
        return query select 'used'::text, null::boolean, null::boolean, null::integer, null::integer, null::integer;
        return;
    end if;
    update public.boss_battle_tickets k set used_at = now(), outcome = p_outcome, result_id = p_result_id where k.id = t.id;

    if p_outcome = 'clear' then
        select r.result_clear_count into prior_clears from public.boss_challenge_records r
            where r.boss_id = p_boss_id and r.challenger_steam_id = p_steam_id;
        -- 初めて結果でクリアした時だけ、その時の「ほかの人」（作者・本人を除く挑戦者）の数を残す
        if coalesce(prior_clears, 0) = 0 then
            select s.challengers, s.clearers into others_challengers, others_clearers
                from public.boss_hard_defeat_stats(p_boss_id, p_steam_id) s;
        end if;
        insert into public.boss_challenge_records (
            boss_id, challenger_steam_id, challenge_count, clear_count, result_count, result_clear_count,
            first_cleared_at, last_cleared_at, first_clear_challengers, first_clear_clearers
        )
        values (p_boss_id, p_steam_id, 0, 1, 1, 1, now(), now(), others_challengers, others_clearers)
        on conflict (boss_id, challenger_steam_id) do update
            set clear_count = public.boss_challenge_records.clear_count + 1,
                result_count = public.boss_challenge_records.result_count + 1,
                result_clear_count = public.boss_challenge_records.result_clear_count + 1,
                first_cleared_at = coalesce(public.boss_challenge_records.first_cleared_at, now()),
                last_cleared_at = now(),
                first_clear_challengers = case when public.boss_challenge_records.result_clear_count = 0
                    then excluded.first_clear_challengers else public.boss_challenge_records.first_clear_challengers end,
                first_clear_clearers = case when public.boss_challenge_records.result_clear_count = 0
                    then excluded.first_clear_clearers else public.boss_challenge_records.first_clear_clearers end;
    else
        insert into public.boss_challenge_records (boss_id, challenger_steam_id, challenge_count, clear_count, result_count)
        values (p_boss_id, p_steam_id, 0, 0, 1)
        on conflict (boss_id, challenger_steam_id) do update
            set result_count = public.boss_challenge_records.result_count + 1;
    end if;
    perform public.award_hard_defeats(p_boss_id);
    select * into rec from public.boss_challenge_records r where r.boss_id = p_boss_id and r.challenger_steam_id = p_steam_id;
    return query select 'counted'::text, rec.by_owner, rec.hard_awarded_at is not null, rec.clear_count,
        rec.first_clear_challengers, rec.first_clear_clearers;
end;
$$;
revoke all on function public.submit_boss_battle_result(uuid, uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function public.submit_boss_battle_result(uuid, uuid, text, uuid, text) to service_role;

comment on column public.boss_challenge_records.result_count is '決着した戦闘（勝ち・負け）の結果の回数。戦闘チケットで受け付けた分だけ。挑戦の開始（challenge_count）・旧版のクリアの記録は数えない。';
comment on column public.boss_challenge_records.result_clear_count is '戦闘チケットで受け付けた勝ちの回数（通常クリア率・認定の「クリアした人」はこれが1以上の人）。';
comment on column public.boss_challenge_records.hard_awarded_at is '難関ボス討伐の認定日時。一度入ったら変えない（トリガー boss_challenge_records_keep_permanent）。';
