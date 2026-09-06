extends SceneTree

## 追加修正パス（2026-09-03、11回目）「頭・首の連動」確認用の短い診断
## 動画。今回は局所修正のため30秒の通常速度確認動画は不要——通常呼吸を
## 2〜3サイクル、それに続けてDを1回だけ発生させる短い動画のみを撮影
## する（Eは今回変更していないため撮影不要）。実行には必ずウィンドウ
## 有りの通常exeを使うこと（headlessのdummyレンダラーは実描画/動画書き
## 出しが機能しないため）。

const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/movie_head_neck_check"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter
var _elapsed := 0.0

func _init() -> void:
	print("head/neck check movie starting...")
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
		# 通常呼吸を約2サイクル(1周期約2.95秒)自然に見せてから、ちょうど
		# 次にAへ戻ったタイミングでDが発火するよう設定する。Eは今回
		# 変更していないため発火させない。
		_char._next_d_time = 6.0
		_char._next_e_time = 999.0

	print("recording begins (breathing x2-3 cycles, then D fires once)")
	while _elapsed < 9.5:
		await process_frame
		_elapsed += 1.0 / 60.0

	print("head/neck check movie done at t=%.2f, quitting" % _elapsed)
	quit()

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()
