extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/pre_support.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー・支援（2026-11-14 ユーザー「支援は適当にいいものがあれば」）。立ち姿 → 支援のポーズ（1回だけ切り替え）→ 立ち姿。
## 回復: 足元に花が咲き、上から柔らかな光が降りて、花びらが体の周りを舞い上がる。
## 強化: 小さな花の輪が体の周りを回りながら光を集め、一斉に花びらへ弾ける（体の縁が光る）。覚醒後（post_support.gd）は喪華の色でオーラも燃え上がる。

const T := {"pose": 0.20, "bloom": 0.30, "gather": 0.60, "impact": 1.25, "back": 1.95, "end": 2.45}
const SUPPORT_POSE := 9
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const LEAF := Color("#d8ffbc")
const GLOW := Color("#f2f6c8")
const LINE := Color("#4c5c4a")
const PORCELAIN := ["#2e3a32", "#4a5a4c", "#728470", "#9eae98", "#c4d0bc", "#e0e8d8", "#f4f6ee", "#ffffff"]
const MOURN_L := ["#10040c", "#24081a", "#3c0e2a", "#58183c", "#7a2a52", "#9e406a", "#c4648a", "#e696b0"]

var awakened := false
var heal := true

var b_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var flower: ColorRect
var crown: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

## 支援のポーズ（回復＝全体の2枚目の手を胸の前で合わせた姿、強化＝全体の3枚目の両腕を広げた姿。覚醒後は覚醒後全体の同じ番号）
func extra_poses() -> Dictionary:
	return {SUPPORT_POSE: ["post_all" if awakened else "pre_all", 2 if heal else 3]}

func pose_keys() -> Array:
	return [[0.0, 0], [T.pose, SUPPORT_POSE], [T.back, 0]]

func _colors() -> Array:
	# [花びらの濃い色, 明るい色, 光, 縁]
	if awakened:
		return [Color("#4a0e26"), Color("#e8a8c0"), Color("#ff9ad0") if heal else Color("#d060c0"), Color("#1a0610", 0.85)]
	return [IVORY, WHITE, LEAF if heal else Color("#fff4c0"), Color(LINE, 0.85)]

func _build() -> void:
	b_back = batch(back, false)
	b_glow = batch(back)
	var look := {"outline_col": Vector3(.05, .01, .03), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8)} if awakened else {"outline_col": Vector3(.16, .2, .16)}
	var pal: Array = MOURN_L if awakened else PORCELAIN
	flower = bloom_quad(back, pal, [], look.merged({"petals": 10.0, "seed": 4.0}))
	for i in range(6):
		crown.append(bloom_quad(front, pal, [], look.merged({"petals": 6.0, "seed": 30.0 + i, "slender": 0.44})))
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_glow.reset(); b_add.reset(); b_front.reset()
	var cols := _colors()
	var a := t - T.impact
	var feet := HOME + Vector2(2, 3)
	var chest := HOME + Vector2(-2, -52)
	var ch := RBMHeroFx.ramp(t, T.gather, T.impact)
	var on := RBMHeroFx.env(t, T.bloom, T.bloom + 0.3, T.back - 0.2, T.end - 0.1)
	view["dim"] = 0.25 * RBMHeroFx.env(t, T.pose, T.gather, T.back, T.end)
	view["dim_col"] = Color(0.04, 0.0, 0.03) if awakened else Color(0.03, 0.04, 0.03)
	if heal:
		# 足元に花が咲き、上から光が降りる
		show_bloom(flower, feet, 46.0, {"open": RBMHeroFx.ramp(t, T.bloom, T.gather + 0.3), "rot": t * 0.2, "squash": 0.4, "glow": 0.3 * ch + 0.5 * RBMHeroFx.env(a, 0.0, 0.05, 0.2, 0.6), "fade": on})
		for c in crown:
			(c as ColorRect).visible = false
		var shine := RBMHeroFx.env(t, T.gather, T.impact, T.impact + 0.4, T.back)
		light_shaft(b_glow, HOME + Vector2(0, 4), 190.0, 16.0, 44.0, cols[2], 0.24 * shine)
		# 花びらの数（2026-11-15 ユーザー「花びらがありすぎて気持ち悪い」→ 数を約半分に、少し大きく）
		petal_cloud(b_front, chest + Vector2(0, 10), t, 12, 7, 46.0, 4.8, cols[0], cols[1], on, "orbit", 0.45, cols[3])
		embers(b_add, Rect2(HOME.x - 44, HOME.y - 100, 88, 100), t, 30, 9, 80.0, cols[2], RBMHeroFx.env(a, -0.1, 0.1, 0.6, 1.0), 2.0, 6.0)
		view["hero"]["flash"] = 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.35)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = cols[2]
		view["hero"]["lit"] = 0.5 * RBMHeroFx.env(a, 0.0, 0.1, 0.5, 0.9)
		view["hero"]["lit_col"] = cols[2]
	else:
		# 小さな花の輪が体の周りを回りながら光を集め、一斉に花びらへ弾ける
		flower.visible = false
		var burst := RBMHeroFx.ramp(a, 0.0, 0.12)
		for i in range(crown.size()):
			var q: ColorRect = crown[i]
			if burst >= 1.0 or t < T.bloom:
				q.visible = false
				continue
			var ang := float(i) / crown.size() * TAU + t * 2.2
			var p := chest + Vector2(cos(ang) * 40.0, sin(ang) * 14.0 + 8.0)
			show_bloom(q, p, 13.0, {"open": RBMHeroFx.ramp(t, T.bloom + i * 0.05, T.bloom + 0.3 + i * 0.05), "rot": t * 0.6 + i, "squash": 0.8, "glow": 0.5 * ch, "crumble": burst, "fade": 1.0})
		inward(b_add, chest, t, 40, 7, 4.0, 70.0, 1.2, cols[2], ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.05)), 2.4)
		if a >= 0.0:
			petal_cloud(b_front, chest, a, 26, 13, 140.0, 5.2, cols[0], cols[1], 1.0, "burst", 0.45, cols[3])
			for i in range(16):
				var x := HOME.x - 40.0 + 80.0 * RBMHeroFx.r(i, 61)
				var q2 := fmod(a * (1.5 + 0.8 * RBMHeroFx.r(i, 62)) + RBMHeroFx.r(i, 63), 1.0)
				var y0 := HOME.y - q2 * 110.0
				b_add.streak(Vector2(x, y0 - 18.0), Vector2(x, y0), 1.8, Color(WHITE, 0.0), Color(cols[2], 0.8 * sin(q2 * PI) * (1.0 - RBMHeroFx.ramp(a, 0.4, 0.8))))
		view["hero"]["flash"] = 0.5 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25)) if a >= 0.0 else 0.0
		view["hero"]["flash_col"] = WHITE
		view["hero"]["lit"] = 0.7 * RBMHeroFx.env(a, 0.0, 0.08, 0.55, 0.85)
		view["hero"]["lit_col"] = cols[2]
		view["shake"] += hit_shake(a, 5.0, 80.0, 0.3)
	if awakened:
		view["hero"]["sun_aura"] = 1.0 + (1.2 if not heal else 0.5) * RBMHeroFx.env(a, 0.0, 0.1, 0.4, 0.9)
	b_back.commit(); b_glow.commit(); b_add.commit(); b_front.commit()
