extends Node2D
## Visual adapter only: the battle has already resolved the entry. Never writes HP or RNG.
const Render=preload("res://src/bossmaker/visuals/plush/rbm_plush_v12_render.gd")
const Camera=preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const AudioCatalog=preload("res://src/bossmaker/rbm_audio_catalog.gd")
const SOUNDS=["neutral_blunt_swing","neutral_impact_light","neutral_impact_heavy","heal_hp","buff_atk","boss_move_heavy","boss_impact_mass","neutral_sword_swing","wind_cast","wind_burst"]
var kind:="single"
var form:="normal"
var action_kind:="single"
var duration:=2.6
var impact_time:=.933333
var age:=0.0
var active:=false
var _stage: Control
var _body: Control
var _hit:=false
var _revealed:=false
var _boss_visible:=true

static func warm_paths(_asset_id: String,_kind: String) -> Array[String]:
	var out: Array[String]=[]
	for f in ["poses.png","fx.png","aura-v5.png","aura-rest.png"]:out.append(Render.ROOT+f)
	for id in ["plush","plush_awakened"]:
		for i in range(12):out.append(RBMVisualAssets.frame_path(id,i))
		out.append(RBMVisualAssets.ROOT+id+"/hit.png")
	for key in SOUNDS:out.append(str(AudioCatalog.FILES[key]))
	out.append("res://src/bossmaker/visuals/plush/rbm_plush_space.gdshader")
	out.append_array(Render.new_paths())
	out.append_array(Render.extra_paths())
	return out

func play(stage: Control) -> Tween:
	_stage=stage;active=true
	form="awakened" if str(stage._asset_ids["boss"])=="plush_awakened" else "normal"
	if kind=="support":kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	action_kind="awakening" if kind=="awakening" else form+"_"+("all" if kind=="aoe" else kind)
	var clip:=action_kind.replace("_heal","_support").replace("_buff","_support")
	duration=Render.clip_duration(action_kind)
	impact_time=Render.clip_impact(action_kind)
	stage._playing=true;stage._phase="awakening" if kind=="awakening" else "plush_"+kind;stage._motion_offset=Vector2.ZERO
	if kind=="awakening":stage._awakened_appearance_applied=false
	for key in stage._counters:stage._counter_offsets[key]=Vector2.ZERO
	_boss_visible=stage._visuals["boss"].visible
	_body=Render.new();_body.production_stage=stage
	_body.home=stage._foot("boss")
	for key in stage._targets:
		if key!="boss":_body.HOMES[key]=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
	_body.camera=Camera.new();_body.camera.attach(stage)
	z_index=3;add_child(_body)
	stage._visuals["boss"].visible=false
	if not stage._guards.is_empty():stage._sound.play_sound("cover_move",-5)
	_advance(0)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	if kind=="awakening":
		tween.tween_callback(stage._finish_awakening_entry)
		return tween
	if stage._samurai_finish:
		tween.tween_callback(_restore_transform)
		var counter_duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,counter_duration,counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore_transform)
		tween.tween_method(stage._counter_progress,0.0,1.0,.20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):return
	age=t
	_body.show_action(action_kind,t)
	if kind=="awakening":
		if t>=impact_time and not _revealed:
			_revealed=true
			_stage._awakened_appearance_applied=true
			_stage._apply_awakened_appearance()
			_body.on_impact(action_kind)
		return
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.50,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	if t>=impact_time and not _hit:
		_hit=true
		_body.on_impact(action_kind)
		_stage._strike()
		if not active or not is_instance_valid(_stage):return
	if kind in ["single","aoe"]:
		for key in _stage._targets:
			if _stage._guards.has(key):continue
			var reaction:=t-impact_time
			_stage._visuals[key].position=_stage._homes[key]
			if reaction>=0 and reaction<.35:
				_stage._pose(key,10 if _stage._counters.has(key) else 11)
				if not _stage._counters.has(key):_stage._visuals[key].position+=Vector2(-sin(reaction/.35*PI)*(13 if form=="awakened" else 8),-sin(reaction/.35*PI)*3).round()
			elif reaction>=.35:
				var unit: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if unit.get("is_downed",false) else (10 if unit.get("is_defending",false) or _stage._counters.has(key) else 0))

	_body.update_actors()

func play_sound_phase(_phase: String) -> bool:
	# Approved sounds use the stage owner, including mute, voice cap and cancellation.
	return true

func _restore_transform() -> void:
	if is_instance_valid(_body):
		_body.cleanup_visuals()
		_body.audio.stop_all()
		_body.camera.reset()
		_body.visible=false
	if not is_instance_valid(_stage):return
	_stage._visuals["boss"].visible=_boss_visible
	_stage._visuals["boss"].position=_stage._homes["boss"]

func stop() -> void:
	_restore_transform()
	active=false;visible=false;_stage=null
