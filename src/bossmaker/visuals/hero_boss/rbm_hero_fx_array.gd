extends RBMHeroFxBase
## ② 覚醒前・全体「救難照射」: 体に沿う青い炎でめいっぱい溜め、両手から一本の巨大なビームを撃ち切る。玉や鏡は使わない。
## 溜めは三段階（体に炎→大地が応える→両手へ集める）、踏み出す直前に全部を引き込んでから発射する。
## ビームと爆光は mid の層（味方より前・ボスより後ろ）へ置いて、撃っている姿が見えるようにしている。

const T := RBMHeroFxTiming.ARRAY
const BURST := Vector2(178, 228)
## ビームの狙い。全体攻撃なのでほぼ真横に撃ち、太さで四人全員を包む。
const AIM := Vector2(175, 184)
## 最後の爆発の芯（ビームの中）
const CORE := Vector2(178, 188)
const BEAM_LEN := 900.0
const BEAM_HALF := 130.0
## 手元からビームの太さになるまでの長さ（経路に対する割合）
const ROOT_LEN := .17
## 両手を前へ伸ばしたまま照射を撃ち切るコマ
const PALM_POSE := "array_standing_palms"

var b_back: RBMHeroFxBatch
var b_rays: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_mid_mix: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var cracks_charge: ColorRect
var cracks: ColorRect
var blast: ColorRect
var beam_out: RBMHeroFxRibbon
var beam_main: RBMHeroFxRibbon
var beam_core: RBMHeroFxRibbon
var b_under: RBMHeroFxBatch
var ring_a: ColorRect
var ring_b: ColorRect

func _build() -> void:
	cracks_charge = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.A4_BLUE), "seed": 5.2, "squash": .32, "line_w": .038, "glow_col": Vector3(.3, .65, 1.), "glow": .2})
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.A4_AMBER), "seed": 2.4, "squash": .34, "line_w": .06, "glow_col": Vector3(1., .5, .15), "glow": .3})
	b_rays = batch(back)
	blast = blast_quad(back, RBMHeroFx.FIRE, RBMHeroFx.PLASMA, {"amp": 34., "k": .05, "seed": 4.4, "glow": .55, "glow_col": Vector3(1., .55, .18), "glow_r": 50.})
	b_back = batch(back)
	b_under = batch(mid, false)
	beam_out = ribbon(mid, RBMHeroFx.R_AMBER, {"root_len": ROOT_LEN, "taper": .34, "skew": .3, "rough": .32, "rough_freq": 20., "streak": .3, "glow": 1.0, "glow_col": Vector3(1., .5, .12), "seed": 1.0})
	beam_main = ribbon(mid, RBMHeroFx.R_BLUE, {"root_len": ROOT_LEN, "taper": .3, "skew": .3, "rough": .12, "streak": .3, "gain": 1.3, "glow": .8, "glow_col": Vector3(.35, .75, 1.), "seed": 2.0})
	beam_core = ribbon(mid, ["#9fe6ff", "#c8f4ff", "#e6fbff", "#ffffff", "#ffffff", "#ffffff"], {"root_len": ROOT_LEN, "taper": .3, "skew": .3, "streak": .1, "gain": 2.0, "glow": .5, "glow_col": Vector3(.7, .9, 1.), "seed": 3.0})
	ring_a = ring_quad(mid, RBMHeroFx.A4_BLUE, {"squash": .34, "breakup": .45, "seed": 1.0, "glow": .4, "glow_col": Vector3(.35, .7, 1.)})
	ring_b = ring_quad(mid, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .45, "seed": 3.7, "glow": .4, "glow_col": Vector3(1., .6, .2)})
	b_mid = batch(mid)
	b_mid_mix = batch(mid, false)
	b_front = batch(front)

func _step(t: float) -> void:
	for b: RBMHeroFxBatch in [b_back, b_rays, b_under, b_mid, b_mid_mix, b_front]:
		b.reset()
	var F: float = T.fire
	var E: float = T.final
	var CT: float = T.cut
	var f := t - F
	var a := t - E
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [.9, .25], [T.palms, .5], [T.pinch, .72], [F, .8], [F + .2, .62], [E, .62], [E + .3, .5], [5.2, .34], [T.end, 0.0]])
	view["dim_col"] = Color(.02, .04, .12)

	var chest := anchor("chest")
	var palm := anchor("tip") if pose == PALM_POSE else chest
	var focus := chest.lerp(palm, RBMHeroFx.ramp(t, T.palms, T.palms + .1))
	var s1 := RBMHeroFx.ramp(t, T.charge, T.stage2)
	var s2 := RBMHeroFx.ramp(t, T.stage2, T.palms)
	var s3 := RBMHeroFx.ramp(t, T.palms, T.pinch)
	var pinch := RBMHeroFx.ramp(t, T.pinch, F - .03)
	var after := RBMHeroFx.ramp(t, F, F + .2)

	# 体の炎: 三段階で膨らみ、発射の直前に引き込まれ、撃っている間は残る
	var aura_p := (.45 * s1 + .35 * s2 + .6 * s3) * (1.0 - .55 * pinch)
	view["hero"]["dark_aura"] = lerpf(aura_p, .85, after) * (1.0 - RBMHeroFx.ramp(t, CT, CT + .3))

	if t < F:
		_charge(t, focus, chest, s1, s2, s3, pinch)
		beam_out.visible = false
		beam_main.visible = false
		beam_core.visible = false
	else:
		_beam(t, f, palm)
	cracks_charge.visible = s2 > 0.0 and after < 1.0
	if cracks_charge.visible:
		sp(cracks_charge, {"center": w(foot + Vector2(0, 2)), "reveal": 30.0 + 100.0 * s2 + 120.0 * s3, "fade": 1.0 - after})

	# 両手を突き出した瞬間の圧
	var ps := t - float(T.palms)
	refract_wave(palm, ps, .6, 300.0, 5.0, .04)
	show_ring(ring_a, foot, ps, .5, 250.0, 6.0, 5.5)

	if a >= 0.0:
		_final(a)
	else:
		blast.visible = false
		cracks.visible = false
		ring_b.visible = false

	# 味方への命中
	var events := []
	var pulses: Array = T.pulses
	for j in range(4):
		events.append([pulses[j], j])
		events.append([E, j])
		var s: float = t - float(pulses[j])
		var dst := target_chest(j)
		if not present[j]:
			continue
		if s >= 0.0 and s < .3:
			star(b_mid, dst, RBMHeroFx.burst(s, 34.0) * (1.0 - RBMHeroFx.ramp(s, .08, .26)), 12, 33 + j, 70.0, 12.0, [Color(RBMHeroFx.C_BLUE, .9), RBMHeroFx.C_CYAN, RBMHeroFx.C_WHITE])
		sparks(b_mid, dst, s, .55, 46, 201 + j * 9, 460.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, TAU, 140.0, 2.0)
		sparks(b_mid, dst, s, .45, 26, 241 + j * 9, 360.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_ORANGE, 0.0, TAU, 120.0, 1.8)
	ally_hits(t, events, 1.0)
	ally_launch(t, E, .71, 24.0, 16.0)
	var beam_light := RBMHeroFx.env(t, F, F + .06, CT, CT + .2)
	var fire_light := RBMHeroFx.env(a, 0.0, .08, .6, 1.2)
	ally_light(maxf(beam_light * .7, fire_light), RBMHeroFx.C_GOLD if fire_light > beam_light * .7 else RBMHeroFx.C_PALE)
	# 溜めの間は体の輪郭を薄く光らせて、構えを際立たせる
	var rim := .6 * s3 * (1.0 - after)
	if rim > float(view["hero"].get("lit", 0.0)):
		view["hero"]["lit"] = rim
		view["hero"]["lit_col"] = RBMHeroFx.C_PALE
		view["hero"]["lit_side"] = 0.0
	if t < F:
		view["shake"] = Vector2(sin(t * 29.0), cos(t * 23.0) * .6) * (.35 * s2 + s3)
	else:
		view["shake"] = hit_shake(f, 12.0, 72.0, .5) + hit_shake(a, 15.0, 72.0, .85)
	for b: RBMHeroFxBatch in [b_back, b_rays, b_under, b_mid, b_mid_mix, b_front]:
		b.commit()

## 溜め。玉は作らず、光の線・放電・持ち上がる岩・地割れで「集まっている」ことを見せる。
func _charge(t: float, focus: Vector2, chest: Vector2, s1: float, s2: float, s3: float, pinch: float) -> void:
	inward(b_mid, focus, t, 60, 5, 12.0, 200.0, 2.2, RBMHeroFx.C_CYAN, s1 * (1.0 - s3 * .4))
	inward(b_mid, focus, t + .4, 36, 13, 10.0, 160.0, 1.8, RBMHeroFx.C_AMBER, s2 * (1.0 - s3 * .4))
	inward(b_mid, focus, t * 1.4, 110, 21, 10.0, 430.0, 2.8, RBMHeroFx.C_PALE, s3, 2.6)
	inward(b_mid, focus, t * 1.4 + .2, 60, 29, 10.0, 380.0, 2.2, RBMHeroFx.C_AMBER, s3, 2.4)
	inward(b_mid, focus, t * 2.2, 80, 37, 6.0, 300.0, 3.0, RBMHeroFx.C_WHITE, pinch, 5.0)
	# 放電（溜まるほど増える。発射の直前は手の先へ縮む）
	var sd := int(t * 10.0)
	var count := int(1.0 + s2 * 2.0 + s3 * 5.0)
	if s2 > 0.0:
		for i in range(count):
			var reach := (18.0 + 40.0 * RBMHeroFx.r(i, sd + 3)) * (1.0 - .8 * pinch)
			var from := focus + Vector2(RBMHeroFx.r(i, sd + 7) * 10.0 - 5.0, RBMHeroFx.r(i, sd + 9) * 12.0 - 6.0)
			arc(b_mid, from, from + Vector2.from_angle(RBMHeroFx.r(i, sd) * TAU) * reach, sd + i * 13, 1.0, Color(RBMHeroFx.C_CYAN, .75), RBMHeroFx.C_WHITE, 7, .2)
	# 地面の岩が持ち上がり、発射の直前に手へ吸い込まれる
	for i in range(20):
		var age: float = t - (float(T.stage2) + RBMHeroFx.r(i, 3) * 1.4)
		if age < 0.0:
			continue
		var base := Vector2(foot.x + (RBMHeroFx.r(i, 5) - .5) * 250.0, foot.y + 4.0 + RBMHeroFx.r(i, 7) * 24.0)
		var up := base + Vector2(0, -18.0 - 52.0 * RBMHeroFx.r(i, 9))
		var p := base.lerp(up, RBMHeroFx.ramp(age, 0.0, .9)) + Vector2(sin(t * 1.7 + float(i)) * 2.0, sin(t * 2.3 + float(i)) * 2.0)
		p = p.lerp(focus, pinch * pinch)
		b_mid_mix.shard(p, (2.5 + 4.0 * RBMHeroFx.r(i, 11)) * (1.0 - pinch * .8) * RBMHeroFx.ramp(age, 0.0, .15), t * 1.2 + float(i), i, Color("#6b6880"), Color("#2c2a3a"))
	embers(b_back, Rect2(foot.x - 90, foot.y - 34, 180, 34), t, 70, 3, 190.0, RBMHeroFx.C_PALE, s1 * (1.0 - pinch), 2.0)
	# 地面から立ち上る光（溜まるほど増えて高くなる）
	var rise_p := (s2 * .5 + s3 * .8) * (1.0 - pinch)
	if rise_p > 0.0:
		for i in range(36):
			var q := fmod(t * (.9 + .8 * RBMHeroFx.r(i, 51)) + RBMHeroFx.r(i, 53), 1.0)
			var x := foot.x + (RBMHeroFx.r(i, 55) - .5) * 2.0 * (60.0 + 70.0 * s3)
			var y0 := foot.y + 8.0 - q * (40.0 + 170.0 * RBMHeroFx.r(i, 57))
			var length := 14.0 + 40.0 * RBMHeroFx.r(i, 59)
			var c := Color(RBMHeroFx.C_PALE if i % 3 == 0 else RBMHeroFx.C_CYAN, .7 * sin(q * PI) * rise_p)
			b_back.streak(Vector2(x, y0 + length), Vector2(x, y0), 1.6, c, Color(c, 0.0))
	# 手の先の細い光（玉にしない）
	if s3 > 0.0:
		var glow_s := (.35 + .65 * s3) * (1.0 - .4 * pinch)
		b_front.streak(focus + Vector2(-46.0 * glow_s, 0), focus + Vector2(46.0 * glow_s, 0), 3.0, Color(RBMHeroFx.C_PALE, .85), Color(RBMHeroFx.C_PALE, .85))
		b_front.streak(focus + Vector2(0, -18.0 * glow_s), focus + Vector2(0, 18.0 * glow_s), 2.0, Color(RBMHeroFx.C_WHITE, .85), Color(RBMHeroFx.C_WHITE, .85))
	# 発射の直前、空気が手へ引き込まれる
	if pinch > 0.0:
		view["rings"].append(Vector4(focus.x, focus.y, lerpf(240.0, 8.0, pinch), .03 * pinch))
	var unused_chest := chest
	unused_chest = unused_chest

func _beam(t: float, f: float, palm: Vector2) -> void:
	var CT: float = T.cut
	var d := (AIM - palm).normalized()
	var nv := Vector2(-d.y, d.x)
	var path := RBMHeroFx.bow(palm, palm + d * BEAM_LEN, 0.0, 28)
	var head := RBMHeroFx.burst(f, 26.0)
	var grow := RBMHeroFx.ramp(f, 0.0, .1)
	var pulse := 0.0
	for p in T.pulses:
		pulse = maxf(pulse, RBMHeroFx.env(t - float(p), 0.0, .03, .06, .2))
	var climax := RBMHeroFx.env(t, float(T.final) - .06, float(T.final) + .02, CT - .06, CT + .02)
	var thin := 1.0 - RBMHeroFx.ramp(t, CT - .02, CT + .16)
	var k := (.35 + .65 * grow) * (1.0 + .08 * pulse + .18 * climax) * thin
	var fd := 1.0 - RBMHeroFx.ramp(t, CT + .04, CT + .2)
	var on := fd > 0.0
	for r: RBMHeroFxRibbon in [beam_out, beam_main, beam_core]:
		r.visible = on
	if not on:
		return
	beam_out.set_path(path, BEAM_HALF)
	beam_main.set_path(path, BEAM_HALF)
	beam_core.set_path(path, BEAM_HALF)
	sp(beam_out, {"head": head, "tail": 0.0, "body": .62 * k, "flow": t * 2.0, "fade": fd})
	sp(beam_main, {"head": head, "tail": 0.0, "body": .52 * k, "flow": t * 2.4, "fade": fd})
	sp(beam_core, {"head": head, "tail": 0.0, "body": .26 * k, "flow": t * 1.6, "fade": fd})
	# ビームの中を走る光の線
	var line_p := RBMHeroFx.ramp(f, .04, .16) * thin
	if line_p > .01:
		for i in range(16):
			var q := fmod(t * (1.6 + 1.2 * RBMHeroFx.r(i, 41)) + RBMHeroFx.r(i, 43), 1.0)
			var off := (RBMHeroFx.r(i, 45) - .5) * 124.0 * k * minf(q * 6.0, 1.0)
			var p0 := palm + d * q * 620.0 + nv * off
			var c := Color(RBMHeroFx.C_WHITE, .55 * sin(q * PI) * line_p)
			b_mid.streak(p0, p0 + d * (60.0 + 90.0 * RBMHeroFx.r(i, 47)), 2.0, c, Color(c, 0.0))
	# 銃口の光（手の奥）
	star(b_mid, palm, (.7 + .3 * pulse) * thin, 10, 31, 74.0, 13.0, [Color(RBMHeroFx.C_BLUE, .85), Color(RBMHeroFx.C_AMBER, .9), RBMHeroFx.C_PALE, RBMHeroFx.C_WHITE])
	# ビームの進行に沿って走る輪（発射と各命中で一つずつ）
	_travel_ring(palm, d, nv, f)
	for p in T.pulses:
		_travel_ring(palm, d, nv, t - float(p))
	# ビームの下で地面がめくれる
	for i in range(6):
		var x := lerpf(300.0, -10.0, float(i) / 5.0)
		var g := Vector2(x, 262.0 + float(i) * 2.0)
		rocks(b_under, g, f - float(i) * .05, .8, 6, 301 + i * 3, 300.0, 4.5)
		sparks(b_mid, g, f - float(i) * .05, .5, 22, 321 + i * 5, 320.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, -PI * .5, 1.3, 240.0, 1.8)

## ビームの進行方向に垂直な輪。
func _travel_ring(palm: Vector2, d: Vector2, nv: Vector2, age: float) -> void:
	var life := .5
	if age < 0.0 or age > life:
		return
	var u := age / life
	var along := 30.0 + 560.0 * (1.0 - exp(-age * 4.0))
	var r := 66.0 + 44.0 * u
	var o := palm + d * along
	var c := Color(RBMHeroFx.C_PALE, .75 * (1.0 - u))
	var prev := o + nv * r
	for i in range(1, 25):
		var th := float(i) / 24.0 * TAU
		var p := o + nv * cos(th) * r + d * sin(th) * r * .28
		b_mid.line(prev, p, 2.0, c, c)
		prev = p

## 最後の爆発: ビームが届いた所で画面全体の爆炎になる。
func _final(a: float) -> void:
	# 画面の端まで届く光の筋
	var ray := RBMHeroFx.env(a, 0.0, .08, .3, .9) * .7
	if ray > 0.0:
		for layer in range(2):
			var col: Color = RBMHeroFx.C_AMBER if layer == 0 else RBMHeroFx.C_PALE
			for i in range(14 - layer * 6):
				var th := float(i) / (14.0 - layer * 6.0) * TAU + (RBMHeroFx.r(i, 61 + layer) - .5) * .25
				var c := col
				c.a = .3 * ray
				b_rays.spike(BURST, Vector2.from_angle(th), (520.0 + 340.0 * RBMHeroFx.r(i, 67)) * RBMHeroFx.burst(a, 10.0), 46.0 - layer * 22.0, c, Color(col, 0.0))
	# 画面全体の爆炎
	var bf := 1.0 - RBMHeroFx.ramp(a, .55, .95)
	blast.visible = bf > 0.0
	if blast.visible:
		# 中心から外へ噴き出す炎（2026-11-09 採用）
		var center := BURST + Vector2(46, -30)
		var data := blobs(center, a, 48, 8, 460.0, 200.0, 104.0, 150.0, .62, 0.0, 6.2)
		show_blast(blast, data, a, {"flow": a * .22, "cool": RBMHeroFx.ramp(a, .2, 1.1) * .34, "erode": RBMHeroFx.ramp(a, .36, 1.02), "fade": bf, "lump_scale": .62, "tone_cap": .74, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "heat_center": w(center), "heat_radius": 430.0 * RBMHeroFx.burst(a, 6.2), "erode_radial": 220.0})
	# 地割れ
	var cf := 1.0 - RBMHeroFx.ramp(a, .7, 1.25)
	cracks.visible = cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(BURST + Vector2(0, 34)), "reveal": 460.0 * RBMHeroFx.burst(a, 5.0), "fade": cf})
	show_ring(ring_b, BURST + Vector2(0, 30), a, .6, 560.0, 9.0, 4.8, .02)
	# 核の棘
	star(b_mid, CORE, RBMHeroFx.burst(a, 30.0) * (1.0 - RBMHeroFx.ramp(a, .06, .3)), 20, 71, 330.0, 44.0, [Color(RBMHeroFx.C_ORANGE, .9), RBMHeroFx.C_GOLD, RBMHeroFx.C_HOT, RBMHeroFx.C_WHITE])
	# 破片・火花
	sparks(b_mid, CORE, a, 1.2, 130, 81, 1300.0, RBMHeroFx.C_GOLD, RBMHeroFx.C_ORANGE, 0.0, TAU, 240.0, 2.8)
	sparks(b_mid, CORE, a, 1.0, 90, 87, 1120.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, TAU, 200.0, 2.4)
	shards(b_mid, BURST, a, 1.1, 12, 91, 700.0, 10.0, RBMHeroFx.C_PALE, RBMHeroFx.C_BLUE, 280.0)
	rocks(b_mid_mix, BURST + Vector2(0, 26), a, 1.25, 10, 95, 780.0, 9.0)
	var s_power := RBMHeroFx.env(a, .6, .9, 1.3, 1.9)
	embers(b_front, Rect2(-20, 150, 680, 180), a, 150, 99, 240.0, RBMHeroFx.C_AMBER, s_power, 2.4, 20.0)
