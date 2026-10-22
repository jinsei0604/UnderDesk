extends Node2D
## Girl-only animation; resolved entries are read-only. No battle, RNG or resource writes.
const SHEET="res://assets_bossmaker/battle/healer/actions/healer_intermediates_v1.png"
const FX=preload("res://src/bossmaker/visuals/rbm_healer_fx.gd")
const CELLS=[Rect2(70,60,275,308),Rect2(428,60,220,308),Rect2(776,72,270,296),Rect2(1100,78,320,290),
	Rect2(78,408,230,306),Rect2(460,408,194,306),Rect2(788,412,194,302),Rect2(1134,408,250,306),
	Rect2(76,726,234,330),Rect2(400,742,302,314),Rect2(732,744,320,312),Rect2(1110,770,256,286)]
const FEET=[Vector2(210,356),Vector2(546,356),Vector2(873,356),Vector2(1216,356),
	Vector2(202,706),Vector2(554,706),Vector2(889,706),Vector2(1239,706),
	Vector2(212,1048),Vector2(552,1048),Vector2(886,1048),Vector2(1240,1048)]
const TIPS=[Vector2(110,212),Vector2(466,145),Vector2(1004,197),Vector2(1378,195),
	Vector2(117,520),Vector2(580,538),Vector2(916,550),Vector2(1249,548),
	Vector2(116,765),Vector2(439,780),Vector2(770,785),Vector2(1148,920)]
var kind:="normal"
var duration:=0.80
var release_time:=0.30
var impact_time:=0.43
var poses: Array=[]
var cues: Array=[]
var age:=0.0
var active:=false
var _stage: Control
var _actor: Control
var _sheet: Texture2D
var _scale:=82.0/292.0
var _home:=Vector2.ZERO
var _foot:=Vector2.ZERO
var _target:=Vector2.ZERO
var _launch:=Vector2.ZERO
var _target_key:=""
var _recipients: Array[Dictionary]=[]
var _frame:=-1
var _hit:=false
var _released:=false
var _played: Dictionary={}

static func warm_paths(_id: String,_kind: String) -> Array[String]:
	var paths: Array[String]=[SHEET,RBMVisualAssets.frame_path("healer",0)]
	for key in ["neutral_staff_tap","neutral_impact_light","heal_hp","heal_sp"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths

func play(stage: Control) -> Tween:
	_stage=stage
	_actor=stage._visuals[stage._actor]
	_sheet=load(SHEET)
	_home=stage._foot(stage._actor)
	_foot=_home
	if kind=="normal":
		_target_key=str(stage._targets[0])
		_target=stage._chest(_target_key)
	else:
		for key in stage._targets:
			var amount:=int(stage._entry.get("amount",0))
			if kind=="sp":
				var recovered: Dictionary=stage._entry.get("recovered",{})
				amount=int(recovered.get(key,recovered.get(int(key),0)))
			if amount<=0 or (kind=="sp" and key==stage._actor): continue
			var center: Vector2=stage._chest(key)
			center.y=minf(center.y-18,stage.size.y-292)
			_recipients.append({"key":key,"center":center,"amount":amount})
	active=true
	z_index=7
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing=true
	stage._phase="skill_specific"
	stage.visibility_changed.connect(_on_visibility_changed)
	_advance(0.0)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active:return
	age=t
	_actor.visible=false
	# Grounded gesture: no translation, bounce, stretching or mesh distortion.
	_foot=_home
	_frame=-1
	for pose in poses:
		if t>=float(pose[0]):_frame=int(pose[1])
	if _frame<0:
		_actor.visible=true
		_stage._pose(_stage._actor,0)
		_actor.position=(_home-_actor.foot_position()).round()
	for cue in cues:
		if t>=float(cue[0]) and not _played.has(cue[1]):
			_played[cue[1]]=true
			_stage._sound.play_sound(str(cue[1]),float(cue[2]))
	if t>=release_time and not _released:
		_released=true
		_launch=_wand_position()
	if t>=impact_time and not _hit:
		_hit=true
		if kind=="normal":
			_stage._pose(_target_key,11)
			_stage._flash(_target_key)
		_stage.impact.emit(_stage._entry.duplicate(true))
	if _hit and t>=impact_time+0.13 and kind=="normal":_stage._pose(_target_key,0)
	if t>duration-0.10:
		for player in _stage._sound._players:
			if player.playing:player.volume_db=minf(player.volume_db,-16-35*smoothstep(duration-0.10,duration,t))
	queue_redraw()

func _wand_position() -> Vector2:
	return _foot+(TIPS[_frame]-FEET[_frame])*_scale if _frame>=0 else _foot+Vector2(-29,-45)

func _on_visibility_changed() -> void:
	if active and not _stage.is_visible_in_tree():_stage.cancel()

func stop() -> void:
	active=false
	visible=false
	if is_instance_valid(_stage):
		if _stage.visibility_changed.is_connected(_on_visibility_changed):_stage.visibility_changed.disconnect(_on_visibility_changed)
		_stage._sound.stop_all()
	if is_instance_valid(_actor):_actor.visible=true
	queue_redraw()

func _draw() -> void:
	if not active:return
	if _frame>=0:
		var cell: Rect2=CELLS[_frame]
		draw_texture_rect_region(_sheet,Rect2((_foot+(cell.position-FEET[_frame])*_scale).round(),cell.size*_scale),cell)
	_draw_effect()

func _draw_effect() -> void:
	pass
