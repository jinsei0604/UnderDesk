extends Node2D
## Approved ghost timelines; shared stage owns resolved impacts, counters and cleanup.
const Motion=preload("res://src/bossmaker/visuals/rbm_ghost_motion.gd")
const Visual=preload("res://src/bossmaker/visuals/rbm_ghost_visual.gd")
var kind:="single"
var action_kind:="single"
var duration:=4.05
var impact_time:=Motion.SINGLE_HIT
var age:=-1.0
var active:=false
var motion: RefCounted
var _stage: Control
var _body: Node2D
var _hit:=false
var _released:=false
var _boss_visible:=true

## Read in the background once the boss is known (rbm_presentation_warmup.gd): the ghost body loads
## every pose frame when an attack starts.
static func warm_paths(_asset_id: String, _kind: String) -> Array[String]:
	var out: Array[String]=[]
	for i in range(RBMVisualAssets.POSE_COUNT): out.append(RBMVisualAssets.frame_path("ghost",i))
	return out

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	if kind=="support": kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	action_kind="all" if kind=="aoe" else kind
	impact_time={"single":Motion.SINGLE_HIT,"all":Motion.ALL_HIT,"buff":2.40,"heal":2.40}[action_kind]
	stage._playing=true
	stage._phase="ghost_"+action_kind
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var boss: Control=stage._visuals["boss"]
	_boss_visible=boss.visible
	z_index=3
	motion=Motion.new()
	var feet: Array[Vector2]=[]
	var hits: Array[Vector2]=[]
	for key in stage._targets:
		if key=="boss": continue
		var foot: Vector2=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		feet.append(foot)
		hits.append(foot-Vector2(0,height*.55))
	motion.configure(stage._foot("boss"),feet)
	_body=Visual.new()
	_body.kind=action_kind
	_body.attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_body.motion=motion
	_body.targets=hits
	add_child(_body)
	_body.configure(stage)
	boss.visible=false
	_advance(0)
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
	age=t
	_body.advance(t)
	var state: Dictionary=_body.state
	_stage._pose("boss",int(state.pose))
	_stage._visuals["boss"].position=(Vector2(_stage._homes["boss"])+Vector2(state.foot)-motion.home).round()
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.50,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	var release_time: float={"single":1.32,"all":1.04,"buff":.50,"heal":.50}[action_kind]
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
			if reaction>=0 and reaction<.30:
				if _stage._counters.has(key): _stage._pose(key,10)
				else:
					_stage._pose(key,11)
					_stage._visuals[key].position+=Vector2(7*sin(reaction/.30*PI),0).round()
			elif reaction>=.30:
				var unit: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if unit.get("is_downed",false) else (10 if unit.get("is_defending",false) or _stage._counters.has(key) else 0))

func _restore_transform() -> void:
	if not is_instance_valid(_stage): return
	_stage._visuals["boss"].visible=_boss_visible
	_stage._visuals["boss"].position=_stage._homes["boss"]
	_body.visible=false

func stop() -> void:
	_restore_transform()
	active=false
	visible=false
	_stage=null
