-- 公開用の鍵（anon）・ログイン利用者（authenticated）・PUBLIC が、public スキーマの何に触れるかを調べる（読み取りだけ）。
-- 実行: supabase db query --linked -f supabase/tools/inspect_public_access.sql
-- 2026-10-21 作成（bosses の表を公開用の鍵で直接読めた件の調査と、修正の前後の確認）。

select 'table_privilege' as kind, c.relname as object, c.relkind::text as relkind,
       r.rolname as grantee,
       string_agg(distinct p.privilege_type, ',' order by p.privilege_type) as privileges,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
cross join lateral (
  select (aclexplode(coalesce(c.relacl, acldefault('r', c.relowner)))).*
) a
left join pg_roles r on r.oid = a.grantee
cross join lateral (select a.privilege_type) p
where c.relkind in ('r', 'v', 'm', 'p', 'f')
  and (a.grantee = 0 or r.rolname in ('anon', 'authenticated', 'service_role'))
group by c.relname, c.relkind, r.rolname, c.relrowsecurity, c.relforcerowsecurity

union all
select 'column_privilege', table_name, 'col', grantee, string_agg(distinct privilege_type || ':' || column_name, ',' order by privilege_type || ':' || column_name), null, null
from information_schema.column_privileges
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC')
  and (table_schema, table_name, grantee, privilege_type) not in (
    select table_schema, table_name, grantee, privilege_type from information_schema.table_privileges where table_schema = 'public')
group by table_name, grantee

union all
select 'policy', tablename, cmd, array_to_string(roles, ','), coalesce(qual, '') || ' | ' || coalesce(with_check, ''), null, null
from pg_policies where schemaname = 'public'

union all
select 'function_execute', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', case when p.prosecdef then 'definer' else 'invoker' end,
       coalesce(r.rolname, 'PUBLIC'), a.privilege_type, null, null
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
cross join lateral (select (aclexplode(coalesce(p.proacl, acldefault('f', p.proowner)))).*) a
left join pg_roles r on r.oid = a.grantee
where a.grantee = 0 or r.rolname in ('anon', 'authenticated')

union all
select 'default_privilege', d.defaclobjtype::text, pg_get_userbyid(d.defaclrole), coalesce(r.rolname, 'PUBLIC'), a.privilege_type, null, null
from pg_default_acl d
join pg_namespace n on n.oid = d.defaclnamespace and n.nspname = 'public'
cross join lateral (select (aclexplode(d.defaclacl)).*) a
left join pg_roles r on r.oid = a.grantee
where a.grantee = 0 or r.rolname in ('anon', 'authenticated')

order by 1, 2, 4;
