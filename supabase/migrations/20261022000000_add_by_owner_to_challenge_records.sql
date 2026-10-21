-- 作者本人の挑戦を、公開ボスの集計（人気・クリア率・高難度）から外すための印（2026-10-22、ユーザー確定の案B）。
--
-- by_owner: その記録の挑戦者がボスの作者本人なら true。値は DB のトリガーが、記録の挑戦者
-- （challenger_steam_id = Edge Function が Steam の AuthenticateUserTicket で確かめた SteamID）と
-- bosses.owner_steam_id を比べて決める。行を作る時・変える時のたびに計算し直すので、書き込む側が
-- どんな値を入れても上書きされる（クライアントからは指定・改ざんできない。anon・authenticated には
-- この表の権限が無く、記録は service_role の Edge Function から SECURITY DEFINER の2関数経由でだけ作られる）。
-- 作者は後から変わらない（publish-boss は別の作者による上書きを 403 で拒む）ので、作った時の判定のままで正しい。
--
-- 変えないもの: 挑戦の記録の作り方（record_boss_challenge_attempt／_clear、(boss_id, challenger_steam_id) で1行・
-- 回数は DB で足す）、作者本人の挑戦も記録されること、未挑戦一覧（本人の記録で判定）、表の権限、RLS。
-- 集計の側（Edge Functions）は、この migration の後に by_owner=is.false で絞るものをデプロイする（逆の順にしない）。
-- 戻し方: supabase/rollback/20261022000000_drop_by_owner_from_challenge_records.sql

alter table public.boss_challenge_records
    add column if not exists by_owner boolean not null default false;

create or replace function public.boss_challenge_records_set_by_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.by_owner := exists (
        select 1 from public.bosses b
        where b.id = new.boss_id and b.owner_steam_id = new.challenger_steam_id
    );
    return new;
end;
$$;

revoke all on function public.boss_challenge_records_set_by_owner() from public, anon, authenticated;

drop trigger if exists boss_challenge_records_set_by_owner on public.boss_challenge_records;
create trigger boss_challenge_records_set_by_owner
    before insert or update on public.boss_challenge_records
    for each row
    execute function public.boss_challenge_records_set_by_owner();

-- 今ある行にも同じ判定を入れる（2026-10-22 の本番は0行）。この移し替えでは記録の更新日時（updated_at）を
-- 変えないよう、その間だけ updated_at のトリガーを止める（migration は1つの transaction で、表は ALTER TABLE で
-- 排他的に押さえているので、止めている間にほかの書き込みは入らない）。by_owner のトリガーが計算し直す。
alter table public.boss_challenge_records disable trigger boss_challenge_records_set_updated_at;
update public.boss_challenge_records r
    set by_owner = true
    from public.bosses b
    where b.id = r.boss_id and b.owner_steam_id = r.challenger_steam_id and not r.by_owner;
alter table public.boss_challenge_records enable trigger boss_challenge_records_set_updated_at;

comment on column public.boss_challenge_records.by_owner is
    '挑戦者がボスの作者本人なら true（トリガーが challenger_steam_id と bosses.owner_steam_id から決める）。人気・クリア率・高難度の集計から外す。';
