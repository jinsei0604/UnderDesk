extends Node
## 朽ちた機械武者の登場（intro/rbm_intro_musha.gd）の「画面を覆う墨」と、飛び散る墨・斬撃の光を描く層（表示専用）。
## - 墨（shaders/rbm_intro_musha_ink.gdshader）は画面の座標で描く（戦場のカメラの寄りでは拡大しない）。揺れだけ戦場と合わせる。
## - 墨の滴・画面に付いた墨・斬撃の芯は墨の上、光（斬撃・眼・鍔の閃き）は加算で一番上に描く。
## - 墨と滴の時間（clock）はヒットストップ・無音の間で遅く・止まる。斬撃の光は実時間（real_clock）で進む
##   （同じ時計だと、止めている間に斬撃が出ない）。
## 戦闘の状態・乱数には触れない（滴の散らばりは固定の種の自前の乱数）。再生役が消えると層も消える（_exit_tree）。

const SHADER = preload("res://src/bossmaker/visuals/encounter/shaders/rbm_intro_musha_ink.gdshader")
const SCREEN := Vector2(1280, 720)
## 揺れても縁に隙間が出ないよう、墨は画面より少し外まで描く。
const MARGIN := 48.0

class Canvas extends Node2D:
	var fn: Callable
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)

var camera: RefCounted
var ink_layer: CanvasLayer
var top_layer: CanvasLayer
var ink_canvas: Canvas
var fx_canvas: Canvas
var glow_canvas: Canvas
var mat: ShaderMaterial
var rng := RandomNumberGenerator.new()
var drops: Array = []       # {p, v, r, life, age, stick, col, g}
var slashes: Array = []     # {a, b, t0, dur, hold, fade, core, glow, w}
var clock := 0.0            # 墨・滴の時間（遅く・止まる）
var real_clock := 0.0       # 斬撃の光の時間（実時間）
## 一番上の光の層に、振付が描き足すもの（眼の光・鍔の閃き）。
var extra_glow_fn: Callable

func setup(view: Control, cam: RefCounted) -> void:
	camera = cam
	rng.seed = 20261104
	ink_layer = CanvasLayer.new()
	ink_layer.layer = 38
	ink_layer.name = "IntroMushaInk"
	view.add_child(ink_layer)
	top_layer = CanvasLayer.new()
	top_layer.layer = 39
	top_layer.name = "IntroMushaInkTop"
	view.add_child(top_layer)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	ink_canvas = Canvas.new()
	ink_canvas.material = mat
	ink_canvas.fn = _draw_ink
	ink_layer.add_child(ink_canvas)
	fx_canvas = Canvas.new()
	fx_canvas.fn = _draw_fx
	top_layer.add_child(fx_canvas)
	glow_canvas = Canvas.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_canvas.material = add
	glow_canvas.fn = _draw_glow
	top_layer.add_child(glow_canvas)

func param(key: String, value: Variant) -> void:
	mat.set_shader_parameter(key, value)

## 墨を描くかどうか（晴れきった後は描かない。透明でも全画面のシェーダーは重い）。
func show_ink(on: bool) -> void:
	if ink_canvas.visible != on:
		ink_canvas.visible = on

func _exit_tree() -> void:
	for n in [ink_layer, top_layer]:
		if is_instance_valid(n):
			n.queue_free()

## real_dt: 実時間の経過。slow: 墨と滴の時間の進み（1=普通・0=止める）。
func advance(real_dt: float, slow: float = 1.0) -> void:
	var dt := real_dt * slow
	clock += dt
	real_clock += real_dt
	param("time", clock)
	var shake: Vector2 = camera.get("_offset") if camera != null else Vector2.ZERO
	ink_layer.offset = shake
	top_layer.offset = shake
	for d in drops:
		d.age += dt
		if not bool(d.stick):
			d.v += Vector2(0, float(d.g)) * dt
			d.p += Vector2(d.v) * dt
	drops = drops.filter(func(d): return d.age < d.life)
	slashes = slashes.filter(func(s): return real_clock < float(s.t0) + float(s.dur) + float(s.hold) + float(s.fade))
	for n in [ink_canvas, fx_canvas, glow_canvas]:
		n.queue_redraw()

## 斬撃（a から b へ dur 秒で走り、hold 秒そのまま光り、fade 秒で細くなって消える）。
func slash(a: Vector2, b: Vector2, dur: float, hold: float, fade: float, glow: Color, w: float = 3.0, core: Color = Color(1, 1, 0.96)) -> void:
	slashes.append({"a": a, "b": b, "t0": real_clock, "dur": dur, "hold": hold, "fade": fade, "core": core, "glow": glow, "w": w})

## 墨の滴を飛ばす。stick=true は画面に付いた墨（動かずに少し流れて消える）。
func drop(p: Vector2, v: Vector2, r: float, life: float, col: Color, g: float = 900.0, stick: bool = false) -> void:
	drops.append({"p": p, "v": v, "r": r, "life": life, "age": 0.0, "stick": stick, "col": col, "g": g})

# ---------------------------------------------------------------------------

func _draw_ink(ci: CanvasItem) -> void:
	var pts := PackedVector2Array([Vector2(-MARGIN, -MARGIN), Vector2(SCREEN.x + MARGIN, -MARGIN),
		Vector2(SCREEN.x + MARGIN, SCREEN.y + MARGIN), Vector2(-MARGIN, SCREEN.y + MARGIN)])
	var uvs := PackedVector2Array()
	for v in pts:
		uvs.append(v / SCREEN)
	ci.draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)

static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0

# 墨の滴は数百〜千を超えるので、1粒ずつ描くと描画の命令が千を超えて重い。三角形の配列に貯めて、1回の命令で描く。
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()

func _disc(at: Vector2, r: float, c: Color) -> void:
	if c.a <= 0.0:
		return
	r = maxf(1.0, roundf(r))
	at = _snap(at)
	var base := _pts.size()
	if r <= 1.5:
		for v in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_pts.append(at + v)
			_cols.append(c)
		_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		return
	var n := 8 if r < 5.0 else 12
	_pts.append(at)
	_cols.append(c)
	for i in range(n):
		_pts.append(at + Vector2.from_angle(TAU * i / n) * r)
		_cols.append(c)
	for i in range(n):
		_idx.append_array([base, base + 1 + i, base + 1 + (i + 1) % n])

func _draw_fx(ci: CanvasItem) -> void:
	_pts.clear()
	_cols.clear()
	_idx.clear()
	for d in drops:
		var k: float = float(d.age) / float(d.life)
		var c: Color = d.col
		var a := c.a * (1.0 - smoothstep(0.6, 1.0, k))
		var r: float = float(d.r)
		if bool(d.stick):
			# 画面に付いた墨: 少し流れて薄くなる
			var flow := Vector2(0, 18.0 * k * r / 8.0)
			_disc(Vector2(d.p) + flow * 0.5, r, Color(c, a))
			_disc(Vector2(d.p) + flow, r * 0.55, Color(c, a))
		else:
			var v: Vector2 = d.v
			# 速い滴は進む向きに伸びる（2つの円で）。大きい滴には濡れた照りの点
			var tail := -v.normalized() * minf(r * 2.5, v.length() * 0.012)
			_disc(d.p, r, Color(c, a))
			_disc(Vector2(d.p) + tail, r * 0.7, Color(c, a))
			if r >= 3.0:
				_disc(Vector2(d.p) - Vector2(r * 0.35, r * 0.35), maxf(1.0, r * 0.25), Color(0.32, 0.32, 0.38, a * 0.8))
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _idx, _pts, _cols)
	for s in slashes:
		_draw_slash(ci, s, false)

func _draw_glow(ci: CanvasItem) -> void:
	for s in slashes:
		_draw_slash(ci, s, true)
	if extra_glow_fn.is_valid():
		extra_glow_fn.call(ci)

func _slash_state(s: Dictionary) -> Dictionary:
	var t := real_clock - float(s.t0)
	var k := clampf(t / maxf(0.001, float(s.dur)), 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 2.0)
	var after := t - float(s.dur) - float(s.hold)
	var f := 1.0 - clampf(after / maxf(0.001, float(s.fade)), 0.0, 1.0) if after > 0.0 else 1.0
	return {"k": k, "f": f, "head": t <= float(s.dur)}

## 三日月形（両端が細く、中ほどが太い）の帯。先端側を少し太くできる（head_bias）。
func _crescent(ci: CanvasItem, a: Vector2, b: Vector2, w: float, c: Color, head_bias: float) -> void:
	if a.distance_to(b) < 2.0 or w <= 0.0 or c.a <= 0.0:
		return
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 28
	for i in range(steps + 1):
		var u := float(i) / steps
		var prof := pow(sin(PI * clampf(lerpf(u, pow(u, 0.6), head_bias), 0.0, 1.0)), 0.8)
		var at := a.lerp(b, u)
		left.append(at + n * w * 0.5 * prof)
		right.append(at - n * w * 0.5 * prof)
	right.reverse()
	left.append_array(right)
	# 両端で重なった点を除く（重なると多角形が作れない）
	var pts := PackedVector2Array()
	for v in left:
		if pts.is_empty() or pts[pts.size() - 1] != v:
			pts.append(v)
	if pts.size() >= 2 and pts[0] == pts[pts.size() - 1]:
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_colored_polygon(pts, c)

func _draw_slash(ci: CanvasItem, s: Dictionary, glow: bool) -> void:
	var st := _slash_state(s)
	var a: Vector2 = s.a
	var tip: Vector2 = a.lerp(s.b, float(st.k))
	var f: float = st.f
	var w: float = float(s.w)
	var moving: bool = st.head
	var bias := 0.8 if moving else 0.0
	var d := (Vector2(s.b) - a).normalized()
	if glow:
		var g: Color = s.glow
		_crescent(ci, a, tip, w * 7.0 * f, Color(g, 0.14 * f), bias)
		_crescent(ci, a, tip, w * 3.0 * f, Color(g, 0.40 * f), bias)
		if moving:
			# 刃の先: 進む向きに細長い光
			_crescent(ci, tip - d * 150.0, tip + d * 4.0, w * 2.2, Color(g, 0.45), 0.9)
	else:
		_crescent(ci, a, tip, maxf(2.0, w * 2.4 * f), Color(s.core, minf(1.0, f * 1.2)), bias)
