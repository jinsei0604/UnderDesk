extends SceneTree

## 呼吸Idle A/B/C/D/Eそれぞれの実ゲーム上のスクリーンショットを撮影する
## （§16）。§9の目視フリンジ確認のため、実際の暗い部屋背景に重ねた
## 状態で撮影する（プレースホルダーの黒背景ではない）。

const OUT_DIR := "res://tools/_ui_pass_shots/out/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/idle_abcde_stages"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

func run_gpu_verification(tree: SceneTree) -> void:
	_tree_override = tree
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_root = RBMGameRoot.new()
	_tree().root.add_child(_root)
	await _tree().process_frame
	await _tree().process_frame

	_root.find_child("CreateModeButton", true, false).pressed.emit()
	await _tree().process_frame
	_entry = _root.creator_entry
	_entry.find_child("NewBossButton", true, false).pressed.emit()
	await _tree().process_frame
	await _tree().process_frame

	_char = _entry.find_child("GuideCharacter", true, false)
	_char.set_process(false)
	_char._elapsed = 0.0
	_char._idle_stage_index = -1
	_char._breath_cycle_start = 0.0
	_char._next_d_time = 999.0
	_char._next_e_time = 999.0

	# A (0.1s、rest)
	await _advance_to(0.1)
	await _shot("16_idle_a_rest")

	# B (1.8s、rising)
	await _advance_to(1.8)
	await _shot("16_idle_b_rising")

	# C (2.8s、peak)
	await _advance_to(2.8)
	await _shot("16_idle_c_peak")

	# D: 強制発火させて撮影する。
	_char._next_d_time = 0.0
	_char._breath_cycle_start = _char._elapsed
	_char._idle_stage_index = -1
	while _char._special_active == RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)
	await _tree().process_frame
	await _shot("16_idle_d_posture")

	# Dが終わりAへ戻るまで進める。
	while _char._special_active != RBMCreatorGuideCharacter.SpecialIdle.NONE:
		_char._process(0.01)

	# E: 強制発火させて撮影する。
	_char._next_e_time = 0.0
	_char._breath_cycle_start = _char._elapsed
	_char._idle_stage_index = -1
	# MIN_A_HOLD_BEFORE_SPECIAL_SECを超えるまで進める。
	for i in range(60):
		_char._process(0.01)
		if _char._special_active == RBMCreatorGuideCharacter.SpecialIdle.HAND:
			break
	await _tree().process_frame
	await _shot("16_idle_e_hand")

	print("idle A/B/C/D/E screenshots captured")

func _advance_to(target_elapsed: float) -> void:
	while _char._elapsed < target_elapsed:
		var step: float = minf(0.01, target_elapsed - _char._elapsed)
		_char._process(step)
	await _tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, shot_name]))
	print("saved %s (char elapsed=%.3f, stage=%d, special=%d)" % [shot_name, _char._elapsed, _char._idle_stage_index, _char._special_active])
