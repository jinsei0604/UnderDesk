extends RBMHeroFxBase
## ③ 覚醒「安全限界解除」: 青い光の異常→暴走→黒い炎の侵食→暗転→黒紅の大解放（青い力が砕ける）→完了の黒い光冠。

const T := RBMHeroFxTiming.BREACH
const HOT := {"bridge2": Vector2(.41, .34), "release0": Vector2(.54, .32), "release1": Vector2(.49, .39), "release2": Vector2(.36, .36), "release3": Vector2(.47, .32), "release4": Vector2(.46, .36)}

var b_back: RBMHeroFxBatch
var b_crown_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_mix: RBMHeroFxBatch
var pool: ColorRect
var cracks: ColorRect
var aura: ColorRect
var pillar: ColorRect
var blast: ColorRect
var blast2: ColorRect
var core: ColorRect
var rings: Array = []

func _build() -> void:
	pool = quad(back, RBMHeroFx.WORLD, "pool", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.POOL_DARK), "seed": 4.1, "squash": .3})
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(RBMHeroFx.A4_RED), "seed": 7.7, "squash": .32, "line_w": .06, "glow_col": Vector3(1., .12, .22), "glow": .35})
	b_crown_add = batch(back)
	aura = quad(back, Rect2(0, 0, 340, 360), "aura", {"pal_a": RBMHeroFx.pal(RBMHeroFx.AURA_BLUE), "pal_b": RBMHeroFx.pal(RBMHeroFx.AURA_DARK), "seed": 2.8})
	pillar = quad(back, Rect2(0, -100, 520, 360), "pillar", {"pal": RBMHeroFx.pal(["#05030a", "#3a0f33", "#a0132f", "#ed274c", "#ff9a88", "#ffefe8"]), "seed": 8.2, "glow_col": Vector3(1., .1, .2)})
	blast = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.VOID, {"amp": 40., "k": .045, "seed": 3.3, "glow": 1.0, "glow_col": Vector3(.95, .08, .18), "glow_r": 64., "rim_mode": 1., "rim_w": 22.})
	blast2 = blast_quad(back, RBMHeroFx.DARK, RBMHeroFx.DARK, {"amp": 40., "k": .05, "seed": 5.7, "glow": .55, "glow_col": Vector3(.95, .08, .18), "glow_r": 50.})
	b_back = batch(back)
	for i in range(4):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i != 2 else RBMHeroFx.A4_DARK, {"squash": .34, "breakup": .62, "seed": float(i) * 3.3 + 2.0, "glow": .3, "glow_col": Vector3(.95, .1, .2)}))
	core = quad(front, Rect2(0, 0, 200, 200), "orb", {"pal": RBMHeroFx.pal(RBMHeroFx.PLASMA), "seed": 1.3, "glow_col": Vector3(.3, .7, 1.)})
	b_front = batch(front)
	b_mix = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_crown_add.reset(); b_front.reset(); b_mix.reset()
	var RL: float = T.release
	var CP: float = T.complete
	var BO: float = T.blackout
	var COL: float = T.collapse
	var a := t - RL
	var a2 := t - CP
	var g := 0.0
	for at in T.glitches:
		g = maxf(g, RBMHeroFx.env(t, float(at), float(at) + .055, float(at) + .1, float(at) + .27))
	var run := RBMHeroFx.ramp(t, T.runaway, COL)
	var inv := RBMHeroFx.ramp(t, T.invade, COL)
	var coll := RBMHeroFx.ramp(t, COL, BO)
	var chest := anchor("chest")
	var black := RBMHeroFx.ramp(t, BO - .03, BO) * (1.0 - RBMHeroFx.ramp(a, -.001, 0.0))
	# 2段階目のタメ: 爆発まで力が集まり続ける。オーラも足元の闇も途中で縮めない（縮んで戻ると不自然に見える）
	var TM: float = T.tame
	var tm := RBMHeroFx.ramp(t, TM, CP - .12)
	var tm_on := tm * (1.0 - RBMHeroFx.ramp(t, CP - .03, CP))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [.55, .1], [1.22, .3], [2.24, .62], [2.9, .82], [BO, 1.0], [RL, 1.0], [RL + .28, .78], [3.9, .74], [TM, .7], [CP - .1, .88], [CP + .16, .62], [T.duration, .36]])
	view["dim_col"] = Color(.02, .01, .05)
	var jitter := (g * .5 + run * .8 * (1.0 - coll))
	view["shake"] = Vector2(sin(t * 29.0), cos(t * 23.0) * .6) * jitter

	# 地面の闇
	var pool_r := 18.0 + 230.0 * inv
	var pool_f := 1.0
	if a >= 0.0:
		pool_r = lerpf(620.0, 72.0, RBMHeroFx.ramp(a, .2, 1.7))
	pool.visible = t > float(T.invade) - .1 and not (black > .5)
	if pool.visible:
		sp(pool, {"center": w(foot + Vector2(0, 2)), "radius": pool_r, "flow": t * .6, "fade": pool_f})

	# 体の炎: 青→白へ暴走→下から闇に喰われる
	var on := 1.0 - RBMHeroFx.ramp(t, COL, BO - .02)
	aura.visible = t > .3 and on > .01 and a < 0.0
	if aura.visible:
		aura.position = foot + Vector2(-170, -356)
		sp(aura, {"power": (.18 + .34 * g + .95 * run) * on, "flow": t * (2.4 + run * 2.0), "width": (.22 + .16 * run + .08 * g) * on, "corrupt": inv * .95, "glow": .6 + .6 * run})

	# 胸の灯: 異常な明滅 → 収縮 → 赤に変わる
	core.visible = t > .3 and a < .04
	if core.visible:
		core.position = chest - Vector2(100, 100)
		# 闇が来ると青い灯は押しつぶされて小さくなる（黒い炎と体が見える）
		var rad := .05 + .1 * g + .24 * run * (1.0 - .82 * inv)
		rad *= 1.0 - .82 * coll
		var red := RBMHeroFx.ramp(t, BO, RL)
		sp(core, {"radius": rad, "flow": t * 4.0, "spike": 1.0, "glow": 1.0 + run, "pal": RBMHeroFx.pal(RBMHeroFx.DARK if red > .5 else RBMHeroFx.PLASMA), "glow_col": Vector3(1., .1, .2) if red > .5 else Vector3(.3, .7, 1.)})

	# 稲妻
	if t < BO and g + run > .02:
		var count := int(2.0 + g * 4.0 + run * 9.0)
		var sd := int(t * 9.0)
		for i in range(count):
			var reach := (34.0 + 150.0 * run * RBMHeroFx.r(i, sd + 5) + 40.0 * g) * (1.0 - coll * .85)
			var end := chest + Vector2.from_angle(RBMHeroFx.r(i, sd) * TAU) * reach * Vector2(1.0, .78)
			var dark := RBMHeroFx.r(i, sd + 3) < inv * .75
			arc(b_front, chest + Vector2(RBMHeroFx.r(i, sd + 7) * 12.0 - 6.0, RBMHeroFx.r(i, sd + 9) * 22.0 - 11.0), end, sd + i * 13, 1.2, Color(RBMHeroFx.C_RED if dark else RBMHeroFx.C_CYAN, .75), Color(RBMHeroFx.C_ROSE if dark else RBMHeroFx.C_WHITE, 1.0), 9, .17)
	embers(b_back, Rect2(foot.x - 130, foot.y - 34, 260, 44), t, 100, 3, 240.0, RBMHeroFx.C_PALE.lerp(RBMHeroFx.C_RED, inv), minf(run * 2.0, 1.0) * (1.0 - coll), 2.4, 14.0)
	inward(b_front, chest, t, 130, 7, 8.0, 330.0, 2.6, RBMHeroFx.C_PALE.lerp(RBMHeroFx.C_RED, inv), coll * (1.0 - black), 4.6)
	# 本体への色
	var hero: Dictionary = view["hero"]
	if a < 0.0:
		# 黒い炎の侵食: 三回に分けて燃え上がりながら足元から頭へ這い上がり、崩壊で吸い込まれる
		var sg: Array = T.surges
		var s0: float = sg[0]
		var s1: float = sg[1]
		var s2: float = sg[2]
		hero["dark_aura"] = RBMHeroFx.key(t, [[s0, 0.0], [s0 + .08, .8], [s1 - .02, .7], [s1 + .08, 1.25], [s2 - .02, 1.1], [s2 + .08, 1.8], [COL, 1.6], [BO - .02, .25], [BO, 0.0]])
		hero["dark_rise"] = RBMHeroFx.key(t, [[s0, 0.0], [s0 + .12, .3], [s1, .35], [s1 + .12, .7], [s2, .72], [s2 + .12, 1.0]])
	else:
		# 覚醒後の常時オーラ（ここから以降ずっと続く）
		hero["dark_aura"] = RBMHeroFx.key(t, [[RL + .25, 0.0], [RL + .85, .85], [TM, .9], [CP, 1.6], [CP + .06, 1.8], [CP + .6, 1.0]])
	if t > 1.35 and a < 0.0:
		hero["crawl"] = 6.0 + 72.0 * RBMHeroFx.ramp(t, 1.35, 3.0)
		hero["crawl_center"] = HOT.get(pose, Vector2(.45, .32))
	if run > 0.0 and a < -.2:
		hero["lit"] = (.62 + .2 * sin(t * 8.0)) * run * .55
		hero["lit_col"] = RBMHeroFx.C_PALE.lerp(RBMHeroFx.C_RED, inv)
	if g > .35 and t < T.runaway:
		hero["lit"] = g * .7
		hero["lit_col"] = RBMHeroFx.C_PALE
	if black > 0.0:
		hero["silhouette"] = black
		hero["sil_col"] = Color(.01, .005, .02)
		hero["ally_sil"] = black
		hero["lit"] = .75 * black
		hero["lit_col"] = RBMHeroFx.C_RED
		hero["lit_side"] = 0.0
		view["allies"] = [{}, {}, {}, {}]
		# 三つの目が開く
		for i in range(3):
			var at := BO + .05 + float(i) * .05
			if t >= at:
				var p := anchor("chest") + Vector2(float(i - 1) * 8.0, 0.0)
				star(b_front, p, 1.0, 6, 3 + i, 16.0, 3.0, [Color(RBMHeroFx.C_RED, 1.0), Color(RBMHeroFx.C_WHITE, 1.0)])
				b_front.streak(p + Vector2(-30, 0), p + Vector2(30, 0), 2.0, Color(RBMHeroFx.C_RED, .9), Color(RBMHeroFx.C_RED, .9))

	if a >= 0.0:
		_release(a)
	else:
		for n: CanvasItem in [pillar, blast]:
			n.visible = false
		for r: ColorRect in rings:
			r.visible = false
		cracks.visible = false
	if a2 >= 0.0:
		_complete(a2)
	else:
		blast2.visible = false
	# タメの間: 周りの光が体へ集まり、輪郭が赤く灯り、地面が小さく震える
	if tm_on > 0.0:
		inward(b_back, chest, t, 120, 73, 10.0, 360.0, 2.4, RBMHeroFx.C_RED, tm_on, 2.0)
		inward(b_back, chest, t + .4, 60, 79, 8.0, 260.0, 2.0, RBMHeroFx.C_ROSE, tm_on, 2.4)
		view["shake"] += Vector2(sin(t * 29.0), cos(t * 23.0) * .6) * tm_on * 1.2
		if .75 * tm_on > float(hero.get("lit", 0.0)):
			hero["lit"] = .75 * tm_on
			hero["lit_col"] = RBMHeroFx.C_RED
			hero["lit_side"] = 0.0

	set_post({"focus_world": chest, "corrupt": (g * .3 + run * .12) * (1.0 - coll),
		"desat": inv * .45 * (1.0 - black) * (1.0 - .85 * RBMHeroFx.ramp(a2, 0.0, .1)), "vig": (run * .25 + inv * .55) * (1.0 - RBMHeroFx.ramp(a, 0.0, .1)) + tm_on * .5, "vig_col": Vector3(.01, .0, .02), "vig_r": .22})
	b_back.commit(); b_crown_add.commit(); b_front.commit(); b_mix.commit()

func _release(a: float) -> void:
	var origin := foot + Vector2(0, -52)
	var f := 1.0 - RBMHeroFx.ramp(a, .6, 1.05)
	blast.visible = f > 0.0
	if blast.visible:
		var data := blobs(origin, a, 48, 12, 560.0, 300.0, 116.0, 150.0, .7, .3, 7.0)
		show_blast(blast, data, a, {"cool": RBMHeroFx.ramp(a, .3, 1.2) * .2, "erode": RBMHeroFx.ramp(a, .42, 1.22), "fade": f, "lump_scale": .62, "hot_gain": 1.0 - RBMHeroFx.ramp(a, .08, .4), "erode_noise": .4, "tone_cap": .86})
	var pf := 1.0 - RBMHeroFx.ramp(a, .34, .72)
	pillar.visible = pf > 0.0
	if pillar.visible:
		pillar.position = Vector2(foot.x - 260, -100)
		pillar.size = Vector2(520, foot.y + 100)
		sp(pillar, {"width": lerpf(.04, .8, RBMHeroFx.burst(a, 18.0)) * (1.0 - .5 * RBMHeroFx.ramp(a, .16, .7)), "flow": a * 4.0, "fade": pf, "flare": .8})
	var cf := 1.0 - RBMHeroFx.ramp(a, .9, 1.7)
	cracks.visible = cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(foot + Vector2(0, 2)), "reveal": 620.0 * RBMHeroFx.burst(a, 6.0), "fade": cf})
	show_ring(rings[0], foot, a, .5, 520.0, 8.0, 5.2, .05)
	refract_wave(foot, a - .06, .75, 520.0, 5.0, .03)
	rings[1].visible = false
	rings[2].visible = false
	star(b_crown_add, origin, RBMHeroFx.burst(a, 26.0) * (1.0 - RBMHeroFx.ramp(a, .12, .5)), 22, 31, 520.0, 60.0, [Color(RBMHeroFx.C_CRIM, .9), Color(RBMHeroFx.C_RED, .95), Color(RBMHeroFx.C_ROSE, 1.0)])
	# 青い力が砕け散る
	shards(b_front, origin, a, 1.1, 120, 41, 980.0, 7.0, RBMHeroFx.C_PALE, RBMHeroFx.C_BLUE, 180.0)
	sparks(b_front, origin, a, 1.0, 180, 47, 1250.0, RBMHeroFx.C_PALE, RBMHeroFx.C_CYAN, 0.0, TAU, 120.0, 2.2)
	sparks(b_front, origin, a, 1.2, 200, 53, 1120.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 150.0, 2.6)
	rocks(b_mix, foot + Vector2(0, -2), a, 1.3, 30, 59, 800.0, 9.0)
	embers(b_front, Rect2(-20, 130, 680, 220), a, 220, 61, 280.0, RBMHeroFx.C_RED, RBMHeroFx.env(a, .4, .8, float(T.duration) - float(T.release) - .23, float(T.duration) - float(T.release) - .01), 2.4, 20.0)
	var hero: Dictionary = view["hero"]
	if a < .15:
		hero["flash"] = 1.0 - RBMHeroFx.ramp(a, .05, .15)
		hero["flash_col"] = Color(.02, .0, .04)
	var lit := RBMHeroFx.env(a, 0.0, .1, .5, 1.0)
	ally_light(maxf(lit, .35 * RBMHeroFx.env(a, .4, .7, 1.4, 1.6)), RBMHeroFx.C_RED, maxf(lit, .6 * RBMHeroFx.env(a, .4, .7, 1.4, 1.6)))
	view["hero"]["lit_side"] = 0.0
	view["shake"] += hit_shake(a, 18.0, 70.0, .95)

## 覚醒の完了（2段階目）: 体から黒紅の炎が放射状に噴き出して画面いっぱいに広がり、地面にひびが走る。
func _complete(a: float) -> void:
	var chest := foot + Vector2(0, -60)
	var bf := 1.0 - RBMHeroFx.ramp(a, .5, .9)
	blast2.visible = bf > 0.0
	if blast2.visible:
		var center := foot + Vector2(0, -44)
		var data := blobs(center, a, 48, 23, 480.0, 240.0, 104.0, 140.0, .62, 0.0, 6.2)
		show_blast(blast2, data, a, {"flow": a * .22, "cool": .06 + RBMHeroFx.ramp(a, .2, 1.1) * .26, "erode": RBMHeroFx.ramp(a, .36, 1.02), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 40.0, "radial_heat": .36, "heat_center": w(center), "heat_radius": 430.0 * RBMHeroFx.burst(a, 6.2), "erode_radial": 220.0, "tone_cap": .8})
	var cf := 1.0 - RBMHeroFx.ramp(a, .7, 1.25)
	cracks.visible = cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(foot + Vector2(0, 2)), "reveal": 560.0 * RBMHeroFx.burst(a, 5.0), "fade": cf})
	refract_wave(foot, a, .7, 600.0, 5.2, .022)
	sparks(b_back, chest, a, 1.0, 170, 71, 1100.0, RBMHeroFx.C_ROSE, RBMHeroFx.C_RED, 0.0, TAU, 160.0, 2.4)
	view["shake"] += hit_shake(a, 13.0, 84.0, .6)
	var lit := RBMHeroFx.env(a, 0.0, .05, .3, .7)
	ally_light(lit, RBMHeroFx.C_RED, lit)
	view["hero"]["lit_side"] = 0.0
