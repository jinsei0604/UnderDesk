extends SceneTree

## Creator本体UIコンセプト確定パス（2026-09-05）実機確認用ハーネス——実GPU
## レンダリング（非headless、実OpenGLウィンドウ）でRBMGameRootを実際に
## 操作し、①STEP1が崩れていないこと②Creator一覧へ戻るボタン/未保存確認
## ダイアログが銀＋濃紺へ統一されたこと③STEP2のHSliderがGodot標準に
## 見えないこと④STEP2の項目が整理されていること⑤STEP1→STEP2→STEP1の
## 入力保持⑥戻る/次への遷移、を確認する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/creator_ui_kit/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/creator_ui_kit"

var _root: RBMGameRoot

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

func run_gpu_verification(tree: SceneTree) -> void:
	_tree_override = tree
	print("Creator UI kit capture starting...")
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
	_click(_root.creator_entry, "ChooseSimpleModeButton")
	await _tree().process_frame
	await _tree().process_frame
	await _shot("01_step1_normal")

	var main: RBMCreatorMain = _root.creator_entry.main
	print("header title: %s" % main._header.title_label.text)
	print("header step: %s" % main._header.step_label.text)

	# 名前入力→決定でカード表示が名前で更新されること、外見未選択の
	# プレビュー領域の見た目を確認する。
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	_click(step1, "EditNameButton")
	await _tree().process_frame
	step1._name_edit.text = "黒炎竜ヴァルガス"
	_click(step1, "ConfirmNameButton")
	await _tree().process_frame
	await _shot("02_step1_name_set")

	# 「次へ」のHover——実マウスをボタン中心へ移動させ、実際のGodot Button
	# ホバー判定(is_hovered())を経由する。
	var next_button: Button = main._next_button
	_hover(next_button)
	await _tree().process_frame
	await _tree().process_frame
	print("next button hovered: %s" % next_button.is_hovered())
	await _shot("03_step1_next_hover")

	# 次へ→STEP2でヘッダーが追従すること（通常カード表示）。
	main.press_next()
	await _tree().process_frame
	print("after next: header title=%s step=%s" % [main._header.title_label.text, main._header.step_label.text])
	await _shot("04_step2_normal")

	var step2: RBMCreatorStep2Stats = main._step_views[1]
	_click(step2, "EditStatsButton")
	await _tree().process_frame
	await _shot("05_step2_edit_panel")

	# HSliderのHover——つまみ/進捗部分がGodot既定の見た目でないこと・
	# わずかに明るくなることを確認する（HSlider/Sliderはis_hovered()を
	# 持たない——BaseButton専用のAPIのため、ここでは合成マウス移動後の
	# 見た目をスクリーンショットで直接確認する）。
	_hover(step2._hp_slider)
	await _tree().process_frame
	await _tree().process_frame
	await _shot("06_step2_hp_slider_hover")

	# 実際にスライダー/スピンボックスの値を変更→決定でDraftへ反映される
	# ことを確認する（既存シグナル経路、合成マウスドラッグではなく直接
	# .valueへ書き込む——実信号パスはtest_rbm_realplay1_ui_polish.gdと
	# 同じ確立済み手法）。
	step2._hp_spin.value = 88888
	step2._atk_spin.value = 321
	step2._spd_spin.value = 45
	(step2._weak_buttons["FIRE"] as Button).pressed.emit()
	(step2._resist_buttons["ICE"] as Button).pressed.emit()
	await _tree().process_frame
	_click(step2, "ConfirmStatsButton")
	await _tree().process_frame
	await _shot("07_step2_after_confirm")
	print("draft after confirm: hp=%d atk=%d spd=%d weak=%s resist=%s" % [main.draft.hp, main.draft.atk, main.draft.spd, main.draft.weak_attributes, main.draft.resist_attributes])

	# STEP2→STEP1→STEP2で入力保持が壊れていないこと。
	main.press_back()
	await _tree().process_frame
	print("back to step: %d" % main.current_step)
	main.go_to_step(2)
	await _tree().process_frame
	print("round-trip retained: hp=%d atk=%d spd=%d (summary=%s)" % [main.draft.hp, main.draft.atk, main.draft.spd, step2._summary_label.text])

	# Creator一覧へ戻る→未保存確認ダイアログ（銀＋濃紺への統一を確認）。
	_click(main, "ExitCreatorButton")
	await _tree().process_frame
	print("exit confirm visible: %s" % main._exit_confirm_panel.visible)
	await _shot("08_exit_confirm_dialog")
	_click(main, "ExitConfirmCancelButton")
	await _tree().process_frame
	print("exit confirm dismissed: %s" % (not main._exit_confirm_panel.visible))

	# TEST BATTLE等のサブ画面ではヘッダー/共通ナビが隠れること（既存挙動）。
	main.draft.add_party_character("hero")
	var test_result := main.press_test_battle()
	print("press_test_battle ok=%s" % test_result.get("ok", false))
	await _tree().process_frame
	print("header visible during TEST BATTLE: %s" % main._header.visible)
	await _shot("09_test_battle_header_hidden")

	print("Creator UI kit capture done")

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _hover(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	_tree().root.push_input(motion)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
