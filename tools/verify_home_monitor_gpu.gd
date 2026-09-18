extends Node

var _gpu_verification_completed := false

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)

	var side := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--side="):
			side = arg.substr("--side=".length())

	var root := RBMGameRoot.new()
	tree.root.add_child(root)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame

	# タイトル→START→時計SYSTEM CORE起動演出(既存・無改修)を最後まで進めて
	# から、初めてホーム画面(モニター群)が露出する——RBMTitleBootLauncher.
	# boot_completedを直接awaitする。
	var start_button: Control = root._title_boot_launcher.find_child("StartButton", true, false)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	start_button.gui_input.emit(press)
	if start_button is BaseButton:
		start_button.pressed.emit()
	await root._title_boot_launcher.boot_completed
	await tree.process_frame

	if side == "":
		var shot0 := tree.root.get_texture().get_image()
		shot0.save_png(output_dir + "/prod_idle.png")
		print("saved prod_idle.png")

		root._challenge_monitor.mouse_entered.emit()
		await _hold(tree, 0.3)
		var shot1 := tree.root.get_texture().get_image()
		shot1.save_png(output_dir + "/prod_hover_left.png")
		print("saved prod_hover_left.png")
		root._challenge_monitor.mouse_exited.emit()
		await _hold(tree, 0.2)

		root._creator_monitor.mouse_entered.emit()
		await _hold(tree, 0.3)
		var shot2 := tree.root.get_texture().get_image()
		shot2.save_png(output_dir + "/prod_hover_right.png")
		print("saved prod_hover_right.png")
		root._creator_monitor.mouse_exited.emit()
		await _hold(tree, 0.2)

		# 往復導線チェック: タイトル→左クリック→Challenge→戻る→右クリック→
		# Creator→戻る、で例外なく正しい状態になることを確認する。
		_click(root._challenge_monitor)
		await _hold(tree, 3.0)
		var ok1: bool = root.challenge_entry.visible and not root._title_screen.visible
		root._on_challenge_exit_requested()
		await tree.process_frame
		var sfx_stopped1: bool = not _any_sfx_playing(root._challenge_monitor_sfx)
		var ok2: bool = root._title_screen.visible and root._challenge_monitor._state == RBMHomeMonitorPanel._State.IDLE
		var ok2b: bool = root._challenge_monitor.position == RBMGameRoot.HOME_MONITOR_CHALLENGE_RECT.position and root._challenge_monitor.size == RBMGameRoot.HOME_MONITOR_CHALLENGE_RECT.size

		var shot_back1 := tree.root.get_texture().get_image()
		shot_back1.save_png(output_dir + "/prod_back_to_menu_after_challenge.png")

		_click(root._creator_monitor)
		await _hold(tree, 3.0)
		var ok3: bool = root.creator_entry.visible and not root._title_screen.visible
		root._on_creator_exit_requested()
		await tree.process_frame
		var sfx_stopped2: bool = not _any_sfx_playing(root._creator_monitor_sfx)
		var ok4: bool = root._title_screen.visible and root._creator_monitor._state == RBMHomeMonitorPanel._State.IDLE
		var ok4b: bool = root._creator_monitor.position == RBMGameRoot.HOME_MONITOR_CREATE_RECT.position and root._creator_monitor.size == RBMGameRoot.HOME_MONITOR_CREATE_RECT.size

		var shot_back2 := tree.root.get_texture().get_image()
		shot_back2.save_png(output_dir + "/prod_back_to_menu_after_creator.png")

		print("NAV_ROUNDTRIP: challenge_enter=%s challenge_return=%s challenge_return_rect=%s creator_enter=%s creator_return=%s creator_return_rect=%s" % [ok1, ok2, ok2b, ok3, ok4, ok4b])
		print("SFX_STOPPED_AFTER_TRANSITION: challenge=%s creator=%s" % [sfx_stopped1, sfx_stopped2])
		var all_ok: bool = ok1 and ok2 and ok2b and ok3 and ok4 and ok4b and sfx_stopped1 and sfx_stopped2
		print("NAV_ROUNDTRIP_ALL_OK=%s" % all_ok)

		_gpu_verification_completed = true
		return 0

	var target: RBMHomeMonitorPanel = root._challenge_monitor if side == "left" else root._creator_monitor
	_click(target)
	await _hold(tree, 3.0)

	_gpu_verification_completed = true
	return 0

func _any_sfx_playing(sfx: RBMHomeMonitorSfx) -> bool:
	for child in sfx.get_children():
		if child is AudioStreamPlayer and child.playing:
			return true
	return false

func _click(panel: RBMHomeMonitorPanel) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	panel.gui_input.emit(release)

func _hold(tree: SceneTree, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await tree.process_frame
		var dt: float = tree.root.get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		elapsed += dt
