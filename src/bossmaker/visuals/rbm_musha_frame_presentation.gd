extends "res://src/bossmaker/visuals/rbm_musha_presentation.gd"
## 朽ちた機械武者の「コマ送り」の演出(承認済み 2026-09-27): 覚醒前の単体「無音の居合」/全体「縦断・千切」/
## 自己強化・回復「機構調律」と、覚醒後の自己強化・回復。行動ごとの rbm_musha_single / all / support.gd が継承する。
## 元の演出(時刻・技の順番・移動・VFX・筆文字・音・ダメージ通知)はそのまま使い、本体だけを「コマ送り」にする:
## 原画のコマの間に、原画から作った追加コマ(鯉口を切る・抜き始め・納刀の途中・溜め・振り抜き後の沈み・反動・
## 調律の沈み/伸び)を挟んで動きを細かくする。絵を毎フレーム変形したり揺らしたりはしない。
## 単体は「見えない速さ」: 構えの残像だけを残して消え、対象の背後に白い輪郭とともに一瞬で現れる(移動の軌跡は描かない)。
## 支援の終わりに、足元から風の衝撃波が広がる。覚醒後の支援では、墨の層(rbm_musha_ink_director.gd)へ毎コマ経過を渡す。
## 表示専用(戦闘の状態・乱数・行動順には触れない)。
const Rig = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")

## 平らな色の輪郭(瞬間移動の残像・出現の閃き)。色と不透明度は描画時の色で渡す。
const FLAT_SHADER := """shader_type canvas_item;
varying vec4 v_col;
void vertex(){ v_col = COLOR; }
void fragment(){ COLOR = vec4(v_col.rgb, texture(TEXTURE, UV).a * v_col.a); }"""

## 本体のコマ割り [開始時刻, コマ(空=消失), 位置("home"/"behind"), 反転]
const SINGLE_KEYS := [
	[0.00, "idle"], [0.26, "p2k"], [0.40, "p0"], [0.94, "p0k"], [1.16, "p0d"],
	[1.22, ""], [1.28, "p1", "behind", true], [1.88, ""], [1.96, "p1"],
	[2.10, "p2n1"], [2.30, "p2n2"], [2.46, "p2n3"], [2.62, "p2k"], [3.30, "idle"],
]
const ALL_KEYS := [
	[0.00, "idle"], [0.45, "p2k"], [0.75, "p0"], [0.98, "p0k"], [1.05, "p0d"], [1.10, "p3"], [1.30, "p3c"],
	[1.43, "p4i"], [1.70, "p4"], [3.84, "p4i"], [4.27, "p4r"], [4.58, "p4"],
	[4.80, "p2n1"], [4.98, "p2n2"], [5.12, "p2n3"], [5.26, "p2k"], [5.62, "idle"],
]
const SUPPORT_KEYS := [
	[0.00, "idle"], [0.42, "p5d"], [0.50, "p5"], [2.22, "p5d"], [2.30, "p5u"], [2.42, "p5"], [2.65, "idle"],
]
## 瞬間移動の輪郭 [時刻, 長さ, コマ, 位置, 反転, 不透明度, 色]
const FLASHES := [
	[1.22, 0.10, "p0d", "home", false, 0.55, Color(0.80, 0.87, 1.0)],
	[1.28, 0.07, "p1", "behind", true, 0.9, Color(1, 1, 1)],
	[1.88, 0.08, "p1", "behind", true, 0.45, Color(0.80, 0.87, 1.0)],
	[1.96, 0.07, "p1", "home", false, 0.8, Color(1, 1, 1)],
]
## 支援の終わりの風の衝撃波
const SUP_WIND := 2.66

var rig_body: Node2D
var flash_node: Node2D
var fx_back: Node2D
var fx_front: Node2D
var fx_add: Node2D
var body_state: Dictionary = {}
var _flashed := {}
var _home := Vector2.ZERO
## 覚醒後の自己強化/回復のときだけ、墨の層(rbm_musha_ink_director.gd)へ毎コマの状態を渡す(ステージから受け取る)。
var director

class RigBody extends Node2D:
	var owner_p
	## 元の本体と同じ読み取り口(足元・状態)。表示の検査用で、描き方には関係しない。
	var _foot: Vector2:
		get:
			return Vector2(owner_p.body_state.get("foot", Vector2.ZERO)) if owner_p != null else Vector2.ZERO
	var _state: Dictionary:
		get:
			return owner_p.body_state if owner_p != null else {}
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if owner_p == null or owner_p.body_state.is_empty() or str(owner_p.body_state.fr) == "":
			return
		Rig.draw(self, owner_p.body_state)

class FlashLayer extends Node2D:
	var owner_p
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if owner_p != null:
			owner_p._draw_flashes(self)

class FxLayer extends Node2D:
	var owner_p
	var layer := 0
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if owner_p != null:
			owner_p._draw_fx(self, layer)

# ---------------------------------------------------------------------------
func play(stage: Control) -> Tween:
	var tw := super.play(stage)
	if director == null and stage.has_method("musha_ink_director"):
		director = stage.musha_ink_director()
	_home = motion.home
	rig_body = RigBody.new()
	rig_body.owner_p = self
	remove_child(_body)
	_body.queue_free()
	_body = rig_body
	add_child(rig_body)
	move_child(rig_body, 0)
	fx_back = _fx_layer(0, -1, false)
	move_child(fx_back, 0)
	flash_node = FlashLayer.new()
	flash_node.owner_p = self
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FLAT_SHADER
	flash_node.material = fm
	add_child(flash_node)
	move_child(flash_node, rig_body.get_index() + 1)
	fx_front = _fx_layer(1, 2, false)
	fx_add = _fx_layer(2, 3, true)
	if action_kind in ["buff", "heal"]:
		_vfx.awakened = true  # 本番の固定位置の赤い単眼の代わりに、コマの眼の位置で再点灯を描く
	_advance(0.0)
	return tw

## 再生の最初と途中で load() する素材(rbm_presentation_warmup.gd が、ボスが決まった時点で裏で読み込んで持つ)。
## 筆文字(支援でも作る)・元の本体の画像(super.play() で読んでから差し替える)・コマ・完成トラック。
static func warm_paths(asset_id: String, kind: String) -> Array[String]:
	var awakened := asset_id == "musha_awakened"
	var out: Array[String] = [Glyph.ROOT + "ink.png", Glyph.ROOT + "ice.png", Body.ROOT + "poses.png",
		(Body.AWAKENED_ROOT if awakened else Body.ROOT) + "design.png"]
	var frames: Array = []
	if kind == "support":
		frames = ["a3"] if awakened else SUPPORT_KEYS.map(func(k): return k[1])
	else:
		frames = (SINGLE_KEYS if kind == "single" else ALL_KEYS).map(func(k): return k[1])
		if kind == "single":
			frames.append_array(FLASHES.map(func(f): return f[2]))
	for fr in frames:
		if str(fr) != "":
			out.append(Rig.texture_path(str(fr)))
	var tracks: Array = ["musha_buff", "musha_heal"] if kind == "support" else (["musha_single"] if kind == "single" else ["musha_aoe"])
	for track in tracks:
		out.append(str(AudioCatalog.FILES[track]))
	return out

func _fx_layer(layer: int, z: int, additive: bool) -> Node2D:
	var f := FxLayer.new()
	f.owner_p = self
	f.layer = layer
	f.z_index = z
	if additive:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		f.material = add
	add_child(f)
	return f

func _tk() -> String:
	return "support" if action_kind in ["buff", "heal"] else action_kind

func _advance(t: float) -> void:
	if rig_body == null:
		super._advance(t)
		return
	if not active or not is_instance_valid(_stage):
		return
	age = t
	var tk := _tk()
	var shake := Motion.shake_offset(t, motion.shake_force(tk, t)).round()
	body_state = _frame_at(tk, t)
	for n in [rig_body, flash_node, fx_back, fx_front, fx_add]:
		n.position = shake
		n.queue_redraw()
	_vfx.position = shake
	_vfx.advance(t)
	_update_glyph(tk, t, shake)
	_layout_party(tk, t, shake)
	if _awakened and is_instance_valid(director):
		var shown := body_state.duplicate()
		shown.foot = (body_state.foot as Vector2) + shake
		director.set_body(shown)
		director.advance_attack(action_kind, t, shake, {})
	if t >= impact_time and not _hit:
		_hit = true
		_stage._strike()

func stop() -> void:
	if _awakened and is_instance_valid(director):
		director.end_attack()
	super.stop()

# ---------------------------------------------------------------------------
# コマ
# ---------------------------------------------------------------------------
func _keys(tk: String) -> Array:
	match tk:
		"single":
			return SINGLE_KEYS
		"all":
			return ALL_KEYS
	return SUPPORT_KEYS

func _pos(where: String) -> Vector2:
	return motion.behind if where == "behind" else _home

func _key_state(k: Array) -> Dictionary:
	var fr: String = k[1]
	var s := Rig.state(fr, _pos(str(k[2]) if k.size() > 2 else "home"))
	s.flip = bool(k[3]) if k.size() > 3 else false
	return s

func _frame_at(tk: String, t: float) -> Dictionary:
	if _awakened and tk == "support":
		return Rig.state("a3", _home)
	var keys := _keys(tk)
	var cur: Array = keys[0]
	for k in keys:
		if t >= float(k[0]):
			cur = k
	return _key_state(cur)

func _state_at(tk: String, t: float) -> Dictionary:
	return _frame_at(tk, t)

func _draw_flashes(ci: CanvasItem) -> void:
	if _tk() != "single":
		return
	for f in FLASHES:
		var a := age - float(f[0])
		var dur: float = f[1]
		if a < 0.0 or a >= dur:
			continue
		var s := Rig.state(str(f[2]), _pos(str(f[3])))
		s.flip = bool(f[4])
		var col: Color = f[6]
		Rig.draw(ci, s, Color(col.r, col.g, col.b, float(f[5]) * (1.0 - a / dur)))

# ---------------------------------------------------------------------------
# 補助
# ---------------------------------------------------------------------------
static func sg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)

static func eo(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func eio(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

static func alt(t: float) -> float:
	return 1.0 if int(floor(t * 30.0 + 0.5)) % 2 == 0 else -1.0

static func env(x: float, t0: float, rise: float, decay: float) -> float:
	if x < t0:
		return 0.0
	return smoothstep(t0, t0 + rise, x) * exp(-maxf(0.0, x - t0 - rise) / decay)

func _fr() -> String:
	return str(body_state.get("fr", ""))

func _joint(jn: String) -> Vector2:
	var joints := {"knee": Vector2(-12, -38), "hip": Vector2(-2, -80), "chest": Vector2(-6, -112), "shoulder": Vector2(-18, -132)}
	var l: Vector2 = joints.get(jn, Vector2.ZERO)
	if bool(body_state.get("flip", false)):
		l.x = -l.x
	return (body_state.foot as Vector2) + l

# ---------------------------------------------------------------------------
# 味方: 着弾の瞬間の震え(ヒットストップ)と押し込まれる反動(本番の被弾ポーズ・画面揺れはそのまま)
# ---------------------------------------------------------------------------
func _hits(tk: String) -> Array:
	# [時刻, 止める長さ, 押される向き, 強さ]
	if tk == "single":
		return [[Motion.SINGLE_FIRST_HIT, 0.10, Vector2(1, 0), 7.0], [Motion.SINGLE_FINAL, 0.10, Vector2(-1, 0), 11.0]]
	if tk == "all":
		return [[Motion.ALL_FIRST, 0.08, Vector2(-1, 0), 6.0], [Motion.ALL_FINAL, 0.10, Vector2(-1, 0.2), 14.0]]
	return []

func _layout_party(tk: String, t: float, shake: Vector2) -> void:
	var hits := _hits(tk)
	for key in _stage._visuals:
		if key == "boss":
			continue
		var at: Vector2 = Vector2(_stage._homes[key])
		if _stage._guards.has(key):
			var progress := smoothstep(0.0, .5, t) * (1.0 - smoothstep(duration - .50, duration, t))
			at += Vector2(_stage._guard_offsets[key]) * progress
			_stage._pose(key, 10)
		elif _target_keys.has(key) and tk != "support":
			var idx := _target_keys.find(key)
			var reacting := Motion.target_reacting(tk, t, idx, _target_keys.size())
			if reacting:
				at += HIT_REACTION_OFFSET
			if reacting != bool(_reacting.get(key, false)):
				_reacting[key] = reacting
				_stage._pose(key, _reaction_pose(key, reacting))
			for h in hits:
				var t0: float = h[0]
				var hold: float = h[1]
				var dir: Vector2 = h[2]
				var k: float = h[3]
				var a := t - t0
				if a < 0.0:
					continue
				var id := "%s_%.2f" % [key, t0]
				if not _flashed.has(id) and a < 0.05:
					_flashed[id] = true
					var vis = _stage._visuals[key]
					if vis.has_method("impact_flash"):
						vis.impact_flash()
				if a < hold:
					at += Vector2(2.0 * alt(t), 0)
				else:
					var b := a - hold
					at += dir * k * (1.0 - pow(1.0 - clampf(b / 0.10, 0.0, 1.0), 2.0)) * (1.0 - smoothstep(0.18, 0.75, b))
		_stage._visuals[key].position = (at + shake).round()

# ---------------------------------------------------------------------------
# 効果: 背面(土埃・蒸気・床の風) / 前面(風の弧・瞬間移動の風・振りの軌跡) / 加算(単眼・閃き・機構の光)
# ---------------------------------------------------------------------------
func _puff(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	if r < 0.8 or col.a <= 0.01:
		return
	ci.draw_circle(p.round(), r, col)

## 土埃: 足元から横へ広がる(dir: 広がる向きの偏り)。
func _dust(ci: CanvasItem, at: Vector2, a: float, strength: float, dir: float = 0.0) -> void:
	if a < 0.0 or a > 0.7:
		return
	var q := a / 0.7
	for i in range(9):
		var side := -1.0 if i % 2 == 0 else 1.0
		var sp := (0.4 + 0.6 * fposmod(i * 0.618, 1.0)) * (1.0 + dir * side)
		var p := at + Vector2(side * (6.0 + 46.0 * sp * eo(q)) * strength, -2.0 - 10.0 * q * fposmod(i * 0.37, 1.0))
		_puff(ci, p, (2.5 + 7.0 * q) * strength * (0.6 + 0.4 * fposmod(i * 0.29, 1.0)), Color(0.46, 0.43, 0.40, 0.42 * (1.0 - q)))

## 蒸気: 関節から白く噴き、昇って消える。
func _steam(ci: CanvasItem, at: Vector2, a: float, strength: float) -> void:
	if a < 0.0 or a > 1.0:
		return
	for i in range(6):
		var q := clampf(a * 1.3 - 0.06 * i, 0.0, 1.0)
		if q <= 0.0:
			continue
		var p := at + Vector2((fposmod(i * 0.61, 1.0) - 0.5) * 16.0 * q, -26.0 * q * (0.6 + 0.4 * fposmod(i * 0.43, 1.0)))
		_puff(ci, p, (1.5 + 4.5 * q) * strength, Color(0.78, 0.80, 0.82, 0.30 * (1.0 - q)))

func _glint(ci: CanvasItem, p: Vector2, k: float, col: Color = Color(0.85, 0.92, 1.0)) -> void:
	if k <= 0.02:
		return
	var c := col * k
	ci.draw_rect(Rect2((p + Vector2(-4.0 * k - 1.0, -0.5)).round(), Vector2(roundf(8.0 * k + 2.0), 1)), c)
	ci.draw_rect(Rect2((p + Vector2(-0.5, -3.0 * k - 1.0)).round(), Vector2(1, roundf(6.0 * k + 2.0))), c)
	ci.draw_rect(Rect2((p + Vector2(-1, -1)).round(), Vector2(2, 2)), c)

func _eye_glow(ci: CanvasItem, g: float, col: Color = Color(1.0, 0.16, 0.08)) -> void:
	if g <= 0.03 or body_state.is_empty() or _fr() == "" or not Rig.has_point(body_state, "eye"):
		return
	var e := Rig.point(body_state, "eye")
	var c := col * minf(g, 1.2)
	ci.draw_rect(Rect2((e + Vector2(-5, -1)).round(), Vector2(10, 2)), c * 0.5)
	ci.draw_rect(Rect2((e + Vector2(-1.5, -1.5)).round(), Vector2(3, 3)), c)
	if g > 0.45:
		var L := 22.0 * (g - 0.35)
		ci.draw_rect(Rect2((e + Vector2(-L, -0.5)).round(), Vector2(roundf(L * 2.0), 1)), Color(1.0, 0.32, 0.18) * (g - 0.35))

## 風の帯(本番の覚醒の風と同じ作り: 1枚のテーパーしたポリゴン)。flat: 縦の潰れ(床に沿う輪は小さく)。
func _wind_arc(ci: CanvasItem, at: Vector2, r: float, start: float, span: float, c: Color, width: float, flat: float = 1.0) -> void:
	if c.a <= 0.01 or r <= 0.0:
		return
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(25):
		var q := i / 24.0
		var a := start + q * span
		var d := Vector2(cos(a), sin(a) * flat)
		var half := sin(q * PI) * width * .5
		outer.append(at + d * (r + half))
		inner.append(at + d * (r - half))
	if width <= 2.0:
		var line := PackedVector2Array()
		for i in range(25):
			line.append((outer[i] + inner[i]) * 0.5)
		ci.draw_polyline(line, c, width, false)
		return
	for i in range(23, 0, -1):
		outer.append(inner[i])
	if Geometry2D.triangulate_polygon(outer).size() > 0:
		ci.draw_colored_polygon(outer, c)

## 支援の終わりの風の衝撃波: 足元から床に沿って楕円に広がる風の輪(3重・奥半分は背面、手前半分は前面)、
## 体の左右へ弾ける風の弧、土埃。強化はわずかに暖かく、回復はわずかに緑に色づく。
func _wind_shock(ci: CanvasItem, a: float, front: bool) -> void:
	if a < 0.0 or a > 0.75:
		return
	var tone := Color(0.80, 0.85, 0.86)
	if action_kind == "buff":
		tone = tone.lerp(Color(1.0, 0.70, 0.58), 0.28)
	elif action_kind == "heal":
		tone = tone.lerp(Color(0.66, 1.0, 0.74), 0.28)
	var c := _home + Vector2(0, -2)
	for i in range(3):
		var dt := a - 0.07 * i
		if dt < 0.0 or dt > 0.6:
			continue
		var q := dt / 0.6
		var r := 26.0 + 300.0 * pow(q, 0.6)
		for j in range(6):
			var ang := j * TAU / 6.0 + i * 0.5 + q * 0.3
			if (sin(ang + 0.45) > 0.0) != front:
				continue
			_wind_arc(ci, c, r, ang, 0.9, Color(tone, (1.0 - q) * 0.6), 14.0 * (1.0 - q) + 2.0, 0.26)
	if front:
		var q2 := clampf(a / 0.45, 0.0, 1.0)
		if q2 < 1.0:
			for s in [-1.0, 1.0]:
				var c2 := _home + Vector2(0, -84)
				var r2 := 40.0 + 130.0 * pow(q2, 0.6)
				var start := (PI if s < 0.0 else 0.0) - 0.62
				_wind_arc(ci, c2, r2, start, 1.24, Color(tone, (1.0 - q2) * 0.5), 8.0 * (1.0 - q2) + 2.0)
				_wind_arc(ci, c2 + Vector2(0, 30), r2 * 0.8, start + 0.2, 0.9, Color(tone, (1.0 - q2) * 0.35), 5.0 * (1.0 - q2) + 1.0)
	else:
		_dust(ci, _home, a, 1.5)

## 振りの軌跡(白い弧): a から b へ、ctrl 側へ膨らむ。
func _swipe(ci: CanvasItem, a: Vector2, b: Vector2, ctrl: Vector2, k: float, w: float) -> void:
	if k <= 0.02:
		return
	var prev := a
	for i in range(1, 17):
		var f := float(i) / 16.0
		var p := a.lerp(ctrl, f).lerp(ctrl.lerp(b, f), f)
		var width := maxf(1.0, w * sin(PI * f))
		ci.draw_line(prev, p, Color(0.88, 0.92, 1.0, 0.75 * k), width)
		prev = p

func _pt(fr: String, key: String, where: String = "home", flip: bool = false) -> Vector2:
	var s := Rig.state(fr, _pos(where))
	s.flip = flip
	return Rig.point(s, key)

func _draw_fx(ci: CanvasItem, layer: int) -> void:
	var t := age
	var tk := _tk()
	var H: Vector2 = _home
	match layer:
		0:
			_fx_back(ci, tk, t, H)
		1:
			_fx_front(ci, tk, t, H)
		2:
			_fx_add(ci, tk, t, H)

func _fx_back(ci: CanvasItem, tk: String, t: float, H: Vector2) -> void:
	match tk:
		"single":
			_dust(ci, H, t - 0.40, 0.5)
			_dust(ci, H + Vector2(-6, 0), t - 1.22, 1.2, 0.5)
			_dust(ci, motion.behind + Vector2(8, 0), t - 1.28, 1.1)
			_dust(ci, motion.behind, t - 1.88, 0.6)
			_dust(ci, H, t - 1.96, 0.8)
			_steam(ci, _joint("shoulder"), t - 2.95, 0.8)
		"all":
			_dust(ci, H, t - 0.75, 0.6)
			_dust(ci, H + Vector2(-24, 0), t - 1.43, 1.7, -0.4)
			_dust(ci, H, t - 3.84, 0.6)
			_dust(ci, H + Vector2(-10, 0), t - 4.2, 1.2)
			_steam(ci, _joint("shoulder"), t - 4.35, 1.0)
			_steam(ci, _joint("knee") + Vector2(10, 0), t - 4.45, 0.8)
		_:
			var R: float = Motion.SUPPORT_RELIGHT
			if _awakened:
				_steam(ci, _joint("shoulder") + Vector2(14, 2), t - R, 1.0)
			else:
				_dust(ci, H, t - 0.42, 0.6)
				for lk in [[0.58, "knee"], [0.70, "hip"], [0.82, "shoulder"]]:
					_steam(ci, _joint(lk[1]) + Vector2(8, 0), t - float(lk[0]), 0.35)
				for i in range(5):
					_steam(ci, _joint("shoulder") + Vector2(12, 0), t - (1.0 + 0.28 * i), 0.22)
				_steam(ci, _joint("shoulder") + Vector2(14, 2), t - R, 1.4)
				_steam(ci, _joint("shoulder") + Vector2(-12, 4), t - (R + 0.03), 1.0)
				_steam(ci, _joint("knee"), t - (R + 0.04), 1.0)
				_steam(ci, _joint("knee") + Vector2(18, 0), t - (R + 0.08), 1.0)
				_dust(ci, H, t - R, 1.1)
			_wind_shock(ci, t - SUP_WIND, false)

func _fx_front(ci: CanvasItem, tk: String, t: float, H: Vector2) -> void:
	match tk:
		"single":
			# 消える瞬間: 構えのあった所で空気が弾ける(軌跡は描かない)
			_burst_lines(ci, H + Vector2(0, -88), t - 1.22, 1.0)
			_burst_lines(ci, motion.behind + Vector2(0, -80), t - 1.28, 0.8)
			_burst_lines(ci, motion.behind + Vector2(0, -80), t - 1.88, 0.5)
			_burst_lines(ci, H + Vector2(0, -80), t - 1.96, 0.6)
			# 戻ってからの納刀: 刀を鯉口へ運ぶ一振り(2コマ)
			if t >= 2.10 and t < 2.17:
				var k := 1.0 - (t - 2.10) / 0.07
				_swipe(ci, _pt("p1", "tip"), _pt("p2n1", "mouth") + Vector2(40, 30), H + Vector2(-60, -40), k, 5.0)
		"all":
			# 抜きながら上段へ(下から上への弧)
			if t >= 1.10 and t < 1.18:
				var k := 1.0 - (t - 1.10) / 0.08
				_swipe(ci, _pt("p0d", "tsuba") + Vector2(-60, 10), _pt("p3", "tip"), H + Vector2(-150, -60), k, 7.0)
			# 振り下ろし(上段から前下へ)
			if t >= 1.43 and t < 1.50:
				var k := 1.0 - (t - 1.43) / 0.07
				_swipe(ci, _pt("p3c", "tip"), _pt("p4i", "tip"), H + Vector2(-210, -120), k, 9.0)
			# 納刀へ(刀を鯉口へ運ぶ一振り)
			if t >= 4.80 and t < 4.87:
				var k := 1.0 - (t - 4.80) / 0.07
				_swipe(ci, _pt("p4", "tip"), _pt("p2n1", "mouth") + Vector2(40, 30), H + Vector2(-90, 10), k, 5.0)
		_:
			_wind_shock(ci, t - SUP_WIND, true)

## 瞬間移動の空気の弾け: 体のあった所から、短い線が四方へ走って消える。
func _burst_lines(ci: CanvasItem, c: Vector2, a: float, strength: float) -> void:
	if a < 0.0 or a > 0.16:
		return
	var q := a / 0.16
	for i in range(12):
		var ang := i * TAU / 12.0 + 0.2 * fposmod(i * 0.618, 1.0)
		var d := Vector2(cos(ang), sin(ang) * 0.75)
		var r0 := (20.0 + 70.0 * eo(q)) * strength
		var r1 := r0 + (18.0 + 14.0 * fposmod(i * 0.37, 1.0)) * (1.0 - q) * strength
		ci.draw_line((c + d * r0).round(), (c + d * r1).round(), Color(0.86, 0.90, 1.0, 0.8 * (1.0 - q)), 2.0 if i % 3 == 0 else 1.0)

func _fx_add(ci: CanvasItem, tk: String, t: float, H: Vector2) -> void:
	var fr := _fr()
	match tk:
		"single":
			# 構えた瞬間と鯉口を切る瞬間、単眼が光る
			_eye_glow(ci, 0.6 * env(t, 0.40, 0.04, 0.3) + 1.1 * env(t if t < 1.14 else 1.14, 0.94, 0.04, 0.4))
			if fr in ["p0k", "p0d"]:
				_glint(ci, Rig.point(body_state, "tsuba"), 1.0 - sg(t, 0.94, 1.10) * 0.6 if fr == "p0k" else 1.0, Color(1.0, 0.97, 0.9))
			_noto_glints(ci, t, 2.10, 2.62)
		"all":
			_eye_glow(ci, 0.5 * env(t, 0.75, 0.04, 0.3) + 1.1 * env(t if t < 1.42 else 1.42, 1.12, 0.05, 0.35))
			if fr == "p0k":
				_glint(ci, Rig.point(body_state, "tsuba"), 0.9, Color(1.0, 0.97, 0.9))
			_noto_glints(ci, t, 4.80, 5.26)
		_:
			if not _awakened:
				for lk in [[0.58, "knee"], [0.70, "hip"], [0.82, "shoulder"]]:
					var a: float = t - float(lk[0])
					if a >= 0.0 and a < 0.12:
						_glint(ci, _joint(lk[1]), 1.0 - a / 0.12)
				_draw_tuning(ci, t)

## 納刀: 覗いた刀身を光が鍔から鯉口へ滑り、最後に鍔が鳴る(大きな閃き)。
func _noto_glints(ci: CanvasItem, t: float, t0: float, click: float) -> void:
	var fr := _fr()
	if fr in ["p2n1", "p2n2", "p2n3"] and Rig.has_point(body_state, "mouth"):
		var a := Rig.point(body_state, "tsuba")
		var b := Rig.point(body_state, "mouth")
		var f := fposmod((t - t0) * 3.2, 1.0)
		var p := a.lerp(b, f)
		ci.draw_rect(Rect2(p.round() + Vector2(-2, -1), Vector2(4, 1)), Color(0.9, 0.95, 1.0, 0.9))
	var ca := t - click
	if ca >= 0.0 and ca < 0.2 and fr == "p2k":
		var tp := Rig.point(body_state, "tsuba")
		var k := 1.0 - ca / 0.2
		_glint(ci, tp, 1.2 * k, Color(1.0, 0.95, 0.8))
		for i in range(6):
			var ang := i * TAU / 6.0 + 0.4
			var d := Vector2(cos(ang), sin(ang))
			ci.draw_line((tp + d * (3.0 + 10.0 * (1.0 - k))).round(), (tp + d * (6.0 + 16.0 * (1.0 - k))).round(), Color(1.0, 0.9, 0.7, k), 1.0)

## 覚醒前「機構調律」の光(加算): 封剣機構(鍔)の脈動 → 間 → 再点灯で機構が弾け、力が関節へ走る → 単眼の再点灯。
## 自己強化は熱(赤橙の火の粉が昇る)、回復は修復(緑の走査線が足元から頭へ上り、関節が順に嵌まり直して火花が落ちる)。
func _draw_tuning(ci: CanvasItem, t: float) -> void:
	var R: float = Motion.SUPPORT_RELIGHT
	var heal := action_kind == "heal"
	var acc := _color.lerp(Color.WHITE, 0.15)
	var fr := _fr()
	var p5 := fr.begins_with("p5")
	var ts: Vector2 = Rig.point(body_state, "tsuba") if p5 else _joint("hip") + Vector2(-8, -18)
	if p5 and t < R:
		var base := 0.2 * sg(t, 0.95, 2.2)
		var pulse := 0.0
		if t >= 1.0 and t < 2.22:
			pulse = 1.0 - smoothstep(0.0, 0.2, fposmod(t - 1.0, 0.28))
		elif t >= 2.22:
			base = 0.5
		_core(ci, ts, base + 0.55 * pulse, acc)
	var rl := t - R
	if rl < 0.0:
		return
	# 再点灯の瞬間: 全身が一瞬だけ機構の色に灯る(2〜3コマ)
	if rl < 0.13 and fr != "":
		Rig.draw(ci, body_state, Color(acc.r, acc.g, acc.b, 0.6 * (1.0 - rl / 0.13)))
	if rl < 0.5:
		_core(ci, ts, 1.6 * (1.0 - rl / 0.5), acc)
		var reveal := eo(sg(rl, 0.0, 0.08))
		var fade := 1.0 - sg(rl, 0.14, 0.5)
		for jn in ["shoulder", "hip", "knee"]:
			var jp := _joint(jn)
			_line_px(ci, ts, ts.lerp(jp, reveal), acc * (0.9 * fade))
			if rl >= 0.08 and rl < 0.22:
				_glint(ci, jp, 1.0 - (rl - 0.08) / 0.14, acc.lerp(Color.WHITE, 0.5))
	# 単眼の再点灯(本番の赤い単眼を、いまのコマの眼の位置で)
	if p5:
		var e := Rig.point(body_state, "eye")
		var g := 1.0 - 0.5 * sg(t, R + 0.1, 2.65)
		ci.draw_rect(Rect2((e + Vector2(-1, -1)).round(), Vector2(3, 3)), Color(1.0, 0.1, 0.06) * g)
		ci.draw_rect(Rect2((e + Vector2(-5, 0)).round(), Vector2(10, 1)), Color(1.0, 0.25, 0.12) * (g * 0.5))
		if rl < 0.2:
			var L := 26.0 * (1.0 - rl / 0.2)
			ci.draw_rect(Rect2((e + Vector2(-L, -0.5)).round(), Vector2(roundf(L * 2.0), 1)), Color(1.0, 0.3, 0.15) * (1.0 - rl / 0.2))
	if heal:
		_draw_repair(ci, rl, acc)
	else:
		_draw_embers(ci, rl, acc)
	_eye_glow(ci, (0.6 if heal else 0.9) * env(t, 2.61, 0.04, 0.5 if heal else 0.9), Color(1.0, 0.16, 0.08))

func _core(ci: CanvasItem, p: Vector2, g: float, col: Color) -> void:
	if g <= 0.02:
		return
	var q := p.round()
	var k := minf(g, 1.0)
	ci.draw_circle(q, 3.0 + 7.0 * minf(g, 1.6), col * (0.25 * k))
	ci.draw_circle(q, 1.5 + 3.0 * minf(g, 1.6), col * (0.6 * k))
	ci.draw_rect(Rect2(q - Vector2(1, 1), Vector2(3, 3)), Color(1, 1, 1) * k)

func _line_px(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	if a.distance_to(b) < 1.0:
		return
	ci.draw_line(a.round(), b.round(), col * 0.35, 5.0)
	ci.draw_line(a.round(), b.round(), col, 2.0)

## 自己強化: 再点灯の熱で、外套の上から赤橙の火の粉が揺れながら昇る。
func _draw_embers(ci: CanvasItem, rl: float, acc: Color) -> void:
	if rl > 1.4:
		return
	var warm := acc.lerp(Color(1.0, 0.55, 0.2), 0.5)
	var foot: Vector2 = _home
	for i in range(26):
		var st := 0.03 * (i % 6) + 0.05 * float(i / 6)
		var a := rl - st
		if a < 0.0 or a > 1.0:
			continue
		var q := a / 1.0
		var h := 30.0 + 120.0 * fposmod(i * 0.618, 1.0)
		var x := -30.0 + 60.0 * fposmod(i * 0.377 + 0.2, 1.0)
		var p := foot + Vector2(x + 5.0 * sin(a * 9.0 + i), -h - 70.0 * eo(q) - 12.0 * q)
		var k := (1.0 - q) * (0.7 + 0.3 * sin(a * 30.0 + i * 2.0))
		var sz := Vector2(2, 3) if i % 3 == 0 else Vector2(1, 2)
		ci.draw_rect(Rect2(p.round(), sz), warm * k)
		if i % 3 == 0:
			ci.draw_rect(Rect2(p.round() + Vector2(-1, -1), sz + Vector2(2, 2)), warm * (k * 0.25))

## 回復: 緑の走査線が足元から頭へ上り、通過した関節が順に嵌まり直して、火花が落ちる。
func _draw_repair(ci: CanvasItem, rl: float, acc: Color) -> void:
	var foot: Vector2 = _home
	if rl < 0.42:
		var q := eio(clampf(rl / 0.36, 0.0, 1.0))
		var h := 4.0 + 170.0 * q
		var fade := 1.0 - sg(rl, 0.34, 0.42)
		var y := foot.y - h
		var half := 30.0 - 8.0 * q
		ci.draw_rect(Rect2(Vector2(foot.x - half, y).round(), Vector2(roundf(half * 2.0), 2)), acc * (0.95 * fade))
		ci.draw_rect(Rect2(Vector2(foot.x - half + 4.0, y + 2.0).round(), Vector2(roundf(half * 2.0 - 8.0), 4)), acc * (0.3 * fade))
		ci.draw_rect(Rect2(Vector2(foot.x - half + 8.0, y + 6.0).round(), Vector2(roundf(half * 2.0 - 16.0), 6)), acc * (0.12 * fade))
	for o in [["knee", 0.06], ["hip", 0.14], ["chest", 0.2], ["shoulder", 0.26]]:
		var a: float = rl - float(o[1])
		if a < 0.0 or a > 0.7:
			continue
		var jp := _joint(o[0])
		if a < 0.14:
			_glint(ci, jp, 1.0 - a / 0.14, acc.lerp(Color.WHITE, 0.55))
		for m in range(5):
			var v := Vector2(-40.0 + 80.0 * fposmod(m * 0.618 + float(o[1]) * 7.0, 1.0), -50.0 - 40.0 * fposmod(m * 0.37, 1.0))
			var p := jp + v * a + Vector2(0, 260.0 * a * a)
			ci.draw_rect(Rect2(p.round(), Vector2(1, 1)), acc.lerp(Color.WHITE, 0.4) * (1.0 - a / 0.7))
