extends RefCounted
## Actual production views, presenter, resolved battle entries and native GPU rendering.
const Driver=preload("res://src/bossmaker/visuals/plush/rbm_plush_presentation.gd")
var _gpu_verification_completed:=false
var _tree_override: SceneTree
var output_dir: String
var report: Dictionary={"cases":[],"errors":[]}
var view=null
var stage=null
func _tree() -> SceneTree:return _tree_override
func _fail(message: String) -> void:
	if not report.errors.has(message):report.errors.append(message);push_error(message)
func _save(tag: String) -> void:
	if "--perf" in OS.get_cmdline_user_args():return
	_tree().root.get_texture().get_image().save_png(output_dir.path_join(tag+".png"))

func run_gpu_verification(tree: SceneTree,directory: String) -> int:
	_tree_override=tree;output_dir=directory
	tree.root.mode=Window.MODE_WINDOWED
	tree.root.size=Vector2i(1280,720)
	if "--1080" in OS.get_cmdline_user_args():
		tree.root.mode=Window.MODE_FULLSCREEN
		tree.root.size=Vector2i(1920,1080)
	tree.root.content_scale_size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(directory)
	report.renderer=RenderingServer.get_current_rendering_method();report.adapter=RenderingServer.get_video_adapter_name()
	report.requested_size=[1920,1080] if "--1080" in OS.get_cmdline_user_args() else [1280,720]
	await _run()
	if report.cases.size() != _expected_case_count():
		_fail("Verification stopped early: expected %d cases, got %d" % [_expected_case_count(), report.cases.size()])
	report.actual_size=[tree.root.size.x,tree.root.size.y]
	report.passed=report.errors.is_empty();report.case_count=report.cases.size()
	FileAccess.open(directory.path_join("plush-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	_gpu_verification_completed=true
	print("PLUSH_GPU_DONE ",report.passed," cases=",report.case_count)
	return 0 if report.passed else 1

func _run() -> void:
	if "--one" in OS.get_cmdline_user_args():
		await _case("test","single",true);return
	if "--defeat-only" in OS.get_cmdline_user_args():
		await _defeat(false);await _defeat(true);return
	if "--perf" in OS.get_cmdline_user_args():
		for aw in [false,true]:
			for kind in ["single","aoe","heal","buff"]:await _case("challenge",kind,aw)
		await _awakening();return
	if "--selection-only" in OS.get_cmdline_user_args():
		await _selection();return
	if "--capture" in OS.get_cmdline_user_args():
		await _case("challenge","single",false)
		await _case("challenge","aoe",false)
		await _case("challenge","heal",false)
		await _awakening()
		await _case("challenge","single",true)
		await _case("challenge","aoe",true)
		await _case("challenge","buff",true)
		await _defeat(true)
		return
	for aw in [false,true]:
		for kind in ["single","aoe","heal","buff"]:await _case("test",kind,aw)
	for mode in ["clear_check","challenge"]:
		await _case(mode,"single",true)
		await _case(mode,"aoe",true)
	await _case("test","single",true,true)
	await _case("test","aoe",true,true)
	await _awakening()
	await _defeat(false)
	await _defeat(true)
	await _selection()

func _case(mode: String,kind: String,awakened: bool,counter: bool=false) -> void:
	var definition:=_definition_for()
	if counter and kind=="single":definition.party=[definition.party[3]]
	var spec:={"skill_id":"boss_claw","name":"つめ" if kind=="single" else "綿と布","type":"attack","target":"all" if kind=="aoe" else "single","attribute":"NEUTRAL","atk_multiplier":1.0}
	if kind in ["buff","heal"]:spec={"skill_id":"boss_claw","name":"補修","type":"atk_self_buff" if kind=="buff" else "self_heal","buff_multiplier":1.3,"duration_turns":3,"heal_amount":200,"attribute":"NEUTRAL"}
	definition.boss.skills=[spec];definition.boss.atk=40;definition.boss.spd=1;definition.boss.boss_name="ぬいぐるみ"
	if not await _open_view(mode,definition):return
	view.session.battle.boss.hp=1000;view.session.battle.is_awakened=awakened
	var before: Dictionary={};var entry: Dictionary={}
	var samurai_id:=0 if counter and kind=="single" else 3
	for attempt in range(16):
		before=view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary={"type":"skill","skill_id":"samurai_counter"} if counter and view.session.pending_ally_id()==samurai_id else {"type":"defend"}
		for e in view.session.resolve_ally_action(action):
			if str(e.get("actor"))=="boss":entry=e
		if not entry.is_empty():break
	var tag:=mode+("_awakened_" if awakened else "_normal_")+kind+("_counter" if counter else "")
	if entry.is_empty():_fail(tag+": no resolved entry");await _close_view();return
	var snapshot: Dictionary=view.session.battle.snapshot().duplicate(true)
	stage.set_state(before);RBMBattlePresenter.apply_status_snapshot(view,before)
	print("PLUSH_STATE ",tag," before=",before.get("is_awakened")," stage=",stage._asset_ids.boss," after=",entry.visual_state.get("is_awakened"))
	var seen: Array=[];stage.impact.connect(func(e):seen.append(e))
	var observed:=false;var numbers_seen:=false;var saved:=false;var samples: Array=[];var slow: Array=[];var poses: Dictionary={}
	var last:=Time.get_ticks_usec()
	print("REVIEW_CHAPTER ",tag," ",Time.get_ticks_msec()," frame=",Engine.get_frames_drawn())
	view._present_batch([entry],before)
	print("PLUSH_PLAY ",tag," state=",stage._state.get("is_awakened")," asset=",stage._asset_ids.boss," phase=",stage._phase)
	for frame in range(1800):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();var dt:=float(now-last)/1000.0;last=now
		var driver=stage._skill_presentation
		if is_instance_valid(driver) and driver is Driver:
			if not observed:print("PLUSH_DRIVER ",tag," state=",stage._state.get("is_awakened")," asset=",stage._asset_ids.boss," form=",driver.form)
			observed=true
			for moment in [.20,.60,.70,1.0,1.10,1.30,1.50,1.70,1.90,2.12,2.35,2.57,2.76,2.93,3.24,3.51,3.75,3.99,4.48,4.55,5.30,5.70,6.20]:
				if driver.age>=moment and not poses.has(moment):
					_save(tag+"_pose_"+str(moment));poses[moment]=true
			if frame>8:samples.append(dt)
			if frame>8 and dt>20:slow.append({"ms":dt,"age":driver.age,"frame":frame})
			if driver.form!=("awakened" if awakened else "normal"):_fail(tag+": wrong form")
			if driver.age<driver.impact_time-.02 and not stage._damage_numbers._numbers.is_empty():_fail(tag+": numbers before contact")
			if not stage._damage_numbers._numbers.is_empty():
				numbers_seen=true
				if not saved and driver.age>driver.impact_time+.14:
					_save(tag+"_numbers");saved=true
					if stage._damage_numbers.z_index<=driver._body.screen_fx.z_index:_fail(tag+": numbers under blackout")
			if kind=="buff" and driver.age>driver.impact_time+.15 and not saved:_save(tag+"_support");saved=true
		var state: Dictionary=view._presenter.display_state()
		for key in state.get("party",{}):
			var unit: Dictionary=state.party[key]
			var label:=view.find_child("PartyRowHP_%s" % key,true,false) as Label
			if label!=null and label.text!="HP %d / %d" % [int(unit.hp),int(unit.max_hp)]:_fail(tag+": HUD HP not synchronized")
		if observed and not view._presenter.is_playing() and not stage.is_playing():break
	if not observed:_fail(tag+": no native driver")
	if kind!="buff" and not numbers_seen:_fail(tag+": no actual damage/heal numbers")
	if seen.size()!=1 or seen[0]!=entry:_fail(tag+": impact not exactly once")
	if view.session.battle.snapshot()!=snapshot:_fail(tag+": simulation mutated")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation) or not stage._visuals.boss.visible:_fail(tag+": cleanup")
	if stage.scale!=Vector2.ONE:_fail(tag+": camera not restored")
	samples.sort()
	report.cases.append({"id":tag,"impact_count":seen.size(),"numbers_visible":numbers_seen,"entry":entry,"max_ms":samples.back() if not samples.is_empty() else 0,"p99_ms":samples[int(samples.size()*.99)] if not samples.is_empty() else 0,"frames":samples.size(),"slow":slow})
	report.cases.back().merge(_timings(samples))
	print("PLUSH_CASE ",tag," numbers=",numbers_seen)
	await _close_view()

func _awakening() -> void:
	var definition:=_definition_for();definition.boss.hp=400;definition.boss.atk=10;definition.boss.boss_name="ぬいぐるみ"
	definition.boss.awakening={"conditions":[{"type":"hp_at_most","percent":50.0}],"condition_logic":"AND","buff":{"buff_multiplier":1.5,"duration_turns":3},"heal_amount":100}
	if not await _open_view("challenge",definition):return
	for i in range(12):
		if view.session.pending_ally_id()==0:break
		view.session.resolve_ally_action({"type":"defend"})
	var before: Dictionary=view.session.battle.presentation_state().duplicate(true)
	var entry: Dictionary={}
	for e in view.session.resolve_ally_action({"type":"attack"}):
		if str(e.get("action",""))=="awakening":entry=e
	if entry.is_empty():_fail("awakening missing");await _close_view();return
	stage.set_state(before)
	var seen: Array=[];stage.impact.connect(func(e):seen.append(e))
	var saved: Dictionary={};var observed:=false
	var samples: Array=[];var last:=Time.get_ticks_usec()
	print("REVIEW_CHAPTER awakening ",Time.get_ticks_msec()," frame=",Engine.get_frames_drawn())
	view._present_batch([entry],before)
	for i in range(1400):
		await _tree().process_frame;await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();var dt:=float(now-last)/1000.0;last=now
		var d=stage._skill_presentation
		if is_instance_valid(d) and d is Driver:
			observed=true
			if i>8:samples.append(dt)
			for t in [.5,.85,1.4,1.9,2.40,2.72,3.15,3.38,3.40,3.45,3.55,3.72,4.10,5.60]:
				if d.age>=t and not saved.has(t):_save("awakening_"+str(t));saved[t]=true
		if observed and not view._presenter.is_playing():break
	if seen.size()!=1 or stage._asset_ids.boss!="plush_awakened" or stage.scale!=Vector2.ONE:_fail("awakening finish contract")
	_save("awakening_persistent")
	samples.sort()
	report.cases.append({"id":"awakening","impact_count":seen.size(),"persistent_form":stage._asset_ids.boss,"max_ms":samples.back() if not samples.is_empty() else 0,"p99_ms":samples[int(samples.size()*.99)] if not samples.is_empty() else 0,"frames":samples.size()})
	report.cases.back().merge(_timings(samples))
	await _close_view()

func _timings(samples: Array) -> Dictionary:
	var total:=0.0;var over20:=0;var over33:=0
	for dt in samples:
		total+=float(dt)
		if dt>20:over20+=1
		if dt>33:over33+=1
	return {"average_fps":1000.0*samples.size()/maxf(total,.001),"over_20ms":over20,"over_33ms":over33,"over_20_percent":100.0*over20/maxi(1,samples.size())}

func _defeat(awakened: bool) -> void:
	var definition:=_definition_for();definition.boss.hp=400;definition.boss.atk=1;definition.boss.boss_name="ぬいぐるみ"
	if not await _open_view("challenge",definition):return
	view.session.battle.boss.hp=1;view.session.battle.is_awakened=awakened
	var before: Dictionary=view.session.battle.presentation_state().duplicate(true)
	stage.set_state(before)
	var entries: Array=view.session.resolve_ally_action({"type":"attack"})
	view._present_batch(entries,before)
	var tag:="defeat_awakened" if awakened else "defeat_normal"
	var observed:=false;var done:=false
	for i in range(1900):
		await _tree().process_frame;await RenderingServer.frame_post_draw
		for node in stage.get_children():
			if node.get_script()==preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd"):
				observed=true
				if node.state=="done":done=true
		if done:break
	for i in range(150):await _tree().process_frame
	_save(tag)
	if not observed or not done:_fail(tag+": victory did not complete")
	report.cases.append({"id":tag,"victory_seen":observed,"result_seen":done})
	await _close_view()

func _selection() -> void:
	var game:=RBMGameRoot.new()
	_tree().root.add_child(game)
	for i in range(10):await _tree().process_frame
	if "--english" in OS.get_cmdline_user_args():
		RBMLocale.set_locale("en")
		for i in range(3):await _tree().process_frame
	game._on_create_pressed()
	game.creator_entry.find_child("NewBossButton",true,false).pressed.emit()
	game.creator_entry.find_child("ChooseSimpleModeButton",true,false).pressed.emit()
	var main: RBMCreatorMain=game.creator_entry.main
	main.open_appearance_picker()
	var picker: RBMCreatorAppearancePicker=main._appearance_picker
	for i in range(5):await _tree().process_frame
	var button: Button=picker._entry_buttons.get("appearance_plush")
	if button==null:_fail("plush missing from selection");picker.queue_free();return
	# Bring the actual tenth card into the ScrollContainer viewport, without changing layout.
	var ancestor=button.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(button);break
		ancestor=ancestor.get_parent()
	for i in range(3):await _tree().process_frame
	await RenderingServer.frame_post_draw
	_save("selection_normal")
	var profile_toggle := picker.find_child("AwakenedPreviewToggle", true, false) as Button
	var toggle: Button
	if profile_toggle != null:
		button.pressed.emit()
		toggle = profile_toggle
	else:
		toggle = picker.get("_preview_toggle_buttons")["appearance_plush"]
	if toggle == null or toggle.disabled:
		_fail("plush awakening preview is unavailable")
		game.queue_free()
		return
	toggle.pressed.emit()
	await _tree().process_frame;await RenderingServer.frame_post_draw
	_save("selection_awakened")
	report.cases.append({"id":"selection","cards":picker._entry_buttons.size(),"plush_present":true,"awakening_toggle_enabled":not toggle.disabled})
	if profile_toggle != null:
		picker.call("_on_confirm_pressed")
	else:
		button.pressed.emit()
	if main.draft.appearance_id!="appearance_plush":_fail("actual Creator did not accept plush selection")
	for i in range(5):await _tree().process_frame
	_save("creator_selected")
	game.queue_free();await _tree().process_frame

func _definition_for() -> Dictionary:
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"] = []
	for id in ["hero", "butler", "healer", "samurai"]:
		var master: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/allies/" + id + ".json")
		var skill_ids: Array = []
		for skill in master.get("skills", []): skill_ids.append(skill["id"])
		definition.party.append({"character_id": id, "allowed_skill_ids": skill_ids})
	return definition

func _open_view(mode: String, definition: Dictionary) -> bool:
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge": view.setup(null)
	view.set_boss_appearance("appearance_plush")
	if mode!="test":view.request_encounter({"boss_name":"ぬいぐるみ","author":""})
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_plush")
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

func _expected_case_count() -> int:
	var args := OS.get_cmdline_user_args()
	if "--one" in args or "--selection-only" in args: return 1
	if "--defeat-only" in args: return 2
	if "--perf" in args: return 9
	if "--capture" in args: return 8
	return 18
