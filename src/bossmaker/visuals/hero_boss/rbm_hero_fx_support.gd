extends RBMHeroFxBase
## ヒーローの支援（回復・強化 × 覚醒前後。2026-11-17。表示専用。戦闘の状態・乱数には触れない）。時刻は RBMHeroFxTiming.SUPPORT。
## 本体は立ち姿 → 支援のポーズ1枚 → 立ち姿（rbm_hero_boss_motion.gd の SUPPORT_POSE）。heal・dark は再生の前に入れる。
## 覚醒前の回復（腕を組む）: 光の粒が胸の灯へ集まって充電される → 青い光がふくらむ（照射器では照らさない、2026-11-19 ユーザーの指摘）。
## 覚醒前の強化（力をためる構え）: 床の小石が浮き、青い火花が集まる → 青いオーラが燃え上がり、床を衝撃の輪が走る。
## 覚醒後の回復（両腕を広げる）: 周りの闇（黒紅の煙の筋）を体へ吸い込む → 胸が赤く脈打つ。
## 覚醒後の強化（爪を掲げる）: 黒紅のオーラが大きく燃え上がり、床を黒紅の輪が走る。
## 覚醒後は常時のオーラ（黒い炎）をずっと出したまま（強さ1より下げない）。カメラは寄らない（揺れだけ）。

const T := RBMHeroFxTiming.SUPPORT
const BLUE := Color("#5cc6fa")
const PALE := Color("#c8f4ff")

var heal := true
var dark := false
var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var ring: ColorRect

func _build() -> void:
	b_back = batch(back, false)
	ring = ring_quad(back, RBMHeroFx.R_DARK if dark else RBMHeroFx.R_BLUE, {"squash": .3, "breakup": .35, "seed": 3.1, "glow": .5, "glow_col": Vector3(.9, .1, .2) if dark else Vector3(.4, .8, 1.)})
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	ring.visible = false
	var ia := t - float(T.impact)
	var hold := RBMHeroFx.ramp(t, float(T.pose), float(T.pose) + 0.1) * (1.0 - RBMHeroFx.ramp(t, float(T.back), float(T.end)))
	view["dim"] = 0.22 * hold
	view["dim_col"] = Color(0.06, 0.02, 0.05) if dark else Color(0.02, 0.04, 0.1)
	if dark:
		_awakened(t, ia, hold)
	else:
		_normal(t, ia, hold)
	b_back.commit(); b_add.commit(); b_front.commit()

func _normal(t: float, ia: float, hold: float) -> void:
	var chest := anchor("chest")
	var gather := RBMHeroFx.ramp(t, float(T.gather), float(T.impact))
	if heal:
		# 光の粒が胸の灯へ集まる（充電）
		inward(b_add, chest, t, 26, 41, 6.0, 64.0, 1.4, Color(PALE, 0.9), gather * (1.0 - RBMHeroFx.ramp(ia, -0.05, 0.05)), 1.6)
		RBMHeroRooftop.glow(b_add, chest, 3.0 + 7.0 * gather, Color(BLUE, 0.35 + 0.45 * gather))
	else:
		# 床の小石が浮き、青い火花が集まる
		for i in range(8):
			var lift := RBMHeroFx.ramp(t, float(T.gather) + 0.04 * i, float(T.impact)) * (1.0 - RBMHeroFx.ramp(ia, 0.0, 0.25))
			var p := foot + Vector2(-34 + 9.0 * i + 3.0 * RBMHeroFx.r(i, 7), -2.0 - lift * (6.0 + 10.0 * RBMHeroFx.r(i, 9)))
			if lift > 0.02:
				b_front.dot_px(p, 1.6 + RBMHeroFx.r(i, 11), Color("#6b6880"))
		inward(b_add, chest, t, 30, 43, 8.0, 70.0, 1.6, Color(BLUE, 0.9), gather * (1.0 - RBMHeroFx.ramp(ia, -0.05, 0.05)), 2.0)
		view["hero"]["dark_aura"] = 0.25 + 0.75 * gather
	# 命中（回復・強化が入る所）: 青い光がふくらみ、火花が上へ
	if ia >= 0.0:
		var k := 1.0 - RBMHeroFx.ramp(ia, 0.0, 0.5)
		view["hero"]["flash"] = 0.45 * (1.0 - RBMHeroFx.ramp(ia, 0.0, 0.18))
		view["hero"]["flash_col"] = PALE
		sparks(b_add, chest, ia, 0.6, 30, 47, 260.0, Color.WHITE, BLUE, -PI * 0.5, PI * 0.9, -40.0, 1.4)
		embers(b_add, Rect2(foot.x - 22, foot.y - 80, 44, 76), t, 18, 49, 60.0, Color(PALE, 1.0), k, 1.8, 4.0)
		if heal:
			RBMHeroRooftop.glow(b_add, chest, 22.0 * k, Color(BLUE, 0.35 * k))
			RBMHeroRooftop.glow(b_add, chest, 8.0 * k, Color(1, 1, 1, 0.8 * k))
			pass  # 回復は炎を出さない（強化の青い炎と見分ける）
		else:
			# 青いオーラが燃え上がり、床を衝撃の輪が走る
			view["hero"]["dark_aura"] = 1.0 + 0.8 * RBMHeroFx.env(ia, 0.0, 0.08, 0.3, 0.9)
			show_ring(ring, foot + Vector2(0, -1), ia, 0.5, 110.0, 5.0, 6.0, 0.0)
			view["shake"] += hit_shake(ia, 10.0, 80.0, 0.3)
			RBMHeroRooftop.glow(b_add, anchor("head") + Vector2(2, 2), 8.0 * k, Color(BLUE, 0.8 * k))
	if not heal:
		view["hero"]["dark_aura"] = float(view["hero"].get("dark_aura", 0.0)) * (1.0 - RBMHeroFx.ramp(t, float(T.back), float(T.end)))

func _awakened(t: float, ia: float, hold: float) -> void:
	var chest := anchor("chest")
	var gather := RBMHeroFx.ramp(t, float(T.gather), float(T.impact))
	var aura := 1.0
	if heal:
		# 周りの闇（黒紅の煙の筋）を体へ吸い込む → 胸が赤く脈打つ
		inward(b_back, chest, t, 34, 61, 10.0, 96.0, 3.0, Color(RBMHeroFx.C_PLUM, 0.9), gather * (1.0 - RBMHeroFx.ramp(ia, -0.05, 0.08)), 1.5)
		inward(b_add, chest, t, 20, 63, 8.0, 80.0, 1.4, Color(RBMHeroFx.C_RED, 0.8), gather * (1.0 - RBMHeroFx.ramp(ia, -0.05, 0.08)), 1.7)
		aura = 1.0 + 0.3 * gather
		var pulse := 0.5 + 0.5 * sin(t * 18.0)
		RBMHeroRooftop.glow(b_add, chest, (3.0 + 5.0 * gather) * (0.8 + 0.2 * pulse), Color(RBMHeroFx.C_RED, 0.4 + 0.4 * gather))
	else:
		# 黒紅の火花が爪へ集まる
		inward(b_add, anchor("head") + Vector2(-6, -10), t, 24, 65, 8.0, 74.0, 1.6, Color(RBMHeroFx.C_RED, 0.9), gather * (1.0 - RBMHeroFx.ramp(ia, -0.05, 0.05)), 2.0)
		aura = 1.0 + 0.5 * gather
	view["post"]["vig"] = 0.25 * hold
	if ia >= 0.0:
		var k := 1.0 - RBMHeroFx.ramp(ia, 0.0, 0.5)
		view["hero"]["flash"] = 0.22 * (1.0 - RBMHeroFx.ramp(ia, 0.0, 0.14))
		view["hero"]["flash_col"] = Color(RBMHeroFx.C_RED)
		sparks(b_add, chest, ia, 0.6, 30, 67, 260.0, Color(RBMHeroFx.C_ROSE), Color(RBMHeroFx.C_RED), -PI * 0.5, PI * 0.9, -40.0, 1.4)
		embers(b_add, Rect2(foot.x - 24, foot.y - 86, 48, 82), t, 18, 69, 60.0, Color(RBMHeroFx.C_RED, 1.0), k, 1.8, 4.0)
		if heal:
			RBMHeroRooftop.glow(b_add, chest, 18.0 * k, Color(RBMHeroFx.C_RED, 0.35 * k))
			aura = maxf(aura * (1.0 - RBMHeroFx.ramp(ia, 0.0, 0.6)), 1.0 + 0.4 * k)
		else:
			# 黒紅のオーラが大きく燃え上がり、床を黒紅の輪が走る
			aura = 1.5 + 0.8 * RBMHeroFx.env(ia, 0.0, 0.08, 0.3, 0.9)
			show_ring(ring, foot + Vector2(0, -1), ia, 0.55, 120.0, 5.0, 6.0, 0.0)
			view["shake"] += hit_shake(ia, 12.0, 80.0, 0.3)
			RBMHeroRooftop.glow(b_add, anchor("head") + Vector2(2, 2), 8.0 * k, Color(RBMHeroFx.C_RED, 0.8 * k))
	# 常時のオーラ（覚醒後の立ち姿と同じ強さ1）より下げない。戻る所でゆっくり1へ
	var settle := RBMHeroFx.ramp(t, float(T.back), float(T.end))
	view["hero"]["dark_aura"] = maxf(1.0, lerpf(aura, 1.0, settle))
