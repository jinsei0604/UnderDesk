extends "res://tools/verify_battle_visuals_gpu.gd"

func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	for mode in ["test","clear_check","challenge"]:
		await _open_view(mode,_definition_for("samurai"),"appearance_dragon")
		var id:=_actor_id("healer")
		while view.session.pending_ally_id()!=id: view.session.resolve_ally_action({"type":"defend"})
		for unit in view.session.battle.party: unit.hp=unit.max_hp-300
		view.refresh()
		var initial: Dictionary=view.session.battle.presentation_state().duplicate(true)
		var resolved: Dictionary={}
		var seen: Array=[]
		var peak_ages: Array=[]
		stage.impact.connect(func(entry):
			seen.append(entry)
			if entry.get("skill_id","")=="healer_heal_all" and is_instance_valid(stage._skill_presentation): peak_ages.append(stage._skill_presentation.age)
		)
		for frame in range(600):
			if frame==72:
				var entries: Array=view.session.resolve_ally_action({"type":"skill","skill_id":"healer_heal_all"})
				resolved=view.session.battle.snapshot().duplicate(true)
				view._present_batch(entries,initial)
			if frame==200 and view._presenter.display_state()!=initial: _fail(mode+": premature HP/SP update")
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [45,210,258,390,550]:
				var shot:=root.get_texture().get_image()
				if shot==null: _fail(mode+": null capture")
				else: shot.save_png(output_dir+"/%s_%03d.png"%[mode,frame])
		var events:=0
		for entry in seen:
			if entry.get("skill_id","")!="healer_heal_all": continue
			events+=1
			for key in initial.party:
				if int(entry.visual_state.party[key].hp)-int(initial.party[key].hp)!=200: _fail(mode+": wrong heal delta")
			if int(entry.visual_state.party[str(id)].sp)!=80: _fail(mode+": wrong SP")
		if events!=1 or peak_ages.is_empty() or peak_ages[0]<3.05: _fail(mode+": recovery peak timing/count")
		if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(mode+": unfinished visuals")
		if view.session.battle.snapshot()!=resolved: _fail(mode+": simulation mutated")
		report.cases.append({"mode":mode,"heal_events":events,"peak_ages":peak_ages,"simulation_unchanged":view.session.battle.snapshot()==resolved})
		await _close_view()
	report["case_count"]=report.cases.size()
	report["passed"]=report.errors.is_empty()
	FileAccess.open(output_dir+"/healer-saint-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HEALER_SAINT_GPU_DONE passed=",report.passed)
	quit(0 if report.passed else 1)
