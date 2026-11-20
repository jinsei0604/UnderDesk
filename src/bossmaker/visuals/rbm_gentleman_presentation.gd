extends Node2D
## Resolved-entry playback only. Multiple visual bullets produce one combat impact.
const Motion=preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const Vfx=preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")
const Smoke=preload("res://src/bossmaker/visuals/rbm_gentleman_smoke.gdshader")
const Audio=preload("res://src/bossmaker/rbm_audio_catalog.gd")
const TempoMap=preload("res://src/bossmaker/visuals/rbm_tempo_map.gd")
const Camera=preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
## 2026-11-20 作り直した大技（覚醒・覚醒後の全体）: ヒーロー・聖獣と同じ部品（RBMHeroFxBase）のエフェクト。本体は今までどおり
## rbm_gentleman_vfx.gd が要所の絵で描き、絵の名前と光は fx の view["body"]・view["hero"] から受け取る。
const V2_FX := {
	"awakening": preload("res://src/bossmaker/visuals/gentleman/rbm_gentleman_fx_awaken.gd"),
	"awakened_all": preload("res://src/bossmaker/visuals/gentleman/rbm_gentleman_fx_post_all.gd"),
}
const V2_SOUNDS := {"awakening": "gentleman_awakening_v2", "awakened_all": "gentleman_awakened_all"}
const V2_SHADERS := ["blast", "cracks", "pillar", "pool", "post", "ribbon", "ring"]
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}
const POST_MARGIN := 32.0
var kind := "single"
var action_kind := "single"
var duration := 6.0
var impact_time := 2.79
var age := 0.0
var active := false
var awakened := false
var target := Vector2.ZERO
var _stage: Control
var _viewport: SubViewport
var _picture: TextureRect
var _vfx: Node2D
var _smoke: ColorRect
var _audio: AudioStreamPlayer
var _unit := 160.0/94.0
var _hit := false
var _reveal := false
var _boss_visible := true
var _restored := false
var _fx: RBMGentlemanFxBase
var _world: Node2D
var _dim: ColorRect
var _post: ColorRect
var _camera: RefCounted
## fx の相手の番号 → ステージの味方の key
var _fx_keys: Array = []
var _flashed := {}

func is_gentleman() -> bool:return true

## 戦闘テンポで詰める区間（覚醒と、2026-11-20 に作り直した技は詰めない）
func tempo() -> Array:
	return [] if kind=="awakening" or _fx!=null else Motion.tempo(action_kind)

## Read in the background once the boss is known (rbm_presentation_warmup.gd), so the first play never
## parses the motion data or decodes its track on its first frame. kind is the stage's action kind.
static func warm_paths(asset_id: String, kind: String) -> Array[String]:
	var out: Array[String]=[Motion.MOTION_PATH]
	var form:="awakened_" if asset_id=="gentleman_awakened" else ""
	var keys: Array={"single":[form+"single"],"all":[form+"all"],"support":["buff","heal"],"awakening":["awakening"]}.get(kind,[])
	for key in keys:
		out.append(str(Audio.FILES[V2_SOUNDS[key]] if V2_SOUNDS.has(key) else Audio.FILES["gentleman_"+key]))
		if V2_FX.has(key):
			for name in V2_SHADERS:out.append("res://src/bossmaker/visuals/hero_boss/shaders/%s.gdshader"%name)
	if kind=="awakening":out.append(RBMVisualAssets.frame_path("gentleman_awakened",0))
	return out

func play(stage: Control) -> Tween:
	_stage=stage
	active=true
	awakened=str(stage._asset_ids.get("boss",""))=="gentleman_awakened"
	if kind=="support":kind="heal" if str(stage._skill.get("effect","")) in ["heal","self_heal"] else "buff"
	action_kind=("awakened_single" if awakened else "single") if kind=="single" else (("awakened_all" if awakened else "all") if kind=="aoe" else kind)
	var data:=Motion.clip(action_kind)
	duration=float(data.duration);impact_time=float(data.impact)
	if V2_FX.has(action_kind):
		_fx=(V2_FX[action_kind] as GDScript).new()
		duration=_fx.duration();impact_time=_fx.impact()
	stage._playing=true;stage._phase="gentleman_"+action_kind
	stage._motion_offset=Vector2.ZERO
	if kind=="awakening":stage._awakened_appearance_applied=false
	for key in stage._counters:stage._counter_offsets[key]=Vector2.ZERO
	_boss_visible=stage._visuals.boss.visible
	stage._visuals.boss.visible=false
	z_index=17
	_viewport=SubViewport.new()
	_viewport.size=Vector2i(ceil(stage.size.x/_unit),ceil(stage.size.y/_unit))
	_viewport.transparent_bg=true;_viewport.disable_3d=true;_viewport.gui_disable_input=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_smoke=ColorRect.new()
	_smoke.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_smoke.material=ShaderMaterial.new();_smoke.material.shader=Smoke
	_viewport.add_child(_smoke)
	_vfx=Vfx.new();_vfx.kind=action_kind;_vfx.data=data;_vfx.awakened=awakened
	_vfx.canvas_size=Vector2(_viewport.size)
	_vfx.attribute=str(stage._skill.get("attribute",stage._entry.get("attribute","NEUTRAL")))
	_vfx.impact_sheets=stage.get("_gentleman_impacts")
	if is_instance_valid(_vfx.impact_sheets):_vfx.impact_sheets.request(_vfx.attribute,action_kind)
	_vfx.boss=stage._foot("boss")/_unit
	for key in stage._party_keys:
		_vfx.party_feet.append(stage._foot(key)/_unit)
		_vfx.party_heights.append(stage.Assets.display_height(str(stage._asset_ids[key]))/_unit)
	for key in stage._targets:
		if key=="boss":continue
		var foot: Vector2=stage._foot(key)+Vector2(stage._guard_offsets.get(key,Vector2.ZERO))
		var height: float=stage.Assets.display_height(str(stage._asset_ids[key]))
		_vfx.feet.append(foot/_unit);_vfx.points.append((foot-Vector2(0,height*.57))/_unit)
		_vfx.heights.append(height/_unit)
	target=stage._foot("boss")
	if not _vfx.feet.is_empty():target=_vfx.feet[0]*_unit
	_vfx.target=target/_unit
	_viewport.add_child(_vfx)
	_picture=TextureRect.new();_picture.texture=_viewport.get_texture()
	_picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_picture.size=Vector2(_viewport.size)*_unit
	add_child(_picture)
	if _fx!=null:_build_v2()
	var sound_key: String=V2_SOUNDS[action_kind] if V2_FX.has(action_kind) else "gentleman_"+action_kind
	_audio=AudioStreamPlayer.new();_audio.stream=load(Audio.FILES[sound_key]);_audio.volume_db=-3.0 if _fx!=null else -6.0
	add_child(_audio)
	stage._sound.history.append(sound_key)
	if stage._sound.history.size()>64:stage._sound.history.pop_front()
	stage.visibility_changed.connect(_visibility_changed)
	if not stage._sound.muted:_audio.play()
	if not stage._guards.is_empty():stage._sound.play_sound("cover_move",-5)
	# 何回も当たる攻撃（2026-10-23）: 影の射撃・先の弾が当たるたびに小さな数字、最後の一撃（impact）で合計（stage.begin_multi_hit()）
	if kind in ["single","aoe"]:stage.begin_multi_hit(_v2_hit_plan() if _fx!=null else _multi_hit_plan(data),float(_fx.get("final_share")) if _fx!=null and _fx.get("final_share")!=null else (.6 if kind=="single" else .4))
	_advance(0)
	var tween:=create_tween()
	# 戦闘テンポ（2026-10-16）: 止まっている区間だけ詰める（覚醒は詰めない）。通しの音も同じ時刻へ合わせ直す。
	TempoMap.tween_timeline(tween,_advance,duration,tempo(),_jump_audio)
	if kind=="awakening":
		tween.tween_callback(stage._finish_awakening_entry)
		return tween
	if stage._samurai_finish:
		tween.tween_callback(_restore)
		var counter_duration: float=stage.SAMURAI_WIND_START_DELAY+stage.SamuraiWind.AFTERMATH_START+stage.SamuraiWind.AFTERMATH_DURATION+.05
		tween.tween_method(stage._samurai_finish_progress,0.0,counter_duration,counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore)
		tween.tween_method(stage._counter_progress,0.0,1.0,.20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

## 最後の一撃（impact）より前に当たる弾の時刻（相手ごと）。影の射撃は影ごとに決めた相手（Motion.shadow_target、
## rbm_gentleman_vfx.gd と同じ数え方。2026-11-20 から影は1人の相手に並んで撃つ）、本体の先の弾（覚醒後）は全部の相手。
func _multi_hit_plan(data: Dictionary) -> Dictionary:
	var keys: Array[String]=[]
	for key in _stage._targets:
		if key!="boss":keys.append(key)
	var plan:={}
	if keys.is_empty():return plan
	for e in data.get("shadows",[]):
		if float(e.hit)>=impact_time-.001:continue
		var key: String=keys[Motion.shadow_target(e,keys.size())]
		if not plan.has(key):plan[key]=[]
		plan[key].append(float(e.hit))
	for e in data.get("host",[]):
		if float(e.hit)>=impact_time-.001:continue
		for key in keys:
			if not plan.has(key):plan[key]=[]
			plan[key].append(float(e.hit))
	return plan

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):return
	age=t
	if kind=="awakening" and t>=impact_time and not _reveal:
		_reveal=true;_stage._awakened_appearance_applied=true
		_stage._apply_awakened_appearance();awakened=true
	_vfx.age=t
	if _fx!=null:_advance_v2(t)
	_vfx.queue_redraw()
	_smoke.position=(_vfx.host_foot()-Vector2(70,151)).round();_smoke.size=Vector2(140,180)
	_smoke.visible=awakened or (kind=="awakening" and t>impact_time-.18)
	var power: float=1.3 if awakened else 0.0
	if kind=="awakening":power=smoothstep(impact_time-.18,impact_time+.37,t)*(1+.9*(1-smoothstep(impact_time+.62,impact_time+2.12,t)))
	_smoke.material.set_shader_parameter("age",t);_smoke.material.set_shader_parameter("power",power)
	var shock:=0.0
	var dt:=t-impact_time
	if dt>=0 and dt<.65:shock=(7 if kind=="aoe" else 3)*exp(-dt*7)
	if kind=="awakening" and t<impact_time:shock=smoothstep(5.5,8.08,t)*3
	if _fx==null:_picture.position=(Vector2(sin(t*83),sin(t*119)*.58)*shock*_unit).round()
	for key in _stage._guards:
		var progress:=smoothstep(0,.5,t)*(1-smoothstep(duration-.5,duration,t))
		_stage._visuals[key].position=(Vector2(_stage._homes[key])+Vector2(_stage._guard_offsets[key])*progress).round()
		_stage._pose(key,10)
	_stage.advance_multi_hit(t)
	if t>=impact_time and not _hit and kind!="awakening":
		_hit=true;_stage._strike()
		if not active or not is_instance_valid(_stage):return
	if kind in ["single","aoe"] and dt>=0 and _fx==null:
		for key in _stage._targets:
			if _stage._guards.has(key):continue
			_stage._visuals[key].position=_stage._homes[key]
			if dt<.30:
				_stage._pose(key,10 if _stage._counters.has(key) else 11)
				_stage._visuals[key].position+=Vector2(7*sin(dt/.30*PI),0).round()
			else:
				var state: Dictionary=_stage._unit_state(key)
				_stage._pose(key,11 if state.get("is_downed",false) else (10 if state.get("is_defending",false) or _stage._counters.has(key) else 0))

func play_sound_phase(_phase: String) -> bool:return true
func _jump_audio(t: float) -> void:
	_audio=TempoMap.crossfade_jump(_audio,t)
func _visibility_changed() -> void:
	if is_instance_valid(_audio) and is_instance_valid(_stage):_audio.stream_paused=not _stage.is_visible_in_tree()
func _restore() -> void:
	if _restored:return
	_restored=true
	if is_instance_valid(_stage):
		_stage._visuals.boss.visible=_boss_visible
		_stage._visuals.boss.position=_stage._homes.boss
		if _stage.visibility_changed.is_connected(_visibility_changed):_stage.visibility_changed.disconnect(_visibility_changed)
	if is_instance_valid(_audio):_audio.stop()
	if is_instance_valid(_picture):_picture.visible=false
	if is_instance_valid(_viewport):_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if _camera!=null:
		_camera.reset();_camera=null
	if is_instance_valid(_stage) and _fx!=null:
		for key in _stage._party_keys:
			var visual: Control=_stage._visuals.get(key)
			if is_instance_valid(visual):visual.self_modulate=Color.WHITE
	for n in [_world,_dim,_post]:
		if is_instance_valid(n):n.visible=false
func stop() -> void:
	_restore();active=false;visible=false;_stage=null

# ---- 2026-11-20 作り直した大技（覚醒・覚醒後の全体）----

## 層（z はステージの中の絶対値）: 暗さ1・後ろ1 ＜ 味方2 ＜ 中3 ＜ 本体（このノード）17 ＜ 前18 ＜ 画面全体の処理19
func _build_v2() -> void:
	_dim=ColorRect.new()
	_dim.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_dim.position=Vector2(-POST_MARGIN,-POST_MARGIN)
	_dim.size=_stage.size+Vector2.ONE*POST_MARGIN*2.0
	_dim.z_as_relative=false;_dim.z_index=1
	_dim.color=Color(0,0,0,0)
	add_child(_dim)
	_world=Node2D.new()
	_world.scale=Vector2(2,2)
	add_child(_world)
	var back:=_v2_layer("GentlemanBack",1)
	var mid:=_v2_layer("GentlemanMid",3)
	var front:=_v2_layer("GentlemanFront",18)
	_fx.mid=mid
	var targets: Array=[]
	_fx_keys.clear()
	for key in _stage._targets:
		if key=="boss" or targets.size()>=4:continue
		_fx_keys.append(str(key))
		targets.append((_stage._foot(key)+Vector2(_stage._guard_offsets.get(key,Vector2.ZERO)))*0.5)
	for i in range(4):
		_fx.present[i]=i<targets.size()
		if i>=targets.size():targets.append(Vector2(175,225))
	_world.add_child(_fx)
	_fx.setup(back,front,targets)
	_post=ColorRect.new()
	_post.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_post.position=Vector2(-POST_MARGIN,-POST_MARGIN)
	_post.size=_stage.size+Vector2.ONE*POST_MARGIN*2.0
	_post.z_as_relative=false;_post.z_index=19
	var pm:=ShaderMaterial.new()
	pm.shader=RBMHeroFx.shader("post")
	_post.material=pm
	add_child(_post)
	_camera=Camera.new()
	_camera.attach(_stage)
	_vfx.v2=true

func _v2_layer(layer_name: String, z: int) -> Node2D:
	var n:=Node2D.new()
	n.name=layer_name
	n.z_as_relative=false;n.z_index=z
	_world.add_child(n)
	return n

func _v2_hit_plan() -> Dictionary:
	var plan:={}
	for h in _fx.hits():
		var i:=int(h[1])
		if i>=_fx_keys.size() or float(h[0])>=impact_time-.001:continue
		var key: String=_fx_keys[i]
		if not plan.has(key):plan[key]=[]
		plan[key].append(float(h[0]))
	return plan

func _advance_v2(t: float) -> void:
	_fx.advance_all(t,_stage._foot("boss")*0.5)
	var view: Dictionary=_fx.view
	var body: Dictionary=view.get("body",{})
	var hero_info: Dictionary=view.get("hero",{})
	_vfx.pose_override=str(body.get("pose",""))
	_vfx.body_flash=float(hero_info.get("flash",0.0));_vfx.body_flash_col=hero_info.get("flash_col",Color.WHITE)
	_vfx.body_lit=float(hero_info.get("lit",0.0));_vfx.body_lit_col=hero_info.get("lit_col",Color.WHITE)
	var dim:=float(view.get("dim",0.0))
	var dc: Color=view.get("dim_col",Color(0.05,0.0,0.02))
	dc.a=dim
	_dim.color=dc
	_allies_v2(view,dim)
	var shake: Vector2=view.get("shake",Vector2.ZERO)
	_camera._offset=(shake*2.0*_camera.shake_strength()).snapped(Vector2(2,2))
	_camera.apply()
	_apply_post(view,t)

## 味方の反応（のけぞり・光・暗さ。表示だけ）。聖獣・ヒーローと同じ計算。
func _allies_v2(view: Dictionary,dim: float) -> void:
	var ally_views: Array=view.get("allies",[{},{},{},{}])
	for key in _stage._party_keys:
		var visual: Control=_stage._visuals.get(key)
		if not is_instance_valid(visual):continue
		var slot:=_fx_keys.find(str(key))
		var v: Dictionary=ally_views[slot] if slot>=0 else {}
		var k:=1.0-minf(dim*0.73,0.8)
		var c:=Color(k,k,k,1.0)
		var lit:=float(v.get("lit",0.0))
		if lit>0.0:
			c=c.lerp(Color(v.get("lit_col",Color.WHITE))*1.2,lit*0.35)
			c.a=1.0
		visual.self_modulate=c
		if _stage._guards.has(key) or slot<0 or not _stage._targets.has(key):continue
		var force:=float(v.get("force",0.0))
		visual.position=(Vector2(_stage._homes[key])+Vector2(-13.0*force-float(v.get("back",0.0)),-8.0*force-float(v.get("lift",0.0)))*2.0).round()
		if float(v.get("flash",0.0))>0.45:
			if not _flashed.get(key,false):
				_flashed[key]=true
				_stage._flash(key)
		else:
			_flashed[key]=false
		if force>0.08:
			_stage._pose(key,10 if _stage._counters.has(key) else 11)
		else:
			var state: Dictionary=_stage._unit_state(key)
			_stage._pose(key,11 if state.get("is_downed",false) else (10 if state.get("is_defending",false) or _stage._counters.has(key) else 0))

func _apply_post(view: Dictionary,t: float) -> void:
	var pm:=_post.material as ShaderMaterial
	pm.set_shader_parameter("time",t)
	for k in POST_DEFAULTS:pm.set_shader_parameter(k,POST_DEFAULTS[k])
	pm.set_shader_parameter("focus",Vector2(0.5,0.5))
	var post_values: Dictionary=view.get("post",{})
	for k in post_values:
		var value: Variant=post_values[k]
		if k=="focus_world":pm.set_shader_parameter("focus",_uv(value))
		elif k=="split_world":pm.set_shader_parameter("split_p",_uv(value))
		else:pm.set_shader_parameter(k,value)
	var rings:=PackedVector4Array()
	var screen:=get_viewport_rect().size
	var scale_y:=2.0*_stage.get_global_transform_with_canvas().get_scale().y/maxf(screen.y,1.0)
	for ring in view.get("rings",[]):
		var ruv:=_uv(Vector2(ring.x,ring.y))
		rings.append(Vector4(ruv.x,ruv.y,ring.z*scale_y,ring.w))
		if rings.size()>=6:break
	var count:=rings.size()
	while rings.size()<6:rings.append(Vector4.ZERO)
	pm.set_shader_parameter("rings",rings)
	pm.set_shader_parameter("ring_count",count)

func _uv(p: Vector2) -> Vector2:
	var canvas:=_stage.get_global_transform_with_canvas()*(p*2.0)
	return canvas/get_viewport_rect().size
