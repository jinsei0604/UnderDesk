extends Node2D
## Resolved-entry playback only. Multiple visual bullets produce one combat impact.
const Motion=preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const Vfx=preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")
const Smoke=preload("res://src/bossmaker/visuals/rbm_gentleman_smoke.gdshader")
const Audio=preload("res://src/bossmaker/rbm_audio_catalog.gd")
var kind := "single"
var action_kind := "single"
var duration := 6.0
var impact_time := 2.79
var age := 0.0
var active := false
var awakened := false
var target := Vector2.ZERO
var _stage: Control
var _viewport: SubViewport
var _picture: TextureRect
var _vfx: Node2D
var _smoke: ColorRect
var _audio: AudioStreamPlayer
var _unit := 160.0/94.0
var _hit := false
var _reveal := false
var _boss_visible := true
var _restored := false

func is_gentleman() -> bool:return true

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	awakened=str(stage._asset_ids.get("boss",""))=="gentleman_awakened"
	if kind=="support":kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	action_kind=("awakened_single" if awakened else "single") if kind=="single" else (("awakened_all" if awakened else "all") if kind=="aoe" else kind)
	var data:=Motion.clip(action_kind)
	duration=float(data.duration);impact_time=float(data.impact)
	stage._playing=true;stage._phase="gentleman_"+action_kind
	stage._motion_offset=Vector2.ZERO
	if kind=="awakening":stage._awakened_appearance_applied=false
	for key in stage._counters:stage._counter_offsets[key]=Vector2.ZERO
	_boss_visible=stage._visuals.boss.visible
	stage._visuals.boss.visible=false
	z_index=17
	_viewport=SubViewport.new()
	_viewport.size=Vector2i(ceil(stage.size.x/_unit),ceil(stage.size.y/_unit))
	_viewport.transparent_bg=true;_viewport.disable_3d=true;_viewport.gui_disable_input=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_smoke=ColorRect.new()
	_smoke.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_smoke.material=ShaderMaterial.new();_smoke.material.shader=Smoke
	_viewport.add_child(_smoke)
	_vfx=Vfx.new();_vfx.kind=action_kind;_vfx.data=data;_vfx.awakened=awakened
	_vfx.canvas_size=Vector2(_viewport.size)
	_vfx.attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_vfx.boss=stage._foot("boss")/_unit
	for key in stage._party_keys:_vfx.party_feet.append(stage._foot(key)/_unit)
	for key in stage._targets:
		if key=="boss":continue
		var foot: Vector2=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		_vfx.feet.append(foot/_unit);_vfx.points.append((foot-Vector2(0,height*.57))/_unit)
	target=stage._foot("boss")
	if not _vfx.feet.is_empty():target=_vfx.feet[0]*_unit
	_vfx.target=target/_unit
	_viewport.add_child(_vfx)
	_picture=TextureRect.new();_picture.texture=_viewport.get_texture()
	_picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_picture.size=Vector2(_viewport.size)*_unit
	add_child(_picture)
	var sound_key: String="gentleman_"+action_kind
	_audio=AudioStreamPlayer.new();_audio.stream=load(Audio.FILES[sound_key]);_audio.volume_db=-6
	add_child(_audio)
	stage._sound.history.append(sound_key)
	if stage._sound.history.size()>64:stage._sound.history.pop_front()
	stage.visibility_changed.connect(_visibility_changed)
	if not stage._sound.muted:_audio.play()
	if not stage._guards.is_empty():stage._sound.play_sound("cover_move",-5)
	_advance(0)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	if kind=="awakening":
		tween.tween_callback(stage._finish_awakening_entry)
		return tween
	if stage._samurai_finish:
		tween.tween_callback(_restore)
		var counter_duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,counter_duration,counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore)
		tween.tween_method(stage._counter_progress,0.0,1.0,.20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):return
	age=t
	if kind=="awakening" and t>=impact_time and not _reveal:
		_reveal=true;_stage._awakened_appearance_applied=true
		_stage._apply_awakened_appearance();awakened=true
	_vfx.age=t;_vfx.queue_redraw()
	_smoke.position=(_vfx.boss-Vector2(70,151)).round();_smoke.size=Vector2(140,180)
	_smoke.visible=awakened or (kind=="awakening" and t>7.9)
	var power: float=1.3 if awakened else 0.0
	if kind=="awakening":power=smoothstep(7.9,8.45,t)*(1+.9*(1-smoothstep(8.7,10.2,t)))
	_smoke.material.set_shader_parameter("age",t);_smoke.material.set_shader_parameter("power",power)
	var shock:=0.0
	var dt:=t-impact_time
	if dt>=0 and dt<.65:shock=(7 if kind=="aoe" else 3)*exp(-dt*7)
	if kind=="awakening" and t<impact_time:shock=smoothstep(5.5,8.08,t)*3
	_picture.position=(Vector2(sin(t*83),sin(t*119)*.58)*shock*_unit).round()
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.5,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	if t>=impact_time and not _hit and kind!="awakening":
		_hit=true;_stage._strike()
		if not active or not is_instance_valid(_stage):return
	if kind in ["single","aoe"] and dt>=0:
		for key in _stage._targets:
			if _stage._guards.has(key):continue
			_stage._visuals[key].position=_stage._homes[key]
			if dt<.30:
				_stage._pose(key,10 if _stage._counters.has(key) else 11)
				_stage._visuals[key].position+=Vector2(7*sin(dt/.30*PI),0).round()
			else:
				var state: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if state.get("is_downed",false) else (10 if state.get("is_defending",false) or _stage._counters.has(key) else 0))

func play_sound_phase(_phase: String) -> bool:return true
func _visibility_changed() -> void:
	if is_instance_valid(_audio) and is_instance_valid(_stage):_audio.stream_paused=not _stage.is_visible_in_tree()
func _restore() -> void:
	if _restored:return
	_restored=true
	if is_instance_valid(_stage):
		_stage._visuals.boss.visible=_boss_visible
		_stage._visuals.boss.position=_stage._homes.boss
		if _stage.visibility_changed.is_connected(_visibility_changed):_stage.visibility_changed.disconnect(_visibility_changed)
	if is_instance_valid(_audio):_audio.stop()
	if is_instance_valid(_picture):_picture.visible=false
	if is_instance_valid(_viewport):_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
func stop() -> void:
	_restore();active=false;visible=false;_stage=null
