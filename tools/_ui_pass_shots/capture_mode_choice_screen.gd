extends SceneTree

## 右側UI仕上げ（2026-09-04）確認用ハーネス。実GPUレンダリング（非
## headless、実OpenGLウィンドウ）で「作成方法選択」画面を撮影する。

const OUT_DIR := "res://tools/_ui_pass_shots/out/mode_choice_finish/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/mode_choice_finish"

var _root: RBMGameRoot

## GPU Runner移行(2026-09-13)用: 新runner経由でdynamic loadされ`.new()`で
## 生成された場合、このインスタンス自身は生きているSceneTreeではないため、
## runnerが注入する_tree_overrideを使う。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

## 正式GPU runner成功判定contract(2026-09-13制定)。詳細はtools/gpu_runner.gd
## 冒頭コメント参照。falseのままならrunnerはexit code 0を返さない。
var _gpu_verification_completed := false

## GPU Runner移行(2026-09-13)用の明示的entry point。tools/gpu_runner.gd
## から`load()`で動的ロードされた後、生きているSceneTreeを引数で受け取って
## 1回だけ呼び出される想定(newもset_scriptも不要、_init()の二重実行なし)。
## 検証内容自体は変更していない。
func run_gpu_verification(tree: SceneTree) -> int:
	_tree_override = tree
	print("mode choice screen capture starting...")
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_click(_root, "CreateModeButton")
	await _tree().process_frame
	var creator_entry: RBMCreatorEntry = _root.creator_entry
	_click(creator_entry, "NewBossButton")
	await _tree().process_frame
	await _tree().process_frame
	await _shot("01_mode_choice")

	# ホバー状態も1枚確認する（SIMPLEパネル）。
	# 調査(2026-09-13): "MethodCardSurface"という子ノード名は、UNDERDESK
	# 削除コミット(92821cf)で削除された旧ModeChoicePanelSurfaceクラスの
	# インスタンス名で、現在のsrc側には存在しない。SIMPLE/HARDCOREボタンは
	# 現在RBMWorldUi.method_layout()内でmenu_button()により構築されており、
	# ホバー外観はGodot標準のButtonテーマ(normal/hover/pressed等の
	# stylebox override)で自動的に切り替わる方式に置き換わっている
	# ——手動set_state()を持つ専用の子ノードはもう存在しない。
	# 同系統のcapture_creator_ui_kit.gdが既に採用している、実際の
	# InputEventMouseMotionをpush_inputして本物のis_hovered()状態を
	# 発生させる方式(_hover())に合わせる。
	var simple_btn: Button = creator_entry.find_child("ChooseSimpleModeButton", true, false)
	_hover(simple_btn)
	await _tree().process_frame
	await _tree().process_frame
	await _shot("02_simple_hover")

	# 既存遷移確認: SIMPLE/HARDCORE/戻る。
	_click(creator_entry, "ChooseSimpleModeButton")
	await _tree().process_frame
	var simple_transition_ok: bool = creator_entry.main.visible and creator_entry.main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_SIMPLE
	print("transition check: SIMPLE -> creator visible+simple mode = %s" % simple_transition_ok)

	# 巻き戻して再度開き、HARDCOREとBACKも確認する。
	await _root2_reset()
	_gpu_verification_completed = true
	return 0

func _root2_reset() -> void:
	var creator_entry: RBMCreatorEntry = _root.creator_entry
	# 新しいRBMGameRootを作らず、mainを非表示に戻してTOPから再度開く簡易確認。
	creator_entry.main.visible = false
	creator_entry._show_top()
	await _tree().process_frame
	_click(creator_entry, "NewBossButton")
	await _tree().process_frame
	_click(creator_entry, "ChooseAdvancedModeButton")
	await _tree().process_frame
	var hardcore_transition_ok: bool = creator_entry.main.visible and creator_entry.main.draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED
	print("transition check: HARDCORE -> creator visible+advanced mode = %s" % hardcore_transition_ok)

	creator_entry.main.visible = false
	creator_entry._show_top()
	await _tree().process_frame
	_click(creator_entry, "NewBossButton")
	await _tree().process_frame
	_click(creator_entry, "ModeChoiceBackButton")
	await _tree().process_frame
	var back_ok: bool = not creator_entry.find_child("ModeChoicePanel", true, false).visible
	print("transition check: BACK -> mode choice hidden = %s" % back_ok)

	print("mode choice screen capture done")

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()

func _hover(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	_tree().root.push_input(motion)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	var path := "%s%s.png" % [OUT_DIR, name]
	img.save_png(path)
	print("saved %s" % path)

## 注意: 旧来の直接`-s`起動(`godot --path . -s res://tools/_ui_pass_shots/
## capture_mode_choice_screen.gd`)は正式サポート対象外とした。`_init()`を
## 互換目的で定義すると、`.new()`のたびにGDScriptのコンストラクタとして
## 自動発火してしまい、tools/gpu_runner.gdからの明示呼び出しと合わせて
## run_gpu_verification()が二重実行される(検証済みの実際の不具合だった
## ため、意図的に`_init()`を持たない構造にしている)。今後はこのファイルは
## 必ず以下のように新runner経由で実行する:
##   godot --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/_ui_pass_shots/capture_mode_choice_screen.gd
