extends Node2D
## Presentation-only primitives. Hero action scripts author their timing separately.
const Flame = preload("res://src/bossmaker/visuals/rbm_hero_flame.gd")
## No RNG, battle/session/unit reference, time scale, sprite stretching or shared asset writes.
const SHEET_PATH = "res://assets_bossmaker/battle/hero/actions/hero_intermediates_v1.png"
const RETURN_PATH = "res://assets_bossmaker/battle/hero/actions/hero_retreat_v2.png"
const RETURN_CELLS = [Rect2(163,72,522,402),Rect2(962,72,513,404),Rect2(350,551,455,420),Rect2(901,550,374,422)]
const RETURN_PIVOTS = [Vector2(493,464),Vector2(1100,464),Vector2(488,959),Vector2(1098,962)]
const RETURN_SCALE := 0.25
const RETURN_HANDS = [Vector2(431,335),Vector2(1040,335),Vector2(425,820),Vector2(1007,822)]
const RETURN_TIPS = [Vector2(549,438),Vector2(1156,438),Vector2(537,927),Vector2(917,927)]
const CELLS = [
	Rect2(33,45,273,265),Rect2(351,48,246,264),Rect2(657,48,270,264),Rect2(997,48,244,264),
	Rect2(32,348,251,282),Rect2(347,327,240,303),Rect2(617,348,357,282),Rect2(984,397,251,238),
	Rect2(8,663,329,244),Rect2(368,636,229,275),Rect2(649,668,340,240),Rect2(983,662,272,250),
	Rect2(58,906,203,309),Rect2(335,977,228,239),Rect2(632,898,285,318),Rect2(983,940,204,276),
]
const PIVOTS = [Vector2(214,305),Vector2(505,305),Vector2(829,305),Vector2(1157,305),
	Vector2(159,623),Vector2(492,622),Vector2(773,623),Vector2(1129,627),
	Vector2(185,899),Vector2(510,903),Vector2(771,900),Vector2(1130,904),
	Vector2(166,1207),Vector2(464,1208),Vector2(778,1208),Vector2(1090,1208)]
const HANDS = {0:Vector2(113,197),1:Vector2(450,201),2:Vector2(744,201),3:Vector2(1085,201),4:Vector2(70,411),5:Vector2(439,416),6:Vector2(850,434),7:Vector2(1149,553),8:Vector2(135,748),9:Vector2(470,740),10:Vector2(850,760),11:Vector2(1150,793),12:Vector2(170,1040),14:Vector2(731,1047),15:Vector2(1128,1052)}
const TIPS = {0:Vector2(46,262),1:Vector2(376,262),2:Vector2(674,262),3:Vector2(1019,262),4:Vector2(156,362),5:Vector2(507,338),6:Vector2(962,363),7:Vector2(1220,622),8:Vector2(20,741),9:Vector2(435,650),10:Vector2(975,757),11:Vector2(1240,874),12:Vector2(168,919),14:Vector2(731,912),15:Vector2(1135,954)}
const PIXEL_SCALE := 0.4
var kind := "normal"
var duration := 0.78
var impact_time := 0.31
var release_time := 0.245
var return_time := 0.44
var age := 0.0
var active := false
var _stage: Control
var _actor: Control
var _sheet: Texture2D
var _return_sheet: Texture2D
var _home := Vector2.ZERO
var _foot := Vector2.ZERO
var _land := Vector2.ZERO
var _target := Vector2.ZERO
var _frame := -1
var _hit := false
var _release := false
var _cast := false
var _last_tip := Vector2.ZERO
var _trail: Array[Dictionary] = []
var _shake_nodes: Array[CanvasItem] = []
var _shake_homes: Array[Vector2] = []
var _shake := Vector2.ZERO

static func warm_paths(_asset_id: String, _kind: String) -> Array[String]:
	var paths: Array[String] = [SHEET_PATH,RETURN_PATH]
	for pose in [0,1,3,6,7]: paths.append(RBMVisualAssets.frame_path("hero", pose))
	for key in ["neutral_sword_swing","neutral_impact_light","fire_swing","fire_cast","fire_impact_light","fire_impact_heavy","buff_atk"]:
		paths.append(str(preload("res://src/bossmaker/rbm_audio_catalog.gd").FILES[key]))
	return paths

func play(stage: Control) -> Tween:
	_stage = stage
	stage.visibility_changed.connect(_on_stage_visibility_changed)
	_actor = stage._visuals[stage._actor]
	_sheet = load(SHEET_PATH)
	_return_sheet = load(RETURN_PATH)
	_home = stage._foot(stage._actor)
	_target = stage._chest("boss") if stage._visuals.has("boss") else _home + Vector2(260,-90)
	# Land close enough for the real blade to contact the boss silhouette, outside the HUD.
	_land = Vector2(_target.x-66, clampf(_target.y+78,minf(400,stage.size.y-100),minf(500,stage.size.y-12)))
	if kind == "wrap": _land = _home
	_foot = _home
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 7
	active = true
	stage._playing = true
	stage._phase = "skill_specific"
	for node in stage.get_children():
		if node is Control and node != self and node.name != "BattleEffects":
			_shake_nodes.append(node)
			_shake_homes.append(node.position)
	_advance(0.0)
	var tween := create_tween()
	tween.tween_method(_advance,0.0,duration,duration)
	tween.tween_callback(stage._finish)
	return tween

func _advance(t: float) -> void:
	if not active: return
	for node in _shake_nodes:
		if is_instance_valid(node): node.position-=_shake
	age = t
	_update_motion()
	if t >= release_time and not _release:
		_release = true
		_stage._sound.play_sound("neutral_sword_swing" if kind == "normal" else ("fire_cast" if kind == "wrap" else "fire_swing"),-2 if kind == "normal" else (0 if kind=="wrap" else -4))
	if kind != "normal" and kind != "wrap" and t >= release_time+0.033 and not _cast:
		_cast = true
		# A quiet ignition follows the physical swing, never precedes it.
		_stage._sound.play_sound("fire_cast",-13)
	if t >= impact_time and not _hit:
		_hit = true
		var cue := "buff_atk" if kind == "wrap" else ("neutral_impact_light" if kind == "normal" else ("fire_impact_heavy" if kind == "sweep" else "fire_impact_light"))
		_stage._sound.play_sound(cue,2 if kind=="wrap" else (0 if kind=="sweep" else (-2 if kind=="slash" else -4)))
		if kind != "wrap":
			_stage._pose("boss",11)
			_stage._flash("boss")
		_stage.impact.emit(_stage._entry.duplicate(true))
	if _hit and t > impact_time+0.14 and kind != "wrap": _stage._pose("boss",0)
	var tip := _sword_tip()
	if _frame in [5,6,7,9,10,11] and t >= release_time and t < impact_time+0.075:
		_trail.append({"tip":tip,"hand":_sword_hand(),"time":t})
	while not _trail.is_empty() and t-float(_trail[0]["time"])>0.115: _trail.pop_front()
	# Optional 2px world-only shake: all stage content and background move together; HUD stays fixed.
	var offset := Vector2.ZERO
	if kind == "sweep" and t >= impact_time and t < impact_time+0.10:
		var strength: float = float(_stage.get_meta("presentation_shake_strength",1.0))
		offset = Vector2(2 if int((t-impact_time)*60)%2 == 0 else -2,0)*strength
	for node in _shake_nodes:
		if is_instance_valid(node): node.position+=offset
	_shake=offset
	position = offset
	# End/cancel releases every voice; short fade preserves the natural tail at a normal finish.
	if t>duration-0.08:
		for player in _stage._sound._players:
			if player.playing: player.volume_db=minf(player.volume_db,-13.0-42.0*smoothstep(duration-0.08,duration,t))
	queue_redraw()

func _update_motion() -> void:
	_actor.visible = false
	if kind == "wrap":
		_foot = _home
		if age < 0.09: _original(0)
		elif age < 0.23: _original(6)
		elif age < 0.59: _frame = 12
		elif age < 0.83: _frame = 14
		elif age < 0.95: _frame = 15
		else: _original(0)
		return
	var arrival := release_time-0.06
	if age < 0.05:
		_foot = _home+Vector2(-3*smoothstep(0,0.05,age),0)
		_original(1 if age>0.025 else 0)
	elif age < arrival:
		var u := clampf((age-0.05)/(arrival-0.05),0,1)
		_foot = (_home+Vector2(-3,0)).lerp(_land,pow(u,1.35))
		_foot.y -= sin(u*PI)*5
		_frame = [0,1,2,3][mini(3,int(u*4))]
	elif age < release_time:
		_foot = _land+Vector2(-4*(1-smoothstep(arrival,release_time,age)),0)
		_frame = 8 if kind == "sweep" else 4
	elif age < impact_time-0.025:
		_foot = _land
		_frame = 9 if kind == "sweep" else 5
	elif age < impact_time+(0.055 if kind=="sweep" else 0.0):
		_foot = _land+Vector2(3,0)
		_frame = 10 if kind == "sweep" else 6
	elif age < return_time:
		_foot = _land+Vector2(3,0)
		_frame = 11 if kind == "sweep" else 7
	elif age < duration-0.055:
		var u := clampf((age-return_time)/(duration-0.055-return_time),0,1)
		# A distinct backward bound, not reversed footage or an equal-speed slide.
		_foot = (_land+Vector2(3,0)).lerp(_home,smoothstep(0,1,u))
		_foot.y -= sin(u*PI)*13
		_frame = 16 if u<0.18 else (17 if u<0.67 else 18)
	else:
		_foot = _home
		if age<duration-0.027: _frame=19
		else: _original(0)
	_foot = _foot.round()

func _original(pose: int) -> void:
	_frame = -1
	_actor.visible = true
	_stage._pose(_stage._actor,pose)
	# Source poses retain exactly their original scale and origin.
	_actor.position = _foot-_actor.foot_position()

func _sword_tip() -> Vector2:
	if _frame>=16: return _foot+(RETURN_TIPS[_frame-16]-RETURN_PIVOTS[_frame-16])*RETURN_SCALE
	return _foot+(Vector2(TIPS.get(_frame,Vector2.ZERO))-PIVOTS[_frame])*PIXEL_SCALE if _frame>=0 and TIPS.has(_frame) else _foot+Vector2(10,-100)

func _sword_hand() -> Vector2:
	if _frame>=16: return _foot+(RETURN_HANDS[_frame-16]-RETURN_PIVOTS[_frame-16])*RETURN_SCALE
	return _foot+(Vector2(HANDS.get(_frame,Vector2.ZERO))-PIVOTS[_frame])*PIXEL_SCALE if _frame>=0 and HANDS.has(_frame) else _foot+Vector2(10,-55)

func _on_stage_visibility_changed() -> void:
	if active and not _stage.is_visible_in_tree(): _stage.cancel()

func stop() -> void:
	active = false
	if is_instance_valid(_stage) and _stage.visibility_changed.is_connected(_on_stage_visibility_changed):
		_stage.visibility_changed.disconnect(_on_stage_visibility_changed)
	visible = false
	_trail.clear()
	if is_instance_valid(_actor): _actor.visible = true
	for node in _shake_nodes:
		if is_instance_valid(node): node.position-=_shake
	_shake=Vector2.ZERO
	position = Vector2.ZERO
	if is_instance_valid(_stage): _stage._sound.stop_all()
	queue_redraw()

func _draw() -> void:
	if not active: return
	for i in range(1,_trail.size()):
		var a: Dictionary = _trail[i-1]
		var b: Dictionary = _trail[i]
		if kind!="normal" and age-float(b.time)<0.028:continue
		var alpha := (1.0-clampf((age-float(b.time))/0.115,0,1))*0.75
		_draw_ribbon(a,b,alpha)
	if _frame>=16:
		var idx:=_frame-16
		var r: Rect2=RETURN_CELLS[idx]
		draw_texture_rect_region(_return_sheet,Rect2((_foot+(r.position-RETURN_PIVOTS[idx])*RETURN_SCALE).round(),r.size*RETURN_SCALE),r)
	elif _frame>=0:
		var r: Rect2 = CELLS[_frame]
		draw_texture_rect_region(_sheet,Rect2((_foot+(r.position-PIVOTS[_frame])*PIXEL_SCALE).round(),r.size*PIXEL_SCALE),r)
	if _frame>=0 and Flame.is_active(_stage._state,_stage._actor):
		Flame.draw_blade(self,_sword_hand(),_sword_tip(),float(Time.get_ticks_msec())/1000.0,_buff_flame_strength())
	if kind == "wrap":
		_draw_wrap()
	elif _hit:
		_draw_impact()

func _draw_ribbon(a: Dictionary,b: Dictionary,alpha: float) -> void:
	var va: Vector2=Vector2(a.tip)-Vector2(a.hand)
	var vb: Vector2=Vector2(b.tip)-Vector2(b.hand)
	if Vector2(a.tip).distance_to(Vector2(b.tip))<1:return
	var color := Color(0.8,0.89,0.98,alpha*0.65) if kind=="normal" else Color(1,0.32,0.035,alpha*0.85)
	var width:=8.0 if kind=="normal" else 13.0
	for i in 6:
		var u:=float(i)/6.0
		var v:=float(i+1)/6.0
		var pa: Vector2=Vector2(a.hand).lerp(Vector2(b.hand),u)
		var pb: Vector2=Vector2(a.hand).lerp(Vector2(b.hand),v)
		var da:=Vector2.from_angle(lerp_angle(va.angle(),vb.angle(),u))
		var db:=Vector2.from_angle(lerp_angle(va.angle(),vb.angle(),v))
		var ra:=lerpf(va.length(),vb.length(),u)
		var rb:=lerpf(va.length(),vb.length(),v)
		var outer_a: Vector2=(pa+da*ra).round()
		var outer_b: Vector2=(pb+db*rb).round()
		draw_colored_polygon(PackedVector2Array([outer_a,outer_b,(pb+db*(rb-width)).round(),(pa+da*(ra-width)).round()]),color)
		draw_line(outer_a,outer_b,Color(0.95,0.98,1,alpha) if kind=="normal" else Color(1,0.82,0.29,alpha),2,false)

func _draw_impact() -> void:
	var elapsed := age-impact_time
	var lifetime := 0.16 if kind == "normal" else (0.30 if kind == "sweep" else 0.23)
	if elapsed > lifetime: return
	var u := clampf(elapsed/lifetime,0,1)
	var center := _target+Vector2(-8,8)
	var color := Color(0.9,0.96,1,1-u) if kind == "normal" else Color(1,0.69,0.16,1-u)
	var count := 7 if kind == "normal" else 14
	for i in count:
		var angle := float(i)*2.399+0.4
		var reach := (12+float(i%4)*6)*(0.2+u*1.8)
		var p := center+Vector2(cos(angle),sin(angle))*reach
		draw_line(p.round(),(p+Vector2(cos(angle),sin(angle))*5*(1-u)).round(),color,2,false)
	if kind == "normal":
		draw_line((center+Vector2(-11,-19)*(1-u)).round(),(center+Vector2(10,16)*(1-u)).round(),Color(1,1,1,1-u),3,false)
	elif kind=="sweep":
		# A shallow crescent follows the horizontal blade and widens across the target.
		# It stays below the face, above the log, and left of the command HUD.
		var span:=110.0+u*34.0
		var pivot:=Vector2(_target.x,_land.y-68)
		for j in 16:
			var q:=float(j)/16.0
			var v:=float(j+1)/16.0
			var a: Vector2=(pivot+Vector2(lerpf(-span,span,q),sin(q*PI)*15)).round()
			var b: Vector2=(pivot+Vector2(lerpf(-span,span,v),sin(v*PI)*15)).round()
			var wa:=Vector2(0,(5+sin(q*PI)*7)*(1-u))
			var wb:=Vector2(0,(5+sin(v*PI)*7)*(1-u))
			draw_colored_polygon(PackedVector2Array([a,b,(b+wb).round(),(a+wa).round()]),Color(1,0.29,0.04,(1-u)*0.72))
			draw_line(a,b,Color(1,0.86,0.36,1-u),2,false)
		for j in 10:
			var q:=float(j)/9.0
			var p: Vector2=(pivot+Vector2(lerpf(-span,span,q),sin(q*PI)*15-u*22)).round()
			draw_rect(Rect2(p,Vector2(2,4+float(j%3)*2)),Color(1,0.5,0.055,(1-u)*0.8))
	else:
		# One broad travelling cut; no repeated damage pulses or full-screen flash.
		var width := 126.0 if kind == "sweep" else 40.0
		var length := 26.0 if kind == "sweep" else 66.0
		var a := center+Vector2(-width,-length)*(0.5+u*0.5)
		var b := center+Vector2(width,length)*(0.5+u*0.5)
		draw_line(a.round(),b.round(),Color(0.85,0.16,0.035,(1-u)*0.65),10*(1-u)+1,false)
		draw_line(a.round(),b.round(),Color(1,0.70,0.22,1-u),4*(1-u)+1,false)
		for i in 9:
			var p := a.lerp(b,float(i)/8.0)+Vector2(sin(float(i)*2.1+u*4)*7,-u*22)
			draw_rect(Rect2(p.round(),Vector2(2,4)),Color(1,0.45,0.05,1-u))

func _draw_wrap() -> void:
	Flame.draw_gather(self,age,_home,_sword_hand(),_sword_tip())

func _buff_flame_strength() -> float:
	return smoothstep(0.75,0.94,age) if kind=="wrap" else 1.0
