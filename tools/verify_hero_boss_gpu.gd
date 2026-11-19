extends RefCounted
## ヒーロー（hero_boss）の実GPUの確認。本番の画面（TEST・クリアチェック・挑戦）、presenter、決まった戦闘の行動、実際の描画で確かめる。
## 起動: godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_hero_boss_gpu.gd --output=<dir> [--perf] [--1080] [--capture] [--selection-only] [--defeat-only] [--awakened-defeat] [--english]
## --perf は実時間（録画モードなし）で、同じ起動で同じ技を2回ずつ測る。--capture は確認動画用（--write-movie と一緒に使う）。
## --intro-only・--new-only（2026-11-17）: 登場だけ／登場・支援（覚醒前後×回復・強化）・撃破（覚醒前後）だけ。--perf・--capture と組み合わせられる。
const Driver = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_presentation.gd")
const Victory = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
var _gpu_verification_completed := false
var _tree_override: SceneTree
var output_dir: String
var report: Dictionary = {"cases": [], "errors": []}
var view = null
var stage = null
var audio_peak_db := -120.0

func _tree() -> SceneTree:
	return _tree_override

func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args()

func _fail(message: String) -> void:
	if not report.errors.has(message):
		report.errors.append(message)
		push_error(message)

func _save(tag: String) -> void:
	if "--perf" in _args() or "--capture" in _args():
		return
	_tree().root.get_texture().get_image().save_png(output_dir.path_join(tag + ".png"))

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	_tree_override = tree
	output_dir = directory
	tree.root.mode = Window.MODE_WINDOWED
	tree.root.size = Vector2i(1280, 720)
	if "--1080" in _args():
		tree.root.mode = Window.MODE_FULLSCREEN
		tree.root.size = Vector2i(1920, 1080)
	tree.root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(directory)
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	report.requested_size = [1920, 1080] if "--1080" in _args() else [1280, 720]
	# 重いコマの CPU・GPU の内訳（2026-11-17。描画の時間を測る設定を入れる）
	RenderingServer.viewport_set_measure_render_time(tree.root.get_viewport_rid(), true)
	var original_locale := RBMLocale.current_locale()
	tree.process_frame.connect(_observe_audio)
	await _run()
	tree.process_frame.disconnect(_observe_audio)
	if RBMLocale.current_locale() != original_locale:
		RBMLocale.set_locale(original_locale)
	if report.cases.size() != _expected_case_count():
		_fail("Verification stopped early: expected %d cases, got %d" % [_expected_case_count(), report.cases.size()])
	report.audio_peak_db = audio_peak_db
	if audio_peak_db > -0.1:
		_fail("Master output approaches clipping: %.2f dB" % audio_peak_db)
	report.actual_size = [tree.root.size.x, tree.root.size.y]
	report.passed = report.errors.is_empty()
	report.case_count = report.cases.size()
	FileAccess.open(directory.path_join("hero-boss-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	_gpu_verification_completed = true
	print("HERO_BOSS_GPU_DONE ", report.passed, " cases=", report.case_count, " peak_db=", audio_peak_db)
	return 0 if report.passed else 1

## 確認動画を切り出すための印（--write-movie の何コマ目か）
func _mark(tag: String, what: String) -> void:
	if "--capture" in _args():
		print("HERO_BOSS_MARK ", tag, " ", what, " ", Engine.get_frames_drawn())

func _observe_audio() -> void:
	audio_peak_db = maxf(audio_peak_db, maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0)))

func _run() -> void:
	if "--intro-only" in _args():
		for repetition in (2 if "--perf" in _args() else 1):
			await _intro()
		return
	if "--new-only" in _args():
		for repetition in (2 if "--perf" in _args() else 1):
			await _intro()
			for aw in [false, true]:
				for mode in ["heal", "buff"]:
					await _support(mode, aw)
			await _defeat(false)
			await _defeat(true)
		return
	if "--selection-only" in _args():
		await _selection()
		return
	if "--defeat-only" in _args():
		await _defeat(false)
		await _defeat(true)
		return
	if "--awakened-defeat" in _args():
		await _defeat(true)
		if "--perf" in _args():
			await _defeat(true)
		return
	if "--perf" in _args():
		for repetition in 2:
			for aw in [false, true]:
				for kind in ["single", "aoe"]:
					await _case("challenge", kind, aw)
			await _awakening()
		return
	if "--capture" in _args():
		await _case("challenge", "single", false)
		await _case("challenge", "aoe", false)
		await _awakening()
		await _case("challenge", "single", true)
		await _case("challenge", "aoe", true)
		await _defeat(true)
		return
	for aw in [false, true]:
		for kind in ["single", "aoe"]:
			await _case("test", kind, aw)
	for mode in ["clear_check", "challenge"]:
		await _case(mode, "single", true)
		await _case(mode, "aoe", false)
	await _case("test", "single", true, true)
	await _case("test", "aoe", false, true)
	await _awakening()
	await _defeat(false)
	await _defeat(true)
	await _selection()

func _case(mode: String, kind: String, awakened: bool, counter: bool = false) -> void:
	var definition := _definition_for()
	if counter and kind == "single":
		definition.party = [definition.party[3]]
	definition.boss.skills = [{"skill_id": "boss_claw", "name": "光の刃" if kind == "single" else "照射", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}]
	definition.boss.atk = 40
	definition.boss.spd = 1
	definition.boss.boss_name = "ヒーロー"
	if not await _open_view(mode, definition):
		return
	view.session.battle.boss.hp = 1000
	view.session.battle.is_awakened = awakened
	var before: Dictionary = {}
	var entry: Dictionary = {}
	var samurai_id := 0 if counter and kind == "single" else 3
	for attempt in range(16):
		before = view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and view.session.pending_ally_id() == samurai_id else {"type": "defend"}
		for e in view.session.resolve_ally_action(action):
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var tag := mode + ("_awakened_" if awakened else "_normal_") + kind + ("_counter" if counter else "")
	if entry.is_empty():
		_fail(tag + ": no resolved entry")
		await _close_view()
		return
	var snapshot: Dictionary = view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	var observed := false
	var numbers_seen := false
	var samples: Array = []
	var slow: Array = []
	var shots := {}
	var last := Time.get_ticks_usec()
	view._present_batch([entry], before)
	for frame in range(1800):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		var driver = stage._skill_presentation
		if is_instance_valid(driver) and driver is Driver:
			observed = true
			if frame > 8:
				samples.append(dt)
				if dt > 20:
					var rid := _tree().root.get_viewport_rid()
					slow.append({"ms": snappedf(dt, 0.1), "age": snappedf(driver.age, 0.01), "frame": frame,
						"render_cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.1),
						"render_gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.1),
						"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))})
			if driver.scene != ({"single": "shear" if awakened else "blade", "aoe": "press" if awakened else "array"}[kind]):
				_fail(tag + ": wrong move " + driver.scene)
			for moment in _moments(driver.scene):
				if driver.age >= moment and not shots.has(moment):
					shots[moment] = true
					_save(tag + "_%.2f" % moment)
			if not stage._damage_numbers._numbers.is_empty():
				numbers_seen = true
				if stage._damage_numbers.z_index <= 6:
					_fail(tag + ": numbers under the hero layers")
		var state: Dictionary = view._presenter.display_state()
		for key in state.get("party", {}):
			var unit: Dictionary = state.party[key]
			var label := view.find_child("PartyRowHP_%s" % key, true, false) as Label
			if label != null and label.text != "HP %d / %d" % [int(unit.hp), int(unit.max_hp)]:
				_fail(tag + ": HUD HP not synchronized")
		if observed and not view._presenter.is_playing() and not stage.is_playing():
			break
	if not observed:
		_fail(tag + ": no hero driver")
	if not numbers_seen:
		_fail(tag + ": no damage numbers")
	if seen.size() != 1 or seen[0] != entry:
		_fail(tag + ": impact not exactly once")
	if view.session.battle.snapshot() != snapshot:
		_fail(tag + ": simulation mutated")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation) or not stage._visuals.boss.visible:
		_fail(tag + ": cleanup")
	if stage.scale != Vector2.ONE:
		_fail(tag + ": camera not restored")
	for key in stage._party_keys:
		if stage._visuals[key].self_modulate != Color.WHITE:
			_fail(tag + ": ally color not restored")
	samples.sort()
	report.cases.append({"id": tag, "impact_count": seen.size(), "numbers_visible": numbers_seen, "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0, "slow": slow})
	report.cases.back().merge(_timings(samples))
	print("HERO_BOSS_CASE ", tag, " ", JSON.stringify(_timings(samples)))
	await _close_view()

func _moments(scene: String) -> Array:
	match scene:
		"blade": return [0.9, 1.4, 1.75, 2.1, 2.5]
		"array": return [1.5, 2.6, 3.4, 3.9, 4.55, 4.9]
		"shear": return [0.9, 1.47, 1.95, 2.3, 2.6]
		"press": return [1.8, 3.24, 3.3, 3.7, 3.9, 4.3]
		"breach": return [1.2, 2.4, 3.1, 3.4, 5.0, 5.5]
	return []

func _intro() -> void:
	var definition := _definition_for()
	definition.boss.boss_name = "ヒーロー"
	view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_boss_appearance("appearance_hero_boss")
	view.request_encounter({"boss_name": "ヒーロー", "author": ""})
	view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_hero_boss")
	var observed := false
	var done := false
	var samples: Array = []
	var shots := {}
	var slow: Array = []
	var max_age := 0.0
	var last := Time.get_ticks_usec()
	for i in range(1200):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		if stage == null and is_instance_valid(view) and view.get("_battlefield_ally_row") != null:
			stage = view._battlefield_ally_row.get_meta("visual_stage", null)
		var player = null
		if stage != null:
			for node in stage.get_children():
				if node.get_script() == IntroPlayer:
					player = node
		if player != null:
			if not observed:
				_mark("intro", "start")
			if observed and player.state == "playing":
				samples.append(dt)
				if dt > 20:
					slow.append({"ms": snappedf(dt, 0.1), "age": snappedf(float(player.age), 0.01)})
			observed = true
			max_age = maxf(max_age, float(player.age))
			for moment in [0.5, 0.9, 1.2, 1.45, 1.75, 1.95, 2.3, 3.0, 3.3, 3.75, 3.9, 4.1, 4.5, 5.2]:
				if float(player.age) >= moment and not shots.has(moment):
					shots[moment] = true
					_save("intro_%.2f" % moment)
		elif observed:
			done = true
			for k in range(20):
				await _tree().process_frame
			_mark("intro", "end")
			break
	if not observed or not done:
		_fail("intro did not play through (observed=%s done=%s)" % [observed, done])
	if stage != null and (stage.scale != Vector2.ONE or not stage._visuals.boss.visible):
		_fail("intro: stage not restored")
	for n in ["HeroIntroWorld", "HeroIntroDim", "HeroIntroPost"]:
		if stage != null and stage.find_child(n, false, false) != null:
			for i in range(3):
				await _tree().process_frame
			if stage.find_child(n, false, false) != null:
				_fail("intro: left behind " + n)
	samples.sort()
	report.cases.append({"id": "intro", "observed": observed, "done": done, "max_age": max_age, "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0, "slow": slow})
	report.cases.back().merge(_timings(samples))
	print("HERO_BOSS_CASE intro ", JSON.stringify(_timings(samples)), " max=", samples.back() if not samples.is_empty() else 0, " slow=", JSON.stringify(slow))
	await _close_view()

## 支援（回復・強化）。立ち姿 → 支援のポーズ → 立ち姿、命中は1回。
func _support(mode: String, awakened: bool) -> void:
	var definition := _definition_for()
	definition.boss.skills = [{"skill_id": "boss_claw", "name": "救援の光" if mode == "heal" else "正義の構え", "type": "self_heal" if mode == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}]
	definition.boss.spd = 1
	definition.boss.boss_name = "ヒーロー"
	# 支援は登場・勝利の演出を使わない TEST の画面で（同じ戦場の描画。登場を毎回待たない）
	if not await _open_view("test", definition):
		return
	view.session.battle.boss.hp = 1000
	view.session.battle.is_awakened = awakened
	var before: Dictionary = {}
	var entry: Dictionary = {}
	for attempt in range(16):
		before = view.session.battle.presentation_state().duplicate(true)
		for e in view.session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var tag := "support_" + ("awakened_" if awakened else "normal_") + mode
	if entry.is_empty():
		_fail(tag + ": no resolved entry")
		await _close_view()
		return
	var snapshot: Dictionary = view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	var observed := false
	var samples: Array = []
	var shots := {}
	var last := Time.get_ticks_usec()
	for k in range(20):
		await _tree().process_frame
	_mark(tag, "start")
	view._present_batch([entry], before)
	for frame in range(900):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		var driver = stage._skill_presentation
		if is_instance_valid(driver) and driver is Driver:
			observed = true
			if frame > 8:
				samples.append(dt)
			var expected := ("awakened_" if awakened else "") + mode
			if driver.scene != expected:
				_fail(tag + ": wrong scene " + driver.scene)
			for moment in [0.2, 0.5, 0.8, 1.1, 1.25, 1.35, 1.6, 2.0]:
				if driver.age >= moment and not shots.has(moment):
					shots[moment] = true
					_save(tag + "_%.2f" % moment)
		if observed and not view._presenter.is_playing() and not stage.is_playing():
			break
	for k in range(20):
		await _tree().process_frame
	_mark(tag, "end")
	if not observed:
		_fail(tag + ": no hero support driver")
	if seen.size() != 1:
		_fail(tag + ": impact not exactly once")
	if view.session.battle.snapshot() != snapshot:
		_fail(tag + ": simulation mutated")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation) or not stage._visuals.boss.visible or stage.scale != Vector2.ONE:
		_fail(tag + ": cleanup")
	samples.sort()
	report.cases.append({"id": tag, "impact_count": seen.size(), "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0})
	report.cases.back().merge(_timings(samples))
	print("HERO_BOSS_CASE ", tag, " ", JSON.stringify(_timings(samples)))
	await _close_view()

func _awakening() -> void:
	var definition := _definition_for()
	definition.boss.hp = 400
	definition.boss.atk = 10
	definition.boss.boss_name = "ヒーロー"
	definition.boss.awakening = {"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal_amount": 100}
	if not await _open_view("challenge", definition):
		return
	for i in range(12):
		if view.session.pending_ally_id() == 0:
			break
		view.session.resolve_ally_action({"type": "defend"})
	var before: Dictionary = view.session.battle.presentation_state().duplicate(true)
	var entry: Dictionary = {}
	for e in view.session.resolve_ally_action({"type": "attack"}):
		if str(e.get("action", "")) == "awakening":
			entry = e
	if entry.is_empty():
		_fail("awakening missing")
		await _close_view()
		return
	stage.set_state(before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	var shots := {}
	var observed := false
	var samples: Array = []
	var last := Time.get_ticks_usec()
	view._present_batch([entry], before)
	for i in range(1400):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		var d = stage._skill_presentation
		if is_instance_valid(d) and d is Driver:
			observed = true
			if i > 8:
				samples.append(dt)
			for t in _moments("breach"):
				if d.age >= t and not shots.has(t):
					shots[t] = true
					_save("awakening_%.2f" % t)
		if observed and not view._presenter.is_playing():
			break
	for i in range(30):
		await _tree().process_frame
	await RenderingServer.frame_post_draw
	_save("awakening_idle_with_aura")
	if not observed:
		_fail("awakening: no hero driver")
	if seen.size() != 1 or stage._asset_ids.boss != "hero_boss_awakened" or stage.scale != Vector2.ONE:
		_fail("awakening finish contract")
	if stage._visuals.boss.find_child("HeroDarkAura", false, false) == null:
		_fail("awakened idle has no aura")
	samples.sort()
	report.cases.append({"id": "awakening", "impact_count": seen.size(), "persistent_form": stage._asset_ids.boss, "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0})
	report.cases.back().merge(_timings(samples))
	print("HERO_BOSS_CASE awakening ", JSON.stringify(_timings(samples)))
	await _close_view()

func _timings(samples: Array) -> Dictionary:
	var total := 0.0
	var over20 := 0
	var over33 := 0
	for dt in samples:
		total += float(dt)
		if dt > 20:
			over20 += 1
		if dt > 33:
			over33 += 1
	return {"average_fps": 1000.0 * samples.size() / maxf(total, .001), "over_20ms": over20, "over_33ms": over33}

func _defeat(awakened: bool) -> void:
	var definition := _definition_for()
	definition.boss.hp = 400
	definition.boss.atk = 1
	definition.boss.boss_name = "ヒーロー"
	if not await _open_view("challenge", definition):
		return
	view.session.battle.boss.hp = 1
	view.session.battle.is_awakened = awakened
	var before: Dictionary = view.session.battle.presentation_state().duplicate(true)
	stage.set_state(before)
	var tag := "defeat_awakened" if awakened else "defeat_normal"
	var shots := {}
	for k in range(20):
		await _tree().process_frame
	_mark(tag, "start")
	view._present_batch(view.session.resolve_ally_action({"type": "attack"}), before)
	var observed := false
	var done := false
	var first := 0
	var samples: Array = []
	var last := Time.get_ticks_usec()
	for i in range(1900):
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		for node in stage.get_children():
			if node.get_script() == Victory:
				if not observed:
					first = i
				observed = true
				if node.state == "playing" and i > first + 2:
					samples.append(dt)
				if node.state == "playing":
					for moment in [0.3, 0.6, 0.9, 1.2, 1.5, 1.8, 2.1, 2.4, 2.8, 3.2, 3.6, 4.2, 4.8]:
						if float(node.age) >= moment and not shots.has(moment):
							shots[moment] = true
							_save(tag + "_t%.2f" % moment)
				if node.state == "done":
					done = true
		if done:
			break
	for i in range(150):
		await _tree().process_frame
	_mark(tag, "end")
	_save(tag)
	if not observed or not done:
		_fail(tag + ": victory did not complete")
	samples.sort()
	report.cases.append({"id": tag, "victory_seen": observed, "result_seen": done, "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0})
	report.cases.back().merge(_timings(samples))
	print("HERO_BOSS_CASE ", tag, " ", JSON.stringify(_timings(samples)), " max=", samples.back() if not samples.is_empty() else 0)
	await _close_view()

func _selection() -> void:
	var game := RBMGameRoot.new()
	_tree().root.add_child(game)
	for i in range(10):
		await _tree().process_frame
	if "--english" in _args():
		RBMLocale.set_locale("en")
		for i in range(3):
			await _tree().process_frame
	game._on_create_pressed()
	game.creator_entry.find_child("NewBossButton", true, false).pressed.emit()
	game.creator_entry.find_child("ChooseSimpleModeButton", true, false).pressed.emit()
	var main: RBMCreatorMain = game.creator_entry.main
	main.open_appearance_picker()
	var picker: RBMCreatorAppearancePicker = main._appearance_picker
	for i in range(5):
		await _tree().process_frame
	var button: Button = picker._entry_buttons.get("appearance_hero_boss")
	if button == null:
		_fail("hero missing from selection")
		game.queue_free()
		return
	var ancestor = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			break
		ancestor = ancestor.get_parent()
	button.pressed.emit()
	for i in range(3):
		await _tree().process_frame
	await RenderingServer.frame_post_draw
	_save("selection_normal")
	var toggle := picker.find_child("AwakenedPreviewToggle", true, false) as Button
	if toggle == null or toggle.disabled:
		_fail("hero awakening preview is unavailable")
		game.queue_free()
		return
	toggle.pressed.emit()
	for i in range(3):
		await _tree().process_frame
	await RenderingServer.frame_post_draw
	_save("selection_awakened")
	picker.call("_on_confirm_pressed")
	if main.draft.appearance_id != "appearance_hero_boss":
		_fail("actual Creator did not accept the hero selection")
	for i in range(5):
		await _tree().process_frame
	await RenderingServer.frame_post_draw
	_save("creator_selected")
	report.cases.append({"id": "selection", "cards": picker._entry_buttons.size(), "hero_present": true, "awakening_toggle_enabled": not toggle.disabled})
	game.queue_free()
	await _tree().process_frame

func _definition_for() -> Dictionary:
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"] = []
	for id in ["hero", "butler", "healer", "samurai"]:
		var master: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/allies/" + id + ".json")
		var skill_ids: Array = []
		for skill in master.get("skills", []):
			skill_ids.append(skill["id"])
		definition.party.append({"character_id": id, "allowed_skill_ids": skill_ids})
	return definition

func _open_view(mode: String, definition: Dictionary, encounter: bool = true) -> bool:
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge":
		view.setup(null)
	view.set_boss_appearance("appearance_hero_boss")
	if mode != "test" and encounter:
		view.request_encounter({"boss_name": "ヒーロー", "author": ""})
	if mode == "test":
		view.start(definition, 20260906)
	elif mode == "clear_check":
		view.start_battle(definition, 20260906)
	else:
		view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_hero_boss")
	for i in range(8):
		await _tree().process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage", null)
	if stage == null or not stage.has_method("get_visual_audit"):
		_fail("Production View has no auditable visual stage: " + mode)
		return false
	var ticks := 0
	while view._presenter.is_playing() and ticks < 600:
		await _tree().process_frame
		ticks += 1
	# 登場（2026-11-17 からヒーローにもある）が終わるのを待つ
	var encounter_node = view.get("_encounter")
	while encounter_node != null and is_instance_valid(encounter_node) and encounter_node.is_playing() and ticks < 1200:
		await _tree().process_frame
		ticks += 1
	stage.set_state(view.session.battle.presentation_state())
	return true

func _close_view() -> void:
	if is_instance_valid(view):
		view.queue_free()
	view = null
	stage = null
	await _tree().process_frame

func _expected_case_count() -> int:
	if "--intro-only" in _args():
		return 2 if "--perf" in _args() else 1
	if "--new-only" in _args():
		return 14 if "--perf" in _args() else 7
	if "--selection-only" in _args():
		return 1
	if "--defeat-only" in _args():
		return 2
	if "--awakened-defeat" in _args():
		return 2 if "--perf" in _args() else 1
	if "--perf" in _args():
		return 10
	if "--capture" in _args():
		return 6
	return 14
