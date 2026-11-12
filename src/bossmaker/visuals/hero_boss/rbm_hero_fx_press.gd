extends RBMHeroFxBase
## ⑤ 覚醒後・全体「双鏡執行・落陽断」＝断罪: 四人へ断罪の線が降り、ボスの振り下ろしと一緒に画面そのものが切れる。
## 刃先の通った線（一本だけ）で画面が裂け、四人をまとめて斬る。大地が裂けて黒い炎の柱が順に噴き上がり、最後に黒紅の炎が噴き出して、切れた画面が閉じる。

const T := RBMHeroFxTiming.PRESS
const TIP := Vector2(225, 276)
## 画面の切れる線。振り下ろした刃先の通り道（右上→左下）に合わせ、少しパーティー側へ寄せている。
const CUT_A := Vector2(423, -130)
const CUT_B := Vector2(117, 396)
## 線の上の基準の点（ここからの距離で裂け目の先頭を決める）
const CUT_P := Vector2(188, 274)
## パーティーの中心
const PARTY_C := Vector2(175, 225)
## 四人に当たる順（味方の番号）
const ORDER := [1, 0, 3, 2]
## 手前に出す斬線の太さ（後ろの帯に対する割合）
const FRONT_K := .17
const CORE_PAL := ["#ed274c", "#ff9a88", "#ffffff", "#ffffff", "#ffffff", "#ffffff"]
## 黒い炎の柱の高さと根元の半幅（jets の順）
const JET_H := [190.0, 140.0, 160.0, 120.0, 145.0, 105.0, 125.0, 110.0, 95.0, 100.0, 90.0]
const JET_W := [30.0, 25.0, 27.0, 23.0, 25.0, 21.0, 23.0, 21.0, 19.0, 20.0, 18.0]

var b_sky: RBMHeroFxBatch
var b_wall: RBMHeroFxBatch
var b_wall_add: RBMHeroFxBatch
var b_back: RBMHeroFxBatch
var b_front_wall: RBMHeroFxBatch
var b_front_add: RBMHeroFxBatch
var b_mix: RBMHeroFxBatch
var aura: ColorRect
var fissure: ColorRect
var jets_q: ColorRect
var burst_r: ColorRect
var blast: ColorRect
var hit_blast: ColorRect
var edge: RBMHeroFxRibbon
var edge2: RBMHeroFxRibbon
var trail: RBMHeroFxRibbon
var stroke_b: RBMHeroFxRibbon
var stroke_f: RBMHeroFxRibbon
var stroke_c: RBMHeroFxRibbon

func _build() -> void:
	b_sky = batch(back)
	aura = quad(back, Rect2(0, 0, 260, 240), "aura", {"pal_a": RBMHeroFx.pal(RBMHeroFx.AURA_DARK), "pal_b": RBMHeroFx.pal(RBMHeroFx.AURA_DARK), "seed": 2.2, "corrupt": 1.2, "glow_col": Vector3(.8, .06, .18), "glow_col_b": Vector3(.8, .06, .18)})
	burst_r = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 40., "k": .05, "seed": 8.7, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 50.})
	blast = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.VOID, {"amp": 36., "k": .05, "seed": 7.3, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 40., "rim_mode": 1., "rim_w": 18.})
	hit_blast = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 24., "k": .08, "seed": 3.9, "glow": .6, "glow_col": Vector3(.95, .08, .18), "glow_r": 34.})
	b_wall_add = batch(back)
	b_wall = batch(back, false)
	b_back = batch(back)
	trail = ribbon(back, RBMHeroFx.R_VOID, {"body": .55, "taper": .4, "skew": .55, "rough": .7, "rough_freq": 26., "streak": 0.0, "gain": 1.3, "glow": .9, "glow_col": Vector3(.95, .08, .18)})
	trail.set_path(RBMHeroFx.bow(Vector2(296, 222), Vector2(372, 112), 6.0, 16), 42.0)
	fissure = quad(back, Rect2(-100, 225, 840, 110), "fissure", {"size": Vector2(840, 110), "origin": (TIP.x + 100.0) / 840.0, "pal": RBMHeroFx.pal(["#05030a", "#3a0f33", "#a0132f", "#ed274c", "#ff9a88", "#ffc8bc"]), "seed": 4.5})
	jets_q = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.VOID, {"amp": 18., "k": .09, "seed": 6.1, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 26., "rim_mode": 1., "rim_w": 11.})
	# 切る線: 太い帯はボスと四人の後ろ、細い線はいちばん手前（誰も隠さずに、手前を切っているように見せる）
	var main_path := RBMHeroFx.bow(CUT_A, CUT_B, 0.0, 28)
	stroke_b = ribbon(back, RBMHeroFx.R_TEAR, {"body": .9, "taper": .32, "skew": 2.4, "rough": .6, "rough_freq": 26., "streak": .25, "gain": 1.15, "glow": .9, "glow_col": Vector3(.95, .08, .18), "seed": 2.0})
	stroke_b.set_path(main_path, 74.0)
	edge2 = ribbon(front, RBMHeroFx.R_DARK, {"body": .86, "taper": .85, "skew": .42, "rough": .55, "rough_freq": 12., "streak": .7, "glow": .9, "glow_col": Vector3(1., .08, .18), "seed": 3.0})
	edge = ribbon(front, ["#ed274c", "#ff9a88", "#ffefe8", "#ffffff", "#ffffff", "#ffffff"], {"body": .3, "taper": .9, "skew": .42, "streak": .3, "gain": 1.6, "glow": .5, "glow_col": Vector3(1., .4, .4), "seed": 6.0})
	stroke_f = ribbon(front, RBMHeroFx.R_TEAR, {"body": .15, "taper": .32, "skew": 2.4, "rough": .6, "rough_freq": 26., "streak": .25, "gain": 1.15, "glow": 0.0, "seed": 2.0})
	stroke_f.set_path(main_path, 74.0)
	stroke_c = ribbon(front, CORE_PAL, {"body": .3, "taper": .32, "skew": 2.4, "streak": .1, "gain": 2.0, "glow": .4, "glow_col": Vector3(1., .5, .5)})
	stroke_c.set_path(main_path, 18.0)
	b_front_add = batch(front)
	b_front_wall = batch(front, false)
	b_mix = batch(front, false)

func _step(t: float) -> void:
	for b: RBMHeroFxBatch in [b_sky, b_wall, b_wall_add, b_back, b_front_add, b_front_wall, b_mix]:
		b.reset()
	var D: float = T.drop
	var RU: float = T.rupture
	var CL: float = T.close
	var a := t - D
	var ar := t - RU
	var ac := t - CL
	view["dim"] = RBMHeroFx.key(t, [[0.0, .14], [.92, .36], [1.7, .62], [2.6, .78], [D, .82], [D + .3, .72], [RU + .2, .7], [CL + .3, .6], [5.04, .42], [6.17, .1]])
	view["dim_col"] = Color(.03, .01, .05)

	# 体の黒い炎（振り下ろしまで大きくなり続ける）
	var ap := RBMHeroFx.env(t, T.dock, 1.1, float(T.leap) - .12, float(T.leap) + .16)
	view["hero"]["dark_aura"] = RBMHeroFx.key(t, [[T.dock, 1.0], [T.edge, 1.3], [T.leap, 1.5], [T.strike, 1.85], [D, 2.2], [RU + .2, 2.2], [CL + .4, 1.7], [5.2, 1.2], [6.2, 1.0]])
	aura.visible = ap > .01
	if aura.visible:
		aura.position = foot + Vector2(-130, -236)
		sp(aura, {"power": .34 + .46 * ap, "flow": t * 2.6, "width": .18 + .1 * ap})
	embers(b_back, Rect2(foot.x - 90, foot.y - 30, 180, 34), t, 60, 2, 180.0, RBMHeroFx.C_RED, ap)
	# 三眼が灯り、光が腕へ戻る
	var dock := RBMHeroFx.env(t, T.dock, T.dock + .2, 1.0, 1.25)
	if dock > 0.0:
		var c := anchor("chest")
		for i in range(3):
			var p := c + Vector2(float(i - 1) * 8.0, 0.0)
			star(b_front_add, p, dock * .85, 6, 3 + i, 22.0, 4.0, [Color(RBMHeroFx.C_RED, 1.0), RBMHeroFx.C_WHITE])
		inward(b_front_add, anchor("tip"), t, 60, 5, 6.0, 170.0, 2.2, RBMHeroFx.C_RED, dock)

	# 刃の延長（黒い炎の刃が天へ伸びる）
	var grow := RBMHeroFx.ramp(t, T.edge, 2.1)
	var eo := RBMHeroFx.env(t, T.edge, T.edge + .1, T.edge_off - .01, T.edge_off + .03)
	edge.visible = eo > 0.0
	edge2.visible = eo > 0.0
	if eo > 0.0:
		var root := anchor("root")
		var tip := anchor("tip")
		var d := (tip - root).normalized()
		var length := 30.0 + 190.0 * grow
		var path := RBMHeroFx.bow(root, tip + d * length, 2.0 * sin(t * 6.0), 18)
		edge2.set_path(path, 26.0 + 14.0 * grow)
		edge.set_path(path, 20.0 + 7.0 * grow)
		sp(edge2, {"head": 1.0, "tail": 0.0, "flow": t * 7.0, "fade": eo})
		sp(edge, {"head": 1.0, "tail": 0.0, "flow": t * 9.0, "fade": eo})
		embers(b_front_add, Rect2(tip.x - 70, tip.y - 60, 140, 110), t, 60, 19, 200.0, RBMHeroFx.C_ROSE, grow * eo)

	# 断罪の線: 四人の頭上から一本ずつ降りる
	var sent: Array = T.sentence
	for i in range(4):
		var s := t - float(sent[i])
		var en := 1.0 - RBMHeroFx.ramp(a, -.02, .02)
		if s >= 0.0 and en > 0.0 and present[i]:
			# 前後に並ぶ二人の線が重ならないよう、列ごとに少しずらす
			var p: Vector2 = Vector2(targets[i]) + Vector2(-5.0 if i < 2 else 5.0, 0.0)
			var drop_len := RBMHeroFx.burst(s, 18.0)
			var bright := 1.0 - .5 * RBMHeroFx.ramp(s, .1, .4)
			var y_end := lerpf(-100.0, p.y, drop_len)
			var c := Color(RBMHeroFx.C_RED, bright * en)
			var glow_c := Color(RBMHeroFx.C_RED, .3 * bright * en)
			var glow_e := Color(RBMHeroFx.C_RED, .03 * bright * en)
			b_sky.quad(Vector2(p.x - 10.0, -100), Vector2(p.x + 10.0, -100), Vector2(p.x + 10.0, y_end), Vector2(p.x - 10.0, y_end), glow_c, glow_c, glow_e, glow_e)
			b_sky.quad(Vector2(p.x - 3.5, -100), Vector2(p.x + 3.5, -100), Vector2(p.x + 3.5, y_end), Vector2(p.x - 3.5, y_end), c, c, c, c)
			var wh := Color(1, 1, 1, bright * en)
			b_front_add.quad(Vector2(p.x - 1.0, -100), Vector2(p.x + 1.0, -100), Vector2(p.x + 1.0, y_end), Vector2(p.x - 1.0, y_end), wh, wh, wh, wh)
			if drop_len > .95:
				var w_mark := 16.0 + 26.0 * (1.0 - RBMHeroFx.ramp(s, .1, .34))
				b_sky.spike(p, Vector2.LEFT, w_mark, 5.0, c, Color(c, 0.0))
				b_sky.spike(p, Vector2.RIGHT, w_mark, 5.0, c, Color(c, 0.0))
			if s < .22:
				star(b_front_add, p + Vector2(0, -24), 1.0 - RBMHeroFx.ramp(s, .05, .22), 8, 40 + i, 46.0, 7.0, [Color(RBMHeroFx.C_RED, 1.0), RBMHeroFx.C_WHITE])

	_dive_trail(t)
	_main_cut(t, ar, ac)
	_party_hits(t)
	if a >= 0.0:
		_drop(a, t)
	else:
		fissure.visible = false
		jets_q.visible = false
	if ar >= 0.0:
		_rupture(ar, ac)
	else:
		blast.visible = false
		burst_r.visible = false
	var hits: Array = T.hits
	var events := []
	for i in range(4):
		events.append([hits[i], ORDER[i]])
		events.append([RU, i])
	ally_hits(t, events, 1.35)
	ally_launch(t, RU - .13, .96, 28.0, 19.0)
	var lit := RBMHeroFx.env(a, 0.0, .1, .5, .9) + RBMHeroFx.env(ar, 0.0, .1, .8, 1.6)
	ally_light(RBMHeroFx.sat(lit) * .9, RBMHeroFx.C_RED)
	for b: RBMHeroFxBatch in [b_sky, b_wall, b_wall_add, b_back, b_front_add, b_front_wall, b_mix]:
		b.commit()

## 急降下の軌跡（闇の裂け目）。
func _dive_trail(t: float) -> void:
	var S: float = T.strike
	var D: float = T.drop
	var ds := RBMHeroFx.env(t, S - .02, S + .06, D + .02, D + .16)
	trail.visible = ds > 0.0
	if ds > 0.0:
		sp(trail, {"head": 1.0 - .98 * RBMHeroFx.ramp(t, D - .05, D + .12), "tail": 1.0 - RBMHeroFx.ramp(t, S, D), "flow": t * 8.0, "fade": ds})

## 振り下ろしの線。振り下ろしたコマが出た瞬間に、線は端から端までつながり、画面も一度に大きくずれる。
func _main_cut(t: float, ar: float, ac: float) -> void:
	var S: float = T.strike
	var D: float = T.drop
	var on := t >= S and ac < .14
	stroke_b.visible = on and ac < 0.0
	stroke_f.visible = on and ac < 0.0
	stroke_c.visible = on
	if not on:
		return
	var u := 1.0
	var a := t - D
	var narrow := lerpf(1.0, .34, RBMHeroFx.ramp(a, .06, .4))
	var closing := 1.0 - RBMHeroFx.ramp(ac, -.08, .0)
	var body_k := narrow * closing
	if stroke_b.visible:
		sp(stroke_b, {"head": u, "tail": 0.0, "body": .9 * body_k, "flow": t * .5, "fade": 1.0})
		sp(stroke_f, {"head": u, "tail": 0.0, "body": .9 * FRONT_K * body_k, "flow": t * .5, "fade": 1.0})
	# 閉じた瞬間に線が一度だけ光って消える
	var core_body := .3 * maxf(body_k, .45) if ac < 0.0 else .3
	sp(stroke_c, {"head": u, "tail": 0.0, "body": core_body, "flow": t, "fade": 1.0 - RBMHeroFx.ramp(ac, .0, .14)})
	if ac >= 0.0:
		return
	var d := (CUT_B - CUT_A).normalized()
	set_post({"split_world": CUT_P, "split_dir": d, "split_amt": .15 * closing, "split_gap": .022 * closing, "split_col": Vector3(1., .86, .82), "split_head": 99.0})

## 着弾の炎と、四人への当たり（画面は切らない。小さな火花だけ）。
func _party_hits(t: float) -> void:
	var a := t - float(T.drop)
	hit_blast.visible = a >= 0.0 and a < .36
	if hit_blast.visible:
		var data := blobs(TIP, a, 12, 5, 170.0, 90.0, 46.0, 40.0, 1.0, 0.0, 10.0)
		show_blast(hit_blast, data, t, {"flow": t * .22, "cool": .06, "erode": RBMHeroFx.ramp(a, .1, .3), "fade": 1.0 - RBMHeroFx.ramp(a, .18, .34), "erode_noise": .4,
			"polar": 1.0, "detail": .6, "radial_heat": .3, "heat_center": w(TIP), "heat_radius": 240.0, "erode_radial": 160.0, "tone_cap": .64})
	var hits: Array = T.hits
	for i in range(4):
		var s := t - float(hits[i])
		if s >= 0.0 and present[ORDER[i]]:
			sparks(b_front_add, target_chest(ORDER[i]), s, .6, 40, 71 + i * 9, 520.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 200.0, 2.0)

func _drop(a: float, t: float) -> void:
	# 地を横断する亀裂
	var open_ := RBMHeroFx.burst(a, 5.0)
	var f := 1.0 - RBMHeroFx.ramp(a, 1.5, 2.3)
	fissure.visible = f > 0.0
	if fissure.visible:
		var wid := key_open(a)
		sp(fissure, {"head_l": (TIP.x + 100.0) / 840.0 * (1.0 - open_ * 1.1), "head_r": lerpf((TIP.x + 100.0) / 840.0, 1.1, open_), "open_w": wid, "flow": t, "fade": f, "glow": .9})
	# 亀裂に沿って黒い炎の柱が順に噴き上がり、破断で一度大きく燃え上がってから消える
	var ar := t - float(T.rupture)
	var jets: Array = T.jets
	var data := PackedVector4Array()
	var oldest := 1e9
	var surge := 1.0 + .35 * RBMHeroFx.env(ar, 0.0, .06, .2, .45) if ar >= 0.0 else 1.0
	var gone := 1.0 - RBMHeroFx.ramp(a, .9, 1.25)
	for i in range(jets.size()):
		var ja: float = a - float(jets[i][1])
		if ja <= 0.0 or gone <= 0.0:
			continue
		oldest = minf(oldest, ja)
		var grow := RBMHeroFx.burst(ja, 9.0)
		var h: float = JET_H[i] * grow * surge
		var base := Vector2(float(jets[i][0]), 282.0 + 3.0 * sin(float(i) * 1.7))
		# 炎の柱: 下から上へ玉を重ね、上ほど細く、てっぺんの玉は先に昇る
		for k in range(4):
			var u := (float(k) + .5) / 4.0
			var p := base + Vector2(sin(float(i) * 2.3 + float(k) * 1.1) * 6.0 * u, -h * u - ja * ja * 40.0 * u)
			var rad: float = JET_W[i] * (1.0 - .32 * u) * (.5 + .5 * grow) * gone
			data.append(Vector4(p.x - RBMHeroFx.WORLD.position.x, p.y - RBMHeroFx.WORLD.position.y, rad, clampf(1.0 - .3 * u - ja * .5, .05, 1.0)))
	jets_q.visible = not data.is_empty()
	if jets_q.visible:
		show_blast(jets_q, data, t, {"cool": RBMHeroFx.ramp(a, .7, 1.2) * .2, "erode": RBMHeroFx.ramp(a, .75, 1.2), "fade": gone, "erode_noise": .4, "hot_gain": 1.0 - RBMHeroFx.ramp(oldest, .1, .5), "tone_cap": .86})
	# 着弾
	refract_wave(TIP, a, .7, 560.0, 5.0, .03)
	refract_wave(TIP, a - .08, .6, 400.0, 5.4, .015)
	sparks(b_front_add, TIP, a, .95, 130, 31, 1150.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, -PI * .5, PI * 1.25, 250.0, 2.6)
	rocks(b_mix, TIP, a, 1.2, 28, 37, 760.0, 9.0)
	embers(b_front_add, Rect2(-20, 240, 680, 90), t, 200, 41, 240.0, RBMHeroFx.C_RED, RBMHeroFx.env(a, .1, .5, 2.2, 2.9), 2.4, 12.0)
	view["shake"] += hit_shake(a, 15.0, 74.0, .55)

func key_open(a: float) -> float:
	return RBMHeroFx.key(a, [[0.0, 2.0], [.16, 6.0], [.5, 9.0], [.57, 14.0], [.95, 10.0], [1.5, 5.0], [2.3, 2.5]])

func _rupture(a: float, ac: float) -> void:
	# パーティーの真ん中から黒紅の炎が噴き出す
	var rf := 1.0 - RBMHeroFx.ramp(a, .55, .95)
	burst_r.visible = rf > 0.0
	if burst_r.visible:
		var center := PARTY_C + Vector2(20, -10)
		var data := blobs(center, a, 48, 31, 470.0, 260.0, 104.0, 130.0, .62, 0.0, 6.2)
		show_blast(burst_r, data, a, {"flow": a * .12, "cool": .06 + RBMHeroFx.ramp(a, .2, 1.1) * .26, "erode": RBMHeroFx.ramp(a, .36, 1.02), "fade": rf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "heat_center": w(center), "heat_radius": 430.0 * RBMHeroFx.burst(a, 6.2), "erode_radial": 220.0, "tone_cap": .8})
	# 地表一面の爆炎
	var bf := 1.0 - RBMHeroFx.ramp(a, .55, 1.0)
	blast.visible = bf > 0.0
	if blast.visible:
		var data := PackedVector4Array()
		for i in range(6):
			var cx := -40.0 + float(i) * 150.0
			data.append_array(blobs(Vector2(cx, 278), maxf(a - absf(float(i) - 1.8) * .025, .0), 6, 10 + i * 3, 130.0, 44.0, 56.0, 56.0, .72, .3, 8.0))
		show_blast(blast, data, a, {"cool": RBMHeroFx.ramp(a, .3, 1.2) * .2, "erode": RBMHeroFx.ramp(a, .42, 1.2), "fade": bf, "lump_scale": .62, "hot_gain": 1.0 - RBMHeroFx.ramp(a, .05, .24), "erode_noise": .4, "tone_cap": .86})
	# 刃の列が砕ける
	shards(b_front_add, Vector2(200, 180), a, 1.15, 50, 51, 1200.0, 8.0, RBMHeroFx.C_RED, RBMHeroFx.C_CRIM, 220.0)
	shards(b_mix, Vector2(200, 200), a, 1.25, 56, 57, 1100.0, 11.0, Color("#3a0f33"), RBMHeroFx.C_VOID, 300.0)
	sparks(b_front_add, Vector2(200, 240), a, 1.25, 150, 61, 1500.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 200.0, 2.8)
	rocks(b_mix, Vector2(230, 280), a, 1.4, 32, 67, 960.0, 10.0)
	refract_wave(TIP, a, .9, 720.0, 4.4, .05)
	# 閉じた瞬間、線に沿って火花が散る
	refract_wave(TIP.lerp(CUT_A, .1), ac - .04, .7, 640.0, 5.2, .015)
	if ac >= 0.0 and ac < 1.0:
		for i in range(6):
			var p := CUT_B.lerp(CUT_A, .18 + float(i) * .13)
			sparks(b_front_add, p, ac, .7, 40, 501 + i * 7, 520.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 200.0, 2.2)
	view["shake"] += hit_shake(a, 20.0, 68.0, .9) + hit_shake(ac, 12.0, 90.0, .42)
