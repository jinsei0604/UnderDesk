extends RBMHeroFxBase
## ① 覚醒前・単体「導光抜刃」: 体に沿う青い炎の溜め→構えで止まるタメ→光の突進→青白い大斬撃＋橙の縁→遅れて切断面が開く二段目の爆光。
## 斬撃・爆光は mid の層（味方より前・ボスより後ろ）へ置いて、技の間もボスの動きが見えるようにしている。

const T := RBMHeroFxTiming.BLADE
## 相手の胸の高さの当たる所（基準は右手前の味方）。_build() で今回の相手の位置へずらす。
var HIT := Vector2(214, 240)

var b_back: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_mid_mix: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var dash: RBMHeroFxRibbon
var dash_core: RBMHeroFxRibbon
var slash_out: RBMHeroFxRibbon
var slash_main: RBMHeroFxRibbon
var seam: RBMHeroFxRibbon
var cross_amber: RBMHeroFxRibbon
var cross_main: RBMHeroFxRibbon
var rings: Array = []

func _build() -> void:
	HIT += focus_delta
	b_back = batch(back)
	blast = blast_quad(back, RBMHeroFx.FIRE, RBMHeroFx.PLASMA, {"amp": 14., "k": .12, "seed": 2.2, "glow": .9, "glow_col": Vector3(.3, .55, 1.), "glow_r": 34.})
	dash = ribbon(back, RBMHeroFx.R_BLUE, {"body": .62, "taper": .45, "skew": .55, "rough": .28, "streak": .7, "glow": .8, "glow_col": Vector3(.2, .55, 1.)})
	dash_core = ribbon(back, RBMHeroFx.R_AMBER, {"body": .4, "taper": .5, "skew": .5, "streak": .6, "glow": .5, "glow_col": Vector3(1., .55, .15)})
	for i in range(3):
		rings.append(ring_quad(mid, RBMHeroFx.A4_BLUE if i != 1 else RBMHeroFx.A4_AMBER, {"squash": .42, "breakup": .5, "seed": float(i) * 4.3 + 1.0, "glow": .4, "glow_col": Vector3(.35, .7, 1.) if i != 1 else Vector3(1., .6, .2)}))
	cross_amber = ribbon(mid, RBMHeroFx.R_AMBER, {"body": .6, "core_shift": -.5, "taper": .55, "rough": .2, "streak": .35, "glow": 1.0, "glow_col": Vector3(1., .5, .1), "seed": 4.0})
	cross_main = ribbon(mid, RBMHeroFx.R_BLUE, {"body": .6, "taper": .6, "rough": .12, "streak": .3, "gain": 1.4, "glow": .6, "glow_col": Vector3(.5, .85, 1.), "seed": 9.0})
	slash_out = ribbon(mid, RBMHeroFx.R_AMBER, {"body": .64, "taper": .5, "rough": .3, "rough_freq": 14., "streak": .35, "glow": 1.0, "glow_col": Vector3(1., .5, .12), "seed": 1.0, "core_shift": .5})
	slash_main = ribbon(mid, RBMHeroFx.R_BLUE, {"body": .66, "taper": .62, "rough": .1, "streak": .35, "gain": 1.35, "glow": .7, "glow_col": Vector3(.35, .75, 1.), "seed": 2.0})
	seam = ribbon(mid, RBMHeroFx.R_BLUE, {"body": .4, "taper": .4, "streak": .1, "gain": 2.0, "glow": .9, "glow_col": Vector3(.5, .85, 1.)})
	b_mid = batch(mid)
	b_mid_mix = batch(mid, false)
	b_front = batch(front)
	slash_out.set_path(RBMHeroFx.bow(HIT + Vector2(250, 190) * .9, HIT - Vector2(250, 190) * .9, 34.0), 58.0)
	slash_main.set_path(RBMHeroFx.bow(HIT + Vector2(250, 190) * .96, HIT - Vector2(250, 190) * .96, 28.0), 40.0)
	seam.set_path(RBMHeroFx.bow(HIT + Vector2(250, 190) * .96, HIT - Vector2(250, 190) * .96, 28.0), 9.0)
	cross_amber.set_path(RBMHeroFx.bow(HIT + Vector2(-260, 180), HIT + Vector2(260, -180), -46.0), 64.0)
	cross_main.set_path(RBMHeroFx.bow(HIT + Vector2(-260, 180), HIT + Vector2(260, -180), -46.0), 40.0)

func _step(t: float) -> void:
	b_back.reset(); b_mid.reset(); b_mid_mix.reset(); b_front.reset()
	var C: float = T.contact
	var S: float = T.seam
	var DS: float = T.dash
	var a := RBMHeroFx.stop_age(t - C)
	var e := t - S
	view["dim"] = RBMHeroFx.key(t, [[0.4, 0.0], [.9, .2], [C - .16, .5], [S + .12, .56], [S + .75, .24], [T.end, 0.0]])

	# 溜め: 体に沿う青い炎と、胸へ集まる線
	var charge := RBMHeroFx.env(t, T.charge, T.draw, DS, DS + .12)
	# タメ: 構えで止まっている間に炎が膨らみ、踏み出す直前に一瞬だけ体へ引き込まれる
	var tame := RBMHeroFx.ramp(t, T.tame, DS - .1)
	var pull := RBMHeroFx.ramp(t, DS - .1, DS - .02)
	view["hero"]["dark_aura"] = RBMHeroFx.ramp(t, T.charge, T.draw) * (1.0 + .5 * tame) * (1.0 - .45 * pull) * (1.0 - RBMHeroFx.ramp(t, DS, DS + .14))
	if charge > .01:
		var ch := anchor("chest")
		inward(b_mid, ch, t, 44, 5, 8.0, 120.0, 2.0, RBMHeroFx.C_CYAN, charge)
		inward(b_mid, ch, t + .3, 24, 11, 6.0, 96.0, 1.6, RBMHeroFx.C_AMBER, charge)
		if tame > 0.0:
			inward(b_mid, anchor("tip"), t, 44, 17, 6.0, 110.0, 2.0, RBMHeroFx.C_PALE, tame * (1.0 - .5 * pull), 2.8)

	# 抜刀の閃き
	var d := t - T.draw
	if d >= 0.0 and d < .3:
		var tip := anchor("tip")
		var s := 1.0 - RBMHeroFx.ramp(d, .03, .2)
		star(b_front, tip, s, 8, 21, 26.0, 4.0, [RBMHeroFx.C_AMBER, RBMHeroFx.C_GOLD, RBMHeroFx.C_WHITE])
		sparks(b_mid, tip, d, .36, 22, 30, 300.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_AMBER, 0.0, TAU, 60.0)

	# 踏み出す直前、刃の先に力が溜まる
	var glint := RBMHeroFx.ramp(t, DS - .16, DS - .02) * (1.0 - RBMHeroFx.ramp(t, DS + .01, DS + .09))
	if glint > 0.0:
		star(b_front, anchor("tip"), glint, 8, 27, 24.0, 4.0, [Color(RBMHeroFx.C_CYAN, .9), RBMHeroFx.C_PALE, RBMHeroFx.C_WHITE])

	# 突進の帯（本体の移動に沿って伸びる）
	var ds := RBMHeroFx.env(t, DS, DS + .08, C + .02, C + .2)
	dash.visible = ds > 0.0
	dash_core.visible = ds > 0.0
	if ds > 0.0:
		var from := Vector2(392, 196)
		var to := Vector2(232, 228) + focus_delta
		var path := RBMHeroFx.bow(to, from, -6.0, 16)
		dash.set_path(path, 26.0)
		dash_core.set_path(path, 12.0)
		# 本体の後ろへ伸びて、到達と同時に根元から消える（帯だけが残らない）
		var head := RBMHeroFx.ramp(t, DS + .04, C)
		var gone := 1.0 - .98 * RBMHeroFx.ramp(t, C - .06, C + .14)
		sp(dash, {"head": gone, "tail": 1.0 - head, "flow": t * 9.0, "fade": ds})
		sp(dash_core, {"head": gone, "tail": 1.0 - head, "flow": t * 11.0, "fade": ds})
		sparks(b_back, Vector2(lerpf(392, 240, head), lerpf(238.0, 268.0, head)) + focus_delta * head, t - DS, .4, 30, 41, 180.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, .4, -40.0)

	# 命中
	if a >= 0.0 and a < 1.0:
		_impact(a, t - C)
	else:
		for r: ColorRect in rings:
			r.visible = false
		slash_out.visible = false
		slash_main.visible = false
		seam.visible = false
		blast.visible = false

	# 二段目（切断面が開く）
	cross_amber.visible = e >= 0.0 and e < .48
	cross_main.visible = cross_amber.visible
	if e >= 0.0 and e < 1.2:
		_second(e)
	if a >= 0.0:
		view["shake"] = hit_shake(a, 5.5) + hit_shake(e, 9.0, 80.0, .42)
	ally_hits(t, [[C, 3], [S, 3]], 1.0)
	var lit := RBMHeroFx.env(t, C, C + .08, C + .3, C + .6) * .85 + RBMHeroFx.env(t, S, S + .06, S + .28, S + .62)
	ally_light(RBMHeroFx.sat(lit), RBMHeroFx.C_GOLD)
	# タメの間は体の輪郭を薄く光らせて、構えを際立たせる
	var rim := .6 * tame * (1.0 - RBMHeroFx.ramp(t, DS, DS + .06))
	if rim > float(view["hero"].get("lit", 0.0)):
		view["hero"]["lit"] = rim
		view["hero"]["lit_col"] = RBMHeroFx.C_PALE
		view["hero"]["lit_side"] = 0.0
	b_back.commit(); b_mid.commit(); b_mid_mix.commit(); b_front.commit()

func _impact(a: float, _real: float) -> void:
	# 主役: 画面を斜めに割る大斬撃
	var head := RBMHeroFx.ramp(a, -.01, .05)
	var thin := 1.0 - .94 * RBMHeroFx.ramp(a, .1, .4)
	var f := 1.0 - RBMHeroFx.ramp(a, .3, .46)
	slash_out.visible = a < .46
	slash_main.visible = a < .46
	if slash_out.visible:
		sp(slash_out, {"head": head, "tail": 0.0, "body": .64 * thin, "flow": a * 4.0, "fade": f})
		sp(slash_main, {"head": head, "tail": 0.0, "body": .66 * thin, "flow": a * 5.0, "fade": f})
	# 切断面の細い線は二段目まで残る
	seam.visible = a < .8
	if seam.visible:
		sp(seam, {"head": 1.0, "tail": 0.0, "flow": a * 5.0, "fade": 1.0 - RBMHeroFx.ramp(a, .55, .8)})
	# 芯の爆光
	blast.visible = a < .62
	if blast.visible:
		var data := blobs(HIT, a, 22, 5, 88.0, 62.0, 34.0, 24.0, 1.8, .55, 12.0)
		show_blast(blast, data, a, {"cool": RBMHeroFx.ramp(a, .12, .6) * .2, "erode": RBMHeroFx.ramp(a, .12, .5), "fade": 1.0 - RBMHeroFx.ramp(a, .2, .44), "erode_noise": .4})
	var s := RBMHeroFx.burst(a, 26.0) * (1.0 - RBMHeroFx.ramp(a, .1, .3))
	star(b_mid, HIT, s, 14, 51, 150.0, 22.0, [Color(RBMHeroFx.C_BLUE, .85), Color(RBMHeroFx.C_AMBER, .95), RBMHeroFx.C_PALE, RBMHeroFx.C_WHITE])
	show_ring(rings[0], HIT, a, .46, 210.0, 7.0, 6.5, .018)
	rings[1].visible = false
	rings[2].visible = false
	sparks(b_mid, HIT, a, .72, 110, 61, 620.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, -2.45, 1.0, 180.0, 2.2)
	sparks(b_mid, HIT, a, .6, 70, 67, 520.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_ORANGE, .7, 1.1, 180.0, 2.0)
	sparks(b_mid, HIT, a, .5, 50, 71, 380.0, RBMHeroFx.C_WHITE, RBMHeroFx.C_AMBER, 0.0, TAU, 140.0, 1.6)
	shards(b_mid, HIT, a, .7, 14, 75, 360.0, 6.0, RBMHeroFx.C_PALE, RBMHeroFx.C_BLUE, 260.0)
	rocks(b_mid_mix, HIT + Vector2(0, 22), a, .75, 10, 79, 300.0, 4.5)

func _second(e: float) -> void:
	var f := 1.0 - RBMHeroFx.ramp(e, .3, .48)
	var thin := 1.0 - .94 * RBMHeroFx.ramp(e, .1, .42)
	if e < .48:
		sp(cross_amber, {"head": RBMHeroFx.ramp(e, -.01, .05), "tail": 0.0, "body": .6 * thin, "flow": e * 4.0, "fade": f})
		sp(cross_main, {"head": RBMHeroFx.ramp(e, -.01, .05), "tail": 0.0, "body": .6 * thin, "flow": e * 5.0, "fade": f})
	if e < .62:
		blast.visible = true
		var data := blobs(HIT, e, 34, 15, 190.0, 120.0, 52.0, 70.0, 1.4, .6, 9.0)
		show_blast(blast, data, e, {"cool": RBMHeroFx.ramp(e, .16, .8) * .22, "erode": RBMHeroFx.ramp(e, .16, .62), "fade": 1.0 - RBMHeroFx.ramp(e, .22, .56), "erode_noise": .4, "tone_cap": .84})
	var s := RBMHeroFx.burst(e, 22.0) * (1.0 - RBMHeroFx.ramp(e, .12, .36))
	star(b_mid, HIT, s, 18, 91, 230.0, 30.0, [Color(RBMHeroFx.C_DEEP, .9), Color(RBMHeroFx.C_ORANGE, .95), RBMHeroFx.C_GOLD, RBMHeroFx.C_WHITE])
	show_ring(rings[2], HIT, e, .36, 250.0, 7.0, 6.0, .03)
	sparks(b_mid, HIT, e, .95, 120, 101, 760.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_ORANGE, 0.0, TAU, 220.0, 2.4)
	sparks(b_mid, HIT, e, .8, 90, 107, 640.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, TAU, 160.0, 2.0)
	shards(b_mid, HIT, e, .95, 26, 111, 460.0, 8.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_ORANGE, 300.0)
	rocks(b_mid_mix, HIT + Vector2(0, 24), e, 1.0, 14, 115, 400.0, 6.0)
	embers(b_front, Rect2(HIT.x - 110, HIT.y - 20, 220, 50), e, 40, 119, 130.0, RBMHeroFx.C_AMBER, 1.0 - RBMHeroFx.ramp(e, .7, 1.2))
