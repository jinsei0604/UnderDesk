extends SceneTree

## 診断用（「人間の動きに見えない」原因調査、2026-09-04）: 実ゲーム画面
## （実背景合成・実スケール）で、通常呼吸の各段の「保持中」「切り替え
## 直前」「切り替え直後」を撮影し、静止画としての見た目とスナップの
## 見え方の両方を目視確認できるようにする。

const OUT_DIR := "res://tools/_ui_pass_shots/out/motion_review/"
const TEST_STAGES_DIR := "user://bossmaker_ui_pass_screenshot/motion_review_stages"

var _root: RBMGameRoot
var _entry: RBMCreatorEntry
var _char: RBMCreatorGuideCharacter

## GPU Runner移行(2026-09-13)用: 詳細はcapture_mode_choice_screen.gd参照。
var _tree_override: SceneTree = null

func _tree() -> SceneTree:
	return _tree_override if _tree_override != null else self

func run_gpu_verification(tree: SceneTree) -> void:
	_tree_override = tree
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_STAGES_DIR)

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

	# 段境界(累積0.70,1.00,1.30,1.60,2.05,2.35,2.65,2.95)の直前・直後を
	# 撮影し、「保持中の静止」と「切り替えの瞬間」の両方を並べて見る。
	var checkpoints := [
		{"t": 0.10, "label": "01_A_rest_early"},
		{"t": 0.65, "label": "02_A_rest_late"},
		{"t": 0.69, "label": "03_A_just_before_snap"},
		{"t": 0.72, "label": "04_AB_just_after_snap"},
		{"t": 0.95, "label": "05_AB_late"},
		{"t": 1.15, "label": "06_B_mid"},
		{"t": 1.45, "label": "07_BC_mid"},
		{"t": 1.80, "label": "08_C_peak"},
		{"t": 2.20, "label": "09_BC_falling"},
		{"t": 2.50, "label": "10_B_falling"},
		{"t": 2.80, "label": "11_AB_falling"},
		{"t": 2.94, "label": "12_AB_just_before_loop"},
		{"t": 2.97, "label": "13_A_just_after_loop"},
	]

	for cp in checkpoints:
		await _advance_to(float(cp["t"]))
		await _shot(String(cp["label"]))

	print("motion quality review screenshots captured")

func _advance_to(target_elapsed: float) -> void:
	while _char._elapsed < target_elapsed:
		var step: float = minf(0.005, target_elapsed - _char._elapsed)
		_char._process(step)

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _tree().root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, shot_name]))
	print("saved %s (char elapsed=%.4f, stage=%d)" % [shot_name, _char._elapsed, _char._idle_stage_index])
