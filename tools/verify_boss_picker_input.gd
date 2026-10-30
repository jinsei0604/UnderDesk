extends "res://tools/verify_musha_picker_gpu.gd"
## The original fixture supplies logical viewport positions. Keep them local
## when injecting events so DPI/window scaling cannot offset the clicks.
func _click(at: Vector2) -> void:
	_send_mouse(at, MOUSE_BUTTON_LEFT)

func _wheel(at: Vector2, button: MouseButton) -> void:
	_send_mouse(at, button)

func _send_mouse(at: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_tree.root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.global_position = at
		_tree.root.push_input(event, true)

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	await super.run_gpu_verification(tree, output_dir)
	var passed := false
	for child in tree.root.get_children():
		if child is RBMGameRoot:
			var main: RBMCreatorMain = child.creator_entry.main
			passed = main.draft.appearance_id == "appearance_musha" and main._test_battle_view.visible and main._test_battle_view.session != null
			child.queue_free()
	for i in 3: await tree.process_frame
	print("PICKER_INPUT_PASSED ", passed)
	_gpu_verification_completed = true
	return 0 if passed else 1
