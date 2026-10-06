extends RefCounted
## Real test/clear-check/challenge views hosted by gpu_runner.tscn.
const Driver = preload("res://src/bossmaker/visuals/rbm_astronaut_presentation.gd")
var _gpu_verification_completed := false
var tree: SceneTree
var output_dir := ""
var report := {"cases":[],"errors":[]}
var view: Control
var stage: Control

func fail(message: String) -> void:
	report.errors.append(message)
	push_error(message)

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	output_dir = directory
	DirAccess.make_dir_recursive_absolute(directory)
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name()=="headless": fail("A real GPU renderer is required")
	else:
		for entry in [["single",false],["aoe",false],["awakening",false],["single",true],["aoe",true],["buff",true],["heal",true]]:
			await run_case("test",entry[0],entry[1])
		for mode in ["clear_check","challenge"]:
			await run_case(mode,"aoe",true)
		await picker_case()
	report.passed = report.errors.is_empty()
	FileAccess.open(output_dir.path_join("astronaut-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	_gpu_verification_completed = true
	print("ASTRONAUT_GPU_DONE passed=",report.passed," cases=",report.cases.size())
	return 0 if report.passed else 1

func definition(kind: String) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "宇宙飛行士"
	draft.appearance_id = "appearance_astronaut"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ["hero","butler","healer","samurai"]: draft.add_party_character(id)
	var spec := {"name":"宇宙装備","type":"attack","target":"all" if kind=="aoe" else "single","attribute":"NEUTRAL","atk_multiplier":1.0}
	if kind in ["buff","heal"]: spec = {"name":"宇宙装備","type":"self_heal" if kind=="heal" else "atk_self_buff","heal_amount":200,"buff_multiplier":1.3,"duration_turns":3}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	return draft.to_definition()

func open_view(mode: String, def: Dictionary) -> void:
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	tree.root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge": view.setup(null)
	view.set_boss_appearance("appearance_astronaut")
	if mode == "test": view.start(def,20260927)
	elif mode == "clear_check": view.start_battle(def,20260927)
	else: view.start_battle(def,RBMBattleUiKit.ALL_VISIBLE,"appearance_astronaut")
	for i in 8: await tree.process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage",null)
	if stage == null: fail("Missing real stage: "+mode); return
	for i in 600:
		if not view._presenter.is_playing(): break
		await tree.process_frame
	stage._sound.muted = true

func capture(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	image.save_png(output_dir.path_join(tag+".png"))

func run_case(mode: String, kind: String, awakened: bool) -> void:
	await open_view(mode,definition(kind))
	if stage == null: return
	view.session.battle.boss.hp = 1500
	view.session.battle.is_awakened = awakened
	var before: Dictionary = {}
	var entry: Dictionary = {}
	for attempt in 16:
		before = view.session.battle.presentation_state().duplicate(true)
		var entries: Array = view.session.resolve_ally_action({"type":"defend"})
		for e in entries:
			if str(e.get("actor"))=="boss": entry=e
		if not entry.is_empty(): break
	if kind=="awakening":
		entry = {"actor":"boss","action":"awakening"}
		view.session.battle.is_awakened = true
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view,before)
	var impacts: Array = []
	stage.impact.connect(func(e):impacts.append(e))
	view._present_batch([entry],before)
	var driver = stage._skill_presentation
	if not driver is Driver:
		fail(mode+"/"+kind+": astronaut presentation was not dispatched")
	else:
		stage._tween.pause()
		var action: String = driver.action_kind
		var seconds: float = driver.duration
		var playback: Tween = stage._tween
		var tag: String = mode+"_"+action
		var stamps: Array = {"single":[1.7,3.12,3.48],"all":[2.95,3.49],"awakening":[3.2,5.9,6.60,9.0],"planet":[2.1,3.85,4.42],"blackhole":[.25,1.45,1.90,2.16,2.39,2.70,3.50,4.60,4.90,5.32,6.6],"buff":[1.3,1.9],"heal":[1.3,1.9]}[driver.action_kind]
		var saved := 0
		var t := 0.0
		var elapsed := Time.get_ticks_msec()
		while t < seconds-.001:
			playback.custom_step(1.0/60)
			t += 1.0/60
			await tree.process_frame
			if saved < stamps.size() and t >= stamps[saved]:
				await capture(tag+"_%0.2f"%stamps[saved])
				saved += 1
		if stage.is_playing(): playback.custom_step(30)
		for i in 3: await tree.process_frame
		if stage.is_playing(): fail(tag+": did not finish")
		if impacts.size()!=1: fail(tag+": impact count="+str(impacts.size()))
		if view.session.battle.snapshot()!=resolved: fail(tag+": presentation changed simulation")
		if stage._visuals.boss.z_index!=1: fail(tag+": boss drawing order not restored")
		if (awakened or kind=="awakening") and stage._asset_ids.boss!="astronaut_awakened": fail(tag+": lost awakened state")
		await capture(tag+"_finished")
		report.cases.append({"mode":mode,"action":action,"impacts":impacts.size(),"duration":seconds,"elapsed_ms":Time.get_ticks_msec()-elapsed,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	view.queue_free()
	await tree.process_frame
	await tree.process_frame

func picker_case() -> void:
	var picker := RBMCreatorAppearancePicker.new()
	tree.root.add_child(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.open("appearance_astronaut")
	for i in 5: await tree.process_frame
	var button := picker.find_child("Appearance_appearance_astronaut",true,false) as Button
	var scroll := picker.find_child("AppearanceScroll",true,false) as ScrollContainer
	if scroll == null:
		for child in picker.find_children("*","ScrollContainer",true,false): scroll=child
	if scroll != null and button != null: scroll.ensure_control_visible(button)
	for i in 5: await tree.process_frame
	var label := picker.find_child("AppearanceName_appearance_astronaut",true,false) as Label
	if label==null or label.text!="宇宙飛行士": fail("Picker is missing 宇宙飛行士")
	await capture("appearance_picker_astronaut")
	picker.queue_free()
	await tree.process_frame
