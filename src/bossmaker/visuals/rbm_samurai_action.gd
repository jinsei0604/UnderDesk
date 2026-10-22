extends Node2D
## Reads resolved events only. Motion is an authored body sequence on one fixed pixel scale.
const Body=preload("res://src/bossmaker/visuals/rbm_samurai_body.gd")
const FX=preload("res://src/bossmaker/visuals/rbm_samurai_fx.gd")
const Wind=preload("res://src/bossmaker/visuals/rbm_samurai_iai_wind.gd")
const SHEET=Body.SHEET
var kind:="normal"
var duration:=0.86
var release_time:=0.31
var impact_time:=0.35
var retreat_time:=0.48
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
var _frame:=0
var _hit:=false
var _played: Dictionary={}
var _start_stance:=false
var _wind_clock:=0.0

static func warm_paths(_id: String,_kind: String) -> Array[String]:
	var paths: Array[String]=[SHEET]
	for pose in [0,6,7,8,10]:paths.append(RBMVisualAssets.frame_path("samurai",pose))
	for key in ["neutral_sword_swing","neutral_impact_light","wind_swing","wind_move","wind_impact_light","wind_impact_heavy","wind_cast","buff_atk","guard_set"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths

func play(stage: Control) -> Tween:
	_stage=stage;_actor=stage._visuals[stage._actor];_sheet=load(SHEET)
	_home=stage._foot(stage._actor);_foot=_home
	_start_stance=Wind.is_active(stage._unit_state(stage._actor))
	_wind_clock=stage._samurai_stance.wind_clock
	if kind in ["normal","single","all"]:
		_target_key=str(stage._targets[0]);_target=stage._chest(_target_key)
		var contact_frame:=9 if kind=="all" else 6
		# Place the feet on the boss's ground plane. Aim at the height this actual
		# katana reaches, rather than lifting the entire body to an abstract chest.
		_target.y=stage._foot(_target_key).y-3+(Body.TIPS[contact_frame].y-Body.FEET[contact_frame].y)*Body.SCALE
		_land=_target-(Body.TIPS[contact_frame]-Body.FEET[contact_frame])*Body.SCALE
	else:_land=_home
	active=true;z_index=7;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	stage._playing=true;stage._phase="skill_specific"
	stage.visibility_changed.connect(_on_visibility_changed)
	if is_instance_valid(stage._samurai_stance):stage._samurai_stance.refresh()
	_advance(0.0)
	var tween:=create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active:return
	age=t;_actor.visible=false;_foot=_home;_frame=0
	for pose in poses:
		if t>=float(pose[0]):_frame=int(pose[1])
	if _start_stance:
		if t<0.04:_frame=18
		elif t<0.075:_frame=17
		elif t<0.10:_frame=16
	if kind in ["normal","single","all"]:
		var arrival:=release_time-0.07
		if t<retreat_time:
			var u:=smoothstep(0.065,arrival,t)
			_foot=_home.lerp(_land,u)+Vector2(0,-sin(u*PI)*5)
		else:
			var u:=smoothstep(retreat_time+0.045,duration-0.11,t)
			_foot=_land.lerp(_home,u)+Vector2(0,-sin(u*PI)*17)
		var charged:=float(_stage._unit_state(_stage._actor).get("next_attack_bonus_multiplier",1))>1
		if charged and t>duration-0.11:
			_frame=16
			if t>duration-0.065:_frame=17
			if t>duration-0.025:_frame=18
		elif t>duration-0.055:_frame=0
	for cue in cues:
		if t>=float(cue[0]) and not _played.has(cue[1]):
			_played[cue[1]]=true;_stage._sound.play_sound(str(cue[1]),float(cue[2]))
	if t>=impact_time and not _hit:
		_hit=true
		if kind in ["normal","single","all"]:
			_stage._pose(_target_key,11);_stage._flash(_target_key)
		_stage.impact.emit(_stage._entry.duplicate(true))
	if _hit and t>=impact_time+0.13 and kind in ["normal","single","all"]:_stage._pose(_target_key,0)
	if t>duration-0.10:
		for player in _stage._sound._players:
			if player.playing:player.volume_db=minf(player.volume_db,-16-35*smoothstep(duration-0.10,duration,t))
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
	var hand:=Body.hand(_frame,_foot);var tip:=Body.tip(_frame,_foot)
	var wind:=wind_strength()
	Wind.mantle(self,_foot,hand,tip,_wind_clock+age,wind,true)
	Body.draw_frame(self,_sheet,_frame,_foot)
	if kind in ["normal","single","all"]:FX.stroke(self,age,release_time,impact_time,kind,hand,tip,_target)
	else:FX.stance(self,age,impact_time,kind,_foot,hand,tip)
	Wind.mantle(self,_foot,hand,tip,_wind_clock+age,wind)
	if _start_stance and kind in ["normal","single","all"]:
		Wind.attack(self,hand,tip,_target,age,release_time,impact_time,kind=="all")
	elif wind>0:Wind.support(self,_foot,age,impact_time)

func wind_strength() -> float:
	if not active:return 0.0
	var charged:=Wind.is_active(_stage._unit_state(_stage._actor))
	if _start_stance:
		# Keep the consuming strike intact through impact, then let its wind go.
		return 1.0 if charged else 1-smoothstep(retreat_time,duration-0.02,age)
	if kind=="iai" and charged:return smoothstep(impact_time,impact_time+0.14,age)
	return 0.0
