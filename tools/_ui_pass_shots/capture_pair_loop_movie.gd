extends SceneTree

## 追加修正パス（2026-09-03、10回目）§7: 指定した2つのIdleテクスチャを
## 短い間隔で往復させ続ける診断動画を撮る。1回の切り替えでは分かりに
## くい横ズレも、連続往復させることで視覚的に強調される。
## 実行時に--script-args経由でINDEX_A/INDEX_B/LABEL_A/LABEL_Bを
## 切り替えられるようOSの環境変数で受け取る（Godotの--scriptには引数を
## 直接渡せないため、OS.get_environment()で受け取る）。

const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/pair_loop_stage"
const HOLD_SEC := 0.45  # 各状態の保持時間。短めにして往復を連続表示する。
const TOTAL_SEC := 8.0

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter
var _elapsed := 0.0

func _init() -> void:
	var idx_a := int(OS.get_environment("PAIR_IDX_A"))
	var idx_b := int(OS.get_environment("PAIR_IDX_B"))
	var label_a := OS.get_environment("PAIR_LABEL_A")
	var label_b := OS.get_environment("PAIR_LABEL_B")
	print("pair loop: %s(idx=%d) <-> %s(idx=%d)" % [label_a, idx_a, label_b, idx_b])

	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
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

	var showing_a := true
	var next_switch := HOLD_SEC
	_char._body.texture = _char._idle_textures[idx_a]

	while _elapsed < TOTAL_SEC:
		await process_frame
		_elapsed += 1.0 / 60.0
		if _elapsed >= next_switch:
			showing_a = not showing_a
			_char._body.texture = _char._idle_textures[idx_b] if not showing_a else _char._idle_textures[idx_a]
			next_switch += HOLD_SEC

	print("pair loop movie done at t=%.2f, quitting" % _elapsed)
	quit()
