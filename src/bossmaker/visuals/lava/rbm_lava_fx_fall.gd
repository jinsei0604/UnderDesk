extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/pre_defeat.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人・撃破（2026-11-14 試作。ユーザー指定なし→こちらの案）。本番では全ボス共通のとどめのスロー（白く光る）の後に続く。
## うずくまる姿（覚醒の2枚目）→ 炉の火が消えていく（体の照りが消え、灰色へ冷える・湯気が立つ・小さく震える）
## → 冷えた体にひびが入り、かけらがこぼれる → 上から四角い粒でほどけ（縁は消えかけの残り火の色）、ほどけた所から岩が転げ落ちる
## → 立っていた所に冷えた岩の山が残り、割れ目の残り火がゆっくり消える・湯気が細くなる。
## 覚醒後（post_defeat.gd）は最後の大噴火 → 火口の上に岩の山が残る。

const T := {"cool": 0.30, "crack": 1.05, "melt": 1.55, "gone": 2.75, "end": 4.60}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
const ROCK_LIT := Color("#5a4a44")
const ROCK_DARK := Color("#221a1a")
const ASH := Color("#3a3436")
const POSE := 9
const TOP_Y := -100.0
const PILE_N := 46

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var steam: ColorRect

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
	steam = blast_quad(back, SMOKE, SMOKE, {"amp": 18., "k": .07, "seed": 3.9, "glow": 0.0, "glow_r": 16.})
	b_front = batch(front, false)
	b_add = batch(front)

## 体から岩が転げ落ちて、立っていた所に山を作る。t0〜t1 の間にほどけた高さから順に落ちる。glow は割れ目の残り火の強さ。
func rock_pile(b: RBMHeroFxBatch, b_glow: RBMHeroFxBatch, t: float, t0: float, t1: float, glow: float, width: float = 92.0) -> void:
	for i in range(PILE_N):
		var r1 := RBMHeroFx.r(i, 81)
		var r2 := RBMHeroFx.r(i, 82)
		var r3 := RBMHeroFx.r(i, 83)
		# 下の段ほど先に積もる（山の形）
		var layer := float(i) / PILE_N
		var tx := (r2 - 0.5) * width * (1.0 - 0.6 * layer)
		# 山の形: 中ほど高い（高さ約28）
		var hump := 1.0 - pow(absf(tx) / (width * 0.5), 2.0)
		var rest := HOME + Vector2(tx, 3.0 - layer * 26.0 * maxf(hump, 0.2))
		var td := t0 + (t1 - t0) * (0.15 + 0.85 * r1)
		var age := t - td
		if age < 0.0:
			continue
		var src := HOME + Vector2(tx * 0.5, TOP_Y * (1.0 - r1) + 6.0)
		var fall := minf(1.0, age / 0.32)
		var p := src.lerp(rest, fall * fall) + Vector2(0, -10.0 * sin(PI * fall) * (1.0 - fall))
		var sz := 6.0 + 6.0 * r3 * (1.0 - 0.45 * layer)
		# 5角形の丸い岩だけ（尖った三角を作らない: 種を 3 で割って 2 余る数にする）
		var seed_ := i * 3 + 2
		b.shard(p, sz, r1 * TAU, seed_, ROCK_LIT, ROCK_DARK)
		if fall >= 1.0 and glow > 0.0 and i % 3 == 0:
			var g := glow * (0.6 + 0.4 * sin(t * 3.0 + i))
			b_glow.line(p + Vector2(-sz * 0.4, 0), p + Vector2(sz * 0.3, sz * 0.2), 1.0, Color(EMBER, 0.8 * g), Color(HOT, 0.6 * g))

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var co := RBMHeroFx.ramp(t, T.cool, T.melt)
	view["hero"]["flash"] = 0.7 * (1.0 - RBMHeroFx.ramp(t, 0.0, 0.3))
	view["hero"]["flash_col"] = WHITE
	# 炉の火が消えていく: 照りが消え、灰色へ冷える
	view["hero"]["lit"] = 0.55 * (1.0 - co)
	view["hero"]["lit_col"] = EMBER
	view["hero"]["desat"] = 0.75 * co
	view["hero"]["tint"] = 0.3 * co
	view["hero"]["tint_col"] = ASH
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.12], [T.melt, 0.35], [T.gone, 0.38], [T.end, 0.15]])
	view["dim_col"] = Color(0.03, 0.02, 0.02)
	var tremble := RBMHeroFx.env(t, T.cool, float(T.cool) + 0.2, T.melt, float(T.melt) + 0.3)
	body["off"] = Vector2(roundf(sin(t * 43.0) * tremble), 0.0)
	# 残り火（だんだん少なく）・ひびからこぼれるかけら
	embers(b_add, Rect2(HOME.x - 50, HOME.y - 100, 100, 100), t, 30, 9, 50.0, EMBER, 1.0 - co, 2.0, 6.0)
	if t >= T.crack:
		var ca := t - T.crack
		for k in range(3):
			var o := HOME + Vector2(-20 + k * 20, -70 + k * 14)
			shards(b_front, o, ca - k * 0.12, 0.7, 4, 61 + k * 5, 60.0, 3.0, ROCK_LIT, ROCK_DARK, 400.0, PI * 0.5, 1.4)
		view["shake"] += hit_shake(ca, 4.0, 70.0, 0.2)
	# 上から四角い粒でほどける（縁は消えかけの残り火の色）。ほどけた所から岩が転げ落ちて山になる
	body["dissolve"] = smoothstep(T.melt, T.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(Color("#c8501a"), 0.9)
	body["shadow"] = 1.0 - body["dissolve"]
	rock_pile(b_front, b_add, t, T.melt, T.gone, 1.0 - RBMHeroFx.ramp(t, T.gone, T.end - 0.4))
	view["shake"] += Vector2(sin(t * 31.0), 0.0) * 1.2 * RBMHeroFx.env(t, T.melt, T.melt + 0.1, T.gone - 0.2, T.gone)
	# 湯気（冷える間に立ち、最後は細くなる）
	var sa := t - T.cool
	var sf := 1.0 - RBMHeroFx.ramp(t, T.gone - 0.2, T.end - 0.6)
	steam.visible = sa >= 0.0 and sf > 0.0
	if steam.visible:
		var sc := HOME + Vector2(0, -60.0 - sa * 10.0)
		show_blast(steam, blobs(sc, sa * 0.3, 16, 19, 60.0, 34.0, 20.0, 70.0, .1, 0.0, 2.0), sa, {"flow": sa * .15, "cool": 0.0, "erode": 0.0, "fade": sf * RBMHeroFx.ramp(sa, 0.0, 0.6) * 0.5, "erode_noise": .6, "tone_cap": .6})
	b_back.commit(); b_add.commit(); b_front.commit()
