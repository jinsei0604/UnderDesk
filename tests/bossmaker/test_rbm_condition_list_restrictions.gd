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
##
## 2026-10-29 ユーザー確定で、新しく選べる条件は行動・覚醒とも4カテゴリ（11種類）に変わった。旧条件は保存済みの
## データでは消さずに読み込み・判定・表示を続ける（下の「既存データ互換」）。

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
	creator.draft.appearance_id = "appearance_dragon"  # 覚醒を追加できる外見
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _step3(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	var step3 := _step3(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	step3.refresh()
	return step3._advanced_view

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## 2026-10-28: 覚醒は一覧の覚醒の見出しの「＋ 覚醒を追加する」から作る（行動の種類の一覧では選ばない）。
func _open_new_awakening_form(advanced: RBMCreatorStep4ActionPatterns) -> RBMActionEditorForm:
	_btn(advanced, "AddAwakeningButton").pressed.emit()
	return advanced._form

## 2026-10-28: 通常行動の条件は「条件で分岐」のターンの行（行動の詳細）で付ける。
func _open_new_conditional_row(advanced: RBMCreatorStep4ActionPatterns) -> void:
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()

func _select_condition_type(advanced: RBMCreatorStep4ActionPatterns, condition_type: String) -> void:
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._select_condition_type(condition_type)

# ---------------------------------------------------------------------------
# 2026-10-29 ユーザー確定: 新しく選べる条件は4カテゴリ（ボスHP・ターン・攻略側生存人数・特定キャラクターの状態）だけ。
# 行動（条件で分岐の行）と覚醒の両方で、2段階（カテゴリ→比較方法と値）で選ぶ。
# ---------------------------------------------------------------------------

func _flattened_category_types() -> Array:
	var out := []
	for category in RBMActionPatternRules.CONDITION_CATEGORIES:
		out.append_array(category["types"])
	return out

func test_awakening_condition_dropdown_has_exactly_six_items() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_eq(advanced._condition_category_option.item_count, 4, "awakening uses the same four categories")
	var labels := []
	for i in range(advanced._condition_category_option.item_count):
		labels.append(advanced._condition_category_option.get_item_text(i))
	assert_eq(labels, [tr("ボスHP"), tr("ターン"), tr("攻略側生存人数"), tr("特定キャラクターの状態")])

func test_awakening_ui_condition_types_constant_is_exactly_the_confirmed_six() -> void:
	assert_eq(RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES, _flattened_category_types())
	assert_eq(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES, _flattened_category_types())
	assert_eq(_flattened_category_types(), [
		"hp_at_most", "hp_at_least",
		"turn_at", "turn_at_least", "turn_at_most", "turn_every_n",
		"allies_at_most", "allies_at_least", "allies_exactly",
		"character_alive", "character_downed",
	])

func test_awakening_condition_dropdown_excludes_all_removed_types() -> void:
	var removed := ["hp_between", "turn_between", "last_boss_skill", "last_received_skill", "last_received_attribute", "weak_hit"]
	for condition_type in removed:
		assert_false(RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES.has(condition_type), "%s must not be offered for awakening" % condition_type)
		assert_false(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has(condition_type), "%s must not be offered for actions" % condition_type)
		assert_true(RBMActionPatternRules.NORMAL_CONDITION_TYPES.has(condition_type), "%s still loads and evaluates from saved data" % condition_type)

func test_each_category_offers_only_its_own_comparisons() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	var expected := [["以下", "以上"], ["ちょうど", "以降", "まで", "ごと"], ["以下", "以上", "ちょうど"], ["生存", "戦闘不能"]]
	for i in range(4):
		advanced._condition_category_option.select(i)
		advanced._condition_category_option.item_selected.emit(i)
		var texts := []
		for j in range(advanced._condition_compare_option.item_count):
			texts.append(advanced._condition_compare_option.get_item_text(j))
		var want := []
		for label in expected[i]:
			want.append(tr(label))
		assert_eq(texts, want, "category %d" % i)
	assert_eq(advanced._condition_compare_label.text, tr("状態"), "the character category asks for the state")
	assert_true(advanced._condition_character_row.visible)
	assert_true(advanced._condition_character_row.get_index() < advanced._condition_compare_row.get_index(), "キャラクター → 状態 の順")

func test_awakening_hp_at_most_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 30.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "hp_at_most", "percent": 30.0}])

func test_awakening_turn_at_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "turn_at")
	advanced._condition_turn_spin.value = 5
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "turn_at", "turn": 5}])

func test_awakening_allies_at_most_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "allies_at_most")
	advanced._condition_count_spin.value = 2
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], [{"type": "allies_at_most", "count": 2}])

func test_awakening_character_downed_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_select_condition_type(advanced, "character_downed")
	advanced._condition_character_option.select(0)
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	var conditions: Array = creator.draft.awakening["conditions"]
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0]["type"]), "character_downed")
	assert_true(RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(str(conditions[0]["character_id"])))

## 新しく選べなくなった覚醒の旧条件（前回受けたスキル）は、保存済みのボスから消えず、編集して保存し直しても残る。
func test_awakening_last_received_skill_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	var advanced := _open_advanced(creator)
	var old := [{"type": "last_received_skill", "skill_id": str(RBMActionPatternSummary.all_known_ally_skill_ids()[0])}]
	creator.draft.set_awakening({"conditions": old.duplicate(true), "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	var card := advanced.find_child("AwakeningCardButton", true, false) as Control
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	card.gui_input.emit(release)
	assert_eq(advanced._pending_conditions, old, "shown as is")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["conditions"], old, "re-saving keeps it")

## 覚醒の旧条件（前回受けた属性）も、定義の読み込み・戦闘の判定は今までどおり。
func test_awakening_last_received_attribute_can_be_set_and_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.add_turn_action({"mode": "fixed", "entries": [{"skill_id": str(creator.draft.skills[0].get("skill_id", ""))}]})
	creator.draft.set_awakening({"conditions": [{"type": "last_received_attribute", "attribute": "FIRE"}], "condition_logic": "AND", "buff": {}, "heal": {}})
	var result := RBMDefinitionLoader.resolve(creator.draft.to_definition())
	assert_true(bool(result.get("ok", false)), "errors: %s" % [result.get("errors", [])])
	assert_eq((result["boss_def"]["awakening"]["conditions"] as Array)[0]["type"], "last_received_attribute")

# ---------------------------------------------------------------------------
# 行動（条件で分岐の行）
# ---------------------------------------------------------------------------

func test_normal_action_ui_condition_types_excludes_only_turn_between() -> void:
	for condition_type in RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES:
		assert_true(RBMActionPatternRules.NORMAL_CONDITION_TYPES.has(condition_type), "%s is a known (loadable) type" % condition_type)
	assert_eq(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.size(), 11)

func test_normal_action_turn_conditions_retain_the_four_specified_types() -> void:
	for condition_type in ["turn_at", "turn_at_least", "turn_at_most", "turn_every_n"]:
		assert_true(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has(condition_type))

## 「ボスHPが○%〜○%のあいだ」は新しく選べない（以下・以上だけ）。保存済みのデータでは消さない。
func test_normal_action_hp_between_is_retained() -> void:
	assert_false(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has("hp_between"))
	assert_true(RBMActionPatternRules.NORMAL_CONDITION_TYPES.has("hp_between"))

func test_normal_action_condition_dropdown_does_not_offer_turn_between() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_null(advanced.find_child("ConditionTypeOption", true, false), "no long single dropdown")
	assert_eq(advanced._condition_category_option.item_count, 4)
	advanced._select_condition_type("turn_at")
	assert_eq(advanced._condition_compare_option.item_count, 4, "ちょうど・以降・まで・ごと（○〜○のあいだは無い）")

## どの比較方法を選んでも、範囲（下限・上限）の入力欄は出ない（新しい条件の入力欄に範囲は無い）。
func test_normal_action_turn_between_field_never_shows_for_a_newly_selectable_type() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	for condition_type in RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES:
		advanced._select_condition_type(condition_type)
		var visible_rows := 0
		for row in [advanced._condition_percent_row, advanced._condition_turn_row, advanced._condition_n_row, advanced._condition_count_row, advanced._condition_character_row]:
			if (row as Control).visible:
				visible_rows += 1
		assert_eq(visible_rows, 1, "%s shows exactly one value field" % condition_type)
		assert_eq(advanced._pending_conditions[-1].get("type"), condition_type)

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
