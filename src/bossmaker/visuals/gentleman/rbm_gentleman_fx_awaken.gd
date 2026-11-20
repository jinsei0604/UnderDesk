extends RBMGentlemanFxBase
## 異形紳士の覚醒「異形の目覚め」（2026-11-20 作り直し。前の版は暗くなってお辞儀・正体・帽子だけで約12秒、派手さがなかった）。
## 2026-11-20 ユーザー「覚醒モーションの派手さがまったくないから、他のボスと同じくらい派手に豪華なように」。
## 意味: 帽子に手をやり、深くお辞儀をする → 足元の石畳が割れて深紅の光が漏れ、黒い墨が広がり、闇に赤い目が開き、鐘が鳴る
## → 体を起こして両腕を広げる（顔の無い正体）: 足元から闇の柱が噴き上がり、衝撃の輪・裂け目・花びらが散る
## → 黒い墨の帯が体のまわりを巡り、花びらが渦を巻いて上り、背後に墨の煙が湧く → 帽子をかぶり直すと、全部が体へ吸い込まれる
## → 二丁の銃を広げて構えた瞬間（覚醒）、深紅の墨の爆発・二重の衝撃の輪・花びらの爆発 → 覚醒後の黒い靄をまとって立つ。

const T := {"lift": 0.25, "bow": 0.55, "bow_mid": 0.8, "bow_deep": 1.05, "rise": 2.45, "reveal": 2.7, "swirl_end": 4.05, "hat": 4.05, "awaken": 4.5, "lower": 5.5, "end": 6.2}
## 正体が現れた時に開く裂け目（足元からの位置）
const RIFTS := [Vector2(-46, -70), Vector2(40, -86), Vector2(-28, -116), Vector2(52, -40)]
const EYES := [Vector2(300, 120), Vector2(340, 104), Vector2(452, 112), Vector2(500, 140), Vector2(560, 120), Vector2(600, 170), Vector2(270, 168), Vector2(520, 200), Vector2(430, 92), Vector2(610, 250)]

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var cracks: ColorRect
var pool: ColorRect
var pillar: ColorRect
var smoke: ColorRect
var blast: ColorRect
var rings: Array = []
var swirls: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.awaken

func pose_keys() -> Array:
	return [[0.0, "hat_reach_00"], [T.lift, "hat_reach_15"], [T.bow, "bow_down_04"], [T.bow_mid, "bow_down_08"], [T.bow_deep, "bow_down_15"],
		[T.rise, "bow_up_08"], [T.reveal, "legacy_reveal"], [T.hat, "legacy_hat_replace"], [T.awaken - 0.12, "dual_open_raise_07"], [T.awaken, "dual_open_raise_15"],
		[T.lower, "dual_open_raise_07"], [T.lower + 0.25, "dual_open_raise_00"]]

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	pool = quad(back, RBMHeroFx.WORLD, "pool", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#020105", "#0a0410", "#2a0816", "#7a1026", "#ff5a6a"]), "seed": 3.3, "squash": .3})
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120308", "#7a1026", "#ff5a6a", "#fff0f2"]), "seed": 8.2, "squash": .32, "line_w": .05, "glow_col": Vector3(1., .2, .3), "glow": .6})
	smoke = blast_quad(back, INK_SMOKE, INK_SMOKE, {"amp": 22., "k": .07, "seed": 2.4, "glow": .25, "glow_col": Vector3(.6, .05, .12), "glow_r": 30.})
	pillar = quad(back, Rect2(0, -100, 120, 400), "pillar", {"pal": RBMHeroFx.pal(DARK_PILLAR), "seed": 6.1, "glow_col": Vector3(1., .15, .25), "glow": .8})
	b_mid = batch(mid, false)
	for i in range(3):
		swirls.append(ribbon(front, ["#1a0612", "#0a0410", "#05020a", "#3a0a1c", "#c22a44", "#ff8a96"], {"body": .7, "taper": .5, "skew": .7, "rough": .5, "rough_freq": 14., "streak": .5, "gain": 1.05, "glow": .3, "glow_col": Vector3(1., .15, .25), "seed": 2.0 + i * 3.0}))
	blast = blast_quad(back, CRIMSON_INK, INK_SMOKE, {"amp": 26., "k": .06, "seed": 4.4, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 44.})
	for i in range(4):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i % 2 == 0 else RBMHeroFx.A4_DARK, {"squash": .34, "breakup": .5, "seed": 1.0 + i * 1.9, "glow": .5, "glow_col": Vector3(.95, .15, .25)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var f := foot
	var ch := chest()
	var r1 := t - T.reveal
	var a := t - T.awaken
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.bow_deep, 0.55], [T.reveal - 0.05, 0.68], [T.reveal + 0.05, 0.4], [T.hat, 0.62], [T.awaken + 0.05, 0.35], [T.end - 0.4, 0.12], [T.end, 0.0]])
	view["dim_col"] = Color(0.05, 0.0, 0.02)
	set_post({"vig": 0.15 + 0.45 * RBMHeroFx.env(t, T.lift, T.bow_deep, T.awaken, T.end), "vig_col": Vector3(.2, .0, .04), "vig_r": .28})
	# お辞儀の間: 足元に黒い墨が広がり、石畳が割れて深紅の光が漏れる（正体で大きく割れる）
	var spread := RBMHeroFx.ramp(t, T.bow_mid, T.rise) * 0.6 + 0.4 * RBMHeroFx.burst(maxf(r1, 0.0), 6.0) * (1.0 if r1 >= 0.0 else 0.0)
	var pool_fade := 1.0 - RBMHeroFx.ramp(t, T.awaken + 0.4, T.end - 0.2)
	pool.visible = spread > 0.01 and pool_fade > 0.0
	if pool.visible:
		sp(pool, {"center": w(f + Vector2(0, 1)), "radius": 10.0 + 46.0 * spread, "flow": t * 0.5, "fade": pool_fade})
	cracks.visible = t >= T.bow_deep and pool_fade > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(f + Vector2(0, 1)), "reveal": 12.0 + 36.0 * RBMHeroFx.ramp(t, T.bow_deep, T.rise) + 70.0 * (RBMHeroFx.burst(r1, 7.0) if r1 >= 0.0 else 0.0), "fade": pool_fade,
			"glow": 0.4 + 0.4 * RBMHeroFx.env(t, T.reveal, T.reveal + 0.05, T.reveal + 0.3, T.reveal + 1.0)})
	# 割れ目から立ちのぼる深紅の光の粒
	embers(b_back_add, Rect2(f.x - 40, f.y - 50, 80, 50), t, 30, 11, 46.0, Color(RED, 1.0), RBMHeroFx.env(t, T.bow_deep, T.bow_deep + 0.4, T.awaken, T.awaken + 0.6), 1.5, 8.0)
	# 闇に赤い目が開く（お辞儀の間に1つずつ）→ 覚醒の瞬間に閉じる
	for i in range(EYES.size()):
		var open := RBMHeroFx.env(t, T.bow_deep + 0.12 * i, T.bow_deep + 0.12 * i + 0.15, T.awaken - 0.05, T.awaken + 0.1)
		eyes(b_add, EYES[i], open * (0.6 + 0.4 * absf(sin(t * 2.5 + i))), 1.0 + 0.3 * (i % 3))
	# 正体: 足元から闇の柱が噴き上がる
	var pf := RBMHeroFx.env(r1, 0.0, 0.08, 0.9, 1.4) if r1 >= 0.0 else 0.0
	pillar.visible = pf > 0.0
	if pillar.visible:
		pillar.position = Vector2(f.x - 60, -100)
		pillar.size = Vector2(120, f.y + 104)
		sp(pillar, {"width": lerpf(.08, .6, RBMHeroFx.burst(r1, 10.0)) * (1.0 - .45 * RBMHeroFx.ramp(r1, .5, 1.4)), "flow": t * 2.6, "fade": pf, "flare": .8})
	if r1 >= 0.0:
		show_ring(rings[0], f + Vector2(0, -2), r1, 0.7, 180.0, 7.0, 5.5, 0.025)
		refract_wave(ch, r1, 0.6, 260.0, 5.0, 0.03)
		sparks(b_add, ch, r1, 0.8, 90, 21, 520.0, PALE, RED, -PI * 0.5, PI * 1.6, 220.0, 2.0)
		view["shake"] += hit_shake(r1, 9.0, 80.0, 0.45)
		set_post({"flash": 0.14 * (1.0 - RBMHeroFx.ramp(r1, 0.0, 0.1))})
		view["hero"]["flash"] = 0.6 * (1.0 - RBMHeroFx.ramp(r1, 0.0, 0.18))
		view["hero"]["flash_col"] = ROSE
	# 正体が現れると、まわりの空間に裂け目が開く（帽子をかぶり直すと閉じる）
	for i in range(RIFTS.size()):
		var open := RBMHeroFx.env(t, T.reveal + 0.06 * i, T.reveal + 0.2 + 0.06 * i, T.hat + 0.1, T.awaken)
		rift(b_mid, b_add, f + RIFTS[i], open, 11.0, t, 30 + i)
	# 黒い墨の帯が体のまわりを巡る（速く → 帽子で吸い込まれる）
	var swirl := RBMHeroFx.env(t, T.reveal + 0.1, T.reveal + 0.4, T.hat, T.awaken)
	var pull := RBMHeroFx.ramp(t, T.hat, T.awaken)
	for i in range(swirls.size()):
		var r: RBMHeroFxRibbon = swirls[i]
		r.visible = swirl > 0.01
		if not r.visible:
			continue
		var spin := (t - T.reveal) * (5.0 + 2.0 * pull) + float(i) * TAU / 3.0
		var rad := Vector2(30.0 - 4.0 * i, 9.0 + 2.0 * i) * (1.0 - 0.75 * pull)
		var cy := -10.0 - 22.0 * float(i)
		var pts := PackedVector2Array()
		for k in range(22):
			var ang := spin + 2.6 * float(k) / 21.0
			pts.append(f + Vector2(cos(ang) * rad.x, cy + sin(ang) * rad.y))
		r.set_path(pts, 3.4)
		sp(r, {"head": 1.0, "tail": 0.0, "flow": t * 2.0, "fade": 0.9 * swirl})
	# 背後に墨の煙が湧く
	var sm := RBMHeroFx.env(t, T.reveal + 0.1, T.reveal + 0.5, T.hat, T.awaken + 0.1)
	smoke.visible = sm > 0.0
	if smoke.visible:
		show_blast(smoke, blobs(f + Vector2(0, -40), t - T.reveal + 0.6, 14, 19, 60.0, 50.0, 26.0, 60.0, .2, .5, 3.0), t - T.reveal, {"flow": t * .4, "cool": .6, "erode": 1.0 - sm, "fade": sm * 0.6, "erode_noise": .6, "detail": .6, "amp": 22.0, "tone_cap": .7})
	# 花びらが渦を巻いて上る
	var spiral := RBMHeroFx.env(t, T.reveal + 0.05, T.reveal + 0.3, T.hat - 0.1, T.hat + 0.2)
	if spiral > 0.0:
		for i in range(40):
			var q := fmod((t - T.reveal) * (0.5 + 0.3 * RBMHeroFx.r(i, 81)) + RBMHeroFx.r(i, 82), 1.0)
			var ang := (t - T.reveal) * 4.0 + RBMHeroFx.r(i, 83) * TAU + q * 5.0
			var p := f + Vector2(cos(ang) * (18.0 + 26.0 * q), -8.0 - 110.0 * q + sin(ang) * 6.0)
			var col := RED.lerp(Color("#7a1026"), RBMHeroFx.r(i, 84) * 0.6)
			b_front.dot_px(p, 2.0, Color(col, spiral * sin(q * PI)))
			if absf(sin(t * 8.0 + i)) > 0.6:
				b_front.dot_px(p + Vector2(2, 0), 1.0, Color(ROSE, spiral * sin(q * PI) * 0.8))
	# 帽子をかぶり直す: 光の線が体へ集まる
	inward(b_add, ch, t - T.hat, 26, 91, 110.0, 6.0, 1.4, Color(ROSE, 1.0), RBMHeroFx.env(t, T.hat, T.hat + 0.1, T.awaken - 0.05, T.awaken), 2.4)
	view["hero"]["lit"] = maxf(float(view["hero"].get("lit", 0.0)), 0.6 * RBMHeroFx.env(t, T.hat, T.awaken - 0.1, T.awaken + 0.2, T.end))
	view["hero"]["lit_col"] = RED
	# 覚醒: 二丁を広げた瞬間の深紅の墨の爆発・二重の衝撃の輪・花びらの爆発
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.45, 1.05)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var c := ch + Vector2(0, -4)
		show_blast(blast, blobs(c, a, 26, 47, 120.0, 90.0, 40.0, 60.0, .5, .4, 8.0), a, {"flow": a * .3, "cool": .02 + RBMHeroFx.ramp(a, .2, 1.0) * .14, "erode": RBMHeroFx.ramp(a, .2, .95), "fade": bfin, "erode_noise": .5,
			"polar": 1.0, "detail": .7, "amp": 26.0, "radial_heat": .4, "heat_center": w(c), "heat_radius": 180.0 * RBMHeroFx.burst(a, 7.0), "erode_radial": 110.0, "tone_cap": 1.0})
	if a >= 0.0:
		show_ring(rings[1], f + Vector2(0, -4), a, 0.8, 300.0, 9.0, 5.0, 0.03)
		show_ring(rings[2], f + Vector2(0, -4), a - 0.08, 0.8, 240.0, 6.0, 5.0, 0.0)
		show_ring(rings[3], ch, a - 0.04, 0.6, 160.0, 5.0, 6.0, 0.0)
		refract_wave(ch, a, 0.8, 420.0, 4.6, 0.04)
		sparks(b_add, ch, a, 1.1, 170, 61, 820.0, PALE, RED, 0.0, TAU, 160.0, 2.2)
		view["shake"] += hit_shake(a, 14.0, 70.0, 0.6)
		set_post({"flash": 0.2 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), "chroma": 0.006 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3))})
		view["hero"]["flash"] = maxf(float(view["hero"].get("flash", 0.0)), 0.7 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2)))
		view["hero"]["flash_col"] = PALE
	petals(b_front, ch, a, 2.3, 80, 71, 280.0, 1.0, 0.5)
	petals(b_front, ch, r1, 1.6, 36, 73, 170.0, 1.0, 0.4)
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()
