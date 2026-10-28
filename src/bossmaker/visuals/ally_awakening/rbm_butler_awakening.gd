extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_vfx_base.gd"
## 老執事の覚醒「静寂の氷晶」: 足元に時計の文字盤の霜が描かれ、秒針が刻むたびに霜が伸びる → 秒針が止まり、すべてが静止 →
## 地面から氷の尖塔の冠が突き上がり、砕けて舞い、頭上に大きな雪の結晶。Codex の版より「静から動」の落差と威圧感を強める。
const BLUE := Color("509cf5")
const ICE := Color("bfe6ff")
const WHITE := Color("f2fbff")
const DEEP := Color("2a5fb8")

func _init() -> void:
	character_id = "butler"
	color = Color("509cf5")
	duration = 5.90
	release_time = 3.25
	quiet_time = 2.70
	dark_peak = 0.58
	hold = 0.08

func shake_amplitude() -> float:
	return 5.0

func pose_at(t: float) -> String:
	if t < .48: return "b:0"
	if t < .72: return "s:1"
	if t < 2.7: return "s:2"
	if t < 3.4: return "s:3"
	if t < 4.95: return "s:1"
	return "b:0"

func _draw() -> void:
	if not active:
		return
	var t := vt()
	if t < release_time:
		var b := smoothstep(.2, 1.6, t)
		var tick := floorf(minf(t, quiet_time) * 2.0)  # 0.5 秒ごとに刻む。静止の後は止まる
		var frozen := smoothstep(quiet_time, quiet_time + .15, t)
		# 足元の文字盤（外周と12の目盛り）
		var center := Vector2(0, 2)
		q_ring(center, Vector2(92, 24) * b, 2, tint(ICE, .7 * b))
		q_ring(center, Vector2(72, 19) * b, 2, tint(BLUE, .5 * b))
		for i in 12:
			var a := i * TAU / 12
			var d := Vector2(cos(a), sin(a) * .26)
			q_line(PackedVector2Array([center + d * 76 * b, center + d * 90 * b]), tint(WHITE, b * (.9 if i % 3 == 0 else .5)), 2)
		# 秒針（刻むたびに霜の枝が1本ずつ伸びる）
		var ha := -PI * .5 + tick * TAU / 12
		q_line(PackedVector2Array([center, center + Vector2(cos(ha), sin(ha) * .26) * 70 * b]), tint(WHITE, b), 2)
		for i in int(tick):
			var a := -PI * .5 + (i + 1) * TAU / 12
			var d := Vector2(cos(a), sin(a) * .26)
			var p := center + d * 92
			var len := 22.0 + 10 * h1(i)
			q_line(PackedVector2Array([p, p + d * len]), tint(ICE, .8), 2)
			q_line(PackedVector2Array([p + d * len * .5, p + d * len * .5 + d.rotated(.7) * 9]), tint(ICE, .6), 2)
		# 舞う細かな雪（静止の後は空中で止まる）
		var st := minf(t, quiet_time)
		for i in 26:
			var q := fposmod(st * .18 + h1(i), 1.0)
			var p := Vector2((h1(i + 2) - .5) * 260 + sin(st + i) * 8, -170 + q * 170)
			q_rect(Rect2(p, Vector2(2, 2)), tint(WHITE, b * sin(q * PI) * (1 - frozen * .3)))
		# 静止の瞬間: 冷気が足元へ凝縮する白い輪
		if frozen > 0:
			q_ring(center, Vector2(40 + 50 * (1 - frozen), 10 + 13 * (1 - frozen)), 3, tint(WHITE, frozen))
	else:
		var u := t - release_time
		var k := 1 - smoothstep(.2, 1.9, u)
		var rise := smoothstep(0, .14, u)
		var shatter := smoothstep(.62, .75, u)
		# 氷の尖塔の冠（地面から突き上がる。0.7 秒で砕ける）
		for i in 11:
			var a := PI + (i + .5) * PI / 11
			var x := cos(a) * 110
			var h := (60 + 70 * (1 - absf(cos(a)))) * rise
			var base := Vector2(x, 6 + sin(a) * -8)
			var w := 11 + 6 * h1(i)
			if shatter < 1:
				q_poly(PackedVector2Array([base + Vector2(-w, 0), base + Vector2(w, 0), base + Vector2(w * .3, -h), base + Vector2(0, -h - 12)]), tint(ICE.lerp(DEEP, .2 * float(i % 2)), 1 - shatter))
				q_line(PackedVector2Array([base + Vector2(0, -2), base + Vector2(0, -h)]), tint(WHITE, (1 - shatter) * .8), 2)
			# 砕けた破片
			if shatter > 0:
				var v := u - .62
				for j in 4:
					var dir := Vector2(cos(a + (j - 1.5) * .5), -1.0 + .4 * h1(i * 4 + j)).normalized()
					var p := base + Vector2(0, -h * (.25 + .2 * j)) + dir * v * (160 + 60 * h1(i + j)) + Vector2(0, 120 * v * v)
					q_diamond(p, 3, 6, tint(ICE.lerp(WHITE, h1(j)), k), v * 8 + j)
		# 頭上の大きな雪の結晶（6 本の枝）
		var gs := smoothstep(0, .25, u) * (1 + u * .15)
		var top := Vector2(0, -150)
		for i in 6:
			var d := Vector2.from_angle(i * TAU / 6 + u * .2)
			q_line(PackedVector2Array([top, top + d * 46 * gs]), tint(WHITE, k), 3)
			for j in 2:
				var p := top + d * (18 + 14 * j) * gs
				q_line(PackedVector2Array([p, p + d.rotated(.8) * 10 * gs]), tint(ICE, k), 2)
				q_line(PackedVector2Array([p, p + d.rotated(-.8) * 10 * gs]), tint(ICE, k), 2)
		# 地を這う冷気の輪
		for j in 2:
			var q := maxf(0, u - j * .14)
			var rad := 60 + pow(q, .5) * 260
			q_ring(Vector2(0, 4), Vector2(rad, rad * .24), 6 * (1 - smoothstep(0, 1.2, q)) + 1, tint(ICE, (1 - smoothstep(.2, 1.3, q)) * .7))
	flush()
