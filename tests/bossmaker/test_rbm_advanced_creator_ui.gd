extends GutTest

## RPG BOSS MAKER — HARDCORE Creator STEP3「攻撃」画面のUI-drivingテスト
## （2026-09-05全面再設計、旧「行動パターン」ブロックUIのテストを全面
## 置換）。既存のtest_rbm_creator_flow.gd/test_rbm_realplay1_ui_polish.gd
## と同じ「実UIツリーをインスタンス化して公開API/シグナル経由で操作する」
## 方針をそのまま踏襲する。
##
## トップ画面は「攻撃」の番号付き一覧だけを表示し、「＋攻撃を追加する」から
## (1)既存の攻撃から選ぶ (2)新しく攻撃を作る (3)ランダム攻撃を作る、の3択に
## 入る（§4）。旧「条件/行動/追加ルール/瞬間発動後」の4ブロックUIは完全に
## 撤去した——このファイルの旧テストも全面的に書き直した。
##
## Codexレビュー指摘対応⑪(Node Orphans): このファイルはスロット/条件/
## ランダム候補一覧をqueue_free()で何度も再構築させるテストを多数含み、
## queue_free()は次のアイドルフレームまで実際の解放を遅延させるため、
## テスト間で1フレームも待たないとGUTのOrphan集計に一時的な未解放ノードが
## 積み上がって見える。after_each()を追加するだけで解消する。
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

func _fill_minimum_valid_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "HARDCOREUIテストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_skill({"name": "咆哮", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5})
	creator.draft.add_party_character("hero")

func _step3(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

## 共通行動作成フォームを最短距離で埋めて保存するヘルパー——既存の攻撃を
## 新規作成する際、フォーム自身の保存ボタンで確定する文脈（ランダム候補の
## 新規作成/性能編集）で使う。「新しく攻撃を作る」（skill_slot_view、
## フォームの保存/キャンセルボタンは非表示）では使わない——SkillSlot
## ConfirmButton経由で確定する。
func _fill_and_save_form(form: RBMActionEditorForm, name: String) -> void:
	form._name_edit.text = name
	form._on_save_pressed()

func _all_label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for found in node.find_children("*", "Label", true, false):
		texts.append((found as Label).text)
	return texts

func _all_button_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for found in node.find_children("*", "Button", true, false):
		texts.append((found as Button).text)
	return texts

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4:
	var step3 := _step3(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3

# ---------------------------------------------------------------------------
# モード切替（ロジック — Creator UI改修§23-A: 切替UI自体は最終確認画面から
# 削除された。draft.set_creator_mode()等の下位ロジック自体は無改修のまま
# 残置されており、以下は「実UIボタン」ではなくその直接APIを叩いて同じ
# 契約を確認する——UIから到達できなくなった事実そのものはこのファイルの
# 完了報告で明記する）。
# ---------------------------------------------------------------------------

func test_step3_defaults_to_simple_mode_with_simple_view_visible() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_true(step3._simple_view.visible)
	assert_false(step3._advanced_view.visible)

func test_switching_to_advanced_never_requires_confirmation() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	step3.refresh()
	assert_false(step3._simple_view.visible)
	assert_true(step3._advanced_view.visible)

func test_switching_to_advanced_auto_converts_existing_normal_action_percentages() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.normal_actions_enabled = true
	creator.draft.normal_action_percentages[skill_id] = 100.0
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(creator.draft.action_sequence.size(), 1)
	var slot: Dictionary = creator.draft.action_sequence[0]
	assert_true((slot.get("conditions", []) as Array).is_empty())

func test_switching_back_to_simple_without_advanced_only_settings_needs_no_confirmation() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_false(creator.draft.has_advanced_only_settings())
	assert_true(creator.draft.can_switch_to_simple_without_confirmation())
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)

func test_switching_back_to_simple_with_advanced_only_settings_needs_confirmation_first() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.add_action_slot({
		"kind": "skill",
		"skill_id": str(creator.draft.skills[0].get("skill_id", "")),
		"conditions": [{"type": "hp_at_most", "percent": 30.0}],
		"condition_logic": "AND",
		"max_uses": 2,
	})
	assert_true(creator.draft.has_advanced_only_settings())
	assert_false(creator.draft.can_switch_to_simple_without_confirmation(), "confirmation must be pending before an explicit discard")

	# キャンセル相当: 何もしなければADVANCEDのまま。
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(creator.draft.action_sequence.size(), 1)

	# 確定相当: 明示的にdiscard_advanced_settings_and_revert_to_simple()を呼ぶ。
	creator.draft.discard_advanced_settings_and_revert_to_simple()
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_true(creator.draft.action_sequence.is_empty())

# ---------------------------------------------------------------------------
# 2026-10-28 作り直し（ユーザー確定・案A）: HARDCORE の「通常行動」はターンごとの設定。
# ① 一覧（ターンのカード）→ ② ターンの設定（決め方: 確定 / 使用率で抽選 / 条件で分岐）→ ③ 行動の詳細。
# 旧「攻撃の一覧・3択（ランダム攻撃を作る）・使用回数・↑↓・一覧の削除ボタン」は廃止した。
# 以下は旧テストと同じ観点（追加の流れ・キャンセル・条件・抽選・性能編集・削除の後片付け・検証）を新しい画面で確かめる。
# ---------------------------------------------------------------------------

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

func _sid(creator: RBMCreatorMain, index: int) -> String:
	return str(creator.draft.skills[index].get("skill_id", ""))

func _fixed_turn(skill_id: String) -> Dictionary:
	return {"mode": "fixed", "entries": [{"skill_id": skill_id}]}

func _card_text(advanced: RBMCreatorStep4ActionPatterns, card_name: String) -> String:
	return "\n".join(_all_label_texts(advanced.find_child(card_name, true, false)))

func test_list_view_shows_only_attacks_heading_and_add_button_when_empty() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	assert_true(advanced._list_view.visible)
	assert_eq(advanced._turn_list.get_child_count(), 0)
	assert_true(_btn(advanced, "AddTurnButton").visible)
	assert_true(_btn(advanced, "AddExtraActionButton").visible)
	assert_false(advanced._turn_loop_note.visible, "no loop note without turns")

func test_slot_list_card_shows_ordinal_name_performance_condition_and_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": _sid(creator, 1), "conditions": [{"type": "hp_at_most", "percent": 30.0}], "condition_logic": "AND"}], "else_skill_id": _sid(creator, 0)})
	advanced.refresh()
	var fixed := _card_text(advanced, "TurnCard_0")
	assert_true(fixed.contains(tr("%dターン目") % 1), "ターン番号: %s" % fixed)
	assert_true(fixed.contains("斬撃"), "行動名: %s" % fixed)
	assert_true(fixed.contains("威力100"), "性能: %s" % fixed)
	var conditional := _card_text(advanced, "TurnCard_1")
	assert_true(conditional.contains("HPが30%以下"), "条件が読める形で載っていること: %s" % conditional)
	assert_true(conditional.contains("咆哮"))
	assert_true(conditional.contains(tr("それ以外 → %s") % "斬撃"))
	assert_false(conditional.contains("使用回数"), "使用回数は廃止")
	assert_true(advanced._turn_loop_note.visible)

func test_add_slot_button_opens_the_three_way_add_choice() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	assert_true(advanced._turn_view.visible, "a new turn opens its settings")
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	assert_true(advanced._add_choice_view.visible)
	assert_true(_btn(advanced, "AddChoicePickExistingButton").visible)
	assert_true(_btn(advanced, "AddChoiceCreateNewButton").visible)
	assert_null(advanced.find_child("AddChoiceCreateRandomButton", true, false), "「ランダム攻撃を作る」は無い（抽選はターンの決め方で選ぶ）")

func test_add_choice_cancel_returns_to_list() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCancelButton").pressed.emit()
	assert_true(advanced._turn_view.visible, "back to the turn settings")
	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_true(advanced._list_view.visible)
	assert_true(creator.draft.turn_actions.is_empty())

func test_add_choice_create_new_opens_skill_slot_view_with_form_active() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._entry_view.visible)
	assert_true(advanced._form.visible, "the performance form is open for a new action")
	assert_false(advanced._performance_summary_row.visible)
	assert_false(advanced._condition_block.visible, "a fixed turn has no conditions")
	assert_false(advanced._weight_block.visible, "a fixed turn has no usage rate")

func test_add_choice_create_random_opens_random_editor_view() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	assert_true(_btn(advanced, "EqualizeTurnButton").visible)
	assert_true(advanced._turn_total_label.visible)
	assert_eq(_btn(advanced, "AddTurnEntryButton").text, tr("＋ 候補を追加する"))

func test_pick_existing_then_confirm_adds_a_slot_referencing_the_chosen_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	assert_true(advanced._pick_existing_view.visible)
	_click(advanced, "PickExistingSkillCard_1")
	assert_true(advanced._performance_summary_row.visible, "an existing action shows its summary, not the form")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.turn_actions, [_fixed_turn(_sid(creator, 1))])
	assert_eq(creator.draft.skills.size(), skills_before, "no new action is created")

func test_pick_existing_cancel_returns_to_add_choice() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_btn(advanced, "PickExistingCancelButton").pressed.emit()
	assert_true(advanced._add_choice_view.visible)

func test_create_new_attack_flow_creates_skill_and_slot_atomically_on_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "新しい攻撃"
	assert_eq(creator.draft.skills.size(), skills_before, "nothing is created before the detail screen is saved")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before + 1)
	assert_true(creator.draft.turn_actions.is_empty(), "the turn is written only when the turn is saved")
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.turn_actions.size(), 1)
	assert_eq(str(creator.draft.find_skill(str(creator.draft.turn_actions[0]["entries"][0]["skill_id"])).get("name", "")), "新しい攻撃")

func test_cancelling_new_creation_flow_does_not_leave_a_provisional_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "取り消す攻撃"
	_btn(advanced, "EntryCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before)
	assert_true(advanced._turn_view.visible)

func _open_new_conditional_row(advanced: RBMCreatorStep4ActionPatterns) -> void:
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")

func _finish_conditional_turn(advanced: RBMCreatorStep4ActionPatterns) -> void:
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_click(advanced, "TurnElseCard")
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_1")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()

func test_ui_add_condition_button_flow_saves_the_condition_into_the_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_open_new_conditional_row(advanced)
	assert_true(advanced._condition_block.visible)
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_percent_spin.value = 40.0
	_finish_conditional_turn(advanced)
	var turn: Dictionary = creator.draft.turn_actions[0]
	assert_eq(turn["entries"][0]["conditions"], [{"type": "hp_at_most", "percent": 40.0}])
	assert_eq(str(turn["else_skill_id"]), _sid(creator, 1))

func test_condition_logic_option_hidden_until_a_second_condition_exists() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_false(advanced._condition_logic_option.visible)
	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_true(advanced._condition_logic_option.visible)

func test_ui_condition_logic_option_toggles_and_or_into_the_saved_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	_btn(advanced, "AddConditionButton").pressed.emit()
	var or_index := RBMActionPatternRules.CONDITION_LOGIC_TYPES.find("OR")
	advanced._condition_logic_option.select(or_index)
	advanced._condition_logic_option.item_selected.emit(or_index)
	_finish_conditional_turn(advanced)
	assert_eq(str(creator.draft.turn_actions[0]["entries"][0]["condition_logic"]), "OR")

## 使用回数は廃止（2026-10-28 ユーザー確定）: どの画面にも使用回数の入力が無い。
func test_uses_default_unlimited_and_switching_to_limited_saves_max_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_open_new_conditional_row(advanced)
	for node_name in ["UsesUnlimitedCheck", "UsesLimitedCheck", "UsesCountSpin"]:
		assert_null(advanced.find_child(node_name, true, false), node_name)
	assert_false(_all_label_texts(advanced).has(tr("■ 使用回数")))

## 2026-10-29: 条件は2段階（カテゴリ4つ→比較方法と値）。長い1つのプルダウンは無く、「前回使った行動」などは選べない。
func test_last_boss_skill_condition_is_labeled_as_previous_action_not_existing_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_open_new_conditional_row(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	var categories := advanced._condition_category_option
	assert_eq(categories.item_count, 4)
	for i in range(4):
		assert_eq(categories.get_item_text(i), tr(str(RBMActionPatternRules.CONDITION_CATEGORIES[i]["label"])))
	assert_eq(advanced._condition_compare_option.item_count, 2, "ボスHP: 以下・以上だけ")
	assert_eq(advanced._condition_compare_option.get_item_text(0), tr("以下"))
	assert_eq(advanced._condition_compare_option.get_item_text(1), tr("以上"))
	assert_null(advanced.find_child("ConditionTypeOption", true, false), "the long dropdown is gone")
	assert_false(_all_label_texts(advanced).has(tr("前回使った行動")))

func test_random_slot_creation_with_pick_existing_candidate() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	for card_index in [0, 1]:
		_btn(advanced, "AddTurnEntryButton").pressed.emit()
		_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
		_click(advanced, "PickExistingSkillCard_%d" % card_index)
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "EqualizeTurnButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.turn_actions, [{"mode": "random", "entries": [{"skill_id": _sid(creator, 0), "weight": 50.0}, {"skill_id": _sid(creator, 1), "weight": 50.0}]}])

## 同じターンに既にある候補は「既存の行動から選ぶ」に出さない（同じ行動を2回並べない）。
func test_random_slot_new_candidate_creates_a_reusable_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "新しい候補"
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	var new_id := str(advanced._pending_entries()[0]["skill_id"])
	assert_false(creator.draft.find_skill(new_id).is_empty(), "the new candidate is a real, reusable action")
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	assert_null(advanced.find_child("PickExistingSkillCard_2", true, false), "already a candidate of this turn")
	assert_not_null(advanced.find_child("PickExistingSkillCard_0", true, false))

func test_random_slot_manual_mode_weights_are_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	advanced._weight_spin.value = 70.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_1")
	assert_almost_eq(advanced._weight_spin.value, 30.0, 0.001, "a new candidate starts with the rest of 100%")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var weights := []
	for entry in creator.draft.turn_actions[0]["entries"]:
		weights.append(float(entry["weight"]))
	assert_eq(weights, [70.0, 30.0])

func test_random_candidate_rows_have_no_condition_or_uses_controls() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	assert_false(advanced._condition_block.visible)
	assert_true(advanced._weight_block.visible)
	assert_null(advanced.find_child("UsesCountSpin", true, false))

func test_random_add_candidate_choice_cancel_returns_to_random_editor() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCancelButton").pressed.emit()
	assert_true(advanced._turn_view.visible)
	assert_true(_btn(advanced, "TurnModeButton_random").button_pressed, "the turn keeps its way of choosing")

func test_cancelling_random_slot_edit_cleans_up_newly_created_candidate_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	for candidate_name in ["候補A", "候補B"]:
		_btn(advanced, "AddTurnEntryButton").pressed.emit()
		_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
		advanced._form._name_edit.text = candidate_name
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before + 2, "sanity")
	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before, "cancelling the turn removes the actions created in it")
	assert_true(creator.draft.turn_actions.is_empty())

func test_editing_existing_slot_shows_performance_summary_not_form_by_default() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	advanced.refresh()
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")
	assert_true(advanced._performance_summary_row.visible)
	assert_false(advanced._form.visible)
	assert_true(advanced._performance_summary_label.text.contains("斬撃"))
	assert_true(_btn(advanced, "EntryDeleteButton").visible, "deleting is on the detail screen")

func test_edit_performance_button_opens_the_shared_form_inline() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	advanced.refresh()
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	assert_true(advanced._form.visible)
	assert_eq(advanced._form._name_edit.text, "斬撃")
	assert_false(advanced._entry_actions_row.visible, "the outer save row hides while the form has its own save")
	advanced._form._name_edit.text = "斬撃改"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	assert_false(advanced._form.visible)
	assert_eq(str(creator.draft.find_skill(_sid(creator, 0)).get("name", "")), "斬撃改")

## 同じ行動を2つのターンで使っている時、性能の変更は両方に効くが、もう一方のターンの条件は変わらない。
func test_editing_shared_skill_performance_does_not_affect_other_slots_own_condition_and_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": _sid(creator, 0), "conditions": [{"type": "turn_at", "turn": 2}], "condition_logic": "AND"}], "else_skill_id": _sid(creator, 1)})
	advanced.refresh()
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")
	assert_true(advanced._shared_skill_notice.visible, "tells the author the action is used elsewhere too")
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 2.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(float(creator.draft.find_skill(_sid(creator, 0)).get("atk_multiplier", -1.0)), 2.0)
	assert_eq(creator.draft.turn_actions[1]["entries"][0]["conditions"], [{"type": "turn_at", "turn": 2}])

func test_cancelling_performance_edit_restores_the_original_skill_content() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	advanced.refresh()
	var original := creator.draft.find_skill(_sid(creator, 0)).duplicate(true)
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 7.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryCancelButton").pressed.emit()
	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_eq(creator.draft.find_skill(_sid(creator, 0)), original)

func test_cancelling_an_edit_of_an_existing_slot_does_not_delete_pre_existing_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	advanced.refresh()
	var skills_before := creator.draft.skills.size()
	_click(advanced, "TurnCard_0")
	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before)
	assert_eq(creator.draft.turn_actions, [_fixed_turn(_sid(creator, 0))])

## 一覧のカードには編集・削除・↑↓のボタンを置かない（カード全体を押して開く、2026-10-28）。並べ替えは
## 右の四方向矢印のつまみの長押し＋ドラッグ（挿入型、2026-10-29。詳しくは test_rbm_hardcore_turn_actions.gd）。
func test_move_slot_up_and_down_changes_array_order() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 1)))
	advanced.refresh()
	var buttons := advanced._turn_list.find_children("*", "BaseButton", true, false)
	assert_eq(buttons.size(), 2, "one move handle per turn card")
	for b in buttons:
		assert_true(b is RBMTurnMoveHandle, "only the move handle: %s" % b.name)
	advanced.draft.move_turn_action(1, 0)
	advanced.refresh()
	assert_eq(advanced.draft.turn_actions, [_fixed_turn(_sid(creator, 1)), _fixed_turn(_sid(creator, 0))])
	var card := advanced.find_child("TurnCard_1", true, false) as Control
	assert_eq(card.mouse_filter, Control.MOUSE_FILTER_STOP, "the whole card is clickable")
	_click(advanced, "TurnCard_1")
	assert_eq(advanced._turn_title.text, tr("%dターン目の設定") % 2)

func test_deleting_a_slot_from_its_edit_screen_removes_it_and_cleans_up_unreferenced_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "消す攻撃"
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var new_id := str(creator.draft.turn_actions[0]["entries"][0]["skill_id"])
	_click(advanced, "TurnCard_0")
	_btn(advanced, "TurnDeleteButton").pressed.emit()
	assert_true(creator.draft.turn_actions.is_empty())
	assert_true(creator.draft.find_skill(new_id).is_empty(), "the unreferenced action is cleaned up")

## 一覧から直接は消せない（2026-10-28）。ターンの中の行動を消してターンを保存すると、使われなくなった行動は片付く。
func test_deleting_a_slot_from_the_list_directly_also_cleans_up_unreferenced_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	for candidate_name in ["残す", "消す"]:
		_btn(advanced, "AddTurnEntryButton").pressed.emit()
		_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
		advanced._form._name_edit.text = candidate_name
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_click(advanced, "PickExistingSkillCard_0")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var removed_id := str(creator.draft.turn_actions[0]["entries"][1]["skill_id"])
	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_1")
	_btn(advanced, "EntryDeleteButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq((creator.draft.turn_actions[0]["entries"] as Array).size(), 2)
	assert_true(creator.draft.find_skill(removed_id).is_empty())
	assert_null(advanced._turn_list.find_child("DeleteSlotButton_0", true, false))

func test_deleting_one_slot_does_not_delete_a_skill_still_used_by_another_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	creator.draft.add_turn_action(_fixed_turn(_sid(creator, 0)))
	advanced.refresh()
	_click(advanced, "TurnCard_0")
	_btn(advanced, "TurnDeleteButton").pressed.emit()
	assert_eq(creator.draft.turn_actions.size(), 1)
	assert_false(creator.draft.find_skill(_sid(creator, 0)).is_empty(), "still used by the other turn")

func test_deleting_a_random_slot_removes_it_and_cleans_up_all_its_candidate_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	for candidate_name in ["候補A", "候補B"]:
		_btn(advanced, "AddTurnEntryButton").pressed.emit()
		_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
		advanced._form._name_edit.text = candidate_name
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before + 2, "sanity")
	_click(advanced, "TurnCard_0")
	_btn(advanced, "TurnDeleteButton").pressed.emit()
	assert_true(creator.draft.turn_actions.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before)

# ---------------------------------------------------------------------------
# 検証
# ---------------------------------------------------------------------------

func test_step3_is_step_valid_delegates_to_the_currently_visible_mode() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	assert_true(step3.is_step_valid(), "SIMPLE mode with normal actions off and zero scripted actions defaults to valid")

	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	step3.refresh()
	assert_false(step3.is_step_valid(), "HARDCORE needs at least one turn (案A)")
	assert_eq(step3.validation_message(), tr("通常行動を1ターン以上追加してください"))

	creator.draft.add_turn_action({"mode": "random", "entries": [{"skill_id": _sid(creator, 0), "weight": 100.0}]})
	assert_false(step3.is_step_valid(), "a random turn needs two or more candidates")
	assert_true(step3.validation_message().begins_with(tr("%dターン目：%s") % [1, ""]), step3.validation_message())

	creator.draft.update_turn_action(0, _fixed_turn(_sid(creator, 0)))
	assert_true(step3.is_step_valid())

# ---------------------------------------------------------------------------
# §11必須テスト項目（新モデルへ適用）
# ---------------------------------------------------------------------------

func test_simple_view_has_no_mode_toggle_button() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	assert_null(step3._simple_view.find_child("SwitchToAdvancedModeButton", true, false))
	assert_null(step3._simple_view.find_child("SwitchToSimpleModeButton", true, false))

func test_advanced_view_has_no_mode_toggle_button() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	assert_null(step3._advanced_view.find_child("SwitchToAdvancedModeButton", true, false))
	assert_null(step3._advanced_view.find_child("SwitchToSimpleModeButton", true, false))

# ---------------------------------------------------------------------------
# §28: デザイン言語（既存のRBMCreatorUiKit、旧「行動パターン」文言を残さない）
# ---------------------------------------------------------------------------

func test_final_ui_copy_uses_new_wording_not_legacy_pattern_terms() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var texts := _all_label_texts(advanced)
	texts.append_array(_all_button_texts(advanced))
	var joined := "\n".join(texts)
	assert_false(joined.contains("行動パターン"), "旧「行動パターン」文言を残さないこと")
	assert_false(joined.contains("追加ルール"), "旧「追加ルール」文言を残さないこと")
	assert_true(joined.contains("攻撃"), "新しい「攻撃」文言を使うこと")
