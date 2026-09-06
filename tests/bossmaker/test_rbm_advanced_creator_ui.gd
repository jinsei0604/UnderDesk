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
# §3: トップ画面は「攻撃」の一覧だけ
# ---------------------------------------------------------------------------

func test_list_view_shows_only_attacks_heading_and_add_button_when_empty() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	assert_true(advanced._list_view.visible)
	assert_eq(advanced._slot_list.get_child_count(), 0)
	assert_true(_btn(advanced, "AddSlotButton").visible)

func test_slot_list_card_shows_ordinal_name_performance_condition_and_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({
		"kind": "skill", "skill_id": skill_id,
		"conditions": [{"type": "hp_at_most", "percent": 30.0}],
		"condition_logic": "AND", "max_uses": 2,
	})
	advanced.refresh()
	var card: VBoxContainer = advanced._slot_list.get_child(0)
	var texts := PackedStringArray()
	for child in card.get_children():
		if child is Label:
			texts.append((child as Label).text)
	var joined := "\n".join(texts)
	assert_true(joined.contains("01"), "番号が表示される: %s" % joined)
	assert_true(joined.contains("HPが30%以下"), "条件が読める形で載っていること: %s" % joined)
	assert_true(joined.contains("斬撃"), "行動名がそのまま載っていること: %s" % joined)
	assert_true(joined.contains("使用回数：2回"), "使用回数が読める形で載っていること: %s" % joined)

# ---------------------------------------------------------------------------
# §4: 追加方法の3択
# ---------------------------------------------------------------------------

func test_add_slot_button_opens_the_three_way_add_choice() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	assert_true(advanced._add_choice_view.visible)
	assert_true(_btn(advanced, "AddChoicePickExistingButton").visible)
	assert_true(_btn(advanced, "AddChoiceCreateNewButton").visible)
	assert_true(_btn(advanced, "AddChoiceCreateRandomButton").visible)

func test_add_choice_cancel_returns_to_list() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCancelButton").pressed.emit()
	assert_true(advanced._list_view.visible)

## §6: 「新しく攻撃を作る」を選んだ瞬間、性能フォーム・発動条件・使用回数
## が同一画面へ同時に表示される（確定ボタンは1つだけ）。
func test_add_choice_create_new_opens_skill_slot_view_with_form_active() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._skill_slot_view.visible)
	assert_true(advanced._skill_slot_form_active)
	assert_true(advanced._form.visible)
	assert_true(advanced._condition_uses_block.visible)
	assert_eq(advanced._form.get_parent(), advanced._skill_slot_form_slot)
	assert_eq(advanced._condition_uses_block.get_parent(), advanced._skill_slot_condition_uses_slot)
	assert_eq(_btn(advanced, "SkillSlotConfirmButton").text, "攻撃を追加")
	assert_false(_btn(advanced, "SkillSlotDeleteButton").visible)

func test_add_choice_create_random_opens_random_editor_view() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	assert_true(advanced._random_editor_view.visible)
	assert_eq(_btn(advanced, "RandomConfirmButton").text, "ランダム攻撃を追加")
	assert_false(_btn(advanced, "RandomDeleteButton").visible)

# ---------------------------------------------------------------------------
# §5: 既存の攻撃から選ぶ
# ---------------------------------------------------------------------------

func test_pick_existing_then_confirm_adds_a_slot_referencing_the_chosen_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	assert_true(advanced._pick_existing_view.visible)

	var select_button: Button = advanced._pick_existing_list.find_child("PickExistingSkillButton_0", true, false)
	assert_not_null(select_button)
	select_button.pressed.emit()

	assert_true(advanced._skill_slot_view.visible)
	assert_false(advanced._skill_slot_form_active, "既存を選んだ直後はフォームを開かず性能サマリのみ表示する")
	assert_true(advanced._skill_slot_performance_summary_row.visible)

	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 1)
	assert_eq(str(creator.draft.action_sequence[0].get("skill_id", "")), skill_id)
	assert_eq(creator.draft.skills.size(), skills_before, "既存skillを選んだだけなので新規skillは作られない")

func test_pick_existing_cancel_returns_to_add_choice() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	_btn(advanced, "PickExistingCancelButton").pressed.emit()
	assert_true(advanced._add_choice_view.visible)

# ---------------------------------------------------------------------------
# §6: 新しく攻撃を作る（性能+条件+使用回数を1画面で確定）
# ---------------------------------------------------------------------------

func test_create_new_attack_flow_creates_skill_and_slot_atomically_on_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "新しい攻撃"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(creator.draft.skills.size(), skills_before + 1, "新しいskillが1つ作られる")
	assert_eq(creator.draft.action_sequence.size(), 1, "同時にスロットも1つ追加される")
	var slot: Dictionary = creator.draft.action_sequence[0]
	var new_skill_id := str(slot.get("skill_id", ""))
	assert_eq(str(creator.draft.find_skill(new_skill_id).get("name", "")), "新しい攻撃")
	assert_true(advanced._list_view.visible, "確定後は一覧画面へ戻る")

func test_cancelling_new_creation_flow_does_not_leave_a_provisional_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "使い捨て"
	_btn(advanced, "SkillSlotCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before, "confirmする前は何もdraftへ書き込まれていない")
	assert_true(creator.draft.action_sequence.is_empty())

# ---------------------------------------------------------------------------
# §7/§8: 発動条件・使用回数（skill_slot_view内の共有ブロック経由）
# ---------------------------------------------------------------------------

func test_ui_add_condition_button_flow_saves_the_condition_into_the_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 0)

	_btn(advanced, "AddConditionButton").pressed.emit()
	assert_true(advanced._condition_editor.visible)
	advanced._condition_percent_spin.value = 42.0
	_btn(advanced, "ConfirmConditionButton").pressed.emit()

	assert_false(advanced._condition_editor.visible, "confirm closes the condition sub-editor")
	assert_eq(advanced._pending_conditions.size(), 1)
	assert_eq(str(advanced._pending_conditions[0].get("type", "")), "hp_at_most")
	assert_eq(float(advanced._pending_conditions[0].get("percent", -1.0)), 42.0)

	advanced._form._name_edit.text = "行動"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var slot: Dictionary = creator.draft.action_sequence[0]
	var conditions: Array = slot.get("conditions", [])
	assert_eq(conditions.size(), 1)
	assert_eq(str(conditions[0].get("type", "")), "hp_at_most")
	assert_eq(float(conditions[0].get("percent", -1.0)), 42.0)

func test_condition_logic_option_hidden_until_a_second_condition_exists() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_false(advanced._condition_logic_option.visible, "条件0件ではAND/ORは無意味なので隠す")

	_btn(advanced, "AddConditionButton").pressed.emit()
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 1)
	assert_false(advanced._condition_logic_option.visible, "条件1件のままではAND/ORを出さない")

	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("turn_at"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 2)
	assert_true(advanced._condition_logic_option.visible, "2件目を追加した瞬間だけAND/ORが現れる")

func test_ui_condition_logic_option_toggles_and_or_into_the_saved_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_eq(advanced._pending_condition_logic, "AND")

	advanced._condition_logic_option.select(RBMActionPatternRules.CONDITION_LOGIC_TYPES.find("OR"))
	advanced._on_condition_logic_selected(advanced._condition_logic_option.selected)
	assert_eq(advanced._pending_condition_logic, "OR")

	advanced._form._name_edit.text = "行動"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var slot: Dictionary = creator.draft.action_sequence[0]
	assert_eq(str(slot.get("condition_logic", "")), "OR")

func test_uses_default_unlimited_and_switching_to_limited_saves_max_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	assert_eq(advanced._pending_max_uses, RBMActionPatternRules.UNLIMITED_USES)
	assert_true(advanced._uses_unlimited_check.button_pressed)

	advanced._uses_limited_check.button_pressed = true
	advanced._on_uses_limited_toggled(true)
	advanced._uses_count_spin.value = 3.0
	assert_eq(advanced._pending_max_uses, 3)

	advanced._form._name_edit.text = "行動"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var slot: Dictionary = creator.draft.action_sequence[0]
	assert_eq(int(slot.get("max_uses", -99)), 3)

## §2/§7: last_boss_skill条件は「前回使った行動」として見せる（唯一の
## 既存スキル参照）。
func test_last_boss_skill_condition_is_labeled_as_previous_action_not_existing_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	_btn(advanced, "AddConditionButton").pressed.emit()

	var label: Label = advanced._condition_boss_skill_row.get_child(0)
	assert_eq(label.text, "前回使った行動", "「既存スキルを選択」という文言は使わない")

	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("last_boss_skill"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	assert_true(advanced._condition_boss_skill_row.visible)
	assert_eq(advanced._condition_boss_skill_option.item_count, creator.draft.skills.size())

	advanced._condition_boss_skill_option.select(1)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	assert_eq(str(advanced._pending_conditions[0].get("skill_id", "")), str(creator.draft.skills[1].get("skill_id", "")))

# ---------------------------------------------------------------------------
# §10/§11/§12: ランダム攻撃
# ---------------------------------------------------------------------------

func test_random_slot_creation_with_pick_existing_candidate() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	assert_true(advanced._random_editor_view.visible)

	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	assert_true(advanced._random_add_choice_view.visible)
	_btn(advanced, "RandomAddChoicePickExistingButton").pressed.emit()
	assert_true(advanced._random_pick_existing_view.visible)

	var select_button: Button = advanced._random_pick_existing_list.find_child("RandomPickExistingSkillButton_0", true, false)
	assert_not_null(select_button)
	select_button.pressed.emit()

	assert_true(advanced._random_editor_view.visible)
	assert_eq(advanced._random_candidates.size(), 1)
	assert_eq(str(advanced._random_candidates[0].get("skill_id", "")), skill_id)

	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 1)
	var slot: Dictionary = creator.draft.action_sequence[0]
	assert_eq(str(slot.get("kind", "")), "random")
	assert_eq((slot.get("candidates", []) as Array).size(), 1)

## §11: 新規作成されたスキルはdraft.skillsの共有ライブラリへ保存されるため、
## 別の配置の「既存の攻撃から選ぶ」一覧にも現れる（再利用可能なことの
## 直接証明）。
func test_random_slot_new_candidate_creates_a_reusable_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	assert_true(advanced._random_create_new_view.visible)
	_fill_and_save_form(advanced._form, "新規候補")

	assert_true(advanced._random_editor_view.visible, "保存後、ランダム編集画面へ自動的に戻る")
	assert_eq(creator.draft.skills.size(), skills_before + 1)
	assert_eq(advanced._random_candidates.size(), 1)
	var new_skill_id := str(advanced._random_candidates[0].get("skill_id", ""))
	assert_eq(str(creator.draft.find_skill(new_skill_id).get("name", "")), "新規候補")
	_btn(advanced, "RandomConfirmButton").pressed.emit()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	var expected_button_name := ""
	for i in range(creator.draft.skills.size()):
		if str(creator.draft.skills[i].get("skill_id", "")) == new_skill_id:
			expected_button_name = "PickExistingSkillButton_%d" % i
	assert_ne(expected_button_name, "")
	assert_not_null(advanced._pick_existing_list.find_child(expected_button_name, true, false), "ランダム攻撃内で新規作成した攻撃が、別の配置の「既存の攻撃から選ぶ」一覧にも現れる")

func test_random_slot_manual_mode_weights_are_saved() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	advanced._random_mode_option.select(RBMActionPatternRules.RANDOM_MODES.find(RBMActionPatternRules.RANDOM_MODE_MANUAL))
	advanced._on_random_mode_selected(advanced._random_mode_option.selected)

	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補A")
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補B")

	advanced._set_random_candidate_weight(0, 70.0)
	advanced._set_random_candidate_weight(1, 30.0)

	_btn(advanced, "RandomConfirmButton").pressed.emit()
	var slot: Dictionary = creator.draft.action_sequence[0]
	assert_eq(str(slot.get("mode", "")), "manual")
	var candidates: Array = slot.get("candidates", [])
	assert_eq(candidates.size(), 2)
	assert_eq(float(candidates[0].get("weight", -1.0)), 70.0)
	assert_eq(float(candidates[1].get("weight", -1.0)), 30.0)

## §12確定（非常に重要）: ランダム候補の行に条件・使用回数のコントロールが
## 一切存在しない——候補側にその概念自体が無いことのUI上の直接証明。
func test_random_candidate_rows_have_no_condition_or_uses_controls() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補A")

	var row: HBoxContainer = advanced._random_candidate_list.find_child("RandomCandidateRow_0", true, false)
	assert_not_null(row)
	var found_condition_or_uses := false
	for child in row.get_children():
		if str(child.name).contains("Condition") or str(child.name).contains("Uses"):
			found_condition_or_uses = true
	assert_false(found_condition_or_uses)

func test_random_add_candidate_choice_cancel_returns_to_random_editor() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCancelButton").pressed.emit()
	assert_true(advanced._random_editor_view.visible)

func test_cancelling_random_slot_edit_cleans_up_newly_created_candidate_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補A")
	assert_eq(creator.draft.skills.size(), skills_before + 1)

	_btn(advanced, "RandomCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before, "キャンセル時、未保存の新規作成候補skillは片付く")
	assert_true(creator.draft.action_sequence.is_empty())

# ---------------------------------------------------------------------------
# §19: 編集は「性能編集」と「配置(条件/使用回数)編集」を区別する
# ---------------------------------------------------------------------------

func test_editing_existing_slot_shows_performance_summary_not_form_by_default() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	var edit_button: Button = advanced._slot_list.find_child("EditSlotButton_0", true, false)
	assert_not_null(edit_button)
	edit_button.pressed.emit()

	assert_true(advanced._skill_slot_view.visible)
	assert_false(advanced._skill_slot_form_active)
	assert_true(advanced._skill_slot_performance_summary_row.visible)
	assert_eq(_btn(advanced, "SkillSlotConfirmButton").text, "保存")
	assert_true(_btn(advanced, "SkillSlotDeleteButton").visible)

func test_edit_performance_button_opens_the_shared_form_inline() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()

	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	assert_true(advanced._skill_slot_form_active)
	assert_true(advanced._form.visible)
	assert_eq(advanced._form._name_edit.text, str(creator.draft.skills[0].get("name", "")))

	advanced._form._name_edit.text = "改名された攻撃"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	assert_false(advanced._skill_slot_form_active, "性能保存後はフォームが閉じ配置編集画面へ戻る")
	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "改名された攻撃")

## §19安全性の核心例: 同じ攻撃性能を2つの配置へ置いた状態で、片方の
## 性能編集を行っても、もう片方の配置自身の条件/使用回数には一切影響しない
## （性能は共有、配置は独立）。
func test_editing_shared_skill_performance_does_not_affect_other_slots_own_condition_and_uses() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [{"type": "turn_at", "turn": 1}], "condition_logic": "AND", "max_uses": -1})
	var slot_id_2: String = creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [{"type": "turn_at", "turn": 5}], "condition_logic": "AND", "max_uses": 2})
	advanced.refresh()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "共有攻撃・改名"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "共有攻撃・改名", "性能(name)は共有スキルなので両方の配置から見える")
	var slot2 := creator.draft.find_action_slot(slot_id_2)
	assert_eq(int((slot2.get("conditions", []) as Array)[0].get("turn", -1)), 5, "他方の配置自身の条件は無傷")
	assert_eq(int(slot2.get("max_uses", -99)), 2, "他方の配置自身の使用回数は無傷")

func test_cancelling_performance_edit_restores_the_original_skill_content() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var original_name := str(creator.draft.skills[0].get("name", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "編集中の一時的な名前"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "編集中の一時的な名前", "sanity: フォーム保存で即座に反映される")

	_btn(advanced, "SkillSlotCancelButton").pressed.emit()
	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), original_name, "配置編集全体をキャンセルすると、性能編集で変更した内容も元へ戻る")

func test_cancelling_an_edit_of_an_existing_slot_does_not_delete_pre_existing_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()
	var skills_before := creator.draft.skills.size()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotCancelButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before, "編集開始前から存在していたskillはキャンセルでも消えない")
	assert_false(creator.draft.find_skill(skill_id).is_empty())

# ---------------------------------------------------------------------------
# §20: ↑↓並び替え（スロット全体を1単位として移動）
# ---------------------------------------------------------------------------

func test_move_slot_up_and_down_changes_array_order() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var first_id: String = creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	var second_id: String = creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	assert_eq(str(creator.draft.action_sequence[0].get("slot_id", "")), first_id)
	var up_button: Button = advanced._slot_list.find_child("MoveSlotUpButton_1", true, false)
	assert_not_null(up_button)
	up_button.pressed.emit()
	assert_eq(str(creator.draft.action_sequence[0].get("slot_id", "")), second_id)
	assert_eq(str(creator.draft.action_sequence[1].get("slot_id", "")), first_id)

	var down_button: Button = advanced._slot_list.find_child("MoveSlotDownButton_0", true, false)
	assert_not_null(down_button)
	down_button.pressed.emit()
	assert_eq(str(creator.draft.action_sequence[0].get("slot_id", "")), first_id)
	assert_eq(str(creator.draft.action_sequence[1].get("slot_id", "")), second_id)

# ---------------------------------------------------------------------------
# 削除の安全性
# ---------------------------------------------------------------------------

func test_deleting_a_slot_from_its_edit_screen_removes_it_and_cleans_up_unreferenced_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var skills_before := creator.draft.skills.size()
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotDeleteButton").pressed.emit()
	assert_true(creator.draft.action_sequence.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before - 1, "他から参照されなくなったskillは実体も削除される")

func test_deleting_a_slot_from_the_list_directly_also_cleans_up_unreferenced_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var skills_before := creator.draft.skills.size()
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	var delete_button: Button = advanced._slot_list.find_child("DeleteSlotButton_0", true, false)
	assert_not_null(delete_button)
	delete_button.pressed.emit()
	assert_true(creator.draft.action_sequence.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before - 1)

func test_deleting_one_slot_does_not_delete_a_skill_still_used_by_another_slot() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	var skills_before := creator.draft.skills.size()
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [{"type": "turn_at_least", "turn": 3}], "condition_logic": "AND", "max_uses": -1})
	advanced.refresh()

	var delete_button: Button = advanced._slot_list.find_child("DeleteSlotButton_0", true, false)
	delete_button.pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 1, "もう1つの配置は残る")
	assert_eq(creator.draft.skills.size(), skills_before, "まだ別配置から参照されているのでskill自体は消えない")

func test_deleting_a_random_slot_removes_it_and_cleans_up_all_its_candidate_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var advanced := _open_advanced(creator)._advanced_view
	var skills_before := creator.draft.skills.size()

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補A")
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_eq(creator.draft.skills.size(), skills_before + 1)

	var edit_button: Button = advanced._slot_list.find_child("EditSlotButton_0", true, false)
	edit_button.pressed.emit()
	assert_true(advanced._random_editor_view.visible)
	_btn(advanced, "RandomDeleteButton").pressed.emit()
	assert_true(creator.draft.action_sequence.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before, "ランダム攻撃自体を削除すると、その候補として作られたskillも片付く")

# ---------------------------------------------------------------------------
# ステップ検証委譲（is_step_valid/validation_message）
# ---------------------------------------------------------------------------

func test_step3_is_step_valid_delegates_to_the_currently_visible_mode() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	assert_true(step3.is_step_valid(), "SIMPLE mode with normal actions off and zero scripted actions defaults to valid")

	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	step3.refresh()
	creator.draft.action_sequence.clear()
	assert_true(step3.is_step_valid(), "zero action_sequence overall is valid — the boss simply has no HARDCORE AI configured")

	creator.draft.add_action_slot({"kind": "random", "candidates": [], "conditions": [], "condition_logic": "AND", "max_uses": -1})
	assert_false(step3.is_step_valid(), "a registered random slot with zero candidates is what's actually invalid")
	assert_ne(step3.validation_message(), "")

	creator.draft.action_sequence.clear()
	creator.draft.add_action_slot({"kind": "skill", "skill_id": str(creator.draft.skills[0].get("skill_id", "")), "conditions": [], "condition_logic": "AND", "max_uses": -1})
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
