extends GutTest
## 挑戦トップの「あなたの討伐記録」（RBMDefeatRecord、2026-10-16）の契約テスト。
## 初回クリア・再クリア・難関の判定（5%以下・初回で固定・不明は数えない）・再起動・アカウントの切り替え・
## Steam Cloud との統合と競合・壊れた記録・実際の挑戦の流れ（オンラインのボスだけ数える）・オンラインの記録への影響。
## 本物の Steam には触れない（偽の Steam Cloud・偽の Steam・偽の記録の API）。
const TEST_ROOT := "user://test_rbm_defeat_record"
const TEST_DIR := TEST_ROOT + "/stages"
const ACCOUNT_A := "76561198000000001"
const ACCOUNT_B := "76561198000000002"

func before_each() -> void:
	_remove_recursive(TEST_ROOT)
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	_remove_recursive(TEST_ROOT)
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func test_first_clears_count_once_per_boss_in_the_mode_of_the_first_clear() -> void:
	var r := RBMDefeatRecord.new(ACCOUNT_A)
	assert_eq(r.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	assert_true(r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.40, 100))
	assert_true(r.record_clear("boss-2", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.30, 110))
	assert_false(r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.40, 120), "the same boss again does not add")
	# 後で同じボスが HARDCORE に更新されて、また勝っても、最初にクリアした難易度のまま
	assert_false(r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.01, 130))
	assert_eq(r.counts(), {"simple": 1, "hardcore": 1, "hard": 0})

## 2026-10-23: 難関は、サーバーの認定（作者以外の挑戦結果50回以上・挑戦者10人以上・クリア率5%以下のボスで、初めてクリアした時の
## ほかの人のクリア率が5%以下）だけでつく。手元ではクリア率から決めない（0%・5% でも認定が無ければ難関ではない）。
func test_hard_comes_only_from_the_server_award_and_a_low_rate_alone_never_counts() -> void:
	var r := RBMDefeatRecord.new(ACCOUNT_A)
	r.record_clear("rate-0-held", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.0)
	r.record_clear("rate-5-held", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.05)
	r.record_clear("rate-4-awarded", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.04, -1, true)
	r.record_clear("unknown-awarded", RBMCreatorDraft.CREATOR_MODE_ADVANCED, -1.0, -1, true)
	assert_eq(r.counts(), {"simple": 2, "hardcore": 2, "hard": 2}, "only the bosses the server awarded are hard")
	# 再クリアは数えない。サーバーがその時に認定を返せば、さかのぼって難関になる
	assert_false(r.record_clear("rate-5-held", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.05, -1, true))
	assert_eq(r.counts(), {"simple": 2, "hardcore": 2, "hard": 3})

func test_the_official_rate_is_the_online_list_rate_and_unknown_is_not_guessed() -> void:
	assert_almost_eq(RBMDefeatRecord.official_rate({"unique_challengers": 40, "unique_clearers": 1}), 0.025, 0.0001)
	assert_eq(RBMDefeatRecord.official_rate({"unique_challengers": 0, "unique_clearers": 0}), -1.0, "no challengers: unknown")
	assert_eq(RBMDefeatRecord.official_rate({"unique_challengers": 10}), -1.0, "missing clearers: unknown")
	assert_eq(RBMDefeatRecord.official_rate({}), -1.0, "an older server without counts: unknown")

func test_records_survive_a_restart_and_are_separate_per_account() -> void:
	var a := RBMDefeatRecord.new(ACCOUNT_A)
	a.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.02, -1, true)
	a.record_clear("boss-2", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.5)
	# 再起動: 新しい記録係が同じアカウントのファイルを読む
	var a2 := RBMDefeatRecord.new(ACCOUNT_A)
	a2.load_records()
	assert_eq(a2.counts(), {"simple": 1, "hardcore": 1, "hard": 1})
	# アカウントの切り替え: 別のアカウントは自分の記録だけ
	var b := RBMDefeatRecord.new(ACCOUNT_B)
	b.load_records()
	assert_eq(b.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	b.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.9)
	assert_ne(a2.local_path(), b.local_path())
	a2.load_records()
	assert_eq(a2.counts(), {"simple": 1, "hardcore": 1, "hard": 1}, "B's clear does not change A")
	assert_eq(RBMDefeatRecord.sanitize_account(""), RBMDefeatRecord.LOCAL_ACCOUNT)
	assert_eq(RBMDefeatRecord.sanitize_account("../x"), RBMDefeatRecord.LOCAL_ACCOUNT, "no path-like account names")

func test_steam_cloud_merges_two_pcs_and_the_earliest_first_clear_wins() -> void:
	var cloud := RBMFakeSteamCloud.new()
	# PC1
	var pc1 := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	pc1.record_clear("only-pc1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5, 100)
	assert_eq(pc1.cloud_state, "synced")
	# PC2（手元の保存先が別。同じアカウントの Steam Cloud）
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_ROOT + "/pc2/stages")
	var pc2 := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	pc2.load_records()
	assert_eq(pc2.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "PC2 sees PC1's record through Steam Cloud")
	pc2.record_clear("only-pc2", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.03, 200, true)
	# 同じボスを、Steam Cloud が使えない間に両方の PC で初めてクリアした（競合）
	cloud.available = false
	pc2.record_clear("both", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.02, 300)
	assert_eq(pc2.cloud_state, "unavailable")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)
	pc1.record_clear("both", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.6, 250)
	cloud.available = true
	pc1.load_records()   # PC1 の "both"(250) と、Steam Cloud にはまだ無い
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_ROOT + "/pc2/stages")
	pc2.load_records()   # PC2 の "both"(300) は、Steam Cloud の PC1 の "both"(250) に負ける
	assert_eq(pc2.counts(), {"simple": 2, "hardcore": 1, "hard": 1}, "union of both PCs; 'both' keeps the earliest first clear (SIMPLE, 60%)")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)
	pc1.load_records()
	assert_eq(pc1.counts(), pc2.counts(), "both PCs converge to the same record")

func test_without_steam_cloud_records_stay_on_this_pc_and_a_failed_upload_keeps_the_local_record() -> void:
	var cloud := RBMFakeSteamCloud.new()
	cloud.available = false
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5)
	assert_eq(r.cloud_state, "unavailable")
	assert_true(FileAccess.file_exists(r.local_path()))
	cloud.available = true
	cloud.fail_writes = true
	r.record_clear("boss-2", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5)
	assert_eq(r.cloud_state, "write_failed")
	var again := RBMDefeatRecord.new(ACCOUNT_A)
	again.load_records()
	assert_eq(again.counts().simple, 2, "the local record is kept even when the upload fails")

func test_a_corrupted_local_record_is_set_aside_without_crashing() -> void:
	var r := RBMDefeatRecord.new(ACCOUNT_A)
	DirAccess.make_dir_recursive_absolute(RBMDefeatRecord.records_dir())
	var f := FileAccess.open(r.local_path(), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	r.load_records()
	assert_eq(r.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	var moved := false
	for name in DirAccess.get_files_at(RBMDefeatRecord.records_dir()):
		if name.contains(".corrupt."):
			moved = true
	assert_true(moved, "the broken file is kept aside, not overwritten")
	assert_true(r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5))

# ---------------------------------------------------------------------------
# 実際の挑戦の流れ（RBMChallengeEntry）

var _tmp_steam_appid_path := "user://test_steam_dev_appid_defeat_record.local.txt"

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
	# 2026-10-23: Steam の ticket を頼まれたら、次のフレームで偽の Steam が答える（結果の送信・チケットの発行など、通信の数が
	# 流れで変わるため。手で答える _ticket() を重ねても、待っていない時の答えは無視される）
	auth.state_changed.connect(func(state):
		if state == RBMSteamAuth.AuthState.REQUESTING:
			_ticket.call_deferred(auth))
	return auth

func _ticket(auth: RBMSteamAuth) -> void:
	var fake := auth.adapter_for_testing() as RBMFakeSteamAdapter
	fake.fire_ticket_response(fake.last_issued_handle(), RBMFakeSteamAdapter.RESULT_OK, 3, PackedByteArray([1, 2, 3]))

func _draft(mode: String) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "討伐記録テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.set_creator_mode(mode)
	draft.add_party_character("hero")
	draft.add_skill({"name": "QA", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	return draft

func test_winning_online_challenges_updates_the_hub_and_local_bosses_and_other_modes_do_not_count() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	var auth := _steam_auth()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)
	var browse_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(browse_api)
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(browse_api)
	entry.set_online_recorder_for_testing(recorder)
	var cloud := RBMFakeSteamCloud.new()
	var record := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	entry.set_defeat_record_for_testing(record)
	add_child_autofree(entry)
	entry.enter_challenge()
	assert_eq(entry._hub_view.defeat_counts_shown(), {"simple": 0, "hardcore": 0, "hard": 0})

	# オンラインのボス（一覧のクリア率 1/40 = 2.5%。サーバーが難関ボス討伐に認定済みと答える）に勝つ → HARDCORE 1・難関 1
	# 2026-10-23: 今のサーバー（戦闘チケットあり）。勝ちは戦闘チケットで結果として送り、応答の認定で難関がつく
	recorder_api.tickets_enabled = true
	recorder_api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": true, "first_clear_rate": 0.025})
	entry._last_browse_was_online = true
	entry._online_list_view._summaries["boss-hard"] = {"unique_challengers": 40, "unique_clearers": 1}
	entry._on_online_boss_selected("boss-hard", _draft(RBMCreatorDraft.CREATOR_MODE_ADVANCED), "討伐記録テストボス", "")
	_ticket.call_deferred(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over and entry._battle_view.session.battle.winner == "ally", "sanity: won")
	_ticket.call_deferred(auth)
	await wait_process_frames(3)
	assert_eq(record.counts(), {"simple": 0, "hardcore": 1, "hard": 1})
	assert_eq(recorder_api.counted_results.size(), 1, "the win is sent once as a battle result with the battle ticket")
	assert_eq(recorder_api.counted_results[0].outcome, "clear")
	assert_eq(recorder_api.record_clear_calls.size(), 0, "the old clear record is only for wins without a ticket")

	# もう一度挑戦して勝っても増えない
	entry._battle_view._do_restart()
	await wait_process_frames(2)
	entry._battle_view.act_attack(0)
	_ticket.call_deferred(auth)
	await wait_process_frames(3)
	assert_eq(record.counts(), {"simple": 0, "hardcore": 1, "hard": 1}, "a re-clear does not add")

	# クリア率の分からないオンラインのボス（SIMPLE、サーバーの認定なし）→ SIMPLE 1、難関は増えない
	recorder_api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": false, "first_clear_rate": null})
	entry._on_online_boss_selected("boss-unknown-rate", _draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE), "討伐記録テストボス", "")
	_ticket.call_deferred(auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	entry._battle_view.act_attack(0)
	_ticket.call_deferred(auth)
	await wait_process_frames(3)
	assert_eq(record.counts(), {"simple": 1, "hardcore": 1, "hard": 1})

	# 手元に保存したボス（ローカルの一覧から）は数えない
	entry._last_browse_was_online = false
	var saved := RBMLocalStageRepository.save_new(_draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE))
	entry._confirm_view.open(str(saved.stage_id), _draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE))
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(2)
	entry._battle_view.act_attack(0)
	await wait_process_frames(2)
	assert_eq(record.counts(), {"simple": 1, "hardcore": 1, "hard": 1}, "a local boss does not count")

	# 挑戦トップに戻ると、今のアカウントの数が出る（Steam Cloud にも同じ記録がある）
	entry._show_hub()
	assert_eq(entry._hub_view.defeat_counts_shown(), {"simple": 1, "hardcore": 1, "hard": 1})
	assert_true(cloud.files.has(RBMDefeatRecord.CLOUD_FILE))
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	await get_tree().process_frame

func test_the_hub_shows_three_cards_with_the_hard_card_in_gold() -> void:
	var hub := RBMChallengeHubView.new()
	add_child_autofree(hub)
	for n in ["DefeatRecordTitle", "DefeatRecordSimple", "DefeatRecordHardcore", "DefeatRecordHard"]:
		assert_not_null(hub.find_child(n, true, false), n)
	hub.set_defeat_counts({"simple": 12, "hardcore": 3, "hard": 1})
	assert_eq(hub.defeat_counts_shown(), {"simple": 12, "hardcore": 3, "hard": 1})
	var hard_value := hub.find_child("DefeatRecordHard", true, false).find_child("ValueLabel", true, false) as Label
	assert_eq(hard_value.get_theme_color("font_color"), RBMChallengeListStyle.GOLD)
	# 右下の空いている所に収まり、ほかのボタンと重ならない
	for n in ["DefeatRecordSimple", "DefeatRecordHardcore", "DefeatRecordHard"]:
		var r := (hub.find_child(n, true, false) as Control).get_rect()
		assert_lte(r.end.y, 700.0, n + " fits on the screen")
		for b in ["SearchBossButton", "RandomChallengeButton"]:
			assert_false(r.intersects((hub.find_child(b, true, false) as Control).get_rect()), n + " does not overlap " + b)

# ---------------------------------------------------------------------------
# 2026-10-22: 自分が作ったボスは討伐記録に数えない。サーバー（挑戦・クリアの記録の応答の by_owner）を正とし、
# この PC で公開したボス（保存したボスの online_boss_id）も作者とみなす。分からない・食い違う時は数えない。

func test_the_ownership_decision_counts_only_bosses_confirmed_to_be_someone_elses() -> void:
	assert_eq(RBMChallengeEntry.defeat_ownership([false, false], false), RBMChallengeEntry.DEFEAT_NOT_OWNER)
	assert_eq(RBMChallengeEntry.defeat_ownership([null, false], false), RBMChallengeEntry.DEFEAT_NOT_OWNER, "the clear answer alone is enough")
	assert_eq(RBMChallengeEntry.defeat_ownership([false, null], false), RBMChallengeEntry.DEFEAT_NOT_OWNER, "the attempt answer alone is enough")
	assert_eq(RBMChallengeEntry.defeat_ownership([true, true], false), RBMChallengeEntry.DEFEAT_OWNER)
	assert_eq(RBMChallengeEntry.defeat_ownership([true, null], false), RBMChallengeEntry.DEFEAT_OWNER)
	assert_eq(RBMChallengeEntry.defeat_ownership([null, null], true), RBMChallengeEntry.DEFEAT_OWNER, "published from this PC")
	assert_eq(RBMChallengeEntry.defeat_ownership([null, null], false), RBMChallengeEntry.DEFEAT_UNKNOWN)
	assert_eq(RBMChallengeEntry.defeat_ownership([false, true], false), RBMChallengeEntry.DEFEAT_CONFLICT)
	assert_eq(RBMChallengeEntry.defeat_ownership([false, false], true), RBMChallengeEntry.DEFEAT_CONFLICT, "the server and this PC disagree")

func test_the_server_answer_is_read_only_from_a_successful_boolean() -> void:
	assert_eq(RBMChallengeEntry.server_by_owner({"ok": true, "clear_count": 1, "by_owner": true}), true)
	assert_eq(RBMChallengeEntry.server_by_owner({"ok": true, "clear_count": 1, "by_owner": false}), false)
	assert_eq(RBMChallengeEntry.server_by_owner({"ok": true, "clear_count": 1}), null, "an older server without the field: unknown")
	assert_eq(RBMChallengeEntry.server_by_owner({"ok": true, "by_owner": "false"}), null, "not a boolean: unknown")
	assert_eq(RBMChallengeEntry.server_by_owner({"ok": false, "error_kind": "network_error", "by_owner": false}), null, "a failure: unknown")

## tickets = true は今のサーバー（戦闘チケットあり）。false は旧版のサーバー（チケットが無い勝ちは旧来のクリアの記録で判断する経路）。
func _entry_for_ownership(attempt_response: Dictionary, clear_response: Dictionary, tickets := false) -> Dictionary:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	var auth := _steam_auth()
	var recorder_api := RBMFakeBossApiAdapter.new()
	recorder_api.tickets_enabled = tickets
	add_child_autofree(recorder_api)
	recorder_api.configure_record_attempt_response(attempt_response)
	recorder_api.configure_record_clear_response(clear_response)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)
	var browse_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(browse_api)
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(browse_api)
	entry.set_online_recorder_for_testing(recorder)
	var cloud := RBMFakeSteamCloud.new()
	var record := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	entry.set_defeat_record_for_testing(record)
	add_child_autofree(entry)
	entry.enter_challenge()
	entry._last_browse_was_online = true
	return {"entry": entry, "record": record, "api": recorder_api, "auth": auth, "cloud": cloud}

## オンラインのボスを選んで挑戦し、勝つ（win = false なら挑戦を始めるだけ）。
func _challenge_online(s: Dictionary, boss_id: String, mode: String, summary: Dictionary, win := true) -> void:
	var entry: RBMChallengeEntry = s.entry
	entry._online_list_view._summaries[boss_id] = summary
	entry._on_online_boss_selected(boss_id, _draft(mode), "討伐記録テストボス", "")
	_ticket.call_deferred(s.auth)
	entry._confirm_view._on_challenge_pressed()
	await wait_process_frames(3)
	if not win:
		return
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over and entry._battle_view.session.battle.winner == "ally", "sanity: won")
	_ticket.call_deferred(s.auth)
	await wait_process_frames(3)

func _after_ownership_test() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	await get_tree().process_frame

func test_the_author_clearing_their_own_boss_adds_nothing_but_the_online_records_are_still_sent() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": true}, {"ok": true, "clear_count": 1, "by_owner": true})
	await _challenge_online(s, "own-boss", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 40, "unique_clearers": 1})
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "neither HARDCORE nor a hard boss for my own boss")
	assert_eq(s.entry._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_OWNER)
	assert_eq(s.api.record_attempt_calls.size(), 1, "the author can still challenge (attempt recorded)")
	assert_eq(s.api.record_clear_calls.size(), 1, "the clear is still recorded on the server")
	await _after_ownership_test()

func test_a_boss_published_from_this_pc_is_the_authors_even_when_the_server_cannot_answer() -> void:
	var mine := _draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	mine.set_online_boss_id("published-here")
	RBMLocalStageRepository.save_new(mine)
	var failure := {"ok": false, "error_kind": "network_error", "message": "offline"}
	var s := _entry_for_ownership(failure, failure)
	await _challenge_online(s, "published-here", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 10, "unique_clearers": 0})
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	assert_eq(s.entry._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_OWNER)
	await _after_ownership_test()

func test_another_players_boss_counts_when_either_record_confirms_it() -> void:
	var s := _entry_for_ownership({"ok": false, "error_kind": "network_error", "message": "offline"}, {"ok": true, "clear_count": 1, "by_owner": false})
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 10, "unique_clearers": 5})
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0})
	assert_eq(s.entry._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_NOT_OWNER)
	await _after_ownership_test()

func test_starting_a_challenge_without_winning_adds_nothing() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": false}, {"ok": true, "clear_count": 1, "by_owner": false})
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 10, "unique_clearers": 0}, false)
	assert_eq(s.api.record_attempt_calls.size(), 1)
	assert_eq(s.api.record_clear_calls.size(), 0)
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0})
	await _after_ownership_test()

func test_unknown_or_conflicting_answers_add_nothing_and_a_later_confirmed_clear_counts_once() -> void:
	var failure := {"ok": false, "error_kind": "network_error", "message": "offline"}
	var s := _entry_for_ownership(failure, failure)
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 20, "unique_clearers": 1})
	assert_eq(s.entry._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_UNKNOWN)
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "communication failure: not added")

	# 食い違い（挑戦では作者ではない、クリアでは作者）も数えない
	s.api.configure_record_attempt_response({"ok": true, "challenge_count": 1, "by_owner": false})
	s.api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": true})
	await _challenge_online(s, "conflict-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 20, "unique_clearers": 1})
	assert_eq(s.entry._defeat_context.get("ownership"), RBMChallengeEntry.DEFEAT_CONFLICT)
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "conflict: not added")

	# 通信が戻ってから同じボスにまた勝つと、その時に1件だけ数える（今のサーバー: 戦闘チケットの結果の応答の認定で難関を決める）
	s.api.tickets_enabled = true
	s.api.configure_record_attempt_response({"ok": true, "challenge_count": 2, "by_owner": false})
	s.api.configure_record_clear_response({"ok": true, "clear_count": 2, "by_owner": false, "hard_awarded": true, "first_clear_rate": 0.05})
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 20, "unique_clearers": 1})
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 1, "hard": 1})
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 20, "unique_clearers": 1})
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 1, "hard": 1}, "a re-clear does not add")
	await _after_ownership_test()

## 2026-10-23: 難関はサーバーの認定で決まる（初めてクリアした時のほかの人のクリア率 0%・5% は認定、10% は認定しない）。
func test_other_players_bosses_count_by_mode_and_the_hard_award_at_0_5_and_10_percent_and_stay_recorded() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": false}, {"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": true, "first_clear_rate": 0.0}, true)
	await _challenge_online(s, "rate-0", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 20, "unique_clearers": 0})
	s.api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": true, "first_clear_rate": 0.05})
	await _challenge_online(s, "rate-5", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 20, "unique_clearers": 1})
	s.api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": false, "first_clear_rate": 0.1})
	await _challenge_online(s, "rate-10", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 20, "unique_clearers": 2})
	assert_eq(s.record.counts(), {"simple": 2, "hardcore": 1, "hard": 2}, "0% and exactly 5% are awarded, 10% is not")
	assert_almost_eq(float(s.record.data.bosses["rate-5"].rate), 0.05, 0.0001, "the first clear rate from the server is kept")
	# 作者のボスの勝利を挟んでも、もう数えた記録は消えない
	s.api.configure_record_attempt_response({"ok": true, "challenge_count": 1, "by_owner": true})
	s.api.configure_record_clear_response({"ok": true, "clear_count": 1, "by_owner": true})
	await _challenge_online(s, "own-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 20, "unique_clearers": 0})
	assert_eq(s.record.counts(), {"simple": 2, "hardcore": 1, "hard": 2})
	# 読み直しても同じ（手元と Steam Cloud の形式は今までどおり）
	var reloaded := RBMDefeatRecord.new(ACCOUNT_A, s.cloud)
	reloaded.load_records()
	assert_eq(reloaded.counts(), {"simple": 2, "hardcore": 1, "hard": 2})
	assert_true((s.cloud as RBMFakeSteamCloud).files.has(RBMDefeatRecord.CLOUD_FILE))
	await _after_ownership_test()

func test_the_local_online_ids_list_only_published_bosses_and_skip_broken_files() -> void:
	var published := _draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	published.set_online_boss_id("online-id-1")
	RBMLocalStageRepository.save_new(published)
	RBMLocalStageRepository.save_new(_draft(RBMCreatorDraft.CREATOR_MODE_SIMPLE))
	var broken := FileAccess.open(TEST_DIR.path_join("1234567890.json"), FileAccess.WRITE)
	broken.store_string("{ not json")
	broken.close()
	assert_eq(RBMLocalStageRepository.online_boss_ids(), {"online-id-1": true}, "only the boss published from this PC; a broken file is skipped quietly")

# ---------------------------------------------------------------------------
# 2026-10-23: 難関ボス討伐の認定（サーバーが決める）。保留 → さかのぼった認定・永久に保持・負けの記録・認定の受け取り。
# 条件の境界（挑戦結果 49/50/51・挑戦者 9/10/11・クリア率 4/5/6%・挑戦0回）と遡及の決まりは、DB の関数で決まるので
# supabase/tools/verify_hard_defeat_checks.sql（本物の DB）と submit-battle-result の deno テストで確かめる。
# 戦闘チケット・送信待ち・送り直しのゲーム側は test_rbm_battle_results.gd。

func test_a_held_clear_becomes_hard_when_the_server_awards_it_later_and_stays_hard() -> void:
	var cloud := RBMFakeSteamCloud.new()
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("held", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.04, 100)
	r.record_clear("never", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.3, 110)
	assert_true(r.has_unawarded_entries())
	assert_eq(r.mark_hard(["held", "not-cleared-here"]), 1, "only an existing record becomes hard; a boss without a record is ignored")
	assert_eq(r.counts(), {"simple": 2, "hardcore": 0, "hard": 1})
	assert_eq(r.mark_hard(["held"]), 0, "already hard: nothing changes")
	# 再起動・読み直しても残る（手元と Steam Cloud の両方）
	var reloaded := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	reloaded.load_records()
	assert_eq(reloaded.counts(), {"simple": 2, "hardcore": 0, "hard": 1})
	# Steam Cloud の形式は今までどおり（mode・rate・hard・at だけ）
	var cloud_data: Dictionary = JSON.parse_string(cloud.files[RBMDefeatRecord.CLOUD_FILE])
	assert_eq((cloud_data.bosses["held"] as Dictionary).keys().size(), 4)
	assert_true(bool(cloud_data.bosses["held"].hard))

func test_merging_keeps_a_hard_award_from_either_side() -> void:
	var a := {"account": ACCOUNT_A, "bosses": {"x": {"mode": "simple", "rate": 0.04, "hard": true, "at": 200}}}
	var b := {"account": ACCOUNT_A, "bosses": {"x": {"mode": "simple", "rate": 0.04, "hard": false, "at": 100}}}
	assert_true(bool(RBMDefeatRecord.merge(a, b).bosses["x"].hard), "the earlier entry keeps its time, and the award is kept")
	assert_eq(int(RBMDefeatRecord.merge(a, b).bosses["x"].at), 100)
	assert_true(bool(RBMDefeatRecord.merge(b, a).bosses["x"].hard), "either order")
	# 手元が難関で Steam Cloud が古い（難関なし）時も、読み直すと難関のまま。Steam Cloud も難関に直る
	var cloud := RBMFakeSteamCloud.new()
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("x", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.04, 100, true)
	cloud.files[RBMDefeatRecord.CLOUD_FILE] = JSON.stringify({"format": RBMDefeatRecord.FORMAT, "version": 1, "account": ACCOUNT_A,
		"bosses": {"x": {"mode": "simple", "rate": 0.04, "hard": false, "at": 100}}})
	r.load_records()
	assert_eq(r.counts().hard, 1)
	assert_true(bool(JSON.parse_string(cloud.files[RBMDefeatRecord.CLOUD_FILE]).bosses["x"].hard), "Steam Cloud gets the award back")

func test_the_award_fields_are_read_only_from_a_successful_response() -> void:
	assert_true(RBMChallengeEntry.server_hard_awarded({"ok": true, "hard_awarded": true}))
	assert_false(RBMChallengeEntry.server_hard_awarded({"ok": true, "hard_awarded": false}))
	assert_false(RBMChallengeEntry.server_hard_awarded({"ok": true}), "an older server: not awarded")
	assert_false(RBMChallengeEntry.server_hard_awarded({"ok": true, "hard_awarded": "true"}), "not a boolean")
	assert_false(RBMChallengeEntry.server_hard_awarded({"ok": false, "hard_awarded": true}), "a failure")
	assert_almost_eq(float(RBMChallengeEntry.server_first_clear_rate({"ok": true, "first_clear_rate": 0.05})), 0.05, 0.0001)
	assert_eq(RBMChallengeEntry.server_first_clear_rate({"ok": true, "first_clear_rate": null}), null)
	assert_eq(RBMChallengeEntry.server_first_clear_rate({"ok": false, "first_clear_rate": 0.01}), null)

func _losing_draft() -> RBMCreatorDraft:
	# 必ず負けるボス（test_rbm_result_screens.gd と同じ形）
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "負けるテストボス"
	draft.hp = 99999
	draft.atk = 9999
	draft.spd = 1
	var skill_id := draft.add_skill({"name": "猛攻", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 100.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	draft.add_party_character("hero")
	return draft

func _fight_until_over(view: RBMChallengeBattleView) -> void:
	for i in 40:
		if view.session == null or view.session.battle == null or view.session.battle.battle_over:
			return
		view.act_attack(0)

func test_the_battle_view_reports_a_loss_once_and_never_as_a_win() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	var lost := [0]
	var won := [0]
	view.challenge_lost.connect(func(): lost[0] += 1)
	view.challenge_won.connect(func(): won[0] += 1)
	view.start_battle(_losing_draft().to_definition())
	_fight_until_over(view)
	await wait_process_frames(2)
	assert_true(view.session.battle.battle_over and view.session.battle.winner == "boss", "sanity: lost")
	view.refresh()
	view.refresh()
	assert_eq([lost[0], won[0]], [1, 0], "one result per battle, even if the screen refreshes again")

func test_a_loss_on_an_online_boss_is_sent_as_a_result_and_a_local_boss_loss_is_not() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": false}, {"ok": true, "clear_count": 1, "by_owner": false}, true)
	await _challenge_online(s, "their-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 10, "unique_clearers": 0}, false)
	_ticket.call_deferred(s.auth)
	(s.entry as RBMChallengeEntry)._battle_view.challenge_lost.emit()
	await wait_process_frames(3)
	assert_eq(s.api.counted_results.size(), 1, "the loss is sent once with the battle ticket")
	assert_eq([s.api.counted_results[0].boss_id, s.api.counted_results[0].outcome], ["their-boss", "loss"])
	assert_eq(s.record.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "a loss is not a defeat record")
	# 手元に保存したボスの負けは送らない
	(s.entry as RBMChallengeEntry)._last_browse_was_online = false
	(s.entry as RBMChallengeEntry)._battle_view.challenge_lost.emit()
	await wait_process_frames(2)
	assert_eq(s.api.submit_calls.size(), 1)
	assert_eq(s.api.counted_results.size(), 1)
	await _after_ownership_test()

func _show_hub_and_receive(s: Dictionary) -> void:
	_ticket.call_deferred(s.auth)
	(s.entry as RBMChallengeEntry)._show_hub()
	await wait_process_frames(3)

func test_the_hub_receives_retroactive_awards_only_when_needed_and_not_too_often() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": false}, {"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": false, "first_clear_rate": 0.04}, true)
	var entry: RBMChallengeEntry = s.entry
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 0, "no records yet: nothing to ask")
	await _challenge_online(s, "held-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 25, "unique_clearers": 1})
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "held: the boss has not reached 50 results / 10 challengers yet")
	# 後でサーバーが認定した（50回・10人に届き、5%以下）→ 挑戦トップで受け取る。ほかの人のボス・記録の無いボスは無視
	s.api.configure_list_my_hard_awards_response({"ok": true, "boss_ids": ["held-boss", "never-cleared-here"]})
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 1)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 1})
	assert_eq(entry._hub_view.defeat_counts_shown(), {"simple": 1, "hardcore": 0, "hard": 1})
	# 難関がまだついていない記録が無ければ聞きに行かない
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 1)
	# 新しい保留の記録があっても、間隔（10分）が空くまでは聞きに行かない
	s.api.configure_list_my_hard_awards_response({"ok": true, "boss_ids": ["held-boss", "held-2"]})
	await _challenge_online(s, "held-2", RBMCreatorDraft.CREATOR_MODE_ADVANCED, {"unique_challengers": 25, "unique_clearers": 1})
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 1, "throttled")
	entry._hard_award_sync_at_msec = Time.get_ticks_msec() - RBMChallengeEntry.HARD_AWARD_SYNC_INTERVAL_MSEC - 1
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 2)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 1, "hard": 2})
	await _after_ownership_test()

func test_a_failed_award_check_changes_nothing_and_a_restart_checks_again() -> void:
	var s := _entry_for_ownership({"ok": true, "challenge_count": 1, "by_owner": false}, {"ok": true, "clear_count": 1, "by_owner": false, "hard_awarded": false, "first_clear_rate": 0.04}, true)
	var entry: RBMChallengeEntry = s.entry
	await _challenge_online(s, "held-boss", RBMCreatorDraft.CREATOR_MODE_SIMPLE, {"unique_challengers": 25, "unique_clearers": 1})
	s.api.configure_list_my_hard_awards_response({"ok": false, "error_kind": "network_error", "message": "offline"})
	await _show_hub_and_receive(s)
	assert_eq(s.api.list_my_hard_awards_calls, 1)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 0}, "a failed check changes nothing")
	# 再起動（新しい挑戦トップは間隔の記録を持たない）→ 通信が戻っていれば受け取る
	entry._hard_award_sync_at_msec = -1
	s.api.configure_list_my_hard_awards_response({"ok": true, "boss_ids": ["held-boss"]})
	await _show_hub_and_receive(s)
	assert_eq(s.record.counts(), {"simple": 1, "hardcore": 0, "hard": 1})
	# 記録を読み直しても残る
	var reloaded := RBMDefeatRecord.new(ACCOUNT_A, s.cloud)
	reloaded.load_records()
	assert_eq(reloaded.counts(), {"simple": 1, "hardcore": 0, "hard": 1})
	await _after_ownership_test()
