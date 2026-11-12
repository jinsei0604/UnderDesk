extends Node2D
## ヒーロー（hero_boss）の技の再生（表示専用）。戦闘はすでに決まった行動を読むだけで、HP・乱数・行動順・保存データには触れない。
## 覚醒前: 単体＝導光抜刃（blade）、全体＝救難照射（array）。覚醒＝安全限界解除（breach）。
## 覚醒後: 単体＝逆刃・交差断裁（shear）、全体＝双鏡執行・落陽断（press）。2026-11-09〜10 にユーザーが確認動画で採用した内容。
## 本体は正式モーション（rbm_hero_boss_motion.gd）を整数の座標で置くだけ。エフェクトは rbm_hero_fx_*.gd が 640×360 の論理ドットで描き、
## ここで2倍してステージ（全画面の並び 1280×720）へ重ねる。音は技ごとに1本の専用トラック（assets_bossmaker/audio/hero_boss）。
## 重なり（このノードの中の z）: 暗さ1・後ろの効果1 ＜ 味方2 ＜ 中の効果3 ＜ 本体とオーラ4 ＜ 前の効果5 ＜ 画面全体の処理6。

const Motion := preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_motion.gd")
const Camera := preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const AudioCatalog := preload("res://src/bossmaker/rbm_audio_catalog.gd")
const SCENE_SCRIPTS := {
	"blade": preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_blade.gd"),
	"array": preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_array.gd"),
	"breach": preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_breach.gd"),
	"shear": preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_shear.gd"),
	"press": preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_press.gd"),
}
const PressFx := preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_fx_press.gd")
const SOUND_KEYS := {"blade": "hero_boss_single", "array": "hero_boss_all", "breach": "hero_boss_awakening", "shear": "hero_boss_awakened_single", "press": "hero_boss_awakened_all"}
const SHADERS := ["actor", "aura", "blast", "cracks", "dark_aura", "fissure", "orb", "pillar", "pool", "post", "ribbon", "ring"]
## 基準の並び（論理ドット）: 本体の足元と、味方の4か所（rbm_battle_stage.gd の全画面の並びの半分。エフェクトの番号の順）。
const HOME_FOOT := Vector2(390, 238)
const PARTY := [Vector2(137, 185), Vector2(214, 203), Vector2(137, 245), Vector2(214, 263)]
## 単体攻撃の基準の相手（右手前）
const SINGLE_SLOT := 3
## 立ち位置が動かない技の足元（コマごとに矩形の幅が違うので、足元の効果はこの位置に固定する）
const LOCK_FOOT := {"array": Vector2(390, 238), "breach": Vector2(390, 238)}
## 影を置く地面の線 [立ち位置 x, y, 踏み込み先 x, y]
const GROUND := {"blade": [393, 238, 243, 270], "array": [390, 238, 390, 238], "breach": [390, 238, 390, 238], "shear": [391, 238, 242, 266], "press": [388, 238, 284, 276]}
## 単体攻撃で相手の前まで踏み込んだ時の足元の x（基準の相手の時）。ここまでの進み具合で、相手の位置へのずれを足す。
const REACH_X := {"blade": 243.0, "shear": 242.0}
const AURA_STYLES := {"blade": "blue", "array": "blue_big", "breach": "dark", "shear": "dark", "press": "dark"}
## 1回の行動のダメージを、途中の当たりで分けて見せる時の最後の一撃の割合
const FINAL_SHARE := {"blade": .6, "array": .4, "shear": .5, "press": .4}
const VOLUME_DB := -8.0
const POST_MARGIN := 32.0
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}

var kind := "single"
var scene := "blade"
var duration := 3.0
var impact_time := 1.0
var age := 0.0
var active := false
var awakened := false
var timing: Dictionary = {}

var _stage: Control
var _fx: RBMHeroFxBase
var _world: Node2D
var _back: Node2D
var _mid: Node2D
var _front: Node2D
var _actor: Node2D
var _dim: ColorRect
var _post: ColorRect
var _body: Sprite2D
var _body_mat: ShaderMaterial
var _shadow: Polygon2D
var _aura: RBMHeroDarkAura
var _audio: AudioStreamPlayer
var _camera: RefCounted
var _sheet: Texture2D
var _offset := Vector2.ZERO
var _focus_delta := Vector2.ZERO
var _slot_keys: Array = ["", "", "", ""]
var _flashed := {}
var _hit := false
var _boss_visible := true
var _restored := false

func is_hero_boss() -> bool:
	return true

## 技 → 再生する場面。
static func scene_for(asset_id: String, action_kind: String) -> String:
	var aw := asset_id.ends_with("_awakened")
	match action_kind:
		"awakening": return "breach"
		"all", "aoe": return "press" if aw else "array"
		_: return "shear" if aw else "blade"

## 事前読み込み（rbm_presentation_warmup.gd）。kind はステージの "single" / "all" / "awakening"。
static func warm_paths(asset_id: String, action_kind: String) -> Array[String]:
	var s := scene_for(asset_id, action_kind)
	var out: Array[String] = [Motion.SHEET_PATH, str(AudioCatalog.FILES[SOUND_KEYS[s]])]
	for name in SHADERS:
		out.append("res://src/bossmaker/visuals/hero_boss/shaders/%s.gdshader" % name)
	for cel in Motion.cels_of(s):
		out.append(RBMHeroDarkAura.field_path(cel))
	if s == "breach":
		out.append(RBMHeroDarkAura.field_path(Motion.STANCE["awakened"]))
		out.append(RBMVisualAssets.frame_path("hero_boss_awakened", 0))
	return out

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	awakened = str(stage._asset_ids.get("boss", "")) == "hero_boss_awakened"
	scene = scene_for(str(stage._asset_ids.get("boss", "")), kind)
	timing = Motion.TIMINGS[scene]
	duration = float(timing["duration"])
	impact_time = _impact_time()
	stage._playing = true
	stage._phase = "hero_boss_" + scene
	stage._motion_offset = Vector2.ZERO
	if kind == "awakening":
		stage._awakened_appearance_applied = false
	for key in stage._counters:
		stage._counter_offsets[key] = Vector2.ZERO
	_boss_visible = stage._visuals["boss"].visible
	stage._visuals["boss"].visible = false
	_offset = stage._foot("boss") - HOME_FOOT * 2.0
	_map_party()
	_build()
	_audio = AudioStreamPlayer.new()
	_audio.stream = load(AudioCatalog.FILES[SOUND_KEYS[scene]])
	_audio.volume_db = VOLUME_DB
	add_child(_audio)
	stage._sound.history.append(SOUND_KEYS[scene])
	if stage._sound.history.size() > 64:
		stage._sound.history.pop_front()
	stage.visibility_changed.connect(_visibility_changed)
	if not stage._sound.muted:
		_audio.play()
	if not stage._guards.is_empty():
		stage._sound.play_sound("cover_move", -5)
	# 何回も当たる攻撃: 途中の当たりのたびに小さな数字、最後の一撃（impact）で合計（stage.begin_multi_hit()）
	if kind != "awakening":
		stage.begin_multi_hit(_multi_hit_plan(), float(FINAL_SHARE.get(scene, .5)))
	_advance(0.0)
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, duration, duration)
	if kind == "awakening":
		tween.tween_callback(_reveal_awakened)
		tween.tween_callback(stage._finish_awakening_entry)
		return tween
	if stage._samurai_finish:
		tween.tween_callback(_restore)
		var counter_duration: float = stage.SAMURAI_WIND_START_DELAY + stage.SamuraiWind.AFTERMATH_START + stage.SamuraiWind.AFTERMATH_DURATION + .05
		tween.tween_method(stage._samurai_finish_progress, 0.0, counter_duration, counter_duration)
	elif not stage._counters.is_empty():
		tween.tween_callback(_restore)
		tween.tween_method(stage._counter_progress, 0.0, 1.0, .20)
		tween.tween_callback(stage._counter_impact)
	tween.tween_callback(stage._finish)
	return tween

## 最後の一撃（impact。HP の表示が変わる所）の時刻。
func _impact_time() -> float:
	match scene:
		"blade": return float(timing["seam"])
		"array": return float(timing["final"])
		"shear": return float(timing["final"])
		"press": return float(timing["rupture"])
	return float(timing.get("complete", duration))

## 最後の一撃より前の当たり（相手ごとの時刻）。
func _multi_hit_plan() -> Dictionary:
	var plan := {}
	match scene:
		"blade":
			_add_hit(plan, _slot_keys[SINGLE_SLOT], float(timing["contact"]))
		"shear":
			_add_hit(plan, _slot_keys[SINGLE_SLOT], float(timing["cut1"]))
			_add_hit(plan, _slot_keys[SINGLE_SLOT], float(timing["cut2"]))
		"array":
			var pulses: Array = timing["pulses"]
			for j in range(4):
				_add_hit(plan, _slot_keys[j], float(pulses[j]))
		"press":
			var hits: Array = timing["hits"]
			for i in range(4):
				_add_hit(plan, _slot_keys[PressFx.ORDER[i]], float(hits[i]))
	return plan

func _add_hit(plan: Dictionary, key: String, at: float) -> void:
	if key.is_empty() or at >= impact_time - .001:
		return
	if not plan.has(key):
		plan[key] = []
	plan[key].append(at)

## 今回の相手を、エフェクトの基準の4か所へ割り当てる（全体攻撃は近い所、単体攻撃は右手前の1か所）。
func _map_party() -> void:
	_slot_keys = ["", "", "", ""]
	var keys: Array[String] = []
	for key in _stage._targets:
		if key != "boss":
			keys.append(str(key))
	_focus_delta = Vector2.ZERO
	if scene in ["blade", "shear"]:
		if not keys.is_empty():
			_slot_keys[SINGLE_SLOT] = keys[0]
			_focus_delta = _to_world(_target_foot(keys[0])) - PARTY[SINGLE_SLOT]
		return
	for key in keys:
		var p := _to_world(_target_foot(key))
		var best := -1
		for i in range(4):
			if _slot_keys[i] != "":
				continue
			if best < 0 or p.distance_to(PARTY[i]) < p.distance_to(PARTY[best]):
				best = i
		if best >= 0:
			_slot_keys[best] = key

func _target_foot(key: String) -> Vector2:
	return _stage._foot(key) + Vector2(_stage._guard_offsets.get(key, Vector2.ZERO))

func _to_world(p: Vector2) -> Vector2:
	return (p - _offset) * 0.5

func _build() -> void:
	z_index = 0
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.position = Vector2(-POST_MARGIN, -POST_MARGIN)
	_dim.size = _stage.size + Vector2.ONE * POST_MARGIN * 2.0
	_dim.z_index = 1
	_dim.color = Color(0, 0, 0, 0)
	add_child(_dim)
	_world = Node2D.new()
	_world.scale = Vector2(2, 2)
	_world.position = _offset
	add_child(_world)
	_back = _layer("HeroBack", 1)
	_mid = _layer("HeroMid", 3)
	_actor = _layer("HeroBody", 4)
	_front = _layer("HeroFront", 5)
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(16):
		pts.append(Vector2(cos(i * TAU / 16) * 18.0, sin(i * TAU / 16) * 2.2))
	_shadow.polygon = pts
	_shadow.color = Color8(44, 44, 59)
	_actor.add_child(_shadow)
	_aura = RBMHeroDarkAura.new()
	_actor.add_child(_aura)
	_aura.setup(str(AURA_STYLES[scene]))
	_sheet = load(Motion.SHEET_PATH) as Texture2D
	_body = Sprite2D.new()
	_body.texture = _sheet
	_body.region_enabled = true
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = RBMHeroFx.shader("actor")
	_body.material = _body_mat
	_actor.add_child(_body)
	_fx = (SCENE_SCRIPTS[scene] as GDScript).new()
	_fx.mid = _mid
	_fx.focus_delta = _focus_delta if scene in ["blade", "shear"] else Vector2.ZERO
	var targets := []
	for i in range(4):
		var key: String = _slot_keys[i]
		_fx.present[i] = not key.is_empty() or scene in ["blade", "shear"]
		targets.append(_to_world(_stage._foot(key)) if not key.is_empty() and not scene in ["blade", "shear"] else PARTY[i])
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
	var row := Motion.at(scene, t)
	var cel := str(row[0])
	var r := Motion.rect(cel)
	var raw_foot := Motion.foot_of(cel, row[1])
	var reach := 0.0
	if REACH_X.has(scene):
		reach = clampf((HOME_FOOT.x - raw_foot.x) / (HOME_FOOT.x - float(REACH_X[scene])), 0.0, 1.0)
	var foot := raw_foot + _focus_delta * reach
	_fx.advance(t + float(timing.get("offset", 0.0)), cel, LOCK_FOOT.get(scene, foot), foot)
	var view: Dictionary = _fx.view
	var hero_info: Dictionary = view.get("hero", {})
	var dim := float(view.get("dim", 0.0))
	var dc: Color = view.get("dim_col", Color(0.05, 0.06, 0.12))
	dc.a = dim
	_dim.color = dc
	# 本体
	_body.region_rect = r
	_body.position = (foot + Vector2(float(hero_info.get("dx", 0.0)), 0.0) - Vector2(round(r.size.x * 0.5), r.size.y)).round()
	_body_mat.set_shader_parameter("tint_amt", float(hero_info.get("tint", 0.0)))
	_rim(_body_mat, hero_info)
	var hot: Vector2 = hero_info.get("crawl_center", Vector2(.5, .3))
	_body_mat.set_shader_parameter("crawl", float(hero_info.get("crawl", 0.0)))
	_body_mat.set_shader_parameter("crawl_center", (r.position + hot * r.size) / _sheet.get_size())
	_body_mat.set_shader_parameter("flash", float(hero_info.get("flash", 0.0)))
	_body_mat.set_shader_parameter("flash_col", hero_info.get("flash_col", Color.WHITE))
	_body_mat.set_shader_parameter("silhouette", float(hero_info.get("silhouette", 0.0)))
	_body_mat.set_shader_parameter("sil_col", hero_info.get("sil_col", Color(.02, .01, .04)))
	# 影とオーラ（跳んでいる間は影を小さく）
	var g: Array = GROUND[scene]
	var u := 0.0 if g[0] == g[2] else clampf((float(g[0]) - raw_foot.x) / (float(g[0]) - float(g[2])), 0.0, 1.0)
	var ground_y := lerpf(float(g[1]), float(g[3]), u) + _focus_delta.y * reach
	var lift := maxf(0.0, ground_y - foot.y)
	_shadow.position = Vector2(foot.x, ground_y - 0.5)
	_shadow.scale = Vector2.ONE * (18.0 - minf(11.0, lift * 0.12)) / 18.0
	_aura.show_on(cel, _body.position, Vector2(foot.x, ground_y), lift, float(hero_info.get("dark_aura", 0.0)), t, float(hero_info.get("dark_rise", 1.0)))
	_allies(view, dim, hero_info)
	# 揺れ（戦場のカメラ。強さの設定 presentation_shake_strength を掛ける）
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	_camera._offset = (shake * 2.0 * _camera.shake_strength()).snapped(Vector2(2, 2))
	_camera.apply()
	_apply_post(view, t)
	_stage.advance_multi_hit(t)
	if t >= impact_time and not _hit and kind != "awakening":
		_hit = true
		_stage._strike()

## 味方の反応（のけぞり・光・暗さ）。表示だけ（self_modulate と位置・姿勢）。終わりに元へ戻す。
func _allies(view: Dictionary, dim: float, hero_info: Dictionary) -> void:
	var ally_views: Array = view.get("allies", [{}, {}, {}, {}])
	var sil := float(hero_info.get("ally_sil", 0.0))
	for key in _stage._party_keys:
		var visual: Control = _stage._visuals.get(key)
		if not is_instance_valid(visual):
			continue
		var slot := _slot_keys.find(key)
		var v: Dictionary = ally_views[slot] if slot >= 0 else {}
		var k := (1.0 - minf(dim * 0.73, 0.8)) * (1.0 - 0.95 * sil)
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
		if slot < 0 or not _stage._targets.has(key):
			continue
		var force := float(v.get("force", 0.0))
		visual.position = (Vector2(_stage._homes[key]) + Vector2(-13.0 * force - float(v.get("back", 0.0)), -8.0 * force - float(v.get("lift", 0.0))) * 2.0).round()
		if float(v.get("flash", 0.0)) > 0.45:
			if not _flashed.get(key, false):
				_flashed[key] = true
				_stage._flash(key)
		else:
			_flashed[key] = false
		if force > 0.08:
			_stage._pose(key, 10 if _stage._counters.has(key) else 11)
		else:
			var state: Dictionary = _stage._unit_state(key)
			_stage._pose(key, 11 if state.get("is_downed", false) else (10 if state.get("is_defending", false) or _stage._counters.has(key) else 0))

func _rim(m: ShaderMaterial, v: Dictionary) -> void:
	m.set_shader_parameter("rim_amt", float(v.get("lit", 0.0)))
	m.set_shader_parameter("rim_col", v.get("lit_col", Color.WHITE))
	m.set_shader_parameter("rim_side", float(v.get("lit_side", 1.0)))

## 画面全体の処理（屈折・画面の断裂・ノイズの乱れ・色調・周辺減光）。座標は画面の UV へ直す。
func _apply_post(view: Dictionary, t: float) -> void:
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
		elif k == "split_world":
			pm.set_shader_parameter("split_p", _uv(value))
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
	var canvas := _stage.get_global_transform_with_canvas() * (p * 2.0 + _offset)
	return canvas / get_viewport_rect().size

## 覚醒の最後: 本体を覚醒後の立ち姿（常時オーラつき）へ替える。
func _reveal_awakened() -> void:
	if not is_instance_valid(_stage):
		return
	_stage._awakened_appearance_applied = true
	_stage._apply_awakened_appearance()
	_restore()

func play_sound_phase(_phase: String) -> bool:
	return true

func _visibility_changed() -> void:
	if is_instance_valid(_audio) and is_instance_valid(_stage):
		_audio.stream_paused = not _stage.is_visible_in_tree()

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
		if _stage.visibility_changed.is_connected(_visibility_changed):
			_stage.visibility_changed.disconnect(_visibility_changed)
	if is_instance_valid(_audio):
		_audio.stop()
	for n in [_world, _dim, _post]:
		if is_instance_valid(n):
			n.visible = false

func stop() -> void:
	_restore()
	active = false
	visible = false
	_stage = null
