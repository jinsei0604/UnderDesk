extends "res://tools/verify_battle_visuals_gpu.gd"
## Runs the installed UI lifecycle; no preview adapters.
var game: RBMGameRoot
var evidence: Dictionary = {"screens":[],"checks":[],"errors":[]}

func check(ok: bool, label_text: String) -> void:
	evidence.checks.append({"label":label_text,"passed":ok})
	if not ok: evidence.errors.append(label_text)

func click(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name,true,false) as Button
	check(button != null,"button exists: "+button_name)
	if button != null: button.pressed.emit()

func shot(id: String, _target: Control) -> void:
	for i in range(8): await _tree().process_frame
	await RenderingServer.frame_post_draw
	_tree().root.get_texture().get_image().save_png(output_dir.path_join(id+".png"))
	evidence.screens.append(id)
	print("SHOT "+id)

func settle() -> void:
	for i in range(10): await _tree().process_frame
	if is_instance_valid(view) and view.session != null:
		var ticks := 0
		while view._presenter.is_playing() and ticks < 900:
			await _tree().process_frame
			ticks += 1
		check(ticks < 900,"presentation completes")

func within(c: Control, name_text: String) -> void:
	check(c.is_visible_in_tree() and Rect2(0,0,1280,720).encloses(c.get_global_rect()), name_text+" visible and within viewport")

func verify_mode(mode: String) -> void:
	await settle()
	stage = view._battlefield_ally_row.get_meta("visual_stage")
	within(view._quit_button,mode+" exit")
	check(view._world_battle.current_background == ("day" if mode == "test" else "night"),mode+" selected day-night background displayed")
	check(stage.get_global_rect() == Rect2(0,0,1280,720),mode+" fullscreen stage")
	var feet: Array = []
	for key in stage._party_keys: feet.append(stage._foot(key))
	check(feet.size()==4 and feet[0].x>feet[1].x and feet[0].y>feet[2].y and feet[1].y>feet[3].y and feet[2].x>feet[3].x,mode+" staggered formation")
	await shot(mode+"-normal",view)
	var before: Dictionary = view.session.battle.snapshot().duplicate(true)
	view._open_skill_list()
	await settle()
	within(view._quit_button,mode+" exit during skills")
	var scroll: ScrollContainer = view._world_battle.command_scroll
	within(scroll,mode+" skill scroll")
	check(not scroll.get_global_rect().intersects(view._quit_button.get_global_rect()),mode+" exit does not overlap skills")
	await shot(mode+"-skills",view)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await settle()
	var back: Button = view.find_child("SkillListBackButton",true,false)
	within(back,mode+" skill Back reachable by scrolling")
	check(scroll.get_global_rect().encloses(back.get_global_rect()),mode+" skill Back inside scroll clip")
	await shot(mode+"-skills-bottom",view)
	back.pressed.emit()
	await settle()
	check(before == view.session.battle.snapshot(),mode+" skill UI preserves snapshot")
	# Exercise target picker with the existing waiting ally's targetable support skill.
	var unit = view._unit_by_id(view.session.pending_ally_id())
	for skill in unit.skills:
		if view._skill_needs_target(skill):
			view.act_skill(unit.id,skill.id)
			await settle()
			within(view._quit_button,mode+" exit during target selection")
			await shot(mode+"-target",view)
			view._close_target_picker()
			break
	var homes: Dictionary = stage._homes.duplicate(true)
	view.act_attack(view.session.pending_ally_id())
	await settle()
	check(stage._homes == homes,mode+" attack returns to formation")
	check(before != view.session.battle.snapshot(),mode+" actual session progressed")
	if mode != "challenge":
		view.rewind_to(1)
		await settle()
		check(stage._homes == homes,mode+" REWIND preserves formation")
		within(view._quit_button,mode+" exit after REWIND")
	if mode != "test":
		view._restart_button.pressed.emit()
		await settle()
		within(view._restart_confirm,mode+" restart dialog")
		await shot(mode+"-restart-confirm",view)
		view._restart_confirm.hide()
	view.open_log_window()
	await settle()
	within(view._log_window_overlay.close_button,mode+" log close")
	view._close_all_overlays()
	if mode == "test":
		view._quit_button.pressed.emit()
		await settle()
		within(view._quit_confirm,mode+" quit dialog")
		within(view.find_child("QuitConfirmButton",true,false),mode+" confirm exit")
		await shot(mode+"-quit-confirm",view)
		click(view,"QuitCancelButton")
		check(not view._quit_confirm.visible,mode+" cancel exit")
		view._open_skill_list()
		await settle()
		view._quit_button.pressed.emit()
		click(view,"QuitConfirmButton")
	else:
		view._quit_button.pressed.emit()
		if mode == "challenge":
			await settle()
			within(view._quit_confirm,"challenge quit dialog")
			view._quit_confirm.hide()
	await settle()

## GPU Runner移行(2026-09-13)用の明示的entry point。tools/gpu_runner.gd
## から`load()`で動的ロードされた後、生きているSceneTreeを引数で受け取って
## 1回だけ呼び出される想定(newもset_scriptも不要)。既存CLI引数
## (--output/--record-all)の意味は変えていない。戻り値は旧来のquit()
## 引数と同じ意味の終了コード。
func run_gpu_verification(tree: SceneTree, output_dir_override: String = "", record_all_override: bool = false) -> int:
	_tree_override = tree
	if output_dir_override != "": output_dir = output_dir_override
	if record_all_override: record_all = true
	_tree().root.size = Vector2i(1280,720)
	_tree().root.content_scale_size = Vector2i(1280,720)
	_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing("user://world_ui_install/empty_stages")
	game = RBMGameRoot.new()
	_tree().root.add_child(game)
	await settle()
	click(game,"CreateModeButton")
	click(game.creator_entry,"NewBossButton")
	await shot("method-choice",game)
	click(game.creator_entry,"ChooseSimpleModeButton")
	var main: RBMCreatorMain = game.creator_entry.main
	main.draft.boss_name = "黒炎竜ヴァルガス"
	main.draft.appearance_id = "appearance_dragon"
	main.draft.hp = 2400
	main.draft.atk = 80
	main.draft.spd = 30
	var sid := main.draft.add_skill({"name":"炎撃","type":"attack","target":"single","attribute":"FIRE","atk_multiplier":1.0})
	main.draft.normal_actions_enabled = true
	main.draft.normal_action_percentages[sid] = 100.0
	for id in ["hero","butler","healer","samurai"]: main.draft.add_party_character(id)
	main.go_to_step(2)
	await settle()
	var stats = main._step_views[1]
	check(stats.find_child("StatsNormalDisplay",true,false)==null,"no stats confirmation screen")
	check(stats.find_child("ConfirmStatsButton",true,false)==null,"no stats confirm button")
	stats._hp_spin.get_line_edit().text = "3800"
	stats._hp_spin.get_line_edit().text_changed.emit("3800")
	await _tree().process_frame
	check(main.draft.hp==3800,"typing applies HP without Enter or confirmation")
	stats._atk_slider.value = 120
	check(main.draft.atk==120,"slider applies ATK immediately")
	await shot("stats-live",game)
	main.go_to_step(5)
	await settle()
	var combat_before := main.draft.battle_content_snapshot().duplicate(true)
	click(main,"DayBackgroundButton")
	check(main.draft.battle_background=="day","Day button selects day")
	check(main.draft.battle_content_snapshot()==combat_before,"background excluded from combat content")
	var saved := main.draft.to_saved_dict()
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(JSON.parse_string(JSON.stringify(saved)))
	check(restored.battle_background=="day","day choice save/restore")
	var disk_saved: Dictionary = main.press_save_as_new()
	check(bool(disk_saved.get("ok",false)),"background choice saved through production repository")
	var disk_loaded: Dictionary = RBMLocalStageRepository.load_stage(str(disk_saved.get("stage_id","")))
	restored.restore_from_saved_dict(disk_loaded.get("draft_data",{}))
	check(restored.battle_background=="day","background choice reloaded from saved file")
	saved.erase("battle_background")
	restored.restore_from_saved_dict(saved)
	check(restored.battle_background=="night","old saves default to night")
	await shot("summary-day",game)
	check(main.press_test_battle().ok,"test starts via Creator")
	view = main._test_battle_view
	await verify_mode("test")
	check(not view.visible and main._steps_root.visible,"test Exit returns to Creator")
	click(main,"NightBackgroundButton")
	check(main.draft.battle_background=="night","Night button selects night")
	await shot("summary-night",game)
	main.press_clear_check()
	await settle()
	check(not main._clear_check_view._world_battle.canvas.visible,"clear-check confirmation remains visible")
	await shot("clear-check-before-start",game)
	check(main.press_clear_check_start(20260906).ok,"clear check starts via Creator")
	view = main._clear_check_view
	await verify_mode("clear-check")
	check(not view.visible and main._steps_root.visible,"clear-check return reaches Creator")
	game.hide()
	await _open_view("challenge",_definition_for("samurai"),"appearance_dragon")
	await verify_mode("challenge")
	await _close_view()
	for mode in ["test","clear_check","challenge"]:
		for winner in ["ally","boss"]:
			var definition := _definition_for("samurai")
			definition.boss.hp = 1 if winner == "ally" else 100000
			definition.boss.atk = 1 if winner == "ally" else 9999
			definition.boss.spd = 1 if winner == "ally" else 500
			definition.boss.skills[0].target = "all"
			await _open_view(mode,definition,"appearance_dragon")
			if mode == "clear_check": view.draft = RBMCreatorDraft.new()
			if not view.session.battle.battle_over:
				view.act_attack(view.session.pending_ally_id())
			await settle()
			check(view.session.battle.battle_over and view.session.battle.winner==winner,mode+" actual result "+winner)
			within(view._outcome_area,mode+" result panel "+winner)
			if mode == "clear_check" and winner == "ally":
				check(not view._retry_button.visible,"successful clear-check retains its return-only result flow")
			else:
				within(view._retry_button,mode+" result retry "+winner)
			within(view._return_button,mode+" result return "+winner)
			await shot(mode+"-result-"+winner,view)
			# Window resize changes physical size, retaining the 1280x720 logical canvas.
			_tree().root.size = Vector2i(960,540)
			await settle()
			within(view._return_button,mode+" result return at 960x540")
			_tree().root.size = Vector2i(1600,900)
			await settle()
			within(view._return_button,mode+" result return at 1600x900")
			_tree().root.size = Vector2i(1280,720)
			await _close_view()
	game.queue_free()
	evidence.checks_count = evidence.checks.size()
	FileAccess.open(output_dir.path_join("render-report.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"\t"))
	print("WORLD_UI_INSTALL_DONE checks=%d errors=%d" % [evidence.checks.size(),evidence.errors.size()])
	return 0 if evidence.errors.is_empty() else 1

## 旧来の直接`-s`起動との後方互換用の薄い入口(正式サポート対象外。
## selfが生きているtreeの場合のみ機能する)。
func _run() -> void:
	quit(await run_gpu_verification(self, output_dir, record_all))
