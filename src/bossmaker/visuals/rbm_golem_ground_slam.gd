extends Node2D
## Approved golem AoE v2. Presentation of resolved entries only.
const VFX=preload("res://src/bossmaker/visuals/rbm_golem_ground_vfx.gd")
const HIT:=1.64
const DURATION:=4.12
var age:=-1.0
var active:=false
var _stage: Control
var _vfx: Node2D
var _display: Sprite2D
var _shake:=Vector2.ZERO
var _slammed:=false
var _hit:=false

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	stage._playing=true
	stage._phase="golem_ground_slam"
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var viewport:=SubViewport.new()
	viewport.size=Vector2i((stage.size/4).ceil())
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_vfx=VFX.new()
	var feet: Array[Vector2]=[]
	for key in stage._targets: feet.append(stage._foot(key))
	_vfx.configure(stage._foot("boss"),feet)
	_vfx.attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	viewport.add_child(_vfx)
	_display=Sprite2D.new()
	_display.texture=viewport.get_texture()
	_display.centered=false
	_display.scale=Vector2(4,4)
	_display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_display)
	var tween:=create_tween()
	if stage._samurai_finish:
		tween.tween_method(_advance,0.0,1.90,1.90)
		var duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(_counter_handoff,0.0,duration,duration)
	else:
		tween.tween_method(_advance,0.0,DURATION,DURATION)
		if not stage._counters.is_empty():
			tween.tween_method(stage._counter_progress,0.0,1.0,.20)
			tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	_clear_shake()
	age=t
	var pose:=4 if t<.72 else (5 if t<1.9 else (3 if t<2.18 else 0))
	_stage._pose("boss",pose)
	_stage._visuals["boss"].position=_stage._homes["boss"]
	if t>=.72 and not _slammed:
		_slammed=true
		_stage._sound.play_sound("neutral_impact_heavy",-5)
	if t>=HIT and not _hit:
		_hit=true
		_stage._strike()
	for key in _stage._targets:
		_stage._visuals[key].position=_stage._homes[key]
		var reaction:=t-HIT
		if reaction>=0 and reaction<.5:
			if _stage._counters.has(key):
				_stage._pose(key,10)
			else:
				_stage._pose(key,11)
				var direction: Vector2=(_stage._foot(key)-_vfx.center).normalized()
				_stage._visuals[key].position+=(direction*8*sin(reaction/.5*PI)).round()
		elif reaction>=.5:
			var state: Dictionary=_stage._unit_state(key)
			_stage._pose(key,11 if state.get("is_downed",false) else (10 if state.get("is_defending",false) else 0))
	_vfx.age=t
	_vfx.queue_redraw()
	if t>=.72 and t<.82:
		_shake=Vector2([2,-2,0][int((t-.72)*60)%3],0)
	elif t>=HIT and t<HIT+.20:
		var tick:=int((t-HIT)*60)
		_shake=Vector2([4,-4,2,-2,0][tick%5],[0,2,-2,0][tick%4])
	for visual in _stage._visuals.values(): visual.position+=_shake
	_display.position=_shake

func _counter_handoff(t: float) -> void:
	if not active: return
	_clear_shake()
	age=1.90+t
	_vfx.age=age
	_vfx.queue_redraw()
	_stage._samurai_finish_progress(t)

func _clear_shake() -> void:
	if is_instance_valid(_stage) and _shake!=Vector2.ZERO:
		for visual in _stage._visuals.values(): visual.position-=_shake
	_shake=Vector2.ZERO
	if is_instance_valid(_display): _display.position=Vector2.ZERO

func stop() -> void:
	_clear_shake()
	active=false
	visible=false
	_stage=null
