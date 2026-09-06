extends SceneTree

## 使い捨て: GuideCharacterを非表示にして、背景だけの実スクリーンショット
## を撮る。発見した白いブロックが本当に背景美術の一部かどうかを直接
## 確認するため。

const OUT_DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/bg_only_stage"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter

func _init() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	root.add_child(_root)
	await process_frame
	await process_frame

	_root.find_child("CreateModeButton", true, false).pressed.emit()
	await process_frame
	_entry = _root.creator_entry
	_entry.find_child("NewBossButton", true, false).pressed.emit()
	await process_frame
	await process_frame

	_char = _entry.find_child("GuideCharacter", true, false)
	_char.visible = false

	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "frame_BG_ONLY.png"))
	print("saved frame_BG_ONLY.png (character hidden)")
	quit()
