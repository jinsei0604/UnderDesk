extends SceneTree

## STEP3「行動」表示順修正（2026-09-05）実機確認用ハーネス——実GPU
## レンダリング（非headless）でADVANCEDモードのRBMCreatorStep4ActionPatternsを
## 実際に操作し、①初期状態で「行動パターン」一覧が正常②パターンを開くと
## 「追加ルール」がSTEP3編集パネルの最下部（行動作成フォームより下）にある
## こと③通常攻撃/ランダム攻撃/既存行動編集のいずれでもフォームが追加ルール
## より上に表示されること④ScrollContainerがフォーム表示中も最下部まで正常に
## スクロールできること⑤追加ルール自体の既存操作・保存/キャンセル/削除が
## 正常なこと⑥STEP1に影響がないこと、を確認する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/step3_rule_order/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/step3_rule_order"

var _root: RBMGameRoot

func _init() -> void:
	print("STEP3 rule-order capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	root.add_child(_root)
	await process_frame
	await process_frame

	_click(_root, "CreateModeButton")
	await process_frame
	_click(_root.creator_entry, "NewBossButton")
	await process_frame
	_click(_root.creator_entry, "ChooseAdvancedModeButton")
	await process_frame
	await process_frame

	var main: RBMCreatorMain = _root.creator_entry.main
	print("mode is advanced: %s" % (main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED))

	# STEP1は無改修——回帰確認用に1枚だけ撮る。
	await _shot("00_step1_untouched")

	main.go_to_step(3)
	await process_frame
	print("header after go_to_step(3): title=%s step=%s" % [main._header.title_label.text, main._header.step_label.text])
	var step4: RBMCreatorStep4 = main._step_views[2]
	var advanced: RBMCreatorStep4ActionPatterns = step4._advanced_view
	print("advanced view visible: %s" % advanced.visible)
	await _shot("01_step3_initial_pattern_list")

	# ①「＋ 行動パターンを作る」でエディタパネルを開く。
	_click(advanced, "AddPatternButton")
	await process_frame
	print("editor panel visible: %s" % advanced._editor_panel.visible)
	await _shot("02_step3_editor_panel_opened")
	_report_vertical_order(advanced, "after opening empty pattern editor")

	# ②「＋ 通常攻撃を作る」でフォームを開く——フォームが追加ルールより上にあること。
	_click(advanced, "AddSkillActionButton")
	await process_frame
	print("form visible (normal action): %s" % advanced._form.visible)
	await _shot("03_step3_normal_action_form_open")
	_report_vertical_order(advanced, "normal action form open")

	# フォームへ実際に値を入れて保存——行動一覧へ反映され、フォームが閉じること。
	advanced._form._name_edit.text = "火炎爪"
	_click(advanced._form, "SaveActionButton")
	await process_frame
	print("form visible after save: %s, actions=%d" % [advanced._form.visible, advanced._editor_actions.size()])
	print("action count label: %s" % advanced._action_count_label.text)
	await _shot("04_step3_after_normal_action_saved")

	# ③「＋ ランダム攻撃を作る」→候補を追加、でもフォームが追加ルールより上にあること。
	_click(advanced, "AddRandomActionButton")
	await process_frame
	print("random editor visible: %s" % advanced._random_editor.visible)
	_click(advanced, "AddRandomCandidateButton")
	await process_frame
	print("form visible (random candidate): %s" % advanced._form.visible)
	await _shot("05_step3_random_candidate_form_open")
	_report_vertical_order(advanced, "random candidate form open")
	advanced._form._name_edit.text = "小爪"
	_click(advanced._form, "SaveActionButton")
	await process_frame
	_click(advanced, "CloseRandomEditorButton")
	await process_frame
	print("action count label after random: %s" % advanced._action_count_label.text)

	# ④ 既存行動（固定行動、上で保存した「火炎爪」）を編集した場合も同様。
	_click(advanced, "EditFixedActionButton_0")
	await process_frame
	print("form visible (edit existing): %s title=%s" % [advanced._form.visible, advanced._form._title_label.text])
	await _shot("06_step3_edit_existing_action_form_open")
	_report_vertical_order(advanced, "edit existing fixed action form open")
	_click(advanced._form, "CancelActionButton")
	await process_frame
	print("form visible after cancel: %s" % advanced._form.visible)

	# ⑤ スクロール確認——フォームが閉じた状態で最下部（保存/キャンセル/削除ボタン）まで届くこと。
	var scroll: ScrollContainer = advanced._scroll_container
	var v_bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(v_bar.max_value)
	await process_frame
	await process_frame
	var save_pattern_button: Button = advanced.find_child("SavePatternButton", true, false)
	print("scroll_vertical=%d max=%d save_button_visible_on_screen=%s" % [scroll.scroll_vertical, int(v_bar.max_value), _is_within_viewport(save_pattern_button)])
	await _shot("07_step3_scrolled_to_bottom")
	scroll.scroll_vertical = 0
	await process_frame

	# ⑥ 追加ルールの既存操作——「＋ 追加ルール」→「使用回数を制限」。
	_click(advanced, "AddRuleButton")
	await process_frame
	print("rule picker visible: %s" % advanced._add_rule_row.visible)
	_click(advanced, "AddMaxUsesRuleButton")
	await process_frame
	print("max_uses after rule add: %d" % advanced._editor_max_uses)
	await _shot("08_step3_rule_added")

	# ⑦ 保存——パターン一覧へ反映されること。
	_click(advanced, "SavePatternButton")
	await process_frame
	print("editor panel visible after save: %s, pattern_count=%d" % [advanced._editor_panel.visible, main.draft.action_patterns.size()])
	await _shot("09_step3_pattern_saved")

	# ⑧ 削除——一覧から消えること。
	_click(advanced, "EditPatternButton_0")
	await process_frame
	_click(advanced, "DeletePatternButton")
	await process_frame
	print("pattern_count after delete: %d" % main.draft.action_patterns.size())

	print("STEP3 rule-order capture done, quitting")
	quit()

func _report_vertical_order(advanced: RBMCreatorStep4ActionPatterns, label: String) -> void:
	var what_header: Control = advanced.find_child("ActionCountLabel", true, false)
	var rule_list: Control = advanced.find_child("RuleList", true, false)
	var add_rule_button: Control = advanced.find_child("AddRuleButton", true, false)
	var form_y: float = advanced._form.global_position.y
	var form_bottom: float = form_y + advanced._form.size.y
	var rule_y: float = add_rule_button.global_position.y
	print("[order:%s] action_count_label.y=%.1f form.y=%.1f form.visible=%s form_bottom=%.1f AddRuleButton.y=%.1f form_above_rule=%s" % [
		label, what_header.global_position.y, form_y, advanced._form.visible, form_bottom, rule_y, form_bottom <= rule_y
	])
	if rule_list != null:
		print("  RuleList.y=%.1f" % rule_list.global_position.y)

func _is_within_viewport(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	var viewport_size := root.size
	return rect.position.y >= 0.0 and rect.position.y < float(viewport_size.y)

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
