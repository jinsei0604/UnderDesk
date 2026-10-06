extends RefCounted
## Targeted dragon verification hosted by the standard production GPU runner.
const Driver = preload("res://src/bossmaker/visuals/rbm_dragon_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
var _gpu_verification_completed := false
var _tree_override: SceneTree
var output_dir: String
var report: Dictionary = {"cases": [], "errors": []}
var view = null
var stage = null

func _tree() -> SceneTree: return _tree_override
func _fail(message: String) -> void:
	if not report.errors.has(message):
		report.errors.append(message)
		push_error(message)

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	_tree_override = tree
	output_dir = directory
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["engine"] = Engine.get_version_info().string
	await _run()
	if report.has("passed") and report.has("case_count"): _gpu_verification_completed = true
	return 0 if report.get("passed", false) else 1

func _run() -> void:
	_tree().root.size = Vector2i(1280, 720)
	_tree().root.content_scale_size = Vector2i(1280, 720)
	_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name() == "headless": return
	if "--awakening-only" in OS.get_cmdline_user_args():
		for mode in ["test","clear_check","challenge"]: await _awakening_case(mode)
		report["case_count"]=report.cases.size()
		report["passed"]=report.errors.is_empty()
		FileAccess.open(output_dir.path_join("dragon-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("DRAGON_GPU_DONE passed=",report.passed," cases=",report.case_count)
		return
	if "--spectacle-only" in OS.get_cmdline_user_args():
		for attribute in Palette.COLORS:
			await _case("test","single",attribute,true)
			await _case("test","aoe",attribute,true)
		for mode in ["test","clear_check","challenge"]: await _awakening_case(mode)
		await _case("test","aoe","FIRE",true,true)
		report["case_count"]=report.cases.size()
		report["passed"]=report.errors.is_empty()
		FileAccess.open(output_dir.path_join("dragon-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("DRAGON_GPU_DONE passed=",report.passed," cases=",report.case_count)
		return
	if "--ranged-only" in OS.get_cmdline_user_args():
		for attribute in Palette.COLORS:
			await _case("test","aoe",attribute,false)
			await _case("test","single",attribute,true)
			await _case("test","aoe",attribute,true)
		for mode in ["clear_check","challenge"]:
			await _case(mode,"aoe","NEUTRAL",false)
			await _case(mode,"single","NEUTRAL",true)
			await _case(mode,"aoe","NEUTRAL",true)
		await _case("test","single","WIND",true,true)
		await _case("test","aoe","FIRE",true,true)
		report["case_count"]=report.cases.size()
		report["passed"]=report.errors.is_empty()
		FileAccess.open(output_dir.path_join("dragon-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("DRAGON_GPU_DONE passed=",report.passed," cases=",report.case_count)
		return
	if "--review-only" in OS.get_cmdline_user_args():
		for mode in ["test", "clear_check", "challenge"]:
			await _case(mode, "single", "NEUTRAL", false)
		await _case("test", "single", "WIND", false, true)
		await _awakening_case("test")
		await _case("test", "single", "NEUTRAL", true)
		await _case("test", "aoe", "NEUTRAL", true)
		report["case_count"] = report.cases.size()
		report["passed"] = report.errors.is_empty()
		FileAccess.open(output_dir.path_join("dragon-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
		print("DRAGON_GPU_DONE passed=", report.passed, " cases=", report.case_count)
		return
	if "--bite-only" in OS.get_cmdline_user_args():
		await _case("test", "single", "NEUTRAL", false)
		report["case_count"] = report.cases.size()
		report["passed"] = report.errors.is_empty()
		FileAccess.open(output_dir.path_join("dragon-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
		print("DRAGON_GPU_DONE passed=", report.passed, " cases=", report.case_count)
		return
	# Five colors on the changed bite; one representative of the established actions.
	for attribute in Palette.COLORS: await _case("test", "single", attribute, false)
	await _case("test", "aoe", "NEUTRAL", false)
	await _case("test", "single", "NEUTRAL", true)
	await _case("test", "aoe", "NEUTRAL", true)
	for awakened in [false, true]:
		for kind in ["buff", "heal"]: await _case("test", kind, "ICE" if kind == "buff" else "FIRE", awakened)
	for mode in ["clear_check", "challenge"]:
		await _case(mode, "single", "NEUTRAL", false)
	for mode in ["test", "clear_check", "challenge"]: await _awakening_case(mode)
	await _case("test", "single", "WIND", false, true)
	await _case("test", "aoe", "FIRE", true, true)
	report["case_count"] = report.cases.size()
	report["passed"] = report.errors.is_empty()
	FileAccess.open(output_dir.path_join("dragon-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DRAGON_GPU_DONE passed=", report.passed, " cases=", report.case_count)

func _matching_pixels(img: Image, expected: Color) -> int:
	if img == null: return 0
	var count := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a >= .12 and absf(c.r - expected.r) < .03 and absf(c.g - expected.g) < .03 and absf(c.b - expected.b) < .03: count += 1
	return count

func _save(tag: String) -> void:
	var img := _tree().root.get_texture().get_image()
	if img == null: _fail(tag + ": no GPU image")
	else: img.save_png(output_dir.path_join(tag + ".png"))

func _expected_action(kind: String, awakened: bool) -> String:
	if kind in ["buff", "heal"]: return kind
	return ("focused_breath" if kind == "single" else "meteors") if awakened else ("bite" if kind == "single" else "breath")

func _check_restored(tag: String, awakened: bool) -> void:
	if not stage._visuals["boss"].visible: _fail(tag + ": boss visibility not restored")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag + ": presentation cleanup")
	if stage._visuals["boss"].scale != Vector2.ONE or stage._visuals["boss"].pivot_offset != Vector2.ZERO: _fail(tag + ": transform not restored")
	if stage._asset_ids["boss"] != ("dragon_awakened" if awakened else "dragon"): _fail(tag + ": wrong persistent form")
	for key in stage._homes:
		if stage._visuals[key].position != stage._homes[key]: _fail(tag + ": position not restored")

func _case(mode: String, kind: String, attribute: String, awakened: bool, counter: bool = false) -> void:
	var definition := _definition_for()
	if counter and kind == "single": definition.party = [definition.party[3]]
	var spec := {"skill_id": "boss_claw", "name": "Dragon QA " + kind, "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"skill_id": "boss_claw", "name": "Dragon roar", "type": "atk_self_buff" if kind == "buff" else "self_heal", "buff_multiplier": 1.3, "duration_turns": 3, "heal_amount": 200, "attribute": attribute}
	definition.boss.skills = [spec]
	definition.boss.atk = 40
	definition.boss.spd = 1
	if not await _open_view(mode, definition): return
	view.session.battle.boss.hp = 1000
	view.session.battle.is_awakened = awakened
	var before: Dictionary = {}
	var entry: Dictionary = {}
	var samurai_id := 0 if counter and kind == "single" else 3
	for attempt in range(16):
		before = view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and view.session.pending_ally_id() == samurai_id else {"type": "defend"}
		var entries: Array = view.session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var tag := mode + ("_awakened_" if awakened else "_normal_") + kind + "_" + attribute + ("_counter" if counter else "")
	if entry.is_empty():
		_fail(tag + ": no production entry")
		await _close_view()
		return
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	var after: Dictionary = view.session.battle.presentation_state()
	var counters := int(entry.get("counter", false))
	for hit in entry.get("hits", {}).values(): counters += int(hit.get("counter", false))
	if counter and counters != 1: _fail(tag + ": real counter missing")
	if kind == "aoe" and entry.get("hits", {}).size() != 4: _fail(tag + ": expected four targets")
	if kind == "heal" and (int(entry.get("amount", 0)) != 200 or int(after.boss.hp) - int(before.boss.hp) != 200): _fail(tag + ": real healing failed")
	if kind == "buff":
		var buff: Dictionary = after.boss.get("timed_effects", {}).get("atk_buff", {})
		if not is_equal_approx(float(buff.get("value", 0)), 1.3): _fail(tag + ": real buff failed")
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	stage._sound.history.clear()
	var edge_samples:=0
	var observed := false
	var body_motion_seen := false
	var colored_pixels := -1
	var expected: Color = (Color("ef4847") if kind == "buff" else Color("71da87")) if kind in ["buff", "heal"] else Palette.color_for(attribute)
	var saved := false
	var record := ("--record-bite" in OS.get_cmdline_user_args() and mode == "test" and kind == "single" and attribute == "NEUTRAL" and not awakened and not counter) or "--bite-only" in OS.get_cmdline_user_args() or ("--review-only" in OS.get_cmdline_user_args() and mode == "test" and not counter)
	var frame_directory := tag + "_frames"
	if record: DirAccess.make_dir_recursive_absolute(output_dir.path_join(frame_directory))
	for frame in range(1100 if counter else 480):
		if frame == 8: view._present_batch([entry], before)
		var driver = stage._skill_presentation
		if is_instance_valid(driver):
			if not driver is Driver: _fail(tag + ": wrong driver")
			else:
				observed = true
				if driver.kind != kind or driver.action_kind != _expected_action(kind, awakened): _fail(tag + ": wrong action")
				if driver.form != ("awakened" if awakened else "normal"): _fail(tag + ": wrong form")
				if kind in ["single", "aoe"] and driver._vfx.attack_attribute != attribute: _fail(tag + ": wrong attribute input")
				if driver.action_kind in ["breath","focused_breath"] and driver.age>1.1 and driver.age<2.4 and frame%20==0:
					var beam: Dictionary=driver._vfx.beam_values()
					var transform: Transform2D=driver._vfx.get_global_transform_with_canvas()
					var a: Vector2=transform*beam.mouth
					var b: Vector2=transform*(beam.mouth+beam.dir*beam.span*beam.travel)
					if b.x>=0: _fail(tag+": beam ends before screen edge")
					var y: float=lerpf(a.y,b.y,(2-a.x)/(b.x-a.x))
					var pixel: Color=_tree().root.get_texture().get_image().get_pixel(2,clampi(int(y),0,719))
					if pixel.get_luminance()<.55: _fail(tag+": rendered beam missing at screen edge")
					edge_samples+=1
				if driver.action_kind=="focused_breath" and (driver._body.state.foot!=driver.motion.home or driver._body.state.scale!=Vector2.ONE or driver._shake!=Vector2.ZERO): _fail(tag+": breath recoil")
				var body_state: Dictionary = driver._body.state
				if body_state.get("scale", Vector2.ONE) != Vector2.ONE or int(body_state.get("pose", 0)) != 0: body_motion_seen = true
				if driver.age >= driver.impact_time and driver.age <= driver.impact_time + .4:
					colored_pixels = maxi(colored_pixels, _matching_pixels(_tree().root.get_texture().get_image(), expected))
					if not saved and mode == "test" and not counter and (attribute == "NEUTRAL" or kind in ["buff", "heal"]):
						_save(tag + "_impact")
						saved = true
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		if record and frame % 2 == 0:
			_tree().root.get_texture().get_image().save_png(output_dir.path_join(frame_directory + "/%04d.png" % (frame / 2)))
		if observed and not stage.is_playing() and not view._presenter.is_playing(): break
	var ranged_key: String=Driver.RANGED_SOUNDS.get(_expected_action(kind,awakened),"")
	if not ranged_key.is_empty():
		if stage._sound.history.count(ranged_key)!=1: _fail(tag+": dedicated SFX missing or duplicated")
		for key in stage._sound.history:
			if key.begins_with(attribute.to_lower()+"_") and not (counter and attribute=="WIND"): _fail(tag+": unwanted attribute SFX")
		if "boss_move_heavy" in stage._sound.history or "boss_impact_mass" in stage._sound.history: _fail(tag+": unwanted generic boss SFX")
	if _expected_action(kind,awakened) in ["breath","focused_breath"] and edge_samples==0: _fail(tag+": no screen edge samples")
	if not observed or colored_pixels < 4: _fail(tag + ": expected rendered VFX color not found")
	if not body_motion_seen: _fail(tag + ": body motion missing")
	if seen.size() != 1 or seen[0] != entry: _fail(tag + ": impact contract")
	_check_restored(tag, awakened)
	if view.session.battle.snapshot() != resolved: _fail(tag + ": simulation changed during playback")
	report.cases.append({"mode": mode, "kind": kind, "action": _expected_action(kind, awakened), "awakened": awakened, "attribute": attribute, "expected_color": expected.to_html(), "rendered_color_pixels": colored_pixels, "edge_samples":edge_samples,"dedicated_sfx":ranged_key,"audio_history":stage._sound.history.duplicate(),"counter_count": counters, "impact_events": seen.size(), "body_motion": body_motion_seen, "simulation_unchanged": view.session.battle.snapshot() == resolved})
	print("DRAGON_CASE ", tag, " pixels=", colored_pixels)
	await _close_view()

func _awakening_case(mode: String) -> void:
	var definition := _definition_for()
	definition.boss.hp = 400
	definition.boss.atk = 10
	definition.boss.awakening = {"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal_amount": 100}
	if not await _open_view(mode, definition): return
	for i in range(12):
		if view.session.pending_ally_id() == 0: break
		view.session.resolve_ally_action({"type": "defend"})
	var before: Dictionary = view.session.battle.presentation_state().duplicate(true)
	var entries: Array = view.session.resolve_ally_action({"type": "attack"})
	var entry: Dictionary = {}
	for e in entries:
		if str(e.get("action", "")) == "awakening": entry = e
	var tag := mode + "_awakening"
	if entry.is_empty():
		_fail(tag + ": real awakening missing")
		await _close_view()
		return
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	stage._sound.history.clear()
	var edge_samples:=0
	var observed := false
	var dark_saved := false
	var reveal_saved := false
	var record := "--review-only" in OS.get_cmdline_user_args()
	if record: DirAccess.make_dir_recursive_absolute(output_dir.path_join("awakening_frames"))
	for frame in range(480):
		if frame == 8: view._present_batch([entry], before)
		var driver = stage._skill_presentation
		if is_instance_valid(driver) and stage._phase == "awakening":
			observed = true
			if mode == "test" and driver.age >= 2.35 and not dark_saved:
				_save(tag + "_black_flame")
				dark_saved = true
			if mode == "test" and driver.age >= 3.35 and not reveal_saved:
				_save(tag + "_reveal")
				reveal_saved = true
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		if record and frame % 2 == 0:
			_tree().root.get_texture().get_image().save_png(output_dir.path_join("awakening_frames/%04d.png" % (frame / 2)))
		if observed and not stage.is_playing() and not view._presenter.is_playing(): break
	if not observed: _fail(tag + ": dedicated awakening never observed")
	if seen.size() != 1 or seen[0] != entry: _fail(tag + ": awakening impact contract")
	if not view.session.battle.is_awakened: _fail(tag + ": awakened state not persistent")
	_check_restored(tag, true)
	view.refresh()
	await _tree().process_frame
	if stage._asset_ids["boss"] != "dragon_awakened": _fail(tag + ": refresh lost awakened appearance")
	if view.session.battle.snapshot() != resolved: _fail(tag + ": simulation changed during playback")
	if mode == "test": _save(tag + "_persistent")
	report.cases.append({"mode": mode, "kind": "awakening", "impact_events": seen.size(), "is_awakened": view.session.battle.is_awakened, "asset": stage._asset_ids["boss"], "simulation_unchanged": view.session.battle.snapshot() == resolved})
	print("DRAGON_CASE ", tag)
	await _close_view()

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
	view.set_boss_appearance("appearance_dragon")
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_dragon")
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
