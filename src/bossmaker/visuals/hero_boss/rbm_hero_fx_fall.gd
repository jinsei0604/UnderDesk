extends RBMHeroFxBase
## 覚醒後の撃破（2026-11-11）: 闇が暴れて爆ぜ、元のヒーローの青い光が昇る（表示専用。戦闘の状態・乱数には触れない）。
## 膝をつく → 地面に紅いひびと闇だまり、内から青い光が漏れる（鼓動3回）→ 黒紅の炎が外へ噴き出し、闇の破片が散り、青い光の柱が立つ
## → 元の青い姿で膝をつき、光の柱が細くなる → 青い光の粒になって昇る。
## 本体・オーラ・暗さ・揺れ・音は rbm_hero_boss_defeat_awakened.gd が受け持つ。ここは back（本体の後ろ）と front（いちばん前）の効果だけ。

const T := RBMHeroFxTiming.FALL
const LIGHT := ["#0a1a52", "#123a96", "#1f68e4", "#5cc6fa", "#c8f4ff", "#ffffff"]

var b_back: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_motes: RBMHeroFxBatch
var pool: ColorRect
var cracks: ColorRect
var blast: ColorRect
var pillar: ColorRect
var ring_red: ColorRect
var ring_blue: ColorRect

func _build() -> void:
	pool = quad(back, RBMHeroFx.WORLD, "pool", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.POOL_DARK), "seed": 6.3, "squash": .3})
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.A4_RED), "seed": 9.4, "squash": .32, "line_w": .06, "glow_col": Vector3(1., .12, .22), "glow": .35})
	pillar = quad(back, Rect2(0, -100, 520, 360), "pillar", {"pal": RBMHeroFx.pal(LIGHT), "seed": 4.6, "glow_col": Vector3(.3, .7, 1.)})
	blast = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.VOID, {"amp": 40., "k": .05, "seed": 2.9, "glow": .6, "glow_col": Vector3(.95, .08, .18), "glow_r": 50.})
	b_back = batch(back)
	ring_red = ring_quad(front, RBMHeroFx.A4_RED, {"squash": .34, "breakup": .62, "seed": 7.1, "glow": .3, "glow_col": Vector3(.95, .1, .2)})
	ring_blue = ring_quad(front, RBMHeroFx.A4_BLUE, {"squash": .34, "breakup": .5, "seed": 3.2, "glow": .35, "glow_col": Vector3(.35, .7, 1.)})
	b_front = batch(front)
	b_motes = batch(front)

## 鼓動のたびに一段ずつ強くなる値（途中で弱めない）。
static func tension(t: float) -> float:
	var v := RBMHeroFx.ramp(t, float(T.kneel), float(T.burst)) * .4
	for at in T.beats:
		v += .2 * RBMHeroFx.ramp(t, float(at), float(at) + .06)
	return v

func _step(t: float) -> void:
	b_back.reset(); b_front.reset(); b_motes.reset()
	var BU: float = T.burst
	var RE: float = T.restore
	var FA: float = T.fade
	var a := t - BU
	var chest := anchor("chest")
	var ten := tension(t) * (1.0 - RBMHeroFx.ramp(a, 0.0, .02))

	# 足元の闇だまり: 膝をついた所から広がり、爆発で吹き飛ぶ
	pool.visible = t > float(T.kneel) - .05 and a < .12
	if pool.visible:
		sp(pool, {"center": w(foot + Vector2(0, 2)), "radius": 24.0 + 36.0 * tension(t), "flow": t * .7, "fade": 1.0 - RBMHeroFx.ramp(a, 0.0, .12)})
	# 紅いひび: 爆発の瞬間に足元から走り、光ってから消える（爆発の前は出さない。放射状の線が星の形に見えるため）
	var cf := 1.0 - RBMHeroFx.ramp(a, .6, 1.1)
	cracks.visible = a >= 0.0 and cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(foot + Vector2(0, 2)), "reveal": 30.0 + 420.0 * RBMHeroFx.burst(a, 5.0), "fade": cf, "glow": .35 + .5 * RBMHeroFx.env(a, 0.0, .04, .2, .6)})
	# 闇が暴れる: 体の周りの黒紅の火の粉、集まる青い光と体を走る青い稲妻（内から光が漏れる）
	embers(b_back, Rect2(foot.x - 70, foot.y - 30, 140, 40), t, 70, 11, 150.0, RBMHeroFx.C_RED, ten * 1.4, 2.2, 10.0)
	inward(b_front, chest, t, 110, 17, 8.0, 230.0, 2.2, RBMHeroFx.C_PALE, ten, 2.4)
	if a < 0.0 and ten > .05:
		var count := int(1.0 + ten * 6.0)
		var sd := int(t * 11.0)
		for i in range(count):
			var reach := 14.0 + 40.0 * ten * RBMHeroFx.r(i, sd + 5)
			var end := chest + Vector2.from_angle(RBMHeroFx.r(i, sd) * TAU) * reach * Vector2(1.0, .8)
			arc(b_front, chest + Vector2(RBMHeroFx.r(i, sd + 7) * 10.0 - 5.0, RBMHeroFx.r(i, sd + 9) * 16.0 - 8.0), end, sd + i * 13, 1.0, Color(RBMHeroFx.C_CYAN, .7), Color(RBMHeroFx.C_WHITE, .95), 7, .2)

	# 爆発: 黒紅の炎が外へ噴き出す（②・③と同じ描き方）
	var bf := 1.0 - RBMHeroFx.ramp(a, .62, 1.05)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		var center := foot + Vector2(0, -40)
		var data := blobs(center, a, 48, 31, 560.0, 270.0, 112.0, 150.0, .62, 0.0, 6.4)
		show_blast(blast, data, a, {"flow": a * .22, "cool": .06 + RBMHeroFx.ramp(a, .2, 1.0) * .26, "erode": RBMHeroFx.ramp(a, .3, .98), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "heat_center": w(center), "heat_radius": 470.0 * RBMHeroFx.burst(a, 6.4), "erode_radial": 220.0, "tone_cap": .8})
	# 青い光の柱: 爆発と同時に立ち、元の姿に戻る間は細く残り、光の粒と一緒に消える
	var pf := RBMHeroFx.ramp(a, 0.0, .03) * (1.0 - RBMHeroFx.ramp(t, FA + .3, float(T.gone)))
	pillar.visible = pf > 0.0
	if pillar.visible:
		pillar.position = Vector2(foot.x - 260, -100)
		pillar.size = Vector2(520, foot.y + 100)
		var wide := lerpf(.04, .62, RBMHeroFx.burst(a, 16.0)) * (1.0 - .62 * RBMHeroFx.ramp(a, .14, .6))
		sp(pillar, {"width": wide * (1.0 - .45 * RBMHeroFx.ramp(t, FA, float(T.gone))), "flow": t * 3.0, "fade": pf, "flare": .8 * (1.0 - RBMHeroFx.ramp(a, .3, .8)) + .25})
	# 輪と画面の屈折
	show_ring(ring_red, foot, a, .55, 560.0, 9.0, 5.0, .05)
	refract_wave(foot, a - .05, .8, 600.0, 4.6, .03)
	show_ring(ring_blue, foot, t - RE, .7, 260.0, 5.0, 4.0, .015)
	# 闇の破片と火花が散る
	var origin := chest + Vector2(0, 6)
	shards(b_front, origin, a, 1.15, 90, 37, 900.0, 7.0, RBMHeroFx.C_RED, RBMHeroFx.C_VOID, 200.0)
	sparks(b_front, origin, a, 1.0, 170, 43, 1150.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 150.0, 2.4)
	sparks(b_front, origin, a, .9, 120, 47, 980.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, TAU, 120.0, 2.0)
	embers(b_front, Rect2(-20, 120, 680, 230), a, 160, 53, 260.0, RBMHeroFx.C_RED, RBMHeroFx.env(a, .25, .55, 1.3, 1.9), 2.2, 18.0)
	# 元の姿に戻った後: 体から青い光の粒が昇る（消えていく間がいちばん多い）
	var rise := RBMHeroFx.env(t, RE, RE + .4, float(T.gone) - .25, float(T.gone) + .05)
	embers(b_motes, Rect2(body_foot.x - 34, body_foot.y - 70, 68, 70), t, 90, 61, 190.0, RBMHeroFx.C_PALE, rise * (.5 + .7 * RBMHeroFx.ramp(t, FA, FA + .4)), 2.0, 8.0)
	embers(b_motes, Rect2(body_foot.x - 20, body_foot.y - 60, 40, 60), t + .3, 40, 67, 240.0, RBMHeroFx.C_WHITE, rise * RBMHeroFx.ramp(t, FA, FA + .5), 2.0, 5.0)

	# 世界の色: 闇が暴れる間は色が抜けて周りが暗くなり、爆発の後は戻る
	var hush := ten * (1.0 - RBMHeroFx.ramp(a, 0.0, .2))
	set_post({"focus_world": chest, "desat": .5 * hush, "vig": .55 * hush + .2 * RBMHeroFx.env(a, 0.0, .05, .3, .8), "vig_col": Vector3(.01, .0, .02), "vig_r": .24})
	b_back.commit(); b_front.commit(); b_motes.commit()
