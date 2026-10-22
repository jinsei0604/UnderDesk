extends Node2D
## Butler-only authored sprite playback and deterministic effect primitives.
## Consumes resolved entries; never references battle/session/RNG or changes time scale.
const SHEET="res://assets_bossmaker/battle/butler/actions/butler_intermediates_v2.png"
const FX=preload("res://src/bossmaker/visuals/rbm_butler_fx.gd")
const CELLS=[Rect2(84,66,159,281),Rect2(396,66,145,281),Rect2(687,70,233,277),Rect2(1001,66,204,281),
	Rect2(80,354,141,279),Rect2(390,353,188,280),Rect2(663,357,257,276),Rect2(993,382,248,251),
	Rect2(60,630,170,307),Rect2(393,628,166,309),Rect2(616,672,313,265),Rect2(936,659,307,278),
	Rect2(78,944,141,272),Rect2(366,976,204,240),Rect2(670,974,261,242),Rect2(1019,946,149,270)]
const FEET=[Vector2(151,338),Vector2(471,338),Vector2(761,338),Vector2(1074,338),
	Vector2(148,625),Vector2(462,625),Vector2(751,625),Vector2(1071,625),
	Vector2(154,928),Vector2(479,928),Vector2(777,928),Vector2(1083,928),
	Vector2(151,1209),Vector2(445,1209),Vector2(757,1209),Vector2(1091,1209)]
const WATCHES=[Vector2(212,285),Vector2(511,184),Vector2(888,172),Vector2(1172,143),
	Vector2(188,490),Vector2(547,405),Vector2(890,456),Vector2(1217,462),
	Vector2(99,677),Vector2(431,674),Vector2(895,764),Vector2(1217,740),
	Vector2(165,1080),Vector2(542,1100),Vector2(899,1078),Vector2(1144,1081)]
# Keep the approved face at its exact original scale. A small sprite rig replaces
# only the generated head, preserving the original bitmap without writing to it.
const HEAD_CUTS=[Rect2(106,69,96,89),Rect2(433,70,94,90),Rect2(723,76,102,89),Rect2(1031,71,99,90),
	Rect2(102,362,98,91),Rect2(417,362,102,92),Rect2(710,365,101,94),Rect2(1060,387,99,92),
	Rect2(110,663,105,98),Rect2(437,664,99,102),Rect2(728,678,101,96),Rect2(1044,664,106,99),
	Rect2(102,950,99,96),Rect2(450,982,95,93),Rect2(750,981,96,92),Rect2(1042,955,104,94)]
const ORIGINAL_HEAD=Rect2(328,92,112,108)
var kind:="normal"
var duration:=0.68
var release_time:=0.24
var impact_time:=0.40
var poses: Array=[]
var cues: Array=[]
var age:=0.0
var active:=false
var _stage: Control
var _actor: Control
var _sheet: Texture2D
var _head: Texture2D
var _scale:=1.0
var _home:=Vector2.ZERO
var _foot:=Vector2.ZERO
var _target:=Vector2.ZERO
var _launch:=Vector2.ZERO
var _target_key:=""
var _frame:=-1
var _hit:=false
var _released:=false
var _played: Dictionary={}
var _shake:=Vector2.ZERO
var _world: Array[Control]=[]
var _recovered_amount:=0

static func warm_paths(_id: String, _kind: String) -> Array[String]:
	var paths: Array[String]=[SHEET]
	for pose in [0,6]: paths.append(RBMVisualAssets.frame_path("butler",pose))
	for key in ["neutral_staff_tap","neutral_impact_light","ice_cast","ice_move","ice_impact_light","ice_impact_heavy","heal_sp"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths

func play(stage: Control) -> Tween:
	_stage=stage
	_actor=stage._visuals[stage._actor]
	_sheet=load(SHEET)
	_head=RBMVisualAssets.texture("butler",0)
	_scale=RBMVisualAssets.display_height("butler")/264.0
	_home=stage._foot(stage._actor)
	_target_key=str(stage._targets[0])
	_target=stage._chest(_target_key)
	if kind=="gift":
		_target.y=minf(_target.y-18,stage.size.y-284)
		_recovered_amount=int(stage._entry.get("amount",0))
	_foot=_home
	active=true
	z_index=7
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing=true
	stage._phase="skill_specific"
	stage.visibility_changed.connect(_on_visibility_changed)
	for child in stage.get_children():
		if child is Control and child.name!="BattleEffects": _world.append(child)
	_advance(0.0)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	for node in _world:
		if is_instance_valid(node): node.position-=_shake
	age=t
	_actor.visible=false
	_foot=(_home+Vector2((0 if kind=="gift" else 2)*smoothstep(0.10,release_time,t)*(1-smoothstep(impact_time,duration-0.04,t)),0)).round()
	_frame=-1
	for pose in poses:
		if t>=float(pose[0]): _frame=int(pose[1])
	if _frame<0:
		_actor.visible=true
		_stage._pose(_stage._actor,6 if _frame==-2 else 0)
		_actor.position=(_foot-_actor.foot_position()).round()
	for cue in cues:
		if t>=float(cue[0]) and not _played.has(cue[1]):
			_played[cue[1]]=true
			_stage._sound.play_sound(str(cue[1]),float(cue[2]))
	if t>=release_time and not _released:
		_released=true
		_launch=_watch_position()
	if t>=impact_time and not _hit:
		_hit=true
		if kind!="gift":
			_stage._pose(_target_key,11)
			_stage._flash(_target_key)
		_stage.impact.emit(_stage._entry.duplicate(true))
	if _hit and t>=impact_time+0.13 and kind!="gift": _stage._pose(_target_key,0)
	_shake=Vector2.ZERO
	if kind=="storm" and t>=impact_time and t<impact_time+0.085:
		_shake=Vector2(2 if int((t-impact_time)*60)%2==0 else -2,0)*float(_stage.get_meta("presentation_shake_strength",1.0))
	for node in _world:
		if is_instance_valid(node): node.position+=_shake
	position=_shake
	if t>duration-0.075:
		for player in _stage._sound._players:
			if player.playing: player.volume_db=minf(player.volume_db,-16-35*smoothstep(duration-0.075,duration,t))
	queue_redraw()

func _watch_position() -> Vector2:
	return _foot+(WATCHES[_frame]-FEET[_frame])*_scale if _frame>=0 else _foot+Vector2(8,-58)

func _on_visibility_changed() -> void:
	if active and not _stage.is_visible_in_tree(): _stage.cancel()

func stop() -> void:
	active=false
	visible=false
	if is_instance_valid(_stage):
		if _stage.visibility_changed.is_connected(_on_visibility_changed): _stage.visibility_changed.disconnect(_on_visibility_changed)
		_stage._sound.stop_all()
	for node in _world:
		if is_instance_valid(node): node.position-=_shake
	_shake=Vector2.ZERO
	position=Vector2.ZERO
	if is_instance_valid(_actor): _actor.visible=true
	queue_redraw()

func _draw() -> void:
	if not active: return
	if _frame>=0:
		var cell: Rect2=CELLS[_frame]
		var cut: Rect2=HEAD_CUTS[_frame]
		for region in [Rect2(cell.position,Vector2(cell.size.x,cut.position.y-cell.position.y)),
			Rect2(Vector2(cell.position.x,cut.position.y),Vector2(cut.position.x-cell.position.x,cut.size.y)),
			Rect2(Vector2(cut.end.x,cut.position.y),Vector2(cell.end.x-cut.end.x,cut.size.y)),
			Rect2(Vector2(cell.position.x,cut.end.y),Vector2(cell.size.x,cell.end.y-cut.end.y))]:
			if region.has_area(): draw_texture_rect_region(_sheet,Rect2((_foot+(region.position-FEET[_frame])*_scale).round(),region.size*_scale),region)
		var anchor: Vector2=(_foot+(Vector2(cut.get_center().x,cut.end.y)-FEET[_frame])*_scale).round()
		var head_scale: float=_actor._pixel_scale
		draw_set_transform(anchor,0.10 if _frame in [13,14] else 0.0)
		draw_texture_rect_region(_head,Rect2(Vector2(-56,-108)*head_scale,ORIGINAL_HEAD.size*head_scale),ORIGINAL_HEAD)
		draw_set_transform(Vector2.ZERO)
	_draw_effect()

func _draw_effect() -> void:
	pass
