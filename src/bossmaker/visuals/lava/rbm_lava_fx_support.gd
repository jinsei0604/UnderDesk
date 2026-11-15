extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/pre_support.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人・支援（2026-11-14 ユーザー「支援は適当にいいものがあれば」）。立ち姿 → 支援のポーズ（1回だけ切り替え）→ 立ち姿。
## 回復（身をかがめて溜める姿＝全体の2枚目）: 足元に溶岩が湧き、2本の溶岩の流れが脚を伝って炉へ吸い込まれる → 炉が明るく燃え、体の割れ目が光る（湯気が立つ）。
## 強化（両腕を広げて炉を開く姿＝全体の3枚目）: 炉に熱が集まり、背の煙突の口から火柱が噴き上がる・足元から溶岩が跳ねる → 体の縁が赤く光る。
## 煙突は絵から測った口の位置（2026-11-15 ユーザー「覚醒前の強化のマグマの位置がボスの体に合っていない」: 覚醒前の絵は煙突が1本だけ・
## 覚醒後は2本で高さも違うのに、頭の上の左右に2本出していた）。覚醒前は左の穴のあいた丸い突起からも火の粉。
## 覚醒後（post_support.gd）は溶岩の色のオーラも燃え上がる。

const T := {"pose": 0.20, "flow": 0.30, "gather": 0.55, "impact": 1.25, "back": 1.95, "end": 2.50}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
const SUPPORT_POSE := 9
## 強化のポーズ（全体の3枚目）の煙突の口の中心（絵の画素）。覚醒前 pre_all/03・覚醒後 post_all/03 を拡大して測った
const STACK_MOUTHS := {"pre": [Vector2(188, 60)], "post": [Vector2(179, 51), Vector2(204, 47)]}
const VENT_PRE := Vector2(164, 69)

var awakened := false
var heal := true

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var pool: ColorRect
var rising: ColorRect
var steam: ColorRect
var stacks: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func extra_poses() -> Dictionary:
	return {SUPPORT_POSE: ["post_all" if awakened else "pre_all", 2 if heal else 3]}

func pose_keys() -> Array:
	return [[0.0, 0], [T.pose, SUPPORT_POSE], [T.back, 0]]

func _build() -> void:
	b_back = batch(back, false)
	pool = molten_quad(back, {"seed": 6.0, "squash": 0.3, "glow": 0.6})
	steam = blast_quad(back, SMOKE, SMOKE, {"amp": 16., "k": .07, "seed": 2.2, "glow": 0.0, "glow_r": 16.})
	for i in range(2):
		stacks.append(eruption_quad(back, {"seed": 5.0 + i * 3.0, "smoke": 0.35}))
	rising = molten_quad(front, {"seed": 9.0, "glow": 0.7})
	b_front = batch(front, false)
	b_add = batch(front)

## 炉の口（絵の中の明るい炉の位置。支援のポーズの中心から）
func _furnace() -> Vector2:
	return at_seq("post_all" if awakened else "pre_all", 2 if heal else 3, "center", 0, 8)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var a := t - T.impact
	var ground := HOME + Vector2(2, 4)
	var ch := RBMHeroFx.ramp(t, T.gather, T.impact)
	var on := RBMHeroFx.env(t, T.flow, T.flow + 0.3, T.back - 0.2, T.end - 0.1)
	view["dim"] = 0.28 * RBMHeroFx.env(t, T.pose, T.gather, T.back, T.end)
	view["dim_col"] = Color(0.05, 0.01, 0.0)
	var furnace := _furnace()
	if heal:
		# 足元に溶岩が湧く（小さな溜まり）
		var pb: Array = []
		var g := RBMHeroFx.ramp(t, T.flow, T.flow + 0.4) * (1.0 - RBMHeroFx.ramp(t, T.back, T.end))
		if g > 0.0:
			for k in range(5):
				var ang := -PI + float(k) / 4.0 * PI
				pb.append(Vector4(ground.x + cos(ang) * 30.0 * g, ground.y + 2.0, 9.0 * g + 2.0, 0.8))
			pb.append(Vector4(ground.x, ground.y + 2.0, 20.0 * g, 0.9))
			show_molten(pool, pb, {"flow": t, "heat": 0.7 + 0.3 * ch})
		else:
			pool.visible = false
		# 溜まりから溶岩の玉が次々に浮き上がり、弧を描いて炉へ吸い込まれる（溶けた液体の玉。線にしない）
		var ff := 1.0 - RBMHeroFx.ramp(a, 0.0, 0.25)
		var rb: Array = []
		for k in range(10):
			var ph := fmod((t - T.flow) * 1.4 + k / 10.0, 1.0)
			if t < T.flow + k * 0.06 or ff <= 0.0:
				continue
			var side := -1.0 if k % 2 == 0 else 1.0
			var root := ground + Vector2(side * (18.0 + 14.0 * RBMHeroFx.r(k, 5)), 0)
			var ctrl := Vector2(furnace.x + side * (34.0 + 10.0 * RBMHeroFx.r(k, 6)), (root.y + furnace.y) * 0.5 + 6.0)
			var u := ph * ph * (3.0 - 2.0 * ph)
			var pos := root.lerp(ctrl, u).lerp(ctrl.lerp(furnace, u), u)
			rb.append(Vector4(pos.x, pos.y, (4.5 + 2.0 * RBMHeroFx.r(k, 7)) * sin(PI * minf(1.0, ph * 1.15)) * ff, 1.0))
		show_molten(rising, rb, {"flow": t * 2.0, "heat": 1.0})
		embers(b_add, Rect2(furnace.x - 16, furnace.y - 12, 32, 24), t, 16, 7, 30.0, HOT, ch * ff, 2.0, 4.0)
		# 炉が明るく燃え、湯気が立つ
		var sa := a + 0.2
		var sf := 1.0 - RBMHeroFx.ramp(t, T.back, T.end)
		steam.visible = sa >= 0.0 and sf > 0.0
		if steam.visible:
			show_blast(steam, blobs(furnace + Vector2(0, -44 - sa * 14.0), sa * 0.4, 12, 9, 50.0, 22.0, 16.0, 60.0, .1, 0.0, 2.0), sa, {"flow": sa * .15, "cool": 0.0, "erode": RBMHeroFx.ramp(sa, 0.6, 1.2), "fade": sf * RBMHeroFx.ramp(sa, 0.0, 0.4) * 0.5, "erode_noise": .6, "tone_cap": .6})
		embers(b_add, Rect2(HOME.x - 50, HOME.y - 110, 100, 110), t, 30, 9, 80.0, EMBER, RBMHeroFx.env(a, -0.1, 0.1, 0.5, 0.9), 2.0, 6.0)
		view["hero"]["lit"] = 0.2 * ch + 0.3 * RBMHeroFx.env(a, 0.0, 0.08, 0.45, 0.85)
		view["hero"]["lit_col"] = HOT
		view["hero"]["flash"] = 0.15 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = EMBER
		for s in stacks:
			(s as ColorRect).visible = false
	else:
		pool.visible = false
		steam.visible = false
		rising.visible = false
		# 炉に熱が集まる
		inward(b_add, furnace, t, 24, 11, 6.0, 90.0, 1.0, HOT, ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.05)), 2.4)
		embers(b_add, Rect2(HOME.x - 60, HOME.y - 100, 120, 100), t, 30, 13, 60.0, EMBER, ch, 2.0, 6.0)
		# 背の煙突の口から火柱が噴き上がる（口の位置は絵から測った。柱は体の後ろに置き、口の縁の上から見える）
		var mouths: Array = STACK_MOUTHS["post" if awakened else "pre"]
		for i in range(2):
			if i >= mouths.size():
				(stacks[i] as ColorRect).visible = false
				continue
			var top := px(mouths[i])
			var st := a - i * 0.06
			var sg := RBMHeroFx.ramp(st, 0.0, 0.12) * (1.0 - RBMHeroFx.ramp(st, 0.45, 0.8))
			# 口の幅に合わせた太さ・上へ広がる炎（細い棒に見せない）
			show_eruption(stacks[i], top + Vector2(0, 2), 6.0, (62.0 if awakened else 56.0) + 8.0 * sin(t * 9.0 + i), sg, {"flow": t * 1.4 + i, "heat": 1.0, "flare": 0.15, "round_top": 1.0, "smoke": 0.1, "spread": 1.1})
			if st >= 0.0:
				lava_drops(b_front, top + Vector2(0, -18), st, 0.8, 8, 21 + i, 200.0, 2.2, -PI * 0.5, 0.9, 380.0)
		if not awakened:
			# 左の穴のあいた丸い突起からも火の粉が噴く
			embers(b_add, Rect2(px(VENT_PRE).x - 6, px(VENT_PRE).y - 40, 12, 40), t, 10, 17, 70.0, HOT, RBMHeroFx.env(a, 0.0, 0.05, 0.4, 0.8), 2.0, 4.0)
		# 足元から熱の輪・体の縁が赤く光る
		if a >= 0.0:
			lava_drops(b_front, ground + Vector2(-30, -2), a, 0.7, 6, 41, 160.0, 2.0, -PI * 0.5, 0.9, 380.0)
			lava_drops(b_front, ground + Vector2(30, -2), a - 0.05, 0.7, 6, 43, 160.0, 2.0, -PI * 0.5, 0.9, 380.0)
			set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.12)), "flash_col": Vector3(1.0, 0.7, 0.4)})
		view["hero"]["lit"] = 0.2 * ch + 0.4 * RBMHeroFx.env(a, 0.0, 0.06, 0.55, 0.85)
		view["hero"]["lit_col"] = ORANGE
		view["hero"]["flash"] = 0.22 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = HOT
		view["shake"] += hit_shake(a, 6.0, 70.0, 0.35)
	if awakened:
		view["hero"]["sun_aura"] = 1.0 + (1.3 if not heal else 0.6) * RBMHeroFx.env(a, 0.0, 0.1, 0.4, 0.9)
	b_back.commit(); b_add.commit(); b_front.commit()
