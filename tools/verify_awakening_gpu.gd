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
		var definition := _definition_for("tank")
		definition["boss"]["hp"] = 400
		definition["boss"]["awakening"] = {
			"conditions": [{"type": "hp_at_most", "percent": 50.0}],
			"condition_logic": "AND",
			"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
			"heal_amount": 50,
		}
		await _open_view(mode,definition,"appearance_dragon")
		var id:=_actor_id("hero")
		while view.session.pending_ally_id()!=id:
			view.session.resolve_ally_action({"type":"defend"})
		view.refresh()
		var initial: Dictionary=view.session.battle.presentation_state().duplicate(true)
		var resolved: Dictionary={}
		var seen: Array=[]
		var saw_awakened:=false
		stage.impact.connect(func(entry): seen.append(entry))
		for frame in range(240):
			if frame==40:
				var entries: Array=view.session.resolve_ally_action({"type":"attack"})
				resolved=view.session.battle.snapshot().duplicate(true)
				view._present_batch(entries,initial)
			if view.session.battle.is_awakened:
				saw_awakened=true
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [35,55,65,90,150,220]:
				var shot:=root.get_texture().get_image()
				if shot==null:_fail(mode+": null capture")
				else:shot.save_png(output_dir+"/%s_%03d.png"%[mode,frame])
		var awakening_events:=0
		for entry in seen:
			if str(entry.get("action",""))=="awakening":awakening_events+=1
		if awakening_events!=1:_fail(mode+": awakening impact count")
		if not saw_awakened:_fail(mode+": is_awakened never observed true")
		if stage.is_playing():_fail(mode+": unfinished visuals")
		if not view.session.battle.is_awakened:_fail(mode+": is_awakened did not persist after playback")
		if view.session.battle.snapshot()!=resolved:_fail(mode+": simulation changed during playback")
		report["cases"].append({"mode":mode,"awakening_events":awakening_events,"is_awakened_observed":saw_awakened,"simulation_unchanged":view.session.battle.snapshot()==resolved})
		await _close_view()
	report["case_count"]=report["cases"].size()
	report["passed"]=report["errors"].is_empty()
	FileAccess.open(output_dir+"/awakening-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AWAKENING_GPU_DONE passed=",report["passed"])
	quit(0 if report["passed"] else 1)
