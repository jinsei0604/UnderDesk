extends RBMHeroFxBase
## ヒーローの登場「救難信号」（2026-11-17。2026-11-19 ユーザーの指摘で照射器を動かさない・手を突き出すコマを使わない形に。
## 表示専用。戦闘の状態・乱数には触れない）。
## 意味: 救難基地の照射器が屋上の床を照らして待っている所へ、ヒーローが降りてくる。
## 夕暮れの屋上が少し暗い。左右の照射器が最初から着地点の床を照らしている（動かさない）→ 画面の上から流れ星が光の中へ落ち、
## ヒーロー着地（片膝・拳を床へ。青い閃光・床を走る衝撃の輪・破片・火花・揺れ）→ 立ち上がる（照射器の光に照らされる）
## → 腕を胸の前で組み（バイザーが光る）、腕を組んだまま背後で大爆発（戦隊もののヒーローの背景の爆発。橙の炎と青い火花）→ 構えへ。
## 本体は正式モーションのコマ（release1＝ヒーロー着地、blade1＝腕組み、normal＝立ち姿）を切り替えるだけ。
## 本体の状態は view["body"] = {"cel", "hidden"}。カメラは寄らない（揺れだけ）。音は assets_bossmaker/audio/hero_boss/intro.wav（1本）。

const T := RBMHeroFxTiming.INTRO
const HOME := Vector2(390, 238)
## 照射器が照らす床（着地点）。光の帯はレンズからここまで。
const SPOT := Vector2(390, 236)
## 流れ星が落ち始める所（画面の上の黒い帯（論理39ドットまで）の向こう）
const SKY := Vector2(398, -30)
const BLUE := Color("#5cc6fa")
const PALE := Color("#c8f4ff")

var b_sky: RBMHeroFxBatch
var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var land_blast: ColorRect
var boom: ColorRect
var shock: ColorRect

func _build() -> void:
	b_sky = batch(back)
	boom = blast_quad(back, RBMHeroFx.FIRE, RBMHeroFx.FIRE, {"amp": 26., "k": .07, "seed": 4.2, "glow": .7, "glow_col": Vector3(1., .55, .2), "glow_r": 50.})
	b_back = batch(back, false)
	land_blast = blast_quad(back, RBMHeroFx.PLASMA, RBMHeroFx.PLASMA, {"amp": 6., "k": .22, "seed": 1.7, "glow": .7, "glow_col": Vector3(.4, .8, 1.), "glow_r": 20., "floor_tone": .35})
	shock = ring_quad(front, RBMHeroFx.R_BLUE, {"squash": .3, "breakup": .35, "seed": 2.4, "glow": .5, "glow_col": Vector3(.4, .8, 1.)})
	b_front = batch(front, false)
	b_add = batch(front)

## 本体のコマ（切り替えは一瞬。間を埋めない）
func cel_at(t: float) -> String:
	if t < T.rise:
		return "release1"
	if t < T.arms:
		return "normal"
	if t < T.settle:
		return "blade1"
	return "normal"

func _step(t: float) -> void:
	b_sky.reset(); b_back.reset(); b_add.reset(); b_front.reset()
	var cel := cel_at(t)
	view["body"] = {"cel": cel, "hidden": t < T.land}
	var la := t - T.land
	view["dim"] = 0.28 * RBMHeroFx.ramp(t, 0.0, 0.4) * (1.0 - RBMHeroFx.ramp(t, T.settle, T.end))
	view["dim_col"] = Color(0.03, 0.04, 0.1)
	# 照射器: 最初から着地点の床を照らしている（動かさない）→ 構えた後に消える
	var on := 1.0 - RBMHeroFx.ramp(t, T.settle, T.end - 0.1)
	RBMHeroRooftop.beam(b_sky, RBMHeroRooftop.LENS_L, SPOT, 10.0, 64.0, RBMHeroRooftop.WARM, on)
	RBMHeroRooftop.beam(b_sky, RBMHeroRooftop.LENS_R, SPOT, 10.0, 64.0, RBMHeroRooftop.WARM, on)
	# 画面の上から流れ星が光の中へ落ちる
	var fk := RBMHeroFx.ramp(t, T.fall, T.land)
	if t >= T.fall and t < T.land:
		var head := SKY.lerp(HOME + Vector2(0, -20), fk * fk)
		var tail := SKY.lerp(HOME + Vector2(0, -20), maxf(0.0, fk * fk - 0.45))
		b_add.streak(tail, head, 11.0, Color(PALE, 0.9), Color(BLUE, 0.0))
		b_add.streak(tail, head, 4.0, Color(1, 1, 1, 1.0), Color(PALE, 0.0))
		RBMHeroRooftop.glow(b_add, head, 16.0, Color(BLUE, 0.75))
		RBMHeroRooftop.glow(b_add, head, 6.0, Color(1, 1, 1, 0.9))
		sparks(b_add, head, 0.05, 0.3, 6, 11 + int(t * 30.0), 120.0, Color.WHITE, BLUE, (SKY - head).angle(), 0.8, 0.0, 1.4)
	# ヒーロー着地: 青い閃光・床を走る衝撃の輪・破片・火花・揺れ
	if la >= 0.0:
		var ground := HOME + Vector2(0, -2)
		view["shake"] += hit_shake(la, 26.0, 70.0, 0.45)
		set_post({"flash": 0.24 * (1.0 - RBMHeroFx.ramp(la, 0.0, 0.12)), "flash_col": Vector3(.8, .95, 1.0)})
		view["hero"]["flash"] = 0.6 * (1.0 - RBMHeroFx.ramp(la, 0.0, 0.2))
		view["hero"]["flash_col"] = PALE
		rocks(b_front, ground, la, 0.9, 16, 21, 320.0, 3.4, 0.6)
		sparks(b_add, ground + Vector2(0, -4), la, 0.5, 40, 23, 420.0, Color.WHITE, BLUE, -PI * 0.5, PI * 0.9, 300.0, 1.6)
		show_ring(shock, ground, la, 0.45, 120.0, 5.0, 6.0, 0.03)
		ally_light(RBMHeroFx.env(la, 0.0, 0.04, 0.12, 0.4) * 0.7, PALE, -1.0)
	var lf := 1.0 - RBMHeroFx.ramp(la, 0.1, 0.3)
	land_blast.visible = la >= 0.0 and lf > 0.0
	if land_blast.visible:
		var lb := la + 0.06
		show_blast(land_blast, blobs(HOME + Vector2(0, -4), lb, 12, 31, 50.0, 3.0, 8.0, 6.0, .3, 1.0, 10.0), lb, {"flow": lb * .3, "cool": .02, "erode": RBMHeroFx.ramp(lb, .12, .32) * .5, "fade": lf, "erode_noise": .4,
			"polar": 0.6, "detail": .5, "radial_heat": .6, "heat_center": w(HOME + Vector2(0, -4)), "heat_radius": 50.0 * RBMHeroFx.burst(lb, 10.0), "erode_radial": 40.0, "tone_cap": .98})
	# 立ち上がった後: 照射器の光に照らされる（縁が淡く光る）
	if t >= T.rise:
		view["hero"]["lit"] = 0.35 * RBMHeroFx.ramp(t, T.rise, T.rise + 0.2) * (1.0 - RBMHeroFx.ramp(t, T.settle, T.end))
		view["hero"]["lit_col"] = RBMHeroRooftop.WARM
	# 腕組み: バイザーが光る（丸い光）
	var va := t - T.arms
	if va >= 0.0 and va < 0.4:
		var g := RBMHeroFx.env(va, 0.0, 0.05, 0.12, 0.4)
		RBMHeroRooftop.glow(b_add, anchor("head") + Vector2(2, 2), 9.0 * g, Color(1.0, 0.85, 0.5, 0.8 * g))
	# 腕を組んだまま、背後で大爆発（少し育った所から出す。出始めの小さな形は尖った星に見える）
	var ba := t - T.boom
	var bf := 1.0 - RBMHeroFx.ramp(ba, 0.62, 0.92)
	boom.visible = ba >= 0.0 and bf > 0.0
	if boom.visible:
		var bc := HOME + Vector2(6, -40)
		var bb := ba + 0.08
		show_blast(boom, blobs(bc, bb, 26, 41, 84.0, 30.0, 30.0, 46.0, .55, 0.0, 6.2), bb, {"flow": bb * .22, "cool": RBMHeroFx.ramp(bb, .2, .9) * .3, "erode": RBMHeroFx.ramp(bb, .32, .95), "fade": bf, "lump_scale": .62, "tone_cap": .9, "erode_noise": .4})
	if ba >= 0.0:
		sparks(b_add, HOME + Vector2(0, -50), ba, 0.7, 60, 51, 480.0, Color("#fff0c4"), Color("#ff8a24"), -PI * 0.5, PI * 1.6, 90.0, 1.8)
		sparks(b_add, HOME + Vector2(0, -50), ba, 0.6, 30, 53, 400.0, Color.WHITE, BLUE, -PI * 0.5, PI * 1.4, 80.0, 1.6)
		view["shake"] += hit_shake(ba, 18.0, 65.0, 0.5)
		ally_light(RBMHeroFx.env(ba, 0.0, 0.05, 0.3, 0.8) * 0.6, Color("#ffb347"), 0.0)
		view["hero"]["lit"] = maxf(float(view["hero"].get("lit", 0.0)), 0.5 * RBMHeroFx.env(ba, 0.0, 0.05, 0.3, 0.9))
		view["hero"]["lit_col"] = Color("#ffb347")
	b_sky.commit(); b_back.commit(); b_add.commit(); b_front.commit()
