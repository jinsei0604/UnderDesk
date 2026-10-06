extends "res://tools/verify_battle_visuals_gpu.gd"
const Driver=preload("res://src/bossmaker/visuals/rbm_wolf_presentation.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_wolf_vfx.gd")

func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	for attribute in Palette.COLORS:
		for kind in ["single","aoe"]: await _case("test",kind,attribute,false)
	for mode in ["test","clear_check","challenge"]:
		if mode!="test":
			for kind in ["single","aoe"]: await _case(mode,kind,"NEUTRAL",false)
		for kind in ["buff","heal"]: await _case(mode,kind,"ICE" if kind=="buff" else "FIRE",false)
	for kind in ["single","aoe"]: await _case("test",kind,"WIND",true)
	report["case_count"]=report.cases.size()
	report["passed"]=report.errors.is_empty()
	FileAccess.open(output_dir.path_join("wolf-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WOLF_GPU_DONE passed=",report.passed," cases=",report.case_count)
	quit(0 if report.passed else 1)

func _matching_pixels(img: Image,expected: Color) -> int:
	if img==null: return 0
	var count:=0
	for y in range(0,img.get_height(),2):
		for x in range(0,img.get_width(),2):
			var c:=img.get_pixel(x,y)
			if c.a<.12: continue
			if expected.s<.12:
				if c.s<.14: count+=1
			else:
				var delta:=absf(c.h-expected.h)
				if minf(delta,1-delta)<.055 and c.s>.18: count+=1
	return count

func _case(mode: String,kind: String,attribute: String,counter: bool) -> void:
	var definition:=_definition_for("samurai")
	if counter and kind=="single": definition.party=[definition.party[3]]
	var spec={"skill_id":"boss_claw","name":"狼の噛みつき" if kind=="single" else "狼の疾走","type":"attack","target":"all" if kind=="aoe" else "single","attribute":attribute,"atk_multiplier":1.0}
	if kind in ["buff","heal"]:
		spec={"skill_id":"boss_claw","name":"遠吠え・強化" if kind=="buff" else "遠吠え・回復","type":"atk_self_buff" if kind=="buff" else "self_heal","buff_multiplier":1.3,"duration_turns":3,"heal_amount":200,"attribute":attribute}
	definition.boss.skills=[spec]
	definition.boss.atk=40
	definition.boss.spd=1
	if not await _open_view(mode,definition,"appearance_wolf"): return
	view.session.battle.boss.hp=1000
	var before: Dictionary={}
	var entry: Dictionary={}
	var samurai_id:=0 if counter and kind=="single" else 3
	for attempt in range(16):
		before=view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary={"type":"skill","skill_id":"samurai_counter"} if counter and view.session.pending_ally_id()==samurai_id else {"type":"defend"}
		var entries: Array=view.session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor"))=="boss": entry=e
		if not entry.is_empty(): break
	var tag:=mode+"_"+kind+"_"+attribute+("_counter" if counter else "")
	if entry.is_empty():
		_fail(tag+": no production entry")
		await _close_view()
		return
	var resolved: Dictionary=view.session.battle.snapshot().duplicate(true)
	var after: Dictionary=view.session.battle.presentation_state()
	var counters:=int(entry.get("counter",false))
	for hit in entry.get("hits",{}).values(): counters+=int(hit.get("counter",false))
	if counter and counters!=1: _fail(tag+": real counter missing")
	if kind=="aoe" and entry.get("hits",{}).size()!=4: _fail(tag+": expected four hits")
	if kind=="heal" and (int(entry.get("amount",0))!=200 or int(after.boss.hp)-int(before.boss.hp)!=200): _fail(tag+": real healing failed")
	if kind=="buff":
		var buff: Dictionary=after.boss.get("timed_effects",{}).get("atk_buff",{})
		if not is_equal_approx(float(buff.get("value",0)),1.3): _fail(tag+": real buff failed")
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view,before)
	var seen: Array=[]
	stage.impact.connect(func(e):seen.append(e))
	var observed:=false
	var turn_seen:=false
	var colored_pixels:=-1
	var expected: Color=VFX.SUPPORT[kind] if kind in VFX.SUPPORT else Palette.color_for(attribute)
	for frame in range(780 if counter else 240):
		if frame==30: view._present_batch([entry],before)
		var driver=stage._skill_presentation
		if is_instance_valid(driver):
			if not driver is Driver: _fail(tag+": wrong driver")
			else:
				observed=true
				if driver.kind!=kind: _fail(tag+": wrong motion")
				if kind in ["single","aoe"] and driver._vfx.attack_attribute!=attribute: _fail(tag+": wrong attribute input")
				if kind=="single" and driver.age>=1.0 and driver.age<1.45 and stage._visuals["boss"].scale.x<0: turn_seen=true
				if driver.age>=driver.impact_time+.10 and colored_pixels<0:
					colored_pixels=_matching_pixels(driver._vfx.get_parent().get_texture().get_image(),expected)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [68,95,105,230] and mode=="test" and not counter:
			var img:=root.get_texture().get_image()
			if img!=null: img.save_png(output_dir.path_join("%s_%03d.png"%[tag,frame]))
	if not observed or colored_pixels<10: _fail(tag+": expected rendered color not found")
	if kind=="single" and not turn_seen: _fail(tag+": turning return missing")
	if seen.size()!=1 or seen[0]!=entry: _fail(tag+": impact contract")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag+": cleanup")
	if stage._visuals["boss"].scale!=Vector2.ONE or stage._visuals["boss"].pivot_offset!=Vector2.ZERO: _fail(tag+": transform not restored")
	for key in stage._homes:
		if stage._visuals[key].position!=stage._homes[key]: _fail(tag+": position not restored")
	if view.session.battle.snapshot()!=resolved: _fail(tag+": simulation changed during playback")
	report.cases.append({"mode":mode,"kind":kind,"attribute":attribute,"expected_color":expected.to_html(),"rendered_color_pixels":colored_pixels,"counter":counter,"counter_count":counters,"production_skill_id":entry.get("skill_id"),"impact_events":seen.size(),"turning_return":turn_seen,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	print("WOLF_CASE ",tag," pixels=",colored_pixels)
	await _close_view()
