extends Node
## 異形紳士の登場（intro/rbm_intro_gentleman.gd）の「画面を覆う黒いガラス」を描く層（表示専用、2026-11-23）。
## - 黒いガラス・弾痕とひび・砕けた破片は画面の座標で描く（戦場のカメラの寄りでは拡大しない）。揺れだけ戦場と合わせる。
## - 闇の中で銃口の光に一瞬だけ照らされる紳士（振付の figure_fn）は、ガラスの上に描く。
## - 光（銃口の閃光・弾の筋・ひびの煌めき・赤い目・ガラスの粉）は加算で一番上に描く。
## - ひび・破片の形は固定の種の自前の乱数で作る（戦闘の状態・乱数には触れない）。再生役が消えると層も消える（_exit_tree）。

const SCREEN := Vector2(1280, 720)
## 揺れても縁に隙間が出ないよう、ガラスは画面より少し外まで描く。
const MARGIN := 48.0
const GLASS := Color(0.012, 0.014, 0.024)
const CRACK := Color(0.66, 0.72, 0.82)
const CRACK_HI := Color(0.96, 0.98, 1.0)
const FLASH := Color(1.0, 0.72, 0.38)

class Canvas extends Node2D:
	var fn: Callable
	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)

var camera: RefCounted
var glass_layer: CanvasLayer
var top_layer: CanvasLayer
var glass_canvas: Canvas
var glow_canvas: Canvas
var rng := RandomNumberGenerator.new()
var clock := 0.0
## 砕ける前の黒いガラスの濃さ（1＝真っ暗）。
var cover := 1.0
## ガラスがひびに受ける光（銃口の閃光で一瞬明るくなる）。
var lit := 0.0
var cracks: Array = []    # {c, segs(PackedVector2Array: 2点ずつ), delay(PackedFloat32Array: 線ごと), hi(PackedByteArray), t0, r, dust(PackedVector2Array)}
var shards: Array = []    # {pts(重心からの3点), c, v, rot, w, s, grow, life, age, delay, shade}
var flashes: Array = []   # {p, d, t0, k}
var tracers: Array = []   # {a, b, t0}
var sparks: Array = []    # {p, t0, life, s}
var glitter: Array = []   # {p, v, life, age, r}
var white := 0.0          # 画面全体の白い閃き（加算）
var shattered := false
## ガラスの上に描く、照らされた紳士（振付が描く）。
var figure_fn: Callable
## 一番上の光の層に振付が描き足すもの（赤い目・撃鉄の閃き・銃口の煙）。
var extra_glow_fn: Callable

func setup(view: Control, cam: RefCounted) -> void:
	camera = cam
	rng.seed = 20261123
	glass_layer = CanvasLayer.new()
	glass_layer.layer = 38
	glass_layer.name = "IntroGentlemanGlass"
	view.add_child(glass_layer)
	top_layer = CanvasLayer.new()
	top_layer.layer = 39
	top_layer.name = "IntroGentlemanGlassTop"
	view.add_child(top_layer)
	glass_canvas = Canvas.new()
	glass_canvas.fn = _draw_glass
	glass_layer.add_child(glass_canvas)
	glow_canvas = Canvas.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_canvas.material = add
	glow_canvas.fn = _draw_glow
	top_layer.add_child(glow_canvas)

func _exit_tree() -> void:
	for n in [glass_layer, top_layer]:
		if is_instance_valid(n):
			n.queue_free()

func advance(dt: float) -> void:
	clock += dt
	var shake: Vector2 = camera.get("_offset") if camera != null else Vector2.ZERO
	glass_layer.offset = shake
	top_layer.offset = shake
	for s in shards:
		s.age += dt
		if s.age < s.delay:
			continue
		var k := dt
		s.v += Vector2(0, 1500.0) * k
		s.c += Vector2(s.v) * k
		s.rot += float(s.w) * k
		s.s += float(s.grow) * k
	shards = shards.filter(func(s): return s.age < s.delay + s.life)
	for g in glitter:
		g.age += dt
		g.v += Vector2(0, 520.0) * dt
		g.v *= 0.985
		g.p += Vector2(g.v) * dt
	glitter = glitter.filter(func(g): return g.age < g.life)
	flashes = flashes.filter(func(f): return clock < float(f.t0) + 0.16)
	tracers = tracers.filter(func(t): return clock < float(t.t0) + 0.12)
	sparks = sparks.filter(func(s): return clock < float(s.t0) + float(s.life))
	for n in [glass_canvas, glow_canvas]:
		n.queue_redraw()

# --- 出来事 -------------------------------------------------------------------

## 銃口の閃光（p: 画面の座標、d: 銃身の向き）。
func muzzle_flash(p: Vector2, d: Vector2) -> void:
	flashes.append({"p": p, "d": d.normalized(), "t0": clock})

## 弾の筋（銃口から、画面に当たる所まで）。
func tracer(a: Vector2, b: Vector2) -> void:
	tracers.append({"a": a, "b": b, "t0": clock})

## 弾痕とひび（c を中心に半径 radius まで。grow 秒で外へ走る）。放射のひびが主で、同心のひびは弾痕の近くに途切れ途切れに。
## 弾痕に近いひびは太く明るく（hi=1）、外のひびは細く淡い。
func crack(c: Vector2, radius: float, rays: int, grow: float) -> void:
	var segs := PackedVector2Array()
	var delay := PackedFloat32Array()
	var hi := PackedByteArray()
	var ends: Array = []
	var a0 := rng.randf() * TAU
	for i in range(rays):
		var a := a0 + TAU * i / rays + rng.randf_range(-0.3, 0.3) * TAU / rays
		var length := radius * (rng.randf_range(0.85, 1.15) if rng.randf() < 0.35 else rng.randf_range(0.28, 0.75))
		var pts: Array[Vector2] = [c + Vector2.from_angle(a) * rng.randf_range(5.0, 9.0)]
		var dist := 0.0
		var dir := a
		while dist < length:
			var step := rng.randf_range(8.0, 18.0) * (1.0 + 1.4 * dist / radius)
			dir = lerp_angle(dir + rng.randf_range(-0.22, 0.22), a, 0.22)
			var q: Vector2 = pts.back() + Vector2.from_angle(dir) * step
			_seg(segs, delay, hi, pts.back(), q, dist / radius * grow, dist < radius * 0.3)
			pts.append(q)
			dist += step
			if dist > radius * 0.1 and rng.randf() < 0.1:
				_branch(segs, delay, hi, q, dir + rng.randf_range(0.3, 0.7) * (1.0 if rng.randf() < 0.5 else -1.0), length * rng.randf_range(0.1, 0.25), dist / radius * grow, radius, grow)
		ends.append(pts)
	# 同心のひび（弾痕の近くだけ。隣り合う放射のひびの間を、ところどころ外へふくらんだ線でつなぐ）
	for ring in [[0.05, 0.75], [0.12, 0.5], [0.22, 0.28]]:
		var rr: float = radius * float(ring[0])
		for i in range(rays):
			if rng.randf() > float(ring[1]):
				continue
			var p1: Variant = _point_at(ends[i], c, rr * rng.randf_range(0.8, 1.25))
			var p2: Variant = _point_at(ends[(i + 1) % rays], c, rr * rng.randf_range(0.8, 1.25))
			if p1 == null or p2 == null:
				continue
			var mid: Vector2 = (Vector2(p1) + Vector2(p2)) * 0.5
			mid += (mid - c).normalized() * rng.randf_range(-2.0, 6.0)
			_seg(segs, delay, hi, p1, mid, float(ring[0]) * grow + 0.01, true)
			_seg(segs, delay, hi, mid, p2, float(ring[0]) * grow + 0.01, true)
	# 弾痕のまわりの砕けた粉
	var dust := PackedVector2Array()
	for i in range(int(radius * 0.06) + 22):
		dust.append(c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 8.0 + minf(radius, 300.0) * 0.05))
	cracks.append({"c": c, "segs": segs, "delay": delay, "hi": hi, "t0": clock, "r": radius, "dust": dust})
	# ひびが走る間、ひびの上で光が瞬く
	for i in range(mini(16, rays + 6)):
		var j := rng.randi_range(0, delay.size() - 1)
		sparks.append({"p": segs[j * 2], "t0": clock + delay[j], "life": rng.randf_range(0.18, 0.4), "s": rng.randf_range(0.6, 1.2)})

func _seg(segs: PackedVector2Array, delay: PackedFloat32Array, hi: PackedByteArray, a: Vector2, b: Vector2, at: float, bright: bool) -> void:
	segs.append(a.round())
	segs.append(b.round())
	delay.append(at)
	hi.append(1 if bright else 0)

func _branch(segs: PackedVector2Array, delay: PackedFloat32Array, hi: PackedByteArray, from: Vector2, dir: float, length: float, at: float, radius: float, grow: float) -> void:
	var p := from
	var dist := 0.0
	while dist < length:
		var step := rng.randf_range(7.0, 16.0)
		dir += rng.randf_range(-0.3, 0.3)
		var q := p + Vector2.from_angle(dir) * step
		_seg(segs, delay, hi, p, q, at + dist / radius * grow, false)
		p = q
		dist += step

static func _point_at(pts: Array, c: Vector2, r: float) -> Variant:
	for q in pts:
		if Vector2(q).distance_to(c) >= r:
			return q
	return null

## ガラスが砕ける（c から外へ、wave 秒かけて割れが広がる）。ひびの点と画面の縁で三角形に割り、破片を飛ばす。
func shatter(c: Vector2, wave: float) -> void:
	shattered = true
	# 割れ目の点: 中心のまわりの輪（外ほど大きな破片）と画面の縁。細い三角にならないよう、輪ごとに角度を散らす
	var pts := PackedVector2Array([c])
	var radii := [24.0, 58.0, 105.0, 170.0, 250.0, 345.0, 455.0, 585.0, 735.0, 905.0]
	var box := Rect2(-MARGIN, -MARGIN, SCREEN.x + MARGIN * 2.0, SCREEN.y + MARGIN * 2.0)
	for k in range(radii.size()):
		var n := 6 + k * 3
		var off := rng.randf() * TAU
		for j in range(n):
			var ang := off + TAU * (j + rng.randf_range(-0.3, 0.3)) / n
			var q := c + Vector2.from_angle(ang) * float(radii[k]) * rng.randf_range(0.88, 1.12)
			if box.grow(-6.0).has_point(q):
				pts.append(q)
	for i in range(9):
		var x := box.position.x + box.size.x * i / 8.0
		pts.append(Vector2(x, box.position.y))
		pts.append(Vector2(x, box.end.y))
	for i in range(1, 6):
		var y := box.position.y + box.size.y * i / 6.0
		pts.append(Vector2(box.position.x, y))
		pts.append(Vector2(box.end.x, y))
	var tri := Geometry2D.triangulate_delaunay(pts)
	var reach := c.distance_to(Vector2.ZERO) + 200.0
	for i in range(0, tri.size(), 3):
		var a := pts[tri[i]]
		var b := pts[tri[i + 1]]
		var d := pts[tri[i + 2]]
		var cen := (a + b + d) / 3.0
		var away := cen - c
		var dist := away.length()
		away = away / dist if dist > 1.0 else Vector2.UP
		var speed := rng.randf_range(300.0, 620.0) * (0.6 + 300.0 / (dist + 140.0))
		shards.append({"pts": PackedVector2Array([a - cen, b - cen, d - cen]), "c": cen,
			"v": away * speed + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-320.0, -80.0)),
			"rot": 0.0, "w": rng.randf_range(-6.0, 6.0), "s": 1.0, "grow": rng.randf_range(0.9, 2.4),
			"life": rng.randf_range(0.42, 0.8), "age": 0.0, "delay": wave * dist / reach, "shade": rng.randf()})
	cracks.clear()
	cover = 0.0
	# 画面の前を舞うガラスの粉
	for i in range(150):
		var at := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 520.0)
		var v := (at - c).normalized() * rng.randf_range(80.0, 520.0) + Vector2(0, rng.randf_range(-260.0, 0.0))
		glitter.append({"p": at, "v": v, "life": rng.randf_range(0.6, 1.6), "age": 0.0, "r": 1.0 if rng.randf() < 0.75 else 2.0})

# --- 描画 -------------------------------------------------------------------

var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()

func _batch_begin() -> void:
	_pts.clear()
	_cols.clear()
	_idx.clear()

func _batch_end(ci: CanvasItem) -> void:
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), _idx, _pts, _cols)

func _quad(at: Vector2, r: float, c: Color) -> void:
	if c.a <= 0.0:
		return
	at = at.round()
	var base := _pts.size()
	for v in [Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)]:
		_pts.append(at + v)
		_cols.append(c)
	_idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

func _tri(a: Vector2, b: Vector2, d: Vector2, ca: Color, cb: Color, cd: Color) -> void:
	var base := _pts.size()
	_pts.append_array([a, b, d])
	_cols.append_array([ca, cb, cd])
	_idx.append_array([base, base + 1, base + 2])

func _draw_glass(ci: CanvasItem) -> void:
	if cover > 0.0:
		ci.draw_rect(Rect2(-MARGIN, -MARGIN, SCREEN.x + MARGIN * 2.0, SCREEN.y + MARGIN * 2.0), Color(GLASS, cover))
	if figure_fn.is_valid():
		figure_fn.call(ci)
	_draw_cracks(ci)
	_draw_shards(ci)

func _draw_cracks(ci: CanvasItem) -> void:
	if cracks.is_empty():
		return
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	var shine := PackedVector2Array()
	_batch_begin()
	for cr in cracks:
		var age := clock - float(cr.t0)
		var segs: PackedVector2Array = cr.segs
		var delay: PackedFloat32Array = cr.delay
		var hi: PackedByteArray = cr.hi
		for i in range(delay.size()):
			if age < delay[i]:
				continue
			if hi[i] == 1:
				inner.append_array([segs[i * 2], segs[i * 2 + 1]])
				shine.append_array([segs[i * 2] + Vector2(-1, -1), segs[i * 2 + 1] + Vector2(-1, -1)])
			else:
				outer.append_array([segs[i * 2], segs[i * 2 + 1]])
		# 弾痕: 白く砕けた縁・粉・黒い穴
		var c: Vector2 = cr.c
		var hole := 4.0 + minf(float(cr.r), 400.0) * 0.008
		for v in cr.dust:
			_quad(v, 1.0, Color(CRACK_HI, 0.5))
		_ngon(c, hole + 4.0, Color(CRACK, 0.45))
		_ngon(c, hole + 1.5, Color(CRACK_HI, 0.75))
		_ngon(c, hole, Color(0.0, 0.0, 0.0, 1.0))
	_batch_end(ci)
	var k := 0.8 + 0.2 * lit
	var boost := 0.85 + 0.45 * lit
	if not outer.is_empty():
		ci.draw_multiline(outer, Color(CRACK * boost, 0.55 * k), 1.0)
	if not inner.is_empty():
		ci.draw_multiline(inner, Color(CRACK * boost, 0.9 * k), 2.0)
	if not shine.is_empty():
		ci.draw_multiline(shine, Color(CRACK_HI, 0.75 * k), 1.0)

## 少しいびつな多角形（弾痕の穴・縁）。
func _ngon(at: Vector2, r: float, c: Color) -> void:
	var n := 9
	var base := _pts.size()
	_pts.append(at)
	_cols.append(c)
	for i in range(n):
		var wob := 0.8 + 0.4 * absf(sin(at.x * 0.37 + at.y * 0.11 + i * 2.3))
		_pts.append((at + Vector2.from_angle(TAU * i / n) * r * wob).round())
		_cols.append(c)
	for i in range(n):
		_idx.append_array([base, base + 1 + i, base + 1 + (i + 1) % n])

## 破片: 黒いガラスの面（一つの角だけ照り返しで明るい）。まだ落ちていない破片の縁は、画面じゅうに走ったひびとして描く。
## 落ち始めた破片は、上を向いた縁だけが光る。
func _draw_shards(ci: CanvasItem) -> void:
	if shards.is_empty():
		return
	_batch_begin()
	var resting := PackedVector2Array()
	var dim := PackedVector2Array()
	var lit_edges := PackedVector2Array()
	for s in shards:
		var moving := float(s.age) >= float(s.delay)
		var u := clampf((float(s.age) - float(s.delay)) / float(s.life), 0.0, 1.0)
		var a := 1.0 - smoothstep(0.6, 1.0, u)
		if a <= 0.0:
			continue
		var x := Transform2D(float(s.rot), Vector2(float(s.s), float(s.s)), 0.0, Vector2(s.c))
		var p: PackedVector2Array = s.pts
		var q := [x * p[0], x * p[1], x * p[2]]
		var sh: float = float(s.shade)
		if not moving:
			_tri(q[0], q[1], q[2], Color(GLASS, 1.0), Color(GLASS, 1.0), Color(GLASS, 1.0))
			resting.append_array([q[0], q[1], q[1], q[2], q[2], q[0]])
			continue
		var gl := Color(0.06 + 0.2 * sh, 0.07 + 0.21 * sh, 0.1 + 0.25 * sh, a)
		_tri(q[0], q[1], q[2], gl, Color(0.03, 0.035, 0.05, a), Color(0.045, 0.05, 0.07, a))
		if u < 0.4:
			dim.append_array([q[0], q[1], q[1], q[2], q[2], q[0]])
		# 上を向いた縁（外向きの法線が上・左上）だけ光る
		var cen: Vector2 = (q[0] + q[1] + q[2]) / 3.0
		for e in range(3 if u < 0.55 else 0):
			var e0: Vector2 = q[e]
			var e1: Vector2 = q[(e + 1) % 3]
			var mid := (e0 + e1) * 0.5
			var nrm := (mid - cen).normalized()
			if nrm.dot(Vector2(-0.45, -0.89)) > 0.55:
				lit_edges.append_array([e0, e1])
	_batch_end(ci)
	if not resting.is_empty():
		ci.draw_multiline(resting, Color(CRACK, 0.7), 1.0)
	if not dim.is_empty():
		ci.draw_multiline(dim, Color(CRACK, 0.22), 1.0)
	if not lit_edges.is_empty():
		ci.draw_multiline(lit_edges, Color(CRACK_HI, 0.8), 1.0)

func _draw_glow(ci: CanvasItem) -> void:
	if white > 0.0:
		ci.draw_rect(Rect2(-MARGIN, -MARGIN, SCREEN.x + MARGIN * 2.0, SCREEN.y + MARGIN * 2.0), Color(1, 1, 1, white))
	_batch_begin()
	for f in flashes:
		_flash(f)
	for s in sparks:
		var u := (clock - float(s.t0)) / float(s.life)
		if u < 0.0:
			continue
		var k := sin(PI * clampf(u, 0.0, 1.0)) * float(s.s)
		_star(s.p, 3.0 + 9.0 * k, Color(CRACK_HI, 0.85 * k))
	for g in glitter:
		var u := float(g.age) / float(g.life)
		var tw := 0.5 + 0.5 * sin(float(g.age) * 40.0 + float(g.life) * 17.0)
		_quad(g.p, float(g.r), Color(CRACK_HI, (1.0 - u) * (0.35 + 0.65 * tw)))
	_batch_end(ci)
	for t in tracers:
		_draw_tracer(ci, t)
	if extra_glow_fn.is_valid():
		extra_glow_fn.call(ci)

## 銃口の閃光: 前へ長く、斜めに短い炎の筋と、明るい芯・広い光。
func _flash(f: Dictionary) -> void:
	var u := (clock - float(f.t0)) / 0.16
	var k := pow(1.0 - clampf(u, 0.0, 1.0), 1.6)
	if k <= 0.0:
		return
	var p: Vector2 = f.p
	var d: Vector2 = f.d
	# 広い光（照らされた空気）
	for i in range(5):
		var r := 34.0 + i * 34.0
		_disc(p + d * 18.0, r, Color(FLASH, 0.07 * k))
	# 炎の筋（前へ1本・斜め前へ2本・横へ2本）
	for spike in [[0.0, 70.0, 9.0], [0.55, 40.0, 6.0], [-0.55, 40.0, 6.0], [1.4, 22.0, 4.0], [-1.4, 22.0, 4.0]]:
		var dir := d.rotated(float(spike[0]))
		var reach := float(spike[1]) * (0.6 + 0.4 * k)
		var w := float(spike[2]) * k
		var side := Vector2(-dir.y, dir.x)
		_tri(p + side * w, p - side * w, p + dir * reach, Color(1, 0.95, 0.8, k), Color(1, 0.95, 0.8, k), Color(FLASH, 0.0))
	_disc(p, 9.0 * k + 3.0, Color(1, 1, 0.92, k))
	_disc(p, 18.0 * k + 4.0, Color(1, 0.85, 0.55, 0.5 * k))

func _disc(at: Vector2, r: float, c: Color) -> void:
	if c.a <= 0.0 or r <= 0.0:
		return
	at = at.round()
	var n := 10 if r < 12.0 else 18
	var base := _pts.size()
	_pts.append(at)
	_cols.append(c)
	for i in range(n):
		_pts.append(at + Vector2.from_angle(TAU * i / n) * r)
		_cols.append(Color(c, 0.0))
	for i in range(n):
		_idx.append_array([base, base + 1 + i, base + 1 + (i + 1) % n])

## 小さな四方の光（ひび・破片の煌めき）。
func _star(at: Vector2, ln: float, c: Color) -> void:
	if c.a <= 0.0:
		return
	at = at.round()
	for d in [Vector2(1, 0), Vector2(0, 1)]:
		var side := Vector2(-d.y, d.x)
		_tri(at - d * ln, at + side * 1.2, at + d * ln, Color(c, 0.0), c, Color(c, 0.0))
		_tri(at - d * ln, at - side * 1.2, at + d * ln, Color(c, 0.0), c, Color(c, 0.0))
	_quad(at, 1.0, c)

## 弾の筋: 銃口から画面へ、ごく短い時間で伸びて消える。
func _draw_tracer(ci: CanvasItem, t: Dictionary) -> void:
	var age := clock - float(t.t0)
	var grow := clampf(age / 0.035, 0.0, 1.0)
	var fade := 1.0 - clampf((age - 0.035) / 0.08, 0.0, 1.0)
	if fade <= 0.0:
		return
	var a: Vector2 = t.a
	var b: Vector2 = a.lerp(t.b, grow)
	ci.draw_line(a.round(), b.round(), Color(1, 0.8, 0.45, 0.35 * fade), 7.0)
	ci.draw_line(a.round(), b.round(), Color(1, 0.97, 0.85, 0.9 * fade), 2.0)
