extends Node2D
## Resolved battle entries only; normal and awakened dragons share playback plumbing.
## 2026-11-28: 前の攻撃（噛みつき・前の息吹・前の隕石）のスクリプトと噛みつきのコマ画像は、使わなくなったので削除した。
const Motion=preload("res://src/bossmaker/visuals/rbm_dragon_motion.gd")
const Body=preload("res://src/bossmaker/visuals/rbm_dragon_body.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_dragon_vfx.gd")
## 息吹・隕石の完成トラック（攻撃の再生役が鳴らす。事前読み込みと検証の道具もこの表を読む）
const RANGED_SOUNDS={"breath":"dragon_normal_breath","focused_breath":"dragon_awakened_breath","meteors":"dragon_awakened_meteors"}
const AudioCatalog=preload("res://src/bossmaker/rbm_audio_catalog.gd")
## 攻撃4種（2026-11-26 ユーザー承認）: 噛みつき→急降下「天翔墜撃」・息吹・覚醒後の集中の息吹・隕石は、新しい作り
## （dragon/rbm_dragon_attack_host.gd）で再生する。強化・回復は今までどおり下の再生（Motion・Body・VFX の咆哮）。
const Host=preload("res://src/bossmaker/visuals/dragon/rbm_dragon_attack_host.gd")
## 攻撃の種類 → 再生役の技の名前（噛みつきは急降下に置き換えた）
const HOST_ACTIONS={"bite":"dive","breath":"breath","focused_breath":"focused_breath","meteors":"meteors"}
var _host: Node2D
var kind:="single"
var form:="normal"
var action_kind:="focused_breath"
var duration:=2.35
var impact_time:=Motion.SUPPORT_HIT
var _age:=-1.0
## 演出の時刻（検証の道具・計測が読む）。攻撃4種は再生役（_host）の時刻、強化・回復は下の再生の時刻
var age: float:
	get: return float(_host.age) if is_instance_valid(_host) else _age
	set(value): _age=value
var active:=false
var motion: RefCounted
var _stage: Control
var _body: Node2D
var _vfx: Node2D
var _hit:=false
var _released:=false
var _boss_visible:=true

## Read in the background once the boss is known (rbm_presentation_warmup.gd): the boss pose frames the
## timelines switch to, the approved ranged clips, and (2026-11-26) the new attack effects' shaders and the
## dive's roar (dragon/rbm_dragon_attack_host.gd). The old bite frames are no longer used.
static func warm_paths(asset_id: String, kind: String) -> Array[String]:
	var awakened:=asset_id=="dragon_awakened"
	var out: Array[String]=[]
	for pose in range(1,11): out.append(RBMVisualAssets.frame_path(asset_id,pose))
	var ranged: String={"single":"focused_breath" if awakened else "","all":"meteors" if awakened else "breath"}.get(kind,"")
	if ranged!="": out.append(str(AudioCatalog.FILES[RANGED_SOUNDS[ranged]]))
	var attack: String={"single":"focused_breath" if awakened else "bite","all":"meteors" if awakened else "breath"}.get(kind,"")
	if attack!="":
		for path in Host.warm_paths(HOST_ACTIONS[attack]):
			if not out.has(path): out.append(path)
	return out

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	form="awakened" if str(stage._asset_ids["boss"])=="dragon_awakened" else "normal"
	if kind=="support": kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	if kind in ["buff","heal"]: action_kind=kind
	elif kind=="single": action_kind="focused_breath" if form=="awakened" else "bite"
	else: action_kind="meteors" if form=="awakened" else "breath"
	if HOST_ACTIONS.has(action_kind):
		z_index=0
		_host=Host.new()
		add_child(_host)
		var attr:=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
		var tw: Tween=_host.play(stage,HOST_ACTIONS[action_kind],form=="awakened",attr)
		duration=_host.duration
		impact_time=_host.impact_time
		# 覚醒後のオーラ（rbm_dragon_aura.gd）が、攻撃中も host の体に付いていくように
		_body=_host.get("_body")
		return tw
	# ここから下は強化・回復（咆哮）だけ
	duration=Motion.SUPPORT_DURATION
	impact_time=Motion.SUPPORT_HIT
	stage._playing=true
	stage._phase="dragon_"+action_kind
	stage._motion_offset=Vector2.ZERO
	for key in stage._counters: stage._counter_offsets[key]=Vector2.ZERO
	var boss: Control=stage._visuals["boss"]
	_boss_visible=boss.visible
	z_index=3
	_body=Body.new()
	add_child(_body)
	_body.configure(stage)
	boss.visible=false
	motion=Motion.new()
	motion.configure(stage._foot("boss"))
	_vfx=VFX.new()
	_vfx.body=_body
	_vfx.kind=action_kind
	_vfx.prepare()
	add_child(_vfx)
	_advance(0)
	stage._play_se("cast")
	if not stage._guards.is_empty(): stage._sound.play_sound("cover_move",-5)
	var tween:=create_tween()
	# 戦闘テンポ（2026-10-16）: 強化・回復は詰める区間なし（今までどおり）
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
	age=t
	var state: Dictionary=motion.sample(action_kind,t)
	_body.advance(state)
	_stage._pose("boss",int(state.pose))
	_stage._visuals["boss"].position=(Vector2(_stage._homes["boss"])+Vector2(state.foot)-motion.home).round()
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.50,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	if t>=Motion.SUPPORT_RELEASE and not _released:
		_released=true
		_stage._play_se("release")
	if t>=impact_time and not _hit:
		_hit=true
		_stage._strike()
		if not active or not is_instance_valid(_stage): return
	_vfx.advance(t)

## 攻撃4種は再生役が完成トラックを鳴らす。強化・回復はステージの共通の音（false を返す）
func play_sound_phase(phase: String) -> bool:
	if is_instance_valid(_host): return _host.play_sound_phase(phase)
	return false

func _restore_transform() -> void:
	if not is_instance_valid(_stage): return
	_stage._visuals["boss"].visible=_boss_visible
	_stage._visuals["boss"].position=_stage._homes["boss"]
	_body.visible=false
	_vfx.visible=false

func stop() -> void:
	if is_instance_valid(_host):
		_host.stop()
		active=false
		visible=false
		_stage=null
		return
	_restore_transform()
	active=false
	visible=false
	_stage=null
