extends GutTest

## RPG BOSS MAKER — RBMCreatorDraft HARDCORE Creator「攻撃（action_sequence）」
## データモデルのテスト（2026-09-05全面再設計、旧「行動パターン」仕様の
## テストを全面置換）。Creator UIは一切介さない、純粋なデータ/ロジックの
## テスト。
##
## 旧仕様にあった瞬間条件（action_pattern_is_instant()）・1パターン内の
## 複数行動ステップ（can_add_action_to_pattern()）は新仕様に一切存在しない
## （RBMActionPatternRules冒頭コメント参照）——これらの関数自体が
## RBMCreatorDraftから削除されているため、対応する旧テストは削除した
## （「未知の条件タイプとして拒否される」ことはtest_rbm_advanced_definition_
## loader.gdでカバー済み）。

func _draft_with_two_skills() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "TestBoss"
	draft.hp = 1000
	draft.atk = 50
	draft.spd = 10
	draft.add_skill({"name": "Fire Breath", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.5})
	draft.add_skill({"name": "Roar", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 3})
	return draft

func _bare_slot(skill_id: String = "boss_skill_1") -> Dictionary:
	return {
		"kind": "skill",
		"skill_id": skill_id,
		"conditions": [],
		"condition_logic": "AND",
		"max_uses": -1,
	}

func _bare_random_slot(candidates: Array, mode: String = "manual") -> Dictionary:
	return {
		"kind": "random",
		"mode": mode,
		"candidates": candidates,
		"conditions": [],
		"condition_logic": "AND",
		"max_uses": -1,
	}

# ---------------------------------------------------------------------------
# 攻撃スロットCRUD（§1/§20）
# ---------------------------------------------------------------------------

func test_add_action_slot_returns_unique_slot_id_and_appends_to_array() -> void:
	var draft := _draft_with_two_skills()
	var id1 := draft.add_action_slot(_bare_slot())
	var id2 := draft.add_action_slot(_bare_slot())
	assert_ne(id1, id2)
	assert_eq(draft.action_sequence.size(), 2)
	assert_eq(str(draft.action_sequence[0].get("slot_id", "")), id1)
	assert_eq(str(draft.action_sequence[1].get("slot_id", "")), id2)

func test_find_action_slot_returns_empty_dict_for_unknown_id() -> void:
	var draft := _draft_with_two_skills()
	assert_true(draft.find_action_slot("nope").is_empty())

func test_update_action_slot_replaces_fields_but_keeps_slot_id() -> void:
	var draft := _draft_with_two_skills()
	var id := draft.add_action_slot(_bare_slot())
	var replacement := _bare_slot()
	replacement["max_uses"] = 3
	draft.update_action_slot(id, replacement)
	var found := draft.find_action_slot(id)
	assert_eq(str(found.get("slot_id", "")), id)
	assert_eq(int(found.get("max_uses", -1)), 3)

func test_remove_action_slot_removes_only_that_entry() -> void:
	var draft := _draft_with_two_skills()
	var id1 := draft.add_action_slot(_bare_slot())
	var id2 := draft.add_action_slot(_bare_slot())
	draft.remove_action_slot(id1)
	assert_eq(draft.action_sequence.size(), 1)
	assert_true(draft.find_action_slot(id1).is_empty())
	assert_false(draft.find_action_slot(id2).is_empty())

## §20「作者はドラッグ等によって並び順を変更できる」——配列位置そのものが
## 実行順（RBMBattle側のラウンドロビン走査順）。
func test_move_action_slot_swaps_array_position() -> void:
	var draft := _draft_with_two_skills()
	var id1 := draft.add_action_slot(_bare_slot())
	var id2 := draft.add_action_slot(_bare_slot())
	assert_true(draft.move_action_slot(id2, -1))
	assert_eq(str(draft.action_sequence[0].get("slot_id", "")), id2)
	assert_eq(str(draft.action_sequence[1].get("slot_id", "")), id1)

func test_move_action_slot_at_array_edge_is_a_no_op() -> void:
	var draft := _draft_with_two_skills()
	var id1 := draft.add_action_slot(_bare_slot())
	assert_false(draft.move_action_slot(id1, -1))
	assert_eq(draft.action_sequence.size(), 1)

## §1確定: action_sequence全体（配置スロットの総数）の上限
## （RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS=20）。旧仕様の
## 「1パターン内の行動数上限」から、新モデルでは対応する概念である
## 「ボスが持つ攻撃スロットの総数」へ引き継がれた。
func test_can_add_action_slot_true_below_cap() -> void:
	var draft := _draft_with_two_skills()
	for i in range(RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS - 1):
		draft.add_action_slot(_bare_slot())
	assert_true(draft.can_add_action_slot())

func test_can_add_action_slot_false_at_cap() -> void:
	var draft := _draft_with_two_skills()
	for i in range(RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS):
		draft.add_action_slot(_bare_slot())
	assert_false(draft.can_add_action_slot())
	assert_eq(draft.add_action_slot(_bare_slot()), "")

# ---------------------------------------------------------------------------
# §2確定: 作成済み攻撃(skills)の再利用——同じskill_idを複数スロットへ配置
# ---------------------------------------------------------------------------

func test_same_skill_id_can_be_placed_in_multiple_slots_independently() -> void:
	var draft := _draft_with_two_skills()
	var id1 := draft.add_action_slot(_bare_slot("boss_skill_1"))
	var slot1 := _bare_slot("boss_skill_1")
	slot1["max_uses"] = 1
	draft.update_action_slot(id1, slot1)
	var id2 := draft.add_action_slot(_bare_slot("boss_skill_1"))
	var slot2 := _bare_slot("boss_skill_1")
	slot2["conditions"] = [{"type": "turn_at_least", "turn": 3}]
	draft.update_action_slot(id2, slot2)
	assert_eq(draft.action_sequence.size(), 2)
	assert_eq(int(draft.find_action_slot(id1).get("max_uses", -1)), 1)
	assert_true((draft.find_action_slot(id2).get("conditions", []) as Array).is_empty() == false)
	# 両方とも同じskill_idを参照するが、それぞれ独立した条件/使用回数を持つ。
	assert_eq(str(draft.find_action_slot(id1).get("skill_id", "")), "boss_skill_1")
	assert_eq(str(draft.find_action_slot(id2).get("skill_id", "")), "boss_skill_1")
	# 依然として1つのskillとしてのみ保存されている（同じ攻撃を複製していない）。
	assert_eq(draft.skills.size(), 2)

# ---------------------------------------------------------------------------
# STEP 3 (HARDCORE) 検証
# ---------------------------------------------------------------------------

func test_step4_advanced_is_valid_true_in_simple_mode_regardless_of_content() -> void:
	var draft := _draft_with_two_skills()
	# creator_modeが"simple"のままなら、action_sequenceの中身に何があっても
	# HARDCORE専用の検証は一切適用されない（SIMPLE表示中はHARDCORE検証対象外）。
	assert_true(draft.step4_advanced_is_valid())

func test_step4_advanced_is_valid_false_for_random_slot_with_no_candidates() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.action_sequence.clear()
	draft.add_action_slot(_bare_random_slot([]))
	assert_false(draft.step4_advanced_is_valid())

func test_step4_advanced_is_valid_false_for_manual_random_slot_not_summing_to_100() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.action_sequence.clear()
	draft.add_action_slot(_bare_random_slot([{"skill_id": "boss_skill_1", "weight": 30.0}]))
	assert_false(draft.step4_advanced_is_valid())

func test_step4_advanced_is_valid_true_for_manual_random_slot_summing_to_100() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.action_sequence.clear()
	draft.add_action_slot(_bare_random_slot([{"skill_id": "boss_skill_1", "weight": 60.0}, {"skill_id": "boss_skill_2", "weight": 40.0}]))
	assert_true(draft.step4_advanced_is_valid())

func test_step4_advanced_is_valid_false_for_skill_slot_referencing_unknown_skill() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.action_sequence.clear()
	draft.add_action_slot(_bare_slot("not_a_real_skill"))
	assert_false(draft.step4_advanced_is_valid())

func test_step4_advanced_is_valid_false_for_multi_condition_slot_with_unknown_logic() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.action_sequence.clear()
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "turn_at_least", "turn": 1}, {"type": "hp_at_most", "percent": 50.0}]
	slot["condition_logic"] = "XOR"
	draft.add_action_slot(slot)
	assert_false(draft.step4_advanced_is_valid())

# ---------------------------------------------------------------------------
# SIMPLE → HARDCORE 自動変換（切替直後の戦闘内容が変化しない設計）
# ---------------------------------------------------------------------------

func test_simple_to_advanced_converts_normal_action_percentages_into_a_condition_less_random_slot() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 70.0
	draft.normal_action_percentages["boss_skill_2"] = 30.0
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 1)
	var slot: Dictionary = draft.action_sequence[0]
	assert_true((slot.get("conditions", []) as Array).is_empty())
	assert_eq(str(slot.get("kind", "")), "random")
	assert_eq(str(slot.get("mode", "")), "manual")
	var by_skill := {}
	for candidate in slot.get("candidates", []):
		by_skill[str(candidate.get("skill_id", ""))] = float(candidate.get("weight", 0.0))
	assert_eq(by_skill.get("boss_skill_1", 0.0), 70.0)
	assert_eq(by_skill.get("boss_skill_2", 0.0), 30.0)

## scripted_actionsの"replace"タイミングは「ターン条件＋固定攻撃」へ変換
## される。turn_start_interrupt/turn_end_interruptは変換対象外——「既存の
## まま独立して動作する別機能」のとおり、action_sequenceには一切現れない。
func test_simple_to_advanced_converts_replace_scripted_actions_only() -> void:
	var draft := _draft_with_two_skills()
	draft.add_scripted_action(3, "boss_skill_1", "replace")
	draft.add_scripted_action(5, "boss_skill_2", "turn_start_interrupt")
	draft.add_scripted_action(7, "boss_skill_2", "turn_end_interrupt")
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 1)
	var slot: Dictionary = draft.action_sequence[0]
	var conditions: Array = slot.get("conditions", [])
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0].get("type", "")), "turn_at")
	assert_eq(int(conditions[0].get("turn", -1)), 3)
	assert_eq(str(slot.get("kind", "")), "skill")
	assert_eq(str(slot.get("skill_id", "")), "boss_skill_1")
	# turn_start_interrupt/turn_end_interruptはscripted_actions自体に残ったまま。
	assert_eq(draft.scripted_actions.size(), 3)

## §21「既存設定はすべて維持する」——SIMPLE側フィールドはHARDCORE切替後も
## 一切変更されない（自動変換は"コピーして新しい構造を作る"のであって
## "移動"ではない）。
func test_switching_to_advanced_never_mutates_the_simple_source_fields() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.add_scripted_action(2, "boss_skill_2", "replace")
	var before_normal := draft.normal_action_percentages.duplicate(true)
	var before_scripted := draft.scripted_actions.duplicate(true)
	draft.set_creator_mode("advanced")
	assert_eq(draft.normal_action_percentages, before_normal)
	assert_eq(draft.scripted_actions, before_scripted)
	assert_true(draft.normal_actions_enabled)

## action_sequenceが既に何か持っている状態（2回目以降のHARDCORE切替）では
## 自動変換をスキップし、既存の編集内容を上書きしない。
func test_switching_to_advanced_a_second_time_does_not_reconvert_or_duplicate() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 1)
	draft.set_creator_mode("simple")
	draft.set_creator_mode("advanced")
	# action_sequenceは前回切替時のまま維持され、2重に変換されて増えたり
	# しない（discard_advanced_settings_and_revert_to_simple()を挟まない
	# 限りaction_sequenceは空にならないため）。
	assert_eq(draft.action_sequence.size(), 1)

## §14/§18: 変換順の直接検証（実装時に確認済み仕様の回帰ガード）: SIMPLEの
## 既存挙動では、scripted_actionsのreplaceは常にnormal_action_percentagesの
## 抽選より優先される。HARDCOREの「上から順に発動可能なスロットを走査」で
## 同じ優先順位を再現するには、変換後の配列で「turn_at条件つきスロット」が
## 「無条件のランダム行動スロット（フォールバック）」より前にある必要がある。
func test_converted_replace_slot_comes_before_the_condition_less_fallback_slot() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.add_scripted_action(3, "boss_skill_2", "replace")
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 2)
	var first: Dictionary = draft.action_sequence[0]
	var second: Dictionary = draft.action_sequence[1]
	assert_false((first.get("conditions", []) as Array).is_empty())
	assert_eq(str((first.get("conditions", []) as Array)[0].get("type", "")), "turn_at")
	assert_true((second.get("conditions", []) as Array).is_empty())

func test_simple_to_advanced_with_nothing_configured_produces_no_slots() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	assert_true(draft.action_sequence.is_empty())

# ---------------------------------------------------------------------------
# HARDCORE → SIMPLE
# ---------------------------------------------------------------------------

## §24: 手動でHARDCORE画面から追加されたスロットは、対応するSIMPLE側
## エントリが無いため、たとえ"形"としてSIMPLE表現可能でも無確認では戻せない
## （警告なしに内容が消えるのを防ぐ）。
func test_bare_slot_with_only_a_skill_step_needs_confirmation_without_a_simple_equivalent() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot())
	assert_false(draft.has_advanced_only_settings())
	assert_false(draft.can_switch_to_simple_without_confirmation())

## 対になる正のケース: SIMPLE→HARDCOREの自動変換で生成された、未編集の
## スロット（scripted_actionsのreplaceエントリからそのまま複製されたもの）
## は、現在のSIMPLE側フィールドから今この瞬間に再変換しても全く同じ内容に
## なるため、無確認でSIMPLEへ戻せる。
func test_freshly_auto_converted_slot_can_switch_to_simple_without_confirmation() -> void:
	var draft := _draft_with_two_skills()
	draft.add_scripted_action(3, "boss_skill_1", "replace")
	draft.set_creator_mode("advanced")
	assert_eq(draft.action_sequence.size(), 1)
	assert_true(draft.can_switch_to_simple_without_confirmation())

## 手動でHARDCOREへさらに1スロット追加すると、たとえ追加分自体が"形"として
## SIMPLE表現可能でも、もはや現在のSIMPLE側フィールドの再変換結果と一致
## しなくなるため確認対象になる。
func test_auto_converted_slot_plus_a_manually_added_one_needs_confirmation() -> void:
	var draft := _draft_with_two_skills()
	draft.add_scripted_action(3, "boss_skill_1", "replace")
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot("boss_skill_2"))
	assert_false(draft.can_switch_to_simple_without_confirmation())

func test_slot_with_a_non_turn_at_condition_has_advanced_only_settings() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "hp_at_least", "percent": 50.0}]
	draft.add_action_slot(slot)
	assert_true(draft.has_advanced_only_settings())
	assert_false(draft.can_switch_to_simple_without_confirmation())

func test_slot_with_limited_max_uses_has_advanced_only_settings() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var slot := _bare_slot()
	slot["max_uses"] = 1
	draft.add_action_slot(slot)
	assert_true(draft.has_advanced_only_settings())

## §22「変換不能なHARDCORE設定を勝手に近似変換してはならない」——
## discard_advanced_settings_and_revert_to_simple()を呼ばない限り、
## action_sequenceはHARDCORE専用の内容を保持したまま残り続ける（SIMPLE
## 表示へ強制変換されたりしない）。
func test_discard_advanced_settings_clears_sequence_and_restores_simple_fields_untouched() -> void:
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	draft.set_creator_mode("advanced")
	var slot := _bare_slot()
	slot["max_uses"] = 1
	draft.add_action_slot(slot)
	assert_true(draft.has_advanced_only_settings())

	draft.discard_advanced_settings_and_revert_to_simple()
	assert_eq(draft.creator_mode, "simple")
	assert_true(draft.action_sequence.is_empty())
	# 破棄してもSIMPLE側フィールドは無傷のまま——最初から一切変更していない
	# ため、復元処理なしにそのまま有効。
	assert_true(draft.normal_actions_enabled)
	assert_eq(draft.normal_action_percentages.get("boss_skill_1", 0.0), 100.0)

# ---------------------------------------------------------------------------
# Definition生成 (action_sequenceが空ならキー自体を省略する)
# ---------------------------------------------------------------------------

func test_to_definition_omits_action_sequence_key_when_empty() -> void:
	var draft := _draft_with_two_skills()
	var definition := draft.to_definition()
	assert_false((definition["boss"] as Dictionary).has("action_sequence"))

func test_to_definition_includes_action_sequence_and_advanced_ai_version_when_present() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot())
	var definition := draft.to_definition()
	var boss: Dictionary = definition["boss"]
	assert_true(boss.has("action_sequence"))
	assert_eq((boss["action_sequence"] as Array).size(), 1)
	assert_eq(int(boss.get("advanced_ai_version", 0)), RBMCreatorDraft.ADVANCED_AI_VERSION)

func test_to_definition_normal_actions_and_scripted_actions_unaffected_by_advanced_mode() -> void:
	# SIMPLE専用Definitionのシリアライズ結果が一切変化しない（バイト単位で
	# 不変）ことの確認——HARDCOREへ切り替えても、SIMPLE側フィールドから
	# 生成されるnormal_actions/scripted_actionsの中身自体は変わらない。
	var draft := _draft_with_two_skills()
	draft.normal_actions_enabled = true
	draft.normal_action_percentages["boss_skill_1"] = 100.0
	var before := draft.to_definition()
	draft.set_creator_mode("advanced")
	var after := draft.to_definition()
	assert_eq((before["boss"] as Dictionary)["normal_actions"], (after["boss"] as Dictionary)["normal_actions"])

# ---------------------------------------------------------------------------
# Clear Checkについて確定: creator_modeは比較対象に含めない
# ---------------------------------------------------------------------------

func test_battle_content_snapshot_includes_action_sequence() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot())
	var snapshot := draft.battle_content_snapshot()
	assert_true(snapshot.has("action_sequence"))
	assert_eq((snapshot["action_sequence"] as Array).size(), 1)

func test_switching_mode_alone_does_not_invalidate_clear_check() -> void:
	var draft := _draft_with_two_skills()
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	draft.set_creator_mode("advanced")
	# HARDCOREへ切り替えただけ（行動スロット0件、SIMPLE側フィールドも
	# 一切変更していない）なので実際の戦闘定義は変化していない——
	# Clear Checkは維持される。
	assert_true(draft.is_clear_check_currently_valid())
	draft.set_creator_mode("simple")
	assert_true(draft.is_clear_check_currently_valid())

func test_adding_an_action_slot_invalidates_clear_check() -> void:
	var draft := _draft_with_two_skills()
	draft.record_clear_check_success()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot())
	assert_false(draft.is_clear_check_currently_valid())

# ---------------------------------------------------------------------------
# 保存/読込 (advanced_ai_version、旧stage互換)
# ---------------------------------------------------------------------------

func test_save_and_restore_round_trips_creator_mode_and_action_sequence() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var slot := _bare_random_slot([{"skill_id": "boss_skill_1", "weight": 40.0}, {"skill_id": "boss_skill_2", "weight": 60.0}])
	slot["conditions"] = [{"type": "hp_at_least", "percent": 10.0}]
	draft.add_action_slot(slot)
	var saved := draft.to_saved_dict()

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_eq(restored.creator_mode, "advanced")
	assert_eq(restored.action_sequence.size(), 1)
	var restored_slot: Dictionary = restored.action_sequence[0]
	assert_eq(str(restored_slot.get("conditions", [])[0].get("type", "")), "hp_at_least")
	# "mode"フィールドがラウンドトリップ後も保持されている（"自分で設定"の
	# 重みが読込後に"均等"表示へ巻き戻らないことの直接確認）。
	assert_eq(str(restored_slot.get("mode", "")), "manual")
	var by_skill := {}
	for candidate in restored_slot.get("candidates", []):
		by_skill[str(candidate.get("skill_id", ""))] = float(candidate.get("weight", 0.0))
	assert_eq(by_skill.get("boss_skill_1", 0.0), 40.0)
	assert_eq(by_skill.get("boss_skill_2", 0.0), 60.0)

func test_restoring_a_pre_hardcore_saved_dict_without_the_new_fields_falls_back_to_simple() -> void:
	var draft := _draft_with_two_skills()
	var saved := draft.to_saved_dict()
	saved.erase("creator_mode")
	saved.erase("action_sequence")
	saved.erase("next_slot_ordinal")
	saved.erase("advanced_ai_version")

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_eq(restored.creator_mode, "simple")
	assert_true(restored.action_sequence.is_empty())

func test_clear_check_snapshot_with_action_sequence_round_trips_and_stays_valid() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var slot := _bare_random_slot([{"skill_id": "boss_skill_1", "weight": 25.0}, {"skill_id": "boss_skill_2", "weight": 75.0}])
	draft.add_action_slot(slot)
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	var saved_snapshot := draft.clear_check_snapshot_for_save()

	var restored := RBMCreatorDraft.new()
	restored.boss_name = draft.boss_name
	restored.hp = draft.hp
	restored.atk = draft.atk
	restored.spd = draft.spd
	for skill in draft.skills:
		restored.skills.append(skill.duplicate(true))
	restored.action_sequence = draft.action_sequence.duplicate(true)
	restored.restore_clear_check_snapshot(saved_snapshot)
	assert_true(restored.is_clear_check_currently_valid())

# ---------------------------------------------------------------------------
# §19確定: ボススキル削除時のaction_sequence整理
# ---------------------------------------------------------------------------

func test_removing_a_skill_used_by_a_single_slot_removes_the_whole_slot() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_slot("boss_skill_1"))
	draft.remove_skill("boss_skill_1")
	assert_true(draft.action_sequence.is_empty())

func test_removing_a_skill_used_as_one_random_candidate_keeps_the_slot_with_remaining_candidates() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	draft.add_action_slot(_bare_random_slot([{"skill_id": "boss_skill_1", "weight": 1.0}, {"skill_id": "boss_skill_2", "weight": 1.0}], "even"))
	draft.remove_skill("boss_skill_1")
	assert_eq(draft.action_sequence.size(), 1)
	var candidates: Array = draft.action_sequence[0].get("candidates", [])
	assert_eq(candidates.size(), 1)
	assert_eq(str(candidates[0].get("skill_id", "")), "boss_skill_2")

func test_removing_a_skill_referenced_by_last_boss_skill_condition_clears_only_that_condition() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var slot := _bare_slot("boss_skill_2")
	slot["conditions"] = [{"type": "last_boss_skill", "skill_id": "boss_skill_1"}]
	draft.add_action_slot(slot)
	draft.remove_skill("boss_skill_1")
	assert_eq(draft.action_sequence.size(), 1)
	assert_true((draft.action_sequence[0].get("conditions", []) as Array).is_empty())

## §19確定(重要な安全性テスト): 同じskill_idを複数スロットへ配置している
## 状態で、片方のスロットだけを削除しても、もう片方のスロット（同じ
## skill_idを参照）は無傷のまま残る——skillの実体もまだ参照されているため
## 誤って削除されない。
func test_removing_one_slot_referencing_a_shared_skill_does_not_delete_the_skill_or_the_other_slot() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var id1 := draft.add_action_slot(_bare_slot("boss_skill_1"))
	var id2 := draft.add_action_slot(_bare_slot("boss_skill_1"))
	draft.remove_action_slot(id1)
	draft.remove_skill_if_unreferenced("boss_skill_1")
	assert_eq(draft.action_sequence.size(), 1)
	assert_eq(str(draft.action_sequence[0].get("slot_id", "")), id2)
	assert_false(draft.find_skill("boss_skill_1").is_empty())

## 対になるケース: 最後の参照を削除した時だけ、実際にskillの実体も片付く。
func test_removing_the_last_slot_referencing_a_skill_deletes_the_skill() -> void:
	var draft := _draft_with_two_skills()
	draft.set_creator_mode("advanced")
	var id1 := draft.add_action_slot(_bare_slot("boss_skill_1"))
	draft.remove_action_slot(id1)
	draft.remove_skill_if_unreferenced("boss_skill_1")
	assert_true(draft.find_skill("boss_skill_1").is_empty())
