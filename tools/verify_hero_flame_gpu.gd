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
var retain_result := false
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
	tree.root.title="MC Hero Flame Review"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DirAccess.make_dir_recursive_absolute(output_dir)
	results["adapter"]=RenderingServer.get_video_adapter_name()
	results["renderer"]=RenderingServer.get_current_rendering_method()
	results["window"]=[size_px.x,size_px.y]
	results["fixed_fps"]=Engine.get_frames_per_second() # overwritten explicitly below
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
	label.text="勇者 / 集炎の統一・強化中の刀身炎"
	sublabel.text="1280×720 / 本番HUD / 実時間・音声付き"
	# Prewarm only the prototype asset set; skill onset still uses the readiness gate.
	for path in preload("res://src/bossmaker/visuals/rbm_hero_action.gd").warm_paths("hero",""):
		load(path)
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
	await _case("hero_burst_slash","強化前 / 集炎を炎纏いと統一",false)
	if not performance_mode: await tree.create_timer(0.6).timeout
	await _buff_sequence()
	if performance_mode:
		for setting in [["slime","day"],["dragon","night"]]:
			await _close_view()
			await _new_view(setting[0],setting[1])
			for action in ["attack","hero_slash","hero_blaze_all","hero_flame_wrap","hero_burst_slash"]:
				await _case(action,setting[0]+" / "+setting[1],false)
		await _cancel_checks()
		for mode in ["clear_check","challenge"]:
			await _close_view()
			await _new_view("knight","night",mode)
			for action in ["hero_flame_wrap","hero_burst_slash"]:
				await _case(action,mode,false)
	label.text="再生完了 / バフ終了で元の刀身へ"
	sublabel.text="実際の攻撃力バフに同期 / 戦闘計算・SP・行動順は維持"
	await tree.create_timer(0.8).timeout
	if capture_mode:
		audio_record.set_recording_active(false)
		audio_record.get_recording().save_to_wav(output_dir+"/realtime-audio.wav")
	results["duration"]=(Time.get_ticks_usec()-zero_time)/1000000.0
	results["passed"]=results.errors.is_empty()
	FileAccess.open(output_dir+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	FileAccess.open(output_dir+"/done.txt",FileAccess.WRITE).store_string("done")
	print("HERO_ACTIONS_DONE ",results.passed," ",results.cases.size())
	if capture_mode: AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	await _close_view()
	overlay.queue_free()
	await tree.process_frame
	_gpu_verification_completed=true
	return 0 if results.passed else 1

func _new_view(boss: String, background: String, mode: String="test") -> void:
	await _open_view(mode,_definition_for("hero"),"appearance_"+boss)
	view.battle_background=background
	# Coverage deliberately chooses standard day/night rather than boss-specific artwork.
	view._world_battle.boss_backgrounds={}
	view._world_battle.background_convention="res://tools/no_background_%s.png"
	view._world_battle.update()
	var id:=_actor_id("hero")
	var safety:=0
	while view.session.pending_ally_id()!=id and safety<32:
		view.session.resolve_ally_action({"type":"defend"})
		safety+=1
	view._presenter.cancel()
	view.refresh()
	stage.impact.connect(func(_entry): impact_times.append(Time.get_ticks_usec()))
	stage.finished.connect(func(): finished_times.append(Time.get_ticks_usec()))
	for script in _hero_scripts():
		stage._presentation_warmup.ensure(script,"hero","")
	var waiting:=true
	while waiting:
		waiting=false
		for script in _hero_scripts():
			waiting=not stage._presentation_warmup.ensure(script,"hero","").is_empty() or waiting
		await _tree().process_frame
	await _tree().create_timer(0.35).timeout

func _case(action: String, setting: String, shots: bool) -> void:
	var title := {"baseline":"00  通常攻撃 / 現行・比較用", "attack":"01  通常攻撃 / 本番・無属性", "hero_slash":"02  単体攻撃 / 炎の一閃", "hero_blaze_all":"03  全体攻撃 / 横薙ぎ・1体に1命中", "hero_flame_wrap":"04  炎纏い / 身体から刀身へ", "hero_burst_slash":"05  高威力単体攻撃 / 立ち構え・炎纏いと同じ集炎"}
	label.text=title[action]
	sublabel.text=setting+"   |   実時間再生 / 構え → 命中 → 復帰"
	var battle: RBMBattle=view.session.battle
	var original:=battle.snapshot().duplicate(true)
	# A sandbox fixture grants SP only BEFORE resolving the actual action. Combat code stays byte-identical.
	for unit in battle.party:
		if unit.character_id=="hero": unit.sp=50 if not performance_mode and action in ["attack","baseline"] else 100
	var before:=battle.presentation_state().duplicate(true)
	stage.set_state(before)
	var request: Dictionary={"type":"attack"} if action in ["attack","baseline"] else {"type":"skill","skill_id":action}
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
	var hero_key:=str(_actor_id("hero"))
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
	results.cases.back()["audio_cues"]=stage._sound.history.duplicate()
	if performance_mode and (over33>0 or float(over20)/maxi(1,times.size())>0.02): results.errors.append("Frame budget: "+action+" / "+setting)
	if not performance_mode:await _tree().create_timer(0.4).timeout
	if not retain_result: battle.restore(original)
	var refresh_start:=Time.get_ticks_usec()
	view.refresh()
	results.cases.back()["idle_refresh_cpu_ms"]=(Time.get_ticks_usec()-refresh_start)/1000.0
	await _tree().process_frame

func _cancel_checks() -> void:
	var checks: Array=[]
	for key in ["attack","hero_slash","hero_blaze_all","hero_flame_wrap","hero_burst_slash"]:
		var skill: Dictionary={}
		for item in _master("hero").skills:
			if item.id==key: skill=item
		var entry: Dictionary={"actor":_actor_id("hero"),"action":"attack","target":"boss","amount":20} if key=="attack" else _skill_entry(_actor_id("hero"),skill)
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
	return entry

func _hero_scripts() -> Array:
	return [preload("res://src/bossmaker/visuals/rbm_hero_normal.gd"),preload("res://src/bossmaker/visuals/rbm_hero_slash.gd"),preload("res://src/bossmaker/visuals/rbm_hero_sweep.gd"),preload("res://src/bossmaker/visuals/rbm_hero_wrap.gd"),preload("res://src/bossmaker/visuals/rbm_hero_burst.gd")]

func _buff_sequence() -> void:
	retain_result=true
	await _case("hero_flame_wrap","炎纏い / 使用ターンを含む3ターン",false)
	await _flame_state("炎纏い後 / 待機中も刀に炎",true,1.5)
	await _next_hero()
	await _case("attack","強化2ターン目 / 移動・攻撃・復帰にも炎が追従",false)
	await _flame_state("通常攻撃後 / 強化が持続",true,0.7)
	await _next_hero()
	await _case("hero_burst_slash","強化3ターン目 / 同じ集炎から高威力の一撃",false)
	await _flame_state("3ターン目の行動後 / まだ効果中",true,0.9)
	await _next_hero()
	await _flame_state("4ターン目 / 攻撃力アップ終了・刀身も元へ",false,2.0)
	await _case("attack","強化終了後 / 元の通常攻撃",false)
	retain_result=false

func _next_hero() -> void:
	# Resolve intervening participants normally; only their review footage is omitted.
	# No turn/effect fields are written by this harness.
	var battle: RBMBattle=view.session.battle
	var hero:=_actor_id("hero")
	battle.advance_to_next_decision()
	var guard:=0
	while view.session.pending_ally_id()!=hero and not battle.battle_over and guard<40:
		battle.resolve_pending_ally_action({"type":"defend"})
		battle.advance_to_next_decision()
		guard+=1
	view.refresh()
	await _tree().process_frame
	if battle.battle_over: results.errors.append("Review fixture ended before buff expiry")

func _flame_state(title: String, expected: bool, hold: float) -> void:
	label.text=title
	sublabel.text="本番HUD / 他の参加者の行動は省略し、実際のターンを進行"
	var elapsed:=0.0
	var frames: Array[float]=[]
	var last:=Time.get_ticks_usec()
	while elapsed<hold:
		await _tree().process_frame
		var now:=Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		elapsed+=(now-last)/1000000.0
		last=now
	var actual: bool=preload("res://src/bossmaker/visuals/rbm_hero_flame.gd").is_active(stage._state,str(_actor_id("hero")))
	var visible_aura:=false
	for child in stage._visuals[str(_actor_id("hero"))].get_children():
		if child.get_script()==preload("res://src/bossmaker/visuals/rbm_hero_sword_aura.gd"): visible_aura=child.visible
	if actual!=expected or visible_aura!=expected: results.errors.append("Buff state mismatch: "+title)
	if not results.has("buff_checks"): results["buff_checks"]=[]
	results.buff_checks.append({"title":title,"turn":stage._state.turn,"expected":expected,"active":actual,"visible":visible_aura,"frame_ms":frames if performance_mode else [],"end_seconds":(Time.get_ticks_usec()-zero_time)/1000000.0})
