extends Node2D
## 朽ちた機械武者の前面VFX(斬撃・交差閃光・衝撃・墨散り・最終斬撃・強化回復の機構)。
## 承認済み試作のfront.gdの描画をそのまま移植したもの——数値・発火時刻は変更して
## いない。画像で描いた飛び道具は無く、頂点は2px単位に丸めアンチエイリアス無し。
## 表示専用: 対象位置(確定済みの実際の足元)と経過時間を受け取って描くだけ。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")

var kind := "single"
var age := 0.0
var color := Color.WHITE
## 対象の胴の中心(ステージ座標)。単体は1点、全体は対象の数だけ。
var hits: Array[Vector2] = []
## 全体の中心。
var center := Vector2.ZERO
var home := Vector2.ZERO
## 最終斬撃の画面閃光の矩形(実際の戦闘領域)。
var screen := Rect2()
## 覚醒後は眼が既に点灯(細い赤線)しているため、再点灯の赤い単眼は描かない。
var awakened := false

func advance(t: float) -> void:
	age = t
	queue_redraw()

func poly(points: Array, c: Color) -> void:
	var p := PackedVector2Array()
	for point in points:
		p.append(Vector2(point).snapped(Vector2(2, 2)))
	if not Geometry2D.triangulate_polygon(p).is_empty():
		draw_colored_polygon(p, c)

func slash(at: Vector2, angle: float, length: float, width: float, c: Color) -> void:
	var d := Vector2(cos(angle), sin(angle))
	var n := Vector2(-d.y, d.x)
	poly([at - d * length * .5, at + n * width, at + d * length * .5, at - n * width * .7], c)

func ring(p: Vector2, r: Vector2, c: Color, w: float) -> void:
	var points := PackedVector2Array()
	for i in range(65):
		var a := i * TAU / 64.0
		points.append((p + Vector2(cos(a) * r.x, sin(a) * r.y)).snapped(Vector2(2, 2)))
	draw_polyline(points, c, w, false)

func burst(p: Vector2, t: float, c: Color, power: float = 1.0) -> void:
	if t < 0.0 or t > .65:
		return
	var q := t / .65
	var col := c.lightened(.3)
	col.a = 1.0 - q
	ring(p, Vector2(22 + q * 90, 10 + q * 40) * power, col, 3)
	for j in range(12):
		var a := j * 2.399
		var at := p + Vector2(cos(a), sin(a)) * (16 + q * 100) * power
		slash(at, a, (10 + q * 28) * power, 1.5, col)

func cross(p: Vector2, t: float, c: Color, scale_factor: float = 1.0) -> void:
	if t < 0.0 or t > .36:
		return
	var q := t / .36
	var col := c
	col.a = 1.0 - q
	slash(p, -1.08, 190 * scale_factor, 7 * (1 - q) * scale_factor, col)
	slash(p, -2.18, 130 * scale_factor, 5 * (1 - q) * scale_factor, col)
	slash(p, -1.08, 177 * scale_factor, 2.5 * (1 - q) * scale_factor, Color(1, 1, 1, 1 - q))
	slash(p, -2.18, 119 * scale_factor, 2 * (1 - q) * scale_factor, Color(1, 1, 1, 1 - q))

func ink_spray(p: Vector2, t: float, c: Color, size: float) -> void:
	if t < .25 or t > .9:
		return
	var q := (t - .25) / .65
	for i in range(28):
		var dir := Vector2(sin(i * 7.3), cos(i * 4.9))
		var at := p + dir * (size * .3 + q * size * .5) + Vector2(0, q * q * 30)
		var col := c.darkened(.55) if i % 3 != 0 else Color(.015, .012, .025)
		col.a = (1.0 - q) * .8
		draw_rect(Rect2(at.snapped(Vector2(2, 2)), Vector2(2 + i % 3, 3 + i % 4)), col)

## 最終斬撃(単体・全体で同一描画)。寿命1秒。
func finale(p: Vector2, t: float, c: Color) -> void:
	if t < 0.0 or t > 1.0:
		return
	var q := t
	if t < .34:
		var fade := 1.0 - t / .34
		slash(p, -PI / 2, 1500, 110 * fade, c.darkened(.28))
		slash(p, -PI / 2, 1550, 64 * fade, c.lightened(.2))
		slash(p, -PI / 2, 1600, 25 * fade, Color.WHITE)
		for j in range(6):
			var y := p.y - 300 + j * 120
			var side := -1 if j % 2 != 0 else 1
			poly([Vector2(p.x + side * 22, y), Vector2(p.x + side * 135, y - 60), Vector2(p.x + side * 64, y + 8), Vector2(p.x + side * 170, y + 65)], Color(c, fade * .8))
	if t < .09 and screen.has_area():
		draw_rect(screen, Color(1, 1, 1, (1.0 - t / .09) * .9))
	for i in range(3):
		var dt := t - i * .08
		if dt < 0.0:
			continue
		var col := c.lightened(.40)
		col.a = (1.0 - q) * .87
		ring(p, Vector2(45 + dt * 1450, 35 + dt * 920), col, 19 * (1 - q) + 3)
	burst(p, t, c, 4.8)
	for i in range(32):
		var a := i * 2.399
		var at := p + Vector2(cos(a) * q * 560, sin(a) * q * 155 - q * 90)
		var radius := 22 + q * 43
		poly([at + Vector2(-radius, 0), at + Vector2(-radius * .6, -radius), at + Vector2(radius * .4, -radius * 1.1), at + Vector2(radius, 0), at + Vector2(radius * .4, radius * .5), at + Vector2(-radius * .7, radius * .4)], Color(.10, .105, .13, (1.0 - q) * .48))

func _draw() -> void:
	var t := age
	var c := color
	if kind == "single":
		if hits.is_empty():
			return
		var hit := hits[0]
		if t >= 1.3 and t < 1.55:
			slash(hit, -.13, 230, 1.5, Color(.91, 1, .91, 1 - (t - 1.3) / .25))
		cross(hit, t - Motion.SINGLE_FIRST_HIT, c, .85)
		burst(hit, t - Motion.SINGLE_FIRST_HIT, c, .7)
		ink_spray(hit, t - Motion.SINGLE_FINAL, c, 255)
		finale(hit, t - Motion.SINGLE_FINAL, c)
		if t >= Motion.SINGLE_FINAL and t < 2.84:
			slash(home - Vector2(0, 102), 0, 18, 2, Color.WHITE)
	elif kind == "all":
		if hits.is_empty():
			return
		if t >= 1.43 and t < Motion.ALL_FIRST:
			var q := (t - 1.43) / .09
			slash(home + Vector2(-24, -108), -PI / 2 + q * .25, 155, 4 * (1 - q), Color(.94, .94, 1, 1 - q))
		for i in range(hits.size()):
			cross(hits[i], t - Motion.ALL_FIRST, c, .85)
		for i in range(28):
			var dt := t - (2.48 + i * .043)
			if dt < 0.0 or dt > .17:
				continue
			var p := hits[i % hits.size()] + Vector2(sin(i * 7.1) * 28, cos(i * 3.7) * 29)
			var a := -PI / 2 + sin(i * 2.7) * .68
			var col := c
			col.a = 1.0 - dt / .17
			slash(p, a, 100 + i % 4 * 21, 3.5 * (1 - dt / .17), col)
			slash(p, a, 96 + i % 4 * 21, 1.2, Color(1, 1, 1, 1 - dt / .17))
		ink_spray(center, t - Motion.ALL_FINAL, c, 255)
		finale(center, t - Motion.ALL_FINAL, c)
	else:
		var core := home + Vector2(-13, -103)
		if t >= .95 and t < 2.35:
			var q := (t - .95) / 1.4
			for i in range(5):
				var a := i * TAU / 5.0 + sin(q * PI) * .30
				var p := core + Vector2(cos(a), sin(a)) * 7
				draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(3, 3)), Color(.42, .43, .48))
			for i in range(9):
				var phase := fposmod(q * 2 + i * .177, 1.0)
				var p := core + Vector2(sin(i * 4.7) * phase * 32, -phase * 24)
				var col := c
				col.a = sin(phase * PI) * .85
				slash(p, -1.2, 5, 1, col)
		if not awakened and t >= Motion.SUPPORT_RELIGHT and t < 2.65:
			draw_rect(Rect2(home + Vector2(-22, -151), Vector2(3, 4)), Color(1, .02, .02))
		var ring_age := t - Motion.SUPPORT_RELIGHT
		if ring_age >= 0.0 and ring_age < .7:
			var col := c
			col.a = (1.0 - ring_age / .7) * .7
			ring(home - Vector2(0, 3), Vector2(36 + ring_age * 36, 9 + ring_age * 9), col, 2)
