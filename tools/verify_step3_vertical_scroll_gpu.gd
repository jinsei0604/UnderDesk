extends Node

## HARDCORE STEP3が「横スクロール無し・縦スクロールのみ」であることの実機(実GPU)確認。
##
## 実行はtools/gpu_runner.tscn経由。動画にするにはGodotのMovie Makerで
##   Godot_v4.7-stable_win64.exe --path . --write-movie <out.avi> --fixed-fps 30 \
##     res://tools/gpu_runner.tscn -- --tool=res://tools/verify_step3_vertical_scroll_gpu.gd --output=<dir>
## のように起動する(--write-movieは通常の引数より前に置く)。
##
## 流れ: STEP3で新規攻撃フォーム+条件を積んで縦に長くする → 全体スクリーン
## ショット → 実際の入力イベント(ホイール右/Shift+ホイール)で横へ動かそうと
## しても動かない → 通常のホイールで縦にだけスクロールできる(下→上)。
## 結果は標準出力の`SVS_`行に出力する。

var _gpu_verification_completed := false
var _tree: SceneTree

## --scenario=video(既定): レイアウト確認+縦スクロールの実演(動画向け)。
## --scenario=inputs: 横へ動かそうとする入力(ホイール右/左、Shift+ホイール、
## scroll_horizontalの直接指定)の検証。Godotは横スクロール範囲が無い時、これらを
## 縦スクロールとして扱うため、動画とは分けて実行する(コンテンツが横へ動かない
## ことは`scroll_horizontal==0`で確認する)。
var _scenario := "video"

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	_tree = tree
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			_scenario = arg.substr("--scenario=".length())
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing("user://bossmaker_svs")

	var root := RBMGameRoot.new()
	tree.root.add_child(root)
	await _frames(4)
	root._top_monitor_battle.stop_loop()
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_advanced_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "実機確認ボス"
	main.draft.hp = 2000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	for character_id in ["hero", "butler", "samurai", "healer"]:
		main.draft.add_party_character(character_id)
	main.go_to_step(3)
	await _frames(3)
	var step3: RBMCreatorStep4 = main._step_views[2]
	var adv: RBMCreatorStep4ActionPatterns = step3._advanced_view

	# 新規攻撃フォーム+条件を何件か積む(縦に長くする)。
	adv.find_child("AddSlotButton", true, false).pressed.emit()
	await _frames(2)
	adv.find_child("AddChoiceCreateNewButton", true, false).pressed.emit()
	await _frames(2)
	adv._form._name_edit.text = "条件付きの攻撃"
	for i in range(7):
		adv.find_child("AddConditionButton", true, false).pressed.emit()
		await _frames(1)
	var idx: int = adv._active_condition_types.find("turn_at_least")
	adv._condition_type_option.select(idx)
	adv._condition_type_option.item_selected.emit(idx)
	adv._condition_turn_spin.value = 3
	await _frames(6)

	var scroll: ScrollContainer = adv._scroll_container
	var hbar := scroll.get_h_scroll_bar()
	var vbar := scroll.get_v_scroll_bar()
	var next_button := main.find_child("NextButton", true, false) as Button
	var profile := main.find_child("BossProfilePanel", true, false) as Control
	print("SVS_LAYOUT window=%s scroll_rect=%s h_mode=%d h_range=%.1f h_bar_visible=%s v_range=%.1f v_bar_visible=%s" % [
		str(tree.root.size), str(scroll.get_global_rect()), scroll.horizontal_scroll_mode, hbar.max_value - hbar.page, hbar.visible, vbar.max_value - vbar.page, vbar.visible])
	print("SVS_EDGES next_button_right=%.0f profile_right=%.0f (window width 1280)" % [next_button.get_global_rect().end.x, profile.get_global_rect().end.x])
	tree.root.get_texture().get_image().save_png(output_dir + "/step3_1280x720_full.png")

	var center := scroll.get_global_rect().get_center()
	await _frames(20)

	if _scenario == "inputs":
		await _run_horizontal_inputs(scroll, center)
		_gpu_verification_completed = true
		return 0

	await _frames(10)

	# --- 縦にだけスクロールできる(下 → 上)。 ---
	for i in range(30):
		_wheel(center, MOUSE_BUTTON_WHEEL_DOWN, false)
		await _frames(2)
	await _frames(20)
	var bottom_v := scroll.scroll_vertical
	tree.root.get_texture().get_image().save_png(output_dir + "/step3_1280x720_scrolled_bottom.png")
	print("SVS_VERTICAL_DOWN scroll_vertical=%d scroll_horizontal=%d v_range=%.1f" % [bottom_v, scroll.scroll_horizontal, vbar.max_value - vbar.page])
	for i in range(30):
		_wheel(center, MOUSE_BUTTON_WHEEL_UP, false)
		await _frames(2)
	await _frames(20)
	print("SVS_VERTICAL_UP scroll_vertical=%d scroll_horizontal=%d" % [scroll.scroll_vertical, scroll.scroll_horizontal])

	_gpu_verification_completed = true
	return 0

func _run_horizontal_inputs(scroll: ScrollContainer, center: Vector2) -> void:
	for i in range(6):
		_wheel(center, MOUSE_BUTTON_WHEEL_RIGHT, false)
		await _frames(2)
	await _frames(10)
	print("SVS_WHEEL_RIGHT scroll_horizontal=%d scroll_vertical=%d" % [scroll.scroll_horizontal, scroll.scroll_vertical])
	for i in range(6):
		_wheel(center, MOUSE_BUTTON_WHEEL_LEFT, false)
		await _frames(2)
	await _frames(10)
	print("SVS_WHEEL_LEFT scroll_horizontal=%d scroll_vertical=%d" % [scroll.scroll_horizontal, scroll.scroll_vertical])
	for i in range(6):
		_wheel(center, MOUSE_BUTTON_WHEEL_DOWN, true)
		await _frames(2)
	await _frames(10)
	print("SVS_SHIFT_WHEEL_DOWN scroll_horizontal=%d scroll_vertical=%d" % [scroll.scroll_horizontal, scroll.scroll_vertical])
	scroll.scroll_horizontal = 400
	await _frames(20)
	print("SVS_HORIZONTAL_FORCED scroll_horizontal=%d (must be 0)" % scroll.scroll_horizontal)


func _frames(n: int) -> void:
	for i in range(n):
		await _tree.process_frame

func _wheel(position: Vector2, button: MouseButton, shift: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		event.global_position = position
		event.shift_pressed = shift
		event.factor = 1.0
		Input.parse_input_event(event)
