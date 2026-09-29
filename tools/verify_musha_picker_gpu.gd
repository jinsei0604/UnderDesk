extends Node

## ボス選択画面(外見ピッカー)に新ボス「朽ちた機械武者」を追加し、縦スクロール化
## した変更の実機(実GPU)確認。実際の入力イベント(ホイール/クリック)を使う。
##   Godot_v4.7-stable_win64.exe --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/verify_musha_picker_gpu.gd --output=<dir>
## 出力(標準出力の`MPK_`行): レイアウト、スクロール範囲、ホイール/クリックの結果。

var _gpu_verification_completed := false
var _tree: SceneTree

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	_tree = tree
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing("user://bossmaker_mpk")
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
	main.draft.add_party_character("hero")
	main.go_to_step(1)
	await _frames(3)
	main.open_appearance_picker()
	await _frames(6)

	var picker: RBMCreatorAppearancePicker = main._appearance_picker
	var scroll := picker.find_child("GridScroll", true, false) as ScrollContainer
	var vbar := scroll.get_v_scroll_bar()
	var hbar := scroll.get_h_scroll_bar()
	var grid := picker.find_child("AppearanceGrid", true, false) as GridContainer
	var card := picker.find_child("Appearance_appearance_musha", true, false) as Control
	print("MPK_LAYOUT window=%s scroll=%s v_range=%.0f v_bar=%s h_range=%.0f h_bar=%s cards=%d card_size=%s" % [
		str(tree.root.size), str(scroll.get_global_rect()), vbar.max_value - vbar.page, vbar.visible, hbar.max_value - hbar.page, hbar.visible, grid.get_child_count(), str(card.size)])
	tree.root.get_texture().get_image().save_png(output_dir + "/picker_1_top.png")
	print("MPK_TOP musha_card_fully_visible=%s" % scroll.get_global_rect().encloses(card.get_global_rect()))

	# 実際のホイールで、カードの上(ポインタがカード上)からスクロールできること。
	var over_card := (picker.find_child("Appearance_appearance_wolf", true, false) as Control).get_global_rect().get_center()
	for i in range(40):
		_wheel(over_card, MOUSE_BUTTON_WHEEL_DOWN)
		await _frames(2)
	await _frames(10)
	print("MPK_WHEEL_DOWN scroll_vertical=%d scroll_horizontal=%d musha_card_fully_visible=%s" % [scroll.scroll_vertical, scroll.scroll_horizontal, scroll.get_global_rect().encloses(card.get_global_rect())])
	tree.root.get_texture().get_image().save_png(output_dir + "/picker_2_scrolled_bottom.png")

	# 新ボスを実際のクリックで選ぶ。
	var confirmed_ids: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	var click_at := card.get_global_rect().get_center()
	_click(click_at)
	await _frames(8)
	print("MPK_CLICK confirmed=%s draft_appearance=%s picker_visible=%s" % [str(confirmed_ids), main.draft.appearance_id, picker.visible])
	tree.root.get_texture().get_image().save_png(output_dir + "/picker_3_after_select.png")

	# 上へ戻せること + 再度開くと新ボスが選択状態で表示される。
	main.open_appearance_picker()
	await _frames(6)
	var musha_button := picker.find_child("Appearance_appearance_musha", true, false) as Button
	print("MPK_REOPEN musha_selected=%s" % musha_button.button_pressed)
	for i in range(40):
		_wheel(over_card, MOUSE_BUTTON_WHEEL_UP)
		await _frames(1)
	await _frames(6)
	print("MPK_WHEEL_UP scroll_vertical=%d" % scroll.scroll_vertical)
	main._on_appearance_cancelled()
	await _frames(4)

	# TEST BATTLEに入ると通常表示(idle)の新ボスが実戦闘に出る。
	main.draft.add_party_character("butler")
	main.press_test_battle()
	await _frames(40)
	tree.root.get_texture().get_image().save_png(output_dir + "/battle_idle.png")
	print("MPK_DONE")
	_gpu_verification_completed = true
	return 0

func _frames(n: int) -> void:
	for i in range(n):
		await _tree.process_frame

func _wheel(at: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		event.factor = 1.0
		Input.parse_input_event(event)

func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
