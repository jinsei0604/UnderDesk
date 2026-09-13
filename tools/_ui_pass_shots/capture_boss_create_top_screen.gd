extends SceneTree

## 「ボス戦を作成」TOP画面の完成確認用ハーネス（背景アート実装、
## 2026-09-04）。実GPUレンダリング（非headless、実OpenGLウィンドウ）で
## RBMGameRootを実際に操作し、①TOP画面の見た目②3つの既存遷移
## （新しいボス戦を作る／保存したボス戦を編集／戻る）が正常に動作する
## ことを確認する。既存のcapture.gd（Phase 3.5 UI統一パス）と同じ
## find_child+.pressed.emit()経路のみを使う。

const OUT_DIR := "res://tools/_ui_pass_shots/out/boss_create_top/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/boss_create_top"

var _root: RBMGameRoot

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

## 正式GPU runner成功判定contract(2026-09-13制定)。詳細はtools/gpu_runner.gd
## 冒頭コメント参照。falseのままならrunnerはexit code 0を返さない。
var _gpu_verification_completed := false

func run_gpu_verification(tree: SceneTree) -> int:
	_tree_override = tree
	print("boss-create top screen capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	# ① CreateModeButtonを押した直後に表示される「ボス戦を作成」TOP画面。
	_click(_root, "CreateModeButton")
	await _tree().process_frame
	await _shot("01_top_screen")

	var creator_entry: RBMCreatorEntry = _root.creator_entry

	# ② 既存遷移: 「新しいボス戦を作る」→ 作成方法選択画面が開くこと。
	_click(creator_entry, "NewBossButton")
	await _tree().process_frame
	var simple_mode_button: Node = creator_entry.find_child("ChooseSimpleModeButton", true, false)
	var mode_choice_visible: bool = simple_mode_button != null and simple_mode_button.is_visible_in_tree()
	print("existing transition check: NewBossButton -> mode choice visible = %s" % mode_choice_visible)
	await _shot("02_after_new_boss_button")

	# 作成方法選択画面から一旦TOPへ戻り、次の遷移確認へ備える。
	_click(creator_entry, "ModeChoiceBackButton")
	await _tree().process_frame

	# ③ 既存遷移: 「保存したボス戦を編集」→ 保存済み一覧画面が開くこと。
	_click(creator_entry, "EditSavedBossButton")
	await _tree().process_frame
	var list_visible: bool = creator_entry._list_panel.visible
	print("existing transition check: EditSavedBossButton -> saved list visible = %s" % list_visible)
	await _shot("03_after_edit_saved_button")

	_click(creator_entry, "ListBackButton")
	await _tree().process_frame

	# ④ 既存遷移: 「← 戻る」→ 共通ルート画面へ戻ること。
	_click(creator_entry, "BackToRootButton")
	await _tree().process_frame
	var back_to_root_ok: bool = not creator_entry.is_visible_in_tree() or not creator_entry._top_panel.visible
	print("existing transition check: BackToRootButton -> left CREATE top screen = %s" % back_to_root_ok)
	await _shot("04_after_back_to_root")

	print("boss-create top screen capture done")
	_gpu_verification_completed = true
	return 0

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)
