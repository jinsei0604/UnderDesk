extends Node2D
## Golem-specific choreography. Receives resolved logs, never changes combat/RNG.
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_golem_punch_vfx.gd")
const HIT:=.78
const STOP:=.10
const DURATION:=1.72
var age:=-1.0
var impact_attribute:="NEUTRAL"
var contact:=Vector2.ZERO
var endpoint:=Vector2.ZERO
var start:=Vector2.ZERO
var target_key:=""
var active:=false
var _stage: Control
var _vfx: Node2D
var _hit:=false
var _swing:=false
var _accent:=false
var _shake:=Vector2.ZERO
var _boss_z:=1

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	target_key=stage._targets[0]
	start=stage._foot("boss")
	# Aim at the shoulder/upper torso; keep the large golem above the bottom HUD.
	var target_height: float=stage.Assets.display_height(str(stage._asset_ids[target_key]))
	contact=stage._foot(target_key)-Vector2(0,target_height*.80)+Vector2(stage._guard_offsets.get(target_key,Vector2.ZERO))
	# Exact leading fist landmark in the existing attack PNG (pose 02).
	var pixel_scale: float=stage._visuals["boss"]._pixel_scale
	endpoint=contact-Vector2(40-256,280-460)*pixel_scale
	endpoint=endpoint.round()
	stage._motion_offset=endpoint-start
	if stage._samurai_finish:
		# This is the stationary ranged counter; no legacy melee lunge to undo.
		for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	_vfx=VFX.new()
	_vfx.contact=contact
	add_child(_vfx)
	_boss_z=stage._visuals["boss"].z_index
	stage._visuals["boss"].z_index=3
	stage._playing=true
	stage._phase="golem_punch"
	if not stage._guards.is_empty(): stage._sound.play_sound("cover_move",-5)
	var tween:=create_tween()
	if stage._samurai_finish:
		# Existing samurai sequence owns the reflected impact and return.
		tween.tween_method(_advance,0.0,1.10,1.10)
		tween.tween_callback(_counter_handoff)
		var duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,duration,duration)
	else:
		tween.tween_method(_advance,0.0,DURATION,DURATION)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	_clear_shake()
	age=t
	var foot:=start
	var pose:=0
	if t<.20:
		pose=1
		foot=start+Vector2(roundf(10*smoothstep(0,.2,t)),0)
	elif t<.40:
		pose=1
		foot=start+Vector2(10,0)
	elif t<.66:
		pose=1
		foot=(start+Vector2(10,0)).lerp(endpoint+Vector2(54,0),smoothstep(.40,.66,t)).round()
	elif t<HIT:
		pose=2
		foot=(endpoint+Vector2(54,0)).lerp(endpoint,(t-.66)/.12).round()
	elif t<1.10:
		pose=2
		foot=endpoint
	elif t<1.28:
		pose=3
		foot=endpoint
	elif t<DURATION:
		pose=1 if t<1.52 else 3
		foot=endpoint.lerp(start,smoothstep(1.28,DURATION,t)).round()
	_stage._pose("boss",pose)
	_stage._visuals["boss"].position=Vector2(_stage._homes["boss"])+foot-start
	var guard_progress:=smoothstep(.2,.66,t)*(1.0-smoothstep(1.28,DURATION,t))
	for key in _stage._guards:
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*guard_progress).round()
		_stage._pose(key,10)
	var target=_stage._visuals[target_key]
	if not _stage._guards.has(target_key): target.position=_stage._homes[target_key]
	if t>=HIT and not _hit:
		_hit=true
		_stage._sound.play_sound("neutral_impact_heavy",-3)
		if not _stage._guards.is_empty(): _stage._sound.play_sound("guard_hit",-5)
		if _stage._counters.is_empty(): _stage.impact.emit(_stage._entry.duplicate(true))
		else: _stage._pose(target_key,10)
	if t>=.66 and not _swing:
		_swing=true
		_stage._sound.play_sound("neutral_blunt_swing",-5)
	if t>=HIT+STOP and not _accent:
		_accent=true
		impact_attribute=str(_stage._skill.get("attribute",_stage._entry.get("attribute","NEUTRAL")))
		_vfx.impact_color=Palette.color_for(impact_attribute)
	if t>=HIT+STOP and _stage._counters.is_empty():
		var reaction:=t-HIT-STOP
		var amount:=smoothstep(0,.10,reaction)*(1.0-smoothstep(.20,.50,reaction))
		target.position.x-=roundf(12*amount)
		if t<1.30: _stage._pose(target_key,11)
	_vfx.age=t-HIT-STOP
	_vfx.queue_redraw()
	if t>=HIT+STOP and t<HIT+STOP+.18:
		var tick:=int((t-HIT-STOP)*60)
		_shake=Vector2([2,-2,1,-1,0,0][tick%6],0)
		for visual in _stage._visuals.values(): visual.position+=_shake
		_vfx.position=_shake

func _counter_handoff() -> void:
	_clear_shake()
	_vfx.visible=false

func _clear_shake() -> void:
	if _shake!=Vector2.ZERO and is_instance_valid(_stage):
		for visual in _stage._visuals.values(): visual.position-=_shake
	_shake=Vector2.ZERO
	if is_instance_valid(_vfx): _vfx.position=Vector2.ZERO

func stop() -> void:
	_clear_shake()
	active=false
	visible=false
	if is_instance_valid(_stage) and _stage._visuals.has("boss"): _stage._visuals["boss"].z_index=_boss_z
	_stage=null
