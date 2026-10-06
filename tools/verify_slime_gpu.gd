extends RefCounted
## Existing production-view fixtures, hosted by the live GPU runner tree.
const Driver=preload("res://src/bossmaker/visuals/rbm_slime_presentation.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_slime_vfx.gd")
## The expected attack/support color is counted on every frame from 0.10 s to 0.50 s after the
## impact, and the most pixels seen must exceed the count from just before the action by at
## least MIN_ADDED_PIXELS. One sample at a fixed moment was fragile: the support VFX has a planned
## gap between its two bright phases, and a single long frame could move that sample into it.
const COLOR_WINDOW_START:=.10
const COLOR_WINDOW_END:=.50
const MIN_ADDED_PIXELS:=4

var _gpu_verification_completed:=false

var _tree_override: SceneTree
var output_dir: String
var report: Dictionary={"cases":[],"errors":[]}
var view = null
var stage = null
func _tree() -> SceneTree:
	return _tree_override
func _fail(message: String) -> void:
	if not report.errors.has(message): report.errors.append(message)
	push_error(message)


func run_gpu_verification(tree: SceneTree,directory: String) -> int:
	_tree_override=tree
	output_dir=directory
	report["renderer"]=RenderingServer.get_current_rendering_method()
	report["adapter"]=RenderingServer.get_video_adapter_name()
	report["engine"]=Engine.get_version_info().string
	await _run()
	if report.has("passed") and report.has("case_count"):
		_gpu_verification_completed=true
	return 0 if report.get("passed",false) else 1

func _run() -> void:
	_tree().root.size=Vector2i(1280,720)
	_tree().root.content_scale_size=Vector2i(1280,720)
	_tree().root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name()=="headless":
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
	FileAccess.open(output_dir.path_join("slime-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SLIME_GPU_DONE passed=",report.passed," cases=",report.case_count)


func _matching_pixels(img: Image,expected: Color) -> int:
	if img==null: return 0
	var count:=0
	for y in range(0,img.get_height(),2):
		for x in range(0,img.get_width(),2):
			var c:=img.get_pixel(x,y)
			if c.a<.12: continue
			if absf(c.r-expected.r)<.03 and absf(c.g-expected.g)<.03 and absf(c.b-expected.b)<.03: count+=1
	return count

func _case(mode: String,kind: String,attribute: String,counter: bool) -> void:
	var definition:=_definition_for("samurai")
	if counter and kind=="single": definition.party=[definition.party[3]]
	var spec={"skill_id":"boss_claw","name":"伸縮パンチ" if kind=="single" else "全方位しぶき","type":"attack","target":"all" if kind=="aoe" else "single","attribute":attribute,"atk_multiplier":1.0}
	if kind in ["buff","heal"]:
		spec={"skill_id":"boss_claw","name":"液体集束・強化" if kind=="buff" else "液体集束・回復","type":"atk_self_buff" if kind=="buff" else "self_heal","buff_multiplier":1.3,"duration_turns":3,"heal_amount":200,"attribute":attribute}
	definition.boss.skills=[spec]
	definition.boss.atk=40
	definition.boss.spd=1
	if not await _open_view(mode,definition,"appearance_slime"): return
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
	var deformation_seen:=false
	var colored_pixels:=-1
	var baseline_pixels:=-1
	var color_samples:=0
	var screenshots:={}
	var expected: Color=VFX.SUPPORT[kind] if kind in VFX.SUPPORT else Palette.color_for(attribute)
	for frame in range(780 if counter else 240):
		if frame==30:
			baseline_pixels=_matching_pixels(_tree().root.get_texture().get_image(),expected)
			view._present_batch([entry],before)
		var driver=stage._skill_presentation
		if is_instance_valid(driver):
			if not driver is Driver: _fail(tag+": wrong driver")
			else:
				observed=true
				if driver.kind!=kind: _fail(tag+": wrong motion")
				if kind in ["single","aoe"] and driver._vfx.attack_attribute!=attribute: _fail(tag+": wrong attribute input")
				if driver._vfx.state.get("scale",Vector2.ONE)!=Vector2.ONE: deformation_seen=true
				var since_impact: float=driver.age-driver.impact_time
				if since_impact>=COLOR_WINDOW_START and since_impact<=COLOR_WINDOW_END:
					color_samples+=1
					colored_pixels=maxi(colored_pixels,_matching_pixels(_tree().root.get_texture().get_image(),expected))
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		if frame in [68,95,105,230] and mode=="test" and not counter and (attribute=="NEUTRAL" or kind in ["buff","heal"]):
			var img:=_tree().root.get_texture().get_image()
			# Saved after playback: encoding a PNG here stalled playback by about 0.26 s.
			if img!=null: screenshots[frame]=img
	for frame in screenshots: screenshots[frame].save_png(output_dir.path_join("%s_%03d.png"%[tag,frame]))
	if observed and color_samples==0: _fail(tag+": color window was not sampled")
	if not observed or colored_pixels-baseline_pixels<MIN_ADDED_PIXELS: _fail(tag+": expected rendered color not found")
	if not deformation_seen: _fail(tag+": approved body deformation missing")
	if not stage._visuals["boss"].visible: _fail(tag+": boss visibility not restored")
	if seen.size()!=1 or seen[0]!=entry: _fail(tag+": impact contract")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag+": cleanup")
	if stage._visuals["boss"].scale!=Vector2.ONE or stage._visuals["boss"].pivot_offset!=Vector2.ZERO: _fail(tag+": transform not restored")
	for key in stage._homes:
		if stage._visuals[key].position!=stage._homes[key]: _fail(tag+": position not restored")
	if view.session.battle.snapshot()!=resolved: _fail(tag+": simulation changed during playback")
	report.cases.append({"mode":mode,"kind":kind,"attribute":attribute,"expected_color":expected.to_html(),"rendered_color_pixels":colored_pixels,"baseline_color_pixels":baseline_pixels,"color_samples":color_samples,"counter":counter,"counter_count":counters,"production_skill_id":entry.get("skill_id"),"impact_events":seen.size(),"body_deformation":deformation_seen,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	print("SLIME_CASE ",tag," pixels=",colored_pixels," baseline=",baseline_pixels," samples=",color_samples)
	await _close_view()

func _master(character_id: String) -> Dictionary:
	return RBMDataLoader.load_dict("res://data_bossmaker/allies/" + character_id + ".json")

func _definition_for(character_id: String) -> Dictionary:
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var roster := ["hero", "butler", "healer", "samurai" if character_id == "samurai" else "tank"]
	definition["party"] = []
	for id in roster:
		var skill_ids: Array = []
		for skill in _master(id).get("skills", []): skill_ids.append(skill["id"])
		definition["party"].append({"character_id": id, "allowed_skill_ids": skill_ids})
	return definition

func _open_view(mode: String, definition: Dictionary, appearance_id: String) -> bool:
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge": view.setup(null)
	view.set_boss_appearance(appearance_id)
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, appearance_id)
	for i in range(8): await _tree().process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage", null)
	if stage == null or not stage.has_method("get_visual_audit"):
		_fail("Production View has no auditable visual stage: " + mode)
		return false
	var ticks := 0
	while view._presenter.is_playing() and ticks < 600:
		await _tree().process_frame
		ticks += 1
	stage.set_state(view.session.battle.presentation_state())
	return true

func _close_view() -> void:
	if is_instance_valid(view): view.queue_free()
	view = null
	stage = null
	await _tree().process_frame

