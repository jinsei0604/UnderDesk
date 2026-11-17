extends RBMClockFxBase
## 本番（2026-11-17 ユーザー「これでいいね」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/pre_defeat.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長・撃破（2026-11-16）の後に続く）:
## 意味: 「彼の時間が尽きる」。
## うなだれた姿（覚醒の2枚目）→ 顔の時計の針がだんだん遅くなり、12時でかちりと止まる（色が少し抜ける・静寂）
## → 顔のガラスにひびが走る → 体が上から四角い粒でほどけ、ほどけた所からガラスと真鍮のかけらがこぼれ落ちる
## → 立っていた床に、12時で止まった小さな懐中時計が一つだけ寝かせて残り、淡い光に照らされたまま（聖獣の剣・カラーと同じ。結果の画面まで）。

const T := {"slow": 0.30, "stop": 1.30, "crack": 1.50, "melt": 1.75, "gone": 2.85, "remain": 2.95, "end": 4.40}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#7a6030")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const WHITE := Color("#eafcff")
const POSE := 9
## 顔の時計（絵の画素）: 覚醒の2枚目（distress）の [中心, 半径, つぶれ, 傾き]
const FACE := [Vector2(172.5, 94.5), 8.6, 0.82, 0.2]

var awakened := false
var b_shaft: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_chain: RBMHeroFxBatch
var face_dial: ColorRect
var left: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.gone

func extra_poses() -> Dictionary:
	return {POSE: ["awaken", 2]}

func pose_keys() -> Array:
	return [[0.0, POSE]]

func _build() -> void:
	b_shaft = batch(back)
	b_chain = batch(front, false)
	left = dial_quad(front, {"seed": 5.0, "thick": 3.0})
	face_dial = dial_quad(front, {"seed": 17.0, "thick": 0.0, "brass_l": Vector3(.93, .80, .50), "brass": Vector3(.74, .56, .28), "brass_d": Vector3(.40, .27, .12),
		"face_l": Vector3(.96, .93, .84), "face_d": Vector3(.84, .78, .64), "steel": Vector3(.16, .12, .12)})
	b_front = batch(front, false)
	b_glow = batch(front)

## 残る懐中時計（床に寝かせた小さな時計。12時で止まり、ひびが入っている）。覚醒前の撃破（ユーザーが良いと言った形）
func remain_watch(t: float, t0: float, cracked: float) -> void:
	var o := RBMHeroFx.ramp(t, t0, t0 + 0.5)
	if o <= 0.0:
		left.visible = false
		return
	var c := HOME + Vector2(4, 0)
	# 光は消さずに照らし続ける（結果の画面まで残る）。呼吸するようにゆっくり明暗
	var g := o * (0.85 + 0.15 * sin(t * 2.6))
	light_shaft(b_shaft, c + Vector2(0, 2), 150.0, 8.0, 26.0, WHITE, 0.2 * g)
	disc(b_glow, c + Vector2(0, 1), 18.0, Color(TEAL_L, 0.14 * g), 0.3)
	# 鎖（時計から床へ垂れる）
	for k in range(6):
		var p0 := c + Vector2(11 + k * 3.2, 1.0 + sin(k * 1.3) * 0.8)
		b_chain.line(p0, p0 + Vector2(2.0, 0.3), 1.4, Color(BRASS, o), Color(BRASS_D, o))
	show_dial(left, c, 11.5, {"squash": 0.42, "rot": 0.05, "hour": 0.0, "minute": 0.0, "second": 0.0, "crack": cracked, "crack_at": Vector2(.2, -.1), "fade": o, "glow": 0.25 * g, "glow_col": Vector3(.6, .95, 1.)})
	embers(b_glow, Rect2(c.x - 16, c.y - 40, 32, 40), t, 8, 33, 22.0, Color(TEAL_L, 0.8), g * 0.7, 1.4, 4.0)

## 覚醒後の撃破に残る懐中時計（2026-11-16 ユーザー「覚醒後の撃破の最後に出る時計が分かりにくい」: 床に立てた懐中時計に。
## 上に竜頭と吊り輪、そこから床へ垂れる鎖。針は12時で止まり、ひびが入っている。覚醒前は寝かせた小さな時計のまま＝ユーザー「覚醒前はむしろよかった」）
const WATCH_R := 15.0
func remain_watch_upright(t: float, t0: float, cracked: float) -> void:
	var o := RBMHeroFx.ramp(t, t0, t0 + 0.5)
	if o <= 0.0:
		left.visible = false
		return
	var tilt := -0.18
	var foot := HOME + Vector2(4, 0)
	var c := foot + Vector2(0, -WATCH_R * 0.96 - 2.0)
	# 光は消さずに照らし続ける（結果の画面まで残る）。呼吸するようにゆっくり明暗
	var g := o * (0.85 + 0.15 * sin(t * 2.6))
	light_shaft(b_shaft, foot + Vector2(0, 2), 160.0, 10.0, 34.0, WHITE, 0.22 * g)
	# 竜頭（つまみ）と吊り輪（時計の上。傾きに合わせる）
	var up := Vector2(sin(tilt), -cos(tilt))
	var side := Vector2(-up.y, up.x)
	var crown := c + up * (WATCH_R + 1.5)
	var ring_c := c + up * (WATCH_R + 6.5)
	var dk := Color(BRASS_D, o)
	var lt := Color(BRASS, o)
	var ln := Color("#120c08", o)
	b_chain.quad(crown - side * 3.2 - up * 1.5, crown + side * 3.2 - up * 1.5, crown + side * 3.2 + up * 3.2, crown - side * 3.2 + up * 3.2, ln, ln, ln, ln)
	b_chain.quad(crown - side * 2.2 - up * 1.0, crown + side * 2.2 - up * 1.0, crown + side * 2.2 + up * 2.4, crown - side * 2.2 + up * 2.4, dk, lt, lt, dk)
	ring_line(b_chain, ring_c, 4.2, 3.4, ln)
	ring_line(b_chain, ring_c, 4.2, 1.6, lt, 1.0, 0.0, TAU, dk)
	# 鎖: 吊り輪から横へ出て、たるんで床へ落ち、床の上を少し這う（曲線。棒に見せない）
	var c0 := ring_c + side * 4.0
	var c1 := ring_c + side * 18.0 + Vector2(0, 2)
	var c2 := foot + Vector2(18, 1)
	var c3 := foot + Vector2(30, 1)
	var last := c0
	for k in range(18):
		var u := float(k + 1) / 18.0
		var p := c0.bezier_interpolate(c1, c2, c3, u)
		p.y = minf(p.y, foot.y + 1.0)
		b_chain.line(last, p, 2.2, ln, ln)
		b_chain.line(last, p, 1.0, lt if k % 2 == 0 else dk, lt if k % 2 == 0 else dk)
		last = p
	show_dial(left, c, WATCH_R, {"squash": 0.97, "rot": tilt, "thick": 2.0, "hour": 0.0, "minute": 0.0, "second": 0.0, "hot_mark": 0.0, "hot_col": Vector3(.6, .95, 1.), "hot": 0.6 * g,
		"crack": cracked, "crack_at": Vector2(.3, -.2), "piece": 0.7, "fade": o, "glow": 0.3 * g, "glow_col": Vector3(.6, .95, 1.)})
	# ガラスにときどき光が走る（目を引く）
	var gl := fmod(t * 0.6, 1.0)
	if gl < 0.25:
		var a0 := c + Vector2(-WATCH_R * 0.6, -WATCH_R * 0.2).rotated(tilt)
		var a1 := c + Vector2(WATCH_R * 0.4, -WATCH_R * 0.7).rotated(tilt)
		var s := a0.lerp(a1, gl / 0.25)
		b_glow.line(s - (a1 - a0).normalized() * 3.0, s + (a1 - a0).normalized() * 3.0, 1.4, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7 * o))
	embers(b_glow, Rect2(c.x - 18, c.y - 44, 36, 50), t, 8, 33, 22.0, Color(TEAL_L, 0.8), g * 0.7, 1.4, 4.0)

func _step(t: float) -> void:
	b_shaft.reset(); b_glow.reset(); b_front.reset(); b_chain.reset()
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.1], [T.stop, 0.3], [T.gone, 0.32], [T.end, 0.2]])
	view["dim_col"] = Color(0.0, 0.02, 0.04)
	# 顔の時計の針がだんだん遅くなり、12時でかちりと止まる（描かれた顔と同じ大きさの文字盤を重ねる）
	var u := RBMHeroFx.ramp(t, 0.0, T.stop)
	var minute := lerpf(-TAU * 2.0, 0.0, 1.0 - pow(1.0 - u, 3.0))
	var fade := 1.0 - RBMHeroFx.ramp(t, T.melt, T.melt + 0.3)
	if fade > 0.0:
		show_dial(face_dial, px(FACE[0]), float(FACE[1]), {"squash": float(FACE[2]), "rot": float(FACE[3]), "hour": minute * 0.083, "minute": minute, "second": -1.0,
			"crack": RBMHeroFx.ramp(t, T.crack, T.melt), "crack_at": Vector2(.3, -.3), "fade": fade})
	else:
		face_dial.visible = false
	if t >= T.stop and t < T.stop + 0.08:
		view["shake"] += Vector2(1.0 if int(t * 60.0) % 2 == 0 else -1.0, 0.0)
	# 止まった後は少し色が抜け、静寂
	view["hero"]["desat"] = 0.55 * RBMHeroFx.ramp(t, T.stop, T.stop + 0.3)
	view["hero"]["tint"] = 0.2 * RBMHeroFx.ramp(t, T.stop, T.melt)
	view["hero"]["tint_col"] = Color("#5a7a86")
	# 体が上から四角い粒でほどけ、ほどけた所からガラスと真鍮のかけらがこぼれる
	body["dissolve"] = smoothstep(T.melt, T.gone - 0.05, t)
	body["rise"] = 0.95
	body["block"] = 3.0
	body["edge"] = Color(TEAL_L, 0.95)
	body["shadow"] = 1.0 - body["dissolve"]
	for k in range(5):
		var kt := T.melt + (T.gone - T.melt) * (float(k) / 5.0)
		var o := HOME + Vector2(-8 + k * 4, -86 + k * 16)
		glass_shards(b_front, o, t - kt, 0.9, 8, 41 + k * 5, 90.0, 3.6, Color(CREAM, 0.95), Color("#9ab8c0", 0.95), 360.0, PI * 0.5, 2.4)
		glass_shards(b_front, o, t - kt - 0.05, 0.9, 4, 43 + k * 5, 80.0, 3.0, BRASS, BRASS_D, 380.0, PI * 0.5, 2.4)
	embers(b_glow, Rect2(HOME.x - 40, HOME.y - 100, 80, 100), t, 20, 9, 40.0, Color(TEAL_L, 0.8), RBMHeroFx.env(t, T.melt, T.melt + 0.3, T.gone, T.gone + 0.4), 1.8, 6.0)
	# 床に止まった懐中時計が残る
	remain_watch(t, T.remain, 0.25)
	b_shaft.commit(); b_glow.commit(); b_front.commit(); b_chain.commit()
