extends Node2D
## Resolved battle entries only; normal and awakened dragons share playback plumbing.
const Motion=preload("res://src/bossmaker/visuals/rbm_dragon_motion.gd")
const Body=preload("res://src/bossmaker/visuals/rbm_dragon_body.gd")
const BiteMotion=preload("res://src/bossmaker/visuals/rbm_dragon_bite_motion.gd")
const BiteBody=preload("res://src/bossmaker/visuals/rbm_dragon_bite_body.gd")
const BiteVFX=preload("res://src/bossmaker/visuals/rbm_dragon_bite_vfx.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_dragon_vfx.gd")
const RangedVFX=preload("res://src/bossmaker/visuals/rbm_dragon_ranged_vfx.gd")
const RANGED_SOUNDS={"breath":"dragon_normal_breath","focused_breath":"dragon_awakened_breath","meteors":"dragon_awakened_meteors"}
const MeteorSky=preload("res://src/bossmaker/visuals/rbm_dragon_meteor_sky.gd")
const AudioCatalog=preload("res://src/bossmaker/rbm_audio_catalog.gd")
var _sky: Node2D
var _sound_started:=false
var kind:="single"
var form:="normal"
var action_kind:="focused_breath"
var duration:=2.35
var impact_time:=Motion.FOCUSED_HIT
var age:=-1.0
var active:=false
var motion: RefCounted
var _stage: Control
var _body: Node2D
var _vfx: Node2D
var _hit:=false
var _released:=false
var _boss_visible:=true
var _shake:=Vector2.ZERO

## Read in the background once the boss is known (rbm_presentation_warmup.gd): the bite frames, the
## boss pose frames the timelines switch to, and the approved ranged clips.
static func warm_paths(asset_id: String, kind: String) -> Array[String]:
	var awakened:=asset_id=="dragon_awakened"
	var out: Array[String]=[]
	if kind=="single" and not awakened:
		for i in range(12): out.append(BiteBody.ROOT+"%02d.png" % i)
	for pose in range(1,11): out.append(RBMVisualAssets.frame_path(asset_id,pose))
	var ranged: String={"single":"focused_breath" if awakened else "","all":"meteors" if awakened else "breath"}.get(kind,"")
	if ranged!="": out.append(str(AudioCatalog.FILES[RANGED_SOUNDS[ranged]]))
	return out

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	form="awakened" if str(stage._asset_ids["boss"])=="dragon_awakened" else "normal"
	if kind=="support": kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	if kind in ["buff","heal"]: action_kind=kind
	elif kind=="single": action_kind="focused_breath" if form=="awakened" else "bite"
	else: action_kind="meteors" if form=="awakened" else "breath"
	duration={"bite":BiteMotion.DURATION,"breath":4.05,"focused_breath":4.45,"meteors":6.65,"buff":2.35,"heal":2.35}[action_kind]
	impact_time={"bite":BiteMotion.HIT,"breath":Motion.BREATH_HIT,"focused_breath":Motion.FOCUSED_HIT,"meteors":Motion.METEOR_HIT,"buff":Motion.SUPPORT_HIT,"heal":Motion.SUPPORT_HIT}[action_kind]
	stage._playing=true
	stage._phase="dragon_"+action_kind
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var boss: Control=stage._visuals["boss"]
	_boss_visible=boss.visible
	z_index=3
	_body=BiteBody.new() if action_kind=="bite" else Body.new()
	add_child(_body)
	_body.configure(stage)
	boss.visible=false
	motion=BiteMotion.new() if action_kind=="bite" else Motion.new()
	var aim: Vector2=stage._foot("boss")
	var feet: Array[Vector2]=[]
	var hits: Array[Vector2]=[]
	for key in stage._targets:
		if key=="boss": continue
		var foot: Vector2=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		feet.append(foot)
		hits.append(foot-Vector2(0,height*.55)+Vector2(6,0))
	if not hits.is_empty(): aim=hits[0]
	var origin: Vector2=stage._foot("boss")
	if action_kind=="bite": origin+=_body.anchor_offset()
	motion.configure(origin,aim,feet)
	if action_kind=="bite": motion.endpoint=aim-_body.local_point(6,"mouth")
	_vfx=BiteVFX.new() if action_kind=="bite" else (RangedVFX.new() if action_kind in RANGED_SOUNDS else VFX.new())
	_vfx.motion=motion
	_vfx.body=_body
	_vfx.kind=action_kind
	_vfx.attack_attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_vfx.feet=feet
	_vfx.hits=hits
	_vfx.prepare()
	add_child(_vfx)
	if action_kind=="meteors":
		_sky=MeteorSky.new()
		_sky.z_index=-1
		add_child(_sky)
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
	_clear_shake()
	age=t
	var render_time:=t
	var state: Dictionary=motion.sample(action_kind,render_time)
	_body.advance(state)
	_stage._pose("boss",int(state.pose))
	_stage._visuals["boss"].position=(Vector2(_stage._homes["boss"])+Vector2(state.foot)-motion.home).round()
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.50,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	var release_time: float={"bite":1.34,"breath":.78,"focused_breath":.82,"meteors":.54}.get(action_kind,.26)
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
			var reaction:=t-impact_time-(.04 if action_kind=="bite" else 0.0)
			var reaction_length:=.34 if action_kind=="bite" else .42
			if action_kind=="meteors":
				reaction_length=.16
				var target_index: int=_stage._targets.find(key)
				for i in range(_vfx.meteors.size()):
					var arrival: float=_vfx.meteors[i].arrival
					if t>=arrival and (i%_vfx.hits.size()==target_index or i==_vfx.meteors.size()-1): reaction=t-arrival
			_stage._visuals[key].position=_stage._homes[key]
			if reaction>=0 and reaction<reaction_length:
				if _stage._counters.has(key): _stage._pose(key,10)
				else:
					_stage._pose(key,11)
					_stage._visuals[key].position+=Vector2((-8 if action_kind=="bite" else -10)*sin(reaction/reaction_length*PI),0).round()
			elif reaction>=reaction_length:
				var unit: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if unit.get("is_downed",false) else (10 if unit.get("is_defending",false) or _stage._counters.has(key) else 0))
	_vfx.advance(render_time)
	if is_instance_valid(_sky): _sky.advance(render_time)
	if action_kind in RANGED_SOUNDS:
		_shake=_ranged_shake(t)
	elif action_kind=="bite":
		var shake_age:=t-impact_time
		if shake_age>=0 and shake_age<.20:
			_shake=(Vector2(sin(shake_age*113),cos(shake_age*89)*.5)*4.0*(1-shake_age/.20)).round()
	if _shake!=Vector2.ZERO:
		for visual in _stage._visuals.values(): visual.position+=_shake
		position=_shake

func _ranged_shake(t: float) -> Vector2:
	var result:=Vector2.ZERO
	if action_kind=="meteors":
		for meteor in _vfx.meteors:
			var elapsed: float=t-meteor.arrival
			var power:=46.0 if meteor.radius>60 else 4.5
			var span:=1.1 if meteor.radius>60 else .23
			if elapsed>=0 and elapsed<span: result+=Vector2(sin(elapsed*98)*power,cos(elapsed*117)*power*.65)*(1-elapsed/span)
		result=result.limit_length(48)
	elif action_kind=="focused_breath":
		return Vector2.ZERO
	elif t>=.82 and t<2.65:
		var power:=2.0 if action_kind=="focused_breath" else .65
		if action_kind=="focused_breath" and t<1.08: power+=6*(1-(t-.82)/.26)
		result=Vector2(sin(t*97)*power,cos(t*113)*power*.7)
	return result.round()

## These approved clips include charge, release and impacts, independent of attribute.
## The stage audio owner keeps mute, voice limits, cancellation and visibility cleanup.
func play_sound_phase(phase: String) -> bool:
	if not action_kind in RANGED_SOUNDS: return false
	if phase=="cast" and not _sound_started:
		_sound_started=true
		_stage._sound.play_sound(RANGED_SOUNDS[action_kind])
	return true

func _clear_shake() -> void:
	if _shake!=Vector2.ZERO and is_instance_valid(_stage):
		for visual in _stage._visuals.values():
			if is_instance_valid(visual): visual.position-=_shake
	_shake=Vector2.ZERO
	position=Vector2.ZERO

func _restore_transform() -> void:
	_clear_shake()
	if not is_instance_valid(_stage): return
	_stage._visuals["boss"].visible=_boss_visible
	_stage._visuals["boss"].position=_stage._homes["boss"]
	_body.visible=false
	_vfx.visible=false
	if is_instance_valid(_sky): _sky.visible=false

func stop() -> void:
	_restore_transform()
	active=false
	visible=false
	_stage=null
