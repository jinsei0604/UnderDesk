extends GutTest

## RPG BOSS MAKER — STEP3「条件をつける」UIの即時反映化(内側の「追加する」/
## 「キャンセル」廃止)の回帰テスト。
##
## 「＋ 条件をつける」を押した時点で条件が下書きへ作られ、種類/数値/AND-OR等の
## 変更はすべて即時に反映される。外側の「保存」だけが確定手段で、外側の
## 「キャンセル」だけが破棄手段。条件UIは通常/単体・全体攻撃、ランダム攻撃、
## 自己回復、ATK自己強化、覚醒のすべてで同じ共有ブロックを使うため、各アクション
## 種別ごとに同じ操作(条件をつける→値を変える→外側の保存だけ)で条件が保存
## され、開き直しても復元されることを確認する。
##
## 2026-10-28: HARDCORE の行動の画面を作り直した（ターンごとの通常行動、ユーザー確定）。条件は「条件で分岐」の
## ターンの行（③ 行動の詳細）と覚醒で付ける。外側の保存＝行動の詳細の「保存」、draft へ書くのはターンの保存
## （_save() が「それ以外」を選んでターンを保存するところまで行う）。ランダム攻撃の条件は廃止（条件と使用率は
## 同じターンで組み合わせない）。

func after_each() -> void:
	await get_tree().process_frame

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _fill_minimum_valid_boss(creator: RBMCreatorMain, with_skill: bool = true) -> void:
	creator.draft.boss_name = "条件即時反映テストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.appearance_id = "appearance_dragon"  # 覚醒を追加できる外見
	if with_skill:
		creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	step3.refresh()
	return step3._advanced_view

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

## ターンを足して「条件で分岐」にし、条件の行の追加の方法を開く。
func _open_conditional_turn(advanced: RBMCreatorStep4ActionPatterns) -> void:
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()

## 外側の保存: 行動の詳細の「保存」。ターンの行なら「それ以外」を既存の行動から選び、ターンを保存して draft へ書く。
## 保存が止まった時（行動の詳細に残る）は何もしない。
func _save(advanced: RBMCreatorStep4ActionPatterns) -> void:
	var was_awakening := advanced._entry_context == "awakening"
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	if was_awakening or not advanced._turn_view.visible:
		return
	if str(advanced._pending_turn.get("else_skill_id", "")).is_empty():
		_click(advanced, "TurnElseCard")
		_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
		_click(advanced, "PickExistingSkillCard_0")
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()

func _cancel(advanced: RBMCreatorStep4ActionPatterns) -> void:
	_btn(advanced, "EntryCancelButton").pressed.emit()

## 保存したターンの最初の条件の行を開き直す。
func _reopen(advanced: RBMCreatorStep4ActionPatterns) -> void:
	if advanced._turn_view.visible:
		_btn(advanced, "TurnCancelButton").pressed.emit()
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")

func _saved_entry(creator: RBMCreatorMain) -> Dictionary:
	if creator.draft.turn_actions.is_empty():
		return {}
	return creator.draft.turn_actions[0]["entries"][0]

func _saved_conditions(creator: RBMCreatorMain) -> Array:
	return _saved_entry(creator).get("conditions", [])

func _saved_skill_id(creator: RBMCreatorMain) -> String:
	return str(_saved_entry(creator).get("skill_id", ""))

## 行動を新しく作る（覚醒は覚醒の見出しの「＋ 覚醒を追加する」）。行動名と種類(と、攻撃の場合は対象)を選ぶ。
func _start_new_action(advanced: RBMCreatorStep4ActionPatterns, type_id: String, target_all: bool = false) -> void:
	if type_id == RBMActionEditorForm.AWAKENING:
		_btn(advanced, "AddAwakeningButton").pressed.emit()
		return
	_open_conditional_turn(advanced)
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var form: RBMActionEditorForm = advanced._form
	form._name_edit.text = "条件テスト行動"
	form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(type_id))
	form._on_type_selected(form._type_option.selected)
	if type_id == RBMActionEditorForm.ATTACK:
		form._attack_target_option.select(1 if target_all else 0)

## 「条件の種類」を2段階（カテゴリ→比較方法）で選ぶ(ユーザー操作と同じくitem_selectedを発火させる。2026-10-29)。
func _select_condition_type(advanced: RBMCreatorStep4ActionPatterns, condition_type: String) -> void:
	assert_true(RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES.has(condition_type), "%s must be selectable" % condition_type)
	advanced._select_condition_type(condition_type)
	assert_eq(advanced._selected_condition_type(), condition_type)

func _add_condition(advanced: RBMCreatorStep4ActionPatterns, condition_type: String) -> void:
	_btn(advanced, "AddConditionButton").pressed.emit()
	_select_condition_type(advanced, condition_type)

func _row_label_text(advanced: RBMCreatorStep4ActionPatterns, index: int) -> String:
	var row: Node = advanced._condition_list.find_child("ConditionRow_%d" % index, true, false)
	assert_not_null(row, "ConditionRow_%d must exist" % index)
	return (row.get_child(0) as Label).text

# ---------------------------------------------------------------------------
# 内側の「追加する」「キャンセル」が条件UIに残っていない
# ---------------------------------------------------------------------------

func test_no_inner_confirm_or_cancel_buttons_remain_in_the_condition_ui() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_btn(advanced, "AddConditionButton").pressed.emit()

	assert_null(advanced.find_child("ConfirmConditionButton", true, false))
	assert_null(advanced.find_child("CancelConditionButton", true, false))
	var plain_buttons: Array[Button] = []
	for node in advanced._condition_editor.find_children("*", "Button", true, false):
		if node is OptionButton:
			continue  # 種類/キャラクター等のドロップダウンは入力欄であって確定ボタンではない
		plain_buttons.append(node as Button)
		assert_ne((node as Button).text, tr("追加する"), "no 「追加する」 button inside the condition editor")
		assert_ne((node as Button).text, tr("キャンセル"), "no inner cancel button inside the condition editor")
	assert_eq(plain_buttons.size(), 0, "the condition editor holds only inputs, no buttons")

# ---------------------------------------------------------------------------
# 「＋ 条件をつける」で即座に下書きへ作られ、入力変更が即時反映される
# ---------------------------------------------------------------------------

func test_pressing_add_condition_creates_the_condition_immediately() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	assert_eq(advanced._pending_conditions.size(), 0)

	_btn(advanced, "AddConditionButton").pressed.emit()

	assert_true(advanced._condition_editor.visible)
	assert_eq(advanced._pending_conditions.size(), 1)
	assert_eq(str(advanced._pending_conditions[0].get("type", "")), "hp_at_most")
	assert_eq(advanced._condition_list.get_child_count(), 1, "the new condition is listed right away")

func test_type_and_value_changes_are_reflected_without_any_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_btn(advanced, "AddConditionButton").pressed.emit()

	advanced._condition_percent_spin.value = 35.0
	assert_eq(float(advanced._pending_conditions[0].get("percent", -1.0)), 35.0)

	_select_condition_type(advanced, "turn_at")
	assert_eq(advanced._pending_conditions.size(), 1, "changing the type edits the same condition, it does not add another")
	assert_eq(str(advanced._pending_conditions[0].get("type", "")), "turn_at")
	assert_false(advanced._pending_conditions[0].has("percent"), "the previous type's fields are gone")

	advanced._condition_turn_spin.value = 8.0
	assert_eq(int(advanced._pending_conditions[0].get("turn", -1)), 8)
	assert_true(_row_label_text(advanced, 0).contains("8"), "the list label follows the edit: %s" % _row_label_text(advanced, 0))

func test_condition_editor_starts_from_defaults_for_each_new_condition() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "turn_at")
	advanced._condition_turn_spin.value = 9.0

	_btn(advanced, "AddConditionButton").pressed.emit()

	assert_eq(advanced._pending_conditions.size(), 2)
	assert_eq(str(advanced._pending_conditions[1].get("type", "")), "hp_at_most", "a new condition starts from the first type")
	assert_eq(int(advanced._pending_conditions[0].get("turn", -1)), 9, "the earlier condition keeps its own value")
	assert_eq(advanced._condition_turn_spin.value, advanced._condition_turn_spin.min_value, "stale input is not carried into the new condition")

# ---------------------------------------------------------------------------
# 全アクション種別: 条件をつける→値を変える→外側の保存だけ→開き直して復元
# ---------------------------------------------------------------------------

func _assert_condition_saved_and_restored(creator: RBMCreatorMain, advanced: RBMCreatorStep4ActionPatterns, label: String) -> void:
	_add_condition(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 25.0
	_select_condition_type(advanced, "turn_at")
	advanced._condition_turn_spin.value = 6.0
	## 「追加する」は押さない——外側の保存だけ。
	_save(advanced)

	assert_eq(creator.draft.turn_actions.size(), 1, "%s: slot saved" % label)
	var slot := _saved_entry(creator)
	assert_eq(slot.get("conditions", []), [{"type": "turn_at", "turn": 6}], "%s: the displayed condition is exactly what was saved" % label)

	_reopen(advanced)
	assert_eq(advanced._pending_conditions, [{"type": "turn_at", "turn": 6}], "%s: restored on reopen" % label)
	assert_true(_row_label_text(advanced, 0).contains("6"), "%s: restored row is displayed" % label)
	assert_false(advanced._condition_editor.visible, "%s: reopening does not leave a stale editor open" % label)
	_cancel(advanced)

func test_single_attack_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK, false)
	_assert_condition_saved_and_restored(creator, advanced, "単体攻撃")
	assert_eq(str(creator.draft.find_skill(_saved_skill_id(creator)).get("target", "")), "single")

func test_all_attack_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK, true)
	_assert_condition_saved_and_restored(creator, advanced, "全体攻撃")
	assert_eq(str(creator.draft.find_skill(_saved_skill_id(creator)).get("target", "")), "all")

func test_self_heal_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.SELF_HEAL)
	_assert_condition_saved_and_restored(creator, advanced, "HP回復")
	assert_eq(str(creator.draft.find_skill(_saved_skill_id(creator)).get("type", "")), "self_heal")

func test_self_buff_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATK_SELF_BUFF)
	_assert_condition_saved_and_restored(creator, advanced, "自己強化")
	assert_eq(str(creator.draft.find_skill(_saved_skill_id(creator)).get("type", "")), "atk_self_buff")

func test_existing_skill_pick_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_conditional_turn(advanced)
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	_assert_condition_saved_and_restored(creator, advanced, "既存の行動から選ぶ")

## 条件と使用率は同じターンで組み合わせない（2026-10-28）: 使用率で抽選する候補・「それ以外」の行には条件の入力が無い。
func test_random_turn_candidates_and_the_otherwise_row_offer_no_conditions() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	assert_false(advanced._condition_block.visible, "random: no conditions")
	assert_true(advanced._weight_block.visible, "random: usage rate instead")
	_cancel(advanced)
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_click(advanced, "TurnElseCard")
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	assert_false(advanced._condition_block.visible, "otherwise: no conditions")
	assert_false(advanced._weight_block.visible)

func test_awakening_condition_saves_without_add_button_and_restores() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.AWAKENING)
	_add_condition(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 20.0
	_select_condition_type(advanced, "turn_at")
	advanced._condition_turn_spin.value = 4.0
	_save(advanced)

	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening["conditions"], [{"type": "turn_at", "turn": 4}])

	_click(advanced, "AwakeningCardButton")
	assert_eq(advanced._pending_conditions, [{"type": "turn_at", "turn": 4}], "awakening: restored on reopen")
	assert_false(advanced._condition_editor.visible)
	_cancel(advanced)

func test_every_condition_type_offered_for_normal_actions_saves_what_is_displayed() -> void:
	for condition_type in RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES:
		var creator := _new_creator()
		_fill_minimum_valid_boss(creator)
		var advanced := _open_advanced(creator)
		_start_new_action(advanced, RBMActionEditorForm.ATTACK)
		_add_condition(advanced, condition_type)
		var shown := advanced._pending_conditions.duplicate(true)
		assert_eq(shown.size(), 1, condition_type)
		assert_eq(str(shown[0].get("type", "")), condition_type)
		assert_eq(creator.draft.condition_problem(shown[0]), "", "%s: the default values of every type are complete" % condition_type)

		_save(advanced)
		assert_eq(creator.draft.turn_actions.size(), 1, condition_type)
		assert_eq(_saved_conditions(creator), shown, "%s: saved exactly as shown" % condition_type)

func test_every_condition_type_offered_for_awakening_saves_what_is_displayed() -> void:
	for condition_type in RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES:
		var creator := _new_creator()
		_fill_minimum_valid_boss(creator)
		var advanced := _open_advanced(creator)
		_start_new_action(advanced, RBMActionEditorForm.AWAKENING)
		_add_condition(advanced, condition_type)
		var shown := advanced._pending_conditions.duplicate(true)
		assert_eq(shown.size(), 1, condition_type)
		_save(advanced)
		assert_true(creator.draft.has_awakening(), condition_type)
		assert_eq(creator.draft.awakening["conditions"], shown, "%s: saved exactly as shown" % condition_type)

# ---------------------------------------------------------------------------
# 削除 / 外側キャンセル / AND-OR / 複数条件
# ---------------------------------------------------------------------------

func test_deleting_a_condition_still_works_and_keeps_the_editor_bound_correctly() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 10.0
	_add_condition(advanced, "turn_at")
	advanced._condition_turn_spin.value = 5.0
	assert_eq(advanced._pending_conditions.size(), 2)

	## エディタが紐付いている2件目より前(1件目)を削除 → 紐付きは詰まり、以後の
	## 編集は残った条件(元の2件目)へ効く。
	_btn(advanced, "RemoveConditionButton_0").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 1)
	assert_eq(str(advanced._pending_conditions[0].get("type", "")), "turn_at")
	advanced._condition_turn_spin.value = 7.0
	assert_eq(advanced._pending_conditions, [{"type": "turn_at", "turn": 7}])

	## 紐付いている条件そのものを削除 → エディタは閉じ、以後の入力は何も作らない。
	_btn(advanced, "RemoveConditionButton_0").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 0)
	assert_false(advanced._condition_editor.visible)
	advanced._condition_turn_spin.value = 9.0
	assert_eq(advanced._pending_conditions.size(), 0, "input after the bound condition was deleted must not resurrect it")

	## 条件で分岐の行は条件が1つ以上必要（2026-10-28）: 条件を全部消したままでは保存できず、理由を出す。
	_save(advanced)
	assert_true(advanced._entry_view.visible, "stays on the detail screen")
	assert_true(creator.draft.turn_actions.is_empty())
	assert_true((advanced.find_child("EntryErrorLabel", true, false) as Label).visible)

func test_deleting_an_earlier_saved_condition_persists_after_save() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "hp_at_most")
	_add_condition(advanced, "turn_at")
	_save(advanced)
	assert_eq((_saved_conditions(creator) as Array).size(), 2)

	_reopen(advanced)
	_btn(advanced, "RemoveConditionButton_0").pressed.emit()
	_save(advanced)
	assert_eq(_saved_conditions(creator), [{"type": "turn_at", "turn": 1}])

func test_outer_cancel_discards_conditions_created_this_session_for_a_new_action() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skills_before := creator.draft.skills.size()
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "turn_at")
	advanced._condition_turn_spin.value = 3.0
	assert_eq(advanced._pending_conditions.size(), 1)

	_cancel(advanced)

	assert_true(creator.draft.turn_actions.is_empty(), "nothing was written to the draft")
	assert_eq(creator.draft.skills.size(), skills_before)
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 0, "a fresh session starts without the cancelled condition")
	assert_false(advanced._condition_editor.visible)

func test_outer_cancel_restores_the_saved_conditions_of_an_existing_action() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "turn_at")
	advanced._condition_turn_spin.value = 4.0
	_save(advanced)
	var saved: Array = (_saved_conditions(creator) as Array).duplicate(true)

	_reopen(advanced)
	_add_condition(advanced, "hp_at_most")
	_btn(advanced, "RemoveConditionButton_0").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 1, "edited in the session")
	_cancel(advanced)

	assert_eq(_saved_conditions(creator), saved, "cancel leaves the saved conditions untouched")

func test_outer_cancel_discards_conditions_for_saved_rows_and_awakening_too() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": skill_id, "conditions": [{"type": "turn_at", "turn": 2}], "condition_logic": "AND"}], "else_skill_id": skill_id})
	advanced.refresh()
	_reopen(advanced)
	_add_condition(advanced, "hp_at_most")
	_cancel(advanced)
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(_saved_conditions(creator), [{"type": "turn_at", "turn": 2}], "row: cancel discards")

	_start_new_action(advanced, RBMActionEditorForm.AWAKENING)
	_add_condition(advanced, "turn_at")
	_cancel(advanced)
	assert_false(creator.draft.has_awakening(), "awakening: cancel discards")

func test_and_or_logic_and_multiple_conditions_are_saved_as_displayed() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "hp_at_most")
	advanced._condition_percent_spin.value = 60.0
	assert_false(advanced._condition_logic_option.visible, "AND/OR only appears from the second condition")
	_add_condition(advanced, "turn_at_least")
	advanced._condition_turn_spin.value = 3.0
	_add_condition(advanced, "allies_at_most")
	advanced._condition_count_spin.value = 1.0
	assert_true(advanced._condition_logic_option.visible)

	var or_index: int = RBMActionPatternRules.CONDITION_LOGIC_TYPES.find("OR")
	advanced._condition_logic_option.select(or_index)
	advanced._condition_logic_option.item_selected.emit(or_index)
	_save(advanced)

	var slot := _saved_entry(creator)
	assert_eq(str(slot.get("condition_logic", "")), "OR")
	assert_eq(slot.get("conditions", []), [
		{"type": "hp_at_most", "percent": 60.0},
		{"type": "turn_at_least", "turn": 3},
		{"type": "allies_at_most", "count": 1},
	])

	_reopen(advanced)
	assert_eq(advanced._pending_condition_logic, "OR")
	assert_eq(advanced._condition_logic_option.selected, or_index, "the AND/OR choice is restored")
	assert_eq(advanced._pending_conditions.size(), 3)

## 2026-10-29: 「前回使った行動」は新しく選べなくなった。同じ観点（選んだ値がすぐ条件に入る）を「特定キャラクター」で確かめる。
func test_last_boss_skill_condition_follows_the_dropdown_selection_immediately() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "character_downed")
	var ids: Array = RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys()
	assert_eq(str(advanced._pending_conditions[0].get("character_id", "")), str(ids[0]))

	advanced._condition_character_option.select(1)
	advanced._condition_character_option.item_selected.emit(1)
	assert_eq(str(advanced._pending_conditions[0].get("character_id", "")), str(ids[1]))

	_save(advanced)
	assert_eq(_saved_conditions(creator), [{"type": "character_downed", "character_id": str(ids[1])}])

# ---------------------------------------------------------------------------
# 必須値が未設定のまま保存できない(黙って保存しない)
# ---------------------------------------------------------------------------

func test_condition_missing_a_required_value_blocks_the_outer_save_and_explains_why() -> void:
	## 必須の値が欠けた条件は、黙って捨てたり保存したりせず、保存を止めて理由を出す
	## （入力欄では欠けないので、欠けた状態を直接作って確かめる）。
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, false)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.ATTACK)
	_add_condition(advanced, "hp_at_most")
	advanced._pending_conditions[0].erase("percent")
	advanced._rebuild_condition_list()
	assert_true(advanced._condition_error_label.visible, "the problem is shown next to the condition")
	assert_false(advanced._condition_error_label.text.is_empty())

	_save(advanced)

	assert_true(creator.draft.turn_actions.is_empty(), "the slot is not saved")
	assert_true(creator.draft.skills.is_empty(), "the new action itself is not created either")
	assert_true(advanced._entry_view.visible, "the user stays on the editor to fix it")

	## 直せば保存できる。
	_select_condition_type(advanced, "turn_at")
	assert_false(advanced._condition_error_label.visible)
	_save(advanced)
	assert_eq(creator.draft.turn_actions.size(), 1)
	assert_eq(_saved_conditions(creator), [{"type": "turn_at", "turn": 1}])

## 2026-10-29: 「ボスHPの範囲」は新しく選べないが、保存済みのデータの条件は消さずに残る。壊れた範囲なら保存を止め、
## 作者がその条件を消して選び直せば保存できる（黙って消したり変えたりしない）。
func test_hp_between_with_an_inverted_range_blocks_save_until_fixed() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": skill_id, "conditions": [{"type": "hp_between", "percent_min": 60.0, "percent_max": 40.0}], "condition_logic": "AND"}], "else_skill_id": skill_id})
	advanced.refresh()
	_reopen(advanced)
	assert_eq(advanced._pending_conditions, [{"type": "hp_between", "percent_min": 60.0, "percent_max": 40.0}], "the old condition is shown, not dropped")
	assert_true(advanced._condition_error_label.visible)
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(advanced._entry_view.visible, "not saved")

	_btn(advanced, "RemoveConditionButton_0").pressed.emit()
	_add_condition(advanced, "hp_at_least")
	advanced._condition_percent_spin.value = 80.0
	assert_false(advanced._condition_error_label.visible)
	_save(advanced)
	assert_eq(_saved_conditions(creator), [{"type": "hp_at_least", "percent": 80.0}])

## 保存済みの旧条件（新しく選べない種類）は、行を開いて別の条件を足して保存しても黙って消えない。
func test_old_conditions_in_saved_data_survive_editing_the_row() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var old := [{"type": "last_boss_skill", "skill_id": skill_id}, {"type": "weak_hit"}]
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": skill_id, "conditions": old.duplicate(true), "condition_logic": "OR"}], "else_skill_id": skill_id})
	advanced.refresh()
	_reopen(advanced)
	_add_condition(advanced, "turn_at_least")
	advanced._condition_turn_spin.value = 3.0
	_save(advanced)
	assert_eq(_saved_conditions(creator), old + [{"type": "turn_at_least", "turn": 3}])
	assert_eq(str(_saved_entry(creator)["condition_logic"]), "OR")

func test_awakening_save_is_also_blocked_by_an_incomplete_condition() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, false)
	var advanced := _open_advanced(creator)
	_start_new_action(advanced, RBMActionEditorForm.AWAKENING)
	_add_condition(advanced, "hp_at_most")
	## 直接的に必須値を壊す(エディタ経由では選べない欠落の再現): 保存は必ず止まる。
	advanced._pending_conditions[0].erase("percent")
	_save(advanced)
	assert_false(creator.draft.has_awakening())

# ---------------------------------------------------------------------------
# Draft側の検証(条件1件の必須値チェック)
# ---------------------------------------------------------------------------

func test_draft_condition_problem_flags_missing_or_invalid_required_values() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var draft: RBMCreatorDraft = creator.draft
	assert_eq(draft.condition_problem({"type": "hp_at_most", "percent": 50.0}), "")
	assert_ne(draft.condition_problem({"type": "hp_at_most"}), "", "HP condition without a threshold")
	assert_ne(draft.condition_problem({"type": "hp_at_least", "percent": 101.0}), "")
	assert_ne(draft.condition_problem({"type": "hp_between", "percent_min": 70.0, "percent_max": 30.0}), "")
	assert_ne(draft.condition_problem({"type": "turn_at"}), "")
	assert_ne(draft.condition_problem({"type": "turn_every_n", "n": 0}), "")
	assert_ne(draft.condition_problem({"type": "allies_at_most"}), "")
	assert_ne(draft.condition_problem({"type": "character_downed", "character_id": ""}), "")
	assert_ne(draft.condition_problem({"type": "last_boss_skill", "skill_id": "missing"}), "")
	assert_eq(draft.condition_problem({"type": "last_boss_skill", "skill_id": str(draft.skills[0].get("skill_id", ""))}), "")
	assert_ne(draft.condition_problem({"type": "last_received_skill", "skill_id": ""}), "")
	assert_ne(draft.condition_problem({"type": "last_received_attribute"}), "")
	assert_eq(draft.condition_problem({"type": "weak_hit"}), "")
	assert_ne(draft.condition_problem({"type": ""}), "")

func test_draft_step_is_invalid_when_a_saved_slot_holds_an_incomplete_condition() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var draft: RBMCreatorDraft = creator.draft
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var skill_id := str(draft.skills[0].get("skill_id", ""))
	draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": skill_id, "conditions": [{"type": "hp_at_most"}], "condition_logic": "AND"}], "else_skill_id": skill_id})
	assert_false(draft.step4_advanced_is_valid())
	draft.turn_actions[0]["entries"][0]["conditions"] = [{"type": "hp_at_most", "percent": 50.0}]
	assert_true(draft.step4_advanced_is_valid())
