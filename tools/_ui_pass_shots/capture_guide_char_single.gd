extends SceneTree

## §4/§7確認補助: Creator「作成方法を選択」画面を1枚だけ撮影する軽量ハーネス。

const OUT_DIR := "res://tools/_ui_pass_shots/out/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/single_shot_stages"

func _init() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var game_root := RBMGameRoot.new()
	root.add_child(game_root)
	await process_frame
	await process_frame

	game_root.find_child("CreateModeButton", true, false).pressed.emit()
	await process_frame
	var entry: RBMCreatorEntry = game_root.creator_entry
	entry.find_child("NewBossButton", true, false).pressed.emit()
	await process_frame
	await process_frame

	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "14_creator_mode_choice_art.png"))
	print("saved 14_creator_mode_choice_art.png")
	quit()
