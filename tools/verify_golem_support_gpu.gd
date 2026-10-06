extends "res://tools/verify_battle_visuals_gpu.gd"
const Support=preload("res://src/bossmaker/visuals/rbm_golem_support.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")

func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	for mode in ["test","clear_check","challenge"]:
		for action in ["buff","heal"]: await _case(mode,action)
	report["case_count"]=report.cases.size()
	report["passed"]=report.errors.is_empty()
	FileAccess.open(output_dir.path_join("golem-support-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GOLEM_SUPPORT_GPU_DONE passed=",report.passed," cases=",report.case_count)
	quit(0 if report.passed else 1)

func _case(mode: String,action: String) -> void:
	var definition:=_definition_for("samurai")
	var spec={"skill_id":"boss_claw","name":"自己強化" if action=="buff" else "自己回復","type":"atk_self_buff" if action=="buff" else "self_heal","buff_multiplier":1.3,"duration_turns":3,"heal_amount":200,"attribute":"ICE" if action=="buff" else "FIRE"}
	definition.boss.skills=[spec]
	definition.boss.spd=1
	if not await _open_view(mode,definition,"appearance_golem"): return
	view.session.battle.boss.hp=1000
	var before: Dictionary={}
	var boss_entry: Dictionary={}
	for attempt in range(16):
		before=view.session.battle.presentation_state().duplicate(true)
		var entries: Array=view.session.resolve_ally_action({"type":"defend"})
		for e in entries:
			if str(e.get("actor"))=="boss": boss_entry=e
		if not boss_entry.is_empty(): break
	var tag:=mode+"_"+action
	if boss_entry.is_empty():
		_fail(tag+": no production support entry")
		await _close_view()
		return
	var resolved: Dictionary=view.session.battle.snapshot().duplicate(true)
	var after: Dictionary=view.session.battle.presentation_state()
	if action=="heal":
		if int(boss_entry.get("amount",0))!=200 or int(after.boss.hp)-int(before.boss.hp)!=200: _fail(tag+": real healing result")
	else:
		var buff: Dictionary=after.boss.get("timed_effects",{}).get("atk_buff",{})
		if not is_equal_approx(float(buff.get("value",0)),1.3) or int(buff.get("duration_turns",0))!=3: _fail(tag+": real buff result")
		if after.boss.hp!=before.boss.hp: _fail(tag+": buff changed HP")
	for key in before.party:
		if before.party[key].hp!=after.party[key].hp: _fail(tag+": support damaged party")
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view,before)
	var seen: Array=[]
	stage.impact.connect(func(e):seen.append(e))
	var observed:=false
	var direct_idle:=false
	var peak_seen:=false
	for frame in range(240):
		if frame==30: view._present_batch([boss_entry],before)
		var driver=stage._skill_presentation
		if is_instance_valid(driver):
			if driver.get_script()!=Support: _fail(tag+": wrong driver")
			else:
				observed=true
				if driver.mode!=action or VFX.COLORS[driver._vfx.mode]!=(Color("ef4847") if action=="buff" else Color("71da87")): _fail(tag+": incorrect semantic color")
				if driver.age>=1.5 and driver.age<2.0: peak_seen=true
				if driver.age>=2.18:
					direct_idle=true
					if stage._poses["boss"]!=0: _fail(tag+": second crouch")
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [85,132,173,235] and mode=="test":
			var img:=root.get_texture().get_image()
			if img==null: _fail(tag+": capture failed")
			else: img.save_png(output_dir.path_join("%s_%03d.png"%[action,frame]))
	if seen.size()!=1 or seen[0]!=boss_entry: _fail(tag+": expected one exact production entry")
	if not observed or not peak_seen or not direct_idle: _fail(tag+": incomplete timeline")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag+": cleanup")
	for key in stage._homes:
		if stage._visuals[key].position!=stage._homes[key]: _fail(tag+": actor position not restored")
	if view.session.battle.snapshot()!=resolved: _fail(tag+": simulation changed during playback")
	report.cases.append({"mode":mode,"action":action,"color":VFX.COLORS[action].to_html(),"impact_events":seen.size(),"production_skill_id":boss_entry.get("skill_id"),"direct_return_to_idle":direct_idle,"peak_observed":peak_seen,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	await _close_view()
