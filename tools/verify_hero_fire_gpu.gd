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
		var id:=_actor_id("hero")
		while view.session.pending_ally_id()!=id:
			view.session.resolve_ally_action({"type":"defend"})
		view.refresh()
		var initial: Dictionary=view.session.battle.presentation_state().duplicate(true)
		var resolved: Dictionary={}
		var seen: Array=[]
		var ages: Array=[]
		stage.impact.connect(func(entry): seen.append(entry))
		for frame in range(420):
			if frame==72:
				var entries: Array=view.session.resolve_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
				resolved=view.session.battle.snapshot().duplicate(true)
				view._present_batch(entries,initial)
			if stage._hero_finish:
				if stage._phase=="travel" and stage._visuals[str(id)].position!=stage._homes[str(id)]:_fail(mode+": hero moved during projectile")
				ages.append(stage._hero_fire.age)
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [45,85,100,125,145,163,198,400]:
				var shot:=root.get_texture().get_image()
				if shot==null:_fail(mode+": null capture")
				else:shot.save_png(output_dir+"/%s_%03d.png"%[mode,frame])
		var hero_events:=0
		for entry in seen:
			if str(entry.get("skill_id",""))=="hero_burst_slash":hero_events+=1
		if hero_events!=1:_fail(mode+": hero impact count")
		if stage.is_playing() or stage._hero_fire.visible or stage._hero_shake!=Vector2.ZERO:_fail(mode+": unfinished visuals")
		if ages.is_empty() or ages.max()<2.0:_fail(mode+": finish did not run fully")
		if view.session.battle.snapshot()!=resolved:_fail(mode+": simulation changed during playback")
		report["cases"].append({"mode":mode,"hero_impacts":hero_events,"finish_observed":not ages.is_empty(),"simulation_unchanged":view.session.battle.snapshot()==resolved})
		await _close_view()
	report["case_count"]=report["cases"].size()
	report["passed"]=report["errors"].is_empty()
	FileAccess.open(output_dir+"/hero-fire-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("HERO_FIRE_GPU_DONE passed=",report["passed"])
	quit(0 if report["passed"] else 1)
