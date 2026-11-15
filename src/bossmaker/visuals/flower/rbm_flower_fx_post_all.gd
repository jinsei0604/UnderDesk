extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/post_all.gd でユーザーが採用した内容をそのまま移した。
## 喪華のカラー女王・覚醒後全体「喪華の勅令」（2026-11-13 質を上げた版。構成は採用済み: 世界が喪色に沈む → 花びらが四人を囲む
## → 蔦が立ち上がる → 蕾が膨らむ → 一斉に開花 → 喪色の光の解放）:
## 世界が沈む → 腕を寄せて溜めると、女王の背に巨大な喪華が開く（立体の花、ゆっくり回る）。無数の暗い花びらが四人を囲んで回る
## → 地面から蔦が立ち上がって四人それぞれに螺旋に巻き付き、胸元に暗い蕾が膨らむ（立体の花の閉じた形）
## → 腕を開き花裳を広げると、背の喪華から花びらの波が四人へ押し寄せ、蕾が順に開花（当たり。咲いた所から喪色の光の柱）
## → 咲いた花が一斉に弾け、幻想的で禍々しい喪色の光が画面全体へ解放される（最後の一撃）→ 余韻（暗い花びらが降る）。

const T := {"dark": 0.20, "charge": 0.45, "halo": 0.55, "vines": 1.05, "buds": 1.55, "wave": 2.35, "bloom": 2.60, "burst": 2.98, "settle": 3.70, "end": 5.60}
const MAUVE := Color("#8a2a4a")
const DEEP := Color("#4a0e26")
const PINK := Color("#e8a8c0")
const BLUSH := Color("#c06080")
const VIOLET := Color("#b060e0")
const PALE := Color("#fff0f4")
const DARKBLOOM := ["#0c0408", "#1e0814", "#3a0c22", "#5a1a32", "#8a2a4a", "#c06080", "#e8b8c8", "#fff0f4"]
const MOURN := ["#08020a", "#160412", "#26081c", "#3a0e28", "#521634", "#6e2244", "#8e3458", "#b45276"]
## 背の喪華（暗い深紅）
const MOURN_D := ["#060108", "#10030c", "#1c0614", "#2a0a1e", "#3e1028", "#561a38", "#72284c", "#923a62"]
## 四人の胸元に咲く花（喪華より少し明るい）
const MOURN_L := ["#10040c", "#24081a", "#3c0e2a", "#58183c", "#7a2a52", "#9e406a", "#c4648a", "#e696b0"]
## 蔦の色 [縁, 本体, 本体の明るい側, 照り, 葉の縁, 葉, 葉の明るい側]
const VINE_COLS := [Color("#1a0c12"), Color("#3e2432"), Color("#6a4252"), Color("#8c6474"), Color("#1c1a14"), Color("#4a4a30"), Color("#7a7a50")]
const OUTLINE := Color("#1a0610", 0.85)

var b_back: RBMHeroFxBatch
var b_far: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var halo: ColorRect
var flowers: Array = []
var rings: Array = []
var final_share := 0.4

func duration() -> float:
	return T.end

func impact() -> float:
	return T.burst

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.bloom) + i * 0.06, i])
	return out

func stops() -> Array:
	return [[T.burst, 0.14]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.wave, 3], [T.settle, 4]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25 + Vector2(0, -20)

func _build() -> void:
	b_back = batch(back, false)
	halo = bloom_quad(back, MOURN_D, [], {"petals": 12.0, "seed": 9.0, "outline_col": Vector3(.05, .01, .03), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8), "tilt": Vector3(8., 24., 44.)})
	blast = blast_quad(back, DARKBLOOM, DARKBLOOM, {"amp": 34., "k": .05, "seed": 6.1, "glow": .7, "glow_col": Vector3(.8, .2, .45), "glow_r": 50.})
	b_far = batch(back, false)
	b_glow = batch(back)
	for i in range(4):
		flowers.append(bloom_quad(front, MOURN_L, [], {"petals": 10.0, "seed": 30.0 + i, "outline_col": Vector3(.05, .01, .03), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8)}))
	for i in range(3):
		rings.append(ring_quad(front, ["#5a1a32", "#c06080", "#e8b8c8", "#fff0f4"], {"squash": .34, "breakup": .5, "seed": 1.5 + i * 2.6, "glow": .4, "glow_col": Vector3(.8, .2, .45)}))
	b_front = batch(front, false)
	b_add = batch(front)

## 閉じた蕾（下が丸く、先がすぼまる。花弁3枚と萼）
func bud_shape(b: RBMHeroFxBatch, c: Vector2, k: float) -> void:
	var s := 0.4 + 0.6 * k
	var cols: Array = MOURN_L
	var dark := Color(cols[1])
	var mid := Color(cols[4])
	var lite := Color(cols[6])
	for side in [-1.0, 1.0]:
		var ang: float = -PI * 0.5 + side * 0.32
		petal(b, c + Vector2(side * 1.0, 1.0), ang, 17.0 * s, 10.0 * s, Color("#1a0610"), Color("#1a0610"))
		petal(b, c + Vector2(side * 1.0, 0.0), ang, 15.0 * s, 8.4 * s, dark, mid)
	petal(b, c + Vector2(0, 1.5), -PI * 0.5, 20.0 * s, 11.0 * s, Color("#1a0610"), Color("#1a0610"))
	petal(b, c, -PI * 0.5, 18.0 * s, 9.4 * s, mid, lite)
	# 萼（根元の緑の葉）
	for side in [-1.0, 1.0]:
		petal(b, c + Vector2(0, 2), PI * 0.5 + side * 0.9, 7.0 * s, 4.0 * s, Color("#1c1a14"), Color("#4a4a30"))

func _step(t: float) -> void:
	b_back.reset(); b_far.reset(); b_glow.reset(); b_add.reset(); b_front.reset()
	var center := _center()
	var ch := RBMHeroFx.ramp(t, T.charge, T.wave)
	var a := t - T.burst
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.dark + 0.3, 0.6], [T.wave, 0.78], [T.burst, 0.84], [T.burst + 0.3, 0.5], [T.end, 0.18]])
	view["dim_col"] = Color(0.04, 0.0, 0.03)
	var after := 1.0 - RBMHeroFx.ramp(a, 0.0, 0.25)
	# 女王の背に巨大な喪華が開く
	var ho := RBMHeroFx.ramp(t, T.halo, T.halo + 0.9)
	var hf := 1.0 - RBMHeroFx.ramp(a, 0.4, 1.1)
	if ho > 0.0 and hf > 0.0:
		show_bloom(halo, HOME + Vector2(8, -66), 104.0, {"open": ho, "rot": t * 0.08, "squash": 0.92, "glow": 0.2 * ho + 0.5 * RBMHeroFx.env(t, T.wave - 0.3, T.wave, T.wave + 0.1, T.wave + 0.5), "fade": hf})
		inward(b_add, HOME + Vector2(8, -66), t, 60, 7, 10.0, 160.0, 1.4, PINK, ch * (1.0 - RBMHeroFx.ramp(t, T.wave, T.wave + 0.1)), 2.0)
	else:
		halo.visible = false
	# 無数の暗い花びらが四人を囲んで回る
	petal_cloud(b_front, center + Vector2(0, -4), t, 70, 3, 150.0, 4.5, DEEP, PINK, RBMHeroFx.ramp(t, T.charge, T.charge + 0.5) * after, "orbit", 0.4, OUTLINE)
	view["hero"]["lit"] = 0.4 * ch * (1.0 - RBMHeroFx.ramp(t, T.wave, T.wave + 0.3))
	view["hero"]["lit_col"] = BLUSH
	# 地面から蔦が立ち上がり、四人それぞれに螺旋に巻き付く。胸元に蕾が膨らみ → 順に開花
	for i in range(4):
		var q: ColorRect = flowers[i]
		if not present[i]:
			q.visible = false
			continue
		var foot: Vector2 = targets[i]
		var chest := target_chest(i)
		var g := RBMHeroFx.ramp(t, T.vines + i * 0.08, T.vines + i * 0.08 + 0.5) * after
		coil_vine(b_far, b_front, foot + Vector2(0, -1), 44.0, 15.0, 2.4, g, 3.0, RBMHeroFx.ramp(t, T.buds, T.bloom) * 0.6, VINE_COLS, i * 1.3)
		for s in [-1.0, 1.0]:
			var root: Vector2 = foot + Vector2(s * 24.0, 3)
			vine_rich(b_front, root, root + Vector2(s * 10.0, -30), chest + Vector2(s * 8.0, -10), RBMHeroFx.ramp(t, T.vines + 0.1 + i * 0.08, T.vines + 0.6 + i * 0.08) * after, 3.6, 17 + i * 5 + int(s), VINE_COLS)
		var bt := float(T.bloom) + i * 0.06
		var bud := RBMHeroFx.ramp(t, T.buds + i * 0.06, T.buds + i * 0.06 + 0.5)
		var open := RBMHeroFx.ramp(t, bt, bt + 0.2)
		var o := 0.25 + 0.75 * (1.0 - pow(1.0 - open, 3.0))
		var crumble := RBMHeroFx.ramp(a, 0.0, 0.25)
		if open > 0.0 and crumble < 1.0:
			show_bloom(q, chest + Vector2(0, -2), 23.0, {"open": o, "rot": i * 0.8 + t * 0.3, "squash": 0.7, "glow": 0.35 * open, "crumble": crumble, "fade": 1.0})
		else:
			q.visible = false
			# 蕾: しずく形の花弁を重ねた閉じた形が膨らむ（尖った冠の形にしない）
			if bud > 0.0 and a < 0.0:
				bud_shape(b_front, chest + Vector2(0, 4), bud)
		var st := t - bt
		if st >= 0.0:
			sparks(b_add, chest, st, 0.4, 30, 23 + i, 300.0, PALE, BLUSH, 0.0, TAU, 80.0, 1.6)
			# 咲いた所から喪色の光の柱
			var pil := RBMHeroFx.env(st, 0.0, 0.06, 0.3, 0.7) * after
			if pil > 0.0:
				var top := Vector2(foot.x, foot.y - 190)
				b_glow.quad(foot + Vector2(-14, 0), top + Vector2(-8, 0), top, foot, Color(VIOLET, 0.0), Color(PINK, 0.0), Color(PALE, 0.32 * pil), Color(VIOLET, 0.4 * pil))
				b_glow.quad(foot, top, top + Vector2(8, 0), foot + Vector2(14, 0), Color(VIOLET, 0.4 * pil), Color(PALE, 0.32 * pil), Color(PINK, 0.0), Color(VIOLET, 0.0))
	var evs := []
	for i in range(4):
		evs.append([float(T.bloom) + i * 0.06, i])
	ally_hits(t, evs, 0.8)
	# 背の喪華から花びらの波が四人へ押し寄せる
	petal_sweep(b_front, t - T.wave, 150, 71, HOME.x - 20.0, 60.0, 300.0, 1.0 - RBMHeroFx.ramp(t - T.wave, 0.5, 0.9), [DEEP, PINK, OUTLINE], 760.0, 5.0)
	# 咲いた花が一斉に弾け、喪色の光が画面全体へ解放される
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.7, 1.25)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(center, a, 44, 33, 520.0, 260.0, 108.0, 140.0, .55, 0.0, 6.0), a, {"flow": a * .22, "cool": .05 + RBMHeroFx.ramp(a, .25, 1.2) * .22, "erode": RBMHeroFx.ramp(a, .4, 1.2), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .55, "amp": 36.0, "radial_heat": .45, "heat_center": w(center), "heat_radius": 460.0 * RBMHeroFx.burst(a, 6.0), "erode_radial": 220.0, "tone_cap": .96})
		refract_wave(center, a, 0.9, 680.0, 4.6, 0.035)
	if a >= 0.0:
		petal_cloud(b_front, center, a, 170, 41, 400.0, 6.5, DEEP, PINK, 1.0, "burst", 0.45, OUTLINE)
		for i in range(4):
			if present[i]:
				shards(b_front, target_chest(i), a, 0.8, 14, 51 + i, 260.0, 3.0, VINE_COLS[2], VINE_COLS[0], 260.0)
		view["shake"] += hit_shake(a, 16.0, 70.0, 0.6)
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.4, 0.9), BLUSH, 0.0)
		set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.18)), "flash_col": Vector3(1.0, 0.75, 0.9), "chroma": 0.004 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.4))})
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.2, 0.6) * 1.2)
	for i in range(3):
		show_ring(rings[i], center, a - i * 0.08, 0.8, 600.0, 9.0 - i * 2.0, 5.0, 0.03)
	petal_cloud(b_front, Vector2(240, 140), t, 34, 51, 200.0, 4.5, DEEP, PINK, RBMHeroFx.env(a, 0.6, 1.0, T.end - T.burst - 0.5, T.end - T.burst), "fall", 0.45, OUTLINE)
	set_post({"desat": 0.4 * ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3)), "vig": 0.5 * ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.5)) + 0.15, "vig_col": Vector3(.03, .0, .02), "vig_r": .25})
	b_back.commit(); b_far.commit(); b_glow.commit(); b_add.commit(); b_front.commit()
