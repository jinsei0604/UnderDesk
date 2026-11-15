extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/pre_all.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー・覚醒前全体「開花の祝福」（2026-11-13 改: 花をちゃんとした花に・開花の後にお辞儀）:
## 構え → 両腕を胸に寄せて溜める（光が花の顔へ集まり、足元に白磁の小さな花が順に咲く）
## → 両腕を上へ開くと、四人の足元に巨大な白磁の花が外の段から順に開く（3段の花びら・黄色い芯。四人は大輪の中に立つ）
## → 開ききったところでボスが深くお辞儀（覚醒の2枚目のうなだれた姿を借りる）→ 花から光が降り、花びらの嵐が四人を包む（当たり）
## → 大輪が光って崩れ、花びらが一斉に放たれる（白金の光）→ 余韻（花びらが降る）→ 立ち姿へ。

const T := {"charge": 0.30, "release": 1.30, "open": 1.95, "bow": 2.05, "storm": [2.15, 2.27, 2.39, 2.51], "burst": 2.80, "settle": 3.55, "end": 4.40}
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const CREAM := Color("#fff4c0")
const GREEN := Color("#6f8a52")
const LEAF := Color("#9db07a")
const GLOW := Color("#f2f6c8")
const LINE := Color("#4c5c4a")
const LIGHT := ["#3a4a2a", "#6f8a52", "#9db07a", "#d8e8b0", "#f2f6c8", "#fff8e0", "#ffffff", "#ffffff"]
## 白磁の花びら（影は青みがかった緑灰、明るい所は白）
const PORCELAIN := ["#2e3a32", "#4a5a4c", "#728470", "#9eae98", "#c4d0bc", "#e0e8d8", "#f4f6ee", "#ffffff"]
## お辞儀に借りるポーズ（覚醒の2枚目）
const BOW := 9

var b_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var flower: ColorRect
var buds: Array = []
var rings: Array = []
var final_share := 0.45

func duration() -> float:
	return T.end

func impact() -> float:
	return T.burst

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.storm[i]), i])
	return out

func stops() -> Array:
	return [[T.burst, 0.08]]

func extra_poses() -> Dictionary:
	return {BOW: ["awaken", 2]}

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.release, 3], [T.bow, BOW], [T.settle, 1]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25 + Vector2(0, 6)

func _build() -> void:
	b_back = batch(back, false)
	blast = blast_quad(back, LIGHT, LIGHT, {"amp": 26., "k": .06, "seed": 2.6, "glow": .6, "glow_col": Vector3(.95, 1., .8), "glow_r": 40.})
	b_glow = batch(back)
	flower = bloom_quad(back, PORCELAIN, [], {"petals": 10.0, "seed": 3.0, "outline_col": Vector3(.16, .2, .16)})
	for i in range(5):
		buds.append(bloom_quad(front, PORCELAIN, [], {"petals": 6.0, "seed": 11.0 + i, "outline_col": Vector3(.16, .2, .16), "squash": 0.55}))
	for i in range(2):
		rings.append(ring_quad(front, ["#9db07a", "#e8e2d0", "#fbf8ee", "#ffffff"], {"squash": .34, "breakup": .3, "seed": 1.0 + i * 3.3, "glow": .35, "glow_col": Vector3(.95, 1., .8)}))
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_glow.reset(); b_add.reset(); b_front.reset()
	var head := at("mark", 2)
	var center := _center()
	var ch := RBMHeroFx.ramp(t, T.charge, T.release)
	var a := t - T.burst
	view["dim"] = 0.25 * ch + 0.18 * RBMHeroFx.env(t, T.release, T.open, T.burst, T.settle)
	view["dim_col"] = Color(0.04, 0.05, 0.03)
	# 溜め: 光が花の顔へ集まり、足元に白磁の小さな花が順に咲く
	var feet_fade := 1.0 - RBMHeroFx.ramp(t, T.release + 0.4, T.open + 0.3)
	for i in range(5):
		var p := HOME + Vector2(-40 + i * 20, 3 - RBMHeroFx.r(i, 4) * 6)
		var o := RBMHeroFx.ramp(t, T.charge + i * 0.12, T.charge + i * 0.12 + 0.45)
		if o > 0.0 and feet_fade > 0.0:
			show_bloom(buds[i], p, 9.0 + 2.0 * RBMHeroFx.r(i, 6), {"open": o, "rot": i * 0.7 + t * 0.2, "fade": feet_fade})
		else:
			buds[i].visible = false
	if t < T.release + 0.1:
		inward(b_add, head, t, 70, 3, 5.0, 110.0, 1.4, GLOW, ch, 2.2)
		petal_cloud(b_front, at("center", 2, 0, -10), t, 14, 9, 30.0, 3.5, WHITE, IVORY, ch, "orbit", 0.5, Color(LINE, 0.8))
	view["hero"]["lit"] = 0.5 * ch * (1.0 - RBMHeroFx.ramp(t, T.release, T.release + 0.3))
	view["hero"]["lit_col"] = GLOW
	# 開花: 四人の足元に巨大な白磁の花（外の段から順に開く。ゆっくり回る）→ 弾ける時は点描で崩れる
	var open := RBMHeroFx.ramp(t, T.release, T.open)
	var crumble := RBMHeroFx.ramp(a, 0.0, 0.3)
	if open > 0.0 and crumble < 1.0:
		var charge2 := RBMHeroFx.ramp(t, T.open, T.burst)
		show_bloom(flower, center, 124.0, {"open": open, "rot": t * 0.12, "squash": 0.38, "glow": 0.25 * open + 0.6 * charge2 + 0.8 * (1.0 - crumble) * float(a >= 0.0), "crumble": crumble, "fade": 1.0})
		# 花の下の柔らかな影と、花の周りの光
		inward(b_add, center + Vector2(0, -30), t, 40, 15, 6.0, 140.0, 1.2, WHITE, open * (1.0 - crumble) * 0.5, 1.4)
		# 花から立ち上る光
		soft_band(b_glow, center, center + Vector2(0, -170), 150.0 * open, Color(GLOW, 0.16 * open * (1.0 - crumble)), Color(WHITE, 0.0))
	else:
		flower.visible = false
	# 花から光が降り、花びらの嵐が四人を包む
	var rain := RBMHeroFx.env(t, T.bow, T.storm[0], T.burst, T.burst + 0.2)
	for i in range(4):
		if not present[i]:
			continue
		var st := t - float(T.storm[i])
		var on := RBMHeroFx.env(st, 0.0, 0.08, 0.5, 0.75)
		var chest := target_chest(i)
		if rain > 0.0:
			soft_band(b_glow, chest + Vector2(0, 24), chest + Vector2(0, -60), 30.0, Color(GLOW, 0.2 * rain), Color(WHITE, 0.0))
		petal_cloud(b_front, chest + Vector2(0, 6), t, 18, 21 + i * 5, 28.0, 4.5, WHITE, IVORY, on, "orbit", 0.6, Color(LINE, 0.85))
		sparks(b_add, chest, st, 0.35, 20, 31 + i, 260.0, WHITE, GLOW, 0.0, TAU, 60.0, 1.4)
	var evs := []
	for i in range(4):
		evs.append([float(T.storm[i]), i])
	ally_hits(t, evs, 0.6)
	# お辞儀の瞬間: 花の顔の前に小さな光
	var bw := t - T.bow
	if bw >= 0.0 and bw < 0.5:
		disc(b_add, at("top", 1, -10, 18), 5.0 * (1.0 - RBMHeroFx.ramp(bw, 0.0, 0.4)), Color(WHITE, 0.8))
		petal_cloud(b_front, at("top", 1, -10, 18), bw, 10, 61, 40.0, 3.5, WHITE, IVORY, 1.0, "burst", 0.45, Color(LINE, 0.8))
	# 大輪が崩れ、花びらが一斉に放たれる（白金の光）
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.4, 0.85)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(center + Vector2(0, -26), a, 32, 19, 300.0, 150.0, 76.0, 80.0, .55, 0.0, 6.6), a, {"flow": a * .2, "cool": .02 + RBMHeroFx.ramp(a, .2, .8) * .2, "erode": RBMHeroFx.ramp(a, .25, .85), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .45, "amp": 26.0, "radial_heat": .55, "heat_center": w(center + Vector2(0, -26)), "heat_radius": 280.0 * RBMHeroFx.burst(a, 6.6), "erode_radial": 160.0, "tone_cap": .98})
		refract_wave(center, a, 0.6, 420.0, 5.0, 0.025)
	if a >= 0.0:
		petal_cloud(b_front, center + Vector2(0, -30), a, 110, 41, 280.0, 6.0, WHITE, CREAM, 1.0, "burst", 0.45, Color(LINE, 0.85))
		view["shake"] += hit_shake(a, 9.0, 70.0, 0.35)
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.35, 0.8), GLOW, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.12, 0.45) * 0.8)
	for i in range(2):
		show_ring(rings[i], center, a - i * 0.1, 0.6, 320.0, 6.0 - i * 2.0, 5.0, 0.02)
	# 余韻: 花びらが降る
	petal_cloud(b_front, Vector2(220, 150), t, 26, 51, 180.0, 4.5, WHITE, IVORY, RBMHeroFx.env(t, T.burst + 0.3, T.settle, T.end - 0.4, T.end), "fall", 0.45, Color(LINE, 0.8))
	b_back.commit(); b_glow.commit(); b_add.commit(); b_front.commit()

## 線の周りの柔らかい光の帯（中心の色 → 両縁で透明）
func soft_band(b: RBMHeroFxBatch, a: Vector2, c: Vector2, wd: float, col_a: Color, col_c: Color) -> void:
	var side := (c - a).orthogonal().normalized() * wd * 0.5
	b.quad(a, c, c + side, a + side, col_a, col_c, Color(col_c, 0.0), Color(col_a, 0.0))
	b.quad(a, c, c - side, a - side, col_a, col_c, Color(col_c, 0.0), Color(col_a, 0.0))
