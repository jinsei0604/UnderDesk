extends GutTest
## 戦闘チケットで結果を送る流れ（2026-10-23）の契約テスト: RBMBattleResultReporter・RBMBattleResultOutbox・RBMChallengeEntry・
## RBMOnlineChallengeRecorder。1戦闘1枚・途中のやり直しは同じチケット・次のチケットは結果の応答で受け取る・通信が切れた結果は
## 同じ id で送り直す（サーバーは1回だけ数える）・再起動しても残る・期限切れ・複数の PC・作者本人・チケットが取れない時も
## 戦闘は止めない・旧版のサーバーにはチケットを頼まない・Steam の ticket は1本ずつ。
## 本物の Steam・Supabase には触れない（偽の Steam・偽のサーバー RBMFakeBossApiAdapter・偽の Steam Cloud・テスト用の保存先）。
## サーバー側の決まり（偽造・使い回し・期限・上限・認定）は supabase/functions/submit-battle-result の deno テストと、
## 本物の DB の確かめ（verify_hard_defeat_checks.sql）で試す。
const TEST_ROOT := "user://test_rbm_battle_results"
const TEST_DIR := TEST_ROOT + "/stages"
const ACCOUNT_A := "76561198000000001"
var _tmp_steam_appid_path := "user://test_steam_dev_appid_battle_results.local.txt"

func before_each() -> void:
	_remove_recursive(TEST_ROOT)
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	_remove_recursive(TEST_ROOT)
	DirAccess.remove_absolute(_tmp_steam_appid_path)
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

## 偽の Steam（ticket を頼まれたら次のフレームで答える）。
func _steam_auth() -> RBMSteamAuth:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_steam_appid_path)
	var file := FileAccess.open(_tmp_steam_appid_path, FileAccess.WRITE)
	file.store_string("480")
	file.close()
	var fake := RBMFakeSteamAdapter.new()
	fake.configure_available()
	fake.configure_logged_on(true, int(ACCOUNT_A), "Tester")
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(fake)
	add_child_autoqfree(auth)
	auth.initialize()
	auth.state_changed.connect(func(state):
		if state == RBMSteamAuth.AuthState.REQUESTING:
			_answer_ticket.call_deferred(auth))
	return auth

func _answer_ticket(auth: RBMSteamAuth) -> void:
	if not is_instance_valid(auth):
		return
	var fake := auth.adapter_for_testing() as RBMFakeSteamAdapter
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

func _draft(mode: String = RBMCreatorDraft.CREATOR_MODE_SIMPLE) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "結果の送信テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.set_creator_mode(mode)
	draft.add_party_character("hero")
	draft.add_skill({"name": "QA", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	return draft

## 今のサーバー（戦闘チケットあり）につながった挑戦画面。api は偽のサーバー（複数の PC で共有できる）。outbox を渡すと、
## その PC の送信待ち（挑戦トップを開く前から使う）。
func _setup(api: RBMFakeBossApiAdapter = null, cloud: RBMFakeSteamCloud = null, outbox: RBMBattleResultOutbox = null) -> Dictionary:
	var auth := _steam_auth()
	if api == null:
		api = RBMFakeBossApiAdapter.new()
		api.tickets_enabled = true
		add_child_autofree(api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(api)
	var browse_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(browse_api)
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(browse_api)
	entry.set_online_recorder_for_testing(recorder)
	if cloud == null:
		cloud = RBMFakeSteamCloud.new()
	var record := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	entry.set_defeat_record_for_testing(record)
	if outbox != null:
		entry.set_result_outbox_for_testing(outbox)
	add_child_autofree(entry)
	entry.enter_challenge()
	entry._last_browse_was_online = true
	return {"entry": entry, "api": api, "record": record, "recorder": recorder, "auth": auth, "cloud": cloud}

func _start(s: Dictionary, boss_id: String, mode: String = RBMCreatorDraft.CREATOR_MODE_SIMPLE) -> void:
	var entry: RBMChallengeEntry = s.entry
	entry._online_list_view._summaries[boss_id] = {"unique_challengers": 30, "unique_clearers": 1}
	entry._on_online_boss_selected(boss_id, _draft(mode), "結果の送信テストボス", "")
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(5)

func _win(s: Dictionary) -> void:
	var entry: RBMChallengeEntry = s.entry
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over and entry._battle_view.session.battle.winner == "ally", "sanity: won")
	await wait_process_frames(5)

func _lose(s: Dictionary) -> void:
	(s.entry as RBMChallengeEntry)._battle_view.challenge_lost.emit()
	await wait_process_frames(5)

func _restart(s: Dictionary) -> void:
	(s.entry as RBMChallengeEntry)._battle_view._do_restart()
	await wait_process_frames(5)

func _outbox(s: Dictionary) -> RBMBattleResultOutbox:
	return (s.entry as RBMChallengeEntry)._result_outbox()

func _sent_result_ids(api: RBMFakeBossApiAdapter) -> Array:
	var ids: Array = []
	for call in api.submit_calls:
		for r in call.results:
			ids.append(str(r.result_id))
	return ids

# ---------------------------------------------------------------------------

func test_the_battle_view_reports_a_restart_but_not_the_first_start() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	var restarts := [0]
	view.battle_restarted.connect(func(): restarts[0] += 1)
	view.start_battle(_draft().to_definition())
	await get_tree().process_frame
	assert_eq(restarts[0], 0)
	view._do_restart()
	view._do_restart()
	assert_eq(restarts[0], 2)

func test_each_settled_battle_is_sent_once_with_its_own_ticket_and_the_next_ticket_comes_with_the_answer() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	await _start(s, "boss-a", RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(api.record_attempt_calls.size(), 1)
	assert_true((s.entry as RBMChallengeEntry)._result_reporter.has_battle_ticket(), "the first ticket came with the attempt")
	await _win(s)
	assert_eq(api.counted_results.size(), 1)
	assert_eq(api.counted_results[0].outcome, "clear")
	assert_eq(api.submit_calls[0].next_ticket_boss_id, "boss-a", "the next battle's ticket is asked for in the same request")
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 1, "hard": 0}, "the defeat record comes from the answer")
	assert_eq(_outbox(s).entries().size(), 0, "answered: nothing pending")
	# もう一度挑戦 → 届いている次のチケットを使う（チケットだけを取りに行かない）
	await _restart(s)
	await _lose(s)
	assert_eq(api.issue_ticket_calls.size(), 0, "no extra request for 'try again'")
	assert_eq(api.counted_results.size(), 2)
	assert_eq(api.counted_results[1].outcome, "loss")
	var tickets := {}
	for t in api.server_tickets:
		if not str(api.server_tickets[t].result_id).is_empty():
			tickets[t] = true
	assert_eq(tickets.size(), 2, "one ticket per settled battle")
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 1, "hard": 0}, "a loss is not a defeat record")

func test_restarting_in_the_middle_of_a_battle_keeps_the_same_ticket() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	await _start(s, "boss-a")
	var first_ticket: String = api.server_tickets.keys()[0]
	await _restart(s)
	await _restart(s)
	assert_eq(api.issue_ticket_calls.size(), 0, "an unfinished battle has no result, so its ticket is kept")
	await _win(s)
	assert_eq(api.submit_calls[0].results[0].battle_ticket, first_ticket)
	assert_eq(api.counted_results.size(), 1)

func test_a_lost_connection_keeps_the_result_and_it_is_sent_again_with_the_same_id() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	await _start(s, "boss-a")
	api.network_down = true
	await _win(s)
	assert_eq(api.counted_results.size(), 0)
	assert_eq(_outbox(s).entries().size(), 1, "kept for later")
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "not recorded until the server answers")
	# 通信が戻ってから挑戦トップを開く → 同じ id で送り直す
	api.network_down = false
	entry._result_reporter._last_flush_msec = -1
	entry._on_battle_returned_to_list()
	entry._show_hub()
	await wait_process_frames(5)
	var ids := _sent_result_ids(api)
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], ids[1], "the same result id is sent again")
	assert_eq(api.counted_results.size(), 1)
	assert_eq(_outbox(s).entries().size(), 0)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "recorded once the server answered")

func test_a_lost_answer_is_sent_again_and_counted_only_once() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	await _start(s, "boss-a")
	api.lose_next_submit_response = true
	await _win(s)
	assert_eq(api.counted_results.size(), 1, "the server counted it, but the answer never arrived")
	assert_eq(_outbox(s).entries().size(), 1)
	entry._result_reporter._last_flush_msec = -1
	entry._on_battle_returned_to_list()
	entry._show_hub()
	await wait_process_frames(5)
	assert_eq(api.counted_results.size(), 1, "sent again: a duplicate, not counted twice")
	assert_eq(_outbox(s).entries().size(), 0)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0})
	# 何度開いても、もう送らない
	entry._result_reporter._last_flush_msec = -1
	entry._show_hub()
	await wait_process_frames(5)
	assert_eq(api.submit_calls.size(), 2)

func test_pending_results_survive_a_restart_of_the_game_and_keep_the_time_of_the_battle() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	await _start(s, "boss-a")
	api.network_down = true
	await _win(s)
	var pending: Array = _outbox(s).entries()
	assert_eq(pending.size(), 1)
	assert_true(FileAccess.file_exists(_outbox(s).path()), "kept in a file")
	var at := int(pending[0].at)
	# ゲームを終える → 次の起動（新しい挑戦画面・同じ偽のサーバー・同じ Steam Cloud）
	(s.entry as RBMChallengeEntry).queue_free()
	await get_tree().process_frame
	api.network_down = false
	var s2 := _setup(api, s.cloud)
	(s2.entry as RBMChallengeEntry)._show_hub()
	await wait_process_frames(5)
	assert_eq(api.counted_results.size(), 1)
	assert_eq(_sent_result_ids(api)[0], _sent_result_ids(api)[1], "the same id after the restart")
	assert_eq(_outbox(s2).entries().size(), 0)
	assert_eq(s2.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0})
	assert_eq(int(s2.record.data.bosses["boss-a"].at), at, "the defeat record keeps the time of the battle")

func test_an_expired_ticket_drops_the_result_and_the_win_still_decides_the_defeat_record_the_old_way() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	await _start(s, "boss-a")
	var ticket: String = api.server_tickets.keys()[0]
	api.network_down = true
	await _win(s)
	api.network_down = false
	api.expire_ticket(ticket)
	entry._result_reporter._last_flush_msec = -1
	entry._on_battle_returned_to_list()
	entry._show_hub()
	await wait_process_frames(8)
	assert_eq(api.counted_results.size(), 0, "an expired ticket counts nothing")
	assert_eq(_outbox(s).entries().size(), 0, "a definite answer: no endless resending")
	assert_eq(api.record_clear_calls.size(), 1, "the old clear record decides whether it is someone else's boss")
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "the win is not lost from the defeat record (never hard)")

func test_results_older_than_the_ticket_lifetime_are_dropped_locally() -> void:
	var box := RBMBattleResultOutbox.new(ACCOUNT_A)
	var now := int(Time.get_unix_time_from_system())
	var old := RBMBattleResultOutbox.make_entry("boss-a", "t-old", true, {}, now - RBMBattleResultOutbox.KEEP_SECONDS - 10)
	var fresh := RBMBattleResultOutbox.make_entry("boss-a", "t-new", false, {}, now - 60)
	assert_true(box.add(old))
	assert_true(box.add(fresh))
	var kept := box.entries()
	assert_eq(kept.size(), 1)
	assert_eq(kept[0].battle_ticket, "t-new")

func test_two_pcs_on_one_account_each_count_their_own_battles_and_a_copied_pending_result_counts_once() -> void:
	var api := RBMFakeBossApiAdapter.new()
	api.tickets_enabled = true
	add_child_autofree(api)
	var cloud := RBMFakeSteamCloud.new()
	var pc1 := _setup(api, cloud)
	await _start(pc1, "boss-a")
	api.network_down = true
	await _win(pc1)
	api.network_down = false
	# 別の PC（送信待ちは別の場所）
	var pc2 := _setup(api, cloud, RBMBattleResultOutbox.new(ACCOUNT_A, false))
	await _start(pc2, "boss-a")
	await _win(pc2)
	assert_eq(api.counted_results.size(), 1, "PC 2's own battle")
	# PC 1 の送信待ちが PC 2 にも写った（同期された）とする → どちらが送っても1回だけ
	var copied: Array = _outbox(pc1).entries()
	for e in copied:
		_outbox(pc2).add(e)
	(pc2.entry as RBMChallengeEntry)._result_reporter._last_flush_msec = -1
	(pc2.entry as RBMChallengeEntry)._on_battle_returned_to_list()
	(pc2.entry as RBMChallengeEntry)._show_hub()
	await wait_process_frames(5)
	(pc1.entry as RBMChallengeEntry)._result_reporter._last_flush_msec = -1
	(pc1.entry as RBMChallengeEntry)._on_battle_returned_to_list()
	(pc1.entry as RBMChallengeEntry)._show_hub()
	await wait_process_frames(5)
	assert_eq(api.counted_results.size(), 2, "two battles, two results; the copy is a duplicate")
	assert_eq(_outbox(pc1).entries().size(), 0)
	assert_eq(_outbox(pc2).entries().size(), 0)
	var reloaded := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	reloaded.load_records()
	assert_eq(reloaded.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "one boss in the defeat record across both PCs")

func test_the_authors_results_are_sent_but_never_become_a_defeat_record() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	api.configure_record_attempt_response({"ok": true, "challenge_count": 1, "by_owner": true})
	api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": true})
	await _start(s, "own-boss")
	await _win(s)
	assert_eq(api.counted_results.size(), 1, "the author's result is still sent (the server leaves it out of the counts)")
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	assert_eq((s.entry as RBMChallengeEntry)._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_OWNER)
	assert_eq(api.record_clear_calls.size(), 0)

func test_a_hard_award_in_the_answer_marks_the_defeat_record() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": true, "first_clear_rate": 0.025})
	await _start(s, "hard-boss", RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	await _win(s)
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 1, "hard": 1})
	assert_almost_eq(float(s.record.data.bosses["hard-boss"].rate), 0.025, 0.0001)

func test_when_no_ticket_can_be_had_the_battle_still_runs_and_a_win_uses_the_old_record() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	api.ticket_refusal = "rate_limited"
	await _start(s, "boss-a")
	assert_true(entry._battle_view.visible and entry._battle_view.session.start_ok(), "the battle is never blocked")
	assert_false(entry._result_reporter.has_battle_ticket())
	await _win(s)
	assert_eq(api.submit_calls.size(), 0, "nothing to send without a ticket")
	assert_eq(api.record_clear_calls.size(), 1)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0})
	# もう一度挑戦 → 1枚取りに行く（まだ上限）→ 負けは送らない
	await _restart(s)
	assert_eq(api.issue_ticket_calls.size(), 1)
	await _lose(s)
	assert_eq(api.submit_calls.size(), 0)
	# 上限が解けたら、次の戦闘から数える
	api.ticket_refusal = ""
	await _restart(s)
	assert_eq(api.issue_ticket_calls.size(), 2)
	await _lose(s)
	assert_eq(api.counted_results.size(), 1)

func test_an_old_server_without_tickets_is_never_asked_for_tickets_or_results() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	api.tickets_enabled = false
	await _start(s, "boss-a")
	await _win(s)
	await _restart(s)
	await _lose(s)
	await _restart(s)
	assert_eq([api.issue_ticket_calls.size(), api.submit_calls.size()], [0, 0])
	assert_eq(api.record_clear_calls.size(), 1, "the win uses the old clear record as before")
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0})

func test_a_restart_while_the_next_ticket_is_on_its_way_waits_for_it_and_asks_once_if_it_never_comes() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	await _start(s, "boss-a")
	api.network_down = true
	entry._battle_view.act_attack(0)
	# 結果の送信（次のチケットを頼んでいる）がまだ終わらないうちに、もう一度挑戦
	entry._battle_view._do_restart()
	assert_eq(api.issue_ticket_calls.size(), 0, "waits for the answer that may bring the next ticket")
	await wait_process_frames(8)
	assert_eq(api.issue_ticket_calls.size(), 1, "no ticket came: asks once")
	assert_false(entry._result_reporter.has_battle_ticket())
	api.network_down = false
	await _restart(s)
	assert_eq(api.issue_ticket_calls.size(), 2)
	assert_true(entry._result_reporter.has_battle_ticket())

func test_leaving_the_battle_drops_the_ticket_but_keeps_pending_results() -> void:
	var s := _setup()
	var api: RBMFakeBossApiAdapter = s.api
	var entry: RBMChallengeEntry = s.entry
	await _start(s, "boss-a")
	api.network_down = true
	await _win(s)
	entry._on_battle_returned_to_list()
	assert_eq(entry._result_reporter.boss_id(), "")
	assert_false(entry._result_reporter.has_battle_ticket())
	assert_eq(_outbox(s).entries().size(), 1)
	# 手元のボスへの挑戦はチケットも結果も使わない
	entry._result_reporter.on_battle_decided(true)
	assert_eq(_outbox(s).entries().size(), 1)

func test_the_recorder_sends_one_request_at_a_time_so_overlapping_calls_all_succeed() -> void:
	var auth := _steam_auth()
	var api := RBMFakeBossApiAdapter.new()
	api.tickets_enabled = true
	add_child_autofree(api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(api)
	var answers: Array = []
	var call_attempt := func(): answers.append(await recorder.record_challenge_attempt("boss-a"))
	var call_awards := func(): answers.append(await recorder.list_my_hard_awards())
	var call_ticket := func(): answers.append(await recorder.issue_battle_ticket("boss-a"))
	call_attempt.call()
	call_awards.call()
	call_ticket.call()
	await wait_process_frames(10)
	assert_eq(answers.size(), 3)
	for a in answers:
		assert_true(bool(a.get("ok", false)), "every overlapping call succeeds: %s" % str(a))

func test_the_outbox_keeps_one_copy_per_result_per_account_and_sets_a_broken_file_aside() -> void:
	var a := RBMBattleResultOutbox.new(ACCOUNT_A)
	var b := RBMBattleResultOutbox.new("76561198000000002")
	var e := RBMBattleResultOutbox.make_entry("boss-a", "t-1", true, {"mode": "advanced", "rate": 0.1, "attempt_by_owner": false, "published_here": false})
	assert_true(a.add(e))
	assert_true(a.add(e), "the same result twice")
	assert_eq(a.entries().size(), 1)
	assert_eq(b.entries().size(), 0, "another account's results are separate")
	var id := str(e.result_id)
	assert_eq(id.length(), 36)
	assert_eq(id.substr(14, 1), "4", "a version 4 UUID")
	assert_ne(RBMBattleResultOutbox.new_result_id(), RBMBattleResultOutbox.new_result_id())
	a.remove([id])
	assert_eq(a.entries().size(), 0)
	# 上限を超えたら古いものから捨てる
	for i in RBMBattleResultOutbox.MAX_ENTRIES + 5:
		a.add(RBMBattleResultOutbox.make_entry("boss-a", "t-%d" % i, false, {}))
	var kept := a.entries()
	assert_eq(kept.size(), RBMBattleResultOutbox.MAX_ENTRIES)
	assert_eq(kept[0].battle_ticket, "t-5")
	# 壊れたファイルは脇へ避けて、空から始める
	var f := FileAccess.open(a.path(), FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	assert_eq(a.entries().size(), 0)
	var aside := false
	for name in DirAccess.get_files_at(RBMBattleResultOutbox.outbox_dir()):
		if name.contains(".corrupt."):
			aside = true
	assert_true(aside)
	# メモリだけ（保存先を分けていないテスト）はファイルを作らない
	var memory := RBMBattleResultOutbox.new("76561198000000003", false)
	memory.add(RBMBattleResultOutbox.make_entry("boss-a", "t-m", true, {}))
	assert_eq(memory.entries().size(), 1)
	assert_false(FileAccess.file_exists(memory.path()))
