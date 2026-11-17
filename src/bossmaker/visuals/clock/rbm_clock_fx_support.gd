extends RBMClockFxBase
## 本番（2026-11-17 ユーザー「これでいいね」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/pre_support.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長・支援（2026-11-16）。立ち姿 → 支援のポーズ（1回だけ切り替え）→ 立ち姿。
## 回復＝「自分の時間を巻き戻す」: 両手を頭の時計へ（全体の2枚目）。背後に文字盤が浮かび、針が逆へ回る。
##   少し離れた所にいた自分の残像が、逆再生のように体へ戻ってくる・青緑の粒が体へ流れ込む → 巻き戻し切った所で体が澄んだ光に包まれる。
## 強化＝「自分の時間を早送りする」: 両腕を時計の針の角度に開く（全体の3枚目）。背後の文字盤の針と両脇の歯車が速く回り、
##   後ろへ流れる残像（速さ）→ 秒針がひと回りした所で歯車がかみ合って止まり、体の縁が真鍮色に光る。
## 覚醒後（post_support.gd）は黒ずんだ真鍮・深紅の秒針・青緑のオーラが燃え上がる。

const T := {"pose": 0.20, "dial": 0.28, "gather": 0.60, "impact": 1.25, "back": 1.95, "end": 2.45}
const BRASS := Color("#d8b468")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const CYAN := Color("#7ee0ec")
const CRIMSON := Color("#e03848")
const SUPPORT_POSE := 9
const DARK_BRASS := {"brass_l": Vector3(.86, .72, .45), "brass": Vector3(.55, .40, .20), "brass_d": Vector3(.22, .14, .07), "face_l": Vector3(.86, .84, .80), "face_d": Vector3(.5, .48, .46),
	"steel": Vector3(.2, .04, .07), "sec_col": Vector3(.95, .2, .25)}

var awakened := false
var heal := true

var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var dial: ColorRect
var gears: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func extra_poses() -> Dictionary:
	return {SUPPORT_POSE: ["post_all" if awakened else "pre_all", 2 if heal else 3]}

func pose_keys() -> Array:
	return [[0.0, 0], [T.pose, SUPPORT_POSE], [T.back, 0]]

func _build() -> void:
	var look: Dictionary = DARK_BRASS if awakened else {}
	for i in range(2):
		gears.append(gear_quad(back, {"teeth": [12.0, 9.0][i], "spokes": 5.0 if i == 0 else 4.0}))
	dial = dial_quad(back, look.merged({"seed": 9.0, "thick": 3.0}))
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_add.reset(); b_front.reset()
	var a := t - T.impact
	var on := RBMHeroFx.env(t, T.dial, T.dial + 0.2, T.back - 0.2, T.back + 0.1)
	var ch := RBMHeroFx.ramp(t, T.gather, T.impact)
	var center := HOME + Vector2(4, -62)
	var col := CYAN if awakened else TEAL_L
	view["dim"] = 0.26 * on
	view["dim_col"] = Color(0.0, 0.02, 0.05)
	var run := maxf(0.0, t - T.dial)
	# 背後の文字盤: 回復は針が逆へ、強化は先へ速く回る
	var dir := -1.0 if heal else 1.0
	var spin := run * run * (6.0 if heal else 9.0) * dir
	if a >= 0.0:
		spin = (T.impact - T.dial) * (T.impact - T.dial) * (6.0 if heal else 9.0) * dir
	var look: Dictionary = DARK_BRASS if awakened else {}
	show_dial(dial, center + Vector2(0, -8), 46.0, look.merged({"squash": 0.92, "hour": spin * 0.083, "minute": spin, "second": spin * 4.0 if a < 0.0 else 0.0,
		"glow": 0.25 + 0.5 * ch + 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.4)) * float(a >= 0.0), "glow_col": Vector3(.5, .92, 1.) if heal or awakened else Vector3(1., .85, .5), "fade": 0.85 * on, "dark": 0.2}))
	# 強化: 両脇の歯車が速く回り、最後にかみ合って止まる
	for i in range(2):
		var gp := center + Vector2(-58 + 116 * i, 6)
		var gr := (run * run * 7.0 if a < 0.0 else (T.impact - T.dial) * (T.impact - T.dial) * 7.0) * (1.0 if i == 0 else -1.3)
		show_gear(gears[i], gp, [18.0, 13.0][i], {"rot": gr, "fade": 0.0 if heal else on, "dark": 0.2, "glow": 0.4 * ch})
	if heal:
		# 回復: 離れた所の自分の残像が、逆再生のように体へ戻ってくる・粒が流れ込む
		for k in range(3):
			var back_k := 1.0 - RBMHeroFx.ramp(t, T.gather + k * 0.12, T.impact - 0.1 + k * 0.04)
			if back_k > 0.0 and t >= T.dial:
				ghost(SUPPORT_POSE, Vector2(28.0 + 18.0 * k, -4.0 + 3.0 * k) * back_k * (1 if k % 2 == 0 else -1), 0.32 * back_k, TEAL, 0.55)
		inward(b_add, center + Vector2(0, 6), t, 30, 31, 10.0, 110.0, 1.4, Color(col, 0.9), ch, 2.0)
		embers(b_add, Rect2(HOME.x - 60, HOME.y - 130, 120, 130), t, 22, 33, -50.0, Color(col, 0.85), on, 2.0, 6.0)
	else:
		# 強化: 後ろへ流れる残像（速さ）
		for k in range(4):
			var f := float(k + 1)
			ghost(SUPPORT_POSE, Vector2(10.0 * f, 0.0) * ch, 0.26 * ch * (1.0 - k * 0.2), BRASS if not awakened else CRIMSON, 0.55)
		embers(b_add, Rect2(HOME.x - 50, HOME.y - 120, 100, 120), t, 20, 35, 120.0, Color(BRASS, 0.85), on, 2.0, 4.0)
	# 巻き戻し切った・早送りし切った瞬間: 体が光る（澄んだ青緑 / 真鍮色）
	if a >= 0.0:
		view["hero"]["flash"] = 0.3 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3))
		view["hero"]["flash_col"] = col if heal else Color("#fff0c8")
		sparks(b_add, center + Vector2(0, 10), a, 0.5, 30, 37, 260.0, Color("#eafcff") if heal else Color("#fff0c8"), col if heal else BRASS, 0.0, TAU, 60.0, 1.6)
		set_post({"flash": 0.1 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.12)), "flash_col": Vector3(.85, .97, 1.0) if heal else Vector3(1.0, .93, .8)})
		view["shake"] += hit_shake(a, 3.0, 80.0, 0.2)
	view["hero"]["lit"] = 0.25 * ch + 0.35 * RBMHeroFx.env(a, 0.0, 0.06, 0.5, 0.85)
	view["hero"]["lit_col"] = col if heal else BRASS
	if awakened:
		view["hero"]["sun_aura"] = 1.0 + (1.3 if not heal else 0.6) * RBMHeroFx.env(a, 0.0, 0.1, 0.4, 0.9)
	b_add.commit(); b_front.commit()
