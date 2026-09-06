extends SceneTree

## 8回目セッション: 新しい8段階呼吸シーケンス（A→AB→B→BC→C→BC→B→AB→A）
## の各遷移の「直前フレーム」「直後フレーム」を実GPU・実表示スケール
## (0.50)・実背景で撮影する。加えてD/E（A→D→A、A→E→A）も撮影する。
## 実行には必ずウィンドウ有りの通常exe（Godot_v4.7-stable_win64.exe、
## _consoleではない方）を使うこと——headlessの標準dummyレンダラーは
## この環境で`RenderingServer.frame_post_draw`が発火せずハングする。

const OUT_DIR := "res://tools/_ui_pass_shots/out/transitions/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/transition_stages"

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

	# --- 通常呼吸: 8段階の全遷移境界を撮影 ---
	var stage_names := ["a", "ab1", "b1", "bc1", "c", "bc2", "b2", "ab2"]
	for i in range(stage_names.size()):
		_reset_to_normal_breathing()
		var wraps: bool = (i == stage_names.size() - 1)
		await _advance_stage_boundary(i, "%s_to_next" % stage_names[i], wraps)

	# --- D: A→D→A ---
	_reset_to_normal_breathing()
	_char._next_d_time = 0.0
	_char._next_e_time = 999.0
	_char._breath_cycle_start = _char._elapsed
	_char._idle_stage_index = -1
	await _shot("d_before_a")
	while _char._special_active == RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)
	await _shot("d_after_d")
	while _char._elapsed < _char._special_end_time - 0.02:
		_char._process(0.01)
	await _shot("d_before_a_return")
	while _char._special_active != RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)
	await _shot("d_after_a_return")

	# --- E: A→E→A ---
	_reset_to_normal_breathing()
	_char._next_d_time = 999.0
	_char._next_e_time = 0.0
	_char._breath_cycle_start = _char._elapsed
	_char._idle_stage_index = -1
	await _shot("e_before_a")
	while _char._special_active == RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)
	await _shot("e_after_e")
	while _char._elapsed < _char._special_end_time - 0.02:
		_char._process(0.01)
	await _shot("e_before_a_return")
	while _char._special_active != RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)
	await _shot("e_after_a_return")

	print("transition pair screenshots captured")
	quit()

func _reset_to_normal_breathing() -> void:
	_char._special_active = RBMCreatorGuideCharacter.SpecialIdle.NONE
	_char._elapsed = 0.0
	_char._breath_cycle_start = 0.0
	_char._idle_stage_index = -1
	_char._next_d_time = 999.0
	_char._next_e_time = 999.0
	_char._process(0.001)

## stage_index_before で示す段の最後のフレームと、切り替わった直後の
## フレームを撮影する。IDLE_FRAME_DURATIONSの累積境界のわずか手前/後まで
## _processを刻んで進める。
func _advance_stage_boundary(stage_index_before: int, tag: String, wraps: bool = false) -> void:
	var durations: Array[float] = RBMCreatorGuideCharacter.IDLE_FRAME_DURATIONS
	var boundary := 0.0
	for i in range(stage_index_before + 1):
		boundary += durations[i]
	if wraps:
		boundary = 0.0
		for d in durations:
			boundary += d
	while _char._elapsed < boundary - 0.02:
		_char._process(0.01)
	await _shot("%s_before" % tag)
	while _char._elapsed < boundary + 0.02:
		_char._process(0.01)
	await _shot("%s_after" % tag)

func _shot(shot_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, shot_name]))
	print("saved %s (elapsed=%.3f stage=%d special=%d)" % [shot_name, _char._elapsed, _char._idle_stage_index, _char._special_active])
