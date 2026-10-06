extends Node2D
## Replays resolved entries through the existing strike/counter/finish contract.
const Motion=preload("res://src/bossmaker/visuals/rbm_slime_motion.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_slime_vfx.gd")
var kind:="single"
var duration:=2.65
var impact_time:=.91
var age:=-1.0
var active:=false
var motion: RefCounted
var _stage: Control
var _vfx: Node2D
var _hit:=false
var _released:=false
var _scale:=Vector2.ONE
var _pivot:=Vector2.ZERO
var _boss_z:=1
var _boss_visible:=true
var _shake:=Vector2.ZERO

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	if kind=="support": kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	stage._playing=true
	stage._phase="slime_"+kind
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var boss: Control=stage._visuals["boss"]
	_scale=boss.scale
	_pivot=boss.pivot_offset
	_boss_z=boss.z_index
	_boss_visible=boss.visible
	boss.visible=false
	z_index=3
	motion=Motion.new()
	var aim: Vector2=stage._foot("boss")
	var feet: Array[Vector2]=[]
	for key in stage._targets:
		if key!="boss": feet.append(stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO)))
	if kind=="single":
		var key: String=stage._targets[0]
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		aim=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))-Vector2(0,height*.52)+Vector2(23,0)
	motion.configure(stage._foot("boss"),aim,feet)
	_vfx=VFX.new()
	_vfx.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_vfx.motion=motion
	_vfx.kind=kind
	_vfx.attack_attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_vfx.slime=stage.Assets.texture(str(stage._asset_ids["boss"]),0)
	_vfx.pixel_scale=boss._pixel_scale
	_vfx.feet=feet
	_vfx.prepare_particles()
	add_child(_vfx)
	_vfx.advance(0)
	stage._pose("boss",0)
	stage._play_se("cast")
	if not stage._guards.is_empty(): stage._sound.play_sound("cover_move",-5)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
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
	if not active or not is_instance_valid(_stage): return
	_clear_shake()
	age=t
	var render_time:=.925 if kind=="single" and t>=.91 and t<.96 else t
	_vfx.advance(render_time)
	for key in _stage._guards:
		var progress:=smoothstep(0,.50,t)*(1-smoothstep(1.90,2.52,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	var release_time:=.57 if kind=="single" else (.88 if kind=="aoe" else 1.12)
	if t>=release_time and not _released:
		_released=true
		_stage._play_se("release")
	if t>=impact_time and not _hit:
		_hit=true
		_stage._strike()
		if not active or not is_instance_valid(_stage): return
	if kind in ["single","aoe"]:
		for key in _stage._targets:
			if _stage._guards.has(key): continue
			var reaction:=t-impact_time
			_stage._visuals[key].position=_stage._homes[key]
			if reaction>=0 and reaction<.36:
				if _stage._counters.has(key): _stage._pose(key,10)
				else:
					_stage._pose(key,11)
					_stage._visuals[key].position+=Vector2(-10*sin(reaction/.36*PI),0).round()
			elif reaction>=.36:
				var unit: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if unit.get("is_downed",false) else (10 if unit.get("is_defending",false) or _stage._counters.has(key) else 0))
		# Same additive shake/undo pattern as the existing dedicated presentations.
		var shake_age:=t-impact_time
		if shake_age>=0 and shake_age<.19:
			_shake=(Vector2(sin(shake_age*113)*4,cos(shake_age*89)*2)*(1-shake_age/.19)).round()
			for visual in _stage._visuals.values(): visual.position+=_shake
			_vfx.position=_shake

func _clear_shake() -> void:
	if _shake!=Vector2.ZERO and is_instance_valid(_stage):
		for visual in _stage._visuals.values():
			if is_instance_valid(visual): visual.position-=_shake
	_shake=Vector2.ZERO
	if is_instance_valid(_vfx): _vfx.position=Vector2.ZERO

func _restore_transform() -> void:
	_clear_shake()
	if not is_instance_valid(_stage): return
	var boss: Control=_stage._visuals["boss"]
	boss.scale=_scale
	boss.pivot_offset=_pivot
	boss.z_index=_boss_z
	boss.visible=_boss_visible
	if is_instance_valid(_vfx): _vfx.visible=false

func stop() -> void:
	_restore_transform()
	active=false
	visible=false
	_stage=null
