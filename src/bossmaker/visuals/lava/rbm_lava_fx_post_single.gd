extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/post_single.gd でユーザーが採用した内容をそのまま移した。
## 噴界炉の巨神・覚醒後単体「熔槌の正拳」（2026-11-14 作り直し。ユーザー案: 手にマグマを集めてパーティー側に殴ったら大爆発が起きる。
## 前の版は派手さが足りず、マグマの絵が見切れていた）:
## 構え（足元に溶岩溜まり）→ 拳を振りかぶると、足元の溶岩が3本の流れになって拳へ集まり、拳に大きな溶岩の玉ができる（炉心が唸る）
## → パーティー側へ殴ると、溶岩の玉が拳から撃ち出されて相手へ飛ぶ（火の尾）→ 着弾で大爆発（最後の一撃: マグマの大爆発・溶岩溜まり・飛沫・岩・溶岩の塊・衝撃波）
## → 振り抜き → 構えへ。爆発は画面の中に収める（絵の上端が切れないように）。

const T := {"windup": 0.30, "gather_end": 0.95, "punch": 1.00, "boom": 1.22, "follow": 1.36, "back": 2.00, "end": 2.80}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
const BALL_R := 20.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var aura_pool: ColorRect
var pool: ColorRect
var ball: ColorRect
var geyser: ColorRect
var smoke: ColorRect
var boom: ColorRect
var rings: Array = []
var final_share := 0.5

func duration() -> float:
	return T.end

func impact() -> float:
	return T.boom

func stops() -> Array:
	return [[T.boom, 0.13]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.punch, 3], [float(T.follow) + 0.2, 4], [T.back, 1]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"], [T.punch - 0.02, Vector2.ZERO, "snap"], [T.punch + 0.05, Vector2(-12, 0), "out"], [T.back, Vector2(-12, 0), "snap"], [T.back + 0.25, Vector2.ZERO, "out"]]

func _build() -> void:
	b_back = batch(back, false)
	aura_pool = magma_quad(back, {"seed": 1.0})
	pool = magma_quad(back, {"seed": 2.0})
	smoke = blast_quad(back, SMOKE, SMOKE, {"amp": 22., "k": .07, "seed": 2.5, "glow": 0.0, "glow_r": 20.})
	boom = blast_quad(back, LAVA, LAVA, {"amp": 34., "k": .06, "seed": 4.6, "glow": .8, "glow_col": Vector3(1., .5, .15), "glow_r": 44.})
	# 爆炎を描く範囲を縮めない（縮めると上や横が真っ直ぐ切れて見えた）
	boom.set_meta("blast_reach", Vector3.ZERO)
	geyser = magma_quad(front, {"seed": 4.0})
	ball = magma_quad(front, {"seed": 6.0})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .4, "breakup": .5, "seed": 3.0 + i * 2.2, "glow": .45, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var hit := target_chest(3)
	var ground: Vector2 = targets[3] + Vector2(6, 2)
	var off: Vector2 = body.get("off", Vector2.ZERO)
	var a2 := t - T.boom
	# 足元の溶岩溜まり（覚醒後の巨神は常に灼けた地面に立つ）
	show_pool(aura_pool, HOME + off + Vector2(4, 4), 48.0, {"squash": 0.3, "crust": 0.45, "heat": 0.85, "flow": t})
	# 溜め: 足元の溶岩が3本の流れになって拳へ集まり、拳に溶岩の玉ができる
	var ch := RBMHeroFx.ramp(t, T.windup, T.gather_end)
	var fist := at("top", 2, 26, 22)
	var flow_fade := 1.0 - RBMHeroFx.ramp(t, T.punch - 0.06, T.punch + 0.04)
	if t >= T.windup and flow_fade > 0.0:
		for k in range(3):
			var root := HOME + off + Vector2(-34 + k * 30, 6)
			var ctrl := (root + fist) * 0.5 + Vector2(-30 + k * 22, -10)
			lava_ribbon(b_front, root, ctrl, fist, RBMHeroFx.ramp(t, T.windup + k * 0.06, T.windup + 0.35 + k * 0.06), 5.0 - k * 0.6, t + k, flow_fade)
		inward(b_add, fist, t, 50, 5, 4.0, 90.0, 1.4, HOT, ch * flow_fade, 2.4)
		embers(b_add, Rect2(fist.x - 20, fist.y - 16, 40, 32), t, 30, 3, 60.0, ORANGE, ch * flow_fade * 1.4, 2.0, 4.0)
	view["hero"]["lit"] = 0.3 + 0.4 * ch * flow_fade
	view["hero"]["lit_col"] = EMBER
	view["hero"]["lit_side"] = -1.0
	view["dim"] = 0.3 * RBMHeroFx.env(t, T.windup, T.gather_end, T.follow, T.back)
	view["dim_col"] = Color(0.07, 0.02, 0.0)
	# 溶岩の玉: 拳にできる → 殴ると撃ち出されて飛ぶ（火の尾）
	var fly := RBMHeroFx.ramp(t, T.punch, T.boom)
	if t < T.boom and ch > 0.0:
		var start := at("front", 3) if t >= T.punch else fist
		var bp := start.lerp(hit, fly)
		var br := BALL_R * (1.0 - pow(1.0 - ch, 2.0)) * (1.0 + 0.06 * sin(t * 12.0))
		show_lava_ball(ball, bp, br, {"crust": 0.35, "heat": 1.0, "flow": t * 2.0})
		if t >= T.punch:
			b_add.streak(bp + (start - hit).normalized() * 120.0 * minf(1.0, fly * 3.0), bp, br * 1.5, Color(ORANGE, 0.0), Color(HOT, 0.7))
			lava_drops(b_front, bp, fmod(t - T.punch, 0.2), 0.2, 4, 61, 80.0, 2.0, (start - hit).angle(), 0.8, 200.0)
			embers(b_add, Rect2(bp.x - 10, bp.y - 10, 60, 20), t, 20, 63, 30.0, EMBER, 1.0, 2.0, 4.0)
		var pa := t - T.punch
		if pa >= 0.0 and pa < 0.25:
			disc(b_add, at("front", 3), 10.0 * (1.0 - pa / 0.25), Color(WHITE, 0.7 * (1.0 - pa / 0.25)))
			view["shake"] += hit_shake(pa, 8.0, 70.0, 0.25)
	else:
		ball.visible = false
	# 着弾で大爆発
	if a2 >= 0.0:
		show_pool(pool, ground, 86.0 * RBMHeroFx.burst(a2, 7.0), {"squash": 0.32, "crust": RBMHeroFx.ramp(a2, 0.4, 1.4), "heat": 1.0 - 0.4 * RBMHeroFx.ramp(a2, 0.7, 1.4), "flow": t, "fade": 1.0 - RBMHeroFx.ramp(t, T.end - 0.3, T.end)})
		var gg := RBMHeroFx.ramp(a2, 0.0, 0.08) * (1.0 - RBMHeroFx.ramp(a2, 0.35, 0.7))
		show_jet(geyser, ground, Vector2(0, -1), 100.0, 24.0, gg, {"flow": t * 1.4, "heat": 1.0})
		lava_drops(b_front, hit, a2, 1.2, 46, 31, 620.0, 3.6, -PI * 0.5, TAU, 440.0)
		rocks(b_front, ground, a2, 1.1, 26, 33, 620.0, 7.0, 6.0)
		sparks(b_add, hit, a2, 0.9, 120, 35, 800.0, HOT, ORANGE, -PI * 0.5, TAU, 300.0, 2.4)
		disc(b_add, hit, 16.0 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.06)), Color(HOT, 0.7 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.06))))
		set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.12)), "flash_col": Vector3(1.0, 0.7, 0.4)})
		for k in range(6):
			var to := ground + Vector2(-110 + k * 44 + RBMHeroFx.r(k, 41) * 20.0, 14 + RBMHeroFx.r(k, 42) * 40.0)
			var bt := a2 - 0.1 - k * 0.05
			lava_bomb(b_front, b_add, hit + Vector2(0, -20), to, bt, 0.55, 2.5 + RBMHeroFx.r(k, 43) * 2.0, 70.0)
			if bt >= 0.55 and bt < 0.95:
				lava_drops(b_front, to, bt - 0.55, 0.4, 6, 51 + k, 140.0, 1.8, -PI * 0.5, PI * 1.1, 360.0)
	else:
		pool.visible = false
		geyser.visible = false
	var bf := 1.0 - RBMHeroFx.ramp(a2, 0.5, 0.95)
	boom.visible = a2 >= 0.0 and bf > 0.0
	if boom.visible:
		var bc := hit + Vector2(0, -6)
		show_blast(boom, blobs(bc, a2, 32, 11, 230.0, 120.0, 64.0, 70.0, .7, 0.0, 7.4), a2, {"flow": a2 * .3, "cool": .05 + RBMHeroFx.ramp(a2, .15, .8) * .3, "erode": RBMHeroFx.ramp(a2, .3, .9), "fade": bf, "erode_noise": .4, "polar": 1.0, "detail": .55, "radial_heat": .5, "heat_center": w(bc), "heat_radius": 260.0 * RBMHeroFx.burst(a2, 7.4), "erode_radial": 160.0, "tone_cap": .95})
		refract_wave(bc, a2, 0.7, 380.0, 5.0, 0.04)
	var mf := 1.0 - RBMHeroFx.ramp(a2, 0.9, 1.5)
	smoke.visible = a2 >= 0.25 and mf > 0.0
	if smoke.visible:
		show_blast(smoke, blobs(ground + Vector2(0, -50), a2, 16, 13, 90.0, 40.0, 26.0, 90.0, .2, 0.0, 3.0), a2, {"flow": a2 * .2, "cool": 0.0, "erode": RBMHeroFx.ramp(a2, .5, 1.4), "fade": mf * 0.55, "erode_noise": .6, "tone_cap": .7})
	for i in range(3):
		show_ring(rings[i], hit, a2 - i * 0.08, 0.6, 320.0 - i * 70.0, 8.0 - i * 2.0, 5.0, 0.035 * float(i == 0))
	view["shake"] += hit_shake(a2, 24.0, 60.0, 0.6)
	ally_hits(t, [[T.boom, 3]], 1.3)
	if a2 >= 0.0:
		view["allies"][3]["lit"] = 0.6 * RBMHeroFx.env(a2, 0.0, 0.03, 0.3, 0.8)
		view["allies"][3]["lit_col"] = ORANGE
		ally_light(0.4 * RBMHeroFx.env(a2, 0.0, 0.05, 0.3, 0.8), ORANGE, 0.0)
	b_back.commit(); b_add.commit(); b_front.commit()
