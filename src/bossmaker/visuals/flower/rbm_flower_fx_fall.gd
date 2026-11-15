extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/pre_defeat.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー・撃破（2026-11-14 試作。ユーザー指定なし→こちらの案）。本番では全ボス共通のとどめのスロー（白く光る）の後に続く。
## うなだれた姿（覚醒の2枚目）→ 白磁の体が乾いた色へ褪せ、ドレスから花びらがこぼれる
## → 上から四角い粒でほどけ、ほどけた所が花びらになって風で左へ吹かれていく（本番と同じ共通の消え方）
## → 体が消えた床に、小さな白磁のカラーが一輪だけ咲いて残る（聖獣の剣と同じ「残る物」）。
## 覚醒後（post_defeat.gd）は深紅の花びらの嵐・背の大輪が枯れて弾ける・オーラが散る → 喪華が一輪残る。

const T := {"wither": 0.30, "melt": 1.20, "gone": 2.45, "remain": 2.55, "end": 4.40}
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const DRY := Color("#9c8862")
const LINE := Color("#4c5c4a")
const GLOW := Color("#f2f6c8")
const PORCELAIN := ["#2e3a32", "#4a5a4c", "#728470", "#9eae98", "#c4d0bc", "#e0e8d8", "#f4f6ee", "#ffffff"]
const POSE := 9
## 体の上端・下端（ほどける前線の高さの目安。論理ドット）
const TOP_Y := -104.0

var b_back: RBMHeroFxBatch
var b_shaft: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_front: RBMHeroFxBatch

func duration() -> float:
	return T.end

func impact() -> float:
	return T.gone

func extra_poses() -> Dictionary:
	return {POSE: ["awaken", 2]}

func pose_keys() -> Array:
	return [[0.0, POSE]]

func _build() -> void:
	b_back = batch(back, false)
	b_shaft = batch(back)
	b_front = batch(front, false)
	b_glow = batch(front)

## ほどけた所から花びらが生まれ、風で左上へ流れる。前線は上から下へ（dissolve の rise と同じ向き）。
func petal_wind(b: RBMHeroFxBatch, t: float, t0: float, t1: float, n: int, seed_: int, c_dark: Color, c_light: Color, line_c: Color, wind: float = 150.0) -> void:
	for i in range(n):
		var r1 := RBMHeroFx.r(i, seed_)
		var r2 := RBMHeroFx.r(i, seed_ + 1)
		var r3 := RBMHeroFx.r(i, seed_ + 2)
		var ts := t0 + (t1 - t0) * r1
		var age := t - ts
		if age < 0.0 or age > 1.6:
			continue
		var y0 := HOME.y + TOP_Y * (1.0 - r1) + 4.0
		var x0 := HOME.x - 22.0 + 44.0 * r2
		# 風に乗って広がる（上下にもばらける。速さもばらばら）
		var vx := wind * (0.6 + 0.8 * r3)
		var vy := -70.0 + 90.0 * RBMHeroFx.r(i, seed_ + 3)
		var p := Vector2(x0 - vx * age - 40.0 * age * age, y0 + vy * age + sin(age * 4.0 + i) * 8.0)
		var f := (1.0 - smoothstep(1.0, 1.6, age)) * smoothstep(0.0, 0.08, age)
		var col := c_dark.lerp(c_light, r3)
		var ln := 3.4 + 2.6 * r3
		var spin := age * (4.0 + 3.0 * r2) + r1 * TAU
		petal(b, p - Vector2.from_angle(spin) * 0.8, spin, ln + 1.6, ln * 0.6 + 1.4, Color(line_c, 0.85 * f), Color(line_c, 0.85 * f))
		petal(b, p, spin, ln, ln * 0.6, Color(col, f), Color(c_light, f))

func _step(t: float) -> void:
	b_back.reset(); b_shaft.reset(); b_glow.reset(); b_front.reset()
	var wi := RBMHeroFx.ramp(t, T.wither, T.melt)
	# 本番のとどめの白さの続き
	view["hero"]["flash"] = 0.7 * (1.0 - RBMHeroFx.ramp(t, 0.0, 0.3))
	view["hero"]["flash_col"] = WHITE
	# 褪せる（乾いた色へ）
	view["hero"]["tint"] = 0.35 * wi
	view["hero"]["tint_col"] = DRY
	view["hero"]["desat"] = 0.45 * wi
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.1], [T.melt, 0.3], [T.gone, 0.32], [T.end, 0.18]])
	view["dim_col"] = Color(0.03, 0.04, 0.03)
	# 小さく震える（1px）
	var tremble := RBMHeroFx.env(t, T.wither, T.wither + 0.2, T.melt, T.melt + 0.4)
	body["off"] = Vector2(roundf(sin(t * 47.0) * tremble), 0.0)
	# ドレスから花びらがこぼれる
	# 花びらの数（2026-11-15 ユーザー「花びらがありすぎて気持ち悪い」→ 数を約半分に、少し大きく）
	petal_cloud(b_front, HOME + Vector2(0, -36), t - T.wither, 10, 5, 34.0, 4.2, IVORY.lerp(DRY, 0.5), WHITE, RBMHeroFx.env(t, T.wither, T.wither + 0.3, T.melt + 0.4, T.gone), "fall", 0.45, Color(LINE, 0.8))
	# 上から四角い粒でほどける（本番の共通の消え方）。ほどけた所が花びらになって吹かれていく
	body["dissolve"] = smoothstep(T.melt, T.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(Color("#f4f6ee"), 0.95)
	body["shadow"] = 1.0 - body["dissolve"]
	petal_wind(b_front, t, T.melt, T.gone, 44, 21, IVORY.lerp(DRY, 0.35), WHITE, LINE)
	# 消えた床に、小さな白磁のカラーが一輪だけ咲いて残る
	var o := RBMHeroFx.ramp(t, T.remain, T.remain + 0.7)
	if o > 0.0:
		# 光は消さずに照らし続ける（2026-11-16 ユーザー「最後の花が出た時に光を消さないで聖獣と同じように照らして」。結果の画面まで残る）。呼吸するようにゆっくり明暗
		var g := RBMHeroFx.ramp(t, T.remain, T.remain + 0.5) * (0.85 + 0.15 * sin(t * 2.6))
		light_shaft(b_shaft, HOME + Vector2(0, 3), 150.0, 8.0, 26.0, WHITE, 0.2 * g)
		disc(b_glow, HOME + Vector2(2, 2), 20.0, Color(GLOW, 0.14 * g), 0.3)
		calla(b_front, HOME + Vector2(2, 2), 22.0, o, 0.12, [Color("#c4d0bc"), Color("#f4f6ee"), Color("#ffffff")], Color(LINE, 0.95), [Color("#4a5a3c"), Color("#7a9a5c")], Color("#ffd870"))
		embers(b_glow, Rect2(HOME.x - 24, HOME.y - 60, 48, 60), t, 14, 31, 30.0, GLOW, g * 0.8, 1.6, 6.0)
	b_back.commit(); b_shaft.commit(); b_glow.commit(); b_front.commit()
