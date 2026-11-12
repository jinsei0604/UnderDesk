class_name RBMHeroFxBatch
extends Node2D
## 三角形を1回の描画にまとめる層（火花・破片・棘・稲妻）。draw_circle を大量に呼ばない。

var _p := PackedVector2Array()
var _c := PackedColorArray()

func reset() -> void:
	_p.clear()
	_c.clear()

func commit() -> void:
	queue_redraw()

func _draw() -> void:
	var n := _p.size()
	if n == 0:
		return
	var idx := PackedInt32Array()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, _p, _c)

func tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color) -> void:
	_p.append(a); _p.append(b); _p.append(c)
	_c.append(ca); _c.append(cb); _c.append(cc)

func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	tri(a, b, c, ca, cb, cc)
	tri(a, c, d, ca, cc, cd)

## 先端が太く、尾が細く透ける線。
func streak(from: Vector2, to: Vector2, w: float, head: Color, tail: Color) -> void:
	var d := to - from
	if d.length_squared() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized() * w * 0.5
	var mid := to - d * 0.18
	tri(from, mid + n, mid - n, tail, head, head)
	tri(to, mid - n, mid + n, head, head, head)

func line(a: Vector2, b: Vector2, w: float, ca: Color, cb: Color) -> void:
	var d := b - a
	if d.length_squared() < 0.01:
		return
	var n := Vector2(-d.y, d.x).normalized() * w * 0.5
	quad(a + n, b + n, b - n, a - n, ca, cb, cb, ca)

## 根元が太く先が尖った棘。
func spike(o: Vector2, dir: Vector2, length: float, w: float, base: Color, tip: Color) -> void:
	var n := Vector2(-dir.y, dir.x) * w * 0.5
	tri(o + n, o - n, o + dir * length, base, base, tip)

## 不揃いな多角形の破片（明るい面と暗い面の2色）。
func shard(c: Vector2, radius: float, rot: float, seed_: int, lit: Color, dark: Color) -> void:
	var sides := 3 + (seed_ % 3)
	var prev := c + Vector2.from_angle(rot) * radius * (0.6 + RBMHeroFx.r(seed_, 91) * 0.6)
	var first := prev
	for i in range(1, sides + 1):
		var th := rot + TAU * float(i) / sides
		var p := first if i == sides else c + Vector2.from_angle(th) * radius * (0.6 + RBMHeroFx.r(seed_ + i, 91) * 0.6)
		var col := lit if i <= sides / 2 else dark
		tri(c, prev, p, col, col, col)
		prev = p

## ドットに揃えた四角の粒。
func dot_px(p: Vector2, size_: float, col: Color) -> void:
	var a := p.floor()
	var s := Vector2(size_, size_)
	quad(a, a + Vector2(s.x, 0), a + s, a + Vector2(0, s.y), col, col, col, col)
