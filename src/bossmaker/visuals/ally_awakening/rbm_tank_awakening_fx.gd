extends RBMLavaFxBase
## ハンマー使いの覚醒「熔鉱・地裂」（2026-11-19 第2版。表示専用）。時刻は T（音の build もここを読む）。座標は論理ドット（足元からの相対）。
## 2026-11-19 ユーザー「全部ボスとのつながりが分かるように」→ 対応するボス「熔鉱炉の番人」の溶岩（溶岩溜まり magma・噴き上がる柱 eruption・
## 溶岩の飛沫・溶岩の色）を入れた。部品は溶岩のボスと同じもの（RBMLavaFxBase）。
## 意味: 立つ → ハンマーを肩に担いで力を込めると、ハンマーの頭が炉の中の鉄のように赤く焼け、足元の床に溶岩色のひびが脈打つ
## → 頭上へ振りかぶって止まる（ハンマーが白熱）→ 叩きつけ: 床が割れて溶岩が噴き上がり、溶岩溜まりが広がり、飛沫と岩が飛ぶ・衝撃の輪
## → 構え直す間に溶岩が冷えて黒い岩になり、煙が上がる。
## 三角のトゲ・星形・平たい円は使わない。

const T := {"heft": 0.3, "raise": 1.25, "release": 1.6, "recover": 2.55, "settle": 3.15, "end": 3.6}
## ハンマーの頭（frames/08＝肩に担ぐ、04＝頭上、05＝叩きつけ。足元からの相対、論理ドット）
const HAMMER_SHOULDER := Vector2(-18, -40)
const HAMMER_UP := Vector2(-15, -49)
const IMPACT := Vector2(28, 0)
const RED := Color("#c8401a")
const EMBER := Color("#ff9a24")
const HOT := Color("#ffe08a")
const WHITE_HOT := Color("#fff8e0")
## 溶岩色のひび（暗い赤 → 白）
const CRACK_PAL := ["#3a1208", "#b0401a", "#ffb040", "#fff8e0"]

var cracks: ColorRect
var pool: ColorRect
var geyser: ColorRect
var ring: ColorRect
var b_glow_back: RBMHeroFxBatch
var b_body: RBMHeroFxBatch
var b_add: RBMHeroFxBatch

func _build() -> void:
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(CRACK_PAL), "seed": 7.3, "squash": .32, "line_w": .05, "glow_col": Vector3(1., .45, .12), "glow": .5})
	b_glow_back = batch(back)
	pool = magma_quad(back, {"seed": 3.0})
	geyser = eruption_quad(back, {"seed": 2.0})
	ring = ring_quad(back, RBMHeroFx.R_AMBER, {"squash": .3, "breakup": .5, "seed": 2.9, "glow": .45, "glow_col": Vector3(1., .5, .15)})
	b_body = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_glow_back.reset(); b_body.reset(); b_add.reset()
	var ra := t - T.release
	var hit := foot + IMPACT
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.heft + 0.4, 0.36], [T.raise, 0.46], [T.release - 0.02, 0.54], [T.release + 0.3, 0.32], [T.end, 0.0]])
	view["dim_col"] = Color(0.05, 0.025, 0.02)
	# 力を込める: ハンマーの頭が赤く焼ける → 頭上で白熱。火の粉が立ちのぼる
	var heat := RBMHeroFx.ramp(t, T.heft + 0.1, T.release)
	if t >= T.heft and ra < 0.0:
		var head := foot + (HAMMER_SHOULDER if t < T.raise else HAMMER_UP)
		var beat := 0.85 + 0.15 * sin(t * 18.0)
		RBMHeroRooftop.glow(b_add, head, (4.0 + 5.0 * heat) * beat, Color(RED.lerp(EMBER, heat), 0.25 + 0.4 * heat))
		RBMHeroRooftop.glow(b_add, head, 2.0 + 2.0 * heat, Color(EMBER.lerp(WHITE_HOT, heat), 0.5 + 0.4 * heat))
		embers(b_add, Rect2(head.x - 6, head.y - 4, 12, 8), t, 10, 31, 26.0, Color(EMBER, 1.0), heat, 1.3, 4.0)
	# 叩きつけた所から床に溶岩色のひびが走り → 冷えて消える（溜めの間の足元のひびは白い星形に見えたので出さない）
	var cf := (1.0 - RBMHeroFx.ramp(t, T.recover, T.end - 0.1)) if ra >= 0.0 else 0.0
	cracks.visible = cf > 0.0
	if cracks.visible:
		sp(cracks, {"center": w(hit + Vector2(0, 1)), "reveal": 16.0 + 42.0 * RBMHeroFx.burst(ra, 7.0), "fade": cf, "glow": 0.3 + 0.4 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 1.0))})
	if ra < 0.0:
		pool.visible = false
		geyser.visible = false
		b_glow_back.commit(); b_body.commit(); b_add.commit()
		return
	# 叩きつけ: 溶岩が噴き上がる（太く短い柱。頭は丸く煙）→ 沈む
	var up := RBMHeroFx.burst(ra, 9.0) * (1.0 - RBMHeroFx.ramp(ra, 0.3, 0.6))
	show_eruption(geyser, hit + Vector2(0, 1), 6.0, 50.0, up, {"flow": ra * 1.5, "fade": 1.0 - RBMHeroFx.ramp(ra, 0.32, 0.55), "soft_base": 1.0})
	# 溶岩溜まりが広がり、だんだん冷えて黒い岩になる
	var spread := RBMHeroFx.burst(ra, 6.0)
	show_pool(pool, hit + Vector2(0, 1), 8.0 + 18.0 * spread, {"crust": 0.45 * RBMHeroFx.ramp(ra, 0.5, 1.6), "heat": 1.0 - 0.5 * RBMHeroFx.ramp(ra, 0.6, 1.8), "flow": ra * 0.6,
		"fade": 1.0 - RBMHeroFx.ramp(t, T.settle, T.end - 0.05), "squash": 0.3})
	show_ring(ring, hit, ra, 0.6, 76.0, 4.0, 6.0, 0.0)
	# 飛沫と岩・火の粉・煙
	lava_drops(b_body, hit + Vector2(0, -3), ra, 0.9, 18, 41, 170.0, 1.6, -PI * 0.5, PI * 0.9, 380.0)
	rocks(b_body, hit, ra, 0.8, 10, 43, 150.0, 2.2, 2.0)
	sparks(b_add, hit + Vector2(0, -2), ra, 0.6, 30, 45, 190.0, WHITE_HOT, EMBER, -PI * 0.5, PI * 1.1, 260.0, 1.3)
	embers(b_add, Rect2(hit.x - 20, hit.y - 40, 40, 36), t, 18, 47, 40.0, Color(EMBER, 1.0), RBMHeroFx.ramp(ra, 0.1, 0.3) * (1.0 - RBMHeroFx.ramp(t, T.settle, T.end)), 1.4, 5.0)
	_smoke(hit, ra)
	var g := 1.0 - RBMHeroFx.ramp(ra, 0.0, 0.35)
	if g > 0.0:
		RBMHeroRooftop.glow(b_add, hit + Vector2(0, -4), 12.0 * g, Color(HOT, 0.45 * g))
	view["hero"]["flash"] = 0.6 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.2))
	view["hero"]["flash_col"] = WHITE_HOT
	view["hero"]["lit"] = 0.5 * (1.0 - RBMHeroFx.ramp(ra, 0.25, 1.6))
	view["hero"]["lit_col"] = EMBER
	set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.1))})
	b_glow_back.commit(); b_body.commit(); b_add.commit()

## 冷えていく溶岩から上がる煙（暗い灰の柔らかい粒がゆっくり上る）
func _smoke(hit: Vector2, ra: float) -> void:
	var on := RBMHeroFx.ramp(ra, 0.3, 0.7) * (1.0 - RBMHeroFx.ramp(ra, 1.4, T.end - T.release))
	if on <= 0.0:
		return
	for i in range(10):
		var q := fmod(ra * (0.35 + 0.2 * RBMHeroFx.r(i, 51)) + RBMHeroFx.r(i, 52), 1.0)
		var p := hit + Vector2((RBMHeroFx.r(i, 53) - 0.5) * 36.0 + sin(ra * 2.0 + float(i)) * 3.0, -2.0 - q * 34.0)
		RBMHeroRooftop.glow(b_glow_back, p, 3.0 + 4.0 * q, Color(0.16, 0.13, 0.13, 0.35 * on * sin(q * PI)))
