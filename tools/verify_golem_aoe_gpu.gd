extends "res://tools/verify_battle_visuals_gpu.gd"
const Ground=preload("res://src/bossmaker/visuals/rbm_golem_ground_slam.gd")
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
			await _case(mode,attribute,false)
	await _case("test","WIND",true)
	report["case_count"]=report.cases.size()
	report["passed"]=report.errors.is_empty()
	FileAccess.open(output_dir.path_join("golem-aoe-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("GOLEM_AOE_GPU_DONE passed=",report.passed," cases=",report.case_count)
	quit(0 if report.passed else 1)

func _case(mode: String,attribute: String,counter: bool) -> void:
	var definition:=_definition_for("samurai")
	definition.boss.skills[0].attribute=attribute
	definition.boss.skills[0].name="ゴーレムの地砕き"
	definition.boss.skills[0].target="all"
	definition.boss.spd=1
	definition.boss.atk=40
	if not await _open_view(mode,definition,"appearance_golem"): return
	var before: Dictionary={}
	var boss_entry: Dictionary={}
	for attempt in range(16):
		before=view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary={"type":"skill","skill_id":"samurai_counter"} if counter and view.session.pending_ally_id()==3 else {"type":"defend"}
		var entries: Array=view.session.resolve_ally_action(action)
		for entry in entries:
			if str(entry.get("actor"))=="boss": boss_entry=entry
		if not boss_entry.is_empty(): break
	var tag:=mode+"_"+attribute+("_counter" if counter else "")
	if boss_entry.is_empty():
		_fail(tag+": no production boss entry")
		await _close_view()
		return
	var resolved: Dictionary=view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view,before)
	var seen: Array=[]
	stage.impact.connect(func(e):seen.append(e))
	var observed:=false
	var contact_seen:=false
	var eruption_seen:=false
	var wrong_driver:=false
	for frame in range(720 if counter else 330):
		if frame==30: view._present_batch([boss_entry],before)
		var driver=stage._skill_presentation
		if is_instance_valid(driver):
			if driver.get_script()!=Ground:
				wrong_driver=true
			else:
				observed=true
				if driver._vfx.attribute!=attribute: _fail(tag+": wrong palette input")
				contact_seen=contact_seen or (driver.age>=.72 and driver.age<1.0)
				eruption_seen=eruption_seen or (driver.age>=1.64 and driver.age<1.9)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [30,82,136,155,320] and mode=="test" and not counter:
			var img:=root.get_texture().get_image()
			if img==null: _fail(tag+": null capture")
			else: img.save_png(output_dir.path_join("%s_%03d.png"%[attribute,frame]))
	var event_count:=0
	for entry in seen:
		if str(entry.get("actor"))=="boss" and entry.get("skill_id","")=="boss_claw": event_count+=1
	var hits: Dictionary=boss_entry.get("hits",{})
	var counters:=0
	for hit in hits.values():
		if hit.get("counter",false): counters+=1
		elif int(hit.get("amount",0))<=0: _fail(tag+": expected positive party damage")
	if hits.size()!=4: _fail(tag+": expected four actual hit targets")
	if counter and counters!=1: _fail(tag+": missing real samurai counter")
	if event_count!=1: _fail(tag+": missing/duplicate production impact")
	if not observed or not contact_seen or not eruption_seen or wrong_driver: _fail(tag+": dedicated timeline not observed")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag+": cleanup")
	for key in stage._homes:
		if stage._visuals[key].position!=stage._homes[key]: _fail(tag+": actor not restored")
	if view.session.battle.snapshot()!=resolved: _fail(tag+": battle changed by presentation")
	report.cases.append({"mode":mode,"attribute":attribute,"color":Palette.color_for(attribute).to_html(),"counter":counter,"actual_counter_count":counters,"production_skill_id":boss_entry.get("skill_id"),"hit_targets":hits.size(),"impact_events":event_count,"ground_contact_observed":contact_seen,"eruption_observed":eruption_seen,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	await _close_view()
