extends GutTest

## RPG BOSS MAKER Creator STEP3「行動」— 既存攻撃の行動名を変更して保存しても
## BOSS PROFILE > ACTIONS の表示が更新されない不具合の再発防止テスト。
##
## 根本原因: 「性能を編集」を押すと、共有フォーム(RBMActionEditorForm)自身の
## [保存][キャンセル]行が画面中央に現れるが、その外側にある
## RBMCreatorStep4ActionPatternsの[保存][キャンセル][この攻撃を削除]行
## (SkillSlotConfirmButton等)が、修正前は隠されずに同時表示されたままだった。
## 外側の[保存](SkillSlotConfirmButton)は、覚醒編集以外の型では常に
## _skill_slot_skill_id(編集開始時点のskill_id)を使うだけでフォームの
## 「現在の入力値」を一切読まないため、内側フォーム自身の保存ボタンを押す
## 前に外側の[保存]を押してしまうと、入力中の新しい行動名がdraft.skillsへ
## 一切反映されないまま画面が閉じ、結果としてBOSS PROFILE > ACTIONS・攻撃
## 一覧・再編集時の表示すべてが旧名称のまま残っていた。
##
## 修正は2段構え:
## 1. _refresh_skill_slot_view()で、内側フォームが自分自身の保存/キャンセル
##    を持つ文脈(_form_context=="skill_slot_edit_performance")の間は、外側の
##    [保存][キャンセル][この攻撃を削除]行(_skill_slot_actions_row)自体を
##    隠す——実際のクリックでは二重の「保存」ボタンに惑わされて誤操作
##    しようがなくなる。
## 2. 万一(_pressed.emit()での直接呼び出し等)外側の[保存]が内側フォームの
##    開いたまま呼ばれても、_on_skill_slot_confirm_pressed()がフォームの
##    現在値をdraft.update_skill()へ反映してから続行する防御を追加。

const TEST_DIR := "user://bossmaker_test_step3_action_name/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

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

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _fill_minimum_valid_boss(creator: RBMCreatorMain, boss_name: String) -> void:
	creator.draft.boss_name = boss_name
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_party_character("hero")
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)

func _advanced_view(creator: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	return step3._advanced_view

## §11 (ユーザー要求のステップ1〜6): ゴーレムアタック→無属性への改名が
## Draft・BOSS PROFILE ACTIONS・再編集時の読み込みすべてへ正しく反映される
## ことを、実際のボタン操作(公開API/シグナル経由)で確認する。
func test_renaming_an_existing_action_updates_draft_and_boss_profile_actions() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "ゴーレム試験ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	assert_eq(creator._boss_profile_panel._actions_label.text, "01 ゴーレムアタック", "sanity: 作成直後は元の名前が表示される")

	# ステップ2〜3: 既存攻撃の編集画面を開き、行動名を「無属性」へ変更して保存する。
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "無属性"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	# ステップ4: 保存されたデータのnameが「無属性」になっていること。
	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "無属性", "保存データ自体が新しい名前へ更新されること")

	# ステップ5: 右側ACTIONS表示も「無属性」になっていること。
	assert_eq(creator._boss_profile_panel._actions_label.text, "01 無属性", "BOSS PROFILE > ACTIONS が即座に新しい名前へ更新されること")

	# 攻撃一覧(SlotList)自身のカード表示も併せて確認。
	var card: VBoxContainer = advanced._slot_list.get_child(0)
	var card_texts := PackedStringArray()
	for child in card.get_children():
		if child is Label:
			card_texts.append((child as Label).text)
	assert_true("\n".join(card_texts).contains("無属性"), "STEP3内の攻撃一覧カードも新しい名前へ更新されること")

	# ステップ6: 再度編集画面を開いても「無属性」が読み込まれること。
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	assert_eq(advanced._form._name_edit.text, "無属性", "再編集時の行動名フィールドにも新しい名前が読み込まれること")
	_btn(advanced._form, "CancelActionButton").pressed.emit()
	_btn(advanced, "SkillSlotCancelButton").pressed.emit()

## ステップ7: 保存→再ロード後も「無属性」が維持されること。
func test_renamed_action_survives_save_and_reload() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "リロード試験ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "無属性"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	var save_result := creator.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)), "sanity: %s" % [save_result])
	var stage_id := str(save_result.get("stage_id", ""))

	var creator2 := _new_creator()
	var load_result := creator2.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "sanity: %s" % [load_result])
	var skill_id2 := str(creator2.draft.skills[0].get("skill_id", ""))
	assert_eq(str(creator2.draft.find_skill(skill_id2).get("name", "")), "無属性", "再ロード後もdraft.skillsの名前は新しい名前のまま")

	creator2.go_to_step(3)
	var step3_2: RBMCreatorStep4 = creator2._step_views[2]
	assert_eq(creator2._boss_profile_panel._actions_label.text, "01 無属性", "再ロード後、BOSS PROFILE > ACTIONSも新しい名前のまま")

## ゴーレム固有の不具合ではないことの確認(別のボス名・別の攻撃名で再現)。
func test_rename_fix_is_not_specific_to_any_particular_boss_or_action_name() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "竜の試験ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ドラゴンブレス"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "業火の吐息"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "業火の吐息")
	assert_eq(creator._boss_profile_panel._actions_label.text, "01 業火の吐息")

# ---------------------------------------------------------------------------
# 根本原因そのものの直接検証: 外側の[保存]が内側フォームを開いたままの状態を
# もう作れないこと・万一作られても入力内容を握りつぶさないこと。
# ---------------------------------------------------------------------------

func test_outer_actions_row_is_hidden_while_the_inline_performance_form_is_open() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "テストボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	assert_true(advanced._skill_slot_actions_row.visible, "性能編集を開く前は外側の保存/キャンセル/削除行が見えている")
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	assert_false(advanced._skill_slot_actions_row.visible, "内側フォームが開いている間は外側の保存/キャンセル/削除行を隠す")

	_btn(advanced._form, "SaveActionButton").pressed.emit()
	assert_true(advanced._skill_slot_actions_row.visible, "内側フォームの保存後は外側の行が再び見えるようになる")

## 万一(直接呼び出し等)外側の[保存]が内側フォームの開いたまま実行されても、
## 入力中の内容を握りつぶさない防御そのものの検証(_on_skill_slot_confirm_
## pressed()内の追加分岐)。
func test_outer_confirm_defensively_commits_pending_form_data_even_if_form_still_active() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "防御テストボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "無属性"
	# 内側フォーム自身のSaveActionButtonを押さず、直接外側のSkillSlotConfirmButton
	# を呼ぶ(通常のUI操作では(1)により到達しないが、防御ロジック自体を検証する)。
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "無属性", "外側の保存だけでも、開いたままのフォームの入力内容が失われないこと")

## §9-B: 名前以外のフィールド(属性)も同じ経路で更新されるため、同じ不具合の
## 影響を受けていたはず——同じ修正で一緒に直っていることを確認する。
func test_attribute_field_is_also_protected_by_the_same_fix() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "属性テストボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "斬撃"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))
	assert_eq(str(creator.draft.find_skill(skill_id).get("attribute", "")), "NEUTRAL", "sanity")

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	var fire_index: int = RBMDefinitionLoader.VALID_ATTRIBUTES.find("FIRE")
	advanced._form._attack_attribute_option.select(fire_index)
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("attribute", "")), "FIRE", "属性の変更も正しく保存されること")

## §9-F: 同じセッション内で行動名を複数回変更しても、最終的な名前が正しく
## 維持されること。
func test_renaming_multiple_times_in_one_session_keeps_the_final_name() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "多重改名テストボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "仮の名前1"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "仮の名前1")

	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	assert_eq(advanced._form._name_edit.text, "仮の名前1", "再度性能編集を開くと直前に保存した名前が読み込まれる")
	advanced._form._name_edit.text = "無属性"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "無属性", "最後に保存した名前が最終的に維持される")
	assert_eq(creator._boss_profile_panel._actions_label.text, "01 無属性")

## §6: 名前だけを変更した場合、他の攻撃設定(種類/対象/属性/ATK倍率/条件/
## 使用回数)が変化しないこと。
func test_renaming_only_the_name_does_not_change_other_action_settings() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "無変更確認ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	advanced._form._attack_target_option.select(1)  # 全体
	advanced._form._attack_attribute_option.select(RBMDefinitionLoader.VALID_ATTRIBUTES.find("ICE"))
	advanced._form._attack_multiplier_spin.value = 2.5
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "無属性"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	var skill := creator.draft.find_skill(skill_id)
	assert_eq(str(skill.get("name", "")), "無属性")
	assert_eq(str(skill.get("target", "")), "all", "対象は変更されないこと")
	assert_eq(str(skill.get("attribute", "")), "ICE", "属性は変更されないこと")
	assert_eq(float(skill.get("atk_multiplier", -1.0)), 2.5, "ATK倍率は変更されないこと")

## §10: Test Battle(RBMDefinitionLoader.to_definition()経由)へも新しい名前が
## 伝播すること——名前自体はダメージ計算に関与しないため、ここでは
## Definitionのskills配列に新しい名前が反映されることだけを確認する。
func test_renamed_action_name_propagates_to_definition_used_by_test_battle_and_clear_check() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "Definition確認ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ゴーレムアタック"
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var skill_id := str(creator.draft.skills[0].get("skill_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "無属性"
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	var definition := creator.draft.to_definition()
	var found_name := ""
	for s in (definition["boss"] as Dictionary)["skills"]:
		if str((s as Dictionary).get("skill_id", "")) == skill_id:
			found_name = str((s as Dictionary).get("name", ""))
	assert_eq(found_name, "無属性", "Test Battle/Clear Checkが参照するDefinitionにも新しい名前が伝播すること")

# ---------------------------------------------------------------------------
# 類似不具合の再調査: ランダム攻撃の候補性能編集は別画面(_show_only)へ
# 切り替える構造のため、同種の「外側の保存ボタンが同時に見える」状況が
# そもそも起こり得ないことを構造的に確認する。
# ---------------------------------------------------------------------------

func test_random_candidate_performance_edit_does_not_expose_the_outer_confirm_button_simultaneously() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "ランダム攻撃確認ボス")
	var advanced := _advanced_view(creator)

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "ランダム候補A"
	_btn(advanced._form, "SaveActionButton").pressed.emit()

	_btn(advanced, "EditRandomCandidateButton_0").pressed.emit()
	assert_false(_btn(advanced, "RandomConfirmButton").is_visible_in_tree(), "候補の性能編集中は外側のRandomConfirmButtonが画面上に見えていないこと(別ビューへ切り替わっているため)")
	advanced._form._name_edit.text = "ランダム候補A改"
	_btn(advanced._form, "SaveActionButton").pressed.emit()

	var candidate_skill_id := str((advanced._random_candidates[0] as Dictionary).get("skill_id", ""))
	assert_eq(str(creator.draft.find_skill(candidate_skill_id).get("name", "")), "ランダム候補A改")
