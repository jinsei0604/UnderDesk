extends SceneTree

## 診断用: 手の微動E単体（A→E→A）を約4秒録画する。Dは発火させない。
## 実行には必ずウィンドウ有りの通常exeを使うこと。

const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/movie_e_only_stages"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter
var _elapsed := 0.0

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

func run_gpu_verification(tree: SceneTree) -> void:
	_tree_override = tree
	print("E-only diagnostic movie starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_click(_root, "CreateModeButton")
	await _tree().process_frame
	_entry = _root.creator_entry
	_click(_entry, "NewBossButton")
	await _tree().process_frame
	await _tree().process_frame

	_char = _entry.find_child("GuideCharacter", true, false)
	if _char != null:
		_char._next_d_time = 999.0
		_char._next_e_time = 0.5

	print("recording begins (E only: A -> E -> A)")
	while _elapsed < 4.0:
		await _tree().process_frame
		_elapsed += 1.0 / 60.0

	print("E-only movie done at t=%.2f" % _elapsed)

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()
