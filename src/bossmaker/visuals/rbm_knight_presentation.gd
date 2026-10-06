extends Node2D
## Shared knight playback plumbing; dedicated entry scripts select each timeline.
const Motion=preload("res://src/bossmaker/visuals/rbm_knight_motion.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_knight_vfx.gd")
var kind:="single"
var duration:=2.20
var impact_time:=Motion.SINGLE_HIT
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
var _pose_layer: Node2D
var _pose_index:=0

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	if kind=="support": kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	stage._playing=true
	stage._phase="knight_"+kind
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var boss: Control=stage._visuals["boss"]
	_scale=boss.scale
	_pivot=boss.pivot_offset
	_boss_z=boss.z_index
	_boss_visible=boss.visible
	boss.pivot_offset=boss.foot_position()
	boss.z_index=3
	z_index=3
	motion=Motion.new()
	var aim: Vector2=stage._foot("boss")
	var feet: Array[Vector2]=[]
	for key in stage._party_keys: feet.append(stage._foot(key))
	if kind=="single":
		var key: String=stage._targets[0]
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		aim=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))-Vector2(0,height*.55)+Vector2(6,0)
	motion.configure(stage._foot("boss"),aim,feet)
	_pose_layer=Node2D.new()
	_pose_layer.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_pose_layer.draw.connect(_draw_pose)
	add_child(_pose_layer)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i((stage.size/4).ceil())
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_vfx=VFX.new()
	_vfx.motion=motion
	_vfx.kind=kind
	_vfx.attack_attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	for key in stage._targets:
		if key!="boss": _vfx.feet.append(stage._foot(key))
	viewport.add_child(_vfx)
	var display:=Sprite2D.new()
	display.texture=viewport.get_texture()
	display.centered=false
	display.scale=Vector2(4,4)
	display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	stage._play_se("cast")
	if not stage._guards.is_empty(): stage._sound.play_sound("cover_move",-5)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	if stage._samurai_finish:
		tween.tween_callback(_restore_transform)
		var counter_duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,counter_duration,counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_method(stage._counter_progress,0.0,1.0,.20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	age=t
	var state: Dictionary=motion.sample(kind,t)
	var boss: Control=_stage._visuals["boss"]
	_stage._pose("boss",state.pose)
	boss.position=(Vector2(_stage._homes["boss"])+Vector2(state.foot)-motion.home).round()
	boss.scale=Vector2(-_scale.x if state.flip else _scale.x,_scale.y)
	for key in _stage._guards:
		var progress:=smoothstep(.0,.35,t)*(1-smoothstep(1.18,1.92,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	_update_pose_layer(int(state.pose))
	if t>=(.62 if kind=="aoe" else .42) and not _released:
		_released=true
		_stage._play_se("release")
	if t>=impact_time and not _hit:
		_hit=true
		_stage._strike()
	if kind in ["single","aoe"]:
		for key in _stage._targets:
			if _stage._guards.has(key): continue
			var reaction:=t-impact_time-(.08 if kind=="single" else 0.0)
			_stage._visuals[key].position=_stage._homes[key]
			if reaction>=0 and reaction<.42:
				if _stage._counters.has(key): _stage._pose(key,10)
				else:
					_stage._pose(key,11)
					_stage._visuals[key].position+=Vector2(-10*sin(reaction/.42*PI),-2*sin(reaction/.42*PI)).round()
			elif reaction>=.42:
				var unit: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if unit.get("is_downed",false) else (10 if unit.get("is_defending",false) or _stage._counters.has(key) else 0))
	_vfx.advance(t)

func _restore_transform() -> void:
	if not is_instance_valid(_stage): return
	var boss: Control=_stage._visuals["boss"]
	boss.scale=_scale
	boss.pivot_offset=_pivot
	boss.z_index=_boss_z
	boss.visible=_boss_visible
	if is_instance_valid(_pose_layer): _pose_layer.visible=false

func stop() -> void:
	_restore_transform()
	active=false
	visible=false
	_stage=null

func _update_pose_layer(pose: int) -> void:
	_pose_index=pose
	var composite:=kind=="aoe" and pose in [3,5]
	_stage._visuals["boss"].visible=false if composite else _boss_visible
	_pose_layer.visible=composite and _boss_visible
	_pose_layer.position=_stage._foot("boss").round()
	_pose_layer.queue_redraw()

func _pose_region(texture: Texture2D,source: Rect2,destination: Vector2) -> void:
	var origin:=(-Vector2(256,460)*Motion.SCALE).round()
	_pose_layer.draw_texture_rect_region(texture,Rect2(origin+destination*Motion.SCALE,source.size*Motion.SCALE),source)

func _draw_pose() -> void:
	if not active or not is_instance_valid(_stage): return
	var assets=_stage.Assets
	var id: String=_stage._asset_ids["boss"]
	var regions: Array
	var head_destination: Vector2
	if _pose_index==5:
		regions=[Rect2(0,0,512,175),Rect2(0,175,266,75),Rect2(328,175,184,75),Rect2(0,250,512,262)]
		head_destination=Vector2(266,175)
	else:
		regions=[Rect2(0,0,512,185),Rect2(0,185,226,77),Rect2(285,185,227,77),Rect2(0,262,512,250)]
		head_destination=Vector2(226,187)
	for area in regions: _pose_region(assets.texture(id,_pose_index),area,area.position)
	_pose_region(assets.texture(id,0),Rect2(263,143,62,75),head_destination)
