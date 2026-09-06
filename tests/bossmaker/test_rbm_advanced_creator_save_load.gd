extends GutTest

## RPG BOSS MAKER HARDCORE Creator — RBMLocalStageRepositoryのHARDCORE関連
## フィールド（creator_mode/action_sequence/next_slot_ordinal/
## advanced_ai_version）テスト。実プレイヤーのuser://保存ライブラリを一切
## 汚さないよう、test_rbm_local_stage_repository.gdと同じ専用テストディレクトリ
## 差し替えパターンを踏襲する。
##
## 2026-09-05全面再設計に伴い、旧「行動パターン」schema（action_patterns/
## pattern_id/cooldown_turns/trigger_probability/post_instant_behavior）に
## 依存していたテストを新schema（action_sequence/slot_id/max_usesのみ、
## cooldown・発動確率・瞬間発動後という概念は撤去）へ全面移植した。

const TEST_DIR := "user://bossmaker_test_advanced_save/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

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

func _advanced_draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "HARDCOREボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	var skill_id := draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.set_creator_mode("advanced")
	draft.add_action_slot({
		"kind": "random", "mode": "manual",
		"candidates": [{"skill_id": skill_id, "weight": 70.0}, {"skill_id": skill_id, "weight": 30.0}],
		"conditions": [{"type": "hp_at_most", "percent": 50.0}],
		"condition_logic": "AND",
		"max_uses": 3,
	})
	return draft

func test_real_file_round_trip_preserves_creator_mode_and_action_sequence() -> void:
	var draft := _advanced_draft()
	var save_result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(save_result.get("ok", false)))
	var stage_id := str(save_result.get("stage_id", ""))

	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	assert_eq(restored.creator_mode, "advanced")
	assert_eq(restored.action_sequence.size(), 1)
	var slot: Dictionary = restored.action_sequence[0]
	assert_eq(int(slot.get("max_uses", -99)), 3)
	assert_false(slot.has("trigger_probability"), "新schemaにtrigger_probabilityという概念は存在しない")
	assert_false(slot.has("cooldown_turns"), "新schemaにcooldown_turnsという概念は存在しない")
	assert_false(slot.has("post_instant_behavior"), "新schemaに瞬間条件/発動後という概念は存在しない")
	assert_eq(str((slot.get("conditions", []) as Array)[0].get("type", "")), "hp_at_most")

## §17由来「自分で設定」の重みが保存/読込後も保持される（"均等"へ巻き戻らない）
## ——新schemaの実ファイルI/Oを経由した最終確認。
func test_real_file_round_trip_preserves_manual_random_mode_and_weights() -> void:
	var draft := _advanced_draft()
	var save_result := RBMLocalStageRepository.save_new(draft)
	var load_result := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	var slot: Dictionary = restored.action_sequence[0]
	assert_eq(str(slot.get("mode", "")), "manual")
	var candidates: Array = slot.get("candidates", [])
	assert_eq(float(candidates[0].get("weight", -1.0)), 70.0)
	assert_eq(float(candidates[1].get("weight", -1.0)), 30.0)

## 真に古い（HARDCORE概念自体が存在しなかった）保存データを模す:
## creator_mode/action_sequence/next_slot_ordinaryキー自体を取り除く——
## restore_from_saved_dict()が安全な既定値へフォールバックし、SIMPLEとして
## 読み込めることを確認する。
func test_pre_hardcore_saved_stage_without_advanced_fields_loads_as_simple() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "旧ボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	var save_result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(save_result.get("stage_id", ""))

	var raw_load := RBMLocalStageRepository.load_stage(stage_id)
	var draft_data: Dictionary = raw_load.get("draft_data", {})
	draft_data.erase("creator_mode")
	draft_data.erase("action_sequence")
	draft_data.erase("next_slot_ordinal")
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(draft_data)
	assert_eq(restored.creator_mode, "simple")
	assert_true(restored.action_sequence.is_empty())

# ---------------------------------------------------------------------------
# 壊れた保存データの防御的拒否
# ---------------------------------------------------------------------------

func _write_raw_stage(stage_id: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEST_DIR, stage_id], FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func _minimal_valid_payload(stage_id: String) -> Dictionary:
	return {
		"save_format_version": 1,
		"stage_id": stage_id,
		"created_unix_time": 0,
		"updated_unix_time": 0,
		"draft": {},
		"clear_check_success_snapshot": {},
	}

func test_action_sequence_with_wrong_top_level_type_is_rejected() -> void:
	var payload := _minimal_valid_payload("1111111111")
	(payload["draft"] as Dictionary)["action_sequence"] = "not an array"
	_write_raw_stage("1111111111", payload)
	var result := RBMLocalStageRepository.load_stage("1111111111")
	assert_false(bool(result.get("ok", false)))

func test_action_sequence_entry_with_wrong_conditions_type_is_rejected() -> void:
	var payload := _minimal_valid_payload("2222222222")
	(payload["draft"] as Dictionary)["action_sequence"] = [
		{"slot_id": "s1", "kind": "skill", "skill_id": "boss_skill_1", "conditions": "not an array"},
	]
	_write_raw_stage("2222222222", payload)
	var result := RBMLocalStageRepository.load_stage("2222222222")
	assert_false(bool(result.get("ok", false)))

func test_action_sequence_condition_with_wrong_field_type_is_rejected() -> void:
	var payload := _minimal_valid_payload("3333333333")
	(payload["draft"] as Dictionary)["action_sequence"] = [
		{"slot_id": "s1", "kind": "skill", "skill_id": "boss_skill_1", "conditions": [{"type": "hp_at_most", "percent": "fifty"}]},
	]
	_write_raw_stage("3333333333", payload)
	var result := RBMLocalStageRepository.load_stage("3333333333")
	assert_false(bool(result.get("ok", false)))

func test_action_sequence_random_slot_with_malformed_candidate_is_rejected() -> void:
	var payload := _minimal_valid_payload("4444444444")
	(payload["draft"] as Dictionary)["action_sequence"] = [
		{"slot_id": "s1", "kind": "random", "candidates": ["not_a_dict"]},
	]
	_write_raw_stage("4444444444", payload)
	var result := RBMLocalStageRepository.load_stage("4444444444")
	assert_false(bool(result.get("ok", false)))

func test_well_formed_action_sequence_is_accepted_even_with_unfamiliar_condition_type() -> void:
	# §31/将来のPhase拡張への配慮: 型さえ正しければ、未知の条件タイプ文字列
	# 自体をRepository層は拒否しない（意味validationはRBMDefinitionLoaderの
	# 責務——ここで拒否すると、将来条件タイプが追加された時に旧バージョンの
	# Repositoryコードが新しいstageを誤って壊れているとみなしかねない）。
	var payload := _minimal_valid_payload("5555555555")
	(payload["draft"] as Dictionary)["action_sequence"] = [
		{"slot_id": "s1", "kind": "skill", "skill_id": "s1_skill", "conditions": [{"type": "some_future_condition_type", "percent": 10.0}]},
	]
	_write_raw_stage("5555555555", payload)
	var result := RBMLocalStageRepository.load_stage("5555555555")
	assert_true(bool(result.get("ok", false)))

func test_creator_mode_with_wrong_type_is_rejected() -> void:
	var payload := _minimal_valid_payload("6666666666")
	(payload["draft"] as Dictionary)["creator_mode"] = 123
	_write_raw_stage("6666666666", payload)
	var result := RBMLocalStageRepository.load_stage("6666666666")
	assert_false(bool(result.get("ok", false)))

func test_action_sequence_entry_with_wrong_max_uses_type_is_rejected() -> void:
	var payload := _minimal_valid_payload("7777777777")
	(payload["draft"] as Dictionary)["action_sequence"] = [
		{"slot_id": "s1", "kind": "skill", "skill_id": "s1_skill", "max_uses": "three"},
	]
	_write_raw_stage("7777777777", payload)
	var result := RBMLocalStageRepository.load_stage("7777777777")
	assert_false(bool(result.get("ok", false)))

## §22確定: 旧「行動パターン」仕様（advanced_ai_version==1）で保存された
## HARDCOREデータは、Repository層自身の最終防衛線として明示的に拒否される
## ——test_rbm_advanced_codex_review_fixes.gd:test_stage_with_old_pre_
## redesign_advanced_ai_version_is_rejectedがDraft/Repository両層を通した
## より高レベルの確認を担う一方、ここではRepository.load_stage()自身の
## 直接呼び出しでこの防御線をピンポイントに確認する（このファイルの
## スコープである「保存/読込」層そのものへの直接的な回帰ガード）。
func test_old_pre_redesign_advanced_ai_version_is_rejected_at_repository_level() -> void:
	var payload := _minimal_valid_payload("8888888888")
	(payload["draft"] as Dictionary)["advanced_ai_version"] = 1
	_write_raw_stage("8888888888", payload)
	var result := RBMLocalStageRepository.load_stage("8888888888")
	assert_false(bool(result.get("ok", false)))
