-- 2026-10-29 体験版のオンライン挑戦: 異なるオンラインボスへの挑戦は、Steam アカウントごとに累計15体まで。
--
-- 決まり（ユーザー確定）:
-- - 初めて戦闘を始めたボスを1体と数える。同じボス（同じ boss_id）への再挑戦・勝ち負けは関係しない（何度でも挑戦できる）。
-- - 15体に達した後は、新しいボスには挑戦できない。挑戦済みの15体には何度でも挑戦できる。
-- - ボス名ではなく boss_id で数える。同じ boss_id のボスの更新・非公開・再公開では数え直さない。
-- - ボスが削除されても、使った枠は戻らない（bosses への外部キーを付けない。boss_challenge_records とは独立した累計）。
-- - 製品版には制限が無い（体験版かどうかは Edge Function が Steam のチケットのアプリで決め、体験版の時だけここを呼ぶ）。
--
-- 数え方は claim_demo_challenge_slot() だけが行う。同じ人の同時の要求は advisory lock で順番に処理するので、
-- 複数の端末・同時の要求でも16体目は通らない。同じボスは主キーで1行だけ（二重の要求・送り直しで増えない）。
-- 表への直接の権限は誰にも出さない（読み書きは下の SECURITY DEFINER の関数だけ。service_role が呼ぶ）。

create table if not exists public.demo_challenge_slots (
    steam_id text not null check (steam_id ~ '^[0-9]+$'),
    boss_id uuid not null,
    claimed_at timestamptz not null default now(),
    primary key (steam_id, boss_id)
);
alter table public.demo_challenge_slots enable row level security;
revoke all on table public.demo_challenge_slots from anon, authenticated, public, service_role;
comment on table public.demo_challenge_slots is '体験版のオンライン挑戦の累計（2026-10-29）。Steam アカウントごとに挑戦を始めたボスの id を1行ずつ。15体まで。ボスが消えても行は残す。読み書きは claim_demo_challenge_slot・demo_challenge_status だけ。';

-- 体験版の利用者がオンラインのボスとの戦闘を始める時に呼ぶ（record-challenge-attempt・issue-battle-ticket）。
-- 戻り値の status:
--   already   … このボスは挑戦済み（枠を使わない。15体に達していても挑戦できる）
--   claimed   … 新しく枠を1つ使った
--   limit     … 15体に達していて、新しいボスには挑戦できない（行は増やさない）
--   not_found … 公開中のボスではない（行は増やさない。戦闘が成り立たないので枠を使わない）
-- used は呼んだ後の挑戦済みの数、slot_limit は上限（15）。
create or replace function public.claim_demo_challenge_slot(p_boss_id uuid, p_steam_id text)
returns table (status text, used integer, slot_limit integer)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
    max_slots constant integer := 15;
    n integer;
begin
    -- 2026-10-30 安全対策: 数え方は read committed（PostgreSQL・Supabase の既定）が前提。ロックを待った後の数え直しで、
    -- 先に終わった同じ人の要求の行が見える。repeatable read・serializable ではトランザクションの最初の時点の内容しか
    -- 見えず、同時の要求で15体を超えうるので、枠を増やさずにエラーで止める（何も書かない。Edge Function は 502 の
    -- db_error として扱い、15体の上限（limit）とは区別する。ゲームは「通信できなかった」と出して戦闘を始めない）。
    if current_setting('transaction_isolation') <> 'read committed' then
        raise exception 'claim_demo_challenge_slot requires read committed isolation (current: %)', current_setting('transaction_isolation')
            using hint = 'demo_challenge_slots: unexpected transaction isolation';
    end if;
    -- 同じ人の要求を順番に処理する（同時の要求で数え間違えない。ほかの人は待たせない）。
    perform pg_advisory_xact_lock(hashtextextended('demo_challenge_slots:' || p_steam_id, 0));
    select count(*) into n from public.demo_challenge_slots s where s.steam_id = p_steam_id;
    if exists (select 1 from public.demo_challenge_slots s where s.steam_id = p_steam_id and s.boss_id = p_boss_id) then
        return query select 'already'::text, n, max_slots;
        return;
    end if;
    if not exists (select 1 from public.bosses b where b.id = p_boss_id and b.is_published) then
        return query select 'not_found'::text, n, max_slots;
        return;
    end if;
    if n >= max_slots then
        return query select 'limit'::text, n, max_slots;
        return;
    end if;
    insert into public.demo_challenge_slots (steam_id, boss_id) values (p_steam_id, p_boss_id)
        on conflict (steam_id, boss_id) do nothing;
    select count(*) into n from public.demo_challenge_slots s where s.steam_id = p_steam_id;
    return query select 'claimed'::text, n, max_slots;
end;
$$;
revoke all on function public.claim_demo_challenge_slot(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_demo_challenge_slot(uuid, text) to service_role;

-- 今の使用状況（体験版のオンライン一覧の「オンライン挑戦 ○ / 15体」と、挑戦済みのボスの見分けに使う）。読むだけ。
create or replace function public.demo_challenge_status(p_steam_id text)
returns table (used integer, slot_limit integer, boss_ids uuid[])
language sql
stable
security definer
set search_path = ''
as $$
    select count(*)::integer, 15, coalesce(array_agg(s.boss_id order by s.claimed_at), '{}'::uuid[])
        from public.demo_challenge_slots s where s.steam_id = p_steam_id;
$$;
revoke all on function public.demo_challenge_status(text) from public, anon, authenticated;
grant execute on function public.demo_challenge_status(text) to service_role;
