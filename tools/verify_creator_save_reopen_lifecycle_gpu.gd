extends SceneTree

## GPU/Visual検証: Creator「保存 → クリエイター一覧に戻る → 再編集」で
## 保存完了画面が残留表示される重大な状態遷移不具合の実画面確認。
##
## RBMCreatorEntry(実際の入口)→RBMCreatorMain(1インスタンスを使い回す、
## 実際の本番と同じ構成)を実際に操作し、
##   1) 新規作成→保存→「クリエイター一覧に戻る」→同じボスの「編集」で、
##      保存完了画面ではなく通常のCreator STEP画面が開くこと
##   2) その状態から実際に1項目変更して再度保存できること
##   3) アプリ再起動なしで、保存→一覧→再編集を複数回繰り返しても壊れない
##      こと
##   4) 保存→新規作成でも保存完了画面が残らないこと
## をスクリーンショットで確認する。

var report := {"errors": [], "screenshots": []}

func _fail(message: String) -> void:
	if not report["errors"].has(message):
		report["errors"].append(message)
	push_error(message)

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

var output_dir := "res://../gpu-creator-lifecycle"

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

	# 実プレイヤーのuser://保存ライブラリを一切汚さないよう、専用のテスト用
	# ディレクトリへ差し替える(tools/verify_world_ui_install_gpu.gdと同じ技法)。
	RBMLocalStageRepository.set_stages_dir_for_testing("user://gpu_verify_creator_lifecycle/stages")

	var entry := RBMCreatorEntry.new()
	entry.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(entry)
	for i in range(4): await process_frame

	# --- 検証1: 新規作成→保存→一覧→編集 ---
	(_find(entry, "NewBossButton") as Button).pressed.emit()
	await process_frame
	(_find(entry, "ChooseSimpleModeButton") as Button).pressed.emit()
	await process_frame
	entry.main.draft.boss_name = "GPUライフサイクル検証ボス"
	entry.main.draft.hp = 1000
	entry.main.draft.atk = 100
	entry.main.draft.spd = 50
	entry.main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	entry.main.draft.add_party_character("hero")
	await process_frame
	await RenderingServer.frame_post_draw
	var shot1 := root.get_texture().get_image()
	if shot1 == null: _fail("null capture: 01_normal_creator")
	else:
		shot1.save_png(output_dir + "/01_normal_creator_step1.png")
		report["screenshots"].append("01_normal_creator_step1.png")

	entry.main.press_save()
	await process_frame
	(_find(entry.main, "SaveNewButton") as Button).pressed.emit()
	var stage_id: String = entry.main.current_stage_id
	await process_frame
	await RenderingServer.frame_post_draw
	if not _find(entry.main, "SaveSuccessPanel").visible:
		_fail("保存直後は保存完了画面が表示されているはず")
	var shot2 := root.get_texture().get_image()
	if shot2 == null: _fail("null capture: 02_save_success")
	else:
		shot2.save_png(output_dir + "/02_save_success_screen.png")
		report["screenshots"].append("02_save_success_screen.png")

	(_find(entry.main, "SuccessReturnButton") as Button).pressed.emit()
	await process_frame
	if not entry._list_panel.visible:
		_fail("「クリエイター一覧に戻る」で一覧画面が表示されるはず")

	(_find(entry, "OpenButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	# 注: SaveSuccessPanel自身のvisible(ローカルフラグ)は、親のSaveView自体が
	# 非表示になっても単独ではfalseへ戻らない(open()を呼んだ時だけリセット
	# される設計)——実際に画面上へ描画されるかどうかはis_visible_in_tree()
	# (祖先すべての可視性を含めた実効可視性)で判定する必要がある。
	if (_find(entry.main, "SaveSuccessPanel") as Control).is_visible_in_tree():
		_fail("再編集時に保存完了画面が残留表示されている(不具合が再発)")
	if entry.main._save_view.visible:
		_fail("再編集時にSaveView自体が表示されたままになっている(不具合が再発)")
	if not entry.main._steps_root.visible:
		_fail("再編集時に通常のCreator STEP画面が表示されていない")
	var shot3 := root.get_texture().get_image()
	if shot3 == null: _fail("null capture: 03_reopened_creator")
	else:
		shot3.save_png(output_dir + "/03_reopened_creator_normal.png")
		report["screenshots"].append("03_reopened_creator_normal.png")

	# --- 検証2: 再編集した状態から実際に1項目変更して再保存できること ---
	entry.main.draft.hp = 7777
	var overwrite_result := entry.main.press_overwrite_save()
	if not bool(overwrite_result.get("ok", false)):
		_fail("再編集後の上書き保存に失敗した: %s" % [overwrite_result])
	await process_frame
	await RenderingServer.frame_post_draw
	var shot4 := root.get_texture().get_image()
	if shot4 == null: _fail("null capture: 04_reedited_and_resaved")
	else:
		shot4.save_png(output_dir + "/04_reedited_and_resaved_success.png")
		report["screenshots"].append("04_reedited_and_resaved_success.png")

	# --- 検証3: アプリ再起動なしで保存→一覧→再編集を3回連続 ---
	for i in range(3):
		(_find(entry.main, "SuccessReturnButton") as Button).pressed.emit()
		await process_frame
		(_find(entry, "OpenButton") as Button).pressed.emit()
		await process_frame
		if entry.main._save_view.visible or not entry.main._steps_root.visible:
			_fail("%d回目の連続再編集で保存完了画面が残留した" % (i + 1))
		if str(entry.main.draft.boss_name) != "GPUライフサイクル検証ボス":
			_fail("%d回目の連続再編集でdraftが正しくロードされていない" % (i + 1))
		entry.main.draft.spd = 50 + i
		entry.main.press_overwrite_save()
		await process_frame

	# --- 検証4: 保存→新規作成でも保存完了画面が残らないこと ---
	(_find(entry.main, "SuccessReturnButton") as Button).pressed.emit()
	await process_frame
	(_find(entry, "NewBossButton") as Button).pressed.emit()
	await process_frame
	(_find(entry, "ChooseSimpleModeButton") as Button).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	if entry.main._save_view.visible or not entry.main._steps_root.visible:
		_fail("保存→新規作成で保存完了画面が残留した")
	if entry.main.current_step != 1 or not entry.main.draft.boss_name.is_empty():
		_fail("新規作成がSTEP1からの空のdraftで始まっていない")
	var shot5 := root.get_texture().get_image()
	if shot5 == null: _fail("null capture: 05_new_creation_after_save")
	else:
		shot5.save_png(output_dir + "/05_new_creation_after_save_clean.png")
		report["screenshots"].append("05_new_creation_after_save_clean.png")

	report["case_count"] = 1
	report["passed"] = report["errors"].is_empty()
	var f := FileAccess.open(output_dir + "/creator-lifecycle-report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	_remove_recursive("user://gpu_verify_creator_lifecycle")
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	print("CREATOR_LIFECYCLE_GPU_DONE passed=", report["passed"])
	quit(0 if report["passed"] else 1)

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if entry_name != "." and entry_name != "..":
			var full := path + "/" + entry_name
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
