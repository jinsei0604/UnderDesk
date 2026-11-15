extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/awaken.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人 → 噴界炉の巨神「噴界の覚醒」（2026-11-14 作り直し2。指摘「下から出てくるマグマが集合体すぎて気持ち悪い・ヒーローや聖獣に明らかに劣る」
## → 網目の模様を使わず、聖獣の覚醒と同じ格の流れに。絵が変わる所は見せない）:
## 地面が震え、炉が熱を帯びる → 闇が落ち、巨人は影になって炉の口と目だけが光る（機械武者の目と同じ光り方）
## → 鼓動のたびに足元の地面が下から赤く脈打つ → 地面が割れて火口が開き、中で溶岩が渦を巻いてせり上がる（周りに黒煙・火の粉）
## → 巨大な噴火の柱が巨人ごと天まで噴き上がる（ここで絵が変わる。白い閃光・衝撃波・溶岩の塊が四方へ）
## → 柱が崩れ、溶岩の色のオーラをまとった覚醒後の姿が火口の光の中に立つ → 灰と火の粉が降る。

const T := {"curl": 0.45, "dark": 0.90, "beats": [1.40, 1.90, 2.35, 2.75], "caldera": 2.45, "rise": 3.30, "erupt": 3.95, "reveal": 4.75, "done": 4.85, "end": 7.30}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
## 構え（2枚目）の目（兜の穴）と炉の口（絵の画素）
const EYES := [Vector2(157, 90), Vector2(164, 90)]
const MOUTH := Vector2(164, 112)
const CALDERA_R := 120.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var caldera: ColorRect
var column: ColorRect
var spurts: Array = []
var smoke_col: ColorRect
var blast: ColorRect
var smoke_big: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.done

func stops() -> Array:
	return [[T.erupt, 0.12]]

## 絵が変わる（2 → 4 → 5）のは、噴火の柱の中で見えない間だけ
func pose_keys() -> Array:
	return [[0.0, 1], [T.curl, 2], [float(T.erupt) + 0.1, 4], [float(T.reveal) - 0.15, 5]]

func _build() -> void:
	b_back = batch(back, false)
	caldera = caldera_quad(back, {"seed": 3.0})
	smoke_col = blast_quad(back, SMOKE, SMOKE, {"amp": 26., "k": .06, "seed": 4.4, "glow": 0.0, "glow_r": 20.})
	for i in range(6):
		spurts.append(eruption_quad(back, {"seed": 10.0 + i, "smoke": 0.4}))
	blast = blast_quad(back, LAVA, LAVA, {"amp": 42., "k": .045, "seed": 7.2, "glow": .9, "glow_col": Vector3(1., .5, .15), "glow_r": 60.})
	blast.set_meta("blast_reach", Vector3.ZERO)
	smoke_big = blast_quad(back, SMOKE, SMOKE, {"amp": 30., "k": .05, "seed": 6.3, "glow": 0.0, "glow_r": 20.})
	column = eruption_quad(front, {"seed": 2.0, "smoke": 0.55})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 1.0 + i * 2.5, "glow": .4, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

func _beat_k(t: float) -> float:
	var k := 0.0
	for b in T.beats:
		if t >= float(b):
			k = maxf(k, 1.0 - RBMHeroFx.ramp(t - float(b), 0.0, 0.3))
	return k

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var ae := t - T.erupt
	var ar := t - T.reveal
	var dark := RBMHeroFx.ramp(t, T.dark, T.dark + 0.5) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.1))
	var beat := _beat_k(t)
	var ground := HOME + Vector2(4, 4)
	# 世界: 震え → 闇 → 噴火で一瞬白く → 覚醒後は暗い赤
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.dark, 0.2], [float(T.dark) + 0.5, 0.82], [T.erupt, 0.85], [float(T.erupt) + 0.05, 0.2], [T.reveal, 0.45], [T.end, 0.25]])
	view["dim_col"] = Color(0.05, 0.01, 0.0)
	view["shake"] += Vector2(sin(t * 33.0), cos(t * 27.0) * 0.6) * (0.6 * RBMHeroFx.ramp(t, 0.1, T.dark) + 1.4 * RBMHeroFx.ramp(t, T.rise, T.erupt)) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.05))
	# 震えと炉の熱（闇の前）
	var mouth := px(MOUTH) if t >= T.curl else at("center", 1, -14, 8)
	var warm := RBMHeroFx.ramp(t, 0.1, T.dark)
	embers(b_add, Rect2(HOME.x - 70, HOME.y - 90, 140, 90), t, 30, 3, 80.0, EMBER, warm * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.2)), 2.0, 6.0)
	# 影になって炉の口と目だけが光る
	view["hero"]["silhouette"] = dark
	view["hero"]["sil_col"] = Color(0.05, 0.01, 0.01)
	view["hero"]["lit"] = 0.5 * beat * dark
	view["hero"]["lit_col"] = ORANGE
	if t < T.erupt:
		var mk := maxf(0.3 * warm, dark) * (0.75 + 0.45 * beat)
		disc(b_add, mouth, 14.0 * mk, Color(ORANGE, 0.16 * mk))
		disc(b_add, mouth, 7.0 * mk, Color(EMBER, 0.4 * mk))
		disc(b_add, mouth, 3.0 * mk, Color(WHITE, 0.9 * mk))
		for e in EYES:
			eye_glow(b_add, px(e), dark * (0.9 + 0.5 * beat), Color(1.0, 0.55, 0.12))
	# 鼓動: 足元の地面が下から赤く脈打つ → 火口が開き、溶岩が渦を巻いてせり上がる
	var open := RBMHeroFx.ramp(t, T.caldera, float(T.caldera) + 0.8)
	var glow_k := RBMHeroFx.ramp(t, T.beats[0] - 0.1, T.beats[0]) * (0.5 + 0.5 * beat)
	var rise := RBMHeroFx.ramp(t, T.rise, T.erupt)
	var cool := RBMHeroFx.ramp(ar, 0.5, 2.2)
	if glow_k > 0.0 or open > 0.0:
		show_caldera(caldera, ground, CALDERA_R * (0.85 + 0.15 * open), {"squash": 0.28, "open": open, "heat": clampf(0.5 + 0.5 * beat + 0.6 * rise - 0.5 * cool, 0.0, 1.2) * maxf(glow_k, open), "flow": t, "fade": 1.0 - RBMHeroFx.ramp(t, T.end - 0.5, T.end)})
	else:
		caldera.visible = false
	for b in T.beats:
		var bt := t - float(b)
		refract_wave(ground + Vector2(0, -30), bt, 0.5, 220.0, 5.0, 0.03)
		view["shake"] += hit_shake(bt, 6.0, 50.0, 0.25)
	if open > 0.0 and ae < 0.0:
		lava_drops(b_front, ground + Vector2(-CALDERA_R * 0.8, 0), fmod(t * 0.9, 0.6), 0.6, 4, 21, 120.0, 2.0, -PI * 0.5, 0.8, 300.0)
		lava_drops(b_front, ground + Vector2(CALDERA_R * 0.8, 0), fmod(t * 0.9 + 0.3, 0.6), 0.6, 4, 23, 120.0, 2.0, -PI * 0.5, 0.8, 300.0)
	# 縁から短く噴き出す炎（せり上がる間）
	for i in range(6):
		var ang := -PI + float(i) / 5.0 * PI
		var sp_pos := ground + Vector2(cos(ang) * CALDERA_R * 0.82, sin(ang) * CALDERA_R * 0.82 * 0.28 + 2.0)
		var st := t - (float(T.rise) + i * 0.08)
		var sg := RBMHeroFx.ramp(st, 0.0, 0.15) * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.3))
		show_eruption(spurts[i], sp_pos, 9.0, 46.0 + 14.0 * sin(t * 6.0 + i), sg, {"flow": t + i, "heat": 1.0})
	# 黒煙が火口から立ちのぼる
	var sa := t - T.caldera
	var sf := 1.0 - RBMHeroFx.ramp(ae, 0.2, 0.6)
	smoke_col.visible = sa >= 0.0 and sf > 0.0
	if smoke_col.visible:
		show_blast(smoke_col, blobs(ground + Vector2(10, -110 - sa * 18.0), sa * 0.5, 26, 9, 120.0, 60.0, 36.0, 90.0, .1, 0.0, 2.0), sa, {"flow": sa * .12, "cool": 0.0, "erode": 0.0, "fade": sf * RBMHeroFx.ramp(sa, 0.0, 0.6) * 0.8, "erode_noise": .6, "tone_cap": .55})
	if t >= T.rise and ae < 0.0:
		inward(b_add, mouth, t, 90, 15, 8.0, 220.0, 2.0, HOT, rise, 2.2)
	# 噴火の柱: 巨人ごと天まで（中で絵が変わる）→ 崩れる
	var cg := RBMHeroFx.ramp(ae, 0.0, 0.12)
	var cdown := RBMHeroFx.ramp(ar, -0.1, 0.35)
	body["hidden"] = ae >= 0.04 and ar < -0.05
	if ae >= 0.0 and cdown < 1.0:
		show_eruption(column, ground + Vector2(0, 2), 74.0 * (1.0 - 0.6 * cdown), 420.0, cg, {"flow": t * 1.2, "heat": 1.0, "smoke": 0.5 + 0.4 * cdown, "fade": 1.0 - cdown})
	else:
		column.visible = false
	if ae >= 0.0:
		if ae < 0.12:
			set_post({"flash": 0.3 * (1.0 - ae / 0.12), "flash_col": Vector3(1.0, 0.85, 0.6)})
		lava_drops(b_front, ground + Vector2(0, -80), ae, 1.4, 50, 31, 620.0, 3.6, -PI * 0.5, PI * 1.5, 420.0)
		rocks(b_front, ground, ae, 1.4, 30, 33, 700.0, 7.0, 16.0)
		for k in range(12):
			var to := Vector2(30 + k * 52 + RBMHeroFx.r(k, 61) * 30.0, 170 + RBMHeroFx.r(k, 62) * 110.0)
			var bt2 := ae - 0.15 - k * 0.07
			lava_bomb(b_front, b_add, ground + Vector2(0, -220), to, bt2, 0.8, 3.0 + RBMHeroFx.r(k, 63) * 2.5, 50.0)
			if bt2 >= 0.8 and bt2 < 1.2:
				lava_drops(b_front, to, bt2 - 0.8, 0.4, 8, 71 + k, 160.0, 2.0, -PI * 0.5, PI * 1.1, 360.0)
				view["shake"] += hit_shake(bt2 - 0.8, 2.5, 70.0, 0.15)
	view["shake"] += hit_shake(ae, 22.0, 55.0, 0.9)
	var bf := 1.0 - RBMHeroFx.ramp(ae, 0.4, 0.9)
	blast.visible = ae >= 0.0 and bf > 0.0
	if blast.visible:
		var c := ground + Vector2(0, -40)
		show_blast(blast, blobs(c, ae, 34, 31, 340.0, 150.0, 86.0, 120.0, .6, 0.0, 6.6), ae, {"flow": ae * .22, "cool": .05 + RBMHeroFx.ramp(ae, .2, 1.0) * .25, "erode": RBMHeroFx.ramp(ae, .3, .9), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .42, "heat_center": w(c), "heat_radius": 380.0 * RBMHeroFx.burst(ae, 6.6), "erode_radial": 200.0, "tone_cap": .95})
		refract_wave(ground, ae, 0.9, 620.0, 5.0, 0.04)
	for i in range(3):
		show_ring(rings[i], ground, ae - i * 0.09, 0.8, 600.0 - i * 120.0, 9.0 - i * 2.0, 5.0, 0.035 * float(i == 0))
	# 覚醒後の姿: 溶岩の色のオーラ・縁の光・灰と火の粉
	if ar >= -0.1:
		view["hero"]["sun_aura"] = RBMHeroFx.ramp(ar, -0.1, 0.5)
		view["hero"]["lit"] = 0.6 * (1.0 - RBMHeroFx.ramp(ar, 0.3, 1.4))
		view["hero"]["lit_col"] = EMBER
		if ar >= 0.0 and ar < 0.12:
			view["hero"]["flash"] = 0.8 * (1.0 - ar / 0.12)
			view["hero"]["flash_col"] = WHITE
	var mf := 1.0 - RBMHeroFx.ramp(ar, 0.8, 2.0)
	smoke_big.visible = ar >= -0.2 and mf > 0.0
	if smoke_big.visible:
		show_blast(smoke_big, blobs(HOME + Vector2(0, -170), maxf(ar + 0.2, 0.0), 24, 37, 300.0, 80.0, 56.0, 120.0, .2, 0.0, 2.4), maxf(ar + 0.2, 0.0), {"flow": t * .15, "cool": 0.0, "erode": RBMHeroFx.ramp(ar, .8, 2.0), "fade": mf * 0.6, "erode_noise": .6, "tone_cap": .6})
	embers(b_add, Rect2(-20, 40, 680, 300), t, 120, 47, -60.0, Color(0.55, 0.5, 0.48), RBMHeroFx.env(ar, 0.2, 0.8, 2.0, 2.4) * 0.8, 2.0, 18.0)
	embers(b_add, Rect2(-20, 100, 680, 250), t, 120, 49, 200.0, ORANGE, RBMHeroFx.env(ae, 0.3, 0.6, 2.4, 3.0), 2.2, 16.0)
	set_post({"vig": 0.5 * dark + 0.15, "vig_col": Vector3(.06, .01, .0), "vig_r": .26})
	b_back.commit(); b_add.commit(); b_front.commit()
