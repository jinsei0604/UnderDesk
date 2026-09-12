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
		await _open_view(mode,_definition_for("tank"),"appearance_dragon")
		var id:=_actor_id("tank")
		while view.session.pending_ally_id()!=id:
			view.session.resolve_ally_action({"type":"defend"})
		view.refresh()
		var initial: Dictionary=view.session.battle.presentation_state().duplicate(true)
		var resolved: Dictionary={}
		var seen: Array=[]
		var ages: Array=[]
		var walked: Array=[]
		var saw_impact_frame:=false
		var impact_frame_shot_taken:=false
		stage.impact.connect(func(entry): seen.append(entry))
		for frame in range(300):
			if frame==72:
				var entries: Array=view.session.resolve_ally_action({"type":"skill","skill_id":"tank_hammer_smash"})
				resolved=view.session.battle.snapshot().duplicate(true)
				view._present_batch(entries,initial)
			if stage._tank_finish:
				ages.append(stage._tank_hammer.age)
				walked.append(stage._visuals[str(id)].position!=stage._homes[str(id)])
			if stage._tank_impact_frame.visible:
				saw_impact_frame=true
			await process_frame
			await RenderingServer.frame_post_draw
			if stage._tank_impact_frame.visible and not impact_frame_shot_taken:
				impact_frame_shot_taken=true
				var shot0:=root.get_texture().get_image()
				if shot0!=null: shot0.save_png(output_dir+"/%s_hitstop_%03d.png"%[mode,frame])
			if frame in [45,90,105,112,118,125,140,170,220,280]:
				var shot:=root.get_texture().get_image()
				if shot==null:_fail(mode+": null capture")
				else:shot.save_png(output_dir+"/%s_%03d.png"%[mode,frame])
		if not saw_impact_frame:_fail(mode+": black-and-white impact frame never became visible")
		var tank_events:=0
		for entry in seen:
			if str(entry.get("skill_id",""))=="tank_hammer_smash":tank_events+=1
		if tank_events!=1:_fail(mode+": tank impact count")
		if stage.is_playing() or stage._tank_hammer.visible or stage._tank_impact_frame.visible or stage._tank_shake!=Vector2.ZERO:_fail(mode+": unfinished visuals")
		if ages.is_empty() or ages.max()<1.5:_fail(mode+": finish did not run fully")
		if not walked.has(true):_fail(mode+": tank never walked into melee range")
		if view.session.battle.snapshot()!=resolved:_fail(mode+": simulation changed during playback")
		report["cases"].append({"mode":mode,"tank_impacts":tank_events,"finish_observed":not ages.is_empty(),"walked":walked.has(true),"simulation_unchanged":view.session.battle.snapshot()==resolved})
		await _close_view()
	report["case_count"]=report["cases"].size()
	report["passed"]=report["errors"].is_empty()
	FileAccess.open(output_dir+"/tank-hammer-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TANK_HAMMER_GPU_DONE passed=",report["passed"])
	quit(0 if report["passed"] else 1)
