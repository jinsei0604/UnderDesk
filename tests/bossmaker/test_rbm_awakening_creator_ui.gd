extends GutTest

## RPG BOSS MAKER — 覚醒（Awakening）のADVANCED Creator UIテスト。
## test_rbm_advanced_creator_ui.gdと同じ「実UIツリーをインスタンス化して
## 公開API/シグナル経由で操作する」方針を踏襲する。

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
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3._advanced_view

## 「新しく攻撃を作る」を開き、種類ドロップダウンを「覚醒」へ切り替える
## ところまで進める共通ヘルパー。
func _open_new_awakening_form(advanced: RBMCreatorStep4ActionPatterns) -> RBMActionEditorForm:
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var form := advanced._form
	form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(RBMActionEditorForm.AWAKENING))
	form._on_type_selected(form._type_option.selected)
	return form

# ---------------------------------------------------------------------------
# 種類一覧: 覚醒の追加・disabled制御
# ---------------------------------------------------------------------------

func test_type_list_includes_awakening_as_a_fourth_option() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var form := advanced._form
	assert_eq(form._type_option.item_count, 4)
	assert_eq(form._type_option.get_item_text(3), tr("覚醒"))

## 覚醒対応可否(supports_awakening)機構の追加後、「未設定なら常に選択可能」
## という旧仕様は「対応外見 かつ 未設定」の2条件へ変わった(§1確定)。現在
## 実在する6外見は全て覚醒非対応のため、未設定であってもこの経路では
## disabledのままになるのが正しい——「対応外見+未設定」の組み合わせで
## 実際に選択可能になることは、test_rbm_boss_awakening_support.gdの
## 真偽値テーブルテストで別途、両条件を直接の真偽値として保証済み。
func test_awakening_type_stays_disabled_when_unset_but_no_real_appearance_supports_it() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_false(creator.draft.has_awakening())
	assert_false(creator.draft.supports_awakening(), "sanity: no real appearance supports awakening yet")
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._form._type_option.is_item_disabled(3), "unset alone is not enough with today's real appearance data -- the appearance must also support awakening")

func test_awakening_type_becomes_disabled_once_already_set() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._form._type_option.is_item_disabled(3), "already configured -- must start disabled, not merely error on selection")

## 削除後、「既に設定済み」という内部理由は正しくクリアされる(has_awakening()
## がfalseへ戻る)——ただし現在実在する6外見は全て覚醒非対応のため、
## 種類選択肢自体は(独立したもう一方の理由により)disabledのままになるのが
## 正しい仕様(§1確定)。「対応外見であれば削除後に再選択可能になる」という
## 組み合わせ自体は、test_rbm_boss_awakening_support.gdの真偽値テーブル
## テストで別途保証済み。
func test_deleting_awakening_clears_the_already_configured_flag_even_though_the_option_stays_disabled_by_appearance() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_btn(advanced, "DeleteAwakeningButton").pressed.emit()
	assert_false(creator.draft.has_awakening())
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._form._type_option.is_item_disabled(3), "still disabled today -- not because of stale 'already configured' state, but because no real appearance supports awakening yet")

func test_add_attack_button_wording_is_unchanged() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_eq(_btn(advanced, "AddSlotButton").text, tr("＋ 攻撃を追加する"))

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

func test_selecting_awakening_hides_the_outer_uses_count_section() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	assert_false(advanced._uses_row.visible)
	assert_false(advanced._uses_section_heading.visible)

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
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
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
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
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
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
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
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
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
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening.get("buff", {}), {})

func test_awakening_condition_uses_the_existing_condition_block() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	_open_new_awakening_form(advanced)
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES.find("hp_at_most"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	advanced._condition_percent_spin.value = 50.0
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.awakening["conditions"], [{"type": "hp_at_most", "percent": 50.0}])

# ---------------------------------------------------------------------------
# 一覧表示: 最下部固定・↑↓なし
# ---------------------------------------------------------------------------

func test_awakening_card_is_hidden_when_unset() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	assert_false(advanced._awakening_card_container.visible)
	assert_false(advanced._awakening_separator.visible)

func test_awakening_card_appears_below_the_normal_action_list_with_no_reorder_buttons() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.add_action_slot({
		"kind": "skill", "skill_id": str(creator.draft.skills[0].get("skill_id", "")),
		"conditions": [], "condition_logic": "AND", "max_uses": -1,
	})
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {}})
	advanced.refresh()
	assert_true(advanced._awakening_card_container.visible)
	assert_true(advanced._awakening_card_container.get_child_count() > 0)
	var up_buttons: Array = advanced._awakening_card_container.find_children("MoveSlotUpButton*", "Button", true, false)
	var down_buttons: Array = advanced._awakening_card_container.find_children("MoveSlotDownButton*", "Button", true, false)
	assert_true(up_buttons.is_empty(), "awakening must never show a reorder-up button")
	assert_true(down_buttons.is_empty(), "awakening must never show a reorder-down button")
	assert_not_null(advanced._awakening_card_container.find_child("EditAwakeningButton", true, false))
	assert_not_null(advanced._awakening_card_container.find_child("DeleteAwakeningButton", true, false))

func test_normal_action_reorder_still_ignores_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	assert_eq(creator.draft.action_sequence.size(), 2, "awakening must not be counted as a normal action")

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
	_btn(advanced, "EditAwakeningButton").pressed.emit()
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
	_btn(advanced, "EditAwakeningButton").pressed.emit()
	advanced._form._awakening_buff_multiplier_spin.value = 3.0
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.awakening["buff"]["buff_multiplier"], 3.0)

func test_deleting_via_the_edit_screen_removes_the_awakening() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_btn(advanced, "EditAwakeningButton").pressed.emit()
	_btn(advanced, "SkillSlotDeleteButton").pressed.emit()
	assert_false(creator.draft.has_awakening())

func test_deleting_awakening_does_not_touch_normal_actions() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	creator.draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	advanced.refresh()
	_btn(advanced, "DeleteAwakeningButton").pressed.emit()
	assert_false(creator.draft.has_awakening())
	assert_eq(creator.draft.action_sequence.size(), 1, "deleting awakening must not affect normal actions")
