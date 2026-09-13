extends SceneTree

## HARDCORE Creator STEP3全面再設計（2026-09-05）実機確認用ハーネス——実GPU
## レンダリング（非headless）で新STEP3 UI（RBMCreatorStep4ActionPatterns）を
## 実際に操作し、§31の全項目を1280×720で確認する: 0件/通常攻撃1件/複数件/
## 既存の再利用/条件付き/使用回数制限/ランダム攻撃/ランダム内で既存を追加/
## ランダム内で新規作成/スクロール/編集/削除/↑↓並び替え。最後にTEST BATTLEで
## A→B→C→Aが1ターン1攻撃のround-robinで実行されることも実際のBattleログで
## 確認する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/step3_new_ui/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/step3_new_ui"

var _root: RBMGameRoot

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

## 正式GPU runner成功判定contract(2026-09-13制定)。詳細はtools/gpu_runner.gd
## 冒頭コメント参照。falseのままならrunnerはexit code 0を返さない。
var _gpu_verification_completed := false

func run_gpu_verification(tree: SceneTree) -> int:
	_tree_override = tree
	print("STEP3 new UI capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_click(_root, "CreateModeButton")
	await _tree().process_frame
	_click(_root.creator_entry, "NewBossButton")
	await _tree().process_frame
	_click(_root.creator_entry, "ChooseAdvancedModeButton")
	await _tree().process_frame
	await _tree().process_frame

	var main: RBMCreatorMain = _root.creator_entry.main
	print("mode is advanced: %s" % (main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED))
	main.draft.boss_name = "実機確認ボス"
	main.draft.hp = 2000
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")

	main.go_to_step(3)
	await _tree().process_frame
	var step4: RBMCreatorStep4 = main._step_views[2]
	var advanced: RBMCreatorStep4ActionPatterns = step4._advanced_view
	print("advanced view visible: %s" % advanced.visible)

	# §31-1: 0件。
	await _shot("00_zero_attacks")

	# §31-2: 通常攻撃1件（新しく攻撃を作る）。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	print("skill_slot_view form_active: %s" % advanced._skill_slot_form_active)
	await _shot("01_new_attack_form_open")
	advanced._form._name_edit.text = "斬撃A"
	advanced._form._attack_multiplier_spin.value = 1.0
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	print("slot count after first attack: %d" % main.draft.action_sequence.size())
	await _shot("02_one_normal_attack")

	# §31-3: 複数件。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "斬撃B"
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	await _shot("03_multiple_attacks")

	# §31-4: 再利用（既存の攻撃から選ぶ）——「斬撃A」を別スロットとしても配置する。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoicePickExistingButton")
	await _tree().process_frame
	await _shot("04_pick_existing_list")
	_click(advanced, "PickExistingSkillButton_0")
	await _tree().process_frame
	print("skill_slot performance summary visible: %s" % advanced._skill_slot_performance_summary_row.visible)
	await _shot("05_pick_existing_summary")
	var skills_before_reuse: int = main.draft.skills.size()
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	print("skills.size before/after reuse (must be unchanged, no new skill created): %d -> %d" % [skills_before_reuse, main.draft.skills.size()])
	await _shot("06_reused_attack_added")

	# §31-5: 条件付き。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "条件付き攻撃"
	_click(advanced, "AddConditionButton")
	await _tree().process_frame
	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("hp_at_most"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	advanced._condition_percent_spin.value = 30.0
	await _shot("07_condition_editor_open")
	_click(advanced, "ConfirmConditionButton")
	await _tree().process_frame
	print("pending_conditions after confirm: %d" % advanced._pending_conditions.size())
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	await _shot("08_conditional_attack_added")

	# §31-6: 使用回数制限。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "限定攻撃"
	advanced._uses_limited_check.button_pressed = true
	advanced._on_uses_limited_toggled(true)
	advanced._uses_count_spin.value = 2.0
	await _shot("09_uses_limited_editor")
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	await _shot("10_uses_limited_attack_added")

	# §31-7: ランダム攻撃。
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateRandomButton")
	await _tree().process_frame
	print("random editor visible: %s" % advanced._random_editor_view.visible)
	await _shot("11_random_editor_empty")

	# §31-8: ランダム内で既存を追加。
	_click(advanced, "RandomAddCandidateButton")
	await _tree().process_frame
	_click(advanced, "RandomAddChoicePickExistingButton")
	await _tree().process_frame
	await _shot("12_random_pick_existing_list")
	_click(advanced, "RandomPickExistingSkillButton_0")
	await _tree().process_frame
	print("random candidates after pick-existing: %d" % advanced._random_candidates.size())
	await _shot("13_random_with_existing_candidate")

	# §31-9: ランダム内で新規作成。
	_click(advanced, "RandomAddCandidateButton")
	await _tree().process_frame
	_click(advanced, "RandomAddChoiceCreateNewButton")
	await _tree().process_frame
	await _shot("14_random_create_new_form")
	advanced._form._name_edit.text = "ランダム候補新規"
	_click(advanced._form, "SaveActionButton")
	await _tree().process_frame
	print("random candidates after create-new: %d, skills.size=%d" % [advanced._random_candidates.size(), main.draft.skills.size()])
	await _shot("15_random_with_two_candidates")
	_click(advanced, "RandomConfirmButton")
	await _tree().process_frame
	print("slot count after random confirm: %d" % main.draft.action_sequence.size())
	await _shot("16_random_attack_added_to_list")

	# §31-10: スクロール。
	var scroll: ScrollContainer = advanced._scroll_container
	var v_bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(v_bar.max_value)
	await _tree().process_frame
	await _tree().process_frame
	print("scroll_vertical=%d max=%d" % [scroll.scroll_vertical, int(v_bar.max_value)])
	await _shot("17_scrolled_list")
	scroll.scroll_vertical = 0
	await _tree().process_frame

	# §31-11: 編集。
	_click(advanced, "EditSlotButton_0")
	await _tree().process_frame
	print("edit view: performance_summary_visible=%s" % advanced._skill_slot_performance_summary_row.visible)
	await _shot("18_edit_existing_slot")
	_click(advanced, "SkillSlotEditPerformanceButton")
	await _tree().process_frame
	await _shot("19_edit_performance_form_open")
	advanced._form._name_edit.text = "斬撃A改"
	_click(advanced._form, "SaveActionButton")
	await _tree().process_frame
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	await _shot("20_after_edit_saved")

	# §31-12: 削除。
	var count_before_delete: int = main.draft.action_sequence.size()
	_click(advanced, "DeleteSlotButton_0")
	await _tree().process_frame
	print("slot count before/after delete: %d -> %d" % [count_before_delete, main.draft.action_sequence.size()])
	await _shot("21_after_delete")

	# §31-13: ↑↓並び替え。
	var order_before: Array = []
	for slot in main.draft.action_sequence:
		order_before.append(str(slot.get("slot_id", "")))
	_click(advanced, "MoveSlotUpButton_1")
	await _tree().process_frame
	var order_after: Array = []
	for slot in main.draft.action_sequence:
		order_after.append(str(slot.get("slot_id", "")))
	print("order before: %s" % str(order_before))
	print("order after moving slot 1 up: %s" % str(order_after))
	await _shot("22_after_reorder")

	# --- TEST BATTLE: A→B→C→Aが1ターン1攻撃のround-robinで実行されることを
	# 確認する。全て条件なし・使用回数無制限の3スロットへ作り直してから
	# TEST BATTLEへ入る（この構成では、Aが発火した直後cursorがBへ進み、
	# Bは常に無条件で即座に適格なので必ず次のターンに発火する、という
	# §1の「1ターン=1スロット・末尾から先頭へ自動的にループする」挙動を
	# 最も単純な形で観測できる）。
	main.draft.action_sequence.clear()
	advanced.refresh()
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "A"
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "B"
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	_click(advanced, "AddSlotButton")
	await _tree().process_frame
	_click(advanced, "AddChoiceCreateNewButton")
	await _tree().process_frame
	advanced._form._name_edit.text = "C"
	_click(advanced, "SkillSlotConfirmButton")
	await _tree().process_frame
	print("A/B/C sequence built: %d slots" % main.draft.action_sequence.size())

	main.go_to_step(6)
	await _tree().process_frame
	await _shot("23_step6_summary_abc")

	var test_result: Dictionary = main.press_test_battle()
	print("press_test_battle ok=%s errors=%s" % [test_result.get("ok", false), test_result.get("errors", [])])
	await _tree().process_frame
	await _tree().process_frame
	await _shot("24_test_battle_opened")

	var test_view = main._test_battle_view
	var battle: RBMBattle = test_view.session.battle
	for turn in range(1, 5):
		var log: Array = battle.advance_to_next_decision()
		if not battle.battle_over and battle.is_waiting_for_ally_action():
			log.append_array(battle.resolve_pending_ally_action({"type": "attack"}))
			log.append_array(battle.advance_to_next_decision())
		var boss_entries: Array = []
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				boss_entries.append(entry)
		print("turn %d boss_entries=%s cursor=%d" % [turn, str(boss_entries), battle.hardcore_action_cursor()])
		await _tree().process_frame
		await _shot("25_test_battle_turn_%d" % turn)

	print("STEP3 new UI capture done")
	_gpu_verification_completed = true
	return 0

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
