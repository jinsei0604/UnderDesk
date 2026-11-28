extends Node2D
## 竜（翠鱗の竜／覚醒後）の攻撃4種の再生役（2026-11-26 ユーザー承認。表示専用。戦闘の状態・乱数・行動順には触れない）。
##   覚醒前・単体「天翔墜撃」（rbm_dragon_fx_dive.gd）: 咆哮してから空へ舞い上がり、相手の真上から急降下（前の噛みつきの代わり）
##   覚醒前・全体「翠鱗の息吹」／覚醒後・単体「黒焔の一閃」（rbm_dragon_fx_breath.gd）: 口の先の玉からあふれる炎、何回も当たる
##   覚醒後・全体「黒天の隕石」（rbm_dragon_fx_meteors.gd）: 渦から降る隕石の雨と、ゆっくり迫って落ちる巨大隕石
## 今の竜の体の絵（rbm_dragon_body.gd の12ポーズ）を描き、エフェクトを時刻で進め、暗さ・揺れ（戦場のカメラ）・
## 画面全体の処理・味方の反応を当てる。ヒーロー・獅子と同じく、ヒーローのエフェクトの部品（RBMHeroFxBase）を土台にする。
## 戦闘の結果は読むだけ（命中は stage._strike()、何回も当たる表示は stage.begin_multi_hit()）。
## 呼び出しは rbm_dragon_presentation.gd（攻撃4種だけ。強化・回復は今までどおり）。

const Body := preload("res://src/bossmaker/visuals/rbm_dragon_body.gd")
const Camera := preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const TempoMap := preload("res://src/bossmaker/visuals/rbm_tempo_map.gd")
const AudioCatalog := preload("res://src/bossmaker/rbm_audio_catalog.gd")
const FxDive := preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_dive.gd")
const FxBreath := preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_breath.gd")
const FxMeteors := preload("res://src/bossmaker/visuals/dragon/rbm_dragon_fx_meteors.gd")
const POST_MARGIN := 32.0
## 画面全体の処理（post.gdshader）に効果を出す値。どれも0で輪のゆがみも無い時、シェーダーは画面をそのまま返すので、
## その間は矩形を消す（毎コマの画面全体の写し取りと処理を省く。絵は1画素も変わらない。2026-11-27 重さの改善）
const POST_EFFECTS := ["flash", "impact", "vig", "desat", "chroma", "radial", "split_amt", "split_gap", "corrupt"]
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}
## 息吹・隕石は今までの完成トラック（溜め・解放・命中が入った1本の音）をそのまま使う。急降下はステージの共通の音＋咆哮（fx の sounds()）
const RANGED_SOUNDS := {"breath": "dragon_normal_breath", "focused_breath": "dragon_awakened_breath", "meteors": "dragon_awakened_meteors"}
## 解放の合図（ステージの共通の "release" の音）。急降下は飛び立つ時
const RELEASE := {"dive": 1.12, "breath": 0.78, "focused_breath": 0.82, "meteors": 0.54}
## 戦闘テンポ（rbm_tempo_map.gd）で詰める区間。2026-11-26 の新しい演出は、最後まで煙・火の粉・砂煙が消えていく途中で
## 画面が止まっている区間が無いので、どの技も詰めない（前の演出の表は前の絵の止まった区間を詰めていた。2026-11-28 に前の演出ごと削除）。
const TEMPO := {}
## エフェクトが使うシェーダー（事前読み込みで中身の準備まで済ませる。初めての再生の止まりを防ぐ）
const SHADER_PATHS: Array[String] = [
	"res://src/bossmaker/visuals/dragon/shaders/dragon_breath.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/orb.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/cracks.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader",
]

## 事前読み込み（rbm_presentation_warmup.gd）で読む物: シェーダーと、急降下の咆哮の声
static func warm_paths(action: String) -> Array[String]:
	var out: Array[String] = SHADER_PATHS.duplicate()
	if action == "dive":
		out.append(str(AudioCatalog.FILES["dragon_roar"]))
	return out

static func tempo(action: String) -> Array:
	return TEMPO.get(action, [])

var action := "breath"
var active := false
var age := -1.0
var duration := 2.0
var impact_time := 1.0
var _stage: Control
var _fx: RBMDragonFxBase
var _world: Node2D
var _dim: ColorRect
var _post: ColorRect
var _back: Node2D
var _mid: Node2D
var _front: Node2D
var _body: Node2D
var _ghosts: Array = []
var _camera: RefCounted
var _home := Vector2.ZERO
var _slot_keys: Array[String] = []
var _hit := false
var _released := false
var _sound_started := false
var _boss_visible := true
var _flashed := {}
var _restored := false
var _multi := false
var _sound_index := 0

func play(stage: Control, action_kind: String, awakened: bool, attribute: String) -> Tween:
	_stage = stage
	action = action_kind
	active = true
	z_index = 0
	stage._playing = true
	# 前の演出と同じ呼び名（噛みつきの代わりの急降下も "dragon_bite"）
	stage._phase = "dragon_" + ("bite" if action == "dive" else action)
	stage._motion_offset = Vector2.ZERO
	for key in stage._counters:
		stage._counter_offsets[key] = Vector2.ZERO
	_home = stage._foot("boss")
	_boss_visible = stage._visuals["boss"].visible
	stage._visuals["boss"].visible = false
	for key in stage._targets:
		if key != "boss":
			_slot_keys.append(key)
	match action:
		"dive":
			_fx = FxDive.new()
		"meteors":
			_fx = FxMeteors.new()
		_:
			_fx = FxBreath.new()
			_fx.set("focused", action == "focused_breath")
	_fx.attr = attribute
	_fx.awakened = awakened
	_fx.count = maxi(1, _slot_keys.size())
	_fx.home = _home * 0.5
	_build()
	duration = _fx.duration()
	impact_time = _fx.impact()
	# 何回も当たる攻撃（息吹・集中の息吹・隕石）: 途中の当たりで小さな数字、最後の一撃で合計
	var mp: Dictionary = _fx.multi_plan()
	if not mp.is_empty():
		var plan := {}
		for slot in mp:
			if int(slot) < _slot_keys.size():
				plan[_slot_keys[int(slot)]] = (mp[slot] as Array).duplicate()
		stage.begin_multi_hit(plan, _fx.final_share())
		_multi = true
	_advance(0.0)
	stage._play_se("cast")
	if not stage._guards.is_empty():
		stage._sound.play_sound("cover_move", -5)
	var tween := create_tween()
	# 戦闘テンポ（2026-10-16）: 詰める区間があれば詰め、完成トラックも同じ時刻へ合わせ直す（今の新しい演出は区間なし）
	TempoMap.tween_timeline(tween, _advance, duration, tempo(action), _jump_track)
	if stage._samurai_finish:
		tween.tween_callback(_restore)
		var counter_duration: float = stage.SAMURAI_WIND_START_DELAY + stage.SamuraiWind.AFTERMATH_START + stage.SamuraiWind.AFTERMATH_DURATION + .05
		tween.tween_method(stage._samurai_finish_progress, 0.0, counter_duration, counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore)
		tween.tween_method(stage._counter_progress, 0.0, 1.0, .20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(_restore)
	tween.tween_callback(stage._finish)
	return tween

func _build() -> void:
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_dim.size = _stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_dim.z_index = 1
	_dim.color = Color(0, 0, 0, 0)
	add_child(_dim)
	_world = Node2D.new()
	_world.scale = Vector2(2, 2)
	add_child(_world)
	_back = _layer("DragonBack", 1)
	_mid = _layer("DragonMid", 3)
	_front = _layer("DragonFront", 5)
	for i in range(4):
		var g: Node2D = Body.new()
		g.z_index = 4
		g.visible = false
		add_child(g)
		g.configure(_stage)
		_ghosts.append(g)
	_body = Body.new()
	_body.z_index = 4
	add_child(_body)
	_body.configure(_stage)
	var targets := []
	for key in _slot_keys:
		targets.append((_stage._foot(key) + Vector2(_stage._guard_offsets.get(key, Vector2.ZERO))) * 0.5)
	if targets.is_empty():
		targets.append(Vector2(200, 260))
	_fx.mid = _mid
	_world.add_child(_fx)
	_fx.setup(_back, _front, targets)
	_post = ColorRect.new()
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_post.size = _stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_post.z_index = 6
	var pm := ShaderMaterial.new()
	pm.shader = RBMHeroFx.shader("post")
	_post.material = pm
	add_child(_post)
	_camera = Camera.new()
	_camera.attach(_stage)

func _layer(layer_name: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	n.z_index = z
	_world.add_child(n)
	return n

func _advance(t: float) -> void:
	if not active or not is_instance_valid(_stage):
		return
	age = t
	var st: Dictionary = _fx.body_at(t)
	var hidden := bool(st.get("hidden", false))
	_body.visible = not hidden
	var state := {"pose": int(st.get("pose", 0)), "foot": _home + Vector2(st.get("off", Vector2.ZERO)), "scale": st.get("scale", Vector2.ONE), "neck": 0.0}
	_body.advance(state)
	var ghosts: Array = st.get("ghosts", [])
	for i in range(_ghosts.size()):
		var g: Node2D = _ghosts[i]
		if i < ghosts.size() and not hidden:
			var gd: Dictionary = ghosts[i]
			g.visible = true
			g.advance({"pose": int(gd.pose), "foot": _home + Vector2(gd.off), "scale": state.scale, "neck": 0.0})
			# 残像: 同じ絵を属性の色に寄せて薄く（形は変えない）
			var tint := _fx.col(5).lerp(Color.WHITE, 0.35)
			g.modulate = Color(tint.r, tint.g, tint.b, float(gd.a))
		else:
			g.visible = false
	_fx.mouth = _body.mouth_point() * 0.5
	_fx.eye = _body.eye_point() * 0.5
	_fx.advance(t, "", _home * 0.5)
	var view: Dictionary = _fx.view
	var dc: Color = view.get("dim_col", Color(0.05, 0.06, 0.12))
	dc.a = float(view.get("dim", 0.0))
	_dim.color = dc
	_allies(view, float(view.get("dim", 0.0)))
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	_camera._offset = (shake * 2.0 * _camera.shake_strength()).snapped(Vector2(2, 2))
	_camera.apply()
	_apply_post(view, t)
	if _multi:
		_stage.advance_multi_hit(t)
	var fx_sounds: Array = _fx.sounds()
	while _sound_index < fx_sounds.size() and t >= float(fx_sounds[_sound_index][0]):
		_stage._sound.play_sound(str(fx_sounds[_sound_index][1]), float(fx_sounds[_sound_index][2]))
		_sound_index += 1
	if t >= float(RELEASE.get(action, 0.3)) and not _released:
		_released = true
		_stage._play_se("release")
	if t >= impact_time and not _hit:
		_hit = true
		_stage._strike()

func _allies(view: Dictionary, dim: float) -> void:
	var ally_views: Array = view.get("allies", [{}, {}, {}, {}])
	for key in _stage._party_keys:
		var visual: Control = _stage._visuals.get(key)
		if not is_instance_valid(visual):
			continue
		var slot := _slot_keys.find(key)
		var v: Dictionary = ally_views[slot] if slot >= 0 and slot < ally_views.size() else {}
		var k := 1.0 - minf(dim * 0.73, 0.8)
		var c := Color(k, k, k, 1.0)
		var lit := float(v.get("lit", 0.0))
		if lit > 0.0:
			c = c.lerp(Color(v.get("lit_col", Color.WHITE)) * 1.2, lit * 0.35)
			c.a = 1.0
		visual.self_modulate = c
		if _stage._guards.has(key):
			var progress := smoothstep(0.0, 0.5, age) * (1.0 - smoothstep(duration - 0.5, duration, age))
			visual.position = (Vector2(_stage._homes[key]) + Vector2(_stage._guard_offsets[key]) * progress).round()
			_stage._pose(key, 10)
			continue
		if slot < 0:
			continue
		var force := float(v.get("force", 0.0))
		visual.position = (Vector2(_stage._homes[key]) + Vector2(-13.0 * force - float(v.get("back", 0.0)), -8.0 * force - float(v.get("lift", 0.0))) * 2.0).round()
		if float(v.get("flash", 0.0)) > 0.45:
			if not _flashed.get(key, false):
				_flashed[key] = true
				_stage._flash(key)
		else:
			_flashed[key] = false
		if force > 0.08 or float(v.get("lift", 0.0)) > 2.0:
			_stage._pose(key, 10 if _stage._counters.has(key) else 11)
		else:
			var unit: Dictionary = _stage._unit_state(key)
			_stage._pose(key, 11 if unit.get("is_downed", false) else (10 if unit.get("is_defending", false) or _stage._counters.has(key) else 0))

## 画面全体の処理に効果が出るか（POST_EFFECTS のどれかが0より大きい・色味 tint が白でない・輪のゆがみがある）
static func post_active(view: Dictionary) -> bool:
	if not (view.get("rings", []) as Array).is_empty():
		return true
	var post_values: Dictionary = view.get("post", {})
	for k in POST_EFFECTS:
		if float(post_values.get(k, 0.0)) > 0.0:
			return true
	return post_values.has("tint") and Color(post_values["tint"]) != Color.WHITE

func _apply_post(view: Dictionary, t: float) -> void:
	_post.visible = post_active(view)
	if not _post.visible:
		return
	var pm := _post.material as ShaderMaterial
	pm.set_shader_parameter("time", t)
	for k in POST_DEFAULTS:
		pm.set_shader_parameter(k, POST_DEFAULTS[k])
	pm.set_shader_parameter("focus", Vector2(0.5, 0.5))
	var post_values: Dictionary = view.get("post", {})
	for k in post_values:
		var value: Variant = post_values[k]
		if k == "focus_world":
			pm.set_shader_parameter("focus", _uv(value))
		else:
			pm.set_shader_parameter(k, value)
	var rings := PackedVector4Array()
	var screen := get_viewport_rect().size
	var scale_y := 2.0 * _stage.get_global_transform_with_canvas().get_scale().y / maxf(screen.y, 1.0)
	for ring in view.get("rings", []):
		var ruv := _uv(Vector2(ring.x, ring.y))
		rings.append(Vector4(ruv.x, ruv.y, ring.z * scale_y, ring.w))
		if rings.size() >= 6:
			break
	var count := rings.size()
	while rings.size() < 6:
		rings.append(Vector4.ZERO)
	pm.set_shader_parameter("rings", rings)
	pm.set_shader_parameter("ring_count", count)

func _uv(p: Vector2) -> Vector2:
	var canvas := _stage.get_global_transform_with_canvas() * (p * 2.0)
	return canvas / get_viewport_rect().size

## 完成トラックの再生位置を、詰めた区間の先の演出の時刻へ合わせ直す（rbm_tempo_map.gd）
func _jump_track(t: float) -> void:
	if RANGED_SOUNDS.has(action) and is_instance_valid(_stage) and is_instance_valid(_stage._sound):
		_stage._sound.jump(RANGED_SOUNDS[action], t)

func play_sound_phase(phase: String) -> bool:
	if not RANGED_SOUNDS.has(action):
		return false
	if phase == "cast" and not _sound_started:
		_sound_started = true
		_stage._sound.play_sound(RANGED_SOUNDS[action])
	return true

func _restore() -> void:
	if _restored:
		return
	_restored = true
	if _camera != null:
		_camera.reset()
	if is_instance_valid(_stage):
		_stage._visuals["boss"].visible = _boss_visible
		_stage._visuals["boss"].position = _stage._homes["boss"]
		for key in _stage._party_keys:
			var visual: Control = _stage._visuals.get(key)
			if is_instance_valid(visual):
				visual.self_modulate = Color.WHITE
				visual.position = _stage._homes[key]
	for n in [_world, _dim, _post, _body]:
		if is_instance_valid(n):
			(n as CanvasItem).visible = false
	for g in _ghosts:
		(g as CanvasItem).visible = false

func stop() -> void:
	_restore()
	active = false
	visible = false
	_stage = null
