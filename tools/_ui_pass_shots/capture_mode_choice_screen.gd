extends SceneTree

## 右側UI仕上げ（2026-09-04）確認用ハーネス。実GPUレンダリング（非
## headless、実OpenGLウィンドウ）で「作成方法選択」画面を撮影する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/mode_choice_finish/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/mode_choice_finish"

var _root: RBMGameRoot

func _init() -> void:
	print("mode choice screen capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	root.add_child(_root)
	await process_frame
	await process_frame

	_click(_root, "CreateModeButton")
	await process_frame
	var creator_entry: RBMCreatorEntry = _root.creator_entry
	_click(creator_entry, "NewBossButton")
	await process_frame
	await process_frame
	await _shot("01_mode_choice")

	# ホバー状態も1枚確認する（SIMPLEパネル）。
	var simple_btn: Button = creator_entry.find_child("ChooseSimpleModeButton", true, false)
	var simple_surface = simple_btn.find_child("MethodCardSurface", true, false)
	simple_surface.set_state(true, false)
	simple_surface._process(0.2)
	await process_frame
	await _shot("02_simple_hover")
	simple_surface.set_state(false, false)
	simple_surface._process(0.2)

	# 既存遷移確認: SIMPLE/HARDCORE/戻る。
	_click(creator_entry, "ChooseSimpleModeButton")
	await process_frame
	var simple_transition_ok: bool = creator_entry.main.visible and creator_entry.main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_SIMPLE
	print("transition check: SIMPLE -> creator visible+simple mode = %s" % simple_transition_ok)

	# 巻き戻して再度開き、HARDCOREとBACKも確認する。
	_root2_reset()

func _root2_reset() -> void:
	var creator_entry: RBMCreatorEntry = _root.creator_entry
	# 新しいRBMGameRootを作らず、mainを非表示に戻してTOPから再度開く簡易確認。
	creator_entry.main.visible = false
	creator_entry._show_top()
	await process_frame
	_click(creator_entry, "NewBossButton")
	await process_frame
	_click(creator_entry, "ChooseAdvancedModeButton")
	await process_frame
	var hardcore_transition_ok: bool = creator_entry.main.visible and creator_entry.main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED
	print("transition check: HARDCORE -> creator visible+advanced mode = %s" % hardcore_transition_ok)

	creator_entry.main.visible = false
	creator_entry._show_top()
	await process_frame
	_click(creator_entry, "NewBossButton")
	await process_frame
	_click(creator_entry, "ModeChoiceBackButton")
	await process_frame
	var back_ok: bool = not creator_entry.find_child("ModeChoicePanel", true, false).visible
	print("transition check: BACK -> mode choice hidden = %s" % back_ok)

	print("mode choice screen capture done, quitting")
	quit()

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
