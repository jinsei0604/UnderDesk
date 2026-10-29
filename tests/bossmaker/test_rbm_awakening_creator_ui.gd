extends GutTest

## RPG BOSS MAKER — 覚醒（Awakening）のADVANCED Creator UIテスト。
## test_rbm_advanced_creator_ui.gdと同じ「実UIツリーをインスタンス化して
## 公開API/シグナル経由で操作する」方針を踏襲する。
##
## 2026-10-28: HARDCORE の行動の画面を作り直した（ユーザー確定）。覚醒は一覧の「覚醒」の見出し（仕切り線つき）の
## 「＋ 覚醒を追加する」から作り、設定後はカードを押して開く（行動の種類の一覧からは作らない）。使用回数は廃止。

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
	creator.draft.boss_name = "覚醒UIテストボス"
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
	step3.refresh()
	return step3._advanced_view

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

## 覚醒に対応した外見（竜）にして「＋ 覚醒を追加する」を押す。
func _open_new_awakening_form(advanced: RBMCreatorStep4ActionPatterns) -> RBMActionEditorForm:
	advanced.draft.appearance_id = "appearance_dragon"
	advanced.refresh()
	_btn(advanced, "AddAwakeningButton").pressed.emit()
	return advanced._form

func _fixed_turn(creator: RBMCreatorMain) -> Dictionary:
	return {"mode": "fixed", "entries": [{"skill_id": str(creator.draft.skills[0].get("skill_id", ""))}]}

# ---------------------------------------------------------------------------
# 種類一覧: 覚醒の追加・disabled制御
# ---------------------------------------------------------------------------

## 行動の種類の一覧には今も4つ目に「覚醒」があるが、行動を新しく作る時は選べない（覚醒は覚醒の見出しから作る）。
func test_type_list_includes_awakening_as_a_fourth_option() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var form := advanced._form
	assert_eq(form._type_option.item_count, 4)
	assert_eq(form._type_option.get_item_text(3), tr("覚醒"))
	assert_true(form._type_option.is_item_disabled(3), "new actions are never the awakening")

## 覚醒対応可否(supports_awakening)機構の追加後、「未設定なら常に選択可能」
## という旧仕様は「対応外見 かつ 未設定」の2条件へ変わった(§1確定)。現在
## 実在する6外見は全て覚醒非対応のため、未設定であってもこの経路では
## disabledのままになるのが正しい——「対応外見+未設定」の組み合わせで
## 実際に選択可能になることは、test_rbm_boss_awakening_support.gdの
## 真偽値テーブルテストで別途、両条件を直接の真偽値として保証済み。
## 覚醒に対応していない外見では「＋ 覚醒を追加する」は押せない（選んでからエラーにしない）。
func test_awakening_type_stays_disabled_when_unset_but_no_real_appearance_supports_it() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_false(creator.draft.has_awakening())
	assert_false(creator.draft.supports_awakening(), "sanity: no appearance chosen")
	assert_true(_btn(advanced, "AddAwakeningButton").disabled)
	creator.draft.appearance_id = "appearance_dragon"
	advanced.refresh()
	assert_false(_btn(advanced, "AddAwakeningButton").disabled, "the dragon supports awakening")

## 覚醒は1つだけ: 設定済みなら追加のボタンは出さず、覚醒のカードを出す。
func test_awakening_type_becomes_disabled_once_already_set() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	assert_false(_btn(advanced, "AddAwakeningButton").visible, "already configured -- no second awakening")
	assert_not_null(advanced.find_child("AwakeningCardButton", true, false))

## 削除後、「既に設定済み」という内部理由は正しくクリアされる(has_awakening()
## がfalseへ戻る)——ただし現在実在する6外見は全て覚醒非対応のため、
## 種類選択肢自体は(独立したもう一方の理由により)disabledのままになるのが
## 正しい仕様(§1確定)。「対応外見であれば削除後に再選択可能になる」という
## 組み合わせ自体は、test_rbm_boss_awakening_support.gdの真偽値テーブル
## テストで別途保証済み。
func test_deleting_awakening_clears_the_already_configured_flag_even_though_the_option_stays_disabled_by_appearance() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.draft.appearance_id = "appearance_dragon"
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_click(advanced, "AwakeningCardButton")
	_btn(advanced, "EntryDeleteButton").pressed.emit()
	assert_false(creator.draft.has_awakening())
	assert_true(_btn(advanced, "AddAwakeningButton").visible, "can be added again")
	assert_false(_btn(advanced, "AddAwakeningButton").disabled)

func test_add_attack_button_wording_is_unchanged() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_eq(_btn(advanced, "AddTurnButton").text, tr("＋ ターンを追加する"))
	assert_eq(_btn(advanced, "AddAwakeningButton").text, tr("＋ 覚醒を追加する"))

# ---------------------------------------------------------------------------
# 覚醒選択時のフォーム表示
# ---------------------------------------------------------------------------

func test_selecting_awakening_hides_attack_and_name_fields_and_shows_awakening_fields() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	assert_false(form._attack_fields.visible)
	assert_false(form._self_heal_fields.visible)
	assert_false(form._atk_buff_fields.visible)
	assert_true(form._awakening_fields.visible)
	assert_false(form._name_row.visible, "awakening has no name concept")

## 使用回数は廃止（2026-10-28）: 覚醒の画面にも、使用率・ターン開始/終了の入力も出さない。
func test_selecting_awakening_hides_the_outer_uses_count_section() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	assert_null(advanced.find_child("UsesUnlimitedCheck", true, false))
	assert_false(advanced._weight_block.visible)
	assert_false(advanced._extra_block.visible)
	assert_true(advanced._condition_block.visible)

func test_awakening_buff_and_heal_blocks_start_collapsed_behind_add_buttons() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	assert_true(_btn(form, "AwakeningAddBuffButton").visible)
	assert_false(form._awakening_buff_block.visible)
	assert_true(_btn(form, "AwakeningAddHealButton").visible)
	assert_false(form._awakening_heal_block.visible)

# ---------------------------------------------------------------------------
# 保存: 自己強化/HP回復の組み合わせ
# ---------------------------------------------------------------------------

func test_confirm_with_neither_buff_nor_heal_saves_a_transform_only_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening.get("buff", {}), {})
	assert_eq(creator.draft.awakening.get("heal", {}), {})

func test_confirm_with_only_buff_added_saves_buff_only() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	_btn(form, "AwakeningAddBuffButton").pressed.emit()
	form._awakening_buff_multiplier_spin.value = 1.5
	form._awakening_buff_duration_spin.value = 3
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening["buff"], {"buff_multiplier": 1.5, "duration_turns": 3})
	assert_eq(creator.draft.awakening.get("heal", {}), {})

func test_confirm_with_only_heal_added_saves_heal_only() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	_btn(form, "AwakeningAddHealButton").pressed.emit()
	form._awakening_heal_mode_option.select(1)
	form._on_awakening_heal_mode_selected(1)
	form._awakening_heal_percent_spin.value = 30.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening.get("buff", {}), {})
	assert_eq(creator.draft.awakening["heal"], {"heal_mode": "percent", "heal_fixed_amount": 0, "heal_percent": 30.0})

func test_confirm_with_both_buff_and_heal_saves_both() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	_btn(form, "AwakeningAddBuffButton").pressed.emit()
	form._awakening_buff_multiplier_spin.value = 2.0
	form._awakening_buff_duration_spin.value = 1
	_btn(form, "AwakeningAddHealButton").pressed.emit()
	form._awakening_heal_fixed_spin.value = 200
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening["buff"], {"buff_multiplier": 2.0, "duration_turns": 1})
	assert_eq(creator.draft.awakening["heal"], {"heal_mode": "fixed", "heal_fixed_amount": 200, "heal_percent": 0.0})

func test_removing_a_toggled_buff_before_confirm_drops_it() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var form := _open_new_awakening_form(advanced)
	_btn(form, "AwakeningAddBuffButton").pressed.emit()
	assert_true(form._awakening_buff_block.visible)
	_btn(form, "AwakeningRemoveBuffButton").pressed.emit()
	assert_false(form._awakening_buff_block.visible)
	assert_true(_btn(form, "AwakeningAddBuffButton").visible)
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening.get("buff", {}), {})

func test_awakening_condition_uses_the_existing_condition_block() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._select_condition_type("hp_at_most")
	advanced._condition_percent_spin.value = 50.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening["conditions"], [{"type": "hp_at_most", "percent": 50.0}])

# ---------------------------------------------------------------------------
# 一覧表示: 最下部固定・↑↓なし
# ---------------------------------------------------------------------------

func test_awakening_card_is_hidden_when_unset() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_eq(advanced._awakening_container.get_child_count(), 0)
	assert_null(advanced.find_child("AwakeningCardButton", true, false))
	assert_not_null(advanced.find_child("AwakeningSeparator", true, false), "the heading and its separator stay")

func test_awakening_card_appears_below_the_normal_action_list_with_no_reorder_buttons() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.add_turn_action(_fixed_turn(creator))
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {}})
	advanced.refresh()
	var card := advanced.find_child("AwakeningCardButton", true, false) as Control
	assert_not_null(card)
	assert_true(advanced._list_view.get_children().find(advanced._awakening_container) > advanced._list_view.get_children().find(advanced._turn_list), "below the normal actions")
	assert_eq(advanced._awakening_container.find_children("*", "BaseButton", true, false).size(), 0, "no reorder/edit/delete buttons -- the card itself opens the settings")

func test_normal_action_reorder_still_ignores_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.add_turn_action(_fixed_turn(creator))
	creator.draft.add_turn_action(_fixed_turn(creator))
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	assert_eq(creator.draft.turn_actions.size(), 2, "awakening must not be counted as a normal action")
	assert_null(advanced.find_child("TurnCard_2", true, false))

# ---------------------------------------------------------------------------
# 編集・削除
# ---------------------------------------------------------------------------

func test_editing_existing_awakening_prefills_the_form() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({
		"conditions": [{"type": "hp_at_most", "percent": 40.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.75, "duration_turns": 2},
		"heal": {"heal_mode": "fixed", "heal_fixed_amount": 150, "heal_percent": 0.0},
	})
	advanced.refresh()
	_click(advanced, "AwakeningCardButton")
	var form := advanced._form
	assert_true(form._awakening_has_buff)
	assert_eq(form._awakening_buff_multiplier_spin.value, 1.75)
	assert_eq(int(form._awakening_buff_duration_spin.value), 2)
	assert_true(form._awakening_has_heal)
	assert_eq(int(form._awakening_heal_fixed_spin.value), 150)
	assert_eq(advanced._pending_conditions, [{"type": "hp_at_most", "percent": 40.0}])

func test_editing_and_confirming_updates_the_existing_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 1}, "heal": {}})
	advanced.refresh()
	_click(advanced, "AwakeningCardButton")
	advanced._form._awakening_buff_multiplier_spin.value = 3.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["buff"]["buff_multiplier"], 3.0)

func test_deleting_via_the_edit_screen_removes_the_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_click(advanced, "AwakeningCardButton")
	_btn(advanced, "EntryDeleteButton").pressed.emit()
	assert_false(creator.draft.has_awakening())

func test_deleting_awakening_does_not_touch_normal_actions() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.add_turn_action(_fixed_turn(creator))
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_click(advanced, "AwakeningCardButton")
	_btn(advanced, "EntryDeleteButton").pressed.emit()
	assert_false(creator.draft.has_awakening())
	assert_eq(creator.draft.turn_actions.size(), 1, "deleting awakening must not affect normal actions")

