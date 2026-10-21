-- 20261022000000_add_by_owner_to_challenge_records の確かめ（2026-10-22）。空実行では
-- 「begin; <migration>; <このファイル>; rollback;」にして流す（変更は残らない）。適用の後は、このファイルだけを
-- begin; と rollback; で挟んで流しても同じことを確かめられる。確かめで作るボス・記録は、塊の最後の例外で必ず取り消す。
-- どれかが合わなければ例外（CHECK_FAIL ...）で止まる。SteamID は試験用の架空の値だけを使う。

do $$
declare
  v_boss uuid;
  v_owner text := '76561190000000101';
  v_other text := '76561190000000102';
  v_third text := '76561190000000103';
  v_row public.boss_challenge_records;
  v_flag boolean;
  v_non_owner integer;
  v_non_owner_clear integer;
begin
  -- 列・トリガー・関数の権限
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'boss_challenge_records'
                 and column_name = 'by_owner' and is_nullable = 'NO' and column_default = 'false') then
    raise exception 'CHECK_FAIL by_owner column is missing or not "not null default false"';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'boss_challenge_records_set_by_owner' and not tgisinternal) then
    raise exception 'CHECK_FAIL by_owner trigger is missing';
  end if;
  if has_function_privilege('anon', 'public.record_boss_challenge_attempt(uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.record_boss_challenge_attempt(uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.record_boss_challenge_clear(uuid, text)', 'EXECUTE') then
    raise exception 'CHECK_FAIL challenge record function privileges changed';
  end if;
  if has_table_privilege('anon', 'public.boss_challenge_records', 'SELECT,INSERT,UPDATE')
     or has_table_privilege('authenticated', 'public.boss_challenge_records', 'SELECT,INSERT,UPDATE') then
    raise exception 'CHECK_FAIL client roles can touch boss_challenge_records';
  end if;

  begin
    insert into public.bosses (owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
      values (v_owner, 'mc-by-owner-check', 1, '{}'::jsonb, repeat('b', 64), 'mc-by-owner-' || gen_random_uuid()::text, true, now())
      returning id into v_boss;

    -- 記録の2関数（Edge Function と同じ経路）: 作者本人は true、ほかの人は false
    select * into v_row from public.record_boss_challenge_attempt(v_boss, v_owner);
    if not v_row.by_owner then raise exception 'CHECK_FAIL owner attempt is not by_owner'; end if;
    select * into v_row from public.record_boss_challenge_clear(v_boss, v_owner);
    if not v_row.by_owner or v_row.clear_count <> 1 then raise exception 'CHECK_FAIL owner clear'; end if;
    select * into v_row from public.record_boss_challenge_attempt(v_boss, v_other);
    if v_row.by_owner then raise exception 'CHECK_FAIL other attempt is by_owner'; end if;
    select * into v_row from public.record_boss_challenge_attempt(v_boss, v_other);
    if v_row.challenge_count <> 2 or v_row.by_owner then raise exception 'CHECK_FAIL repeated attempt (one row, count 2)'; end if;
    select * into v_row from public.record_boss_challenge_clear(v_boss, v_third);
    if v_row.by_owner or v_row.challenge_count <> 0 or v_row.clear_count <> 1 then raise exception 'CHECK_FAIL clear without attempt'; end if;

    -- 書き換えようとしても DB が計算し直す
    update public.boss_challenge_records set by_owner = false where boss_id = v_boss and challenger_steam_id = v_owner;
    select by_owner into v_flag from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = v_owner;
    if not v_flag then raise exception 'CHECK_FAIL owner flag could be cleared'; end if;
    update public.boss_challenge_records set by_owner = true where boss_id = v_boss and challenger_steam_id = v_other;
    select by_owner into v_flag from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = v_other;
    if v_flag then raise exception 'CHECK_FAIL other flag could be set'; end if;

    -- 集計（Edge Functions と同じ by_owner = false の行だけ）: 挑戦者2人（other・third）、クリア1人（third）
    select count(*), count(*) filter (where clear_count > 0) into v_non_owner, v_non_owner_clear
      from public.boss_challenge_records where boss_id = v_boss and not by_owner;
    if v_non_owner <> 2 or v_non_owner_clear <> 1 then
      raise exception 'CHECK_FAIL aggregate without owner: % challengers, % clearers', v_non_owner, v_non_owner_clear;
    end if;
    -- 同じ人は1行（重複しない決まり）
    if (select count(*) from public.boss_challenge_records where boss_id = v_boss) <> 3 then
      raise exception 'CHECK_FAIL one row per challenger';
    end if;
    raise exception 'MC_BY_OWNER_OK';
  exception
    when others then
      if sqlerrm <> 'MC_BY_OWNER_OK' then
        raise exception 'CHECK_FAIL by_owner check: % (%)', sqlerrm, sqlstate;
      end if;
  end;
end $$;

select (select count(*) from public.bosses) as bosses,
       (select count(*) from public.boss_challenge_records) as boss_challenge_records,
       (select count(*) from public.boss_challenge_records where by_owner) as by_owner_rows;
