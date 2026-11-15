extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/pre_single.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人・覚醒前単体「岩槌落とし」（2026-11-14 作り直し。指摘「巨人が動いているのではなく画面の上でドラッグして動かしているように見える」）:
## 地面の上を滑らせない。構え → 岩の拳を肩越しに掲げる（拳が赤熱して溶岩が垂れる）→ 地面を蹴って高く跳び、画面の上へ消える（土ぼこり・残像）
## → 地面の影だけが相手の所へ移る → 拳を下にして燃えながら真上から落ちてきて叩きつける（ヒットストップ・溶岩の柱・溶岩溜まり・飛沫・岩・衝撃波）
## → 振り抜き → また高く跳んで画面の上へ消え、元の場所へ落ちてきて着地する。

const T := {"windup": 0.30, "leap": 0.66, "fall": 0.94, "slam": 1.10, "follow": 1.42, "hop": 1.74, "drop": 1.98, "land": 2.10, "end": 2.70}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
## 跳んだ時の高さ（画面の上の外まで）
const SKY := -300.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var pool: ColorRect
var jet: ColorRect
var splash: ColorRect
var smoke: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.slam

func stops() -> Array:
	return [[T.slam, 0.12]]

func _reach() -> Vector2:
	return Vector2(-78, 22) + focus_delta

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.fall, 3], [T.follow, 4], [T.hop, 2], [T.land, 1]]

## 位置: 跳ぶ・落ちるは縦だけ。横の移動は画面の外（上）にいる間に済ませる（地面の上を滑らせない）
func move_keys() -> Array:
	var r := _reach()
	return [[0.0, Vector2.ZERO, "snap"], [T.leap, Vector2.ZERO, "snap"], [T.leap + 0.14, Vector2(0, SKY), "out"],
		[T.fall, Vector2(r.x, r.y - 210.0), "snap"], [T.slam, r, "lin"],
		[T.hop, r, "snap"], [T.hop + 0.14, Vector2(r.x, r.y + SKY), "out"],
		[T.drop, Vector2(0, -200.0), "snap"], [T.land, Vector2.ZERO, "lin"]]

func _build() -> void:
	b_back = batch(back, false)
	pool = magma_quad(back, {"seed": 2.0})
	smoke = blast_quad(back, SMOKE, SMOKE, {"amp": 20., "k": .08, "seed": 5.1, "glow": 0.0, "glow_r": 20.})
	splash = blast_quad(back, LAVA, LAVA, {"amp": 22., "k": .08, "seed": 2.2, "glow": .7, "glow_col": Vector3(1., .5, .15), "glow_r": 30.})
	jet = magma_quad(front, {"seed": 4.0})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .4, "breakup": .5, "seed": 3.0 + i * 2.1, "glow": .4, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

## 地面の影（空にいる間も地面に残り、着地点へ移る。高いほど小さく薄い）
func ground_shadow(t: float) -> void:
	var r := _reach()
	var off: Vector2 = body.get("off", Vector2.ZERO)
	var x := HOME.x
	var y := HOME.y
	var lift := 0.0
	if t >= T.leap and t < T.slam:
		var u := RBMHeroFx.ramp(t, T.leap + 0.1, T.fall + 0.06)
		var e := u * u * (3.0 - 2.0 * u)
		x = HOME.x + r.x * e
		y = HOME.y + r.y * e
		lift = (HOME.y + r.y * e) - (HOME.y + off.y)
	elif t >= T.hop and t < T.land:
		var u2 := RBMHeroFx.ramp(t, T.hop + 0.1, T.drop + 0.06)
		var e2 := 1.0 - u2 * u2 * (3.0 - 2.0 * u2)
		x = HOME.x + r.x * e2
		y = HOME.y + r.y * e2
		lift = (HOME.y + r.y * e2) - (HOME.y + off.y)
	else:
		return
	var k := clampf(1.0 - lift / 320.0, 0.35, 1.0)
	disc(b_back, Vector2(x, y + 1), 34.0 * k, Color(0.05, 0.03, 0.03, 0.55 * (0.4 + 0.6 * k)), 0.16)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var a := t - T.slam
	var ground: Vector2 = targets[3] + Vector2(10, 2)
	var off: Vector2 = body.get("off", Vector2.ZERO)
	# 掲げた拳が赤熱し、溶岩が垂れる
	var ch := RBMHeroFx.ramp(t, T.windup, T.leap) * (1.0 - RBMHeroFx.ramp(t, T.slam, T.slam + 0.1))
	var fist := at("top", 2, 30, 18) if t < T.fall else at("front", 3)
	disc(b_add, fist, 3.0 + 3.0 * ch, Color(HOT, 0.6 * ch))
	embers(b_add, Rect2(fist.x - 16, fist.y - 12, 32, 24), t, 26, 3, 50.0, ORANGE, ch * 1.3, 2.0, 4.0)
	if ch > 0.2 and t < T.leap:
		lava_drops(b_front, fist + Vector2(0, 6), fmod(t * 1.7, 0.6), 0.6, 3, 9, 30.0, 1.6, PI * 0.5, 0.6, 260.0)
	view["hero"]["lit"] = 0.4 * ch
	view["hero"]["lit_col"] = EMBER
	view["hero"]["lit_side"] = -1.0
	view["dim"] = 0.25 * RBMHeroFx.env(t, T.windup, T.leap, T.follow, T.hop)
	view["dim_col"] = Color(0.06, 0.02, 0.01)
	ground_shadow(t)
	# 跳び立ち（土ぼこり・岩・小さな衝撃）と、上へ消える残像
	for k in [[T.leap, HOME], [T.hop, HOME + _reach()]]:
		var dt := t - float(k[0])
		if dt >= 0.0 and dt < 0.5:
			var f := 1.0 - dt / 0.5
			for i in range(8):
				disc(b_back, Vector2(k[1]) + Vector2(-36 + i * 10, -3), 6.0 + dt * 34.0 * RBMHeroFx.r(i, 7), Color(0.45, 0.4, 0.38, 0.45 * f), 0.5)
			rocks(b_front, Vector2(k[1]), dt, 0.6, 10, 11, 260.0, 4.0, 2.0)
			view["shake"] += hit_shake(dt, 6.0, 70.0, 0.2)
		if dt >= 0.0 and dt < 0.16:
			for g in range(3):
				ghost(2, off + Vector2(0, 40.0 + g * 40.0), 0.35 - g * 0.1, Color(1.0, 0.45, 0.15), 0.5)
	# 真上から燃えながら落ちてくる（火の尾・残像）
	for seg in [[T.fall, T.slam, 3], [T.drop, T.land, 2]]:
		if t >= float(seg[0]) and t < float(seg[1]):
			var pose_n := int(seg[2])
			var top := at("top", pose_n)
			for g in range(3):
				ghost(pose_n, off + Vector2(0, -36.0 - g * 34.0), 0.4 - g * 0.12, Color(1.0, 0.45, 0.15), 0.5)
			b_add.streak(top + Vector2(0, -150), top + Vector2(0, -10), 26.0, Color(ORANGE, 0.0), Color(HOT, 0.55))
			embers(b_add, Rect2(top.x - 30, top.y - 90, 60, 90), t, 30, 13, -200.0, EMBER, 1.0, 2.2, 6.0)
	# 着地（戻り）
	var la := t - T.land
	if la >= 0.0 and la < 0.4:
		for i in range(6):
			disc(b_back, HOME + Vector2(-26 + i * 10, -3), 5.0 + la * 30.0 * RBMHeroFx.r(i, 17), Color(0.45, 0.4, 0.38, 0.4 * (1.0 - la / 0.4)), 0.5)
		view["shake"] += hit_shake(la, 8.0, 60.0, 0.3)
	# 叩きつけ: 溶岩の柱・溶岩溜まり（冷えて固まる）・飛沫・岩・衝撃波
	if a >= 0.0:
		show_pool(pool, ground, 64.0 * RBMHeroFx.burst(a, 7.0), {"crust": RBMHeroFx.ramp(a, 0.3, 1.3), "heat": 1.0 - 0.5 * RBMHeroFx.ramp(a, 0.8, 1.4), "flow": t, "fade": 1.0 - RBMHeroFx.ramp(t, T.end - 0.3, T.end)})
		var jg := RBMHeroFx.ramp(a, 0.0, 0.1) * (1.0 - RBMHeroFx.ramp(a, 0.35, 0.7))
		show_jet(jet, ground + Vector2(0, -2), Vector2(0, -1), 120.0, 14.0, jg, {"flow": t, "heat": 1.0})
		lava_drops(b_front, ground + Vector2(0, -6), a, 1.0, 26, 21, 380.0, 3.0, -PI * 0.5, PI * 1.1, 420.0)
		disc(b_add, ground + Vector2(0, -8), 22.0 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08)), Color(WHITE, 0.8 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08))), 0.6)
		embers(b_add, Rect2(ground.x - 50, ground.y - 60, 100, 60), t, 30, 21, 60.0, EMBER, RBMHeroFx.env(a, 0.2, 0.4, 1.0, 1.4), 2.0, 6.0)
		set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), "flash_col": Vector3(1.0, 0.7, 0.4)})
	else:
		pool.visible = false
		jet.visible = false
	var sf := 1.0 - RBMHeroFx.ramp(a, 0.35, 0.65)
	splash.visible = a >= 0.0 and sf > 0.0
	if splash.visible:
		show_blast(splash, blobs(ground + Vector2(0, -12), a, 26, 11, 130.0, 54.0, 30.0, 60.0, .9, 0.0, 9.0), a, {"flow": a * .3, "cool": .05 + RBMHeroFx.ramp(a, .1, .6) * .3, "erode": RBMHeroFx.ramp(a, .2, .65), "fade": sf, "erode_noise": .4, "tone_cap": .95})
		refract_wave(ground, a, 0.5, 220.0, 6.0, 0.03)
	var mf := 1.0 - RBMHeroFx.ramp(a, 0.9, 1.5)
	smoke.visible = a >= 0.15 and mf > 0.0
	if smoke.visible:
		show_blast(smoke, blobs(ground + Vector2(0, -24), a, 16, 13, 60.0, 30.0, 20.0, 90.0, .2, 0.0, 3.0), a, {"flow": a * .2, "cool": 0.0, "erode": RBMHeroFx.ramp(a, .5, 1.4), "fade": mf * 0.55, "erode_noise": .6, "tone_cap": .7})
	for i in range(3):
		show_ring(rings[i], ground, a - i * 0.07, 0.5, 190.0 - i * 45.0, 6.0 - i * 1.5, 6.0, 0.03 * float(i == 0))
	rocks(b_front, ground, a, 1.0, 24, 17, 540.0, 6.0, 4.0)
	sparks(b_add, ground + Vector2(0, -6), a, 0.8, 90, 19, 600.0, HOT, ORANGE, -PI * 0.5, PI * 1.1, 320.0, 2.2)
	view["shake"] += hit_shake(a, 22.0, 60.0, 0.55)
	ally_hits(t, [[T.slam, 3]], 1.2)
	if a >= 0.0:
		view["allies"][3]["lit"] = 0.55 * RBMHeroFx.env(a, 0.0, 0.03, 0.3, 0.7)
		view["allies"][3]["lit_col"] = ORANGE
	b_back.commit(); b_add.commit(); b_front.commit()
