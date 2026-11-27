extends Node2D
## Quiet awakened-dragon atmosphere only. The dragon itself keeps its static idle.
var age := 0.0
var _stage: Control
var _foot := Vector2.ZERO
var _tail := Vector2.ZERO
var _height := 180.0
var _pixel := 3.0
## 攻撃中に体が画面から消えている間は雷を出さない
var _body_hidden := false

## 2026-11-26 ユーザー「覚醒後のオーラに赤い雷を常時まとわせて」（承認済み。速さの直しで入れ替わりを 0.34〜0.5 秒に）:
## 体の周りを紅い稲妻がいつも這い回り（数本が入れ替わりながらパチパチと形を変える）、時々地面へ落ちて火花が跳ねる。
## ドットの格子（_pixel）に合わせて描き、外の暗い紅・中の紅・芯の明るい紅の3段（いちばん強いコマだけ白に近い芯）。
const BOLT_GLOW := Color(0.72, 0.03, 0.1, 0.55)
const BOLT_MID := Color(0.95, 0.1, 0.18, 1.0)
const BOLT_CORE := Color(1.0, 0.45, 0.5, 1.0)
const BOLT_HOT := Color(1.0, 0.84, 0.86, 1.0)
const ARC_COUNT := 4
const GROUND_EVERY := 2.6

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 6

func configure(stage: Control) -> void:
	_stage = stage
	refresh()

func refresh() -> void:
	_update_anchors()
	queue_redraw()

func _process(delta: float) -> void:
	age += delta
	_update_anchors()
	if visible:
		queue_redraw()

func _update_anchors() -> void:
	visible = false
	if not is_instance_valid(_stage) or str(_stage._asset_ids.get("boss", "")) != "dragon_awakened":
		return
	var boss: Control = _stage._visuals.get("boss")
	if not is_instance_valid(boss):
		return
	visible = true
	_body_hidden = false
	_height = _stage.Assets.display_height("dragon")
	_foot = boss.position + boss.foot_position()
	var tail_pixel := Vector2(513, 341)
	var pose_records: Array = boss._pose_rects
	var pose_index := int(boss.pose)
	if pose_index >= 0 and pose_index < pose_records.size():
		var landmarks: Dictionary = pose_records[pose_index].get("landmarks", {})
		var tail_values: Array = landmarks.get("tail", [513, 341])
		tail_pixel = Vector2(float(tail_values[0]), float(tail_values[1]))
	_tail = boss.position + tail_pixel * float(boss._pixel_scale)
	# Dedicated dragon actions draw an animated body while the normal actor is hidden.
	var presentation: Node2D = _stage._skill_presentation
	if not boss.visible and is_instance_valid(presentation):
		var body: Node2D = presentation.get("_body")
		if is_instance_valid(body):
			_body_hidden = not body.visible
			if body.has_method("foot_point"):
				_foot = Vector2(body.call("foot_point")) + presentation.position
			if body.has_method("tail_point"):
				_tail = Vector2(body.call("tail_point")) + presentation.position

func _draw() -> void:
	if not visible:
		return
	# Five faint drifting smoke fragments and seven embers remain deliberately sparse.
	for i in range(5):
		var q := fposmod(age * 0.22 + float(i) * 0.219, 1.0)
		var side := sin(float(i) * 7.13)
		var point := _foot + Vector2(side * _height * 0.69 + sin(age + float(i)) * 5.0, -q * _height * 1.08)
		var radius := 6.0 + q * 7.0
		var alpha := sin(q * PI) * 0.28
		_cloud(point, radius, Color(0.022, 0.019, 0.031, alpha))
	for i in range(7):
		var q := fposmod(age * 0.27 + float(i) * 0.157, 1.0)
		var point := _foot + Vector2(sin(float(i) * 5.9) * _height * 0.64 + sin(age * 1.8 + float(i)) * 7.0, -q * _height * 1.05)
		draw_rect(Rect2(point.snapped(Vector2.ONE * _pixel), Vector2(_pixel, _pixel)), Color(0.91, 0.045, 0.075, sin(q * PI) * 0.60))
	# Continuous black flame at the original tail tip, with crisp deep-red edging.
	for i in range(3):
		var origin := _tail + Vector2(float(i - 1) * 5.0, 5.0)
		var h := 23.0 + sin(age * 7.0 + float(i) * 2.0) * 5.0
		_flame(origin, 8.0, h, Color(0.26, 0.013, 0.036, 0.88))
		_flame(origin, 5.0, h * 0.86, Color(0.016, 0.015, 0.021, 0.97))
	if not _body_hidden:
		_red_lightning()

func _rnd(a: int, b: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453, 1.0)

func _red_lightning() -> void:
	var center := _foot + Vector2(-_height * 0.04, -_height * 0.52)
	# 体の周りを這う稲妻（数本が別々の周期で入れ替わる）
	for i in range(ARC_COUNT):
		var life := 0.34 + 0.08 * float(i % 3)
		var phase := float(i) * 0.47
		var gen := int(floor((age + phase) / life))
		var local := fposmod(age + phase, life) / life
		if _rnd(gen, i * 11 + 1) < 0.25:
			continue
		var a0 := _rnd(gen, i * 11 + 2) * TAU
		var span := (0.6 + 0.7 * _rnd(gen, i * 11 + 3)) * (1.0 if _rnd(gen, i * 11 + 4) < 0.5 else -1.0)
		var rx := _height * (0.56 + 0.2 * _rnd(gen, i * 11 + 5))
		var ry := _height * (0.42 + 0.14 * _rnd(gen, i * 11 + 6))
		var p0 := center + Vector2(cos(a0) * rx, sin(a0) * ry)
		var p1 := center + Vector2(cos(a0 + span) * rx, sin(a0 + span) * ry)
		var power := 1.0 if local < 0.25 else 1.0 - (local - 0.25) / 0.75 * 0.9
		# 1本の命の中で2回形を変える（パチパチと這う）
		_bolt(p0, p1, gen * 31 + i * 5 + int(local * 2.0) * 7, power, 8, 0.3, local < 0.08, true)
	# 体から外へ弾ける短い放電（オーラの外側の縁）
	for i in range(3):
		var life := 0.26 + 0.06 * float(i)
		var gen := int(floor((age + float(i) * 0.37) / life))
		var local := fposmod(age + float(i) * 0.37, life) / life
		if _rnd(gen, i * 7 + 200) < 0.3:
			continue
		var th := _rnd(gen, i * 7 + 201) * TAU
		var from := center + Vector2(cos(th) * _height * 0.5, sin(th) * _height * 0.38)
		var to := from + Vector2.from_angle(th + (_rnd(gen, i * 7 + 202) - 0.5) * 0.8) * _height * (0.16 + 0.16 * _rnd(gen, i * 7 + 203))
		_bolt(from, to, gen * 17 + i, 1.0 - local * 0.7, 4, 0.35, local < 0.1, false)
	# 時々、地面へ落ちる雷と火花
	var g := int(floor(age / GROUND_EVERY))
	var ga := age - float(g) * GROUND_EVERY - 0.4 * _rnd(g, 91)
	if ga >= 0.0 and ga < 0.36:
		var from := center + Vector2((_rnd(g, 92) - 0.5) * _height * 0.6, -_height * 0.1)
		var to := Vector2(_foot.x + (_rnd(g, 93) - 0.5) * _height * 1.4, _foot.y + 2.0)
		if ga < 0.16:
			var power := 1.0 if ga < 0.05 else 1.0 - (ga - 0.05) / 0.11 * 0.6
			_bolt(from, to, g * 53 + int(ga * 10.0), power, 9, 0.2, ga < 0.04, true)
		for k in range(8):
			var th := -PI * 0.5 + (_rnd(g * 9 + k, 94) - 0.5) * 2.4
			var sp := 120.0 + 140.0 * _rnd(g * 9 + k, 95)
			var p := to + Vector2.from_angle(th) * sp * ga + Vector2(0, 520.0 * ga * ga)
			var c := BOLT_CORE if k % 2 == 0 else BOLT_MID
			c.a = 1.0 - ga / 0.36
			draw_rect(Rect2(p.snapped(Vector2.ONE * _pixel), Vector2(_pixel, _pixel)), c)

## 1本の稲妻を、ドットの格子のマスに置いて描く（重なりで濃くならないよう、マスは1回だけ塗る）
func _bolt(a: Vector2, b: Vector2, seed_: int, power: float, segs: int, amp: float, hot: bool, branch: bool) -> void:
	if power <= 0.0:
		return
	var d := b - a
	var length := d.length()
	if length < _pixel * 2.0:
		return
	var nv := Vector2(-d.y, d.x) / length
	var pts: Array[Vector2] = [a]
	for k in range(1, segs):
		var u := float(k) / float(segs)
		pts.append(a + d * u + nv * (_rnd(seed_, k) - 0.5) * 2.0 * amp * length * sin(u * PI))
	pts.append(b)
	var core := {}
	var twig := {}
	for k in range(pts.size() - 1):
		_cells(pts[k], pts[k + 1], core)
		if branch and k % 3 == 1:
			var th := (pts[k + 1] - pts[k]).angle() + (_rnd(seed_, k + 40) - 0.5) * 2.0
			var e: Vector2 = pts[k] + Vector2.from_angle(th) * length * (0.15 + 0.15 * _rnd(seed_, k + 50))
			var m: Vector2 = (pts[k] + e) * 0.5 + Vector2.from_angle(th + PI * 0.5) * (_rnd(seed_, k + 60) - 0.5) * length * 0.08
			_cells(pts[k], m, twig)
			_cells(m, e, twig)
	var glow := {}
	for c in core:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				glow[c + Vector2i(dx, dy)] = true
	var cg := BOLT_GLOW
	cg.a *= power
	for c in glow:
		if not core.has(c) and not twig.has(c):
			draw_rect(Rect2(Vector2(c) * _pixel, Vector2(_pixel, _pixel)), cg)
	var cm := BOLT_MID
	cm.a *= power
	for c in twig:
		if not core.has(c):
			draw_rect(Rect2(Vector2(c) * _pixel, Vector2(_pixel, _pixel)), cm)
	var cc := BOLT_HOT if hot else BOLT_CORE
	cc.a *= power
	for c in core:
		draw_rect(Rect2(Vector2(c) * _pixel, Vector2(_pixel, _pixel)), cc)

func _cells(a: Vector2, b: Vector2, into: Dictionary) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / _pixel)))
	for s in range(n + 1):
		var p := a.lerp(b, float(s) / float(n))
		into[Vector2i(int(floor(p.x / _pixel)), int(floor(p.y / _pixel)))] = true

func _cloud(center: Vector2, radius: float, color: Color) -> void:
	var point := center.snapped(Vector2.ONE * _pixel)
	var size := ceilf(radius / _pixel) * _pixel
	draw_rect(Rect2(point - Vector2(size, size * 0.5), Vector2(size * 2.0, size)), color)
	draw_rect(Rect2(point - Vector2(size * 0.5, size), Vector2(size, size * 2.0)), color)

func _flame(origin: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		origin + Vector2(-width, 0), origin + Vector2(-width, -height * 0.35),
		origin + Vector2(-width * 0.3, -height * 0.27), origin + Vector2(-width * 0.6, -height * 0.66),
		origin + Vector2(0, -height), origin + Vector2(width * 0.55, -height * 0.64),
		origin + Vector2(width * 0.22, -height * 0.41), origin + Vector2(width * 0.85, -height * 0.51),
		origin + Vector2(width, 0),
	])
	for i in range(points.size()):
		points[i] = points[i].snapped(Vector2.ONE * _pixel)
	if not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, color)
