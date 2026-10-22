extends RefCounted
var _tree_override: SceneTree
var view = null
var stage = null
var output_dir := ""
var _gpu_verification_completed := false
var results: Dictionary = {"cases":[],"errors":[]}
var label: Label
var sublabel: Label
var marker: ColorRect
var audio_record: AudioEffectRecord
var gift_target := "hero"
var preview := false
var performance_mode := false
var capture_mode := false
var size_px := Vector2i(1280,720)
var zero_time := 0
var case_start := 0
var impact_times: Array = []
var finished_times: Array = []

func _run() -> void:
	pass

func run_gpu_verification(tree: SceneTree, directory: String, _all: bool) -> int:
	_tree_override = tree
	output_dir = directory
	for arg in OS.get_cmdline_user_args():
		preview = preview or arg == "--preview"
		performance_mode = performance_mode or arg == "--perf"
		capture_mode = capture_mode or arg == "--capture"
		if arg == "--1080": size_px = Vector2i(1920,1080)
	if DisplayServer.get_name()=="headless": return 2
	tree.root.size=size_px
	tree.root.content_scale_size=Vector2i(1280,720)
	tree.root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	tree.root.title="MC Butler Integrated Review"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DirAccess.make_dir_recursive_absolute(output_dir)
	results["adapter"]=RenderingServer.get_video_adapter_name()
	results["renderer"]=RenderingServer.get_current_rendering_method()
	results["window"]=[size_px.x,size_px.y]
	results["fixed_fps"]=false
	results["mode"]="realtime_performance" if performance_mode else "realtime_review"
	await _new_view("knight","night")
	var overlay:=CanvasLayer.new()
	tree.root.add_child(overlay)
	label=Label.new()
	label.position=Vector2(355,102)
	label.add_theme_font_size_override("font_size",21)
	label.add_theme_color_override("font_color",Color("ffe4ab"))
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	overlay.add_child(label)
	sublabel=Label.new()
	sublabel.position=Vector2(355,133)
	sublabel.add_theme_font_size_override("font_size",15)
	overlay.add_child(sublabel)
	marker=ColorRect.new()
	marker.position=Vector2(8,8)
	marker.size=Vector2(8,8)
	marker.color=Color.BLACK
	overlay.add_child(marker)
	label.text="老執事4演出 / 本番組み込み・テンポ比較"
	sublabel.text="1280×720 / 本番HUD / 実時間・音声付き"
	await tree.create_timer(1.0).timeout
	if capture_mode:
		FileAccess.open(output_dir+"/ready.txt",FileAccess.WRITE).store_string("ready")
		while not FileAccess.file_exists(output_dir+"/record.trigger"):
			await tree.process_frame
		audio_record=AudioEffectRecord.new()
		audio_record.format=AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,audio_record)
		audio_record.set_recording_active(true)
	zero_time=Time.get_ticks_usec()
	marker.color=Color(0,1,0)
	await tree.create_timer(0.8).timeout
	var actions := ["hero_attack","attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift","butler_grand_ice"] if performance_mode else ["hero_attack","attack","hero_slash","butler_ice_bolt","hero_blaze_all","butler_ice_storm","hero_flame_wrap","butler_sp_gift","butler_grand_ice"]
	for action in actions:
		await _case(action,"騎士 / 夜",preview)
		if not performance_mode: await tree.create_timer(0.65).timeout
	for setting in [["slime","day"],["dragon","night"]]:
		await _close_view()
		await _new_view(setting[0],setting[1])
		for action in (["attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift"] if performance_mode else ["butler_ice_bolt","butler_ice_storm"]):
			await _case(action,setting[0]+" / "+setting[1],false)
			if not performance_mode: await tree.create_timer(0.5).timeout
	gift_target="healer"
	await _case("butler_sp_gift","別配置の味方 / 後列へのSP回復",false)
	gift_target="hero"
	if performance_mode:
		for repeat in range(2):
			for action in ["attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift"]:
				await _case(action,"repeat "+str(repeat),false)
		await _cancel_checks()
		for mode in ["clear_check","challenge"]:
			await _close_view()
			await _new_view("knight","night",mode)
			for action in ["attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift"]:
				await _case(action,mode,false)
	label.text="再生完了 / 本番組み込み・余韻を調整"
	sublabel.text="ご確認対象：時計を扱う所作・氷の手応え・SPの受け渡し・音"
	await tree.create_timer(0.8).timeout
	if capture_mode:
		audio_record.set_recording_active(false)
		audio_record.get_recording().save_to_wav(output_dir+"/realtime-audio.wav")
	results["duration"]=(Time.get_ticks_usec()-zero_time)/1000000.0
	results["passed"]=results.errors.is_empty()
	FileAccess.open(output_dir+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	FileAccess.open(output_dir+"/done.txt",FileAccess.WRITE).store_string("done")
	print("BUTLER_ACTIONS_DONE ",results.passed," ",results.cases.size())
	if capture_mode: AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	await _close_view()
	overlay.queue_free()
	await tree.process_frame
	_gpu_verification_completed=true
	return 0 if results.passed else 1

func _new_view(boss: String, background: String, mode: String="test") -> void:
	await _open_view(mode,_definition_for("butler"),"appearance_"+boss)
	view.battle_background=background
	# Coverage deliberately chooses standard day/night rather than boss-specific artwork.
	view._world_battle.boss_backgrounds={}
	view._world_battle.background_convention="res://tools/no_background_%s.png"
	view._world_battle.update()
	var id:=_actor_id("butler")
	var safety:=0
	while view.session.pending_ally_id()!=id and safety<32:
		view.session.resolve_ally_action({"type":"defend"})
		safety+=1
	view._presenter.cancel()
	view.refresh()
	stage.impact.connect(func(_entry): impact_times.append(Time.get_ticks_usec()))
	stage.finished.connect(func(): finished_times.append(Time.get_ticks_usec()))
	while not stage._presentation_warmup.is_ready():
		await _tree().process_frame
	await _tree().create_timer(0.35).timeout

func _case(action: String, setting: String, shots: bool) -> void:
	var title := {"hero_attack":"比較：勇者の通常攻撃", "hero_slash":"比較：勇者の単体攻撃", "hero_blaze_all":"比較：勇者の全体攻撃", "hero_flame_wrap":"比較：勇者の炎纏い", "attack":"01  通常攻撃 / 時計の一拍・無属性", "butler_ice_bolt":"02  氷単体魔法 / 一点を貫く氷槍", "butler_ice_storm":"03  氷全体魔法 / 広がる一斉着弾・命中1回", "butler_sp_gift":"04  SP回復 / 一礼して味方へ受け渡す", "butler_grand_ice":"05  氷属性大魔法 / 既存・変更なし"}
	label.text=title[action]
	sublabel.text=setting+"   |   実時間再生 / 構え → 命中 → 復帰"
	var battle: RBMBattle=view.session.battle
	var original:=battle.snapshot().duplicate(true)
	var actor_character:="hero" if action.begins_with("hero_") else "butler"
	# Build a fresh valid turn through the real session; fixture state only.
	var fixture:=RBMCreatorTestSession.new(_definition_for(actor_character),20260906)
	while fixture.pending_ally_id()!=_actor_id(actor_character): fixture.resolve_ally_action({"type":"defend"})
	battle.restore(fixture.battle.snapshot())
	# A sandbox fixture grants SP only BEFORE resolving the actual action. Combat code stays byte-identical.
	for unit in battle.party:
		if unit.character_id==actor_character: unit.sp=unit.max_sp
		elif unit.character_id==gift_target: unit.sp=20
	var before:=battle.presentation_state().duplicate(true)
	stage.set_state(before)
	var request: Dictionary={"type":"attack"} if action in ["attack","hero_attack"] else {"type":"skill","skill_id":action,"target_id":_actor_id(gift_target)}
	var entries:=battle.resolve_pending_ally_action(request)
	var resolved:=battle.snapshot().duplicate(true)
	if entries.is_empty() or bool(entries[0].get("failed",false)):
		results.errors.append("Cannot resolve "+action)
		battle.restore(original)
		return
	impact_times.clear()
	finished_times.clear()
	stage._sound.history.clear()
	case_start=Time.get_ticks_usec()
	var times: Array[float]=[]
	var phases: Array[String]=[]
	var draw_calls: Array[int]=[]
	var objects: Array[int]=[]
	var primitives: Array[int]=[]
	var last:=case_start
	var start_ms: float=0
	var shot_indices: Array=[]
	view._present_batch(entries,before)
	start_ms=(Time.get_ticks_usec()-case_start)/1000.0
	var timeout:=0
	while (view._presenter.is_playing() or stage.is_playing()) and timeout<1200:
		await _tree().process_frame
		var now:=Time.get_ticks_usec()
		times.append((now-last)/1000.0)
		last=now
		phases.append("stage_playback" if stage.is_playing() else "presenter_completion_hud_refresh")
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		timeout+=1
		if shots:
			var slot:=int((now-case_start)/100000.0)
			if not shot_indices.has(slot):
				shot_indices.append(slot)
				await RenderingServer.frame_post_draw
				_tree().root.get_texture().get_image().save_png(output_dir+"/%s_%02d.png"%[action,slot])
	var elapsed: float=(Time.get_ticks_usec()-case_start)/1000000.0
	var unchanged: bool=battle.snapshot()==resolved
	if not unchanged: results.errors.append("Battle mutated in playback: "+action)
	if impact_times.size()!=1: results.errors.append("Impact count: "+action+" "+str(impact_times.size()))
	if finished_times.size()!=1: results.errors.append("Finished count: "+action+" "+str(finished_times.size()))
	if stage.is_playing(): results.errors.append("Timeout: "+action)
	var hero_key:=str(_actor_id(actor_character))
	if stage._visuals[hero_key].position!=stage._homes[hero_key] or not stage._visuals[hero_key].visible:
		results.errors.append("Actor cleanup: "+action)
	var sorted:=times.duplicate()
	sorted.sort()
	var over20:=0
	var over33:=0
	var total:=0.0
	for ms in times:
		total+=ms
		if ms>20: over20+=1
		if ms>33: over33+=1
	results.cases.append({"action":action,"setting":setting,"start_seconds":(case_start-zero_time)/1000000.0,"duration":elapsed,"impact_seconds":(impact_times[0]-case_start)/1000000.0 if not impact_times.is_empty() else -1,"impacts":impact_times.size(),"finished":finished_times.size(),"snapshot_unchanged":unchanged,"resolved_entry":entries[0],"begin_call_ms":start_ms,"frames":times.size(),"mean_ms":total/maxi(1,times.size()),"max_ms":sorted.back() if not sorted.is_empty() else 0,"over20":over20,"over33":over33,"frame_ms":times if performance_mode else [],"frame_phase":phases if performance_mode else [],"draw_calls":draw_calls if performance_mode else []})
	results.cases.back()["objects"]=objects if performance_mode else []
	results.cases.back()["primitives"]=primitives if performance_mode else []
	results.cases.back()["audio_cues"]=stage._sound.history.duplicate()
	if performance_mode and (over33>0 or float(over20)/maxi(1,times.size())>0.02): results.errors.append("Frame budget: "+action+" / "+setting)
	if not performance_mode:await _tree().create_timer(0.4).timeout
	battle.restore(original)
	var refresh_start:=Time.get_ticks_usec()
	view.refresh()
	results.cases.back()["idle_refresh_cpu_ms"]=(Time.get_ticks_usec()-refresh_start)/1000.0
	await _tree().process_frame

func _cancel_checks() -> void:
	var checks: Array=[]
	for key in ["attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift"]:
		var skill: Dictionary={}
		for item in _master("butler").skills:
			if item.id==key: skill=item
		var entry: Dictionary={"actor":_actor_id("butler"),"action":"attack","target":"boss","amount":20} if key=="attack" else _skill_entry(_actor_id("butler"),skill)
		for delay in [0.12,0.42,0.64]:
			impact_times.clear()
			finished_times.clear()
			stage.play_entry(entry,skill)
			await _tree().create_timer(delay).timeout
			stage.cancel()
			var impacts:=impact_times.size()
			await _tree().create_timer(0.20).timeout
			var clean: bool=not stage.is_playing() and stage._skill_presentation==null and impact_times.size()==impacts and finished_times.is_empty()
			for player in stage._sound._players: clean=clean and not player.playing
			for actor in stage._visuals:
				clean=clean and stage._visuals[actor].visible and stage._visuals[actor].position==stage._homes[actor]
			checks.append({"action":key,"cancel_at":delay,"clean":clean})
			if not clean: results.errors.append("Cancel cleanup "+key+" "+str(delay))
	results["cancel_checks"]=checks

func _tree() -> SceneTree:
	return _tree_override

func _master(character_id: String) -> Dictionary:
	return RBMDataLoader.load_dict("res://data_bossmaker/allies/"+character_id+".json")

func _definition_for(_character: String) -> Dictionary:
	return RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")

func _open_view(mode: String, definition: Dictionary, appearance: String) -> bool:
	match mode:
		"clear_check":view=RBMCreatorClearCheckView.new()
		"challenge":view=RBMChallengeBattleView.new()
		_:view=RBMCreatorTestBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode!="challenge":view.setup(null)
	view.set_boss_appearance(appearance)
	match mode:
		"clear_check":view.start_battle(definition,20260906)
		"challenge":view.start_battle(definition,RBMBattleUiKit.ALL_VISIBLE,appearance)
		_:view.start(definition,20260906)
	for i in 8: await _tree().process_frame
	stage=view._battlefield_ally_row.get_meta("visual_stage")
	while view._presenter.is_playing(): await _tree().process_frame
	stage.set_state(view.session.battle.presentation_state())
	return true

func _close_view() -> void:
	if is_instance_valid(view):
		view._presenter.cancel()
		view.queue_free()
	view=null
	stage=null
	await _tree().process_frame

func _actor_id(character_id: String) -> int:
	for unit in view.session.battle.party:
		if unit.character_id==character_id:return unit.id
	return -1

func _skill_entry(actor_id: int, skill: Dictionary) -> Dictionary:
	var entry: Dictionary={"actor":actor_id,"action":"skill","skill_id":skill.id}
	if skill.get("effect","")=="damage":entry.merge({"target":"boss","amount":20})
	elif skill.get("id","")=="butler_sp_gift":entry.merge({"target":_actor_id("hero"),"amount":40})
	return entry

func _butler_scripts() -> Array:
	return [RBMBattleStage.ATTACK_PRESENTATIONS["butler"],RBMBattleStage.SKILL_PRESENTATIONS["butler_ice_bolt"].script,RBMBattleStage.SKILL_PRESENTATIONS["butler_ice_storm"].script,RBMBattleStage.SKILL_PRESENTATIONS["butler_sp_gift"].script]
