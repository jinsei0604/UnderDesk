extends "res://tools/verify_encounter_gpu.gd"
## Production dispatch and result integration. Real challenge/clear-check UI, offline fixtures.
const Victory = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
var subject := "dragon"
var awakened_case := false
var selected_checked := false
var warmup_seen := false
var warmup_tail := 0
var warmup_frames: Array = []
const SOUNDS := {"dragon":"dragon_detonation","musha":"musha_break","astronaut":"astro_collapse","gentleman":"gentleman_burst"}

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	tree.root.size = Vector2i(1280,720)
	tree.root.content_scale_size = Vector2i(1280,720)
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale("ja")
	var forms: Array = [false,true]
	if _arg("forms","") == "awakened": forms = [true]
	if _arg("forms","") == "normal": forms = [false]
	for boss_id in _arg("bosses","dragon,musha,astronaut,gentleman").split(","):
		subject = boss_id
		for route in _arg("routes","challenge,clear_check").split(","):
			for awakened in forms:
				awakened_case = awakened
				selected_checked = false
				warmup_seen = false
				await _run(subject,route,false,false)
	var failed := checks.filter(func(c): return not c.ok).size()
	FileAccess.open(out.path_join("encounter-report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed,"perf":perf_results,"warmup_frames":warmup_frames},"\t"))
	print("AWAKENED_INTEGRATION_DONE checks=",checks.size()," failed=",failed)
	_gpu_verification_completed = true
	return 0 if failed == 0 else 1

func _draft(boss: String, hp: int) -> RBMCreatorDraft:
	var d := super._draft(boss,hp)
	if awakened_case:
		d.set_awakening({"conditions":[{"type":"turn_at_least","turn":2}],"condition_logic":"AND","buff":{},"heal":{}})
		d.record_clear_check_success()
		d.publish()
	return d

func _pace(seconds: float) -> void:
	if is_equal_approx(seconds,0.8) and awakened_case:
		# Real defend commands reach turn two without killing the boss in turn one.
		for i in range(8):
			if view.session.battle.is_awakened: break
			view.act_defend(view.session.pending_ally_id())
			var start := Time.get_ticks_msec()
			while bool(view.call("_is_busy")) and Time.get_ticks_msec()-start < 15000:
				await tree.process_frame
		await _frames(2)
		_check("Awakening reached through a resolved action",view.session.battle.is_awakened and director.boss_asset()==subject+"_awakened")
	await super._pace(seconds)

func _perf_sample() -> void:
	var warming := is_instance_valid(director) and is_instance_valid(director.get("_defeat_warmup"))
	if (warming or warmup_tail > 0) and not _perf.is_empty():
		warmup_frames.append({"boss":subject,"ms":(Time.get_ticks_usec()-int(_perf.t))/1000.0,"preparing":warming})
	warmup_tail = 2 if warming else maxi(0,warmup_tail-1)
	super._perf_sample()
	if is_instance_valid(director) and is_instance_valid(director.get("_defeat_warmup")):
		warmup_seen = true
	if not selected_checked and is_instance_valid(director) and is_instance_valid(director.get("_victory")):
		selected_checked = true
		var p = director.get("_victory")
		if subject != "dragon":
			_check("Material preparation only for a possible awakening",warmup_seen == awakened_case)
			_check("Material preparation freed before final impact",not is_instance_valid(director.get("_defeat_warmup")))
		var expected = Victory.defeat_script(subject+"_awakened" if awakened_case else subject)
		_check("Production defeat dispatch: "+("awakened" if awakened_case else "normal"),p.defeat.get_script()==expected)

func _shutdown() -> void:
	if is_instance_valid(director) and is_instance_valid(director.get("_victory")):
		if awakened_case:
			var vp = director.get("_victory")
			var st := _stage()
			_check("Awakened body stays invisible at result",not st._visuals.boss.visible and vp.defeat.gone)
			_check("Awakened aura stays invisible at result",not st.get("_"+subject+"_aura").visible and not st.get("_"+subject+"_aura").is_processing())
			if subject == "musha":
				_check("Musha separate ink stays invisible at result",not st._musha_ink.back.disp.visible and not st._musha_ink.mid.disp.visible and not st._musha_ink.top.disp.visible and not st._musha_idle.visible)
			await RenderingServer.frame_post_draw
			tree.root.get_texture().get_image().save_png(out.path_join("result_"+str(checks.size())+".png"))
		var sounds: Array = director.audio.history.filter(func(e): return e[1]=="enc:"+SOUNDS[subject])
		_check("Detonation sound occurs only once for the awakened form",sounds.size()==(1 if awakened_case else 0))
		var volume_ref: WeakRef
		if awakened_case and subject != "dragon":
			var field = director.get("_victory").defeat.field
			_check("Defeat volume stops rendering before result",field.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
			volume_ref = weakref(field.viewport)
		var s := _stage()
		director.cancel()
		await _frames(2)
		if volume_ref != null:
			_check("Defeat volume freed on cancellation",volume_ref.get_ref() == null)
		_check("Defeat cancellation restores aura and removes layers",s.get("_"+subject+"_aura").is_processing() and _leftovers().is_empty())
	await super._shutdown()
