extends RefCounted
## Real test/clear-check/challenge views hosted by gpu_runner.tscn.
const Driver = preload("res://src/bossmaker/visuals/rbm_gentleman_presentation.gd")
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
	FileAccess.open(output_dir.path_join("gentleman-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	_gpu_verification_completed = true
	print("GENTLEMAN_GPU_DONE passed=",report.passed," cases=",report.cases.size())
	return 0 if report.passed else 1

func definition(kind: String) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "異形紳士"
	draft.appearance_id = "appearance_gentleman"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ["hero","butler","healer","samurai"]: draft.add_party_character(id)
	var spec := {"name":"異形紳士の技","type":"attack","target":"all" if kind=="aoe" else "single","attribute":"NEUTRAL","atk_multiplier":1.0}
	if kind in ["buff","heal"]: spec = {"name":"異形紳士の技","type":"self_heal" if kind=="heal" else "atk_self_buff","heal_amount":200,"buff_multiplier":1.3,"duration_turns":3}
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
	view.battle_background = "day"
	view.set_boss_appearance("appearance_gentleman")
	if mode == "test": view.start(def,20260927)
	elif mode == "clear_check": view.start_battle(def,20260927)
	else: view.start_battle(def,RBMBattleUiKit.ALL_VISIBLE,"appearance_gentleman")
	for i in 8: await tree.process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage",null)
	if stage == null: fail("Missing real stage: "+mode); return
	for i in 600:
		if not view._presenter.is_playing(): break
		await tree.process_frame
	stage._sound.muted = true
	var expected_path := "res://assets_bossmaker/battle/backgrounds/gentleman/background.png"
	if view._world_battle.background.texture.resource_path != expected_path: fail(mode+": wrong fixed background")

## QA-06: 演出は宣言した素材を読み終えてから始まる(読み終えていない時、ステージは開始を待つ)。実際のゲーム
## (戦闘を始める前の画面から裏で読み込む)と同じく、事前読み込みが今の外見の計画を読み終えてから再生する。
## 覚醒のケースは覚醒が設定されていない戦闘に覚醒を流すので(計画に入らない)、覚醒の演出の素材も読み終えるまで待つ。
func warmed(awakening: bool = false) -> void:
	var warm = stage.get("_presentation_warmup")
	for i in 900:
		await tree.process_frame
		if warm == null:
			return
		if awakening and not warm.ensure(RBMBattleStage.BOSS_AWAKENING_PRESENTATIONS["gentleman"], "gentleman", "awakening").is_empty():
			continue
		if warm._key == str(warm._source().get("key","")) and warm.is_ready(): return

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
	await warmed(kind=="awakening")
	var impacts: Array = []
	stage.impact.connect(func(e):impacts.append(e))
	view._present_batch([entry],before)
	var driver = stage._skill_presentation
	if not driver is Driver:
		fail(mode+"/"+kind+": gentleman presentation was not dispatched")
	else:
		stage._tween.pause()
		var action: String = driver.action_kind
		var seconds: float = driver.duration
		var playback: Tween = stage._tween
		var tag: String = mode+"_"+action
		var stamps: Array = [seconds*.15,seconds*.40,driver.impact_time+.10,seconds-.3]
		if kind=="awakening": stamps=[2.7,6.8,8.16,10.1,11.6]
		elif kind=="aoe": stamps=[float(driver._vfx.data.bow.bow_end),float(driver._vfx.data.shadows.back().hit),float(driver._vfx.data.host[0].time)+.04,driver.impact_time+.17,seconds-.3]
		elif kind=="single" and awakened: stamps=[float(driver._vfx.data.host[0].time)+.04,float(driver._vfx.data.host[1].time)+.04,driver.impact_time+.17,seconds-.3]
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
		if (awakened or kind=="awakening") and stage._asset_ids.boss!="gentleman_awakened": fail(tag+": lost awakened state")
		await capture(tag+"_finished")
		report.cases.append({"mode":mode,"action":action,"impacts":impacts.size(),"duration":seconds,"elapsed_ms":Time.get_ticks_msec()-elapsed,"simulation_unchanged":view.session.battle.snapshot()==resolved})
	view.queue_free()
	await tree.process_frame
	await tree.process_frame

func picker_case() -> void:
	var picker := RBMCreatorAppearancePicker.new()
	tree.root.add_child(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.open("appearance_gentleman")
	for i in 5: await tree.process_frame
	var button := picker.find_child("Appearance_appearance_gentleman",true,false) as Button
	var scroll := picker.find_child("AppearanceScroll",true,false) as ScrollContainer
	if scroll == null:
		for child in picker.find_children("*","ScrollContainer",true,false): scroll=child
	if scroll != null and button != null: scroll.ensure_control_visible(button)
	for i in 5: await tree.process_frame
	var label := picker.find_child("AppearanceName_appearance_gentleman",true,false) as Label
	if label==null or label.text!="異形紳士": fail("Picker is missing 異形紳士")
	await capture("appearance_picker_gentleman")
	picker.queue_free()
	await tree.process_frame
