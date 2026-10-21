-- 20261023000000_hard_defeat_award の確かめ（2026-10-23）。空実行では「begin; <migration>; <このファイル>; rollback;」にして流す
-- （変更は残らない）。適用の後は、このファイルを begin; と rollback; で挟んで流しても同じことを確かめられる。
-- 試験のボス・記録・チケットは塊の最後の例外で必ず取り消す。SteamID は試験用の架空の値だけ。合わなければ CHECK_FAIL で止まる。

do $$
declare
  v_owner text := '76561190000003000';
  v_boss uuid;
  v_other_boss uuid;
  v_row public.boss_challenge_records;
  v_res record;
  v_tk uuid;
  v_tk2 uuid;
  v_rid uuid;
  i integer;
begin
  -- 1. 条件の式（数だけ）: 挑戦結果 49/50/51・挑戦者 9/10/11・クリア率 4%/5%/6%・挑戦0回
  if public.boss_hard_defeat_qualifies(49, 20, 1) then raise exception 'CHECK_FAIL 49 results qualified'; end if;
  if not public.boss_hard_defeat_qualifies(50, 20, 1) then raise exception 'CHECK_FAIL 50 results did not qualify'; end if;
  if not public.boss_hard_defeat_qualifies(51, 20, 1) then raise exception 'CHECK_FAIL 51 results did not qualify'; end if;
  if public.boss_hard_defeat_qualifies(60, 9, 0) then raise exception 'CHECK_FAIL 9 challengers qualified'; end if;
  if not public.boss_hard_defeat_qualifies(60, 10, 0) then raise exception 'CHECK_FAIL 10 challengers did not qualify'; end if;
  if not public.boss_hard_defeat_qualifies(60, 11, 0) then raise exception 'CHECK_FAIL 11 challengers did not qualify'; end if;
  if not public.boss_hard_defeat_qualifies(100, 25, 1) then raise exception 'CHECK_FAIL 4%% did not qualify'; end if;
  if not public.boss_hard_defeat_qualifies(100, 20, 1) then raise exception 'CHECK_FAIL 5%% did not qualify'; end if;
  if public.boss_hard_defeat_qualifies(100, 50, 3) then raise exception 'CHECK_FAIL 6%% qualified'; end if;
  if public.boss_hard_defeat_qualifies(0, 0, 0) then raise exception 'CHECK_FAIL 0 results qualified'; end if;

  -- 権限: チケットの発行・結果の受け付けは service_role だけ。ほかの新しい関数・チケットの表は誰にも出さない
  if has_function_privilege('anon', 'public.issue_boss_battle_ticket(uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.submit_boss_battle_result(uuid, uuid, text, uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.issue_boss_battle_ticket(uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.submit_boss_battle_result(uuid, uuid, text, uuid, text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.record_boss_challenge_clear(uuid, text)', 'EXECUTE')
     or has_function_privilege('public', 'public.award_hard_defeats(uuid)', 'EXECUTE')
     or has_function_privilege('public', 'public.boss_hard_defeat_stats(uuid, text)', 'EXECUTE')
     or has_table_privilege('anon', 'public.boss_battle_tickets', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role', 'public.boss_battle_tickets', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'CHECK_FAIL privileges';
  end if;

  begin
    insert into public.bosses (owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
      values (v_owner, 'mc-hard-defeat-check', 1, '{"draft_fields": {"creator_mode": "advanced"}}'::jsonb, repeat('d', 64), 'mc-hard-' || gen_random_uuid()::text, true, now())
      returning id into v_boss;
    insert into public.bosses (owner_steam_id, boss_name, schema_version, payload, battle_hash, idempotency_key, is_published, published_at)
      values (v_owner, 'mc-hard-defeat-other', 1, '{}'::jsonb, repeat('e', 64), 'mc-hard-o-' || gen_random_uuid()::text, false, now())
      returning id into v_other_boss;

    -- 2. チケット: 発行（DB のモードを残す）・非公開のボスには出さない
    select * into v_res from public.issue_boss_battle_ticket(v_boss, '76561190000003001');
    if v_res.status <> 'issued' or (select creator_mode from public.boss_battle_tickets where id = v_res.ticket_id) <> 'advanced' then
      raise exception 'CHECK_FAIL ticket issue';
    end if;
    v_tk := v_res.ticket_id;
    if (select status from public.issue_boss_battle_ticket(v_other_boss, '76561190000003001')) <> 'not_found' then
      raise exception 'CHECK_FAIL ticket for an unpublished boss';
    end if;
    -- 偽造・本人違い・ボス違い・勝敗の値の誤り
    if (select status from public.submit_boss_battle_result(gen_random_uuid(), v_boss, '76561190000003001', gen_random_uuid(), 'clear')) <> 'invalid'
       or (select status from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003999', gen_random_uuid(), 'clear')) <> 'invalid'
       or (select status from public.submit_boss_battle_result(v_tk, v_other_boss, '76561190000003001', gen_random_uuid(), 'clear')) <> 'invalid'
       or (select status from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003001', gen_random_uuid(), 'win')) <> 'invalid' then
      raise exception 'CHECK_FAIL forged or mismatched tickets';
    end if;
    -- 挑戦を始めただけ・旧版のクリアの記録は、挑戦結果・クリア率に入らない
    perform public.record_boss_challenge_attempt(v_boss, '76561190000003001');
    perform public.record_boss_challenge_clear(v_boss, '76561190000003002');
    if (select results from public.boss_hard_defeat_stats(v_boss)) <> 0 or (select challengers from public.boss_hard_defeat_stats(v_boss)) <> 0 then
      raise exception 'CHECK_FAIL an attempt or a legacy clear was counted as a result';
    end if;

    -- 3. 最初の1人（P0）が、ほかに挑戦者のいない時にクリア → 初回の数は 0人・0人（判定保留）
    v_rid := gen_random_uuid();
    select * into v_res from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003001', v_rid, 'clear');
    if v_res.status <> 'counted' or v_res.first_clear_challengers <> 0 or v_res.hard_awarded then raise exception 'CHECK_FAIL pioneer clear'; end if;
    -- 同じ結果の送り直しは数えない（duplicate）。同じチケットで別の結果・別の勝敗は使い回しとして拒む
    if (select status from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003001', v_rid, 'clear')) <> 'duplicate' then
      raise exception 'CHECK_FAIL resend was not a duplicate';
    end if;
    if (select status from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003001', gen_random_uuid(), 'clear')) <> 'used'
       or (select status from public.submit_boss_battle_result(v_tk, v_boss, '76561190000003001', v_rid, 'loss')) <> 'used' then
      raise exception 'CHECK_FAIL ticket reuse';
    end if;
    -- 同じ結果の id を別のチケットで送っても使い回し
    select ticket_id into v_tk2 from public.issue_boss_battle_ticket(v_boss, '76561190000003001');
    if (select status from public.submit_boss_battle_result(v_tk2, v_boss, '76561190000003001', v_rid, 'clear')) <> 'used' then
      raise exception 'CHECK_FAIL result id reuse';
    end if;
    select * into v_row from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001';
    if v_row.result_count <> 1 or v_row.result_clear_count <> 1 then raise exception 'CHECK_FAIL counted more than once'; end if;
    -- 期限切れのチケット
    update public.boss_battle_tickets set expires_at = now() - interval '1 minute' where id = v_tk2;
    if (select status from public.submit_boss_battle_result(v_tk2, v_boss, '76561190000003001', gen_random_uuid(), 'loss')) <> 'expired' then
      raise exception 'CHECK_FAIL expired ticket';
    end if;

    -- 4. 19人が1回ずつ負け → 挑戦者20・クリア1（5%）・挑戦結果20。作者の結果（40回）は数えない
    for i in 1..19 loop
      perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, (76561190000003100 + i)::text)),
        v_boss, (76561190000003100 + i)::text, gen_random_uuid(), 'loss');
    end loop;
    for i in 1..40 loop
      perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, v_owner)), v_boss, v_owner, gen_random_uuid(),
        case when i = 1 then 'clear' else 'loss' end);
    end loop;
    if (select results from public.boss_hard_defeat_stats(v_boss)) <> 20 then raise exception 'CHECK_FAIL the author was counted'; end if;
    -- 挑戦結果を 49 まで（1人が29回負ける）→ まだ保留
    for i in 1..29 loop
      perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003101')),
        v_boss, '76561190000003101', gen_random_uuid(), 'loss');
    end loop;
    if (select results from public.boss_hard_defeat_stats(v_boss)) <> 49 then raise exception 'CHECK_FAIL 49 setup'; end if;
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001') is not null then
      raise exception 'CHECK_FAIL awarded at 49 results';
    end if;
    -- 50回目 → 条件を満たし、P0 にさかのぼって認定。作者は認定しない
    perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003101')),
      v_boss, '76561190000003101', gen_random_uuid(), 'loss');
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001') is null then
      raise exception 'CHECK_FAIL not awarded retroactively at 50 results';
    end if;
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = v_owner) is not null then
      raise exception 'CHECK_FAIL the author was awarded';
    end if;

    -- 5. P20 が初めてクリア（その時 20人中1人 = 5% → 対象）。クリア後は 2/21 で保留。P0 の認定は残る
    select * into v_res from public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003200')),
      v_boss, '76561190000003200', gen_random_uuid(), 'clear');
    if v_res.first_clear_challengers <> 20 or v_res.first_clear_clearers <> 1 or v_res.hard_awarded then
      raise exception 'CHECK_FAIL P20 snapshot or premature award';
    end if;
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001') is null then
      raise exception 'CHECK_FAIL an award was revoked when the rate went up';
    end if;
    for i in 1..19 loop
      perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, (76561190000003300 + i)::text)),
        v_boss, (76561190000003300 + i)::text, gen_random_uuid(), 'loss');
    end loop;   -- 2/40 = 5% → P20 を認定
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003200') is null then
      raise exception 'CHECK_FAIL P20 was not awarded when the boss qualified again';
    end if;

    -- 6. 初めてクリアした時に 5% を超えていた人は、後で条件を満たしても認定しない
    perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003400')),
      v_boss, '76561190000003400', gen_random_uuid(), 'clear');   -- その時 2/40 = 5% → 対象（後で 3/41 で保留）
    select * into v_res from public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003401')),
      v_boss, '76561190000003401', gen_random_uuid(), 'clear');   -- その時 3/41 = 7.3% → 対象外
    if v_res.first_clear_challengers <> 41 or v_res.first_clear_clearers <> 3 then raise exception 'CHECK_FAIL over-5%% snapshot'; end if;
    for i in 1..40 loop
      perform public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, (76561190000003500 + i)::text)),
        v_boss, (76561190000003500 + i)::text, gen_random_uuid(), 'loss');
    end loop;   -- 4/82 = 4.9%
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003400') is null then
      raise exception 'CHECK_FAIL the 5%% first clear was not awarded';
    end if;
    if (select hard_awarded_at from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003401') is not null then
      raise exception 'CHECK_FAIL a first clear over 5%% was awarded';
    end if;

    -- 7. 再クリア: 回数は増えるが、初回の数・認定は変わらない
    select * into v_res from public.submit_boss_battle_result((select ticket_id from public.issue_boss_battle_ticket(v_boss, '76561190000003001')),
      v_boss, '76561190000003001', gen_random_uuid(), 'clear');
    select * into v_row from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001';
    if v_row.result_clear_count <> 2 or v_row.first_clear_challengers <> 0 or v_row.hard_awarded_at is null or not v_res.hard_awarded then
      raise exception 'CHECK_FAIL re-clear changed the first clear or the award';
    end if;

    -- 8. 書き換えの防止: 認定・初回の数を消す・変えようとしても残る
    update public.boss_challenge_records set hard_awarded_at = null, first_clear_challengers = 99, first_clear_clearers = 0
      where boss_id = v_boss and challenger_steam_id = '76561190000003001';
    select * into v_row from public.boss_challenge_records where boss_id = v_boss and challenger_steam_id = '76561190000003001';
    if v_row.hard_awarded_at is null or v_row.first_clear_challengers <> 0 then raise exception 'CHECK_FAIL permanent fields changed'; end if;

    -- 9. 連続した不自然な発行の上限（1人×1ボスで1時間に60枚）。正当な再挑戦の範囲は通る
    for i in 1..60 loop
      if (select status from public.issue_boss_battle_ticket(v_boss, '76561190000003600')) <> 'issued' then
        raise exception 'CHECK_FAIL ticket % of 60 was refused', i;
      end if;
    end loop;
    if (select status from public.issue_boss_battle_ticket(v_boss, '76561190000003600')) <> 'rate_limited' then
      raise exception 'CHECK_FAIL the 61st ticket in an hour was issued';
    end if;
    -- 1人で24時間に600枚まで（1時間より前の599枚 + 今の1枚 = 600 → 次は daily_limit。25時間前の分は数えない）
    insert into public.boss_battle_tickets (boss_id, challenger_steam_id, creator_mode, boss_revision, issued_at, expires_at)
      select v_boss, '76561190000003800', 'advanced', 1, now() - interval '2 hours', now() + interval '29 days' from generate_series(1, 599);
    insert into public.boss_battle_tickets (boss_id, challenger_steam_id, creator_mode, boss_revision, issued_at, expires_at)
      select v_boss, '76561190000003800', 'advanced', 1, now() - interval '25 hours', now() + interval '29 days' from generate_series(1, 50);
    if (select status from public.issue_boss_battle_ticket(v_boss, '76561190000003800')) <> 'issued'
       or (select status from public.issue_boss_battle_ticket(v_boss, '76561190000003800')) <> 'daily_limit' then
      raise exception 'CHECK_FAIL the daily limit';
    end if;
    -- 期限から1日過ぎたチケットは、ほかの人の発行の時に少しずつ（1回100枚まで）消える。期限内のものは消えない
    insert into public.boss_battle_tickets (boss_id, challenger_steam_id, creator_mode, boss_revision, issued_at, expires_at)
      select v_boss, '76561190000003900', 'advanced', 1, now() - interval '40 days', now() - interval '10 days' from generate_series(1, 150);
    perform public.issue_boss_battle_ticket(v_boss, '76561190000003901');
    if (select count(*) from public.boss_battle_tickets where challenger_steam_id = '76561190000003900') <> 50
       or (select count(*) from public.boss_battle_tickets where challenger_steam_id = '76561190000003800') <> 650 then
      raise exception 'CHECK_FAIL expired ticket cleanup';
    end if;
    if (select expires_at from public.boss_battle_tickets where challenger_steam_id = '76561190000003901') < now() + interval '29 days' then
      raise exception 'CHECK_FAIL ticket validity is shorter than 30 days';
    end if;

    -- 10. Edge Functions と同じ service_role の権限で、発行・受け付け・送り直しが通る（チケットの表は直接読めない）
    execute 'set local role service_role';
    select * into v_res from public.issue_boss_battle_ticket(v_boss, '76561190000003700');
    if v_res.status <> 'issued' then raise exception 'CHECK_FAIL issue as service_role'; end if;
    v_rid := gen_random_uuid();
    if (select status from public.submit_boss_battle_result(v_res.ticket_id, v_boss, '76561190000003700', v_rid, 'loss')) <> 'counted'
       or (select status from public.submit_boss_battle_result(v_res.ticket_id, v_boss, '76561190000003700', v_rid, 'loss')) <> 'duplicate' then
      raise exception 'CHECK_FAIL submit as service_role';
    end if;
    begin
      perform 1 from public.boss_battle_tickets limit 1;
      raise exception 'CHECK_FAIL service_role read the ticket table';
    exception when insufficient_privilege then
      null;
    end;
    execute 'reset role';

    -- 11. 挑戦0回のボスは条件を満たさない
    if public.award_hard_defeats(v_other_boss) <> 0 or (select results from public.boss_hard_defeat_stats(v_other_boss)) <> 0 then
      raise exception 'CHECK_FAIL an empty boss';
    end if;
    raise exception 'MC_HARD_DEFEAT_OK';
  exception
    when others then
      if sqlerrm <> 'MC_HARD_DEFEAT_OK' then
        raise exception 'CHECK_FAIL hard defeat check: % (%)', sqlerrm, sqlstate;
      end if;
  end;
end $$;

select (select count(*) from public.bosses) as bosses, (select count(*) from public.boss_challenge_records) as boss_challenge_records,
       (select count(*) from public.boss_battle_tickets) as boss_battle_tickets;
