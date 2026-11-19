extends RefCounted
## ボスの登場（rbm_intro_player.gd の CHOREO）だけを、本番の挑戦の画面・実際の描画で確かめる（2026-11-17。どのボスでも使える）。
## 起動: godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_boss_intro_gpu.gd --output=<dir> --boss=<見た目のID 例 plush> [--perf] [--1080] [--capture]
## 普通は時刻ごとの画像を保存する。--perf は実時間（録画モードなし）で同じ登場を2回測る（画像は保存しない）。
## --capture は確認動画用（--write-movie と一緒に使う。始まりと終わりのコマ番号を印として出す）。
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const MOMENTS := [0.6, 0.9, 1.2, 1.4, 1.6, 1.8, 2.1, 2.3, 2.5, 2.7, 2.9, 3.2, 3.5, 3.7, 3.9, 4.3, 4.7]
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

func _arg(name: String, fallback: String) -> String:
	for a in _args():
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return fallback

func _boss() -> String:
	return _arg("boss", "plush")

func _fail(message: String) -> void:
	if not report.errors.has(message):
		report.errors.append(message)
		push_error(message)

func _save(tag: String) -> void:
	if "--perf" in _args() or "--capture" in _args():
		return
	_tree().root.get_texture().get_image().save_png(output_dir.path_join(tag + ".png"))

func _mark(tag: String, what: String) -> void:
	if "--capture" in _args():
		print("INTRO_MARK ", tag, " ", what, " ", Engine.get_frames_drawn())

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
	report.boss = _boss()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	report.requested_size = [1920, 1080] if "--1080" in _args() else [1280, 720]
	if not IntroPlayer.has_intro(_boss()):
		_fail("no dedicated intro for " + _boss())
	tree.process_frame.connect(_observe_audio)
	for repetition in (2 if "--perf" in _args() else 1):
		await _intro()
	tree.process_frame.disconnect(_observe_audio)
	var expected := 2 if "--perf" in _args() else 1
	if report.cases.size() != expected:
		_fail("Verification stopped early: expected %d cases, got %d" % [expected, report.cases.size()])
	report.audio_peak_db = audio_peak_db
	if audio_peak_db > -0.1:
		_fail("Master output approaches clipping: %.2f dB" % audio_peak_db)
	report.actual_size = [tree.root.size.x, tree.root.size.y]
	report.passed = report.errors.is_empty()
	FileAccess.open(directory.path_join("intro-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	_gpu_verification_completed = true
	print("INTRO_GPU_DONE ", _boss(), " ", report.passed, " cases=", report.cases.size(), " peak_db=", audio_peak_db)
	return 0 if report.passed else 1

func _observe_audio() -> void:
	audio_peak_db = maxf(audio_peak_db, maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0)))

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

func _timings(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"average_fps": 0.0, "over_20ms": 0, "over_33ms": 0}
	var total := 0.0
	var over20 := 0
	var over33 := 0
	for s in samples:
		total += float(s)
		if float(s) > 20.0:
			over20 += 1
		if float(s) > 33.0:
			over33 += 1
	return {"average_fps": 1000.0 / (total / samples.size()), "over_20ms": over20, "over_33ms": over33}

func _intro() -> void:
	var appearance := "appearance_" + _boss()
	var definition := _definition_for()
	view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_boss_appearance(appearance)
	view.request_encounter({"boss_name": _arg("name", "BOSS"), "author": ""})
	view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, appearance)
	var observed := false
	var done := false
	var samples: Array = []
	var shots := {}
	var slow: Array = []
	var max_age := 0.0
	var last := Time.get_ticks_usec()
	for i in range(1400):
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
			for moment in MOMENTS:
				if float(player.age) >= moment and not shots.has(moment):
					shots[moment] = true
					_save("intro_%.2f" % moment)
		elif observed:
			done = true
			for k in range(20):
				await _tree().process_frame
			await RenderingServer.frame_post_draw
			_save("intro_after")
			_mark("intro", "end")
			break
	if not observed or not done:
		_fail("intro did not play through (observed=%s done=%s)" % [observed, done])
	if stage != null and (stage.scale != Vector2.ONE or not stage._visuals.boss.visible):
		_fail("intro: stage not restored")
	samples.sort()
	report.cases.append({"id": "intro", "observed": observed, "done": done, "max_age": max_age, "frames": samples.size(), "max_ms": samples.back() if not samples.is_empty() else 0, "slow": slow})
	report.cases.back().merge(_timings(samples))
	print("INTRO_CASE ", _boss(), " ", JSON.stringify(_timings(samples)), " max=", samples.back() if not samples.is_empty() else 0, " slow=", JSON.stringify(slow))
	if is_instance_valid(view):
		view.queue_free()
	view = null
	stage = null
	await _tree().process_frame
