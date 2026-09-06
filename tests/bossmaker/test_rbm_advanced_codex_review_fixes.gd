extends GutTest

## RPG BOSS MAKER — Codex最終差分レビュー指摘対応（①〜③・⑤〜⑥・⑦.7・⑦.9・⑩）
## の再発防止テスト（2026-09-05全面再設計、旧「行動パターン」仕様の
## テストを全面置換）。各セクション番号はCodexレポートの番号にそのまま
## 対応する——旧④（異種瞬間イベントの順序）・⑦.1〜⑦.6・⑦.8（瞬間条件/
## post_instant_behavior/複数ステップ連続実行前提）は、対応する機能自体が
## 新仕様に一切存在しないため削除した（RBMActionPatternRules冒頭コメント
## 参照）。
##
## Draft層のテストはtest_rbm_advanced_creator_draft.gdと同じ規約
## （_draft_with_two_skills()/_bare_slot()相当）、Battle層のテストは
## test_rbm_advanced_battle.gdと同じ規約（_ally_def()/_party_defs()/
## _skill_slot()/_random_slot()/_boss_with_sequence()/_resolve_one_ally_
## turn()/_play_full_round()/_boss_log_entries()）を、それぞれ自己完結する
## 形で踏襲する（このプロジェクト既存の「各テストファイルは小さな共通
## ヘルパーを継承ではなく複製して持つ」規約どおり）。

const ATTACK := {"type": "attack"}
const DEFEND := {"type": "defend"}

# ---------------------------------------------------------------------------
# 共有ヘルパー（Draft層）
# ---------------------------------------------------------------------------

func _draft_with_two_skills() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "TestBoss"
	draft.hp = 1000
	draft.atk = 50
	draft.spd = 10
	draft.add_skill({"name": "Fire Breath", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.5})
	draft.add_skill({"name": "Roar", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 3})
	return draft

# ---------------------------------------------------------------------------
# 共有ヘルパー（Battle層）
# ---------------------------------------------------------------------------

func _ally_def(character_id: String, atk_override: int = -1) -> Dictionary:
	var def := RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % character_id)
	if atk_override >= 0:
		def["atk"] = atk_override
	return def

func _party_defs(character_ids: Array, atk_override: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for character_id in character_ids:
		out.append(_ally_def(character_id, atk_override))
	return out

func _skill_slot(slot_id: String, skill_id: String, conditions: Array = [], condition_logic: String = "AND", max_uses: int = -1) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": "skill",
		"skill_id": skill_id,
		"conditions": conditions,
		"condition_logic": condition_logic,
		"max_uses": max_uses,
	}

func _random_slot(slot_id: String, candidates: Array, conditions: Array = [], condition_logic: String = "AND", max_uses: int = -1) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": "random",
		"candidates": candidates,
		"conditions": conditions,
		"condition_logic": condition_logic,
		"max_uses": max_uses,
	}

func _boss_skills() -> Array:
	return [
		{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_hit2", "display_name": "Hit2", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_aoe", "display_name": "AoE", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 50},
		{"id": "boss_buff", "display_name": "Buff", "effect": "buff_atk_self", "buff_multiplier": 2.0, "duration_turns": 3},
	]

func _boss_with_sequence(sequence: Array, hp: int = 1000, atk: int = 1, spd: int = 10) -> Dictionary:
	return {
		"id": "adv_boss", "display_name": "AdvBoss", "hp": hp, "atk": atk, "spd": spd,
		"skills": _boss_skills(),
		"normal_action_candidates": [],
		"action_sequence": sequence,
	}

func _resolve_one_ally_turn(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	log.append_array(battle.advance_to_next_decision())
	if battle.battle_over or not battle.is_waiting_for_ally_action():
		return log
	log.append_array(battle.resolve_pending_ally_action(action))
	log.append_array(battle.advance_to_next_decision())
	return log

func _play_full_round(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	var start_turn := battle.current_turn
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn:
			return log
		if not battle.is_waiting_for_ally_action():
			return log
		log.append_array(battle.resolve_pending_ally_action(action))
	return log  # 到達しない — GDScriptの静的チェッカー向けの形式的なフォールバックのみ。

func _boss_log_entries(log: Array) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(entry)
	return out

# ---------------------------------------------------------------------------
# 共有ヘルパー（Repository層、実ファイルI/O）
# ---------------------------------------------------------------------------

const TEST_DIR := "user://bossmaker_test_codex_review/stages"

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

# ---------------------------------------------------------------------------
# ① SIMPLE→HARDCORE 同一ターン複数replaceの変換（2026-09-05再設計で
# 構造が変化した——旧仕様は「1つの連続行動パターンへ集約」だったが、
# 新HARDCORE仕様は「1ターン＝1スロット」原則（§18）のため、同一ターンの
# 複数replaceはそれぞれ独立したturn_at付きスロットへ変換される。
# ---------------------------------------------------------------------------

func test_same_turn_multiple_replace_entries_convert_into_separate_turn_at_slots() -> void:
	var draft := _draft_with_two_skills()
	draft.add_scripted_action(3, "boss_skill_1", "replace")
	draft.add_scripted_action(3, "boss_skill_2", "replace")
	draft.add_scripted_action(3, "boss_skill_1", "replace")
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 3, "同一ターンの3件のreplaceは、それぞれ独立したturn_at付きスロットへ変換される")
	for slot in draft.action_sequence:
		var conditions: Array = slot.get("conditions", [])
		assert_eq(conditions.size(), 1)
		assert_eq(str(conditions[0].get("type", "")), "turn_at")
		assert_eq(int(conditions[0].get("turn", -1)), 3)
	assert_eq(str(draft.action_sequence[0].get("skill_id", "")), "boss_skill_1")
	assert_eq(str(draft.action_sequence[1].get("skill_id", "")), "boss_skill_2")
	assert_eq(str(draft.action_sequence[2].get("skill_id", "")), "boss_skill_1")

## 実装時に確認済みの構造的制約（RBMCreatorDraft._prospective_simple_
## conversion_authoring_slots()のコメント参照、報告書に記載）: SIMPLEの
## "replace"は同一ターンの全件が常にそのターン内で連続実行されるが、
## HARDCORE変換後は走査順で最初にマッチしたスロットだけがそのターンに
## 発動し、残りは同じturn_at条件を持ったまま二度とそのターン番号へ戻らない
## ため以後永久に発動しない——これは実装のバグではなく、新しいラウンド
## ロビン実行モデル自体の帰結。
func test_simple_and_hardcore_diverge_for_same_turn_multi_replace_only_the_first_slot_ever_fires() -> void:
	var draft := _draft_with_two_skills()
	draft.hp = 100000
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.add_scripted_action(1, "boss_skill_1", "replace")
	draft.add_scripted_action(1, "boss_skill_2", "replace")
	var simple_definition := draft.to_definition()
	assert_false(simple_definition["boss"].has("action_sequence"))

	draft.set_creator_mode("advanced")
	var advanced_definition := draft.to_definition()
	assert_true(advanced_definition["boss"].has("action_sequence"))

	var simple_result := RBMDefinitionLoader.start_battle(simple_definition, 42)
	var advanced_result := RBMDefinitionLoader.start_battle(advanced_definition, 42)
	assert_true(bool(simple_result.get("ok", false)), "errors: %s" % str(simple_result.get("errors", [])))
	assert_true(bool(advanced_result.get("ok", false)), "errors: %s" % str(advanced_result.get("errors", [])))
	var simple_battle: RBMBattle = simple_result["battle"]
	var advanced_battle: RBMBattle = advanced_result["battle"]

	var simple_log := _play_full_round(simple_battle, ATTACK)
	var advanced_log := _play_full_round(advanced_battle, ATTACK)

	var simple_boss_skills: Array = []
	for entry in _boss_log_entries(simple_log):
		if entry.has("skill_id"):
			simple_boss_skills.append(str(entry.get("skill_id", "")))
	var advanced_boss_skills: Array = []
	for entry in _boss_log_entries(advanced_log):
		if entry.has("skill_id"):
			advanced_boss_skills.append(str(entry.get("skill_id", "")))

	# SIMPLEは"replace"の全件をそのターン内で連続実行する既存挙動のまま
	# （SIMPLE側は無改修）。
	assert_eq(simple_boss_skills, ["boss_skill_1", "boss_skill_2"])
	# HARDCOREは1ターン1スロット原則のため、変換直後は走査順で最初に
	# マッチするスロット(boss_skill_1)だけが発動する。
	assert_eq(advanced_boss_skills, ["boss_skill_1"], "新HARDCORE仕様では、変換直後の同一ターン内で複数replaceの2件目以降は発動しない——SIMPLE→HARDCORE変換の構造的な非対称性(意図的な仕様上の制約、報告書に記載)")

# ---------------------------------------------------------------------------
# ② HARDCORE→SIMPLEでaction_sequenceを裏側に残さない
# ---------------------------------------------------------------------------

func test_switching_back_to_simple_without_confirmation_actually_drives_real_battle_via_simple_fields() -> void:
	var draft := _draft_with_two_skills()
	draft.hp = 500
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.add_scripted_action(1, "boss_skill_1", "replace")
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 1)
	assert_true(draft.can_switch_to_simple_without_confirmation())
	draft.set_creator_mode("simple")
	assert_true(draft.action_sequence.is_empty(), "action_sequenceが裏側に残っていない")

	var definition := draft.to_definition()
	assert_false(definition["boss"].has("action_sequence"), "SIMPLE状態のDefinitionはaction_sequenceを一切持たない")
	var result := RBMDefinitionLoader.start_battle(definition, 7)
	assert_true(bool(result.get("ok", false)))
	var battle: RBMBattle = result["battle"]
	var log := _play_full_round(battle, ATTACK)
	var boss_entries := _boss_log_entries(log)
	assert_eq(boss_entries.size(), 1)
	assert_eq(str(boss_entries[0].get("skill_id", "")), "boss_skill_1", "SIMPLE側フィールド(scripted_actions replace)が実戦へ反映されている——HARDCORE側は裏で作用していない")

# ---------------------------------------------------------------------------
# ③ Clear Check snapshot正規化
# ---------------------------------------------------------------------------

func test_clear_check_survives_simple_to_advanced_switch_with_normal_action_percentages() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	draft.set_creator_mode("advanced")
	assert_true(draft.is_clear_check_currently_valid(), "normal_action_percentagesケース: SIMPLE→HARDCOREのみでClear Checkが維持される")

func test_clear_check_survives_simple_to_advanced_switch_with_scripted_replace() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	draft.add_scripted_action(2, "boss_skill_1", "replace")
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	draft.set_creator_mode("advanced")
	assert_true(draft.is_clear_check_currently_valid(), "scripted replaceケース: SIMPLE→HARDCOREのみでClear Checkが維持される")

func test_clear_check_survives_simple_to_advanced_switch_with_same_turn_multiple_replace() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	draft.add_scripted_action(2, "boss_skill_1", "replace")
	draft.add_scripted_action(2, "boss_skill_2", "replace")
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	draft.set_creator_mode("advanced")
	assert_true(draft.is_clear_check_currently_valid(), "同一ターン複数replaceケース: SIMPLE→HARDCOREのみでClear Checkが維持される")

func test_clear_check_invalidated_by_advanced_only_addition_then_restored_by_removal() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	draft.add_scripted_action(2, "boss_skill_1", "replace")
	draft.record_clear_check_success()
	draft.set_creator_mode("advanced")
	assert_true(draft.is_clear_check_currently_valid())
	var extra_id: String = draft.add_action_slot({
		"kind": "skill",
		"skill_id": "boss_skill_2",
		"conditions": [{"type": "hp_at_most", "percent": 50.0}],
		"condition_logic": "AND",
		"max_uses": -1,
	})
	assert_false(draft.is_clear_check_currently_valid(), "HARDCORE独自設定を追加すると失効する")
	draft.remove_action_slot(extra_id)
	assert_true(draft.is_clear_check_currently_valid(), "A->B->A: 元へ完全に戻せば復元される")

# ---------------------------------------------------------------------------
# ⑤ 前回のボス行動履歴を全ボス行動で更新
# ---------------------------------------------------------------------------

func test_turn_start_interrupt_updates_last_boss_skill_history() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "last_boss_skill", "skill_id": "boss_buff"}]),
		_skill_slot("b", "boss_hit2"),
	])
	boss_def["scripted_actions"] = [{"turn": 1, "skill_id": "boss_buff", "timing": "turn_start_interrupt", "order": 1}]
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	var boss_entries := _boss_log_entries(log)
	# turn_start_interrupt(boss_buff) -> 通常行動選択時点で「前回のボス行動 =
	# boss_buff」が既に成立しているため、aが採用される。
	var normal_turn_entry: Dictionary = boss_entries[boss_entries.size() - 1]
	assert_eq(str(normal_turn_entry.get("skill_id", "")), "boss_hit", "turn_start_interruptで使用したスキルが「前回のボス行動」として認識される")

func test_turn_end_interrupt_updates_last_boss_skill_history_for_the_next_turns_check() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),  # turn1だけ1回。
	])
	boss_def["scripted_actions"] = [{"turn": 1, "skill_id": "boss_buff", "timing": "turn_end_interrupt", "order": 1}]
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	_play_full_round(battle, DEFEND)  # turn1: 通常行動(boss_hit, 使い切り) -> turn_end_interrupt(boss_buff)。
	assert_true(battle._boss_has_acted)
	assert_eq(battle._boss_last_used_skill_id, "boss_buff", "turn_end_interruptで使用したスキルが「前回のボス行動」として次ターンの判定まで残る")

# ---------------------------------------------------------------------------
# ⑥ advanced_ai_version保存・検証
# ---------------------------------------------------------------------------

func test_advanced_ai_version_is_written_on_new_save() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	var saved := draft.to_saved_dict()
	assert_eq(int(saved.get("advanced_ai_version", -1)), RBMCreatorDraft.ADVANCED_AI_VERSION)

func test_advanced_ai_version_round_trips_through_real_save_and_load() -> void:
	var draft := _draft_with_two_skills()
	draft.add_party_character("hero")
	var save_result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(save_result.get("ok", false)))
	var stage_id := str(save_result.get("stage_id", ""))
	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	var draft_data: Dictionary = load_result.get("draft_data", {})
	assert_eq(int(draft_data.get("advanced_ai_version", -1)), RBMCreatorDraft.ADVANCED_AI_VERSION, "保存->読込を経てもversionが維持される")

func test_stage_without_advanced_ai_version_field_loads_as_v1_compatible() -> void:
	var payload := _minimal_valid_payload("1111111111")
	# advanced_ai_versionフィールド自体が存在しない(この仕様以前の旧stage)。
	_write_raw_stage("1111111111", payload)
	var result := RBMLocalStageRepository.load_stage("1111111111")
	assert_true(bool(result.get("ok", false)), "フィールド欠落はv1互換として正常に受理される")

func test_stage_with_current_advanced_ai_version_is_accepted() -> void:
	var payload := _minimal_valid_payload("2222222222")
	(payload["draft"] as Dictionary)["advanced_ai_version"] = RBMCreatorDraft.ADVANCED_AI_VERSION
	_write_raw_stage("2222222222", payload)
	var result := RBMLocalStageRepository.load_stage("2222222222")
	assert_true(bool(result.get("ok", false)))

## §22確定: 2026-09-05の全面再設計でADVANCED_AI_VERSIONを1→2へ引き上げた
## ため、旧version(1、旧action_patterns形式)のHARDCORE保存データは
## このチェックにより読込時に丸ごと拒否される（自動変換しない、ユーザー
## 確定仕様）。
func test_stage_with_old_pre_redesign_advanced_ai_version_is_rejected() -> void:
	var payload := _minimal_valid_payload("5555555555")
	(payload["draft"] as Dictionary)["advanced_ai_version"] = 1
	_write_raw_stage("5555555555", payload)
	var result := RBMLocalStageRepository.load_stage("5555555555")
	assert_false(bool(result.get("ok", false)), "旧「行動パターン」仕様(version=1)のHARDCORE保存データは自動変換せず拒否される")

func test_stage_with_unknown_advanced_ai_version_is_rejected() -> void:
	var payload := _minimal_valid_payload("3333333333")
	(payload["draft"] as Dictionary)["advanced_ai_version"] = RBMCreatorDraft.ADVANCED_AI_VERSION + 99
	_write_raw_stage("3333333333", payload)
	var result := RBMLocalStageRepository.load_stage("3333333333")
	assert_false(bool(result.get("ok", false)), "未知バージョンは黙って現行版として解釈せず拒否される")

func test_stage_with_non_numeric_advanced_ai_version_is_rejected() -> void:
	var payload := _minimal_valid_payload("4444444444")
	(payload["draft"] as Dictionary)["advanced_ai_version"] = "not_a_number"
	_write_raw_stage("4444444444", payload)
	var result := RBMLocalStageRepository.load_stage("4444444444")
	assert_false(bool(result.get("ok", false)))

# ---------------------------------------------------------------------------
# ⑦.7 使用回数: unlimited/1回/N回、新しい戦闘セッションでのリセット
# ---------------------------------------------------------------------------

func test_max_uses_unlimited_fires_every_eligible_turn() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", -1),
	], 1000, 1, 1)
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	for i in range(5):
		var log := _play_full_round(battle, DEFEND)
		var boss_entries := _boss_log_entries(log)
		assert_eq(boss_entries.size(), 1)
		assert_eq(str(boss_entries[0].get("skill_id", "")), "boss_hit")

func test_max_uses_one_fires_once_then_falls_back() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),
		_skill_slot("b", "boss_hit2"),
	], 1000, 1, 1)
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log1 := _play_full_round(battle, DEFEND)
	assert_eq(str(_boss_log_entries(log1)[0].get("skill_id", "")), "boss_hit")
	for i in range(3):
		var log_n := _play_full_round(battle, DEFEND)
		assert_eq(str(_boss_log_entries(log_n)[0].get("skill_id", "")), "boss_hit2", "1回使い切った後はフォールバックのみ")

## ラウンドロビン方式の性質上（§14/§15確定）、発動に成功したスロットの
## 次から走査が再開されるため、「aの後に常に成立するフォールバックbが
## 続く」構成だとaが使用回数を使い切る前にbへカーソルが移ってしまい、
## aへ二度と一周して戻らない——これは実装のバグではなく新方式の直接的な
## 帰結（このセクション冒頭のtest_condition_failure_skips_to_the_next_
## eligible_slot...と同じ原理）。使用回数だけを単独で検証するため、ここは
## 意図的にスロット1つだけの構成にする（フォールバックが無ければ毎ターン
## 必ずカーソル0から同じスロットを再評価するため、使用回数のゲートだけを
## 素直に観測できる）。
func test_max_uses_n_fires_exactly_n_times_then_does_nothing_afterward() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 3),
	], 1000, 1, 1)
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	for i in range(3):
		var log_n := _play_full_round(battle, DEFEND)
		assert_eq(str(_boss_log_entries(log_n)[0].get("skill_id", "")), "boss_hit", "%d回目はまだ使用回数内" % (i + 1))
	var log4 := _play_full_round(battle, DEFEND)
	assert_eq(str(_boss_log_entries(log4)[0].get("action", "")), "none", "4回目は使用回数上限を超え、他に代替スロットが無いため何もしない")

func test_use_counts_reset_on_a_new_battle_session() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),
		_skill_slot("b", "boss_hit2"),
	], 1000, 1, 1)
	var battle1 := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	_play_full_round(battle1, DEFEND)
	var log2 := _play_full_round(battle1, DEFEND)
	assert_eq(str(_boss_log_entries(log2)[0].get("skill_id", "")), "boss_hit2", "sanity: 1戦闘目では既に使い切っている")

	var battle2 := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log1_new := _play_full_round(battle2, DEFEND)
	assert_eq(str(_boss_log_entries(log1_new)[0].get("skill_id", "")), "boss_hit", "新しい戦闘セッション(TEST BATTLE/Clear Check/CHALLENGEそれぞれ独立したRBMBattleインスタンス)では使用回数がリセットされている")

# ---------------------------------------------------------------------------
# ⑦.9 ランダム再抽選: 結果が保存・共有されず、セッションごとに独立して抽選される
# ---------------------------------------------------------------------------

func test_random_slot_choice_is_freshly_redrawn_per_session_not_memoized_or_shared() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 50.0}, {"skill_id": "boss_hit2", "weight": 50.0}]),
	], 1000, 1, 1)
	var random_slot: Dictionary = boss_def["action_sequence"][0]
	assert_true(random_slot.has("candidates"))
	assert_false(random_slot.has("result"), "引いた結果自体はDefinition/保存データへ一切記録しない")
	assert_false(random_slot.has("chosen"))
	assert_false(random_slot.has("last_pick"))

	var picks := {}
	for seed in range(1, 30):
		var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, seed)
		var log := _play_full_round(battle, DEFEND)
		var picked := str(_boss_log_entries(log)[0].get("skill_id", ""))
		picks[picked] = true
	assert_true(picks.has("boss_hit") and picks.has("boss_hit2"), "十分な数の独立したseedを試せば両方の候補が実際に選ばれる——結果が固定/共有されていない直接証拠")

# ---------------------------------------------------------------------------
# ⑩ SIMPLEのランダム通知
# ---------------------------------------------------------------------------

func test_random_action_notice_shown_for_simple_mode_with_two_or_more_weighted_skills() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 50.0
	draft.normal_action_percentages["boss_skill_2"] = 50.0
	assert_true(draft.has_random_action_variance(), "SIMPLEでも複数候補の通常行動抽選があれば通知対象")

func test_random_action_notice_hidden_for_simple_mode_with_a_single_weighted_skill() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.normal_action_percentages["boss_skill_2"] = 0.0
	assert_false(draft.has_random_action_variance(), "候補が実質1つしかなければ結果は常に同じ——通知不要")

func test_random_action_notice_hidden_for_simple_mode_when_normal_actions_disabled() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = false
	draft.normal_action_percentages["boss_skill_1"] = 50.0
	draft.normal_action_percentages["boss_skill_2"] = 50.0
	assert_false(draft.has_random_action_variance(), "通常行動自体が無効なら実際には抽選が起きない")
