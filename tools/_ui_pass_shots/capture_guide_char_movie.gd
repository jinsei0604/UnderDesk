extends SceneTree

## §14 実GPU動画撮影ハーネス。RBMGameRootを実際に操作して
## Creator「作成方法を選択」画面へ遷移し、正式Idle実装（通常呼吸A→B→C
## →B→A・まばたき・姿勢調整D・手の微動E）が実際に動く様子を
## --write-movie で記録する。
##
## 撮影専用の時間短縮について（§14の明示的な許可の範囲内）: D/Eの本番
## 抽選間隔（D=8〜14秒、E=10〜18秒、いずれもRBMCreatorGuideCharacter側の
## 定数は無改修）のままだと、短い録画時間内にD/Eが1回も映らない可能性が
## あるため、この撮影ハーネスだけがキャラクター構築直後に_next_d_time/
## _next_e_timeへ具体的な発火予定時刻を直接代入し、D/Eが録画時間内に
## 確実に1回ずつ現れるようにしている。本番のクラス定数（D_MIN_INTERVAL_
## SEC等）自体は一切変更していない——この撮影ハーネス側のインスタンス
## 変数への代入のみ。

const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/movie_stages"

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
	print("guide character movie capture starting...")
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
		# 撮影専用の発火予定時刻の前倒し（本番定数は無改修、上記の
		# ドキュメントコメント参照）。Dを約6秒後、Eを約16秒後に発火予定
		# とし、互いに十分な間隔を空けて両方が録画内で確実に見えるようにする。
		_char._next_d_time = 6.0
		_char._next_e_time = 16.0
		print("capture harness: seeded _next_d_time=6.0, _next_e_time=16.0 (instance-only, class defaults untouched)")

	print("mode-choice screen shown, recording begins")

	# --write-movie は固定fpsで駆動されるため、process_frameを回すだけで
	# シミュレーション時間が正しく進む（SceneTreeのオーバーライドではなく
	# 明示的なループで進行——SceneTree._process(delta)->boolはtrueを返すと
	# エンジン停止という直感と逆の意味を持つ罠があるため、このプロジェクトの
	# 確立済みパターン通りawaitループへ統一する）。
	while _elapsed < 34.0:
		await _tree().process_frame
		_elapsed += 1.0 / 60.0

	print("movie capture done at t=%.2f" % _elapsed)

func _click(node: Node, button_name: String) -> void:
	var btn: Button = node.find_child(button_name, true, false)
	if btn == null:
		print("WARN: button not found: %s under %s" % [button_name, node])
		return
	btn.pressed.emit()
