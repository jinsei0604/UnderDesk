extends Node2D
## Golem-specific choreography. Receives resolved logs, never changes combat/RNG.
## 2026-11-20 作り直し（ユーザー「ゴーレムは動きがありすぎ。本来のゴーレムはこんな動きをしない」→ 相手の所まで歩かない）:
## その場で重い一歩だけ踏み込む → 拳を引いて溜める → 地面を殴る（両手を地に着けた絵）→ 衝撃が地面を走り、
## 相手の足元から岩が突き上がって当たる（HIT は前のまま 0.78）→ 体を起こして一歩下がる。
## 体を動かすのは一歩の間だけ。止まっている時間を長く、動く時間を短く（絵は要所の絵を切り替えるだけ）。
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_golem_punch_vfx.gd")
const HIT:=.78
const STOP:=.10
const DURATION:=1.72
## 踏み込む一歩（前へ）と、地面を殴る時刻
const STEP_DIST:=26.0
const STEP_IN:=Vector2(.0,.14)
const SLAM:=.46
const STEP_BACK:=Vector2(1.30,1.46)
## 地面を殴る絵（両手を地に着けた絵）で、手が地面に着く所（足元から、ステージの画素）
const HANDS:=Vector2(-62,-2)
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
var _slammed:=false
var _accent:=false
var _shake:=Vector2.ZERO
var _boss_z:=1
## エフェクト（rbm_golem_fx.gd。ヒーロー・聖獣と同じ部品）。前の版の四角い粒の輪（rbm_golem_punch_vfx.gd）は描かない。
var _fx_host: RBMFxHost

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	target_key=stage._targets[0]
	start=stage._foot("boss")
	# 当たる所（相手の胸の上の方）。岩はこの相手の足元から突き上がる
	var target_height: float=stage.Assets.display_height(str(stage._asset_ids[target_key]))
	contact=stage._foot(target_key)-Vector2(0,target_height*.80)+Vector2(stage._guard_offsets.get(target_key,Vector2.ZERO))
	# 踏み込んだ後の足元（ゴーレムはここから動かない）
	endpoint=(start+Vector2(-STEP_DIST,0)).round()
	stage._motion_offset=endpoint-start
	if stage._samurai_finish:
		for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	_vfx=VFX.new()
	_vfx.contact=contact
	_vfx.visible=false
	add_child(_vfx)
	var fx:=RBMGolemFx.new()
	fx.mode="punch"
	fx.accent=Palette.color_for(str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL"))))
	fx.contact=contact*0.5
	fx.target_foot=(stage._foot(target_key)+Vector2(stage._guard_offsets.get(target_key,Vector2.ZERO)))*0.5
	fx.slam_center=(endpoint+HANDS)*0.5
	fx.slam_time=SLAM
	fx.hit_time=HIT
	fx.steps=[[STEP_IN.y,endpoint*0.5],[STEP_BACK.y,start*0.5]]
	_fx_host=RBMFxHost.new()
	add_child(_fx_host)
	_fx_host.setup(stage,fx,[stage._foot(target_key)])
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

## 足元と絵（時刻だけで決まる）
func pose_at(t: float) -> Dictionary:
	if t<STEP_IN.y:
		# 重い一歩: 足をそろえて少し持ち上がり、前へ
		var m:=clampf(t/STEP_IN.y,0,1)
		return {"foot":(start.lerp(endpoint,m*m*(3-2*m))+Vector2(0,-4*sin(m*PI))).round(),"pose":3}
	if t<.22:
		# 踏みしめる（少し沈む）
		return {"foot":endpoint+Vector2(0,roundf(2*(1-smoothstep(STEP_IN.y,.22,t)))),"pose":1}
	if t<SLAM:
		# 拳を引いて溜める（止まる。最後に少し沈む）
		return {"foot":endpoint+Vector2(roundf(4*smoothstep(.30,SLAM,t)),roundf(2*smoothstep(.36,SLAM,t))),"pose":1}
	if t<1.12:
		# 地面を殴った姿のまま、衝撃が相手へ走り岩が突き上がるのを見届ける
		return {"foot":endpoint+Vector2(0,roundf(3*(1-smoothstep(SLAM,SLAM+.12,t)))),"pose":5}
	if t<STEP_BACK.x:
		return {"foot":endpoint,"pose":8}
	if t<STEP_BACK.y:
		# 一歩下がる
		var m:=(t-STEP_BACK.x)/(STEP_BACK.y-STEP_BACK.x)
		return {"foot":(endpoint.lerp(start,m*m*(3-2*m))+Vector2(0,-4*sin(m*PI))).round(),"pose":3}
	if t<1.56:
		return {"foot":start+Vector2(0,roundf(2*(1-smoothstep(STEP_BACK.y,1.56,t)))),"pose":1}
	return {"foot":start,"pose":0}

func _advance(t: float) -> void:
	if not active: return
	_clear_shake()
	age=t
	var s:=pose_at(t)
	var foot: Vector2=s.foot
	_stage._pose("boss",int(s.pose))
	_stage._visuals["boss"].position=Vector2(_stage._homes["boss"])+foot-start
	if is_instance_valid(_fx_host):_fx_host.advance(t,foot)
	var guard_progress:=smoothstep(.2,.66,t)*(1.0-smoothstep(1.28,DURATION,t))
	for key in _stage._guards:
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*guard_progress).round()
		_stage._pose(key,10)
	var target=_stage._visuals[target_key]
	if not _stage._guards.has(target_key): target.position=_stage._homes[target_key]
	if t>=.24 and not _swing:
		_swing=true
		_stage._sound.play_sound("neutral_blunt_swing",-6)
	if t>=SLAM and not _slammed:
		_slammed=true
		_stage._sound.play_sound("neutral_impact_heavy",-7)
	if t>=HIT and not _hit:
		_hit=true
		_stage._sound.play_sound("neutral_impact_heavy",-3)
		if not _stage._guards.is_empty(): _stage._sound.play_sound("guard_hit",-5)
		if _stage._counters.is_empty(): _stage.impact.emit(_stage._entry.duplicate(true))
		else: _stage._pose(target_key,10)
	if t>=HIT+STOP and not _accent:
		_accent=true
		impact_attribute=str(_stage._skill.get("attribute",_stage._entry.get("attribute","NEUTRAL")))
		_vfx.impact_color=Palette.color_for(impact_attribute)
	if t>=HIT and _stage._counters.is_empty():
		# 足元から突き上がった岩に押し上げられる
		var reaction:=t-HIT
		var amount:=smoothstep(0,.08,reaction)*(1.0-smoothstep(.22,.55,reaction))
		target.position+=Vector2(-roundf(8*amount),-roundf(10*amount))
		if t<1.30: _stage._pose(target_key,11)
	_vfx.age=t-HIT-STOP
	_vfx.queue_redraw()
	# 揺れ: 踏みしめた時・地面を殴った時（縦）・岩が突き上がった時
	var shake:=Vector2.ZERO
	for at in [STEP_IN.y,STEP_BACK.y]:
		var a: float=t-float(at)
		if a>=0 and a<.06:shake=Vector2(0,[2,-1,1,0][int(a*60)%4])
	var sa:=t-SLAM
	if sa>=0 and sa<.14:shake=Vector2(0,[3,-3,2,-2,1,0][int(sa*60)%6])
	var ha:=t-HIT
	if ha>=0 and ha<.18:shake=Vector2([2,-2,1,-1,0,0][int(ha*60)%6],[2,-2,1,0][int(ha*60)%4])
	if shake!=Vector2.ZERO:
		_shake=shake
		for visual in _stage._visuals.values(): visual.position+=_shake
		_vfx.position=_shake

func _counter_handoff() -> void:
	_clear_shake()
	_vfx.visible=false
	if is_instance_valid(_fx_host):_fx_host.clear()

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
