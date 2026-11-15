extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/post_defeat.gd でユーザーが採用した内容をそのまま移した。
## 喪華のカラー女王・撃破（2026-11-14 試作。覚醒後は覚醒前より派手に＝聖獣の時のユーザーの指摘）。
## うつむいた姿（覚醒後全体の4枚目）→ 深紅の花びらが体の周りで渦を巻き始め、オーラが乱れて燃え上がる
## → 背に巨大な喪華が開く → その大輪が一気に枯れる → 枯れた大輪が弾け、深紅の花びらが画面いっぱいに吹き出す（閃光・揺れ・衝撃の輪）
## → 女王は上から四角い粒でほどけ、ほどけた所が深紅の花びらになって吹かれる・オーラが散る
## → 花びらが降る中、女王のいた床に小さな喪華が一輪だけ残り、暗く光る。

const T := {"storm": 0.30, "bloom": 0.85, "wither": 1.55, "burst": 2.15, "gone": 3.15, "remain": 3.30, "end": 5.20}
const DEEP := Color("#4a0e26")
const CRIMSON := Color("#a0244c")
const BLUSH := Color("#c06080")
const PALE := Color("#fff0f4")
const LINE := Color("#1a0610")
const VIOLET := Color("#c088e8")
const MOURN := ["#08020a", "#160412", "#26081c", "#3a0e28", "#521634", "#6e2244", "#8e3458", "#b45276"]
const MOURN_L := ["#10040c", "#24081a", "#3c0e2a", "#58183c", "#7a2a52", "#9e406a", "#c4648a", "#e696b0"]
const POSE := 9
const TOP_Y := -110.0

var b_back: RBMHeroFxBatch
var b_shaft: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var big: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.burst

func stops() -> Array:
	return [[T.burst, 0.10]]

func extra_poses() -> Dictionary:
	return {POSE: ["post_all", 4]}

func pose_keys() -> Array:
	return [[0.0, POSE]]

func _build() -> void:
	b_back = batch(back, false)
	b_shaft = batch(back)
	var look := {"outline_col": Vector3(.05, .01, .03), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8)}
	# 芯は出さない（女王の胸の前に光る丸い印に見えた: 2026-11-14 ユーザー「ボスの中心に変なマーク」）
	big = bloom_quad(back, MOURN, [], look.merged({"petals": 12.0, "seed": 9.0, "tilt": Vector3(8., 24., 44.), "core_k": 0.0}))
	b_front = batch(front, false)
	b_glow = batch(front)

func petal_wind(b: RBMHeroFxBatch, t: float, t0: float, t1: float, n: int, seed_: int) -> void:
	for i in range(n):
		var r1 := RBMHeroFx.r(i, seed_)
		var r2 := RBMHeroFx.r(i, seed_ + 1)
		var r3 := RBMHeroFx.r(i, seed_ + 2)
		var ts := t0 + (t1 - t0) * r1
		var age := t - ts
		if age < 0.0 or age > 1.7:
			continue
		var y0 := HOME.y + TOP_Y * (1.0 - r1) + 4.0
		var x0 := HOME.x - 26.0 + 52.0 * r2
		var vx := 170.0 * (0.6 + 0.8 * r3)
		var vy := -80.0 + 100.0 * RBMHeroFx.r(i, seed_ + 3)
		var p := Vector2(x0 - vx * age - 50.0 * age * age, y0 + vy * age + sin(age * 4.0 + i) * 8.0)
		var f := (1.0 - smoothstep(1.1, 1.7, age)) * smoothstep(0.0, 0.08, age)
		var col := DEEP.lerp(BLUSH, r3)
		var ln := 3.6 + 3.0 * r3
		var spin := age * (4.0 + 3.0 * r2) + r1 * TAU
		petal(b, p - Vector2.from_angle(spin) * 0.8, spin, ln + 1.6, ln * 0.6 + 1.4, Color(LINE, 0.85 * f), Color(LINE, 0.85 * f))
		petal(b, p, spin, ln, ln * 0.6, Color(col, f), Color(PALE.lerp(BLUSH, 0.5), f))

func _step(t: float) -> void:
	b_back.reset(); b_shaft.reset(); b_glow.reset(); b_front.reset()
	var ab := t - T.burst
	var storm := RBMHeroFx.ramp(t, T.storm, T.burst)
	var chest := HOME + Vector2(-2, -56)
	view["hero"]["flash"] = 0.7 * (1.0 - RBMHeroFx.ramp(t, 0.0, 0.3))
	view["hero"]["flash_col"] = PALE
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.15], [T.bloom, 0.45], [T.burst - 0.05, 0.62], [T.burst + 0.05, 0.2], [T.gone, 0.42], [T.end, 0.26]])
	view["dim_col"] = Color(0.05, 0.0, 0.03)
	# 体が深紅に染まり、震える（1〜2px）
	view["hero"]["tint"] = 0.3 * storm
	view["hero"]["tint_col"] = DEEP
	view["hero"]["lit"] = 0.5 * storm * (0.7 + 0.3 * sin(t * 22.0)) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.2))
	view["hero"]["lit_col"] = BLUSH
	var tremble := RBMHeroFx.ramp(t, T.storm, T.burst) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.05))
	body["off"] = Vector2(roundf(sin(t * 53.0) * (1.0 + tremble)) * float(tremble > 0.05), 0.0)
	# オーラが乱れて燃え上がる → 弾けて散る
	view["hero"]["sun_aura"] = (1.0 + 1.6 * storm * (0.75 + 0.25 * sin(t * 17.0))) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.7))
	# 深紅の花びらの渦（だんだん大きく・多く）
	if ab < 0.0:
		# 花びらの数（2026-11-15 ユーザー「花びらがありすぎて気持ち悪い」→ 数を約半分に、少し大きく）
		petal_cloud(b_front, chest + Vector2(0, 14), t * (1.0 + storm), int(8 + 22 * storm), 7, 34.0 + 30.0 * storm, 4.8, DEEP, BLUSH, RBMHeroFx.ramp(t, T.storm, T.storm + 0.3), "orbit", 0.42, Color(LINE, 0.85))
	# 背に巨大な喪華が開く → 一気に枯れる → 弾ける
	var om := RBMHeroFx.ramp(t, T.bloom, float(T.bloom) + 0.55)
	var wi := RBMHeroFx.ramp(t, T.wither, float(T.burst) - 0.05)
	var cr := RBMHeroFx.ramp(ab, 0.0, 0.35)
	if om > 0.0 and cr < 1.0:
		show_bloom(big, HOME + Vector2(6, -64), 96.0, {"open": om, "rot": t * 0.1, "squash": 0.92, "glow": 0.5 * om * (1.0 - wi), "wither": wi, "crumble": cr, "fade": 1.0})
	else:
		big.visible = false
	if wi > 0.0 and ab < 0.0:
		view["shake"] += Vector2(sin(t * 40.0), 0.0) * 1.5 * wi
	# 弾ける: 深紅の花びらが画面いっぱいに吹き出す
	if ab >= 0.0:
		petal_cloud(b_front, chest, ab, 56, 13, 260.0, 5.8, DEEP, BLUSH, 1.0, "burst", 0.6, Color(LINE, 0.85))
		set_post({"flash": 0.22 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.14)), "flash_col": Vector3(1.0, 0.75, 0.88), "vig": 0.35, "vig_col": Vector3(.08, .0, .04), "vig_r": .3})
		if ab < 0.12:
			view["hero"]["flash"] = 0.9 * (1.0 - ab / 0.12)
		embers(b_glow, Rect2(-20, 0, 680, 340), t, 60, 41, 50.0, VIOLET, RBMHeroFx.env(ab, 0.1, 0.4, 2.0, 2.8) * 0.7, 2.0, 18.0)
	view["shake"] += hit_shake(ab, 12.0, 60.0, 0.5)
	# 上から四角い粒でほどける（深紅の縁）。ほどけた所が花びらになって吹かれる
	body["dissolve"] = smoothstep(T.burst, T.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(Color("#e696b0"), 0.95)
	body["shadow"] = 1.0 - body["dissolve"]
	petal_wind(b_front, t, T.burst, T.gone, 44, 21)
	# 花びらが降る中、床に小さな喪華が一輪だけ残る
	petal_cloud(b_front, Vector2(320, 140), t, 18, 51, 300.0, 4.8, DEEP, BLUSH, RBMHeroFx.env(ab, 0.4, 0.9, 2.4, 3.0), "fall", 0.45, Color(LINE, 0.85))
	var o := RBMHeroFx.ramp(t, T.remain, float(T.remain) + 0.7)
	if o > 0.0:
		# 光は消さずに照らし続ける（2026-11-16 ユーザー「最後の花が出た時に光を消さないで聖獣と同じように照らして」。結果の画面まで残る）。呼吸するようにゆっくり明暗
		var g := RBMHeroFx.ramp(t, T.remain, float(T.remain) + 0.5) * (0.85 + 0.15 * sin(t * 2.6))
		light_shaft(b_shaft, HOME + Vector2(0, 3), 150.0, 8.0, 26.0, BLUSH, 0.2 * g)
		disc(b_glow, HOME + Vector2(2, 2), 20.0, Color(BLUSH, 0.14 * g), 0.3)
		calla(b_front, HOME + Vector2(2, 2), 22.0, o, 0.12, [Color("#24081a"), Color("#6e2244"), Color("#c4648a")], Color(LINE, 0.95), [Color("#2a1a1c"), Color("#5a3a3c")], Color("#c088e8"))
		embers(b_glow, Rect2(HOME.x - 20, HOME.y - 50, 40, 50), t, 10, 33, 26.0, BLUSH, g * 0.7, 1.6, 5.0)
	b_back.commit(); b_shaft.commit(); b_glow.commit(); b_front.commit()
