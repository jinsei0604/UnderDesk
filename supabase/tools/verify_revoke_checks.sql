-- 20261021000000_revoke_direct_table_access.sql の確かめ（2026-10-21）。
-- 空実行: supabase/tools/dry_run_migration.sh が「begin; <migration>; <このファイル>; rollback;」にして本番で流す
--         （変更は残らない）。適用の後: このファイルだけを流しても同じことを確かめられる（読み取り・ロールバックだけ）。
-- どれかが合わなければ例外で止まる（CHECK_FAIL ...）。最後の select が、役割ごとの権限の一覧を返す。

do $$
begin
  -- 公開用の鍵（anon）・ログイン利用者（authenticated）は、3つの表を直接読めない・書けない
  begin
    set local role anon;
    perform 1 from public.bosses limit 1;
    raise exception 'CHECK_FAIL anon can read bosses';
  exception when insufficient_privilege then null;
  end;
  begin
    set local role authenticated;
    perform 1 from public.bosses limit 1;
    raise exception 'CHECK_FAIL authenticated can read bosses';
  exception when insufficient_privilege then null;
  end;
  begin
    set local role anon;
    perform 1 from public.boss_challenge_records limit 1;
    raise exception 'CHECK_FAIL anon can read boss_challenge_records';
  exception when insufficient_privilege then null;
  end;
  begin
    set local role anon;
    perform 1 from public.boss_connection_tests limit 1;
    raise exception 'CHECK_FAIL anon can read boss_connection_tests';
  exception when insufficient_privilege then null;
  end;
  begin
    set local role anon;
    insert into public.boss_connection_tests default values;
    raise exception 'CHECK_FAIL anon can insert into boss_connection_tests';
  exception when insufficient_privilege or not_null_violation or check_violation then null;
  end;

  -- Edge Function（service_role）は今までどおり読める・書ける（書き込みは外側の rollback で消える）
  begin
    set local role service_role;
    perform 1 from public.bosses limit 1;
    perform 1 from public.boss_challenge_records limit 1;
    insert into public.bosses (owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
      values ('76561190000000999', 'mc-dry-run', 1, '{}'::jsonb, repeat('a', 64), 'mc-dry-run-' || gen_random_uuid()::text, true, now());
    update public.bosses set revision = revision + 1 where boss_name = 'mc-dry-run';
    perform public.record_boss_challenge_attempt(
      (select id from public.bosses where boss_name = 'mc-dry-run' limit 1), '76561190000000998');
    perform public.record_boss_challenge_clear(
      (select id from public.bosses where boss_name = 'mc-dry-run' limit 1), '76561190000000998');
    -- 上の確かめで足した行は、この塊を抜ける前に例外で消す（外側の rollback でも消えるが、二重にしておく）
    raise exception 'MC_DRY_RUN_SERVICE_ROLE_OK';
  exception
    when others then
      if sqlerrm <> 'MC_DRY_RUN_SERVICE_ROLE_OK' then
        raise exception 'CHECK_FAIL service_role: % (%)', sqlerrm, sqlstate;
      end if;
  end;
end $$;

select r.role, t.tbl,
       has_table_privilege(r.role, 'public.' || t.tbl, 'SELECT') as can_select,
       has_table_privilege(r.role, 'public.' || t.tbl, 'INSERT') as can_insert,
       has_table_privilege(r.role, 'public.' || t.tbl, 'UPDATE') as can_update,
       has_table_privilege(r.role, 'public.' || t.tbl, 'DELETE') as can_delete,
       has_table_privilege(r.role, 'public.' || t.tbl, 'TRUNCATE') as can_truncate,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = t.tbl) as policies,
       (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t.tbl)::regclass) as rls
from (values ('anon'), ('authenticated'), ('service_role')) r(role)
cross join (values ('bosses'), ('boss_challenge_records'), ('boss_connection_tests')) t(tbl)
order by 2, 1;
