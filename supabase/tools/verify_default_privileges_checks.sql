-- migration 20261021100000（トリガー関数の search_path）・20261021100100／100200（既定の権限）の確かめ（2026-10-21）。
-- 空実行では「begin; <3つの migration>; <このファイル>; rollback;」にして流す（変更は残らない）。適用の後は、このファイルだけを流しても同じことを確かめられる。
-- 確かめで作る行・表・関数は、塊の最後の例外で必ず取り消す（既存のボス・挑戦の記録には触れない）。
-- どれかが合わなければ例外（CHECK_FAIL ...）で止まる。

do $$
declare
  v_boss uuid;
  v_ts timestamptz;
begin
  -- A: 2つのトリガー関数の search_path が空に固定されている
  if not exists (select 1 from pg_proc p, unnest(p.proconfig) c
                 where p.oid = 'public.bosses_set_updated_at()'::regprocedure and c in ('search_path=""', 'search_path=')) then
    raise exception 'CHECK_FAIL bosses_set_updated_at has no fixed search_path';
  end if;
  if not exists (select 1 from pg_proc p, unnest(p.proconfig) c
                 where p.oid = 'public.boss_challenge_records_set_updated_at()'::regprocedure and c in ('search_path=""', 'search_path=')) then
    raise exception 'CHECK_FAIL boss_challenge_records_set_updated_at has no fixed search_path';
  end if;

  -- A: トリガーが今までどおり動く（更新すると updated_at が now() に置き換わる）
  begin
    set local role service_role;
    insert into public.bosses (owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
      values ('76561190000000999', 'mc-dry-run', 1, '{}'::jsonb, repeat('a', 64), 'mc-dry-run-' || gen_random_uuid()::text, true, now())
      returning id into v_boss;
    update public.bosses set updated_at = '2000-01-01T00:00:00Z' where id = v_boss returning updated_at into v_ts;
    if v_ts is distinct from now() then
      raise exception 'CHECK_FAIL bosses trigger did not set updated_at (%)', v_ts;
    end if;
    perform public.record_boss_challenge_attempt(v_boss, '76561190000000998');
    perform public.record_boss_challenge_clear(v_boss, '76561190000000998');
    set local role postgres;
    update public.boss_challenge_records set updated_at = '2000-01-01T00:00:00Z'
      where boss_id = v_boss returning updated_at into v_ts;
    if v_ts is distinct from now() then
      raise exception 'CHECK_FAIL boss_challenge_records trigger did not set updated_at (%)', v_ts;
    end if;
    raise exception 'MC_TRIGGER_OK';
  exception
    when others then
      if sqlerrm <> 'MC_TRIGGER_OK' then
        raise exception 'CHECK_FAIL trigger check: % (%)', sqlerrm, sqlstate;
      end if;
  end;

  -- B: postgres が public に新しく作る表・順序・関数に、anon・authenticated・PUBLIC の権限が付かない
  begin
    create table public.mc_default_acl_probe (id integer);
    create sequence public.mc_default_acl_probe_seq;
    create function public.mc_default_acl_probe_fn() returns integer language sql as 'select 1';
    if has_table_privilege('anon', 'public.mc_default_acl_probe', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
       or has_table_privilege('authenticated', 'public.mc_default_acl_probe', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') then
      raise exception 'CHECK_FAIL a new table gets privileges for anon/authenticated';
    end if;
    if has_sequence_privilege('anon', 'public.mc_default_acl_probe_seq', 'USAGE,SELECT,UPDATE')
       or has_sequence_privilege('authenticated', 'public.mc_default_acl_probe_seq', 'USAGE,SELECT,UPDATE') then
      raise exception 'CHECK_FAIL a new sequence gets privileges for anon/authenticated';
    end if;
    if has_function_privilege('anon', 'public.mc_default_acl_probe_fn()', 'EXECUTE')
       or has_function_privilege('authenticated', 'public.mc_default_acl_probe_fn()', 'EXECUTE')
       or has_function_privilege('public', 'public.mc_default_acl_probe_fn()', 'EXECUTE') then
      raise exception 'CHECK_FAIL a new function is executable by anon/authenticated/PUBLIC';
    end if;
    -- service_role の表の既定（TRUNCATE・REFERENCES・TRIGGER・MAINTAIN）は変えていない
    if not has_table_privilege('service_role', 'public.mc_default_acl_probe', 'TRUNCATE') then
      raise exception 'CHECK_FAIL service_role table defaults changed unexpectedly';
    end if;
    raise exception 'MC_PROBE_OK';
  exception
    when others then
      if sqlerrm <> 'MC_PROBE_OK' then
        raise exception 'CHECK_FAIL default privilege probe: % (%)', sqlerrm, sqlstate;
      end if;
  end;
end $$;

select p.proname as function, p.proconfig as config, p.prosecdef as security_definer
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' order by 1;
