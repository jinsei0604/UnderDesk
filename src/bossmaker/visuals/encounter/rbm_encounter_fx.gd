extends Node2D
## 登場・勝利の演出の粒と形（表示専用。戦闘の状態・乱数には触れない）。
## ドット絵に合わせて、位置は2pxの格子に丸め、ぼかしは使わず、明るい面・暗い面の2〜3段で塗る。
## - puff: 土煙・煙のかたまり（暗い底・本体・明るい上の3段。膨らみながら薄れる）
## - rock: 岩・瓦礫の破片（5角形・暗い縁取り・回りながら弧を描いて落ちる）
## - spark: 火花（速さの向きに伸びた明るい線）
## - ember: 火の粉・光の粒（ちらつく2pxの点と淡い光）
## - wisp: 霊気・湯気（揺れながら昇る丸）
## - drop: 液体のしずく（地面で小さな水たまりになる）
## - ink: 墨の粒（速さの向きに伸びる）
## - star: きらめき（十字の光）
## 形: shock（衝撃の輪＝帯）、crack（地割れ）、flash（命中点の局所の光）、rays（放射の線）、streak（速さの線）
## 乱数は演出専用の RandomNumberGenerator（固定の種）だけを使い、戦闘の乱数には触れない。時間は advance(dt) で外から進める。

var parts: Array = []
var shocks: Array = []
var cracks: Array = []
var flashes: Array = []
var rays: Array = []
var streaks: Array = []
var rng := RandomNumberGenerator.new()
var ground_y := 9999.0

func _init() -> void:
	rng.seed = 20261016
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func clear() -> void:
	for a in [parts, shocks, cracks, flashes, rays, streaks]:
		a.clear()
	queue_redraw()

func count() -> int:
	return parts.size() + shocks.size() + cracks.size() + flashes.size() + rays.size() + streaks.size()

func advance(dt: float) -> void:
	for p in parts:
		p.age += dt
		p.v += Vector2(0, p.g) * dt
		p.v *= pow(p.drag, dt * 60.0)
		p.p += p.v * dt
		if p.has("spin"):
			p.rot += p.spin * dt
		if p.kind == "wisp":
			p.p.x += sin(p.age * p.freq + p.phase) * p.sway * dt
		if p.kind == "drop" and not p.get("landed", false) and p.p.y >= float(p.get("floor", ground_y)):
			p.landed = true
			p.p.y = float(p.get("floor", ground_y))
			p.v = Vector2.ZERO
			p.g = 0.0
			p.land_age = p.age
		if p.kind == "rock" and p.p.y >= float(p.get("floor", ground_y)) and p.v.y > 0.0:
			p.p.y = float(p.get("floor", ground_y))
			p.v = Vector2(p.v.x * 0.45, -p.v.y * 0.25)
			p.spin *= 0.5
	parts = parts.filter(func(p): return p.age < p.life)
	for a in [shocks, cracks, flashes, rays, streaks]:
		for e in a:
			e.age += dt
	shocks = shocks.filter(func(e): return e.age < e.life)
	cracks = cracks.filter(func(e): return e.age < e.life)
	flashes = flashes.filter(func(e): return e.age < e.life)
	rays = rays.filter(func(e): return e.age < e.life)
	streaks = streaks.filter(func(e): return e.age < e.life)
	queue_redraw()

func _p(kind: String, p: Vector2, v: Vector2, life: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": kind, "p": p, "v": v, "g": 0.0, "drag": 1.0, "life": life, "age": 0.0}
	d.merge(extra, true)
	parts.append(d)
	return d

# --- 粒 ---------------------------------------------------------------------

## 土煙: 足元から左右へ低く広がる、膨らむかたまり。light/base/dark は明るい上・本体・暗い底の色。
func puff(at: Vector2, amount: int, spread: float, base: Color, power: float = 1.0, up: float = 1.0, size: float = 1.0) -> void:
	var light := base.lightened(0.28)
	var dark := base.darkened(0.35)
	for i in range(amount):
		var dir := -1.0 if i % 2 == 0 else 1.0
		var speed := rng.randf_range(30.0, 150.0) * power
		var r0 := rng.randf_range(3.0, 6.0) * size
		_p("puff", at + Vector2(rng.randf_range(-spread, spread) * 0.5, rng.randf_range(-4, 2)),
			Vector2(dir * speed, -rng.randf_range(6.0, 40.0) * power * up), rng.randf_range(0.55, 1.05),
			{"g": -16.0, "drag": 0.90, "r0": r0, "r1": r0 * rng.randf_range(2.0, 3.2), "base": base, "light": light, "dark": dark, "lobes": _lobes()})

func _lobes() -> Array:
	return [Vector2(rng.randf_range(-0.8, -0.4), rng.randf_range(-0.1, 0.3)), Vector2(rng.randf_range(0.3, 0.8), rng.randf_range(0.0, 0.3)), Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.6, -0.3))]

## 上へ昇る煙の柱（倒れた後・火の後）。
func smoke(at: Vector2, amount: int, base: Color, spread: float = 20.0, rise: float = 40.0) -> void:
	for i in range(amount):
		var r0 := rng.randf_range(4.0, 8.0)
		_p("puff", at + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-6, 6)), Vector2(rng.randf_range(-12, 12), -rng.randf_range(rise * 0.5, rise)),
			rng.randf_range(0.8, 1.5), {"g": -6.0, "drag": 0.97, "r0": r0, "r1": r0 * 2.6, "base": base, "light": base.lightened(0.2), "dark": base.darkened(0.3), "lobes": _lobes()})

## 岩・瓦礫の破片。
func rocks(at: Vector2, amount: int, base: Color, power: float = 1.0, size: float = 1.0, floor_y: float = INF) -> void:
	for i in range(amount):
		var a := rng.randf_range(-PI * 0.92, -PI * 0.08)
		var speed := rng.randf_range(110.0, 330.0) * power
		var s := rng.randf_range(2.5, 6.0) * size
		var pts := PackedVector2Array()
		for k in range(5):
			var ang := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
			pts.append(Vector2(cos(ang), sin(ang)) * s * rng.randf_range(0.7, 1.15))
		_p("rock", at + Vector2(rng.randf_range(-10, 10), rng.randf_range(-6, 0)), Vector2(cos(a) * speed, sin(a) * speed),
			rng.randf_range(0.7, 1.2), {"g": 760.0, "drag": 0.996, "shape": pts, "rot": rng.randf() * TAU, "spin": rng.randf_range(-12, 12),
			"base": base.darkened(rng.randf_range(0.0, 0.25)), "floor": floor_y if floor_y != INF else at.y + rng.randf_range(4, 14)})

## 上から落ちる小石・砂。
func fall(area: Rect2, amount: int, base: Color) -> void:
	for i in range(amount):
		var s := rng.randf_range(1.5, 3.0)
		var pts := PackedVector2Array([Vector2(-s, -s), Vector2(s, -s * 0.6), Vector2(s * 0.8, s), Vector2(-s, s * 0.7)])
		_p("rock", Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)),
			Vector2(rng.randf_range(-6, 6), rng.randf_range(0, 40)), rng.randf_range(0.45, 0.8),
			{"g": 520.0, "drag": 0.99, "shape": pts, "rot": 0.0, "spin": rng.randf_range(-6, 6), "base": base, "floor": 99999.0})

## 火花（明るい線）。dir: 中心の向き（ラジアン）、spread: 広がり。
func sparks(at: Vector2, amount: int, core: Color, glow: Color, dir: float = -PI / 2, spread: float = PI, power: float = 1.0) -> void:
	for i in range(amount):
		var a := dir + rng.randf_range(-spread * 0.5, spread * 0.5)
		var speed := rng.randf_range(160.0, 420.0) * power
		_p("spark", at, Vector2(cos(a), sin(a)) * speed, rng.randf_range(0.18, 0.42), {"g": 380.0, "drag": 0.94, "core": core, "glow": glow})

## 火の粉・光の粒（ゆっくり昇る、ちらつく）。
func embers(at: Vector2, amount: int, core: Color, spread: float = 30.0, rise: float = 60.0, life: float = 1.2) -> void:
	for i in range(amount):
		_p("ember", at + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.4, spread * 0.4)),
			Vector2(rng.randf_range(-22, 22), -rng.randf_range(rise * 0.5, rise)), rng.randf_range(life * 0.5, life),
			{"g": -12.0, "drag": 0.975, "core": core, "phase": rng.randf() * TAU})

## 漂う光の粒（空気の中のちり・蛍・星屑）。速さは小さく、長く残る。
func motes(area: Rect2, amount: int, core: Color, drift: Vector2 = Vector2(0, -6), life: float = 3.0) -> void:
	for i in range(amount):
		_p("ember", Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y)),
			drift + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)), rng.randf_range(life * 0.6, life),
			{"core": core, "phase": rng.randf() * TAU, "soft": true})

## 霊気・湯気（揺れながら昇る丸）。
func wisps(at: Vector2, amount: int, base: Color, spread: float = 24.0, rise: float = 50.0, size: float = 1.0) -> void:
	for i in range(amount):
		var r0 := rng.randf_range(2.5, 5.0) * size
		_p("wisp", at + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.5, spread * 0.5)),
			Vector2(rng.randf_range(-8, 8), -rng.randf_range(rise * 0.5, rise)), rng.randf_range(0.7, 1.4),
			{"drag": 0.985, "r0": r0, "r1": r0 * 0.4, "base": base, "freq": rng.randf_range(4, 8), "phase": rng.randf() * TAU, "sway": rng.randf_range(10, 30)})

## 液体のしずく（はねて、地面で水たまりになり縮む）。
func drops(at: Vector2, amount: int, base: Color, power: float = 1.0, floor_y: float = INF, up: float = 1.0) -> void:
	for i in range(amount):
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)
		var speed := rng.randf_range(90.0, 300.0) * power
		_p("drop", at + Vector2(rng.randf_range(-8, 8), rng.randf_range(-4, 0)), Vector2(cos(a) * speed, sin(a) * speed * up),
			rng.randf_range(0.9, 1.4), {"g": 820.0, "drag": 0.995, "r": rng.randf_range(2.0, 4.5), "base": base,
			"floor": floor_y if floor_y != INF else at.y + rng.randf_range(2, 16)})

## 墨の粒。
func ink(at: Vector2, amount: int, dir: float, base: Color, power: float = 1.0) -> void:
	for i in range(amount):
		var speed := rng.randf_range(120.0, 440.0) * power
		_p("ink", at + Vector2(rng.randf_range(-6, 6), rng.randf_range(-3, 3)), Vector2(dir * speed, -rng.randf_range(0.0, 90.0)),
			rng.randf_range(0.3, 0.75), {"g": 320.0, "drag": 0.93, "base": base, "w": rng.randf_range(2.0, 5.0)})

## きらめき。
func stars(at: Vector2, amount: int, core: Color, spread: float = 20.0) -> void:
	for i in range(amount):
		_p("star", at + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)),
			Vector2(rng.randf_range(-10, 10), -rng.randf_range(6, 30)), rng.randf_range(0.35, 0.7), {"drag": 0.95, "core": core, "size": rng.randf_range(3.0, 7.0)})

# --- 形 ---------------------------------------------------------------------

## 衝撃の輪（帯）。squash<1 で地面に沿った楕円。明るい内側の縁と、外へ薄れる帯。
func shock(center: Vector2, r0: float, r1: float, life: float, color: Color, width: float = 6.0, squash: float = 1.0) -> void:
	shocks.append({"c": center, "r0": r0, "r1": r1, "life": life, "age": 0.0, "color": color, "w": width, "squash": squash})

## 地割れ（中心から左右へ、4pxの格子でジグザグに伸びる。暗い溝と、下側の明るい縁）。
func crack(center: Vector2, length: float, color: Color, life: float = 1.8, branches: int = 2) -> void:
	for side in [-1.0, 1.0]:
		for b in range(branches):
			var pts := PackedVector2Array()
			var p := center.snapped(Vector2(4, 4))
			pts.append(p)
			var steps := int(length / 8.0) - b * 5
			var drift := (rng.randf_range(-0.4, 0.4) + (0.9 if b == 1 else 0.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			for i in range(maxi(3, steps)):
				p += Vector2(side * 8.0, roundf(rng.randf_range(-1.0, 1.0) + drift * 0.5) * 4.0)
				pts.append(p.snapped(Vector2(4, 4)))
			cracks.append({"pts": pts, "age": 0.0, "life": life, "color": color, "grow": 0.14 + b * 0.08})

## 命中点の局所の光（4方向に伸びる十字＋丸）。全画面ではない。
func flash(center: Vector2, radius: float, life: float, color: Color) -> void:
	flashes.append({"c": center, "r": radius, "life": life, "age": 0.0, "color": color})

## 放射する光の線。
func ray_burst(center: Vector2, amount: int, length: float, life: float, color: Color, width: float = 2.0) -> void:
	for i in range(amount):
		var a := TAU * float(i) / amount + rng.randf_range(-0.12, 0.12)
		rays.append({"c": center, "angle": a, "len": length * rng.randf_range(0.65, 1.0), "w": width, "life": life, "age": 0.0, "color": color})

## 速さの線（横に流れる細い線。突進・落下の勢い）。
func speed_lines(area: Rect2, amount: int, dir: Vector2, color: Color, life: float = 0.25) -> void:
	for i in range(amount):
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		streaks.append({"p": p, "dir": dir.normalized(), "len": rng.randf_range(30, 90), "speed": rng.randf_range(600, 1100), "life": life * rng.randf_range(0.6, 1.0), "age": 0.0, "color": color})

# --- 描画 -------------------------------------------------------------------

static func _snap(v: Vector2) -> Vector2:
	return v.snapped(Vector2(2, 2))

## 岩の破片をまとめて描く: 暗い縁（少し大きい形）→ 本体 → 明るい角の点、の順に、種類ごとに続けて描く
## （縁取りの線を1つずつ描くと描画の呼び出しが多くなるため）。
func _draw_rocks() -> void:
	var shapes: Array = []
	for p in parts:
		if p.kind != "rock":
			continue
		var t: float = p.age / p.life
		var a := 1.0 - smoothstep(0.75, 1.0, t)
		var c := _snap(p.p)
		var pts := PackedVector2Array()
		var outer := PackedVector2Array()
		for v in p.shape:
			var q := (v as Vector2).rotated(p.rot)
			pts.append(c + q.round())
			outer.append(c + (q * 1.35 + q.normalized()).round())
		shapes.append([pts, outer, Color(p.base, a), a, p.base])
	for s in shapes:
		draw_colored_polygon(s[1], Color(0.05, 0.04, 0.07, s[3]))
	for s in shapes:
		draw_colored_polygon(s[0], s[2])
	for s in shapes:
		draw_rect(Rect2((s[0] as PackedVector2Array)[0] - Vector2(1, 1), Vector2(2, 2)), Color((s[4] as Color).lightened(0.35), s[3]))

func _draw() -> void:
	_draw_rocks()
	for c in cracks:
		var k: float = clampf(c.age / c.grow, 0.0, 1.0)
		var fade: float = 1.0 - smoothstep(c.life * 0.6, c.life, c.age)
		var pts: PackedVector2Array = c.pts
		var n := int(ceil(pts.size() * k))
		var col: Color = c.color
		col.a *= fade
		var lit := Color(0.85, 0.8, 0.9, 0.45 * fade)
		for i in range(1, n):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var x0 := minf(a.x, b.x)
			draw_rect(Rect2(Vector2(x0, a.y), Vector2(absf(b.x - a.x) + 4, 4)), col)
			if b.y != a.y:
				draw_rect(Rect2(Vector2(b.x, minf(a.y, b.y)), Vector2(4, absf(b.y - a.y) + 4)), col)
			draw_rect(Rect2(Vector2(x0, a.y + 4), Vector2(absf(b.x - a.x) + 4, 2)), lit)
	for s in shocks:
		var t: float = s.age / s.life
		var e := 1.0 - pow(1.0 - t, 3.0)
		var r: float = lerpf(s.r0, s.r1, e)
		var w: float = maxf(2.0, roundf(s.w * (1.0 - t * 0.7) / 2.0) * 2.0)
		var col: Color = s.color
		var a: float = col.a * (1.0 - t)
		draw_set_transform(_snap(s.c), 0.0, Vector2(1.0, s.squash))
		draw_arc(Vector2.ZERO, r - w * 0.5, 0.0, TAU, 96, Color(col, a * 0.35), w, false)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(col.lightened(0.4), a), 2.0 / maxf(s.squash, 0.25), false)
		draw_set_transform(Vector2.ZERO)
	for f in flashes:
		var t: float = f.age / f.life
		var col: Color = f.color
		var a: float = col.a * (1.0 - t) * (1.0 - t)
		var c: Vector2 = _snap(f.c)
		var r: float = f.r * (0.7 + 0.3 * t)
		draw_circle(c, r * 0.9, Color(col, a * 0.35), true, -1.0, false)
		draw_circle(c, r * 0.45, Color(col.lightened(0.5), a * 0.85), true, -1.0, false)
		var arm := r * (1.6 - 0.6 * t)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-arm, 0), c + Vector2(0, -3), c + Vector2(arm, 0), c + Vector2(0, 3)]), Color(col.lightened(0.6), a))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -arm * 0.8), c + Vector2(3, 0), c + Vector2(0, arm * 0.8), c + Vector2(-3, 0)]), Color(col.lightened(0.6), a))
	for r in rays:
		var t: float = r.age / r.life
		var col: Color = r.color
		col.a *= (1.0 - t)
		var dir := Vector2(cos(r.angle), sin(r.angle))
		var a: Vector2 = r.c + dir * r.len * (0.15 + 0.4 * t)
		var b: Vector2 = r.c + dir * r.len * (0.45 + 0.55 * t)
		draw_line(_snap(a), _snap(b), col, r.w, false)
	for s in streaks:
		var t: float = s.age / s.life
		var p: Vector2 = s.p + s.dir * s.speed * s.age
		var col: Color = s.color
		col.a *= 1.0 - t
		draw_line(_snap(p), _snap(p - s.dir * s.len), col, 2.0, false)
	for p in parts:
		var t: float = p.age / p.life
		match p.kind:
			"puff":
				# 形の崩れた煙のかたまり: 大きさの違う3つの丸を少しずらして重ね、暗い底→本体→明るい上の順に塗る。
				var r: float = lerpf(p.r0, p.r1, 1.0 - pow(1.0 - t, 2.0))
				r = maxf(2.0, roundf(r))
				var a := (1.0 - smoothstep(0.30, 1.0, t)) * 0.8
				var c := _snap(p.p)
				var lobes: Array = p.get("lobes", [Vector2(-0.6, 0.1), Vector2(0.55, 0.2), Vector2(0.0, -0.45)])
				for l in lobes:
					draw_circle(c + (Vector2(l) * r * 0.75 + Vector2(0, r * 0.25)).round(), roundf(r * 0.8), Color(p.dark, p.dark.a * a), true, -1.0, false)
				for l in lobes:
					draw_circle(c + (Vector2(l) * r * 0.75).round(), roundf(r * 0.75), Color(p.base, p.base.a * a), true, -1.0, false)
				draw_circle(c + (Vector2(lobes[2]) * r * 0.75 + Vector2(-r * 0.2, -r * 0.2)).round(), roundf(r * 0.4), Color(p.light, p.light.a * a * 0.8), true, -1.0, false)
			"rock":
				pass   # 岩はまとめて描く（下の _draw_rocks）
			"spark":
				var a := 1.0 - t
				var head := _snap(p.p)
				var tail := _snap(p.p - p.v * 0.035)
				draw_line(head, tail, Color(p.glow, a * 0.6), 4.0, false)
				draw_line(head, tail, Color(p.core, a), 2.0, false)
			"ember":
				var flick := 0.65 + 0.35 * sin(p.age * 18.0 + p.phase)
				var a := (1.0 - smoothstep(0.55, 1.0, t)) * flick
				if p.get("soft", false):
					a *= smoothstep(0.0, 0.2, t)
				var c := _snap(p.p)
				draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(p.core, 0.22 * a))
				draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(p.core.lightened(0.4), a))
			"wisp":
				var r: float = maxf(1.0, roundf(lerpf(p.r0, p.r1, t)))
				var a := (1.0 - t) * smoothstep(0.0, 0.15, t)
				var c := _snap(p.p)
				draw_circle(c, r + 1, Color(p.base, p.base.a * a * 0.35), true, -1.0, false)
				draw_circle(c, r, Color(p.base.lightened(0.3), p.base.a * a), true, -1.0, false)
			"drop":
				var c := _snap(p.p)
				if p.get("landed", false):
					var lt: float = (p.age - float(p.land_age)) / maxf(0.01, p.life - float(p.land_age))
					var w: float = roundf(float(p.r) * (2.4 - 1.6 * lt))
					var a := 1.0 - lt
					draw_rect(Rect2(c - Vector2(w, 1), Vector2(w * 2, 2)), Color(p.base.darkened(0.2), a))
					draw_rect(Rect2(c - Vector2(w * 0.5, 2), Vector2(w, 1)), Color(p.base.lightened(0.3), a))
				else:
					var r: float = roundf(p.r)
					draw_circle(c, r, p.base, true, -1.0, false)
					draw_rect(Rect2(c - Vector2(r * 0.5, r * 0.6).round(), Vector2(2, 2)), p.base.lightened(0.5))
			"ink":
				var a := 1.0 - smoothstep(0.5, 1.0, t)
				var head := _snap(p.p)
				var tail := _snap(p.p - p.v * 0.025)
				draw_line(head, tail, Color(p.base, p.base.a * a), p.w, false)
			"star":
				var a := 1.0 - t
				var c := _snap(p.p)
				var s: float = roundf(p.size * (1.0 - t * 0.5))
				draw_rect(Rect2(c + Vector2(-s, -1), Vector2(s * 2, 2)), Color(p.core, a))
				draw_rect(Rect2(c + Vector2(-1, -s), Vector2(2, s * 2)), Color(p.core, a))
				draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, a))
