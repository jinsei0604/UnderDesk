extends GutTest

## RPG BOSS MAKER Phase 1 Step 6 — RBMLocalStageRepository（1 stage = 1 JSON
## ファイルのローカル保存I/O層）テスト。実プレイヤーのuser://保存ライブラリを
## 一切汚さないよう、専用のテスト用ディレクトリへ差し替えて実行し、各テスト
## 終了後に完全削除する。

const TEST_DIR := "user://bossmaker_test_repository/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMLocalStageRepository.set_forced_candidates_for_testing([])
	RBMLocalStageRepository.set_force_rename_failure_for_testing(false)

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _basic_draft(boss_name: String = "テストボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

# ---------------------------------------------------------------------------
# stage_id (§3/§4/§53)
# ---------------------------------------------------------------------------

func test_generated_stage_id_is_a_10_digit_numeric_string() -> void:
	var id := RBMLocalStageRepository.generate_unique_stage_id()
	assert_eq(typeof(id), TYPE_STRING)
	assert_eq(id.length(), 10)
	for i in range(id.length()):
		assert_true(id[i].is_valid_int(), "character %d ('%s') of '%s' must be a digit" % [i, id[i], id])

func test_generated_stage_id_can_begin_with_zero_across_many_draws() -> void:
	var saw_leading_zero := false
	for i in range(200):
		if RBMLocalStageRepository.generate_unique_stage_id().begins_with("0"):
			saw_leading_zero = true
			break
	assert_true(saw_leading_zero, "a leading '0' must be reachable — the id space is not silently truncating to 9 digits")

## §3: 先頭0がString型のまま保たれ、10桁の整数として丸められたり短縮されたり
## しないことを、実際のファイル書き込み経由（手動で用意したペイロード）で
## 直接証明する。
func test_leading_zero_stage_id_round_trips_through_load_as_a_string() -> void:
	var draft := _basic_draft("先頭ゼロ")
	var payload := {
		"save_format_version": 1, "stage_id": "0123456789",
		"created_unix_time": 1000, "updated_unix_time": 1000,
		"draft": draft.to_saved_dict(), "clear_check_success_snapshot": {},
	}
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/0123456789.json" % TEST_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

	assert_true(RBMLocalStageRepository.exists("0123456789"))
	var result := RBMLocalStageRepository.load_stage("0123456789")
	assert_true(bool(result.get("ok", false)))
	assert_eq(str(result.get("stage_id", "")), "0123456789", "leading zero must be preserved, not dropped as if this were a numeric 123456789")

func test_generate_unique_stage_id_never_returns_an_already_saved_id() -> void:
	var first := RBMLocalStageRepository.save_new(_basic_draft())
	var existing_id: String = str(first.get("stage_id", ""))
	for i in range(200):
		var candidate := RBMLocalStageRepository.generate_unique_stage_id()
		assert_ne(candidate, existing_id, "must never regenerate an id that already exists() on disk")

## §53「衝突時再生成」の決定論的テスト——テスト専用のforced-candidatesシーム
## (RBMLocalStageRepository.set_forced_candidates_for_testing()、本番プレイでは
## 常に空配列のまま乱数生成をそのまま使う)で、①1回目の候補が既存stage_idと
## 完全に一致する状況を意図的に作り、②generate_unique_stage_id()の実際の
## while exists(candidate)ループが本当にそれを検出して再生成し、③2回目の
## （別の）候補を採用することを、大量試行に頼らず1回で確定的に証明する。
func test_generate_unique_stage_id_retries_on_a_forced_collision() -> void:
	# ①既存stage_idを用意する（このstage_id自体もシーム経由で確定させる——
	# 手書きのファイル注入ではなく、実際のsave_new()経路を通す）。
	RBMLocalStageRepository.set_forced_candidates_for_testing(["1111111111"])
	var first := RBMLocalStageRepository.save_new(_basic_draft("先に保存済み"))
	assert_eq(str(first.get("stage_id", "")), "1111111111", "sanity: the first save actually landed on the forced id")
	var first_text_before := FileAccess.get_file_as_string("%s/1111111111.json" % TEST_DIR)

	# ②③④次の候補として「既存stage_id(衝突) -> 別のstage_id」の順を強制する。
	RBMLocalStageRepository.set_forced_candidates_for_testing(["1111111111", "2222222222"])
	var generated := RBMLocalStageRepository.generate_unique_stage_id()

	# ⑤: 1回目の候補(1111111111)は衝突のため捨てられ、2回目の候補が採用される。
	assert_eq(generated, "2222222222", "the collision on the FIRST forced candidate must be detected and retried, landing on the SECOND candidate")
	# forced候補キューが実際に2件とも消費されたこと（=本当に2回試行したこと）
	# を、キューが空になっていることで直接確認する。
	assert_true(RBMLocalStageRepository._forced_candidates_for_testing.is_empty(), "both forced candidates must have been consumed by the retry loop")

	# ⑥既存stageは上書きされない: 上記generate_unique_stage_id()の呼び出し
	# 自体はファイルを一切書かないため、そのままsave_new()で実際に保存まで
	# 通し、最初のstageのファイル内容がバイト単位で無変化のままであることを
	# 確認する。
	RBMLocalStageRepository.set_forced_candidates_for_testing(["1111111111", "2222222222"])
	var second := RBMLocalStageRepository.save_new(_basic_draft("衝突後に保存"))
	assert_eq(str(second.get("stage_id", "")), "2222222222")
	var first_text_after := FileAccess.get_file_as_string("%s/1111111111.json" % TEST_DIR)
	assert_eq(first_text_before, first_text_after, "the existing stage at the collided id must remain completely untouched")
	assert_eq(RBMLocalStageRepository.list().size(), 2)

func test_exists_reflects_real_saved_state() -> void:
	assert_false(RBMLocalStageRepository.exists("1111111111"))
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	var id: String = str(result.get("stage_id", ""))
	assert_true(RBMLocalStageRepository.exists(id))

# ---------------------------------------------------------------------------
# save_new (§23/§25/§54/§55)
# ---------------------------------------------------------------------------

func test_save_new_creates_exactly_one_file_and_returns_ok_with_a_10_digit_id() -> void:
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	assert_true(bool(result.get("ok", false)))
	var id: String = str(result.get("stage_id", ""))
	assert_eq(id.length(), 10)
	assert_true(FileAccess.file_exists("%s/%s.json" % [TEST_DIR, id]))
	assert_eq(RBMLocalStageRepository.list().size(), 1)

## §44/§48: save_format_versionが実際にファイルへ記録され、ロード時に読み
## 取れることを直接確認する（Phase 3はversion 2）。
func test_save_new_records_save_format_version_2_and_it_is_readable_on_load() -> void:
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	var id: String = str(result.get("stage_id", ""))
	var loaded := RBMLocalStageRepository.load_stage(id)
	assert_eq(int(loaded.get("save_format_version", -1)), 2)
	assert_eq(RBMLocalStageRepository.SAVE_FORMAT_VERSION, 2)

func test_save_new_sets_created_and_updated_time_to_the_same_moment() -> void:
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	assert_eq(int(result.get("created_unix_time", -1)), int(result.get("updated_unix_time", -2)))
	assert_true(int(result.get("created_unix_time", 0)) > 0)

func test_save_new_never_touches_an_existing_stage() -> void:
	var first := RBMLocalStageRepository.save_new(_basic_draft("元祖ボス"))
	var first_id: String = str(first.get("stage_id", ""))
	var before := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, first_id])

	var second := RBMLocalStageRepository.save_new(_basic_draft("別のボス"))
	var second_id: String = str(second.get("stage_id", ""))

	assert_ne(first_id, second_id)
	var after := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, first_id])
	assert_eq(before, after, "saving a second, brand-new stage must not modify the first stage's file at all")
	assert_eq(RBMLocalStageRepository.list().size(), 2)

func test_save_new_persists_all_draft_fields_reloadable() -> void:
	var draft := _basic_draft("完全復元テスト")
	draft.appearance_id = "appearance_dragon"
	var result := RBMLocalStageRepository.save_new(draft)
	var id: String = str(result.get("stage_id", ""))

	var loaded := RBMLocalStageRepository.load_stage(id)
	assert_true(bool(loaded.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.boss_name, "完全復元テスト")
	assert_eq(restored.appearance_id, "appearance_dragon")
	assert_eq(restored.hp, 1000)

# ---------------------------------------------------------------------------
# overwrite (§24/§54)
# ---------------------------------------------------------------------------

func test_overwrite_keeps_stage_id_and_created_time_updates_content_and_updated_time() -> void:
	var draft := _basic_draft("上書き前")
	var saved := RBMLocalStageRepository.save_new(draft)
	var id: String = str(saved.get("stage_id", ""))
	var created: int = int(saved.get("created_unix_time", 0))

	draft.boss_name = "上書き後"
	draft.hp = 2000
	var result := RBMLocalStageRepository.overwrite(id, draft)
	assert_true(bool(result.get("ok", false)))
	assert_eq(str(result.get("stage_id", "")), id, "stage_id must be preserved")
	assert_eq(int(result.get("created_unix_time", -1)), created, "created_unix_time must be preserved across overwrite")

	assert_eq(RBMLocalStageRepository.list().size(), 1, "overwrite must not create a second file")
	var loaded := RBMLocalStageRepository.load_stage(id)
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.boss_name, "上書き後")
	assert_eq(restored.hp, 2000)

func test_overwrite_also_updates_the_clear_check_snapshot() -> void:
	var draft := _basic_draft()
	var saved := RBMLocalStageRepository.save_new(draft)
	var id: String = str(saved.get("stage_id", ""))

	draft.normal_actions_enabled = true
	draft.normal_action_percentages[str(draft.skills[0]["skill_id"])] = 100.0
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity")
	draft.record_clear_check_success()

	RBMLocalStageRepository.overwrite(id, draft)
	var loaded := RBMLocalStageRepository.load_stage(id)
	assert_ne(loaded.get("clear_check_data", {}), {}, "the Clear Check proof recorded before overwrite must be persisted by overwrite")

# ---------------------------------------------------------------------------
# load (§34/§43/§49/§61)
# ---------------------------------------------------------------------------

func test_load_stage_missing_id_returns_ok_false() -> void:
	var result := RBMLocalStageRepository.load_stage("9999999999")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_invalid_id_format_returns_ok_false_without_crashing() -> void:
	var result := RBMLocalStageRepository.load_stage("not-a-valid-id")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_corrupt_json_returns_ok_false_and_does_not_crash() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/1234500000.json" % TEST_DIR, FileAccess.WRITE)
	file.store_string('{"stage_id": "1234500000", "draft": { totally not json')
	file.close()
	var result := RBMLocalStageRepository.load_stage("1234500000")
	assert_false(bool(result.get("ok", true)), "a truncated/corrupt JSON file must be reported as a load failure, never crash")

func test_corrupt_stage_does_not_affect_other_healthy_stages() -> void:
	var healthy := RBMLocalStageRepository.save_new(_basic_draft("健全なボス"))
	var healthy_id: String = str(healthy.get("stage_id", ""))

	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/1234500000.json" % TEST_DIR, FileAccess.WRITE)
	file.store_string("not json at all {{{")
	file.close()

	var loaded_healthy := RBMLocalStageRepository.load_stage(healthy_id)
	assert_true(bool(loaded_healthy.get("ok", false)), "the corrupt neighbor file must not affect loading the healthy stage")

	var listing := RBMLocalStageRepository.list()
	var names: Array = []
	for entry in listing:
		names.append(str(entry.get("boss_name", "")))
	assert_true(names.has("健全なボス"), "the healthy stage must still be usable")
	assert_eq(listing.size(), 1, "the corrupt stage must be silently excluded from list(), not surfaced as a broken entry")

# ---------------------------------------------------------------------------
# list / status (§17/§20/§21/§22/§57)
# ---------------------------------------------------------------------------

func test_list_returns_empty_array_when_no_stages_saved() -> void:
	assert_eq(RBMLocalStageRepository.list(), [])

func test_list_status_draft_when_definition_invalid() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "下書き"
	# skills/party未設定 -> Definition validation失敗 -> 保存自体は許可される(§20)
	var result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(result.get("ok", false)), "saving an incomplete/invalid draft must succeed (§20)")
	var listing := RBMLocalStageRepository.list()
	assert_eq(listing.size(), 1)
	assert_eq(str(listing[0]["status"]), "draft")

func test_list_status_playable_when_valid_but_not_clear_checked() -> void:
	RBMLocalStageRepository.save_new(_basic_draft("挑戦可能ボス"))
	var listing := RBMLocalStageRepository.list()
	assert_eq(str(listing[0]["status"]), "playable")

func test_list_status_clear_checked_when_valid_and_cleared() -> void:
	var draft := _basic_draft("クリア済みボス")
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[str(draft.skills[0]["skill_id"])] = 100.0
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity")
	draft.record_clear_check_success()
	RBMLocalStageRepository.save_new(draft)

	var listing := RBMLocalStageRepository.list()
	assert_eq(str(listing[0]["status"]), "clear_checked")

## §22: statusはJSONへ固定値として保存されない——手動でファイルの中身だけ
## 変更し、statusフィールド自体はどこにも存在しないこと、かつ再度list()した
## 結果が新しい内容から都度算出されていることを確認する。
func test_status_is_recomputed_live_not_read_from_a_stored_flag() -> void:
	var draft := _basic_draft("状態変化ボス")
	var result := RBMLocalStageRepository.save_new(draft)
	var id: String = str(result.get("stage_id", ""))
	assert_eq(str(RBMLocalStageRepository.list()[0]["status"]), "playable")

	var raw_text := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, id])
	assert_eq(raw_text.find("\"status\""), -1, "the saved JSON must never contain a persisted status/draft/playable/clear_checked flag")

	# 内容を「下書き」相当へ書き換えれば、都度算出のstatusも追従するはず
	draft.remove_party_character("hero")
	RBMLocalStageRepository.overwrite(id, draft)
	assert_eq(str(RBMLocalStageRepository.list()[0]["status"]), "draft", "status must be re-derived from the new content, not cached from the earlier save")

# ---------------------------------------------------------------------------
# 最終レビュー対応① — save_format_versionのロード時検証
# ---------------------------------------------------------------------------

func _write_raw_payload(stage_id: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEST_DIR, stage_id], FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func _valid_minimal_payload(stage_id: String, boss_name: String = "検証用") -> Dictionary:
	var draft := _basic_draft(boss_name)
	return {
		"save_format_version": 1, "stage_id": stage_id,
		"created_unix_time": 1000, "updated_unix_time": 1000,
		"draft": draft.to_saved_dict(), "clear_check_success_snapshot": {},
	}

func test_load_stage_with_version_1_succeeds() -> void:
	var payload := _valid_minimal_payload("1000000001", "version1")
	_write_raw_payload("1000000001", payload)
	var result := RBMLocalStageRepository.load_stage("1000000001")
	assert_true(bool(result.get("ok", false)))
	assert_eq(int(result.get("save_format_version", -1)), 1)

## 最終安全性修正①: int()で切り捨ててから比較していた旧実装だと
## int(1.5)==1でversion 1.5が誤受理されるバグがあった——float同士の完全
## 一致比較へ修正したことを、1.0(GDScriptのfloat値として明示的に書いた場合)
## が引き続き成功することで確認する。
func test_load_stage_with_version_1_0_float_succeeds() -> void:
	var payload := _valid_minimal_payload("1000000011", "version1float")
	payload["save_format_version"] = 1.0
	_write_raw_payload("1000000011", payload)
	var result := RBMLocalStageRepository.load_stage("1000000011")
	assert_true(bool(result.get("ok", false)), "1.0 must be accepted as exactly equal to version 1")

## 最終安全性修正①の核心テスト: int(1.5)==1という誤受理を直接再現しようと
## するケース。修正後はfloat比較のため1.5は確実に拒否される。
func test_load_stage_rejects_version_1_5() -> void:
	var payload := _valid_minimal_payload("1000000012", "version1.5")
	payload["save_format_version"] = 1.5
	_write_raw_payload("1000000012", payload)
	var result := RBMLocalStageRepository.load_stage("1000000012")
	assert_false(bool(result.get("ok", true)), "1.5 must never be accepted as version 1 (int(1.5)==1 truncation bug)")

func test_load_stage_rejects_version_0_5() -> void:
	var payload := _valid_minimal_payload("1000000013", "version0.5")
	payload["save_format_version"] = 0.5
	_write_raw_payload("1000000013", payload)
	var result := RBMLocalStageRepository.load_stage("1000000013")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_non_numeric_version() -> void:
	var payload := _valid_minimal_payload("1000000014", "versionstring")
	payload["save_format_version"] = "1"
	_write_raw_payload("1000000014", payload)
	var result := RBMLocalStageRepository.load_stage("1000000014")
	assert_false(bool(result.get("ok", true)), "a String version value must be rejected, not coerced")

## 未知version(例: 3)はok=falseで拒否する。
func test_load_stage_rejects_unknown_version() -> void:
	var payload := _valid_minimal_payload("1000000002", "version3")
	payload["save_format_version"] = 3
	_write_raw_payload("1000000002", payload)
	var result := RBMLocalStageRepository.load_stage("1000000002")
	assert_false(bool(result.get("ok", true)), "an unknown save_format_version must be rejected, not silently accepted")

## version自体が欠落している場合も、version 1だと勝手に補完せず拒否する。
func test_load_stage_rejects_missing_version() -> void:
	var payload := _valid_minimal_payload("1000000003", "versionless")
	payload.erase("save_format_version")
	_write_raw_payload("1000000003", payload)
	var result := RBMLocalStageRepository.load_stage("1000000003")
	assert_false(bool(result.get("ok", true)), "a missing save_format_version must never be treated as version 1 by default")

## 一覧: 未知version stageは通常stageとして表示せず、他の正常stageの一覧
## 取得には影響しない。
func test_list_excludes_unknown_version_stage_and_keeps_healthy_ones() -> void:
	RBMLocalStageRepository.save_new(_basic_draft("健全なボス"))
	var bad_payload := _valid_minimal_payload("1000000004", "version違反ボス")
	bad_payload["save_format_version"] = 3
	_write_raw_payload("1000000004", bad_payload)

	var listing := RBMLocalStageRepository.list()
	assert_eq(listing.size(), 1, "the unknown-version stage must not appear in list()")
	assert_eq(str(listing[0]["boss_name"]), "健全なボス")

# ---------------------------------------------------------------------------
# 最終レビュー対応② — 保存構造・コンテナ型の防御的検証 (§2-2必須破損テスト)
# ---------------------------------------------------------------------------

func test_load_stage_rejects_draft_as_array() -> void:
	var payload := _valid_minimal_payload("2000000001")
	payload["draft"] = []
	_write_raw_payload("2000000001", payload)
	var result := RBMLocalStageRepository.load_stage("2000000001")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_weak_attributes_as_string() -> void:
	var payload := _valid_minimal_payload("2000000002")
	payload["draft"]["weak_attributes"] = "FIRE"
	_write_raw_payload("2000000002", payload)
	var result := RBMLocalStageRepository.load_stage("2000000002")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_skills_as_dictionary() -> void:
	var payload := _valid_minimal_payload("2000000003")
	payload["draft"]["skills"] = {"a": 1}
	_write_raw_payload("2000000003", payload)
	var result := RBMLocalStageRepository.load_stage("2000000003")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_scripted_actions_as_dictionary() -> void:
	var payload := _valid_minimal_payload("2000000004")
	payload["draft"]["scripted_actions"] = {"a": 1}
	_write_raw_payload("2000000004", payload)
	var result := RBMLocalStageRepository.load_stage("2000000004")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_ally_allowed_skill_ids_as_array() -> void:
	var payload := _valid_minimal_payload("2000000005")
	payload["draft"]["ally_allowed_skill_ids"] = [1, 2, 3]
	_write_raw_payload("2000000005", payload)
	var result := RBMLocalStageRepository.load_stage("2000000005")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_clear_check_snapshot_as_array() -> void:
	var payload := _valid_minimal_payload("2000000006")
	payload["clear_check_success_snapshot"] = []
	_write_raw_payload("2000000006", payload)
	var result := RBMLocalStageRepository.load_stage("2000000006")
	assert_false(bool(result.get("ok", true)))

## 実機で確認した追加のクラッシュ経路: restore_from_saved_dict()はhp/atk/spd/
## next_skill_ordinalをint()でstatically int型付きフィールドへ代入する。
## Array/Dictionaryのようなint()変換不能な値だと、単なるコンソールERRORでは
## 済まずプロセスがハングすることを実機で確認済み（完了報告で開示）——
## コンテナ型フィールドに限らずこれらの数値フィールドも防御対象とする。
func test_load_stage_rejects_hp_as_array() -> void:
	var payload := _valid_minimal_payload("2000000007")
	payload["draft"]["hp"] = [1, 2, 3]
	_write_raw_payload("2000000007", payload)
	var result := RBMLocalStageRepository.load_stage("2000000007")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_normal_actions_enabled_as_dictionary() -> void:
	var payload := _valid_minimal_payload("2000000008")
	payload["draft"]["normal_actions_enabled"] = {"a": 1}
	_write_raw_payload("2000000008", payload)
	var result := RBMLocalStageRepository.load_stage("2000000008")
	assert_false(bool(result.get("ok", true)))

# ---------------------------------------------------------------------------
# 最終安全性修正② — ネスト内部の型破損 (§11 Draft必須シナリオ全7件)
# RBMDefinitionLoader._resolve_author_boss_skill()等の`var x := float(...)`
# 推論代入が、restore直後のlist()/is_playable()呼び出しで壊れたVariantに
# 触れうる経路まで確認した実機調査を踏まえ、指示書のフィールド一覧を
# そのまま実装している。
# ---------------------------------------------------------------------------

func test_load_stage_rejects_skill_atk_multiplier_as_array() -> void:
	var payload := _valid_minimal_payload("4000000001")
	payload["draft"]["skills"][0]["atk_multiplier"] = []
	_write_raw_payload("4000000001", payload)
	var result := RBMLocalStageRepository.load_stage("4000000001")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_scripted_action_turn_as_array() -> void:
	var payload := _valid_minimal_payload("4000000002")
	var skill_id: String = str(payload["draft"]["skills"][0]["skill_id"])
	payload["draft"]["scripted_actions"] = [{"turn": [], "skill_id": skill_id, "timing": "replace"}]
	_write_raw_payload("4000000002", payload)
	var result := RBMLocalStageRepository.load_stage("4000000002")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_normal_action_percentage_value_as_array() -> void:
	var payload := _valid_minimal_payload("4000000003")
	var skill_id: String = str(payload["draft"]["skills"][0]["skill_id"])
	payload["draft"]["normal_action_percentages"] = {skill_id: []}
	_write_raw_payload("4000000003", payload)
	var result := RBMLocalStageRepository.load_stage("4000000003")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_ally_allowed_skill_ids_value_as_string() -> void:
	var payload := _valid_minimal_payload("4000000004")
	payload["draft"]["ally_allowed_skill_ids"] = {"hero": "not-array"}
	_write_raw_payload("4000000004", payload)
	var result := RBMLocalStageRepository.load_stage("4000000004")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_ally_allowed_skill_ids_array_element_as_int() -> void:
	var payload := _valid_minimal_payload("4000000005")
	payload["draft"]["ally_allowed_skill_ids"] = {"hero": [123]}
	_write_raw_payload("4000000005", payload)
	var result := RBMLocalStageRepository.load_stage("4000000005")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_weak_attributes_element_as_array() -> void:
	var payload := _valid_minimal_payload("4000000006")
	payload["draft"]["weak_attributes"] = ["FIRE", []]
	_write_raw_payload("4000000006", payload)
	var result := RBMLocalStageRepository.load_stage("4000000006")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_party_character_ids_element_as_array() -> void:
	var payload := _valid_minimal_payload("4000000007")
	payload["draft"]["party_character_ids"] = ["hero", []]
	_write_raw_payload("4000000007", payload)
	var result := RBMLocalStageRepository.load_stage("4000000007")
	assert_false(bool(result.get("ok", true)))

# ---------------------------------------------------------------------------
# 最終安全性修正② — Clear Check snapshot内部の型破損 (§11必須シナリオ全5件)
# ---------------------------------------------------------------------------

func _valid_clear_check_snapshot() -> Dictionary:
	var draft := _basic_draft("クリア済み検証用")
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[str(draft.skills[0]["skill_id"])] = 100.0
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	draft.record_clear_check_success()
	return draft.clear_check_snapshot_for_save()

## _valid_clear_check_snapshot()と違い、draft本体とclear_check_success_snapshot
## の両方を「同一のdraftインスタンス」から生成して返す——is_clear_check_currently_valid()
## のようなStep 5比較まで通したいテスト専用のペア（構造拒否だけを見る他の
## テストは、draftとsnapshotの内容が一致している必要がないため
## _valid_clear_check_snapshot()単独のままでよい）。
func _valid_clear_check_payload_pair() -> Dictionary:
	var draft := _basic_draft("クリア済みペア検証用")
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[str(draft.skills[0]["skill_id"])] = 100.0
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity")
	draft.record_clear_check_success()
	return {"draft": draft.to_saved_dict(), "clear_check_success_snapshot": draft.clear_check_snapshot_for_save()}

func test_load_stage_rejects_clear_check_hp_as_array() -> void:
	var payload := _valid_minimal_payload("5000000001")
	payload["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	payload["clear_check_success_snapshot"]["hp"] = []
	_write_raw_payload("5000000001", payload)
	var result := RBMLocalStageRepository.load_stage("5000000001")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_clear_check_weak_attributes_as_string() -> void:
	var payload := _valid_minimal_payload("5000000002")
	payload["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	payload["clear_check_success_snapshot"]["weak_attributes"] = "FIRE"
	_write_raw_payload("5000000002", payload)
	var result := RBMLocalStageRepository.load_stage("5000000002")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_clear_check_skills_as_array() -> void:
	var payload := _valid_minimal_payload("5000000003")
	payload["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	payload["clear_check_success_snapshot"]["skills"] = []
	_write_raw_payload("5000000003", payload)
	var result := RBMLocalStageRepository.load_stage("5000000003")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_clear_check_normal_actions_as_dictionary() -> void:
	var payload := _valid_minimal_payload("5000000004")
	payload["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	payload["clear_check_success_snapshot"]["normal_actions"] = {}
	_write_raw_payload("5000000004", payload)
	var result := RBMLocalStageRepository.load_stage("5000000004")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_clear_check_party_as_array() -> void:
	var payload := _valid_minimal_payload("5000000005")
	payload["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	payload["clear_check_success_snapshot"]["party"] = []
	_write_raw_payload("5000000005", payload)
	var result := RBMLocalStageRepository.load_stage("5000000005")
	assert_false(bool(result.get("ok", true)))

## §12: 実際に有効なClear Check snapshotが正しく受理されることの対照確認
## （上記5件の拒否テストが「何でも拒否している」わけではないことの裏付け）。
## draft本体とclear_check_success_snapshotを同一draftインスタンスから
## 生成した組を使う——内容が一致していない2つの無関係なdraftを組み合わせる
## と、型は正しくてもStep 5比較(is_clear_check_currently_valid())が
## falseになるのは検証ロジックとして正しい挙動であり、それを避けるため。
func test_load_stage_accepts_a_genuinely_valid_clear_check_snapshot() -> void:
	var pair := _valid_clear_check_payload_pair()
	var payload := {
		"save_format_version": 2, "stage_id": "5000000006",
		"created_unix_time": 1000, "updated_unix_time": 1000,
		"draft": pair["draft"], "clear_check_success_snapshot": pair["clear_check_success_snapshot"],
	}
	_write_raw_payload("5000000006", payload)
	var result := RBMLocalStageRepository.load_stage("5000000006")
	assert_true(bool(result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(result.get("draft_data", {}))
	restored.restore_clear_check_snapshot(result.get("clear_check_data", {}))
	assert_true(restored.is_clear_check_currently_valid(), "a genuinely valid, structurally-correct Clear Check snapshot must still compare valid after round-tripping through the new validation")

## §12: ネスト内部が壊れたstageが複数存在してもlist()はクラッシュせず、
## 全破損stageを除外し、正常stageは残る（Draft内部破損とClear Check内部
## 破損を混在させた、より厳しいシナリオ）。
func test_list_excludes_multiple_deeply_nested_corrupt_stages_and_keeps_healthy_ones() -> void:
	RBMLocalStageRepository.save_new(_basic_draft("健全なボス3"))

	var p1 := _valid_minimal_payload("6000000001")
	p1["draft"]["skills"][0]["atk_multiplier"] = []
	_write_raw_payload("6000000001", p1)

	var p2 := _valid_minimal_payload("6000000002")
	p2["draft"]["ally_allowed_skill_ids"] = {"hero": [123]}
	_write_raw_payload("6000000002", p2)

	var p3 := _valid_minimal_payload("6000000003")
	p3["clear_check_success_snapshot"] = _valid_clear_check_snapshot()
	p3["clear_check_success_snapshot"]["skills"] = []
	_write_raw_payload("6000000003", p3)

	var p4 := _valid_minimal_payload("6000000004")
	p4["draft"]["weak_attributes"] = ["FIRE", []]
	_write_raw_payload("6000000004", p4)

	var listing := RBMLocalStageRepository.list()
	assert_eq(listing.size(), 1, "list() must not crash across multiple deeply-nested corrupt stages, and must exclude all of them")
	assert_eq(str(listing[0]["boss_name"]), "健全なボス3")

## §2-1: これは「ゲームとして完成しているか」のvalidationではない——
## 名前空欄・パーティ0・スキル0でも、型さえ正しければ引き続きロード可能
## でなければならない（既存の下書き保存要件を壊していないことの直接証明）。
func test_load_stage_still_accepts_a_well_typed_but_incomplete_draft() -> void:
	var empty_draft := RBMCreatorDraft.new()  # boss_name="", party=[], skills=[]
	var payload := {
		"save_format_version": 1, "stage_id": "2000000009",
		"created_unix_time": 1000, "updated_unix_time": 1000,
		"draft": empty_draft.to_saved_dict(), "clear_check_success_snapshot": {},
	}
	_write_raw_payload("2000000009", payload)
	var result := RBMLocalStageRepository.load_stage("2000000009")
	assert_true(bool(result.get("ok", false)), "a well-typed but content-incomplete draft must still load successfully")

## 一覧: 複数の破損パターンが混在していてもlist()はクラッシュせず、破損
## stageを静かに除外し、正常stageは引き続き表示される。
func test_list_excludes_all_structurally_corrupt_stages_and_keeps_healthy_ones() -> void:
	RBMLocalStageRepository.save_new(_basic_draft("健全なボス2"))

	var p1 := _valid_minimal_payload("3000000001")
	p1["draft"] = []
	_write_raw_payload("3000000001", p1)

	var p2 := _valid_minimal_payload("3000000002")
	p2["draft"]["weak_attributes"] = "FIRE"
	_write_raw_payload("3000000002", p2)

	var p3 := _valid_minimal_payload("3000000003")
	p3["draft"]["skills"] = {"a": 1}
	_write_raw_payload("3000000003", p3)

	var p4 := _valid_minimal_payload("3000000004")
	p4["draft"]["hp"] = [1, 2, 3]
	_write_raw_payload("3000000004", p4)

	var listing := RBMLocalStageRepository.list()
	assert_eq(listing.size(), 1, "list() must not crash across multiple corrupt stages, and must exclude all of them")
	assert_eq(str(listing[0]["boss_name"]), "健全なボス2")

# ---------------------------------------------------------------------------
# 最終レビュー対応③ — atomic save失敗の決定論的テスト (§3-1/§3-2)
# ---------------------------------------------------------------------------

## §3-1: tmpへ新しい内容を書き込んだが本番へのrenameを行っていない状態を
## 直接シミュレートする(Repositoryのどのメソッドも呼ばずに作れる状態のため、
## この検証自体にtestability seamは不要)。
func test_atomic_save_a_stray_tmp_write_never_corrupts_the_production_file() -> void:
	RBMLocalStageRepository.set_forced_candidates_for_testing(["1111111111"])
	RBMLocalStageRepository.save_new(_basic_draft("OLD"))
	var prod_path := "%s/1111111111.json" % TEST_DIR
	var text_before := FileAccess.get_file_as_string(prod_path)
	assert_true(text_before.find("OLD") != -1, "sanity")

	var new_payload := _valid_minimal_payload("1111111111", "NEW")
	var tmp_file := FileAccess.open(prod_path + ".tmp", FileAccess.WRITE)
	tmp_file.store_string(JSON.stringify(new_payload))
	tmp_file.close()

	# 1. 本番.jsonのバイト列が元と完全一致
	var text_after := FileAccess.get_file_as_string(prod_path)
	assert_eq(text_before, text_after, "a stray .tmp write must never affect the production file's bytes")

	# 2/3. load_stage()が正常成功し、読み込まれる内容はOLD
	var loaded := RBMLocalStageRepository.load_stage("1111111111")
	assert_true(bool(loaded.get("ok", false)), "the production file must still load successfully")
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.boss_name, "OLD", "must load OLD content, not the un-renamed NEW content sitting in .tmp")

	# 4. tmp内容のNEWが本番へ混ざっていない
	assert_ne(restored.boss_name, "NEW")

## §3-2: renameへ到達する直前で失敗を模擬するtestability seam
## (set_force_rename_failure_for_testing)を使い、overwrite()がok=falseを
## 返し、かつ旧本番ファイルが無傷のままであることを直接確認する。
func test_overwrite_rename_failure_reports_ok_false_and_leaves_old_file_untouched() -> void:
	RBMLocalStageRepository.set_forced_candidates_for_testing(["1111111111"])
	var draft := _basic_draft("OLD")
	RBMLocalStageRepository.save_new(draft)
	var prod_path := "%s/1111111111.json" % TEST_DIR
	var text_before := FileAccess.get_file_as_string(prod_path)

	draft.boss_name = "NEW"
	RBMLocalStageRepository.set_force_rename_failure_for_testing(true)
	var result := RBMLocalStageRepository.overwrite("1111111111", draft)
	RBMLocalStageRepository.set_force_rename_failure_for_testing(false)

	assert_false(bool(result.get("ok", true)), "overwrite must report failure when rename never completed")
	var text_after := FileAccess.get_file_as_string(prod_path)
	assert_eq(text_before, text_after, "the old production file must remain byte-identical when rename never completed")

	var loaded := RBMLocalStageRepository.load_stage("1111111111")
	assert_true(bool(loaded.get("ok", false)), "the old file must still load successfully after the failed overwrite")
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.boss_name, "OLD", "the old content must still be what loads, never NEW")

# ---------------------------------------------------------------------------
# boss_name_exists / 同名 (§26/§56)
# ---------------------------------------------------------------------------

func test_boss_name_exists_true_after_saving_that_name() -> void:
	assert_false(RBMLocalStageRepository.boss_name_exists("同名テスト"))
	RBMLocalStageRepository.save_new(_basic_draft("同名テスト"))
	assert_true(RBMLocalStageRepository.boss_name_exists("同名テスト"))

func test_two_stages_can_share_the_same_boss_name_with_different_ids() -> void:
	var a := RBMLocalStageRepository.save_new(_basic_draft("重複名"))
	var b := RBMLocalStageRepository.save_new(_basic_draft("重複名"))
	assert_ne(str(a.get("stage_id", "")), str(b.get("stage_id", "")))
	assert_eq(RBMLocalStageRepository.list().size(), 2)

## 大文字小文字を無視した完全一致——"Dragon"/"dragon"/"DRAGON"はすべて
## 同名として扱う（確定仕様）。部分一致ではないことも合わせて確認する。
func test_boss_name_exists_is_case_insensitive_exact_match() -> void:
	RBMLocalStageRepository.save_new(_basic_draft("Dragon"))
	assert_true(RBMLocalStageRepository.boss_name_exists("dragon"))
	assert_true(RBMLocalStageRepository.boss_name_exists("DRAGON"))
	assert_true(RBMLocalStageRepository.boss_name_exists("DrAgOn"))
	assert_true(RBMLocalStageRepository.boss_name_exists("Dragon"))
	assert_false(RBMLocalStageRepository.boss_name_exists("Dragon King"), "must stay an exact match, not a partial/substring match")
	assert_false(RBMLocalStageRepository.boss_name_exists("Drago"))

# ---------------------------------------------------------------------------
# delete (§41/§42/§60)
# ---------------------------------------------------------------------------

func test_delete_removes_the_file_and_the_listing_entry() -> void:
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	var id: String = str(result.get("stage_id", ""))
	assert_true(RBMLocalStageRepository.delete(id))
	assert_false(FileAccess.file_exists("%s/%s.json" % [TEST_DIR, id]))
	assert_eq(RBMLocalStageRepository.list().size(), 0)

func test_delete_does_not_affect_other_stages() -> void:
	var a := RBMLocalStageRepository.save_new(_basic_draft("残す"))
	var b := RBMLocalStageRepository.save_new(_basic_draft("消す"))
	RBMLocalStageRepository.delete(str(b.get("stage_id", "")))
	var listing := RBMLocalStageRepository.list()
	assert_eq(listing.size(), 1)
	assert_eq(str(listing[0]["boss_name"]), "残す")
	assert_true(RBMLocalStageRepository.exists(str(a.get("stage_id", ""))))

func test_delete_nonexistent_id_returns_false() -> void:
	assert_false(RBMLocalStageRepository.delete("0000000000"))

# ---------------------------------------------------------------------------
# atomic save (§2/§15/§61)
# ---------------------------------------------------------------------------

func test_save_leaves_no_leftover_tmp_file() -> void:
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	var id: String = str(result.get("stage_id", ""))
	assert_false(FileAccess.file_exists("%s/%s.json.tmp" % [TEST_DIR, id]), "a successful save must not leave a .tmp file behind")

func test_overwrite_replaces_content_atomically_leaving_no_tmp_debris() -> void:
	var draft := _basic_draft("atomic")
	var saved := RBMLocalStageRepository.save_new(draft)
	var id: String = str(saved.get("stage_id", ""))
	draft.hp = 12345
	RBMLocalStageRepository.overwrite(id, draft)
	assert_false(FileAccess.file_exists("%s/%s.json.tmp" % [TEST_DIR, id]))
	var text := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, id])
	assert_true(text.find("12345") != -1, "the final file must contain the NEW content, proving the tmp->rename replace actually happened")

## §15/§61: 保存前に本番ファイルがまだ存在しない状態(temp書き込みの途中を模す
## 別ケース)ではなく、既存の本番ファイルが「書き込み中の一時ファイルの存在」
## だけでは一切変化しないことを確認する——write_failedを直接注入することは
## できないため、ここでは「.tmpだけが存在し本番ファイルがまだ無い」状態から
## 正常な保存が完了すると本番ファイルだけが残ることを確認する形で、
## tmp->renameの置換が実際の書き込み経路として機能していることを検証する。
func test_a_stray_tmp_file_does_not_prevent_a_fresh_save() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var stray := FileAccess.open("%s/leftover.json.tmp" % TEST_DIR, FileAccess.WRITE)
	stray.store_string("leftover from a hypothetical earlier crash")
	stray.close()
	var result := RBMLocalStageRepository.save_new(_basic_draft())
	assert_true(bool(result.get("ok", false)))
	assert_eq(RBMLocalStageRepository.list().size(), 1, "a stray unrelated .tmp file must not be picked up by list() nor block a fresh save")

# ---------------------------------------------------------------------------
# Phase 1 Step 7 — 作者備考・情報公開設定の構造検証 (§46/§59)
# ---------------------------------------------------------------------------

func test_load_stage_accepts_valid_author_notes_and_challenge_info_visibility() -> void:
	var draft := _basic_draft()
	draft.set_author_notes("これは検証用の備考です")
	draft.set_challenge_info_visible("hp", false)
	var payload := _valid_minimal_payload("2000000001", "備考テスト")
	payload["draft"] = draft.to_saved_dict()
	_write_raw_payload("2000000001", payload)
	var result := RBMLocalStageRepository.load_stage("2000000001")
	assert_true(bool(result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(result.get("draft_data", {}))
	assert_eq(restored.author_notes, "これは検証用の備考です")
	assert_false(restored.is_challenge_info_visible("hp"))

## §19/§42: フィールド自体が存在しない旧stage（Step 7以前に保存されたもの）
## は正常に読み込め、下書きとして扱われない。
func test_load_stage_accepts_a_save_missing_the_new_fields_entirely() -> void:
	var payload := _valid_minimal_payload("2000000002", "旧stage")
	# _valid_minimal_payload()自体が既にauthor_notes/challenge_info_visibility
	# を含まないto_saved_dict()以前の"生の"辞書を作っているわけではないため、
	# 明示的にキーを取り除いて旧stageを模す。
	(payload["draft"] as Dictionary).erase("author_notes")
	(payload["draft"] as Dictionary).erase("challenge_info_visibility")
	_write_raw_payload("2000000002", payload)
	var result := RBMLocalStageRepository.load_stage("2000000002")
	assert_true(bool(result.get("ok", false)), "a save from before Step 7 (missing the new fields) must still load successfully")

func test_load_stage_rejects_author_notes_as_array() -> void:
	var payload := _valid_minimal_payload("2000000003", "壊れたnotes")
	(payload["draft"] as Dictionary)["author_notes"] = [1, 2, 3]
	_write_raw_payload("2000000003", payload)
	var result := RBMLocalStageRepository.load_stage("2000000003")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_challenge_info_visibility_as_array() -> void:
	var payload := _valid_minimal_payload("2000000004", "壊れたvisibility")
	(payload["draft"] as Dictionary)["challenge_info_visibility"] = ["hp", "atk"]
	_write_raw_payload("2000000004", payload)
	var result := RBMLocalStageRepository.load_stage("2000000004")
	assert_false(bool(result.get("ok", true)))

func test_load_stage_rejects_challenge_info_visibility_with_a_non_bool_value() -> void:
	var payload := _valid_minimal_payload("2000000005", "壊れたvisibility値")
	(payload["draft"] as Dictionary)["challenge_info_visibility"] = {"hp": "yes"}
	_write_raw_payload("2000000005", payload)
	var result := RBMLocalStageRepository.load_stage("2000000005")
	assert_false(bool(result.get("ok", true)), "a non-bool visibility value must be rejected, matching the int()/bool() static-typed-assignment crash risk pattern this file already guards against")

func test_load_stage_accepts_an_empty_challenge_info_visibility_dict() -> void:
	var payload := _valid_minimal_payload("2000000006", "空visibility")
	(payload["draft"] as Dictionary)["challenge_info_visibility"] = {}
	_write_raw_payload("2000000006", payload)
	var result := RBMLocalStageRepository.load_stage("2000000006")
	assert_true(bool(result.get("ok", false)), "an empty (but present) visibility Dictionary is structurally valid -- restore falls back to all-public per key")
