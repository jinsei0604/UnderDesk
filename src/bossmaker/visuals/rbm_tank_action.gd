extends Node2D
const Body=preload("res://src/bossmaker/visuals/rbm_tank_body.gd")
const FX=preload("res://src/bossmaker/visuals/rbm_tank_fx.gd")
var kind:="normal"
var duration:=1.04
var impact_time:=0.44
var release_time:=0.35
var retreat_time:=0.60
var poses: Array=[]
var cues: Array=[]
var age:=0.0
var active:=false
var _stage: Control
var _actor: Control
var _sheet: Texture2D
var _home:=Vector2.ZERO
var _foot:=Vector2.ZERO
var _land:=Vector2.ZERO
var _target:=Vector2.ZERO
var _target_key:="boss"
var _target_points: Array[Vector2]=[]
var _frame:=0
var _hit:=false
var _played: Dictionary={}
static func warm_paths(_id: String,_kind: String) -> Array[String]:
	var paths: Array[String]=[Body.SHEET]
	for pose in [0,3,6,7,8,10,11]:paths.append(RBMVisualAssets.frame_path("tank",pose))
	for key in ["neutral_blunt_swing","neutral_impact_light","neutral_impact_heavy","cover_move","guard_set","guard_hit"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths
func play(stage: Control) -> Tween:
	_stage=stage;_actor=stage._visuals[stage._actor];_sheet=load(Body.SHEET)
	_home=stage._foot(stage._actor);_foot=_home;_land=_home
	for key in stage._targets:_target_points.append(stage._foot(key))
	if kind in ["normal","smash"]:
		_target_key=str(stage._targets[0])
		var frame:=6 if kind=="normal" else 11
		var offset:=Body.head(frame,Vector2.ZERO)
		_land=stage._foot(_target_key)+Vector2(-offset.x-12,-2)
		_target=Body.head(frame,_land)
	elif kind=="cover":
		_target_key=str(stage._targets[0]);_land=stage._foot(_target_key)+Vector2(63,8)
	active=true;z_index=7;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing=true;stage._phase="skill_specific"
	stage.visibility_changed.connect(_on_visibility_changed)
	_advance(0.0)
	var tween:=create_tween();tween.tween_method(_advance,0.0,duration,duration);tween.tween_callback(stage._finish)
	return tween
func _advance(t: float) -> void:
	if not active:return
	age=t;_actor.visible=false;_foot=_home;_frame=0
	for pose in poses:
		if t>=float(pose[0]):_frame=int(pose[1])
	if kind in ["normal","smash","cover"]:
		var arrival:=release_time-.035
		if t<retreat_time:
			var u:=smoothstep(.065,arrival,t)
			_foot=_home.lerp(_land,u)+Vector2(0,-sin(u*PI)*4)
		else:
			var u:=smoothstep(retreat_time+.035,duration-.08,t)
			_foot=_land.lerp(_home,u)+Vector2(0,-sin(u*PI)*9)
	if t>duration-.045:_frame=0
	for cue in cues:
		if t>=float(cue[0]) and not _played.has(cue[1]):
			_played[cue[1]]=true;_stage._sound.play_sound(str(cue[1]),float(cue[2]))
	if t>=impact_time and not _hit:
		_hit=true
		if kind in ["normal","smash"]:_stage._pose(_target_key,11);_stage._flash(_target_key)
		_stage.impact.emit(_stage._entry.duplicate(true))
	if _hit and t>=impact_time+.14 and kind in ["normal","smash"]:_stage._pose(_target_key,0)
	if t>duration-.10:
		for player in _stage._sound._players:
			if player.playing:player.volume_db=minf(player.volume_db,-16-35*smoothstep(duration-.10,duration,t))
	queue_redraw()
func _on_visibility_changed() -> void:
	if active and not _stage.is_visible_in_tree():_stage.cancel()
func stop() -> void:
	active=false;visible=false
	if is_instance_valid(_stage):
		if _stage.visibility_changed.is_connected(_on_visibility_changed):_stage.visibility_changed.disconnect(_on_visibility_changed)
		_stage._sound.stop_all()
	if is_instance_valid(_actor):_actor.visible=true
	queue_redraw()
func _draw() -> void:
	if not active:return
	Body.draw_frame(self,_sheet,_frame,_foot)
	if kind in ["normal","smash"]:FX.strike(self,age,impact_time,Body.head(_frame,_foot),_target,kind=="smash")
	else:FX.support(self,age,impact_time,kind,_foot,_target_points)
