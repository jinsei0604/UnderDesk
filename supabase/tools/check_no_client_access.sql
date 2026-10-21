-- 読み取りだけの点検（いつ流してもよい。何も変えない）: ゲームの公開用の鍵（anon）・authenticated・PUBLIC が、
-- public の表・順序・関数に直接触れないこと、Edge Functions（service_role）に要る権限が残っていることを確かめる（2026-10-21）。
-- migration を当てた後に毎回流す想定。合わなければ例外（CHECK_FAIL ...）で止まる。最後の select は既定の権限の一覧（情報）。
-- 流し方（リポジトリの直下）: supabase db query --linked -f supabase/tools/check_no_client_access.sql
-- トリガー関数（returns trigger）は直接呼べず REST にも出ないので、関数の EXECUTE の点検から外す。

do $$
declare
  r record;
  client_roles text[] := array['anon', 'authenticated', 'public'];
  role_name text;
begin
  -- 表・ビューなど: 直接の権限が1つも無い
  for r in
    select c.oid, c.relname, c.relkind, c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
  loop
    foreach role_name in array client_roles loop
      if has_table_privilege(role_name, r.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') then
        raise exception 'CHECK_FAIL % has a privilege on table public.%', role_name, r.relname;
      end if;
    end loop;
    if r.relkind in ('r', 'p') and not r.relrowsecurity then
      raise exception 'CHECK_FAIL RLS is off on public.%', r.relname;
    end if;
  end loop;

  -- RLS の policy: 利用者側の役割に向けたものが無い
  if exists (select 1 from pg_policies where schemaname = 'public'
             and (roles && array['anon', 'authenticated', 'public']::name[])) then
    raise exception 'CHECK_FAIL a policy in public targets anon/authenticated/public';
  end if;

  -- 順序: 権限が無い
  for r in
    select c.oid, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'S'
  loop
    foreach role_name in array client_roles loop
      if has_sequence_privilege(role_name, r.oid, 'USAGE,SELECT,UPDATE') then
        raise exception 'CHECK_FAIL % has a privilege on sequence public.%', role_name, r.relname;
      end if;
    end loop;
  end loop;

  -- 関数（トリガー関数を除く）: 呼べない
  for r in
    select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prorettype <> 'trigger'::regtype
  loop
    foreach role_name in array client_roles loop
      if has_function_privilege(role_name, r.oid, 'EXECUTE') then
        raise exception 'CHECK_FAIL % can execute public.%', role_name, r.proname;
      end if;
    end loop;
  end loop;

  -- Edge Functions（service_role）に要る権限は残っている
  if not has_table_privilege('service_role', 'public.bosses', 'SELECT')
     or not has_table_privilege('service_role', 'public.bosses', 'INSERT')
     or not has_table_privilege('service_role', 'public.bosses', 'UPDATE') then
    raise exception 'CHECK_FAIL service_role lost SELECT/INSERT/UPDATE on public.bosses';
  end if;
  if not has_table_privilege('service_role', 'public.boss_challenge_records', 'SELECT') then
    raise exception 'CHECK_FAIL service_role lost SELECT on public.boss_challenge_records';
  end if;
  if not has_function_privilege('service_role', 'public.record_boss_challenge_attempt(uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.record_boss_challenge_clear(uuid, text)', 'EXECUTE') then
    raise exception 'CHECK_FAIL service_role cannot execute the challenge record functions';
  end if;
end $$;

-- 情報: postgres がこれから public に作る物の既定の権限（anon・authenticated・PUBLIC・service_role）と、関数の全体の既定
select 'schema public' as scope,
       case d.defaclobjtype when 'r' then 'tables' when 'S' then 'sequences' when 'f' then 'functions' else d.defaclobjtype::text end as object_type,
       case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end as role,
       string_agg(a.privilege_type, ', ' order by a.privilege_type) as privileges
from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace
  and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole))
group by 1, 2, 3
union all
select 'all schemas', 'functions',
       'PUBLIC',
       case
         when not exists (select 1 from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f')
           then 'EXECUTE (PostgreSQL default)'
         when exists (select 1 from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
                      where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 0 and d.defaclobjtype = 'f' and a.grantee = 0)
           then 'EXECUTE'
         else '(none)'
       end
order by 1, 2, 3;
