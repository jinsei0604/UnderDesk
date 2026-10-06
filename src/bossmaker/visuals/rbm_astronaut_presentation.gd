extends Node2D
## Plays resolved entries only. Combat still owns hits, guarding, counters and RNG.
const Timeline = preload("res://src/bossmaker/visuals/rbm_astronaut_timeline.gd")
const PixelLayer = preload("res://src/bossmaker/visuals/rbm_astronaut_pixel_layer.gd")
const Gravity = preload("res://src/bossmaker/visuals/rbm_astronaut_gravity.gdshader")
const Audio = preload("res://src/bossmaker/rbm_audio_catalog.gd")
var kind := "single"
var action_kind := "single"
var duration := 7.2
var impact_time := 3.27
var age := 0.0
var active := false
var awakened := false
var _stage: Control
var _layer: Node2D
var _vfx: Node2D
var _post: ColorRect
var _copy: BackBufferCopy
var _audio: AudioStreamPlayer
var _hit := false
var _reveal := false
var _boss_z := 1
var target := Vector2.ZERO
var center := Vector2.ZERO

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	awakened = str(stage._asset_ids.get("boss","")) == "astronaut_awakened"
	if kind == "support": kind = "heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	action_kind = kind
	if kind == "single" and awakened: action_kind = "planet"
	if kind == "aoe": action_kind = "blackhole" if awakened else "all"
	duration = Timeline.DURATIONS[action_kind]
	impact_time = Timeline.IMPACTS[action_kind]
	stage._playing = true
	stage._phase = "astronaut_"+action_kind
	stage._motion_offset = Vector2.ZERO
	if kind == "awakening": stage._awakened_appearance_applied = false
	for key in stage._counters: stage._counter_offsets[key] = Vector2.ZERO
	# Use all four current homes for a stable gravity center. A guarded single hit
	# instead uses the resolved recipient's actual cover destination.
	var count := 0
	var feet_center := Vector2.ZERO
	for key in stage._party_keys:
		var foot: Vector2 = stage._foot(key)
		feet_center += foot
		center += foot-Vector2(0,stage.Assets.display_height(str(stage._asset_ids[key]))*.35)
		count += 1
	if count > 0:
		feet_center /= count
		center /= count
	else:
		feet_center = stage.size*Vector2(.30,.72)
		center = feet_center-Vector2(0,36)
	target = feet_center
	if kind == "single" and not stage._targets.is_empty():
		var key: String = stage._targets[0]
		target = stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
	_boss_z = stage._visuals["boss"].z_index
	stage._visuals["boss"].z_index = 18
	_copy = BackBufferCopy.new()
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_copy.z_index = 15
	add_child(_copy)
	_post = ColorRect.new()
	_post.size = stage.size
	_post.z_index = 16
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material_instance := ShaderMaterial.new()
	material_instance.shader = Gravity
	_post.material = material_instance
	add_child(_post)
	_layer = PixelLayer.new()
	_layer.z_index = 17
	add_child(_layer)
	_layer.configure(stage.size)
	_vfx = _layer.effects
	_vfx.kind = action_kind
	_vfx.attack_attribute = str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_vfx.boss = stage._foot("boss")/_layer.unit
	_vfx.target = target/_layer.unit
	_vfx.center = center/_layer.unit
	for key in stage._targets:
		if key != "boss": _vfx.hit_points.append((stage._chest(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO)))/_layer.unit)
	if Audio.FILES.has("astronaut_"+action_kind):
		_audio = AudioStreamPlayer.new()
		_audio.stream = load(Audio.FILES["astronaut_"+action_kind])
		_audio.volume_db = -6
		add_child(_audio)
		stage._sound.history.append("astronaut_"+action_kind)
		if stage._sound.history.size() > 64: stage._sound.history.pop_front()
		stage.visibility_changed.connect(_visibility_changed)
		if not stage._sound.muted: _audio.play()
	if not stage._guards.is_empty(): stage._sound.play_sound("cover_move",-5)
	_advance(0)
	var tween := create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	if kind == "awakening":
		tween.tween_callback(stage._finish_awakening_entry)
		return tween
	if stage._samurai_finish:
		tween.tween_callback(_restore)
		var counter_duration: float = stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,counter_duration,counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore)
		tween.tween_method(stage._counter_progress,0.0,1.0,.20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage): return
	age = t
	if kind == "awakening" and t >= 6.45 and not _reveal:
		_reveal = true
		_stage._awakened_appearance_applied = true
		_stage._apply_awakened_appearance()
		awakened = true
	_stage._pose("boss",Timeline.pose(action_kind,t,awakened))
	var jolt := Timeline.shake(action_kind,t)
	_stage._visuals["boss"].position = _stage._homes["boss"]
	if action_kind != "blackhole": _stage._visuals["boss"].position -= (jolt*_layer.unit).round()
	_layer.picture.position = (-jolt*_layer.unit).round()
	_layer.advance(4.75 if action_kind=="blackhole" and 4.75<=t and t<4.86 else t)
	if action_kind == "awakening":
		_layer.cosmos.visible = true
		_layer.cosmos.material.set_shader_parameter("center",_vfx.boss-Vector2(0,75))
		_layer.cosmos.material.set_shader_parameter("reach",430.0)
		_layer.cosmos.material.set_shader_parameter("strength",smoothstep(1.5,5.7,t)*(1-smoothstep(6.6,10.7,t)))
	var mat := _post.material as ShaderMaterial
	# The gravity shader works in render-target pixels (SCREEN_UV/SCREEN_PIXEL_SIZE). Those are scaled by
	# the window stretch (canvas_items) but do not include the letterbox offset, which is only applied when
	# the target is shown in the window. Without the scale, any window larger than 1280x720 clamps the
	# lower/right part to the stage edge and repeats one row/column there.
	var stretch: Vector2 = _stage.get_viewport().get_final_transform().get_scale()
	var screen_xform: Transform2D = Transform2D.IDENTITY.scaled(stretch) * _stage.get_global_transform_with_canvas()
	var global_scale: Vector2 = screen_xform.get_scale()
	mat.set_shader_parameter("stage_origin",screen_xform.origin)
	mat.set_shader_parameter("stage_size",_stage.size*global_scale)
	mat.set_shader_parameter("unit",_layer.unit*global_scale.x)
	mat.set_shader_parameter("center",center*global_scale)
	var cutoff: float = lerpf(center.x,_stage._foot("boss").x,.62) if action_kind=="blackhole" else _stage.size.x+200
	mat.set_shader_parameter("cutoff",cutoff*global_scale.x)
	mat.set_shader_parameter("jolt",jolt*_layer.unit*global_scale)
	mat.set_shader_parameter("amount",Timeline.pull(t) if action_kind=="blackhole" else 0.0)
	mat.set_shader_parameter("seam",smoothstep(1.15,1.8,t)*(1-smoothstep(2.34,2.40,t)) if action_kind=="blackhole" else 0.0)
	mat.set_shader_parameter("fold",smoothstep(1.95,2.38,t) if action_kind=="blackhole" else 0.0)
	for key in _stage._guards:
		var progress := smoothstep(0,.5,t)*(1-smoothstep(duration-.5,duration,t))
		_stage._visuals[key].position = (Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	if t >= impact_time and not _hit and kind != "awakening":
		_hit = true
		_stage._strike()
		if not active or not is_instance_valid(_stage): return
	if kind in ["single","aoe"] and t >= impact_time:
		for key in _stage._targets:
			if _stage._guards.has(key): continue
			var reaction := t-impact_time
			_stage._visuals[key].position = _stage._homes[key]
			if reaction < .3:
				_stage._pose(key,10 if _stage._counters.has(key) else 11)
				_stage._visuals[key].position += Vector2(7*sin(reaction/.3*PI),0).round()
			else:
				var state: Dictionary = _stage._unit_state(key)
				_stage._pose(key,11 if state.get("is_downed",false) else (10 if state.get("is_defending",false) or _stage._counters.has(key) else 0))

func play_sound_phase(phase: String) -> bool:
	return not kind in ["buff","heal"] or phase != "impact"

func _visibility_changed() -> void:
	if is_instance_valid(_audio) and is_instance_valid(_stage):
		_audio.stream_paused = not _stage.is_visible_in_tree()

func _restore() -> void:
	if is_instance_valid(_stage):
		_stage._visuals["boss"].z_index = _boss_z
		_stage._visuals["boss"].position = _stage._homes["boss"]
	if is_instance_valid(_audio): _audio.stop()
	if is_instance_valid(_post): _post.visible = false
	if is_instance_valid(_copy): _copy.visible = false
	if is_instance_valid(_layer):
		_layer.visible = false
		_layer.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func stop() -> void:
	_restore()
	active = false
	visible = false
	_stage = null
