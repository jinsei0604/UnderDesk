extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_vfx_base.gd"
## 勇者の覚醒「英雄の戴冠」: 足元の炎の輪が育ち、火の粉が剣の切っ先へ吸い込まれる → 一瞬の静止 → 天を突く炎の柱と
## 炎の冠（放射の刃）・地を走る熱の輪。Codex の版の「熱の殻」より縦の解放感と英雄らしさを強める。描く数は Codex の版の 1/10 以下。
const RED := Color("d8332c")
const ORANGE := Color("ff7a2a")
const GOLD := Color("ffd27a")
const WHITE := Color("fff4d6")
const TIP := Vector2(0, -118)

func _init() -> void:
	character_id = "hero"
	color = Color("ef4847")
	duration = 5.60
	release_time = 3.00
	quiet_time = 2.80
	dark_peak = 0.52
	hold = 0.06

func shake_amplitude() -> float:
	return 7.0

## 溜めから最後まで剣を頭上に掲げた姿（s:12）のまま決める（振り下ろさない、2026-10-28 ユーザーの指摘）。
func pose_at(t: float) -> String:
	if t < .35: return "b:0"
	if t < .55: return "b:6"
	return "s:12"

func _draw() -> void:
	if not active:
		return
	var t := vt()
	if t < release_time:
		var b := smoothstep(.3, 2.5, t)
		var pull := smoothstep(quiet_time - .2, release_time, t)
		# 足元の炎の輪（育ってから、溜めの最後に切っ先へ吸われて小さくなる）
		for i in 14:
			var a := i * TAU / 14 + t * .6
			var p := Vector2(cos(a) * 62, sin(a) * 15) * (1 - pull * .7)
			var h := (18 + 22 * h1(i)) * b * (1 - pull) * (.8 + .2 * sin(t * 9 + i))
			if h > 3:
				flame(p, 7, h, t * 6 + i, tint(RED.lerp(ORANGE, h1(i + 3)), .9))
		q_ring(Vector2(0, 2), Vector2(64, 16) * (1 - pull * .6), 3, tint(ORANGE, b * .7))
		# 火の粉が螺旋を描いて切っ先へ
		for i in 28:
			var q := fposmod(t * .55 + h1(i) , 1.0)
			var a := i * 2.399 + q * 5.0
			var r := (1 - q) * (90 + 40 * h1(i + 9))
			var p := TIP + Vector2(cos(a) * r, sin(a) * r * .6 + (1 - q) * 70)
			var p2 := TIP + Vector2(cos(a - .25) * r * 1.08, sin(a - .25) * r * .65 + (1 - q) * 76)
			q_line(PackedVector2Array([p2, p]), tint(GOLD.lerp(ORANGE, q), b * sin(q * PI)), 2)
		# 切っ先の光（溜まるほど大きく）
		var s := 4 + 10 * b + 14 * pull
		q_diamond(TIP, s * .35, s, tint(GOLD, .6 * b + .4 * pull))
		q_diamond(TIP, s, s * .3, tint(WHITE, .5 * b + .5 * pull))
	else:
		var u := t - release_time
		var k := 1 - smoothstep(.15, 1.6, u)
		# 天を突く炎の柱（外の赤 → 橙 → 金の芯。上ほど細く、時間とともに細って消える）
		var grow := smoothstep(0, .12, u)
		for layer in 3:
			var w: float = [46.0, 30.0, 14.0][layer] * (1 - smoothstep(.3, 1.5, u)) + 2
			var c: Color = [RED, ORANGE, GOLD][layer]
			var top := -720.0 * grow
			q_poly(PackedVector2Array([Vector2(-w, 6), Vector2(w, 6), Vector2(w * .45, top), Vector2(-w * .45, top)]), tint(c, k * [.75, .85, .95][layer]))
		# 炎の冠: 頭上から放射する刃（交互に長短）
		for i in 12:
			var a := -PI + (i + .5) * PI / 12
			var len := (70 + 50 * float(i % 2)) * smoothstep(0, .18, u) * (1 + u * .4)
			var d := Vector2(cos(a), sin(a))
			var base := Vector2(0, -96) + d * 26
			var side := d.orthogonal() * (9 - 4 * float(i % 2))
			q_tri(base - side, base + side, base + d * len, tint(GOLD.lerp(ORANGE, float(i % 2)), k * .9))
		# 地を走る熱の輪（2重）
		for j in 2:
			var q := maxf(0, u - j * .12)
			var rad := 40 + pow(q, .55) * 320
			q_ring(Vector2(0, 4), Vector2(rad, rad * .22), 10 * (1 - smoothstep(0, 1.1, q)) + 1, tint(ORANGE.lerp(RED, q), (1 - smoothstep(.2, 1.1, q)) * .85))
		# 立ちのぼる火の粉
		for i in 44:
			var a := h1(i) * TAU
			var v := Vector2(cos(a) * (60 + 140 * h1(i + 1)), -120 - 220 * h1(i + 2))
			var p := Vector2(0, -50) + v * u + Vector2(0, 90 * u * u)
			var f := 1 - smoothstep(.4, 1.9, u + h1(i + 4) * .3)
			q_rect(Rect2(p, Vector2(4, 4) * (1 + float(i % 3))), tint(GOLD.lerp(RED, clampf(u / 1.6, 0, 1)), f))
	flush()
