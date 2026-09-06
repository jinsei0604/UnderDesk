extends SceneTree

## 緊急修正パス: 実GPU・実背景・実表示スケール(0.50)で、A/AB/B/BC/C/D/E
## それぞれを強制表示させたスクリーンショットを撮り、髪・帽子周辺を
## 拡大した比較画像を作る。実行には必ずウィンドウ有りの通常exe
## （Godot_v4.7-stable_win64.exe）を使うこと。

const OUT_DIR := "res://tools/_ui_pass_shots/out/hair_check/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/hair_check_stages"

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
	_char.set_process(false)

	# _idle_textures配列の実際の並び順(A,AB,B,BC,C,D,E,AD)に合わせる
	# ——追加修正パス（2026-09-03、10回目）でADが末尾に追加されたため。
	var labels := ["A", "AB", "B", "BC", "C", "D", "E", "AD"]
	var idx := 0
	for tex in _char._idle_textures:
		_char._body.texture = tex
		await _shot(labels[idx])
		idx += 1

	print("hair check screenshots captured for all %d frames" % labels.size())
	quit()

func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%sframe_%s.png" % [OUT_DIR, label]))
	print("saved frame_%s.png" % label)
