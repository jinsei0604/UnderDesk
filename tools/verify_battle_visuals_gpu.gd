extends SceneTree

## Production-stage GPU QA. No simulation/master/source files are modified.
## Run windowed with --fixed-fps 60 --resolution 1280x720 --audio-driver Dummy.
## User arguments: --output <directory> [--record-all]
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const Motions = preload("res://src/bossmaker/visuals/rbm_motion_catalog.gd")
var output_dir := "res://../gpu-final"
var record_all := false
var report: Dictionary = {"cases": [], "mode_regressions": [], "errors": []}
var view = null
var stage = null
var current_case: Dictionary = {}
var impact_pending := false
var event_counter := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--record-all": record_all = true
		if args[i] == "--output" and i + 1 < args.size(): output_dir = args[i + 1]
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.title = "Makers & Challengers — Motion verification"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	report["display"] = DisplayServer.get_name()
	report["viewport"] = [1280, 720]
	report["engine"] = Engine.get_version_info()
	report["record_all_frames"] = record_all
	report["evidence_scope"] = "Every rendered frame is audited; images are phase/impact/return captures unless --record-all is supplied. Motion cases replay presentation-only entries on a real production View. Mode regressions execute real session actions."
	if DisplayServer.get_name() == "headless":
		_fail("GPU verification refuses --headless")
		_save_report()
		quit(2)
		return
	var asset_coverage: Dictionary = {}
	for asset_id in Assets.ALLY_IDS + Assets.BOSS_IDS:
		asset_coverage[asset_id] = Assets.has_pose_frames(asset_id)
		if not asset_coverage[asset_id]: _fail("Missing pose frames: " + asset_id)
	report["asset_coverage"] = asset_coverage
	for character_id in Assets.ALLY_IDS:
		var definition := _definition_for(character_id)
		if not await _open_view("test", definition, "appearance_knight"):
			_save_report()
			quit(2)
			return
		var actor_id := _actor_id(character_id)
		await _capture(character_id + "_idle.png")
		await _motion_case(character_id + "_normal", {"actor": actor_id, "action": "attack", "target": "boss", "amount": 20})
		await _motion_case(character_id + "_defend", {"actor": actor_id, "action": "defend"})
		await _motion_case(character_id + "_received_hit", {"actor": "boss", "action": "attack", "target": actor_id, "amount": 20})
		for skill in _master(character_id).get("skills", []):
			var entry := _skill_entry(actor_id, skill)
			await _motion_case(str(skill["id"]), entry, skill)
			await _cancel_case(str(skill["id"]) + "_cancel", entry, skill)
		await _close_view()
	for boss_id in Assets.BOSS_IDS:
		if not await _open_view("test", _definition_for("hero"), "appearance_" + boss_id): break
		await _capture(boss_id + "_idle.png")
		await _motion_case(boss_id + "_normal", {"actor": "boss", "action": "attack", "target": 0, "amount": 20})
		await _motion_case(boss_id + "_single", {"actor": "boss", "action": "skill", "skill_id": "qa_single", "target": 0, "amount": 20}, {"effect": "damage", "target": "ally_random_single", "attribute": "ICE"})
		var hits: Dictionary = {}
		for unit in view.session.battle.party: hits[unit.id] = {"target": unit.id, "amount": 20}
		await _motion_case(boss_id + "_all", {"actor": "boss", "action": "skill", "skill_id": "qa_all", "hits": hits}, {"effect": "damage", "target": "ally_all", "attribute": "FIRE"})
		await _motion_case(boss_id + "_heal", {"actor": "boss", "action": "skill", "skill_id": "qa_heal", "target": "boss", "amount": 20}, {"effect": "self_heal", "target": "self"})
		await _motion_case(boss_id + "_buff", {"actor": "boss", "action": "skill", "skill_id": "qa_buff", "target": "boss"}, {"effect": "atk_self_buff", "attribute": "WIND"})
		await _motion_case(boss_id + "_received_hit", {"actor": 0, "action": "attack", "target": "boss", "amount": 20})
		await _close_view()
	for mode in ["test", "clear_check", "challenge"]:
		await _mode_regression(mode)
	report["case_count"] = report["cases"].size()
	report["passed"] = report["errors"].is_empty()
	_save_report()
	print("VISUAL_GPU_DONE passed=%s cases=%d output=%s" % [report["passed"], report["case_count"], ProjectSettings.globalize_path(output_dir)])
	quit(0 if report["passed"] else 1)

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
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge": view.setup(null)
	view.set_boss_appearance(appearance_id)
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, appearance_id)
	for i in range(8): await process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage", null)
	if stage == null or not stage.has_method("get_visual_audit"):
		_fail("Production View has no auditable visual stage: " + mode)
		return false
	var ticks := 0
	while view._presenter.is_playing() and ticks < 600:
		await process_frame
		ticks += 1
	stage.set_state(view.session.battle.presentation_state())
	stage.impact.connect(_on_impact)
	stage.finished.connect(_on_finished)
	return true

func _close_view() -> void:
	if is_instance_valid(view): view.queue_free()
	view = null
	stage = null
	await process_frame

func _actor_id(character_id: String) -> int:
	for unit in view.session.battle.party:
		if unit.character_id == character_id: return unit.id
	return -1

func _skill_entry(actor_id: int, skill: Dictionary) -> Dictionary:
	var entry: Dictionary = {"actor": actor_id, "action": "skill", "skill_id": skill["id"]}
	var other_id := 0 if actor_id != 0 else 1
	match str(skill.get("effect", "")):
		"damage": entry.merge({"target": "boss", "amount": 20})
		"heal":
			if skill.get("target", "") == "ally_all":
				var healed: Dictionary = {}
				for unit in view.session.battle.party: healed[unit.id] = 20
				entry["healed"] = healed
			else: entry.merge({"target": other_id, "amount": 20})
		"sp_recover_single_no_self": entry.merge({"target": other_id, "amount": 20})
		"sp_recover_all_no_self":
			var recovered: Dictionary = {}
			for unit in view.session.battle.party:
				if unit.id != actor_id: recovered[unit.id] = 20
			entry["recovered"] = recovered
		"guard_redirect": entry["protecting"] = other_id
	return entry

func _motion_case(id: String, entry: Dictionary, skill: Dictionary = {}) -> void:
	current_case = {"id": id, "kind": "motion", "entry": entry, "profile": Motions.profile(entry, skill), "events": [], "frames": [], "errors": []}
	var initial: Dictionary = stage.get_visual_audit()
	var simulation_before: Dictionary = view.session.battle.snapshot()
	impact_pending = false
	event_counter = 0
	stage.play_entry(entry, skill)
	var frame := 0
	var last_phase := ""
	while stage.is_playing() and frame < 360:
		await process_frame
		await RenderingServer.frame_post_draw
		var audit: Dictionary = stage.get_visual_audit()
		_check_audit(audit, initial, false)
		current_case["frames"].append({"frame": frame, "audit": _json_value(audit)})
		var phase := str(audit.get("phase", ""))
		if record_all or phase != last_phase or impact_pending:
			_save_image(id + "_%03d_%s.png" % [frame, "impact" if impact_pending else phase])
		impact_pending = false
		last_phase = phase
		frame += 1
	if stage.is_playing():
		_case_fail("Motion timeout")
		stage.cancel()
	await process_frame
	await RenderingServer.frame_post_draw
	_check_audit(stage.get_visual_audit(), initial, true)
	_save_image(id + "_return.png")
	var impacts := 0
	var finishes := 0
	for event in current_case["events"]:
		if event["type"] == "impact": impacts += 1
		if event["type"] == "finished": finishes += 1
	if impacts != 1 or finishes != 1: _case_fail("Expected one impact and one finished, got %d/%d" % [impacts, finishes])
	if simulation_before != view.session.battle.snapshot(): _case_fail("Stage modified simulation state")
	current_case["passed"] = current_case["errors"].is_empty()
	report["cases"].append(current_case)
	print("VISUAL_CASE " + id + " " + str(current_case["passed"]))
	current_case = {}

func _cancel_case(id: String, entry: Dictionary, skill: Dictionary) -> void:
	current_case = {"id": id, "kind": "cancel", "events": [], "frames": [], "errors": []}
	var initial: Dictionary = stage.get_visual_audit()
	stage.play_entry(entry, skill)
	for i in range(5): await process_frame
	stage.cancel()
	var event_count: int = current_case["events"].size()
	for i in range(75):
		await process_frame
		_check_audit(stage.get_visual_audit(), initial, true)
	if event_count != current_case["events"].size(): _case_fail("Cancelled motion emitted late signals")
	current_case["passed"] = current_case["errors"].is_empty()
	report["cases"].append(current_case)
	current_case = {}

func _check_audit(audit: Dictionary, initial: Dictionary, returned: bool) -> void:
	for actor_id in audit.get("actors", {}):
		var actor: Dictionary = audit["actors"][actor_id]
		var original: Dictionary = initial["actors"].get(actor_id, {})
		if original.is_empty(): continue
		if not Vector2(actor["position"]).is_finite(): _case_fail("Nonfinite actor position: " + actor_id)
		if not Vector2(actor["scale"]).is_equal_approx(original["scale"]): _case_fail("Actor scale changed: " + actor_id)
		if actor.has("visible_rect"):
			var bounds: Rect2 = actor["visible_rect"]
			var arena := Rect2(Vector2(-1, -1), Vector2(audit["stage_size"]) + Vector2(2, 2))
			if bounds.has_area() and not arena.encloses(bounds): _case_fail("Sprite clipped by battlefield: " + actor_id)
		if returned:
			if Vector2(actor["position"]).distance_to(original["home"]) > 0.5: _case_fail("Actor failed to return: " + actor_id)
			if Vector2(actor["feet"]).distance_to(original["feet"]) > 0.5: _case_fail("Foot anchor drift: " + actor_id)
	if returned and (audit.get("playing", true) or int(audit.get("effects_count", -1)) != 0): _case_fail("Animation/effects remained after return")

func _mode_regression(mode: String) -> void:
	if not await _open_view(mode, _definition_for("hero"), "appearance_dragon"): return
	var result: Dictionary = {"mode": mode, "errors": []}
	var definition: Dictionary = view.session._definition
	var shadow = RBMChallengeSession.new(definition, view.session._seed) if mode == "challenge" else RBMCreatorTestSession.new(definition, view.session._seed)
	var unit_id: int = view.session.pending_ally_id()
	await _capture(mode + "_command_before.png")
	shadow.resolve_ally_action({"type": "attack"})
	view.act_attack(unit_id)
	var once: Dictionary = view.session.battle.snapshot()
	view.act_attack(unit_id)
	if once != view.session.battle.snapshot(): result["errors"].append("Repeated input advanced simulation during playback")
	var ticks := 0
	while view._presenter.is_playing() and ticks < 900:
		await process_frame
		await RenderingServer.frame_post_draw
		if ticks % 15 == 0: _save_image(mode + "_command_%03d.png" % ticks)
		ticks += 1
	if view._presenter.is_playing(): result["errors"].append("Presenter failed to finish")
	if view.session.battle.snapshot() != shadow.battle.snapshot(): result["errors"].append("Animated session outcome differs from same-seed synchronous session")
	await _capture(mode + "_command_return.png")
	var overflow: Array = []
	for name in ["CommandArea", "PartyRows", "Battlefield"]:
		var control := view.find_child(name, true, false) as Control
		if control != null:
			var rect := control.get_global_rect()
			if rect.end.y > 720.5 or rect.end.x > 1280.5: overflow.append({"node": name, "rect": _json_value(rect)})
	result["ui_overflow"] = overflow
	if not overflow.is_empty(): result["errors"].append("Battle UI extends beyond viewport")
	result["passed"] = result["errors"].is_empty()
	for error in result["errors"]: _fail(mode + ": " + str(error))
	report["mode_regressions"].append(result)
	await _close_view()

func _on_impact(_entry: Dictionary) -> void:
	impact_pending = true
	if not current_case.is_empty():
		current_case["events"].append({"type": "impact", "order": event_counter, "audit": _json_value(stage.get_visual_audit())})
		event_counter += 1

func _on_finished() -> void:
	if not current_case.is_empty():
		current_case["events"].append({"type": "finished", "order": event_counter})
		event_counter += 1

func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_save_image(filename)

func _save_image(filename: String) -> void:
	var screenshot := root.get_texture().get_image()
	var error := screenshot.save_png(output_dir.path_join(filename))
	if error != OK: _fail("PNG write failed: " + filename)

func _case_fail(message: String) -> void:
	if not current_case["errors"].has(message):
		current_case["errors"].append(message)
		_fail(str(current_case["id"]) + ": " + message)

func _fail(message: String) -> void:
	if not report["errors"].has(message): report["errors"].append(message)
	push_error(message)

func _json_value(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Rect2: return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_json_value(item))
		return result
	return value

func _save_report() -> void:
	var file := FileAccess.open(output_dir.path_join("visual-gpu-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_json_value(report), "\t"))
		file.close()
