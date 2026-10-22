extends "res://src/bossmaker/visuals/rbm_hero_action.gd"
## Approved hero finisher: upright sword charge, blade release, focused fire eruption.
const FinishFX=preload("res://src/bossmaker/visuals/rbm_hero_burst_vfx.gd")
var _fire: Node2D
var _played: Dictionary={}
var _launch:=Vector2.ZERO

func _init() -> void:
	kind="burst"
	duration=3.08
	impact_time=1.63
	release_time=0.62
	return_time=2.7

static func warm_paths(asset_id: String, action_kind: String) -> Array[String]:
	var paths: Array[String]=preload("res://src/bossmaker/visuals/rbm_hero_action.gd").warm_paths(asset_id,action_kind)
	for key in ["fire_move","fire_burst"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths

func play(stage: Control) -> Tween:
	_fire=FinishFX.new()
	_fire.z_index=1
	add_child(_fire)
	return super.play(stage)

func _cue(at: float,key: String,gain: float) -> void:
	if age>=at and not _played.has(key):
		_played[key]=true
		_stage._sound.play_sound(key,gain)

func _advance(t: float) -> void:
	if not active:return
	for node in _shake_nodes:
		if is_instance_valid(node):node.position-=_shake
	age=t
	_update_motion()
	_cue(0.16,"fire_cast",-5)
	_cue(0.62,"fire_swing",-1)
	_cue(0.90,"fire_impact_light",-8)
	_cue(1.00,"fire_move",-6)
	_cue(impact_time,"fire_burst",0)
	_cue(impact_time,"fire_impact_heavy",-4)
	if t>=release_time and not _release:
		_release=true
		_launch=_sword_tip()
	_fire.canvas_size=_stage.size
	_fire.floor_point=_stage._foot("boss")
	_fire.launch_point=_launch
	_fire.target_point=_target
	_fire.age=-1.0
	_fire.flight=-1.0
	if t>=release_time and t<0.90:
		_fire.flight=smoothstep(release_time,0.90,t)
	elif t>=0.90:
		# Hold the visible eruption peak for 0.10 s without changing the game clock.
		_fire.age=t-0.90 if t<impact_time else (0.73 if t<impact_time+0.10 else t-1.0)
	if t>=impact_time and not _hit:
		_hit=true
		_stage._pose("boss",11)
		_stage._flash("boss")
		_stage.impact.emit(_stage._entry.duplicate(true))
	if t>impact_time+0.23:_stage._pose("boss",0)
	if t>=0.60 and t<0.84:
		_trail.append({"tip":_sword_tip(),"hand":_sword_hand(),"time":t})
	while not _trail.is_empty() and t-float(_trail[0].time)>0.16:_trail.pop_front()
	var force:=0.0
	if t>=impact_time and t<impact_time+0.25:
		force=4.0*(1.0-smoothstep(impact_time+0.05,impact_time+0.25,t))
	_shake=(Vector2(sin(t*141),cos(t*167))*force*float(_stage.get_meta("presentation_shake_strength",1.0))).snapped(Vector2(2,2))
	for node in _shake_nodes:
		if is_instance_valid(node):node.position+=_shake
	position=_shake
	if t>duration-0.12:
		for player in _stage._sound._players:
			if player.playing:player.volume_db=minf(player.volume_db,-12-42*smoothstep(duration-0.12,duration,t))
	_fire.queue_redraw()
	queue_redraw()

func _update_motion() -> void:
	_actor.visible=false
	var step:=smoothstep(0.50,0.67,age)*(1-smoothstep(0.87,1.12,age))
	_foot=(_home+Vector2(8*step,0)).round()
	if age<0.12:_original(0)
	elif age<0.50:_frame=12
	elif age<0.62:_frame=5
	elif age<0.69:_frame=6
	elif age<0.84:_frame=7
	elif age<1.04:_frame=15
	else:_original(0)

func _draw_impact() -> void:
	pass # The dedicated fire layer owns the impact silhouette.

func _gather_age() -> float:
	return remap(age,0.12,0.76,0.23,0.94)

func _buff_flame_strength() -> float:
	var charge := _gather_age()
	return 1.0-smoothstep(0.23,0.40,charge)*(1.0-smoothstep(0.75,0.94,charge))

func _draw() -> void:
	super._draw()
	if active and age>=0.12 and age<=0.76:
		Flame.draw_gather(self,_gather_age(),_home,_sword_hand(),_sword_tip())
