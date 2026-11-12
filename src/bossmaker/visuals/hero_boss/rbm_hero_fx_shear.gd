extends RBMHeroFxBase
## ④ 覚醒後・単体「逆刃・交差断裁」: 空間を裂く黒紅の二連斬（斬るたびに黒い炎が噴き出す）→×字の傷が闇を吸い込む→断裁で×字に沿って炎が画面の端まで噴き出す。
## 太い帯と爆炎はボスの後ろ、細い斬線と火花はボスの手前に置く。手前を切っているように見せながら、ボスの体は隠さない。

const T := RBMHeroFxTiming.SHEAR
## ×字の交差点。標的の体の左寄りに置いて、ボスが×字の開いた側に立つ形にする。
## 相手の胸の高さの当たる所（基準は右手前の味方）。_build() で今回の相手の位置へずらす。
var HIT := Vector2(196, 238)
const TH1 := -2.33
const TH2 := 2.33
## 手前に出す斬線の太さ（後ろの帯に対する割合）
const FRONT_K := .17

var b_back: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_mid_mix: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var aura: ColorRect
var cracks: ColorRect
var burst_q: ColorRect
var blast: ColorRect
var orb: ColorRect
var ring: ColorRect
var dash: RBMHeroFxRibbon
var tears: Array = []
var cores: Array = []
var finals: Array = []
var tears_f: Array = []
var finals_f: Array = []

func _build() -> void:
	HIT += focus_delta
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.A4_RED), "seed": 3.9, "squash": .36, "line_w": .07, "glow_col": Vector3(1., .12, .22), "glow": .4})
	aura = quad(back, Rect2(0, 0, 240, 220), "aura", {"pal_a": RBMHeroFx.pal(RBMHeroFx.AURA_DARK), "pal_b": RBMHeroFx.pal(RBMHeroFx.AURA_DARK), "seed": 9.1, "corrupt": 1.2, "glow_col": Vector3(.8, .06, .18), "glow_col_b": Vector3(.8, .06, .18)})
	burst_q = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 26., "k": .07, "seed": 5.9, "glow": .6, "glow_col": Vector3(.95, .08, .18), "glow_r": 36.})
	blast = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 40., "k": .05, "seed": 8.1, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 50.})
	b_back = batch(back)
	dash = ribbon(back, RBMHeroFx.R_VOID, {"body": .42, "taper": .4, "skew": .55, "rough": .7, "rough_freq": 26., "streak": 0.0, "gain": 1.3, "glow": .9, "glow_col": Vector3(.95, .08, .18)})
	for i in range(2):
		finals.append(ribbon(mid, RBMHeroFx.R_DARK, {"body": .9, "taper": .3, "rough": .4, "rough_freq": 22., "streak": .5, "gain": .92, "glow": .55, "glow_col": Vector3(1., .1, .2), "seed": 3.0 + i}))
		tears.append(ribbon(mid, RBMHeroFx.R_TEAR, {"body": .74, "taper": .42, "rough": .85, "rough_freq": 34., "streak": .25, "gain": 1.15, "glow": .9, "glow_col": Vector3(.95, .08, .18), "seed": 1.0 + i * 5.0}))
	ring = ring_quad(mid, RBMHeroFx.A4_RED, {"squash": .4, "breakup": .65, "seed": 6.8, "glow": .3, "glow_col": Vector3(.95, .1, .2)})
	orb = quad(mid, Rect2(HIT.x - 130, HIT.y - 130, 260, 260), "orb", {"pal": RBMHeroFx.pal(RBMHeroFx.VOID), "seed": 3.7, "glow_col": Vector3(.95, .08, .2), "glow": 1.2})
	b_mid = batch(mid)
	b_mid_mix = batch(mid, false)
	for i in range(2):
		finals_f.append(ribbon(front, RBMHeroFx.R_DARK, {"body": .12, "taper": .3, "rough": .4, "rough_freq": 22., "streak": .5, "gain": .92, "glow": 0.0, "seed": 3.0 + i}))
		tears_f.append(ribbon(front, RBMHeroFx.R_TEAR, {"body": .22, "taper": .42, "rough": .85, "rough_freq": 34., "streak": .25, "gain": 1.15, "glow": 0.0, "seed": 1.0 + i * 5.0}))
		cores.append(ribbon(front, ["#ed274c", "#ff9a88", "#ffffff", "#ffffff", "#ffffff", "#ffffff"], {"body": .4, "taper": .5, "streak": .1, "gain": 2.0, "glow": .4, "glow_col": Vector3(1., .5, .5)}))
	b_front = batch(front)
	for i in range(2):
		# 一撃目は左下→右上の刃の構え、二撃目は左上→右下の刃の構えに合わせる
		var th: float = TH2 if i == 0 else TH1
		var d := Vector2.from_angle(th)
		var nv := RBMHeroFx.bow(HIT - d * 340.0, HIT + d * 340.0, -18.0 if i == 0 else 18.0)
		(tears[i] as RBMHeroFxRibbon).set_path(nv, 66.0)
		(tears_f[i] as RBMHeroFxRibbon).set_path(nv, 66.0)
		(cores[i] as RBMHeroFxRibbon).set_path(nv, 18.0)
		(finals[i] as RBMHeroFxRibbon).set_path(RBMHeroFx.bow(HIT - d * 620.0, HIT + d * 620.0, 0.0), 84.0)
		(finals_f[i] as RBMHeroFxRibbon).set_path(RBMHeroFx.bow(HIT - d * 620.0, HIT + d * 620.0, 0.0), 84.0)

func _step(t: float) -> void:
	for b: RBMHeroFxBatch in [b_back, b_mid, b_mid_mix, b_front]:
		b.reset()
	var C1: float = T.cut1
	var C2: float = T.cut2
	var F: float = T.final
	var a1 := RBMHeroFx.stop_age(t - C1)
	var a2 := RBMHeroFx.stop_age(t - C2)
	var af := RBMHeroFx.stop_age(t - F)
	view["dim"] = .86 * RBMHeroFx.env(t, .55, 1.36, 2.5, 3.1)
	view["dim_col"] = Color(.03, .01, .05)

	# 溜め。オーラは斬るたびに大きくなり、断裁まで縮まない
	var ch := RBMHeroFx.env(t, T.charge, T.dash - .2, C1 - .06, C1 + .1)
	view["hero"]["dark_aura"] = RBMHeroFx.key(t, [[T.charge, 1.0], [float(T.dash) - .2, 1.3], [C1, 1.5], [C2, 1.75], [F, 1.9], [F + .1, 2.2], [F + .7, 1.25], [float(T.duration) - .3, 1.0]])
	aura.visible = ch > .01
	if aura.visible:
		aura.position = foot + Vector2(-120, -216)
		sp(aura, {"power": .36 + .46 * ch, "flow": t * 2.8, "width": .18 + .1 * ch})
	if ch > .01:
		var tip := anchor("tip")
		var sd := int(t * 10.0)
		for i in range(5):
			arc(b_mid, tip, tip + Vector2.from_angle(RBMHeroFx.r(i, sd) * TAU) * (20.0 + 50.0 * RBMHeroFx.r(i, sd + 3)), sd + i, 1.0, Color(RBMHeroFx.C_RED, .7), RBMHeroFx.C_ROSE, 6, .2)
		inward(b_mid, anchor("chest"), t, 80, 3, 10.0, 200.0, 2.2, RBMHeroFx.C_RED, ch)
		embers(b_back, Rect2(foot.x - 70, foot.y - 26, 140, 30), t, 50, 9, 150.0, RBMHeroFx.C_RED, ch)

	# 突進の裂け目
	var ds := RBMHeroFx.env(t, T.dash, T.dash + .08, C1 + .01, C1 + .14)
	dash.visible = ds > 0.0
	if ds > 0.0:
		var path := RBMHeroFx.bow(Vector2(232, 224) + focus_delta, Vector2(385, 194), 6.0, 16)
		var head := RBMHeroFx.ramp(t, T.dash + .03, C1)
		dash.set_path(path, 34.0)
		sp(dash, {"head": 1.0 - .98 * RBMHeroFx.ramp(t, C1 - .06, C1 + .12), "tail": 1.0 - head, "flow": t * 8.0, "fade": ds})
		sparks(b_back, Vector2(lerpf(385.0, 240.0, head), lerpf(238.0, 266.0, head)) + focus_delta * head, t - T.dash, .4, 40, 41, 220.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, .5, -40.0)

	# 一撃目・二撃目
	_cut(0, a1, F - C1, t)
	_cut(1, a2, F - C2, t)
	var burst_on := false
	if a2 >= 0.0 and a2 < .34:
		_cut_burst(a2, 44, 1.3)
		burst_on = true
	elif a1 >= 0.0 and a1 < .36:
		_cut_burst(a1, 18, 1.0)
		burst_on = true
	burst_q.visible = burst_on
	if a1 >= 0.0 and a1 < .6:
		_hit(a1, 11, 1.0)
	if a2 >= 0.0 and a2 < .6:
		_hit(a2, 37, 1.25)

	# ×字が闇を吸い込む
	var pull := RBMHeroFx.env(t, C2 + .08, F - .1, F - .02, F)
	orb.visible = pull > .01
	if orb.visible:
		sp(orb, {"radius": .08 + .34 * RBMHeroFx.ramp(t, C2 + .08, F - .04), "flow": t * 6.0, "spike": 1.1, "fade": 1.0})
	inward(b_mid, HIT, t, 130, 13, 8.0, 330.0, 2.6, RBMHeroFx.C_RED, pull, 4.2)
	inward(b_mid, HIT, t + .3, 70, 19, 8.0, 260.0, 2.0, RBMHeroFx.C_ROSE, pull, 3.4)

	if af >= 0.0:
		_final(af)
	else:
		blast.visible = false
		cracks.visible = false
		ring.visible = false
		for i in range(2):
			(finals[i] as RBMHeroFxRibbon).visible = false
			(finals_f[i] as RBMHeroFxRibbon).visible = false
	view["shake"] = hit_shake(a1, 7.0) + hit_shake(a2, 9.0) + hit_shake(af, 17.0, 76.0, .7)
	ally_hits(t, [[C1, 3], [C2, 3], [F, 3]], 1.35)
	var lit := RBMHeroFx.env(t, C1, C1 + .06, C1 + .2, C1 + .4) + RBMHeroFx.env(t, C2, C2 + .06, C2 + .2, C2 + .4) + RBMHeroFx.env(t, F, F + .06, F + .4, F + .9)
	ally_light(RBMHeroFx.sat(lit) * .85, RBMHeroFx.C_RED)
	for b: RBMHeroFxBatch in [b_back, b_mid, b_mid_mix, b_front]:
		b.commit()

func _cut(i: int, a: float, until: float, t: float) -> void:
	var tear: RBMHeroFxRibbon = tears[i]
	var core: RBMHeroFxRibbon = cores[i]
	var tear_f: RBMHeroFxRibbon = tears_f[i]
	var f := 1.0 - RBMHeroFx.ramp(a, until + .22, until + .56)
	tear.visible = a >= 0.0 and f > 0.0
	core.visible = tear.visible
	tear_f.visible = tear.visible
	if tear.visible:
		var head := RBMHeroFx.ramp(a, -.01, .04)
		var narrow := lerpf(1.0, .36, RBMHeroFx.ramp(a, .04, .3)) * (1.0 - .9 * RBMHeroFx.ramp(a, until + .08, until + .46))
		sp(tear, {"head": head, "tail": 0.0, "body": .74 * narrow, "flow": t * 1.6, "fade": f})
		sp(tear_f, {"head": head, "tail": 0.0, "body": .74 * FRONT_K * narrow, "flow": t * 1.6, "fade": f})
		sp(core, {"head": head, "tail": 0.0, "body": .24 * maxf(narrow, .45), "flow": t, "fade": f})

## 斬った所から黒い炎が放射状に噴き出す。
func _cut_burst(a: float, sd: int, power: float) -> void:
	var data := blobs(HIT, a, 24, sd, 150.0 * power, 96.0 * power, 46.0 * power, 40.0, 1.0, 0.0, 10.0)
	show_blast(burst_q, data, a, {"flow": a * .22, "cool": .06 + RBMHeroFx.ramp(a, .1, .34) * .2, "erode": RBMHeroFx.ramp(a, .1, .32), "fade": 1.0 - RBMHeroFx.ramp(a, .18, .34), "erode_noise": .4,
		"polar": 1.0, "detail": .6, "radial_heat": .36, "heat_center": w(HIT), "heat_radius": 230.0 * power * RBMHeroFx.burst(a, 10.0), "erode_radial": 160.0, "tone_cap": .8})

func _hit(a: float, sd: int, power: float) -> void:
	var s := RBMHeroFx.burst(a, 30.0) * (1.0 - RBMHeroFx.ramp(a, .08, .3))
	star(b_front, HIT, s, 10, sd + 3, 46.0 * power, 8.0, [RBMHeroFx.C_ROSE, RBMHeroFx.C_WHITE])
	refract_wave(HIT, a, .5, 260.0 * power, 6.2, .015)
	sparks(b_front, HIT, a, .75, 130, sd + 7, 760.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 210.0, 2.2)
	shards(b_mid_mix, HIT, a, .75, 18, sd + 9, 460.0, 6.0, Color("#2a0b2a"), RBMHeroFx.C_VOID, 260.0)
	rocks(b_mid_mix, HIT + Vector2(0, 22), a, .8, 10, sd + 13, 380.0, 5.0)

## ×字に沿って広がる炎の玉（腕は画面の端まで、中心は丸く）。
func _x_blobs(a: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	var ex := RBMHeroFx.burst(a, 6.0)
	var d1 := Vector2.from_angle(TH1)
	var d2 := Vector2.from_angle(TH2)
	var dirs := [d1, d2, -d1, -d2]
	for i in range(30):
		var d: Vector2 = dirs[i % 4]
		var u := pow(RBMHeroFx.r(i, 31), .7)
		var side := (RBMHeroFx.r(i, 33) - .5) * 70.0
		var p := HIT + (d * 560.0 * u + Vector2(-d.y, d.x) * side) * ex
		var rad := (40.0 + 46.0 * RBMHeroFx.r(i, 35)) * (1.0 - .35 * u) * pow(ex, .55)
		out.append(Vector4(p.x - RBMHeroFx.WORLD.position.x, p.y - RBMHeroFx.WORLD.position.y, rad, clampf(1.02 - u * .4 - a * .62, .02, 1.0)))
	out.append_array(blobs(HIT, a, 18, 41, 220.0, 130.0, 86.0, 60.0, .62, 0.0, 8.0))
	return out

func _final(a: float) -> void:
	# ×字の腕が画面の端まで走る
	var f := 1.0 - RBMHeroFx.ramp(a, .26, .5)
	for i in range(2):
		var r: RBMHeroFxRibbon = finals[i]
		var r_f: RBMHeroFxRibbon = finals_f[i]
		r.visible = f > 0.0
		r_f.visible = r.visible
		if r.visible:
			var spread := RBMHeroFx.burst(a, 26.0)
			var body := .72 * (1.0 - .8 * RBMHeroFx.ramp(a, .06, .42))
			sp(r, {"head": .5 + .5 * spread, "tail": .5 - .5 * spread, "body": body, "flow": a * 6.0, "fade": f})
			sp(r_f, {"head": .5 + .5 * spread, "tail": .5 - .5 * spread, "body": body * FRONT_K, "flow": a * 6.0, "fade": f})
	# ×字に沿って噴き出す黒紅の炎
	var bf := 1.0 - RBMHeroFx.ramp(a, .46, .84)
	blast.visible = bf > 0.0
	if blast.visible:
		show_blast(blast, _x_blobs(a), a, {"flow": a * .22, "cool": .06 + RBMHeroFx.ramp(a, .2, 1.1) * .26, "erode": RBMHeroFx.ramp(a, .32, .92), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "heat_center": w(HIT), "heat_radius": 430.0 * RBMHeroFx.burst(a, 6.2), "erode_radial": 220.0, "tone_cap": .8})
	var cf := 1.0 - RBMHeroFx.ramp(a, .7, 1.25)
	cracks.visible = cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(HIT + Vector2(0, 24)), "reveal": 460.0 * RBMHeroFx.burst(a, 7.0), "fade": cf})
	var s := RBMHeroFx.burst(a, 24.0) * (1.0 - RBMHeroFx.ramp(a, .1, .42))
	star(b_front, HIT, s, 14, 59, 60.0, 11.0, [RBMHeroFx.C_ROSE, RBMHeroFx.C_WHITE])
	show_ring(ring, HIT, a, .45, 420.0, 7.0, 5.4, .02)
	sparks(b_front, HIT, a, 1.0, 110, 61, 1240.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 230.0, 2.8)
	sparks(b_mid, HIT, a, 1.0, 150, 63, 1240.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 230.0, 2.8)
	sparks(b_mid, HIT, a, .8, 120, 67, 900.0, RBMHeroFx.C_WHITE, RBMHeroFx.C_ROSE, 0.0, TAU, 170.0, 1.8)
	# 遅れて地面から噴き上がる火の粉
	sparks(b_mid, HIT + Vector2(0, 26), a - .12, .9, 200, 83, 900.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, -PI * .5, 1.4, 260.0, 2.6)
	shards(b_mid_mix, HIT, a, 1.05, 34, 71, 780.0, 9.0, Color("#3a0f33"), RBMHeroFx.C_VOID, 300.0)
	shards(b_mid, HIT, a, .95, 36, 73, 640.0, 7.0, RBMHeroFx.C_RED, RBMHeroFx.C_CRIM, 280.0)
	rocks(b_mid_mix, HIT + Vector2(0, 26), a, 1.1, 20, 77, 640.0, 8.0)
	embers(b_front, Rect2(HIT.x - 240, HIT.y - 30, 480, 90), a, 150, 79, 190.0, RBMHeroFx.C_RED, RBMHeroFx.env(a, .25, .6, 1.2, 1.7), 2.2)
