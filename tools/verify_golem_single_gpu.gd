extends "res://tools/verify_battle_visuals_gpu.gd"
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	for mode in ["test","clear_check","challenge"]:
		for attribute in Palette.COLORS:
			var definition:=_definition_for("samurai")
			definition.boss.skills[0].attribute=attribute
			definition.boss.skills[0].name="ゴーレムの一撃"
			await _open_view(mode,definition,"appearance_golem")
			var before: Dictionary={}
			var entries: Array=[]
			for attempt in range(12):
				before=view.session.battle.presentation_state().duplicate(true)
				entries=view.session.resolve_ally_action({"type":"defend"})
				if entries.any(func(e):return str(e.get("actor"))=="boss"): break
			var resolved: Dictionary=view.session.battle.snapshot().duplicate(true)
			stage.set_state(before)
			RBMBattlePresenter.apply_status_snapshot(view,before)
			var seen: Array=[]
			var observed: Array=[]
			var positions: Array=[]
			stage.impact.connect(func(e): seen.append(e))
			for frame in range(240):
				if frame==30: view._present_batch(entries,before)
				var driver=stage._skill_presentation
				if is_instance_valid(driver) and driver.get("_vfx")!=null and driver._vfx.age>=0:
					observed.append(driver._vfx.impact_color.to_html())
					positions.append(stage._foot("boss").y)
				await process_frame
				await RenderingServer.frame_post_draw
				if frame in [30,108,116,228] and mode=="test":
					root.get_texture().get_image().save_png(output_dir.path_join("%s_%03d.png"%[attribute,frame]))
			var boss_events:=0
			for entry in seen:
				if str(entry.get("actor"))=="boss" and entry.get("skill_id","")=="boss_claw": boss_events+=1
			if boss_events!=1: _fail(mode+attribute+": missing/duplicate production boss skill")
			if observed.is_empty() or observed.any(func(c):return c!=Palette.color_for(attribute).to_html()): _fail(mode+attribute+": wrong attribute VFX")
			if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(mode+attribute+": cleanup")
			if view.session.battle.snapshot()!=resolved: _fail(mode+attribute+": battle changed")
			report.cases.append({"mode":mode,"attribute":attribute,"boss_events":boss_events,"expected_color":Palette.color_for(attribute).to_html(),"observed":not observed.is_empty(),"simulation_unchanged":view.session.battle.snapshot()==resolved})
			await _close_view()
	report["case_count"]=report.cases.size()
	report["passed"]=report.errors.is_empty()
	FileAccess.open(output_dir.path_join("golem-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GOLEM_GPU_DONE passed=",report.passed)
	quit(0 if report.passed else 1)
