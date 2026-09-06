extends SceneTree

## 診断用: 姿勢調整D単体（A→D→A）を約4秒録画する。Eは発火させない。
## 実行には必ずウィンドウ有りの通常exeを使うこと。

const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/movie_d_only_stages"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter
var _elapsed := 0.0

func _init() -> void:
	print("D-only diagnostic movie starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)

	_root = RBMGameRoot.new()
	root.add_child(_root)
	await process_frame
	await process_frame

	_click(_root, "CreateModeButton")
	await process_frame
	_entry = _root.creator_entry
	_click(_entry, "NewBossButton")
	await process_frame
	await process_frame

	_char = _entry.find_child("GuideCharacter", true, false)
	if _char != null:
		# Aフェーズの最低保持時間(0.3秒)をわずかに超えた時点でDが発火する
		# よう設定——撮影冒頭でAの静止姿勢も確認できるようにする。
		_char._next_d_time = 0.5
		_char._next_e_time = 999.0

	print("recording begins (D only: A -> D -> A)")
	while _elapsed < 4.0:
		await process_frame
		_elapsed += 1.0 / 60.0

	print("D-only movie done at t=%.2f, quitting" % _elapsed)
	quit()

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()
