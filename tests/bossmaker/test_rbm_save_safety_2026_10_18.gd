extends GutTest

## 保存の安全性・Steam Cloud（総合品質改善 2026-10-18）の回帰テスト。
## - テストの中では、保存先を差し替えなくても本物の user://bossmaker（ボス戦・挑戦の記録・討伐記録・言語設定）に書かない
## - 書き込みに失敗しても、前の中身が残る（一時ファイル → 置き換え）
## - 討伐記録と Steam Cloud（偽物）: 上げられなかった記録は次に読む時に上げ直す、Steam Cloud の壊れたファイルで手元を
##   失わない、別のアカウントの記録は混ぜない、オフラインで取った記録は後で同期される、記録が増えた時の大きさ
## 本物の Steam・本物の保存には触れない。

const TEST_ROOT := "user://test_rbm_save_safety_2026_10_18"
const ACCOUNT_A := "76561198000000001"
const ACCOUNT_B := "76561198000000002"

func before_each() -> void:
	_remove_recursive(TEST_ROOT)
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_ROOT + "/stages")

func after_each() -> void:
	RBMLocalStageRepository._force_rename_failure_for_testing = false
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

# =============================================================================
# テストの中では本物の保存に書かない
# =============================================================================

func test_tests_never_use_the_real_save_folder_even_without_an_override() -> void:
	assert_true(RBMLocalStageRepository.running_under_gut(), "sanity: GUT の中")
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	var dir := RBMLocalStageRepository.stages_dir()
	assert_ne(dir, RBMLocalStageRepository.DEFAULT_STAGES_DIR, "差し替えが無くても本物のボス戦の置き場ではない")
	assert_true(dir.begins_with(RBMLocalStageRepository.GUT_DEFAULT_ROOT))
	assert_true(RBMDefeatRecord.records_dir().begins_with(RBMLocalStageRepository.GUT_DEFAULT_ROOT), "討伐記録も")
	assert_true(RBMLocalStageRepository._stage_stats_dir().begins_with(RBMLocalStageRepository.GUT_DEFAULT_ROOT), "挑戦の記録も")
	assert_ne(RBMLocale.settings_path(), "user://bossmaker/settings.json", "言語設定も本物のファイルではない")
	assert_eq(RBMLocalStageRepository.DEFAULT_STAGES_DIR, "user://bossmaker/stages", "本物のゲームの置き場は変えていない")

func test_switching_the_language_in_a_test_leaves_the_real_settings_alone() -> void:
	var real := "user://bossmaker/settings.json"
	var before := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>"
	var before_time := FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else 0
	var saved := RBMLocale.current_locale()
	RBMLocale.set_locale("en" if saved == "ja" else "ja")
	RBMLocale.set_locale(saved)
	var after := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<none>"
	assert_eq(after, before, "本物の設定の中身は変わらない")
	assert_eq(FileAccess.get_modified_time(real) if FileAccess.file_exists(real) else 0, before_time, "書き込みもしない")
	assert_true(FileAccess.file_exists(RBMLocale.settings_path()), "テストの置き場に書く")

# =============================================================================
# 書き込みの途中の失敗
# =============================================================================

func test_a_failed_write_keeps_the_previous_content() -> void:
	var path := TEST_ROOT + "/stages/sample.json"
	assert_true(RBMLocalStageRepository._atomic_write(path, "{\"v\": 1}"))
	RBMLocalStageRepository._force_rename_failure_for_testing = true
	assert_false(RBMLocalStageRepository._atomic_write(path, "{\"v\": 2}"), "置き換えに失敗した")
	RBMLocalStageRepository._force_rename_failure_for_testing = false
	assert_eq(FileAccess.get_file_as_string(path), "{\"v\": 1}", "前の中身が残る")

func test_a_saved_boss_survives_a_failed_overwrite() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "上書きに失敗するボス"
	draft.hp = 2000
	draft.add_party_character("hero")
	var saved := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(saved.get("stage_id", ""))
	assert_true(bool(saved.get("ok", false)), "sanity")
	draft.hp = 9999
	RBMLocalStageRepository._force_rename_failure_for_testing = true
	var over := RBMLocalStageRepository.overwrite(stage_id, draft)
	RBMLocalStageRepository._force_rename_failure_for_testing = false
	assert_false(bool(over.get("ok", false)), "失敗を返す")
	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(loaded.get("ok", false)), "前の保存は読める")
	assert_eq(int((loaded.draft_data as Dictionary).get("hp", 0)), 2000, "前の中身のまま")

# =============================================================================
# 討伐記録と Steam Cloud（偽物）
# =============================================================================

func test_a_failed_upload_is_sent_again_on_the_next_load() -> void:
	var cloud := RBMFakeSteamCloud.new()
	cloud.fail_writes = true
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5, 100)
	assert_eq(r.cloud_state, "write_failed", "sanity")
	assert_false(cloud.files.has(RBMDefeatRecord.CLOUD_FILE))
	cloud.fail_writes = false
	var next_start := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	next_start.load_records()
	assert_true(cloud.files.has(RBMDefeatRecord.CLOUD_FILE), "次に読んだ時に上げ直す")
	assert_true(str(cloud.files[RBMDefeatRecord.CLOUD_FILE]).contains("boss-1"))

func test_a_broken_steam_cloud_file_does_not_wipe_the_local_record() -> void:
	var cloud := RBMFakeSteamCloud.new()
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("boss-1", RBMCreatorDraft.CREATOR_MODE_ADVANCED, 0.02, 100)
	cloud.files[RBMDefeatRecord.CLOUD_FILE] = "{ broken"
	var again := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	again.load_records()
	assert_eq(again.counts(), {"simple": 0, "hardcore": 1, "hard": 1}, "手元の記録は残る")
	assert_true(str(cloud.files[RBMDefeatRecord.CLOUD_FILE]).contains("boss-1"), "Steam Cloud は正しい記録で書き直す")

func test_another_accounts_cloud_record_is_never_mixed_in() -> void:
	var cloud := RBMFakeSteamCloud.new()
	var b := RBMDefeatRecord.new(ACCOUNT_B, cloud)
	b.record_clear("b-only", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5, 100)
	var a := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	a.load_records()
	assert_eq(a.counts(), {"simple": 0, "hardcore": 0, "hard": 0}, "別のアカウントの記録は数えない")
	assert_ne(a.local_path(), b.local_path(), "手元の記録もアカウントごとに別のファイル")

func test_a_record_taken_while_offline_is_synced_later() -> void:
	var cloud := RBMFakeSteamCloud.new()
	cloud.available = false
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	r.record_clear("offline", RBMCreatorDraft.CREATOR_MODE_SIMPLE, 0.5, 100)
	assert_eq(r.cloud_state, "unavailable")
	cloud.available = true
	var restarted := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	restarted.load_records()
	assert_eq(restarted.counts().simple, 1, "再起動しても手元の記録が残る")
	assert_true(str(cloud.files.get(RBMDefeatRecord.CLOUD_FILE, "")).contains("offline"), "Steam Cloud が使えるようになったら上げる")
	# 別の PC（手元は空）でも見える
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_ROOT + "/pc2/stages")
	var pc2 := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	pc2.load_records()
	assert_eq(pc2.counts().simple, 1, "別の PC でも同じアカウントなら引き継がれる")

func test_the_record_file_stays_small_as_clears_grow() -> void:
	var cloud := RBMFakeSteamCloud.new()
	var r := RBMDefeatRecord.new(ACCOUNT_A, cloud)
	for i in 1000:
		(r.data.bosses as Dictionary)["00000000-0000-4000-8000-%012d" % i] = {"mode": "simple", "rate": 0.25, "hard": false, "at": 1760000000 + i}
	r._write_local(r.data)
	var size := FileAccess.get_file_as_bytes(r.local_path()).size()
	gut.p("1,000件の討伐記録の大きさ: %d バイト" % size)
	assert_lt(size, 200 * 1024, "1,000件でも 200KB 未満（Steam Cloud の容量の目安を決める材料）")
