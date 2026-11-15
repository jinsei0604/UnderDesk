extends RBMLionFxBase
## 日蝕の獅皇・覚醒後単体「断罪の爪撃」（2026-11-12 作り直し）: 低く構える → 後脚で立ち上がり爪に黒金の炎（背に小さな日蝕）
## → 一瞬で消える（黒い炎の名残だけ）→ 相手の前に急に現れ、現れた時にはもう爪が振り抜かれている（速すぎて見えなかった）
## → 振り抜きで叩きつけ、地面が割れて黒金の炎が爆ぜる → また消えて、元の位置へ急に現れる（覚醒後の立ち姿）。

const T := {"windup": 0.26, "vanish": 0.66, "appear": 0.90, "slam": 1.22, "vanish2": 1.62, "back": 1.84, "end": 2.40}
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const RED := Color("#e0402a")
const CRIM := Color("#a0132f")
const VOID := Color("#0a0608")

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var burst: ColorRect
var puff: ColorRect
var ring_hit: ColorRect
var eclipse: ColorRect
var final_share := 0.55

func duration() -> float:
	return T.end

func impact() -> float:
	return T.slam

func hits() -> Array:
	return [[T.appear, 3]]

func stops() -> Array:
	return [[T.appear, 0.12], [T.slam, 0.12]]

func _reach() -> Vector2:
	return Vector2(-52, 26) + focus_delta

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.appear, 3], [T.slam, 4], [T.back, 0]]

func move_keys() -> Array:
	var r := _reach()
	return [[0.0, Vector2.ZERO, "snap"], [T.appear, Vector2.ZERO, "snap"], [T.appear + 0.001, r, "snap"], [T.slam, r, "snap"], [T.slam + 0.06, r + Vector2(-10, 0), "out"], [T.back, r + Vector2(-10, 0), "snap"], [T.back + 0.001, Vector2.ZERO, "snap"]]

func _build() -> void:
	b_back = batch(back)
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(ECLIPSE), "seed": 5.5})
	puff = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 18., "k": .1, "seed": 2.7, "glow": .5, "glow_col": Vector3(.9, .15, .15), "glow_r": 24.})
	burst = blast_quad(back, BLACKGOLD, BLACKGOLD, {"amp": 26., "k": .07, "seed": 3.3, "glow": .6, "glow_col": Vector3(.95, .3, .1), "glow_r": 36.})
	ring_hit = ring_quad(front, RBMHeroFx.A4_RED, {"squash": .45, "breakup": .5, "seed": 4.0, "glow": .4, "glow_col": Vector3(.95, .3, .1)})
	b_front = batch(front, false)
	b_add = batch(front)

## 消える所の黒い炎の名残（短く弾けて消える）
func _puff(at_pos: Vector2, age: float) -> void:
	var f := 1.0 - RBMHeroFx.ramp(age, 0.15, 0.35)
	puff.visible = age >= 0.0 and f > 0.0
	if puff.visible:
		show_blast(puff, blobs(at_pos, age, 14, 41, 30.0, 24.0, 13.0, 20.0, .9, 0.0, 12.0), age, {"flow": age * .5, "cool": .1, "erode": RBMHeroFx.ramp(age, .05, .35), "fade": f, "erode_noise": .5, "tone_cap": .85})

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var hit := target_chest(3)
	var ground: Vector2 = targets[3] + Vector2(0, 2)
	var a1 := t - T.appear
	var a2 := t - T.slam
	# 溜め: 立ち上がった爪に黒金の炎、背に小さな日蝕
	var ch := RBMHeroFx.ramp(t, T.windup, T.vanish)
	view["dim"] = 0.25 * ch * (1.0 - RBMHeroFx.ramp(t, T.vanish, T.vanish + 0.1)) + 0.35 * RBMHeroFx.env(t, T.vanish, T.appear, T.slam + 0.2, T.vanish2)
	view["dim_col"] = Color(0.04, 0.01, 0.02)
	if t < T.vanish:
		show_eclipse(eclipse, at("top", 2, 6, -8), 10.0, 12.0 * ch, {"flow": t, "power": ch, "fade": ch, "dread": 1.0})
		var claw := at("front", 2, 4, -4)
		embers(b_add, Rect2(claw.x - 12, claw.y - 6, 24, 16), t, 30, 3, 50.0, RED, ch * 1.4, 2.0, 4.0)
		inward(b_add, claw, t, 50, 7, 4.0, 60.0, 1.4, RED, ch, 2.6)
	else:
		eclipse.visible = false
	view["hero"]["lit"] = 0.45 * ch
	view["hero"]["lit_col"] = RED
	# 一瞬で消える（その場に黒い炎の名残）→ 何も見えない間
	if t >= T.vanish and t < T.appear:
		body["alpha"] = 0.0
	_puff(at("center", 2) if t < T.appear else HOME + _reach() + Vector2(0, -40), t - T.vanish if t < T.vanish2 else t - T.vanish2)
	# 急に現れる: 現れた時にはもう振り抜いている。通った道に残像（現れた後に見える）
	if a1 >= 0.0 and a1 < 0.35:
		var gf := 1.0 - RBMHeroFx.ramp(a1, 0.04, 0.3)
		for k in range(3):
			var u := 0.25 + 0.25 * k
			ghost(2 if k == 2 else 3, _reach().lerp(Vector2.ZERO, u), (0.34 - k * 0.09) * gf, CRIM, 0.5)
		b_add.streak(HOME + _reach() + Vector2(40, -40), HOME + Vector2(0, -50), 3.0 * gf, Color(RED, 0.7 * gf), Color(CRIM, 0.0))
	# 一撃目: 交差する爪（深紅の外・金白の芯）。現れた瞬間に出る
	if a1 >= 0.0 and a1 < 0.6:
		var f := 1.0 - RBMHeroFx.ramp(a1, 0.25, 0.55)
		for i in range(3):
			var cc := hit + Vector2(30 + i * 10, -36 + i * 4)
			crescent(b_front, cc, 48.0, PI * 0.62, PI * 0.62 + 1.15, 11.0 * f, Color(CRIM, 0.9 * f), Color(VOID, 0.0), 1.0)
			crescent(b_add, cc, 48.0, PI * 0.62, PI * 0.62 + 1.15, 5.0 * f, Color(HOT, f), Color(GOLD, 0.8 * f), 1.0)
		for i in range(2):
			var cc := hit + Vector2(-34 - i * 9, -36 + i * 4)
			crescent(b_front, cc, 48.0, PI * 0.38, PI * 0.38 - 1.15, 9.0 * f, Color(CRIM, 0.85 * f), Color(VOID, 0.0), 1.0)
			crescent(b_add, cc, 48.0, PI * 0.38, PI * 0.38 - 1.15, 4.0 * f, Color(HOT, f), Color(GOLD, 0.8 * f), 1.0)
		sparks(b_add, hit, a1, 0.45, 80, 11, 600.0, HOT, RED, PI, PI * 1.3, 180.0, 2.0)
		view["shake"] += hit_shake(a1, 13.0, 90.0, 0.3)
		if a1 < 0.08:
			view["hero"]["flash"] = 0.7 * (1.0 - a1 / 0.08)
			view["hero"]["flash_col"] = HOT
	# 二撃目: 叩きつけ。地面が割れ、黒金の炎が爆ぜる
	var bf := 1.0 - RBMHeroFx.ramp(a2, 0.4, 0.75)
	burst.visible = a2 >= 0.0 and bf > 0.0
	if burst.visible:
		show_blast(burst, blobs(ground + Vector2(0, -14), a2, 28, 9, 150.0, 70.0, 46.0, 70.0, .7, 0.0, 8.0), a2, {"flow": a2 * .3, "cool": .08, "erode": RBMHeroFx.ramp(a2, .25, .75), "fade": bf, "erode_noise": .4, "polar": 1.0, "detail": .6, "radial_heat": .4, "heat_center": w(ground), "heat_radius": 140.0 * RBMHeroFx.burst(a2, 8.0), "erode_radial": 120.0, "tone_cap": .9})
	show_ring(ring_hit, ground, a2, 0.5, 160.0, 6.0, 6.0, 0.03)
	sparks(b_add, ground + Vector2(0, -10), a2, 0.7, 120, 17, 760.0, HOT, RED, -PI * 0.5, PI * 1.2, 260.0, 2.2)
	rocks(b_front, ground, a2, 0.9, 16, 19, 420.0, 5.0)
	view["shake"] += hit_shake(a2, 18.0, 70.0, 0.45)
	ally_hits(t, [[T.appear, 3], [T.slam, 3]], 1.0)
	if a2 >= 0.0:
		view["allies"][3]["force"] = maxf(float(view["allies"][3].get("force", 0.0)), RBMHeroFx.env(a2, 0.0, 0.05, 0.15, 0.55) * 1.2)
	# また消えて、元の位置へ急に現れる
	if t >= T.vanish2 and t < T.back:
		body["alpha"] = 0.0
	if t >= T.back and t < T.back + 0.3:
		var gb := 1.0 - RBMHeroFx.ramp(t, T.back, T.back + 0.25)
		ghost(4, _reach() * 0.5, 0.15 * gb, CRIM, 0.5)
		if t < T.back + 0.08:
			view["hero"]["silhouette"] = 0.6 * (1.0 - (t - T.back) / 0.08)
			view["hero"]["sil_col"] = Color(0.12, 0.02, 0.03)
	b_back.commit(); b_add.commit(); b_front.commit()
