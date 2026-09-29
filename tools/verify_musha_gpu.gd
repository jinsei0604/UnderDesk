extends RefCounted
## 朽ちた機械武者の専用演出の実GPU検証(標準の本番GPU runner経由)。
##   Godot_v4.7-stable_win64.exe --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/verify_musha_gpu.gd --output=<dir>
## 本番のTEST BATTLE/CLEAR CHECK/CHALLENGEの実戦闘でボス(appearance_musha)の
## 単体・全体・自己強化・自己回復を再生し、①正しい専用演出が選ばれる ②実際に
## 属性色が描かれる ③impactが確定エントリで1回だけ ④汎用SEが重ならない
## ⑤終了後に本体/位置/演出が元へ戻る ⑥シミュレーションが変化しない、を確認する。
const Driver = preload("res://src/bossmaker/visuals/rbm_musha_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const SHOT_TIMES := {
	"single": [0.9, 1.5, 2.4, 2.9, 3.6],
	"aoe": [1.2, 1.6, 3.0, 4.3, 5.1],
	"buff": [1.5, 2.5],
	"heal": [1.5, 2.5],
}
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
		print("MUSHA_FAIL ", message)

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	_tree_override = tree
	output_dir = directory
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	await _run()
	if report.has("passed") and report.has("case_count"): _gpu_verification_completed = true
	return 0 if report.get("passed", false) else 1

func _run() -> void:
	_tree().root.size = Vector2i(1280, 720)
	_tree().root.content_scale_size = Vector2i(1280, 720)
	_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name() == "headless": return
	for attribute in Palette.COLORS:
		for kind in ["single", "aoe"]: await _case("test", kind, attribute)
	for kind in ["buff", "heal"]: await _case("test", kind, "ICE" if kind == "buff" else "FIRE")
	for mode in ["clear_check", "challenge"]:
		for kind in ["single", "aoe"]: await _case(mode, kind, "NEUTRAL")
	await _case("test", "single", "WIND", true)
	await _case("test", "aoe", "NEUTRAL", true)
	report["case_count"] = report.cases.size()
	report["passed"] = report.errors.is_empty()
	FileAccess.open(output_dir.path_join("musha-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MUSHA_GPU_DONE passed=", report.passed, " cases=", report.case_count)

func _matching_pixels(img: Image, expected: Color, tolerance: float = .10) -> int:
	if img == null: return 0
	var count := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a >= .12 and absf(c.r - expected.r) < tolerance and absf(c.g - expected.g) < tolerance and absf(c.b - expected.b) < tolerance: count += 1
	return count

func _save(tag: String) -> void:
	var img := _tree().root.get_texture().get_image()
	if img == null: _fail(tag + ": no GPU image")
	else: img.save_png(output_dir.path_join(tag + ".png"))

## 純色に近い描画(初撃の交差閃光・追撃の斬撃線・強化回復の火花/リング)が出ている区間。
func _in_sample_window(kind: String, age: float) -> bool:
	match kind:
		"single": return age >= 1.34 and age <= 1.50
		"aoe": return (age >= 1.52 and age <= 1.68) or (age >= 3.0 and age <= 3.2)
		_: return age >= 1.20 and age <= 2.60  # 火花・リングは小さく半透明なので区間を広く取る

func _expected_action(kind: String) -> String:
	return "single" if kind == "single" else ("all" if kind == "aoe" else kind)

func _check_restored(tag: String) -> void:
	if not stage._visuals["boss"].visible: _fail(tag + ": boss visibility not restored")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag + ": presentation cleanup")
	if stage._asset_ids["boss"] != "musha": _fail(tag + ": wrong boss asset " + str(stage._asset_ids["boss"]))
	for key in stage._homes:
		if stage._visuals[key].position != stage._homes[key]: _fail(tag + ": position not restored: " + key)

func _case(mode: String, kind: String, attribute: String, counter: bool = false) -> void:
	var definition := _definition_for()
	if counter and kind == "single": definition.party = [definition.party[3]]
	var spec := {"skill_id": "boss_claw", "name": "Musha QA " + kind, "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"skill_id": "boss_claw", "name": "Musha tune", "type": "atk_self_buff" if kind == "buff" else "self_heal", "buff_multiplier": 1.3, "duration_turns": 3, "heal_amount": 200, "attribute": attribute}
	definition.boss.skills = [spec]
	definition.boss.atk = 40
	definition.boss.spd = 1
	if not await _open_view(mode, definition): return
	view.session.battle.boss.hp = 1000
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
	var tag := mode + "_" + kind + "_" + attribute + ("_counter" if counter else "")
	if entry.is_empty():
		_fail(tag + ": no production entry")
		await _close_view()
		return
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	var counters := int(entry.get("counter", false))
	for hit in entry.get("hits", {}).values(): counters += int(hit.get("counter", false))
	if counter and counters != 1: _fail(tag + ": real counter missing")
	if kind == "aoe" and entry.get("hits", {}).size() != 4: _fail(tag + ": expected four targets")
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	stage._sound.history.clear()
	var observed := false
	var body_motion_seen := false
	var colored_pixels := -1
	var expected: Color = (Color("ef4847") if kind == "buff" else Color("71da87")) if kind in ["buff", "heal"] else Palette.color_for(attribute)
	var shots: Array = SHOT_TIMES[kind].duplicate()
	var take_shots := mode == "test" and not counter and (attribute == "NEUTRAL" or kind in ["buff", "heal"] or (kind == "single" and attribute == "WIND"))
	var strike_time := 0.0
	for frame in range(1400 if counter else 700):
		if frame == 8: view._present_batch([entry], before)
		var driver = stage._skill_presentation
		if is_instance_valid(driver):
			if not driver is Driver: _fail(tag + ": wrong driver")
			else:
				observed = true
				strike_time = driver.impact_time
				if driver.action_kind != _expected_action(kind): _fail(tag + ": wrong action " + driver.action_kind)
				if kind in ["single", "aoe"] and driver._attribute != attribute: _fail(tag + ": wrong attribute input")
				# 本体が動いた: 元の本体は姿勢番号(pose)、コマ送りの本体(2026-09-27承認)はコマ名(fr)が待機の絵から変わる
				var body_state: Dictionary = driver._body._state
				if int(body_state.get("pose", -1)) != -1 or (body_state.has("fr") and not str(body_state.fr) in ["idle", "a3"]): body_motion_seen = true
				if _in_sample_window(kind, driver.age):
					colored_pixels = maxi(colored_pixels, _matching_pixels(_tree().root.get_texture().get_image(), expected, .22 if kind in ["buff", "heal"] else .10))
				if take_shots and not shots.is_empty() and driver.age >= float(shots[0]):
					_save(tag + "_t%03d" % int(float(shots[0]) * 100.0))
					shots.pop_front()
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		if observed and not stage.is_playing() and not view._presenter.is_playing(): break
	if not observed or colored_pixels < (2 if kind in ["buff", "heal"] else 4): _fail(tag + ": expected rendered VFX color not found (%d)" % colored_pixels)
	if not body_motion_seen: _fail(tag + ": body motion missing")
	if seen.size() != 1 or seen[0] != entry: _fail(tag + ": impact contract (%d events)" % seen.size())
	var audio: Array = stage._sound.history.duplicate()
	var track: String = {"single": "musha_single", "aoe": "musha_aoe", "buff": "musha_buff", "heal": "musha_heal"}[kind]
	if audio.count(track) != 1: _fail(tag + ": completed track must play exactly once: " + str(audio))
	for key in audio:
		if counter: break  # 反撃時は侍自身の反撃演出のSEが正当に鳴る
		if str(key).ends_with("_cast") or str(key).ends_with("_release") or str(key).begins_with("boss_impact") or str(key).contains("impact") or str(key).ends_with("_burst") or str(key).ends_with("_end"):
			_fail(tag + ": generic SE layered over the completed track: " + str(key))
	_check_restored(tag)
	if view.session.battle.snapshot() != resolved: _fail(tag + ": simulation changed during playback")
	report.cases.append({"mode": mode, "kind": kind, "attribute": attribute, "expected_color": expected.to_html(), "rendered_color_pixels": colored_pixels, "audio_history": audio, "counter_count": counters, "impact_events": seen.size(), "body_motion": body_motion_seen, "strike_time": strike_time, "simulation_unchanged": view.session.battle.snapshot() == resolved})
	print("MUSHA_CASE ", tag, " pixels=", colored_pixels, " audio=", audio)
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
	view.set_boss_appearance("appearance_musha")
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_musha")
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
