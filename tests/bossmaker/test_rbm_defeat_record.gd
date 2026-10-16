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

func test_hard_bosses_are_judged_by_the_rate_at_the_first_clear_and_unknown_rates_never_count() -> void:
	var r := RBMDefeatRecord.new(ACCOUNT_A)
	r.record_clear("exactly-5", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.05)
	r.record_clear("just-over", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.0501)
	r.record_clear("nobody-yet", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.0)
	r.record_clear("unknown", RBMCreatorDraft.CREATOR_MODE_ADVANCED, -1.0)
	assert_eq(r.counts(), {"simple": 2, "hardcore": 2, "hard": 2}, "5% counts, 5.01% does not, 0% counts, unknown does not")
	# 初回で固定: 後でクリア率が下がって再びクリアしても、難関には変わらない
	r.record_clear("just-over", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.01)
	assert_eq(r.counts().hard, 2)

func test_the_official_rate_is_the_online_list_rate_and_unknown_is_not_guessed() -> void:
	assert_almost_eq(RBMDefeatRecord.official_rate({"unique_challengers": 40, "unique_clearers": 1}), 0.025, 0.0001)
	assert_eq(RBMDefeatRecord.official_rate({"unique_challengers": 0, "unique_clearers": 0}), -1.0, "no challengers: unknown")
	assert_eq(RBMDefeatRecord.official_rate({"unique_challengers": 10}), -1.0, "missing clearers: unknown")
	assert_eq(RBMDefeatRecord.official_rate({}), -1.0, "an older server without counts: unknown")

func test_records_survive_a_restart_and_are_separate_per_account() -> void:
	var a := RBMDefeatRecord.new(ACCOUNT_A)
	a.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.02)
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
	pc2.record_clear("only-pc2", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.03, 200)
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

	# オンラインのボス（一覧のクリア率 1/40 = 2.5%）に勝つ → HARDCORE 1・難関 1
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
	assert_eq(recorder_api.record_clear_calls.size(), 1, "the online clear record is still sent as before")

	# もう一度挑戦して勝っても増えない
	entry._battle_view._do_restart()
	await wait_process_frames(2)
	entry._battle_view.act_attack(0)
	_ticket.call_deferred(auth)
	await wait_process_frames(3)
	assert_eq(record.counts(), {"simple": 0, "hardcore": 1, "hard": 1}, "a re-clear does not add")

	# クリア率の分からないオンラインのボス（SIMPLE）→ SIMPLE 1、難関は増えない
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
