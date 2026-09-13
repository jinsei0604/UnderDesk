extends SceneTree

## AD追加後のA→AD→D→AD→A系列を実GPU・実背景で撮影する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/ad_check_stage"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

func run_gpu_verification(tree: SceneTree) -> void:
	_tree_override = tree
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_root.find_child("CreateModeButton", true, false).pressed.emit()
	await _tree().process_frame
	_entry = _root.creator_entry
	_entry.find_child("NewBossButton", true, false).pressed.emit()
	await _tree().process_frame
	await _tree().process_frame

	_char = _entry.find_child("GuideCharacter", true, false)
	_char.set_process(false)

	var labels := ["A", "AD", "D"]
	var indices := [0, 7, 5]
	for i in range(labels.size()):
		_char._body.texture = _char._idle_textures[indices[i]]
		await _shot(labels[i])

	print("AD sequence screenshots captured")

func _shot(label: String) -> void:
	await _tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%sframe_%s.png" % [OUT_DIR, label]))
	print("saved frame_%s.png" % label)
