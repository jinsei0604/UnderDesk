extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_vfx_base.gd"
## ハンマー使いの覚醒「地裂」: 力を込めるたびに地面が脈打ち（小さな揺れ）、足元から地割れが伸び、岩が浮き上がる →
## 岩が宙で止まる一瞬 → 叩きつけ: 白い衝撃・大きな揺れ・地割れが光って走り、岩塊が四方へ吹き飛び、土煙が大きく広がる。
## Codex の版より「重さ・衝撃・豪快さ」を強める。
const STONE := Color("8a8580")
const DARK := Color("4e4a47")
const DUST := Color("b8b0a4")
const HOT := Color("ffd9a0")
const WHITE := Color("f6f2ea")
var _pulses := 0

func _init() -> void:
	character_id = "tank"
	color = Color("b7bbc2")
	duration = 5.85
	release_time = 3.15
	quiet_time = 2.98
	dark_peak = 0.5
	hold = 0.12

func shake_amplitude() -> float:
	return 8.0

## 本番の12ポーズだけを使う（中割りの s:N はドット密度が違うので使わない、2026-10-28 ユーザーの指摘）。
## 0 立ち → 8 肩に担いで溜める → 4 頭上に振りかぶる（静止）→ 5 地面へ叩きつけ → 6 構え直し → 0。
func pose_at(t: float) -> String:
	if t < .6: return "b:0"
	if t < 2.98: return "b:8"
	if t < 3.15: return "b:4"
	if t < 4.45: return "b:5"
	if t < 4.75: return "b:6"
	return "b:0"

func play() -> bool:
	_pulses = 0
	return super.play()

func advance(t: float) -> void:
	super.advance(t)
	# 力を込めるたびの地面の脈動（0.7 秒ごと、だんだん強く。2px）
	while active and _pulses < 4 and age >= .7 + _pulses * .55:
		_pulses += 1
		shake_requested.emit(2.0 * shake_strength, .12)

## 地割れ（足元から放射。長さ 0〜1）
func _cracks(len: float, c: Color, w: float) -> void:
	for i in 9:
		var a := i * TAU / 9 + .3
		var pts := PackedVector2Array([Vector2.ZERO])
		var p := Vector2.ZERO
		for j in 4:
			var d := Vector2(cos(a + (h1(i * 5 + j) - .5) * .8), sin(a + (h1(i * 5 + j) - .5) * .8) * .26)
			p += d * 34 * len
			pts.append(p)
		q_line(pts, c, w)

func _rock(p: Vector2, s: float, c: Color) -> void:
	q_poly(PackedVector2Array([p + Vector2(-s, -s * .4), p + Vector2(-s * .4, -s), p + Vector2(s * .8, -s * .7), p + Vector2(s, s * .6), p + Vector2(-s * .7, s)]), c)

func _draw() -> void:
	if not active:
		return
	var t := vt()
	if t < release_time:
		var b := smoothstep(.5, 2.8, t)
		_cracks(b, tint(DARK, .9), 3)
		# 浮き上がる岩（静止の間は宙で止まる）
		var st := minf(t, quiet_time)
		for i in 14:
			var x := (h1(i) - .5) * 220
			var lift := smoothstep(.6 + h1(i + 1) * .8, 2.6, st) * (30 + 50 * h1(i + 2))
			var bob := sin(st * 3 + i) * 2 * (1 - smoothstep(quiet_time - .1, quiet_time, t))
			_rock(Vector2(x, 4 - lift + bob), 4 + 4 * h1(i + 3), tint(STONE.lerp(DARK, h1(i + 4)), smoothstep(.6, 1.2, st)))
		# 足元の圧（低い楕円が重く縮む）
		var squeeze := smoothstep(quiet_time - .4, release_time, t)
		q_ring(Vector2(0, 4), Vector2(90 - 40 * squeeze, 20 - 9 * squeeze), 4, tint(WHITE, b * .6 + squeeze * .4))
	else:
		var u := t - release_time
		var k := 1 - smoothstep(.3, 2.0, u)
		# 叩きつけの瞬間の白い衝撃（地面に沿って横に長い）
		var hit := 1 - smoothstep(0, .18, u)
		if hit > 0:
			q_poly(PackedVector2Array([Vector2(-260, 2), Vector2(0, -26), Vector2(260, 2), Vector2(0, 22)]), tint(WHITE, hit))
		# 地割れが光って走る（熱を持った色 → 暗い色）
		_cracks(1.0 + smoothstep(0, .25, u) * 1.6, tint(HOT.lerp(DARK, smoothstep(.2, 1.2, u)), k), 4)
		# 衝撃波（3重の低い楕円）
		for j in 3:
			var q := maxf(0, u - j * .12)
			var rad := 50 + pow(q, .5) * 340
			q_ring(Vector2(0, 6), Vector2(rad, rad * .23), 12 * (1 - smoothstep(0, 1.0, q)) + 1, tint(WHITE.lerp(DUST, q), (1 - smoothstep(.1, 1.1, q)) * .85))
		# 吹き飛ぶ岩塊（重力つき）
		for i in 24:
			var a := PI + h1(i) * PI
			var v := Vector2(cos(a) * (120 + 160 * h1(i + 1)), -160 - 200 * h1(i + 2))
			var p := Vector2((h1(i + 3) - .5) * 60, 0) + v * u + Vector2(0, 420 * u * u)
			if p.y < 30:
				_rock(p, (4 + 6 * h1(i + 5)) * k + 1, tint(STONE.lerp(DARK, h1(i + 6)), k))
		# 大きな土煙（地面から左右へ膨らむ）
		for i in 10:
			var side := -1.0 if i % 2 == 0 else 1.0
			var q := smoothstep(0, 1.4, u)
			var p := Vector2(side * (30 + 150 * q * (.5 + h1(i))), -10 - 30 * q * h1(i + 2))
			var r := (18 + 26 * h1(i + 3)) * (.4 + q)
			q_poly(_circle(p, Vector2(r, r * .6)), tint(DUST, (1 - smoothstep(.4, 2.4, u)) * .45))
	flush()

func _circle(p: Vector2, r: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 12:
		out.append(p + Vector2(cos(i * TAU / 12) * r.x, sin(i * TAU / 12) * r.y))
	return out
