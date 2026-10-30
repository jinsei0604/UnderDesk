-- 20261029000000_demo_challenge_slots（体験版のオンライン挑戦の15体）の確かめ（2026-10-30）。
-- 空実行: 「begin; <migration>; <このファイル>; rollback;」（supabase/tools/dry_run_migration.sh）。
-- 適用の後: このファイルを begin; と rollback; で挟んで流す。行は作らない（架空の SteamID と、存在しない boss_id で呼ぶだけ）。
-- 合わなければ CHECK_FAIL で止まる。
do $$
declare
  v_res record;
  v_cnt integer;
begin
  -- 1. 表: 主キー・RLS・誰にも直接の権限が無い
  if to_regclass('public.demo_challenge_slots') is null then raise exception 'CHECK_FAIL table missing'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.demo_challenge_slots'::regclass) then raise exception 'CHECK_FAIL rls off'; end if;
  if has_table_privilege('anon', 'public.demo_challenge_slots', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated', 'public.demo_challenge_slots', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role', 'public.demo_challenge_slots', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'CHECK_FAIL table privileges';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'public.demo_challenge_slots'::regclass and contype = 'p') <> 1
     or (select count(*) from pg_constraint where conrelid = 'public.demo_challenge_slots'::regclass and contype = 'f') <> 0 then
    raise exception 'CHECK_FAIL constraints';
  end if;
  -- 2. 関数: security definer・search_path 空・service_role だけが実行できる
  if not (select prosecdef from pg_proc where oid = 'public.claim_demo_challenge_slot(uuid,text)'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.demo_challenge_status(text)'::regprocedure) then
    raise exception 'CHECK_FAIL not security definer';
  end if;
  if (select proconfig from pg_proc where oid = 'public.claim_demo_challenge_slot(uuid,text)'::regprocedure) <> array['search_path=""']
     or (select proconfig from pg_proc where oid = 'public.demo_challenge_status(text)'::regprocedure) <> array['search_path=""'] then
    raise exception 'CHECK_FAIL search_path';
  end if;
  if has_function_privilege('anon', 'public.claim_demo_challenge_slot(uuid,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.claim_demo_challenge_slot(uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.demo_challenge_status(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.demo_challenge_status(text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.claim_demo_challenge_slot(uuid,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.demo_challenge_status(text)', 'EXECUTE') then
    raise exception 'CHECK_FAIL function privileges';
  end if;
  -- 3. 呼び出し（行を増やさない経路だけ）: 公開されていないボス → not_found・0体。使用状況は 0 / 15
  select * into v_res from public.claim_demo_challenge_slot(gen_random_uuid(), '76561190000009999');
  if v_res.status <> 'not_found' or v_res.used <> 0 or v_res.slot_limit <> 15 then raise exception 'CHECK_FAIL claim not_found %', v_res; end if;
  select * into v_res from public.demo_challenge_status('76561190000009999');
  if v_res.used <> 0 or v_res.slot_limit <> 15 or v_res.boss_ids <> '{}'::uuid[] then raise exception 'CHECK_FAIL status %', v_res; end if;
  select count(*) into v_cnt from public.demo_challenge_slots where steam_id = '76561190000009999';
  if v_cnt <> 0 then raise exception 'CHECK_FAIL rows were created'; end if;
  -- 4. 形の制約: SteamID は数字だけ（制約の定義を読むだけ。行は入れない）
  if not exists (select 1 from pg_constraint where conrelid = 'public.demo_challenge_slots'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%steam_id%') then
    raise exception 'CHECK_FAIL steam_id check missing';
  end if;
  -- 5. 分離レベルの安全対策（2026-10-30）が入っている（read committed 以外ではエラーで止まる）
  if (select prosrc from pg_proc where oid = 'public.claim_demo_challenge_slot(uuid,text)'::regprocedure) not like '%requires read committed isolation%'
     or current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'CHECK_FAIL isolation guard';
  end if;
  raise notice 'MIGRATION_CHECKS_OK';
end;
$$;

select 'DEMO_SLOTS_CHECKS_OK' as result;
