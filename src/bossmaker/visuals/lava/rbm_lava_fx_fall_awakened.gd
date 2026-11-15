extends "res://src/bossmaker/visuals/lava/rbm_lava_fx_fall.gd"
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/post_defeat.gd でユーザーが採用した内容をそのまま移した。
## 噴界炉の巨神・撃破（2026-11-14 試作。覚醒後は覚醒前より派手に＝聖獣の時のユーザーの指摘）。
## 構えが崩れた姿（覚醒後全体の4枚目）→ 体の中の熱が暴れ出す（照りが速く脈打つ・足元に火口が開く・割れ目から溶岩が噴く・オーラが乱れて燃え上がる・揺れが強まる）
## → 最後の大噴火: 巨神の体から天まで噴火の柱が上がり、溶岩の大爆発（閃光・衝撃の輪・溶岩の塊が四方へ）。オーラが散る
## → 柱の中で巨神が上から四角い粒でほどける → 噴火が止まり、柱が地面から離れて天へ抜けていく → 灰と溶岩の塊が降る中、冷えていく火口の上に岩の山が残る（割れ目の残り火が消える）。
## 2026-11-15 ユーザー「炎の柱が変に見切れていて違和感・質の低さが目立つ」: ①伸び始めの柱が上下とも平らな箱に見えた → 出始めから高く・頭は丸く（round_top）
## ②根元が真横の一直線で切れていた → 根元の下端を火口の手前の縁に沿わせる（soft_base）③衝撃の輪の奥側が柱を横切って輪切りに見えた → 輪を柱の後ろへ
## ④出始めの爆炎の中が暗い穴に見えた → 爆炎は少し育った所から・熱のゆがみの輪（柱を横切る横線・根元の渦）はやめた ⑤最後に柱が細く薄くなって四角い幽霊のように残った → 下端から浮き上がって上へ抜ける（lift）

const TP := {"surge": 0.30, "erupt": 1.80, "gone": 2.95, "end": 5.20}

var caldera: ColorRect
var column: ColorRect
var blast: ColorRect
var smoke_big: ColorRect
var spurts: Array = []
var rings: Array = []

func duration() -> float:
	return TP.end

func impact() -> float:
	return TP.erupt

func stops() -> Array:
	return [[TP.erupt, 0.12]]

func extra_poses() -> Dictionary:
	return {POSE: ["post_all", 4]}

func _build() -> void:
	b_back = batch(back, false)
	caldera = caldera_quad(back, {"seed": 5.0})
	steam = blast_quad(back, SMOKE, SMOKE, {"amp": 18., "k": .07, "seed": 3.9, "glow": 0.0, "glow_r": 16.})
	for i in range(4):
		spurts.append(eruption_quad(back, {"seed": 20.0 + i, "smoke": 0.4}))
	blast = blast_quad(back, LAVA, LAVA, {"amp": 42., "k": .045, "seed": 6.1, "glow": .9, "glow_col": Vector3(1., .5, .15), "glow_r": 60.})
	blast.set_meta("blast_reach", Vector3.ZERO)
	smoke_big = blast_quad(back, SMOKE, SMOKE, {"amp": 30., "k": .05, "seed": 6.8, "glow": 0.0, "glow_r": 20.})
	column = eruption_quad(front, {"seed": 4.0, "smoke": 0.55})
	for i in range(3):
		rings.append(ring_quad(back, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 4.0 + i * 2.5, "glow": .4, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var ae := t - TP.erupt
	var su := RBMHeroFx.ramp(t, TP.surge, TP.erupt)
	var ground := HOME + Vector2(2, 4)
	var beat := 0.5 + 0.5 * sin(t * (6.0 + 20.0 * su * su))
	view["hero"]["flash"] = 0.7 * (1.0 - RBMHeroFx.ramp(t, 0.0, 0.3))
	view["hero"]["flash_col"] = WHITE
	# 体の中の熱が暴れ出す
	view["hero"]["lit"] = (0.3 + 0.6 * su * beat) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.1))
	view["hero"]["lit_col"] = HOT if beat > 0.6 else ORANGE
	view["hero"]["sun_aura"] = (1.0 + 1.6 * su * (0.7 + 0.3 * beat)) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.5))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.2], [TP.erupt - 0.05, 0.7], [float(TP.erupt) + 0.05, 0.15], [TP.gone, 0.4], [TP.end, 0.2]])
	view["dim_col"] = Color(0.05, 0.01, 0.0)
	var tr := su * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.05))
	body["off"] = Vector2(roundf(sin(t * (30.0 + 30.0 * su)) * (1.0 + 2.0 * su * su)) * float(tr > 0.05), 0.0)
	view["shake"] += Vector2(sin(t * 33.0), cos(t * 27.0) * 0.6) * (0.5 + 2.5 * su * su) * float(ae < 0.0)
	embers(b_add, Rect2(HOME.x - 70, HOME.y - 110, 140, 110), t, 40, 9, 90.0, EMBER, su * float(ae < 0.0), 2.0, 6.0)
	# 足元に火口が開く（噴火の後は冷えていく）
	var open := RBMHeroFx.ramp(t, TP.surge + 0.3, TP.erupt)
	var cool := RBMHeroFx.ramp(ae, 0.8, 2.8)
	show_caldera(caldera, ground, 100.0 * (0.8 + 0.2 * open), {"squash": 0.28, "open": open, "heat": clampf((0.6 + 0.5 * beat * su) * open * (1.0 - 0.75 * cool), 0.0, 1.2), "flow": t, "fade": 1.0})
	# 割れ目から溶岩が噴く（だんだん高く）
	for i in range(4):
		var ang := -PI + (float(i) + 0.5) / 4.0 * PI
		var sp_pos := ground + Vector2(cos(ang) * 70.0, sin(ang) * 70.0 * 0.28 + 2.0)
		var st := t - (float(TP.surge) + 0.5 + i * 0.15)
		var sg := RBMHeroFx.ramp(st, 0.0, 0.15) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.3))
		show_eruption(spurts[i], sp_pos, 8.0, 30.0 + 40.0 * su + 10.0 * sin(t * 7.0 + i), sg, {"flow": t + i, "heat": 1.0})
	if ae < 0.0 and su > 0.3:
		inward(b_add, at_seq("post_all", 4, "center"), t, 70, 15, 8.0, 200.0, 2.0, HOT, RBMHeroFx.ramp(t, TP.erupt - 0.6, TP.erupt), 2.4)
	# 最後の大噴火: 体から天まで噴火の柱 → 崩れる
	# 出始めから画面の上まで届く高さ（低い柱を見せない）。根元は火口の内側に収める（flare 0.45: 火口の手前の縁が柱の前に見える）→ 噴火が止まると下端が浮き上がって上へ抜ける
	var cg := 0.55 + 0.45 * RBMHeroFx.ramp(ae, 0.0, 0.1)
	var cdown := RBMHeroFx.ramp(ae, 1.05, 1.75)
	if ae >= 0.0 and cdown < 1.0:
		show_eruption(column, ground + Vector2(0, 2), 56.0 * (1.0 - 0.2 * cdown), 420.0, cg, {"flow": t * 1.2, "heat": 1.0 - 0.3 * cdown, "smoke": 0.5 + 0.3 * cdown, "fade": 1.0 - RBMHeroFx.ramp(cdown, 0.8, 1.0),
			"round_top": 1.0, "soft_base": 1.0, "flare": 0.45, "lift": 470.0 * cdown * cdown})
	else:
		column.visible = false
	if ae >= 0.0:
		if ae < 0.12:
			set_post({"flash": 0.3 * (1.0 - ae / 0.12), "flash_col": Vector3(1.0, 0.85, 0.6)})
		lava_drops(b_front, ground + Vector2(0, -80), ae, 1.4, 50, 31, 620.0, 3.6, -PI * 0.5, PI * 1.5, 420.0)
		rocks(b_front, ground, ae, 1.3, 26, 33, 700.0, 7.0, 16.0)
		for k in range(12):
			var to := Vector2(30 + k * 52 + RBMHeroFx.r(k, 61) * 30.0, 170 + RBMHeroFx.r(k, 62) * 110.0)
			var bt := ae - 0.15 - k * 0.07
			lava_bomb(b_front, b_add, ground + Vector2(0, -220), to, bt, 0.8, 3.0 + RBMHeroFx.r(k, 63) * 2.5, 50.0)
			if bt >= 0.8 and bt < 1.2:
				lava_drops(b_front, to, bt - 0.8, 0.4, 8, 71 + k, 160.0, 2.0, -PI * 0.5, PI * 1.1, 360.0)
				view["shake"] += hit_shake(bt - 0.8, 2.5, 70.0, 0.15)
	view["shake"] += hit_shake(ae, 22.0, 55.0, 0.9)
	var bf := 1.0 - RBMHeroFx.ramp(ae, 0.4, 0.9)
	blast.visible = ae >= 0.0 and bf > 0.0
	if blast.visible:
		var c := ground + Vector2(0, -40)
		# 少し育った所から出す（出始めは熱い所が小さく、爆炎の中が暗い穴に見えた）
		var ba := ae + 0.1
		show_blast(blast, blobs(c, ba, 34, 31, 320.0, 140.0, 80.0, 120.0, .6, 0.0, 6.6), ba, {"flow": ba * .22, "cool": .05 + RBMHeroFx.ramp(ba, .2, 1.0) * .25, "erode": RBMHeroFx.ramp(ba, .3, .9), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .42, "heat_center": w(c), "heat_radius": 360.0 * RBMHeroFx.burst(ba, 6.6), "erode_radial": 200.0, "tone_cap": .95})
		# 熱のゆがみ（refract_wave）は使わない: 出始めは柱の根元に渦の印、広がると奥側の縁が柱を横切る横線に見えた
	for i in range(3):
		var ra := ae - i * 0.09
		if ra >= 0.03:
			show_ring(rings[i], ground, ra + 0.05, 0.8, 600.0 - i * 120.0, 9.0 - i * 2.0, 5.0, 0.035 * float(i == 0))
		else:
			(rings[i] as ColorRect).visible = false
	# 柱の中で上から四角い粒でほどける（縁は白熱）→ 岩の山が残る
	body["dissolve"] = smoothstep(TP.erupt, TP.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(HOT, 0.95)
	body["shadow"] = 1.0 - body["dissolve"]
	rock_pile(b_front, b_add, t, float(TP.erupt) + 0.6, float(TP.gone) + 0.5, 1.0 - RBMHeroFx.ramp(t, float(TP.gone) + 0.6, TP.end - 0.3), 100.0)
	var mf := 1.0 - RBMHeroFx.ramp(ae, 1.4, 2.8)
	smoke_big.visible = ae >= 0.4 and mf > 0.0
	if smoke_big.visible:
		show_blast(smoke_big, blobs(HOME + Vector2(0, -170), ae - 0.4, 24, 37, 300.0, 80.0, 56.0, 120.0, .2, 0.0, 2.4), ae - 0.4, {"flow": t * .15, "cool": 0.0, "erode": RBMHeroFx.ramp(ae, 1.4, 2.8), "fade": mf * 0.6, "erode_noise": .6, "tone_cap": .6})
	# 湯気（冷えていく火口から）
	var sa := ae - 1.2
	var sf := 1.0 - RBMHeroFx.ramp(t, TP.end - 1.0, TP.end)
	steam.visible = sa >= 0.0 and sf > 0.0
	if steam.visible:
		show_blast(steam, blobs(HOME + Vector2(0, -30.0 - sa * 8.0), sa * 0.3, 16, 19, 70.0, 34.0, 20.0, 70.0, .1, 0.0, 2.0), sa, {"flow": sa * .15, "cool": 0.0, "erode": 0.0, "fade": sf * RBMHeroFx.ramp(sa, 0.0, 0.6) * 0.45, "erode_noise": .6, "tone_cap": .6})
	embers(b_add, Rect2(-20, 40, 680, 300), t, 120, 47, -60.0, Color(0.55, 0.5, 0.48), RBMHeroFx.env(ae, 0.6, 1.2, 3.0, 3.4) * 0.8, 2.0, 18.0)
	embers(b_add, Rect2(-20, 100, 680, 250), t, 100, 49, 200.0, ORANGE, RBMHeroFx.env(ae, 0.3, 0.6, 2.0, 2.6), 2.2, 16.0)
	set_post({"vig": 0.3 * su + 0.12, "vig_col": Vector3(.06, .01, .0), "vig_r": .28})
	b_back.commit(); b_add.commit(); b_front.commit()
