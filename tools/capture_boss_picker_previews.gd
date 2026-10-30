extends RefCounted
## Capture only existing production presentations. Run with --fixed-fps 30.
var _gpu_verification_completed := false
var tree: SceneTree
var output := ""
var frames := 0

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	output = directory
	tree.root.size = Vector2i(960, 540)
	tree.root.content_scale_size = Vector2i(1280, 720)
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var cases: Array = []
	for boss in ["slime", "musha", "astronaut", "ghost"]:
		for awakened in ([false, true] if boss in ["musha", "astronaut"] else [false]):
			for kind in ["single", "all"]:
				cases.append(await capture_case(boss, awakened, kind))
	FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE).store_string(JSON.stringify(cases, "\t"))
	_gpu_verification_completed = true
	return 0 if cases.all(func(c): return c.ok) else 1

func capture_case(boss: String, awakened: bool, kind: String) -> Dictionary:
	var tag := boss + ("_awakened" if awakened else "") + "_" + kind
	var folder := output.path_join(tag)
	DirAccess.make_dir_recursive_absolute(folder)
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss
	draft.appearance_id = "appearance_" + boss
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	draft.add_skill({"name":"Preview", "type":"attack", "target":"all" if kind == "all" else "single", "attribute":"NEUTRAL", "atk_multiplier":1.0})
	var definition := draft.to_definition()
	var started := RBMDefinitionLoader.start_battle(definition, 20261028)
	assert(started.ok)
	var battle = started.battle
	battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	stage.show_damage_numbers = false
	tree.root.add_child(stage)
	var bg := TextureRect.new()
	bg.texture = RBMBattleBackgrounds.texture_for(boss, "night")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	stage.add_child(bg)
	stage.move_child(bg, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.configure(battle, draft.appearance_id)
	stage.set_state(battle.presentation_state())
	stage.prepare_presentations(definition, draft.appearance_id, "night")
	stage._sound.muted = true
	var entry := {"actor":"boss", "action":"skill", "skill_id":"preview", "target":0, "amount":20}
	if kind == "all":
		entry.erase("target")
		entry["hits"] = {}
		for unit in battle.party: entry.hits[unit.id] = {"target":unit.id, "amount":20}
	var skill := {"effect":"damage", "target":"ally_all" if kind == "all" else "ally_random_single", "attribute":"NEUTRAL"}
	# One unrecorded warmup ensures no asset-loading pause enters the movie.
	stage.play_entry(entry, skill)
	for i in 1200:
		await tree.process_frame
		if not stage.is_playing(): break
	assert(not stage.is_playing())
	var before: Dictionary = battle.snapshot().duplicate(true)
	frames = 0
	for i in 18: await frame(folder)
	var impacts: Array = []
	stage.impact.connect(func(e): impacts.append(e))
	stage.play_entry(entry, skill)
	while stage.is_playing() and frames < 900: await frame(folder)
	for i in 24: await frame(folder)
	var result := {"id":tag, "frames":frames, "fps":30, "ok":not stage.is_playing() and impacts.size() == 1 and battle.snapshot() == before, "simulation_unchanged":battle.snapshot() == before}
	stage.queue_free()
	await tree.process_frame
	print("CAPTURE ", result)
	return result

func frame(folder: String) -> void:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(folder.path_join("%04d.png" % frames))
	frames += 1
