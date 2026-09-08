extends "res://tools/verify_battle_visuals_gpu.gd"

## Runs actual master skills through sessions, then plays the returned real logs.
## Damage/SP setup below belongs to isolated QA instances, never production data.
const EXPECTED_REAL_CASES := 56
const EXPECTED_SPECIAL_CASES := 6
var last_record: Dictionary = {}

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	report = {"cases": [], "errors": [], "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "viewport": [1280, 720], "scope": "Actual existing master skills resolved by production sessions. QA-only injured/depleted units make healing visible. Same-snapshot shadow sessions verify identical damage, SP, turn state and RNG."}
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	for character_id in Assets.ALLY_IDS:
		for skill in _master(character_id).get("skills", []):
			var definition := _definition_for(character_id)
			definition["boss"]["hp"] = 100000
			definition["boss"]["atk"] = 20
			definition["boss"]["spd"] = 1
			await _open_view("test", definition, "appearance_knight")
			var actor_id := _actor_id(character_id)
			var setup_steps := 0
			while view.session.pending_ally_id() != actor_id and setup_steps < 8:
				view.session.resolve_ally_action({"type": "defend"})
				setup_steps += 1
			for unit in view.session.battle.party:
				unit.hp = maxi(1, unit.max_hp - 200)
				if unit.id != actor_id: unit.sp = maxi(0, unit.max_sp - 60)
			view.refresh()
			var target_id := 0 if actor_id != 0 else 1
			await _real_action(str(skill["id"]), {"type": "skill", "skill_id": skill["id"], "target_id": target_id})
			await _close_view()
	# Existing boss skill definitions, projected onto each selectable appearance.
	var definition_b: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_b.json")
	var all_boss_skills: Array = definition_b["boss"]["skills"].duplicate(true)
	all_boss_skills.append(_definition_for("hero")["boss"]["skills"][0])
	for boss_id in Assets.BOSS_IDS:
		for skill in all_boss_skills:
			var definition := _definition_for("hero")
			definition["boss"]["skills"] = [skill]
			definition["boss"]["normal_actions"] = [{"skill_id": skill["skill_id"], "weight": 1}]
			definition["boss"]["spd"] = 1
			await _open_view("test", definition, "appearance_" + boss_id)
			view.session.battle.boss.hp -= 500
			for i in range(3): view.session.resolve_ally_action({"type": "defend"})
			view.refresh()
			await _real_action(boss_id + "_real_" + str(skill["skill_id"]), {"type": "defend"})
			_verify_boss_result(last_record, skill, boss_id)
			await _close_view()
	await _counter_and_cover()
	_validate_counts(EXPECTED_REAL_CASES)
	var boss_cases := 0
	for item in report["cases"]:
		if item.has("expected_boss_skill_id"): boss_cases += 1
	var coverage := {"id": "boss_coverage", "assertions": []}
	_check(coverage, "30 boss skill/appearance combinations verified", boss_cases == 30, {"actual": boss_cases})
	report["boss_coverage"] = coverage
	report["passed"] = report["errors"].is_empty()
	report["case_count"] = report["cases"].size()
	report["case_breakdown"] = {"ally_skills": 20, "boss_skills": 30, "special_skills_included": 6}
	_save_report()
	print("REAL_SKILLS_GPU_DONE passed=%s cases=%d" % [report["passed"], report["case_count"]])
	quit(0 if report["passed"] else 1)

func _real_action(id: String, action: Dictionary) -> void:
	var before_sim: Dictionary = view.session.battle.snapshot()
	var before: Dictionary = view.session.battle.presentation_state()
	var shadow := RBMCreatorTestSession.new(view.session._definition, view.session._seed)
	shadow.battle.restore(before_sim)
	var expected := shadow.resolve_ally_action(action)
	var actual: Array = view.session.resolve_ally_action(action)
	if actual != expected or view.session.battle.snapshot() != shadow.battle.snapshot(): _fail(id + ": synchronous result/RNG mismatch")
	var failed := false
	for entry in actual:
		if bool(entry.get("failed", false)): failed = true
	if failed: _fail(id + ": actual skill failed")
	var immutable_final: Dictionary = view.session.battle.snapshot()
	var impact_events: Array = []
	var collect_impact := func(entry: Dictionary): impact_events.append(entry.duplicate(true))
	stage.impact.connect(collect_impact)
	view._present_batch(actual, before)
	var frames := 0
	var phases: Dictionary = {}
	while view._presenter.is_playing() and frames < 1200:
		await process_frame
		await RenderingServer.frame_post_draw
		var state: Dictionary = view._presenter.display_state()
		for key in state.get("party", {}):
			var unit: Dictionary = state["party"][key]
			var hp_bar := view.find_child("PartyRowHPBar_%s" % key, true, false) as ProgressBar
			var sp_bar := view.find_child("PartyRowSPBar_%s" % key, true, false) as ProgressBar
			if hp_bar != null and int(hp_bar.value) != int(unit["hp"]): _fail(id + ": HP HUD not synchronized with impact")
			if sp_bar != null and int(sp_bar.value) != int(unit["sp"]): _fail(id + ": SP HUD not synchronized with impact")
		var phase: String = stage.get_visual_audit()["phase"]
		if not phases.has(phase) or frames % 20 == 0:
			_save_image(id + "_%03d_%s.png" % [frames, phase])
		phases[phase] = true
		frames += 1
	if frames >= 1200: _fail(id + ": playback timeout")
	if immutable_final != view.session.battle.snapshot(): _fail(id + ": playback changed simulation")
	await _capture(id + "_return.png")
	stage.impact.disconnect(collect_impact)
	last_record = {"id": id, "actual_entries": actual, "before_state": before, "after_state": view.session.battle.presentation_state(), "impact_events": impact_events, "frames": frames, "phases": phases.keys(), "same_seed_state_equal": immutable_final == shadow.battle.snapshot(), "skill_succeeded": not failed, "assertions": []}
	_check(last_record, "production logs nonempty", not actual.is_empty())
	_check(last_record, "all resolved actions emitted matching impact events", impact_events == actual)
	if action.get("type") == "skill":
		var found := false
		for entry in actual:
			if str(entry.get("actor")) != "boss" and entry.get("skill_id") == action.get("skill_id"): found = true
		_check(last_record, "requested ally skill exists in production log", found)
	report["cases"].append(last_record)
	print("REAL_SKILL_CASE " + id)

func _counter_and_cover() -> void:
	var definition := _definition_for("samurai")
	definition["party"] = [definition["party"][3]]
	definition["boss"]["spd"] = 1
	definition["boss"]["hp"] = 100000
	await _open_view("test", definition, "appearance_wolf")
	var rewind_snapshot: Dictionary = view.session.battle.snapshot().duplicate(true)
	var rewind_presentation: Dictionary = view.session.battle.presentation_state().duplicate(true)
	var rewind_stage_state: Dictionary = stage._state.duplicate(true)
	var rewind_visual: Dictionary = stage.get_visual_audit().duplicate(true)
	var rewind_hud := _hud_state()
	await _real_action("samurai_real_iai_then_hit", {"type": "skill", "skill_id": "samurai_iai"})
	await _real_action("samurai_real_counter_reflect", {"type": "skill", "skill_id": "samurai_counter"})
	_verify_counter(last_record, 0, false)
	var rewind_check := {"id": "rewind", "assertions": []}
	_check(rewind_check, "state actually changed before REWIND", view.session.battle.snapshot() != rewind_snapshot)
	view.rewind_to(1)
	var rewind_frames := 0
	while view._presenter.is_playing() and rewind_frames < 1200:
		await process_frame
		rewind_frames += 1
	await _capture("samurai_rewind_restored.png")
	_check(rewind_check, "full snapshot restored including HP/SP status turn cursor and RNG", view.session.battle.snapshot() == rewind_snapshot)
	_check(rewind_check, "full presentation state restored", view.session.battle.presentation_state() == rewind_presentation)
	_check(rewind_check, "rendered stage state restored", stage._state == rewind_stage_state)
	_check(rewind_check, "visual actors poses anchors and effects restored", stage.get_visual_audit() == rewind_visual)
	_check(rewind_check, "HP/SP HUD and turn label restored", _hud_state() == rewind_hud)
	_check(rewind_check, "playback finished after REWIND", not view._presenter.is_playing())
	_check(rewind_check, "future log history removed", view._battle_log_history.is_empty())
	rewind_check["expected_snapshot"] = rewind_snapshot
	rewind_check["actual_snapshot"] = view.session.battle.snapshot()
	rewind_check["expected_presentation"] = rewind_presentation
	rewind_check["actual_presentation"] = view.session.battle.presentation_state()
	report["rewind_validation"] = rewind_check
	await _close_view()
	definition = _definition_for("hero")
	definition["party"] = [definition["party"][3], definition["party"][0]]
	definition["boss"]["spd"] = 1
	var cover_seed := 1
	for candidate in range(1, 100):
		var probe := RBMCreatorTestSession.new(definition, candidate)
		probe.resolve_ally_action({"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1})
		var entries := probe.resolve_ally_action({"type": "defend"})
		if int(entries[-1].get("visual_original_target", -1)) == 1:
			cover_seed = candidate
			break
	await _open_view("test", definition, "appearance_golem")
	view.start(definition, cover_seed)
	await process_frame
	await _real_action("tank_real_guard_swap", {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1})
	await _real_action("tank_real_redirected_hit", {"type": "defend"})
	var covered: Dictionary = report["cases"][-1]["actual_entries"][-1]
	_check(last_record, "cover target differs from original target", covered.get("target") != covered.get("visual_original_target"))
	_check(last_record, "original target is protected hero", int(covered.get("visual_original_target", -1)) == 1)
	_check(last_record, "actual recipient is tank", int(covered.get("target", -1)) == 0)
	var cover_before: Dictionary = last_record["before_state"]
	var cover_after: Dictionary = covered.get("visual_state", {})
	_check(last_record, "tank was protecting hero before hit", int(cover_before["party"]["0"]["protecting_ally_id"]) == 1)
	_check(last_record, "tank HP loss equals positive redirected damage", int(covered.get("amount", 0)) > 0 and _hp(cover_before, "0") - _hp(cover_after, "0") == int(covered.get("amount", -1)))
	_check(last_record, "protected hero HP unchanged", _hp(cover_before, "1") == _hp(cover_after, "1"))
	await _close_view()
	# A real AoE both damages the other ally and triggers only the samurai's counter.
	definition = _definition_for("samurai")
	definition["party"] = [definition["party"][0], definition["party"][3]]
	definition["boss"]["spd"] = 1
	definition["boss"]["hp"] = 100000
	var source: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_b.json")
	definition["boss"]["skills"] = [source["boss"]["skills"][3]]
	definition["boss"]["normal_actions"] = [{"skill_id": "sentinel_frost_nova", "weight": 1}]
	await _open_view("test", definition, "appearance_dragon")
	await _real_action("aoe_counter_prepare", {"type": "defend"})
	await _real_action("samurai_real_aoe_counter", {"type": "skill", "skill_id": "samurai_counter"})
	_verify_counter(last_record, 1, true)
	await _close_view()

## Explicit nonfatal assertions: preserve all failures in JSON and exit nonzero.
## Unlike language assert(), these checks cannot disappear in release builds.
func _check(record: Dictionary, label: String, condition: bool, evidence: Dictionary = {}) -> void:
	if not record.has("assertions"): record["assertions"] = []
	record["assertions"].append({"name": label, "passed": condition, "evidence": evidence})
	if not condition: _fail(str(record.get("id", "validation")) + ": " + label)

func _validate_counts(expected: int) -> void:
	var counts := {"id": "case_counts", "assertions": []}
	var unique: Dictionary = {}
	for item in report["cases"]: unique[item["id"]] = true
	_check(counts, "executed case count equals expected", report["cases"].size() == expected, {"expected": expected, "actual": report["cases"].size()})
	_check(counts, "case IDs are unique", unique.size() == expected)
	report["count_validation"] = counts
	report["expected_case_count"] = expected

func _hp(state: Dictionary, key: String) -> int:
	return int(state.get("boss", {}).get("hp", -1)) if key == "boss" else int(state.get("party", {}).get(key, {}).get("hp", -1))

func _state_before_entry(record: Dictionary, index: int) -> Dictionary:
	return record["before_state"] if index == 0 else record["actual_entries"][index - 1].get("visual_state", {})

func _boss_entry_index(record: Dictionary, skill_id: String = "") -> int:
	for index in range(record["actual_entries"].size()):
		var entry: Dictionary = record["actual_entries"][index]
		if str(entry.get("actor")) == "boss" and (skill_id.is_empty() or entry.get("skill_id") == skill_id): return index
	return -1

func _verify_counter(record: Dictionary, samurai_id: int, aoe: bool) -> void:
	var key := str(samurai_id)
	var index := _boss_entry_index(record)
	_check(record, "enemy attack exists in production log", index >= 0)
	if index < 0: return
	var entry: Dictionary = record["actual_entries"][index]
	var before := _state_before_entry(record, index)
	var after: Dictionary = entry.get("visual_state", {})
	_check(record, "samurai counter waiting state established", bool(before.get("party", {}).get(key, {}).get("counter_pending", false)))
	var hit := entry
	var counters: Array[int] = []
	if aoe:
		var hits: Dictionary = entry.get("hits", {})
		_check(record, "AoE hit multiple allies", hits.size() >= 2 and hits.size() == before["party"].size())
		hit = {}
		var other_damaged := 0
		for value in hits.values():
			var target := int(value.get("target", -1))
			if bool(value.get("counter", false)): counters.append(target)
			if target == samurai_id:
				hit = value
			else:
				var amount := int(value.get("amount", 0))
				var hp_loss := _hp(before, str(target)) - _hp(after, str(target))
				_check(record, "other ally %d took normal damage" % target, amount > 0 and hp_loss == amount, {"amount": amount, "hp_loss": hp_loss})
				_check(record, "other ally %d did not counter or reflect" % target, not bool(value.get("counter", false)) and int(value.get("reflected", 0)) == 0)
				if amount > 0 and hp_loss == amount: other_damaged += 1
		_check(record, "at least one nonsamurai ally damaged", other_damaged >= 1)
		_check(record, "only samurai triggered AoE counter", counters.size() == 1 and counters[0] == samurai_id, {"counter_actor_ids": counters})
	_check(record, "enemy attack targeted samurai", int(hit.get("target", -1)) == samurai_id)
	_check(record, "counter and block flags emitted", bool(hit.get("counter", false)) and bool(hit.get("blocked", false)))
	_check(record, "production counter entry emitted at visual impact", record["impact_events"].has(entry))
	var reflected := int(hit.get("reflected", 0))
	var boss_loss := _hp(before, "boss") - _hp(after, "boss")
	_check(record, "counter caused matching positive boss HP loss", reflected > 0 and boss_loss == reflected, {"reflected": reflected, "boss_hp_loss": boss_loss})
	_check(record, "blocked samurai received zero damage", int(hit.get("amount", -1)) == 0 and _hp(before, key) == _hp(after, key))
	_check(record, "counter waiting consumed after hit", not bool(after.get("party", {}).get(key, {}).get("counter_pending", true)))

func _verify_boss_result(record: Dictionary, skill: Dictionary, appearance: String) -> void:
	var skill_id := str(skill["skill_id"])
	record["expected_boss_skill_id"] = skill_id
	record["appearance"] = appearance
	var index := _boss_entry_index(record, skill_id)
	_check(record, "expected boss skill_id exists in production log", index >= 0, {"expected_skill_id": skill_id, "appearance": appearance})
	if index < 0: return
	var entry: Dictionary = record["actual_entries"][index]
	var before := _state_before_entry(record, index)
	var after: Dictionary = entry.get("visual_state", {})
	var resolved := RBMBattleUiKit.find_skill_for_actor("boss", skill_id, view.session.battle)
	var kind := str(skill["type"])
	var expected_effect := "damage" if kind == "attack" else ("heal" if kind == "self_heal" else "buff_atk_self")
	_check(record, "resolved effect matches expected boss type", resolved.get("effect") == expected_effect, {"effect": resolved.get("effect"), "expected": expected_effect})
	_check(record, "boss skill has matching visual impact event", record["impact_events"].has(entry))
	match kind:
		"attack":
			if str(skill.get("target", "single")) == "all":
				var hits: Dictionary = entry.get("hits", {})
				_check(record, "all attack hit every living party member", hits.size() == before["party"].size() and hits.size() > 1)
				for hit in hits.values():
					var key := str(hit.get("target", -1))
					_check(record, "AoE target " + key + " HP loss matches positive damage", before["party"].has(key) and int(hit.get("amount", 0)) > 0 and _hp(before, key) - _hp(after, key) == int(hit.get("amount", -1)))
			else:
				var key := str(entry.get("target", -1))
				_check(record, "single attack targets one party member", before["party"].has(key) and not entry.has("hits"))
				_check(record, "single target HP loss matches positive damage", int(entry.get("amount", 0)) > 0 and _hp(before, key) - _hp(after, key) == int(entry.get("amount", -1)))
				for other in before["party"]:
					if other != key: _check(record, "nontarget " + other + " HP unchanged", _hp(before, other) == _hp(after, other))
		"self_heal":
			var amount := int(entry.get("amount", 0))
			var expected_amount := mini(int(skill["heal_amount"]), int(before["boss"]["max_hp"]) - _hp(before, "boss"))
			_check(record, "self heal restored expected positive boss HP", amount > 0 and amount == expected_amount and _hp(after, "boss") - _hp(before, "boss") == amount, {"amount": amount, "expected": expected_amount})
			for key in before["party"]: _check(record, "boss self heal leaves ally " + key + " HP unchanged", _hp(before, key) == _hp(after, key))
		"atk_self_buff":
			var buff: Dictionary = after.get("boss", {}).get("timed_effects", {}).get("atk_buff", {})
			_check(record, "boss ATK buff has expected multiplier", is_equal_approx(float(buff.get("value", -1)), float(skill["buff_multiplier"])))
			_check(record, "boss ATK buff has expected duration and turn", int(buff.get("duration_turns", -1)) == int(skill["duration_turns"]) and int(buff.get("applied_at_turn", -1)) == int(entry["turn"]))
			_check(record, "self buff does not damage or heal boss", _hp(before, "boss") == _hp(after, "boss"))

func _hud_state() -> Dictionary:
	var state := {"units": {}, "boss_label": view.find_child("BossLabel", true, false).text}
	for unit in view.session.battle.party:
		var key := str(unit.id)
		var hp := view.find_child("PartyRowHPBar_" + key, true, false) as ProgressBar
		var sp := view.find_child("PartyRowSPBar_" + key, true, false) as ProgressBar
		state["units"][key] = {"hp": hp.value if hp != null else -1, "sp": sp.value if sp != null else -1}
	return state
