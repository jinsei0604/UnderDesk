extends Node

## ウィンドウ終了要求(右上の×/Alt+F4)の未保存確認の実機(実GPUウィンドウ)検証。
##
## 実行はtools/gpu_runner.tscn経由(README参照)。このツールは本番のRBMGameRoot
## をそのまま起動し、Creator編集中の状態を作って外部からのOS終了メッセージ
## (WM_SYSCOMMAND/SC_CLOSE=タイトルバーの×、実際のAlt+F4キー入力)を待つ。
## 外部ドライバ(PowerShell)が各シナリオの合図(標準出力のマーカー)を見て
## メッセージを送り、確認パネルの出現/終了の有無をログとスクリーンショットで
## 確かめる。
##
## 引数: --scenario=dirty|clean
##   dirty: 未保存あり。close#1(×) → 確認表示 → キャンセルで維持 →
##          close#2(Alt+F4)+連打 → 確認は1つのまま → 保存せず終了で終了。
##   clean: 未保存なし。close(×)だけで確認なしに終了する。
##
## 標準出力のマーカー(外部ドライバが待つ): WCV_READY / WCV_CANCELLED_READY_FOR_2 /
## WCV_MASH_WINDOW / WCV_PRESSING_DISCARD ほか。

var _gpu_verification_completed := false

func run_gpu_verification(tree: SceneTree, output_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	var scenario := "dirty"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.substr("--scenario=".length())

	var root := RBMGameRoot.new()
	tree.root.add_child(root)
	for i in range(4):
		await tree.process_frame

	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_simple_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	if scenario == "dirty":
		main.draft.boss_name = "未保存のボス"
		main.draft.hp = 1234
		main._refresh()
	for i in range(3):
		await tree.process_frame
	print("WCV_INFO auto_accept_quit=%s main_visible=%s has_unsaved=%s" % [tree.auto_accept_quit, main.visible, main.has_unsaved_changes()])
	var panel: PanelContainer = main._exit_confirm_panel
	tree.root.get_texture().get_image().save_png(output_dir + "/wcv_%s_00_ready.png" % scenario)
	print("WCV_READY scenario=%s" % scenario)

	if scenario == "clean":
		# 外部の×で確認なしに即終了するはず。終了しなければ失敗として残す。
		await _wait_seconds(tree, 30.0)
		print("WCV_FAIL clean scenario did not quit within 30s panel_visible=%s" % panel.visible)
		_gpu_verification_completed = true
		return 1

	# --- close#1 (×) ---
	if not await _wait_until(tree, func(): return panel.visible, 60.0):
		print("WCV_FAIL close#1 never showed the confirm panel")
		_gpu_verification_completed = true
		return 1
	for i in range(3):
		await tree.process_frame
	tree.root.get_texture().get_image().save_png(output_dir + "/wcv_dirty_01_close1_panel.png")
	print("WCV_CLOSE1_PANEL_SHOWN still_running=true panel_count=%d main_visible=%s" % [_panel_count(main), main.visible])

	# キャンセル → 編集内容維持。
	(main.find_child("ExitConfirmCancelButton", true, false) as Button).pressed.emit()
	for i in range(3):
		await tree.process_frame
	print("WCV_CANCEL_RESULT panel_visible=%s main_visible=%s boss_name=%s hp=%d has_unsaved=%s" % [panel.visible, main.visible, main.draft.boss_name, main.draft.hp, main.has_unsaved_changes()])
	tree.root.get_texture().get_image().save_png(output_dir + "/wcv_dirty_02_after_cancel.png")
	print("WCV_CANCELLED_READY_FOR_2")

	# --- close#2 (Alt+F4) ---
	if not await _wait_until(tree, func(): return panel.visible, 60.0):
		print("WCV_FAIL close#2 never showed the confirm panel")
		_gpu_verification_completed = true
		return 1
	for i in range(3):
		await tree.process_frame
	tree.root.get_texture().get_image().save_png(output_dir + "/wcv_dirty_03_close2_panel.png")
	print("WCV_CLOSE2_PANEL_SHOWN panel_count=%d" % _panel_count(main))

	# 連打窓: 外部が×/Alt+F4を連打する間、確認は1つのまま・終了しない。
	print("WCV_MASH_WINDOW")
	await _wait_seconds(tree, 10.0)
	print("WCV_MASH_RESULT still_running=true panel_visible=%s panel_count=%d main_visible=%s boss_name=%s" % [panel.visible, _panel_count(main), main.visible, main.draft.boss_name])
	tree.root.get_texture().get_image().save_png(output_dir + "/wcv_dirty_04_after_mash.png")

	# 保存せず終了 → 実際にプロセスが終了する(以降は確認が再び出ない)。
	print("WCV_PRESSING_DISCARD")
	(main.find_child("ExitConfirmDiscardButton", true, false) as Button).pressed.emit()
	await _wait_seconds(tree, 8.0)
	print("WCV_FAIL discard did not quit the game")
	_gpu_verification_completed = true
	return 1

func _panel_count(main: Node) -> int:
	return main.find_children("ExitConfirmPanel", "PanelContainer", true, false).size()

func _wait_until(tree: SceneTree, condition: Callable, timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if condition.call():
			return true
		await tree.process_frame
		var dt: float = tree.root.get_process_delta_time()
		elapsed += dt if dt > 0.0 else 1.0 / 60.0
	return bool(condition.call())

func _wait_seconds(tree: SceneTree, seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await tree.process_frame
		var dt: float = tree.root.get_process_delta_time()
		elapsed += dt if dt > 0.0 else 1.0 / 60.0
