extends Node2D
## 振り子の給仕長／終刻の給仕長（clock）の技の再生（表示専用）。戦闘はすでに決まった行動を読むだけで、HP・乱数・行動順・保存データには触れない。
## 覚醒前: 単体＝指針突き（pre_single: 定められた時刻に時を止め、止めていた一撃がまとめて届く）、全体＝時刻の指揮（pre_all: 4拍で一人ずつ打ち、12時の鐘で大時計が砕ける）。
## 覚醒＝振り子の分岐（awaken: 振り子が過去と未来に分かれ、12時でぶつかる）。覚醒後: 単体＝狂針の宣告（post_single: 宣告 → 止まった時の中の連撃 → 振り子の執行）、
## 全体＝終刻の制止（post_all: 四人それぞれの時計を止めて砕く）。2026-11-16 にユーザーが確認動画（clock_v3 と直し）で採用した内容。
## 支援・登場・撃破はユーザーの確認待ち（それまでは全ボス共通の物が使われる）。
## 他の技のキーポーズを借りる技は、エフェクトの extra_poses() に書く（今の5技は借りない）。
## 作りは金環の聖獣（rbm_lion_presentation.gd）と同じ。2026-11-16 ユーザー「どちらも実装して大丈夫」で本番へ。
## 本体は Codex のキーポーズ（RBMClockMotion）をそのまま切り替えるだけ。エフェクトは rbm_clock_fx_*.gd が 640×360 の論理ドットで描き、
## ここで2倍してステージ（全画面の並び 1280×720）へ重ねる。音は技ごとに1本の専用トラック（assets_bossmaker/audio/clock）。
## 重なり（このノードの中の z）: 暗さ1・後ろの効果1 ＜ 味方2 ＜ 中の効果3 ＜ 本体とオーラ4 ＜ 前の効果5 ＜ 画面全体の処理6。

const Camera := preload("res://src/bossmaker/visuals/rbm_battlefield_camera.gd")
const AudioCatalog := preload("res://src/bossmaker/rbm_audio_catalog.gd")
const FX_SCRIPTS := {
	"pre_single": preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_pre_single.gd"),
	"pre_all": preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_pre_all.gd"),
	"awaken": preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_awaken.gd"),
	"post_single": preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_post_single.gd"),
	"post_all": preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_post_all.gd"),
}
const SOUND_KEYS := {"pre_single": "clock_single", "pre_all": "clock_all", "awaken": "clock_awakening", "post_single": "clock_awakened_single", "post_all": "clock_awakened_all"}
## 支援の強化の音（支援はまだ無い）
const BUFF_SOUND_KEYS := {}
## 支援のポーズ（支援はまだ無い）
const SUPPORT_POSES := {}
## 演出が使うシェーダー（事前読み込みで中身の準備まで済ませる）
const SHADER_PATHS := [
	"res://src/bossmaker/visuals/hero_boss/shaders/actor.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/blast.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/ring.gdshader", "res://src/bossmaker/visuals/hero_boss/shaders/pool.gdshader",
	"res://src/bossmaker/visuals/hero_boss/shaders/post.gdshader",
	"res://src/bossmaker/visuals/clock/shaders/clockface.gdshader", "res://src/bossmaker/visuals/clock/shaders/gear.gdshader",
	"res://src/bossmaker/visuals/clock/shaders/sun_aura.gdshader",
]
const HOME_FOOT := Vector2(390, 237)
const ORIGIN := RBMClockMotion.ORIGIN
const PARTY := [Vector2(137, 185), Vector2(214, 203), Vector2(137, 245), Vector2(214, 263)]
const SINGLE_SLOT := 3
const VOLUME_DB := -8.0
const POST_MARGIN := 32.0
const POST_DEFAULTS := {"chroma": 0.0, "radial": 0.0, "split_amt": 0.0, "split_head": 99.0, "split_soft": .18, "split_gap": 0.0, "corrupt": 0.0, "desat": 0.0, "tint": Color.WHITE, "vig": 0.0, "impact": 0.0, "flash": 0.0}
const GHOSTS := 8
const SHADOW_W := 34.0

var kind := "single"
var move := "pre_single"
var duration := 3.0
var impact_time := 1.0
var age := 0.0
var active := false

var _stage: Control
var _fx: RBMClockFxBase
var _world: Node2D
var _back: Node2D
var _mid: Node2D
var _front: Node2D
var _actor: Node2D
var _dim: ColorRect
var _post: ColorRect
var _body: Sprite2D
var _body_mat: ShaderMaterial
var _ghosts: Array[Sprite2D] = []
var _shadow: Polygon2D
var _aura: RBMClockSunAura
var _audio: AudioStreamPlayer
var _camera: RefCounted
var _textures := {}
## 借りたポーズの出どころ（{番号: [技, 何枚目]}。エフェクトの extra_poses()）。オーラの形もこの元の絵の距離を使う
var _extra_src := {}
var _offset := Vector2.ZERO
var _focus_delta := Vector2.ZERO
var _slot_keys: Array = ["", "", "", ""]
var _flashed := {}
var _hit := false
var _restored := false
var _boss_visible := true

func is_clock() -> bool:
	return true

## 技 → 再生する技の名前。
static func move_for(asset_id: String, action_kind: String) -> String:
	if action_kind == "awakening":
		return "awaken"
	var form := "post" if asset_id.ends_with("_awakened") else "pre"
	if action_kind in ["support", "heal", "buff"]:
		return form + "_support"
	return form + ("_all" if action_kind in ["all", "aoe"] else "_single")

## 技が使う絵 → [[技, 番号], ...]（自分の絵と、エフェクトの extra_poses() で借りる絵。支援は回復・強化の両方の借りたポーズ）
static func pose_sources(m: String) -> Array:
	var out: Array = []
	if SUPPORT_POSES.has(m):
		for k in ["heal", "buff"]:
			out.append(SUPPORT_POSES[m][k])
		return out
	for n in range(1, RBMClockMotion.pose_count(m) + 1):
		out.append([m, n])
	var fx = (FX_SCRIPTS[m] as GDScript).new()
	var extra: Dictionary = fx.extra_poses()
	fx.free()
	for k in extra:
		var src: Array = [str(extra[k][0]), int(extra[k][1])]
		if not out.has(src):
			out.append(src)
	return out

## 事前読み込み（rbm_presentation_warmup.gd）。kind はステージの "single" / "all" / "awakening"。
static func warm_paths(asset_id: String, action_kind: String) -> Array[String]:
	var m := move_for(asset_id, action_kind)
	var out: Array[String] = [str(AudioCatalog.FILES[SOUND_KEYS[m]])]
	if BUFF_SOUND_KEYS.has(m):
		out.append(str(AudioCatalog.FILES[BUFF_SOUND_KEYS[m]]))
	for src in pose_sources(m):
		out.append(RBMClockMotion.pose_path(str(src[0]), int(src[1])))
		if RBMClockMotion.has_field(str(src[0]), int(src[1])):
			out.append(RBMClockMotion.field_path(str(src[0]), int(src[1])))
	var after := "post" if m == "awaken" or m.begins_with("post") else "pre"
	var stance: Array = RBMClockMotion.STANCE[after]
	if not out.has(RBMClockMotion.stance_path(after)):
		out.append(RBMClockMotion.stance_path(after))
	if after == "post" and not out.has(RBMClockMotion.field_path(str(stance[0]), int(stance[1]))):
		out.append(RBMClockMotion.field_path(str(stance[0]), int(stance[1])))
	if m == "awaken":
		out.append(RBMVisualAssets.frame_path("clock_awakened", 0))
	out.append_array(SHADER_PATHS)
	return out

func play(stage: Control) -> Tween:
	_stage = stage
	active = true
	move = move_for(str(stage._asset_ids.get("boss", "")), kind)
	for n in range(1, RBMClockMotion.pose_count(move) + 1):
		_textures[n] = load(RBMClockMotion.pose_path(move, n))
	# 0 番: 演出の後の立ち姿（覚醒なら覚醒後の立ち姿）
	_textures[0] = load(RBMClockMotion.stance_path("post" if move == "awaken" or move.begins_with("post") else "pre"))
	_fx = (FX_SCRIPTS[move] as GDScript).new()
	_fx.seq = move
	var heal := true
	if kind == "support":
		heal = str(stage._skill.get("effect", "")) in ["heal", "self_heal"]
		_fx.set("awakened", move.begins_with("post"))
		_fx.set("heal", heal)
	# 他の技のキーポーズを借りる（支援の回復＝全体の2枚目・強化＝3枚目など）
	_extra_src = _fx.extra_poses()
	for k in _extra_src:
		_textures[int(k)] = load(RBMClockMotion.pose_path(str(_extra_src[k][0]), int(_extra_src[k][1])))
	var sound_key: String = SOUND_KEYS[move] if heal or not BUFF_SOUND_KEYS.has(move) else BUFF_SOUND_KEYS[move]
	duration = _fx.unwarp(_fx.duration())
	impact_time = _fx.unwarp(_fx.impact())
	stage._playing = true
	stage._phase = "clock_" + move
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
	_audio.stream = load(AudioCatalog.FILES[sound_key])
	_audio.volume_db = VOLUME_DB
	add_child(_audio)
	stage._sound.history.append(sound_key)
	if stage._sound.history.size() > 64:
		stage._sound.history.pop_front()
	stage.visibility_changed.connect(_visibility_changed)
	if not stage._sound.muted:
		_audio.play()
	if not stage._guards.is_empty():
		stage._sound.play_sound("cover_move", -5)
	# 何回も当たる攻撃: 途中の当たりのたびに小さな数字、最後の一撃（impact）で合計（stage.begin_multi_hit()）
	if kind != "awakening" and kind != "support":
		var share: Variant = _fx.get("final_share")
		stage.begin_multi_hit(_multi_hit_plan(), float(share) if share != null else 0.5)
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

func _multi_hit_plan() -> Dictionary:
	var plan := {}
	for h in _fx.hits():
		var key: String = _slot_keys[int(h[1])]
		var at: float = _fx.unwarp(float(h[0]))
		if key.is_empty() or at >= impact_time - .001:
			continue
		if not plan.has(key):
			plan[key] = []
		plan[key].append(at)
	return plan

## 今回の相手を、エフェクトの基準の4か所へ割り当てる（全体攻撃は近い所、単体攻撃は右手前の1か所）。
func _map_party() -> void:
	_slot_keys = ["", "", "", ""]
	var keys: Array[String] = []
	for key in _stage._targets:
		if key != "boss":
			keys.append(str(key))
	_focus_delta = Vector2.ZERO
	if kind == "single":
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
	_back = _layer("ClockBack", 1)
	_mid = _layer("ClockMid", 3)
	_actor = _layer("ClockBody", 4)
	_front = _layer("ClockFront", 5)
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		pts.append(Vector2(cos(i * TAU / 20) * SHADOW_W, sin(i * TAU / 20) * 2.6))
	_shadow.polygon = pts
	_shadow.color = Color8(30, 30, 42, 200)
	_actor.add_child(_shadow)
	# 覚醒後の常時オーラ（本体の後ろ）。強さは技の view["hero"]["sun_aura"]（無ければ覚醒後の技で1、それ以外0）
	_aura = RBMClockSunAura.new()
	_actor.add_child(_aura)
	_aura.setup()
	var actor_shader := RBMHeroFx.shader("actor")
	for i in range(GHOSTS):
		var g := Sprite2D.new()
		g.centered = false
		g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var gm := ShaderMaterial.new()
		gm.shader = actor_shader
		gm.set_shader_parameter("silhouette", 1.0)
		g.material = gm
		g.visible = false
		_actor.add_child(g)
		_ghosts.append(g)
	_body = Sprite2D.new()
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = actor_shader
	_body.material = _body_mat
	_actor.add_child(_body)
	_fx.mid = _mid
	_fx.focus_delta = _focus_delta if kind == "single" else Vector2.ZERO
	var targets := []
	for i in range(4):
		var key: String = _slot_keys[i]
		_fx.present[i] = not key.is_empty() or kind == "single"
		targets.append(_to_world(_target_foot(key)) if not key.is_empty() and kind != "single" else PARTY[i] + (_focus_delta if kind == "single" and i == SINGLE_SLOT else Vector2.ZERO))
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
	var te: float = _fx.warp(t)
	_fx.advance_pose(te)
	var view: Dictionary = _fx.view
	var body: Dictionary = view.get("body", {})
	var hero_info: Dictionary = view.get("hero", {})
	var dim := float(view.get("dim", 0.0))
	var dc: Color = view.get("dim_col", Color(0.05, 0.06, 0.12))
	dc.a = dim
	_dim.color = dc
	# 本体（キーポーズの絵をそのまま。足元をそろえて置く）
	var off: Vector2 = body.get("off", Vector2.ZERO)
	var pose := int(body.get("pose", 1))
	var tex: Texture2D = _textures.get(pose)
	_body.texture = tex
	_body.position = HOME_FOOT + off - ORIGIN
	_body.visible = not bool(body.get("hidden", false))
	_body_mat.set_shader_parameter("tint_amt", float(hero_info.get("tint", 0.0)))
	_body_mat.set_shader_parameter("tint", hero_info.get("tint_col", Color(.12, .08, .15)))
	_body_mat.set_shader_parameter("rim_amt", float(hero_info.get("lit", 0.0)))
	_body_mat.set_shader_parameter("rim_col", hero_info.get("lit_col", Color.WHITE))
	_body_mat.set_shader_parameter("rim_side", float(hero_info.get("lit_side", 0.0)))
	_body_mat.set_shader_parameter("flash", float(hero_info.get("flash", 0.0)))
	_body_mat.set_shader_parameter("flash_col", hero_info.get("flash_col", Color.WHITE))
	_body_mat.set_shader_parameter("silhouette", float(hero_info.get("silhouette", 0.0)))
	_body_mat.set_shader_parameter("sil_col", hero_info.get("sil_col", Color(.02, .01, .04)))
	_body.modulate.a = float(body.get("alpha", 1.0))
	# 残像（同じ絵の単色の影。形は変えない）
	var ghosts: Array = body.get("ghosts", [])
	for i in range(GHOSTS):
		var g := _ghosts[i]
		if i < ghosts.size():
			var gd: Dictionary = ghosts[i]
			g.visible = true
			g.texture = _textures.get(int(gd["pose"]), tex)
			g.position = HOME_FOOT + Vector2(gd["off"]) - ORIGIN
			var gm := g.material as ShaderMaterial
			gm.set_shader_parameter("sil_col", gd["col"])
			gm.set_shader_parameter("silhouette", float(gd.get("sil", 0.55)))
			g.modulate = Color(1, 1, 1, float(gd["a"]))
		else:
			g.visible = false
	# 影（跳んでいる間は小さく）
	var lift := maxf(0.0, -off.y)
	_shadow.position = Vector2(HOME_FOOT.x + off.x, HOME_FOOT.y + maxf(off.y, 0.0) + 0.5)
	_shadow.scale = Vector2.ONE * clampf(1.0 - lift * 0.012, 0.35, 1.0)
	_shadow.visible = _body.visible
	# 覚醒後の常時オーラ（今のポーズの輪郭に合わせる。立ち姿＝0番は覚醒後の立ち姿の輪郭）
	var aura_power := float(hero_info.get("sun_aura", 1.0 if move.begins_with("post") else 0.0)) * float(body.get("alpha", 1.0))
	if not _body.visible:
		aura_power = 0.0
	# 借りたポーズは元の絵の距離（2026-11-15 ユーザー「覚醒後のときオーラ消えてるときある」: 借りたポーズに距離が無く消えていた）
	var stance: Array = RBMClockMotion.STANCE["post"]
	var aura_move := move if pose > 0 else str(stance[0])
	var aura_n := pose if pose > 0 else int(stance[1])
	if _extra_src.has(pose):
		aura_move = str(_extra_src[pose][0])
		aura_n = int(_extra_src[pose][1])
	_aura.show_pose(aura_move, aura_n, _body.position, HOME_FOOT + off, aura_power, te)
	_allies(view, dim, hero_info)
	# 揺れ（戦場のカメラ。強さの設定 presentation_shake_strength を掛ける）。ヒットストップの間も小さく揺らし続ける。
	var shake: Vector2 = view.get("shake", Vector2.ZERO)
	if not is_equal_approx(te, t) and is_equal_approx(_fx.warp(t + 0.001), te):
		shake += Vector2(1.6 if int(t * 60.0) % 2 == 0 else -1.6, 0.0)
	_camera._offset = (shake * 2.0 * _camera.shake_strength()).snapped(Vector2(2, 2))
	_camera.apply()
	_apply_post(view, te)
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

## 画面全体の処理（屈折・色調・周辺減光）。座標は画面の UV へ直す。
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

## 覚醒の最後: 本体を覚醒後の立ち姿（常時の太陽のオーラつき）へ替える。
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
