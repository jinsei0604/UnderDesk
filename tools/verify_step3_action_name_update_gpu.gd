extends SceneTree

## GPU/Visual検証: Creator STEP3で既存攻撃の行動名を変更して保存した際、
## BOSS PROFILE > ACTIONS が即座に新しい名前へ更新されることの実画面確認。
##
## 再現/修正対象の不具合: 「性能を編集」を押すと共有フォーム自身の
## [保存][キャンセル]が現れるが、修正前はその外側にあるRBMCreatorStep4
## ActionPatterns自身の[保存][キャンセル][この攻撃を削除]行が同時に
## 表示されたままだった。外側の[保存]を先に押してしまうと、フォームへ
## 入力中の新しい名前がdraft.skillsへ反映されないまま画面が閉じ、
## BOSS PROFILE > ACTIONSが旧名称のまま残っていた。
##
## この検証では実際に「ゴーレムアタック」→「無属性」への改名を行い、
## 1) 性能編集フォームを開いた瞬間、外側の保存/キャンセル/削除行が
##    画面から消えていること(修正①の目視確認)
## 2) フォーム自身の保存を押した直後、BOSS PROFILE > ACTIONSが
##    即座に新しい名前へ変わること
## 3) その後、外側の保存を押して配置編集セッション自体を確定しても、
##    新しい名前が保たれたままであること
## をスクリーンショットで確認する。

var report := {"errors": [], "screenshots": []}

func _fail(message: String) -> void:
	if not report["errors"].has(message):
		report["errors"].append(message)
	push_error(message)

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

var output_dir := "res://../gpu-step3-action-name"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--output" and i + 1 < args.size():
			output_dir = args[i + 1]
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if DisplayServer.get_name() == "headless":
		push_error("GPU preview requires a windowed display; --headless is not valid.")
		quit(2)
		return

	var creator := RBMCreatorMain.new()
	creator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(creator)
	for i in range(4): await process_frame

	creator.draft.boss_name = "GPU検証ボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_party_character("hero")
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.go_to_step(3)
	var step3: RBMCreatorStep4ActionPatterns = _find(creator, "AdvancedView")
	await process_frame

	(_find(step3, "AddSlotButton") as Button).pressed.emit()
	(_find(step3, "AddChoiceCreateNewButton") as Button).pressed.emit()
	var form: RBMActionEditorForm = step3._form
	form._name_edit.text = "ゴーレムアタック"
	(_find(step3, "SkillSlotConfirmButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw

	var actions_label: Label = creator._boss_profile_panel._actions_label
	if not actions_label.text.contains("ゴーレムアタック"):
		_fail("creation should show 01 ゴーレムアタック, got: %s" % actions_label.text)
	var shot1 := root.get_texture().get_image()
	if shot1 == null: _fail("null capture: 01_created")
	else:
		shot1.save_png(output_dir + "/01_created_golem_attack.png")
		report["screenshots"].append("01_created_golem_attack.png")

	# 既存攻撃編集画面 → 性能を編集
	(_find(step3, "EditSlotButton_0") as Button).pressed.emit()
	await process_frame
	(_find(step3, "SkillSlotEditPerformanceButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw

	# 修正①の確認: 内側フォームが開いている間、外側の[保存][キャンセル]
	# [この攻撃を削除]行が画面上から見えなくなっていること。
	var outer_confirm: Button = _find(step3, "SkillSlotConfirmButton")
	if outer_confirm.is_visible_in_tree():
		_fail("outer SkillSlotConfirmButton must not be visible while the inline performance form is open")
	var shot2 := root.get_texture().get_image()
	if shot2 == null: _fail("null capture: 02_editing_form_open")
	else:
		shot2.save_png(output_dir + "/02_editing_form_open_outer_row_hidden.png")
		report["screenshots"].append("02_editing_form_open_outer_row_hidden.png")

	form._name_edit.text = "無属性"
	(_find(step3, "SaveActionButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw

	# 修正②の確認: フォーム自身の保存直後、BOSS PROFILE > ACTIONSが
	# 即座に新しい名前へ変わっていること。
	if not actions_label.text.contains("無属性"):
		_fail("after saving the inline form, BOSS PROFILE ACTIONS should already show 無属性, got: %s" % actions_label.text)
	if actions_label.text.contains("ゴーレムアタック"):
		_fail("BOSS PROFILE ACTIONS must not still show the stale name")
	var shot3 := root.get_texture().get_image()
	if shot3 == null: _fail("null capture: 03_after_inner_save")
	else:
		shot3.save_png(output_dir + "/03_after_inner_save_boss_profile_updated.png")
		report["screenshots"].append("03_after_inner_save_boss_profile_updated.png")

	# 配置編集セッション自体を確定(外側の保存)しても、新しい名前が保たれる。
	(_find(step3, "SkillSlotConfirmButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	if not actions_label.text.contains("無属性"):
		_fail("after the outer confirm, BOSS PROFILE ACTIONS should still show 無属性, got: %s" % actions_label.text)
	var shot4 := root.get_texture().get_image()
	if shot4 == null: _fail("null capture: 04_after_outer_confirm")
	else:
		shot4.save_png(output_dir + "/04_after_outer_confirm_still_updated.png")
		report["screenshots"].append("04_after_outer_confirm_still_updated.png")

	# 再編集して開いても新しい名前が読み込まれること。
	(_find(step3, "EditSlotButton_0") as Button).pressed.emit()
	await process_frame
	(_find(step3, "SkillSlotEditPerformanceButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	if form._name_edit.text != "無属性":
		_fail("reopening the edit form should load the new name, got: %s" % form._name_edit.text)
	var shot5 := root.get_texture().get_image()
	if shot5 == null: _fail("null capture: 05_reopened_edit")
	else:
		shot5.save_png(output_dir + "/05_reopened_edit_shows_new_name.png")
		report["screenshots"].append("05_reopened_edit_shows_new_name.png")

	report["case_count"] = 1
	report["passed"] = report["errors"].is_empty()
	var f := FileAccess.open(output_dir + "/step3-action-name-report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	print("STEP3_ACTION_NAME_GPU_DONE passed=", report["passed"])
	quit(0 if report["passed"] else 1)
