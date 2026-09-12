extends GutTest

## RPG BOSS MAKER — STEP3「行動」条件一覧の整理(2026-09-12)の回帰テスト。
##
## 覚醒の「条件の種類」ドロップダウンは確定仕様の6種類だけに絞り、通常攻撃/
## ランダム攻撃側は「○〜○ターンのあいだ」(turn_between)だけを新規選択肢
## から除外する。検証用のRBMActionPatternRules.NORMAL_CONDITION_TYPES
## (RBMDefinitionLoader/RBMBattleが参照する、旧保存データ後方互換のための
## 全17種の一覧)自体は変更していない——UIの「新規に選べる」選択肢だけを
## NORMAL_ACTION_UI_CONDITION_TYPES/AWAKENING_UI_CONDITION_TYPESという別の
## 一覧で絞り込む。

func after_each() -> void:
	await get_tree().process_frame

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _fill_minimum_valid_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "条件整理テストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _step3(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	var step3 := _step3(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3._advanced_view

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _open_new_awakening_form(advanced: RBMCreatorStep4ActionPatterns) -> RBMActionEditorForm:
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var form := advanced._form
	form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING))
	form._on_type_selected(form._type_option.selected)
	return form

func _select_condition_type(advanced: RBMCreatorStep4ActionPatterns, condition_type: String) -> void:
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(advanced._active_condition_types.find(condition_type))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)

# ---------------------------------------------------------------------------
# 覚醒: 6種類のみ
# ---------------------------------------------------------------------------

func test_awakening_condition_dropdown_has_exactly_six_items() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_eq(advanced._condition_type_option.item_count, 6)
	assert_eq(advanced._active_condition_types, RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES)

func test_awakening_ui_condition_types_constant_is_exactly_the_confirmed_six() -> void:
	assert_eq(RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES, [
		"hp_at_most", "turn_at", "allies_at_most", "character_downed",
		"last_received_skill", "last_received_attribute",
	])

func test_awakening_condition_dropdown_excludes_all_removed_types() -> void:
	var removed := [
		"hp_at_least", "hp_between",
		"turn_at_least", "turn_at_most", "turn_every_n", "turn_between",
		"allies_at_least", "allies_exactly",
		"character_alive", "last_boss_skill", "weak_hit",
	]
	for condition_type in removed:
		assert_false(RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES.has(condition_type), "%s must not be offered for awakening" % condition_type)

func test_awakening_hp_at_most_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 30.0
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "hp_at_most", "percent": 30.0}])

func test_awakening_turn_at_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "turn_at")
	advanced._condition_turn_spin.value = 5
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "turn_at", "turn": 5}])

func test_awakening_allies_at_most_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "allies_at_most")
	advanced._condition_count_spin.value = 2
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "allies_at_most", "count": 2}])

func test_awakening_character_downed_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "character_downed")
	advanced._condition_character_option.select(0)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var conditions: Array = creator.draft.awakening["conditions"]
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0]["type"]), "character_downed")
	assert_true(RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(str(conditions[0]["character_id"])))

func test_awakening_last_received_skill_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "last_received_skill")
	advanced._condition_ally_skill_option.select(0)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var conditions: Array = creator.draft.awakening["conditions"]
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0]["type"]), "last_received_skill")
	assert_false(str(conditions[0]["skill_id"]).is_empty())

func test_awakening_last_received_attribute_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "last_received_attribute")
	advanced._condition_attribute_option.select(0)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var conditions: Array = creator.draft.awakening["conditions"]
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0]["type"]), "last_received_attribute")
	assert_true(RBMDefinitionLoader.VALID_ATTRIBUTES.has(str(conditions[0]["attribute"])))

# ---------------------------------------------------------------------------
# 通常攻撃/ランダム攻撃: 「○〜○ターンのあいだ」のみ削除
# ---------------------------------------------------------------------------

func test_normal_action_ui_condition_types_excludes_only_turn_between() -> void:
	assert_false(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has("turn_between"))
	for condition_type in RBMActionPatternRules.NORMAL_CONDITION_TYPES:
		if condition_type == "turn_between":
			continue
		assert_true(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has(condition_type), "%s must still be offered for normal actions" % condition_type)
	assert_eq(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.size(), RBMActionPatternRules.NORMAL_CONDITION_TYPES.size() - 1)

func test_normal_action_turn_conditions_retain_the_four_specified_types() -> void:
	for condition_type in ["turn_at", "turn_at_least", "turn_at_most", "turn_every_n"]:
		assert_true(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has(condition_type))

func test_normal_action_hp_between_is_retained() -> void:
	assert_true(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has("hp_between"), "hp_between (phase control) must stay available for normal actions")

func test_normal_action_condition_dropdown_does_not_offer_turn_between() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_eq(advanced._active_condition_types, RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES)
	assert_false(advanced._active_condition_types.has("turn_between"))
	assert_eq(advanced._condition_type_option.item_count, RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.size())

func test_normal_action_turn_between_field_never_shows_for_a_newly_selectable_type() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	_btn(advanced, "AddConditionButton").pressed.emit()
	# Selecting every still-offered type must never reveal the turn-range row
	# (it was only ever shown for the now-unselectable turn_between).
	for i in range(advanced._condition_type_option.item_count):
		advanced._condition_type_option.select(i)
		advanced._on_condition_type_selected(i)
		assert_false(advanced._condition_turn_range_row.visible, "turn_between's input row must never appear for a newly selected type")

# ---------------------------------------------------------------------------
# 既存データ互換: turn_betweenを含む旧action_sequenceが壊れず読み込める
# ---------------------------------------------------------------------------

func test_loading_an_old_slot_with_turn_between_does_not_crash_and_still_displays() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({
		"kind": "skill", "skill_id": skill_id,
		"conditions": [{"type": "turn_between", "turn_min": 2, "turn_max": 5}],
		"condition_logic": "AND", "max_uses": -1,
	})
	advanced.refresh()
	var summary := RBMActionPatternSummary.slot_summary(creator.draft.action_sequence[0], creator.draft, 0)
	assert_true(str(summary["condition"]).length() > 0, "an old turn_between condition must still render a real summary line, not crash")

func test_old_slot_with_turn_between_still_resolves_and_evaluates_correctly_in_battle() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({
		"kind": "skill", "skill_id": skill_id,
		"conditions": [{"type": "turn_between", "turn_min": 1, "turn_max": 99}],
		"condition_logic": "AND", "max_uses": -1,
	})
	var result := RBMDefinitionLoader.resolve(creator.draft.to_definition())
	assert_true(bool(result.get("ok", false)), "a boss saved with an old turn_between condition must still resolve without error")
