extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_vfx_base.gd"
## 侍の覚醒「一閃」: 納刀・閉眼（s:18）のまま。木の葉が渦を巻いて次第に遅くなり、目の高さに張りつめた一本の線 →
## 葉が空中で止まり、鼓動が2回（暗転が脈打つ）→ 画面を横切る一閃と遅れて交差する斬撃、止まっていた葉が真っ二つに割れて飛ぶ。
## Codex の版より「緊張 → 一閃の圧」の落差を強める。
const GREEN := Color("a4f255")
const DEEP := Color("4f9a3a")
const WHITE := Color("f4ffe6")
const EYE := Vector2(0, -78)

func _init() -> void:
	character_id = "samurai"
	color = Color("a4f255")
	duration = 5.35
	release_time = 2.85
	quiet_time = 2.30
	dark_peak = 0.62
	hold = 0.10

func shake_amplitude() -> float:
	return 6.0

func pose_at(_t: float) -> String:
	return "s:18"

## 静止の間の鼓動（2回、暗転が少し深くなる）
func extra_dark() -> float:
	var p := 0.0
	for beat in [2.42, 2.66]:
		p = maxf(p, maxf(0, 1 - absf(age - beat) / .07))
	return p * .12

## 葉の位置（解放までの時間 st。静止の後は止まる）
func _leaf(i: int, st: float) -> Vector2:
	var speed := 1.6 * (1 - smoothstep(.8, quiet_time, st)) + .05
	var a := i * 2.399 + st * speed * (1 + h1(i) * .5)
	var r := 70 + 70 * h1(i + 5)
	return Vector2(cos(a) * r, -40 - 60 * h1(i + 7) + sin(a) * r * .32)

## a から b への刃（太さ thick は中央の半分の太さ、bow は反りの高さ）。両端は尖る。
func _blade(a: Vector2, b: Vector2, thick: float, bow: float, alpha: float) -> void:
	var n := 24
	var dir := (b - a).normalized()
	var nor := dir.orthogonal()
	var prev_c := a
	var prev_w := 0.0
	for i in range(1, n + 1):
		var s := float(i) / n
		var c := a.lerp(b, s) + nor * bow * sin(s * PI)
		var w := thick * pow(sin(s * PI), .7)
		q_poly(PackedVector2Array([prev_c - nor * (prev_w + 2), c - nor * (w + 2), c + nor * (w + 2), prev_c + nor * (prev_w + 2)]), tint(GREEN, alpha * .6))
		q_poly(PackedVector2Array([prev_c - nor * prev_w, c - nor * w, c + nor * w, prev_c + nor * prev_w]), tint(WHITE, alpha))
		prev_c = c
		prev_w = w

func _draw() -> void:
	if not active:
		return
	var t := vt()
	var st := minf(t, quiet_time)
	if t < release_time:
		var b := smoothstep(.2, 1.4, t)
		var still := smoothstep(quiet_time, quiet_time + .1, t)
		for i in 22:
			var p := _leaf(i, st)
			q_diamond(p, 2, 6, tint(GREEN.lerp(DEEP, h1(i)), b * .9), st * 2 + i)
		# 足元の風の輪（遅くなって消える）
		q_ring(Vector2(0, 2), Vector2(70, 16), 2, tint(GREEN, b * (1 - still) * .6), st * 2, PI * 1.3)
		# 目の高さに張りつめた線（溜めるほど長く・はっきり）
		var tl := smoothstep(1.2, quiet_time, t)
		q_line(PackedVector2Array([EYE + Vector2(-300 * tl, 0), EYE + Vector2(340 * tl, 0)]), tint(WHITE, tl * (.25 + .25 * still)), 2)
		# 鍔元のきらめき（静止の後）
		if still > 0:
			q_diamond(Vector2(-6, -52), 2 + 6 * still, 2, tint(WHITE, still))
			q_diamond(Vector2(-6, -52), 2, 2 + 8 * still, tint(WHITE, still))
	else:
		var u := t - release_time
		var k := 1 - smoothstep(.2, 1.6, u)
		# 一閃（画面を横切る刃。中央が太く両端が尖る、わずかに反った形。緑の縁＋白い芯。細って消える）
		var cut := 1 - smoothstep(0, .35, u)
		if cut > 0:
			_blade(EYE + Vector2(-640, 10), EYE + Vector2(680, -14), 10 * cut + 1, 14, cut)
		# 遅れて交差する斜めの斬撃（細め）
		var x := 1 - smoothstep(.12, .45, u)
		if u > .12 and x > 0:
			_blade(Vector2(-190, 50), Vector2(185, -215), 6 * x + 1, -10, x)
		# 止まっていた葉が真っ二つに割れて飛ぶ
		for i in 22:
			var p := _leaf(i, quiet_time)
			var away := (p - EYE).normalized()
			var v := u * (180 + 80 * h1(i + 2))
			for half in [-1.0, 1.0]:
				var q := p + away * v + Vector2(0, half * (4 + v * .25)) + Vector2(0, 60 * u * u)
				q_diamond(q, 2, 4, tint(GREEN.lerp(WHITE, .3), k), half * u * 6)
		# 風の航跡（刃の線から上下に開く弧）
		for j in 3:
			var q := maxf(0, u - j * .08)
			var r := 60 + pow(q, .5) * 260
			q_ring(EYE + Vector2(20, 0), Vector2(r, r * .38), 5 * (1 - smoothstep(0, 1.2, q)) + 1, tint(GREEN, (1 - smoothstep(.1, 1.3, q)) * .8), -PI * .15 + j, PI * .9)
	flush()
