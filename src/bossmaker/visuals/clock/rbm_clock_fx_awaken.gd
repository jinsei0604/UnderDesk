extends RBMClockFxBase
## 本番（2026-11-16 ユーザー「これが終わったら実装していいよ」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/awaken.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長 → 終刻の給仕長「振り子の分岐」（2026-11-16 v3。ユーザー「迫力がない・技の一つ一つに意味があるように」。覚醒は各ボス最大の見せ場）:
## 意味: 「一本の時間が二つに分かれ（過去と未来）、ぶつかって“終わりの時刻”になる」。
## 顔の時計の針が狂ったように回る → 盤に手を添えて崩れる（戦場が暗くなる）→ 針が止まり、時が止まる（静寂）
## → 背後に巨大な大時計が現れ、ひびが走る。歯車がかみ合い、一本の振り子が揺れ始める（彼の時間）
## → 振り子が真ん中を通った瞬間、二つに分かれる（分岐）: 青緑の振り子＝過去、深紅の振り子＝未来。大時計の分針も二本に分かれ、青緑は逆へ、深紅は先へ回る。
##   彼の残像も青緑は後ろへ、深紅は前へ流れる
## → 二つの振り子が大きく開き、二本の針が12時へ向かって走る → 真ん中でぶつかり、両針が12時で重なる（鐘の一打・ヒットストップ）
## → 大時計が砕け、光の爆発の中から終刻の給仕長（常時のオーラ）。

const T := {"spin": 0.30, "distress": 0.90, "silence": 1.50, "crack": 2.00, "early": 2.40, "split": 2.95, "late": 3.50, "converge": 4.15, "done": 4.80, "end": 6.60}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#7a6030")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const CYAN := Color("#7ee0ec")
const CRIMSON := Color("#e03848")
const INK := Color("#141418")
const STEEL := [Color("#1a2440"), Color("#8aa2e0"), Color("#0a0a12")]
## 覚醒の光の爆発（外側を黒くしない: 暗い雲に見えた）
const BURST := ["#145a78", "#1e78a0", "#2aa0c0", "#5ac8dc", "#9ae8f0", "#d8fafc", "#f0feff", "#ffffff"]
## 過去（青緑）・未来（深紅）の振り子のおもりの色
const PAST := {"brass_l": Vector3(.75, .98, 1.0), "brass": Vector3(.30, .62, .70), "brass_d": Vector3(.08, .22, .28), "glow": 0.7, "glow_col": Vector3(.45, .92, 1.)}
const FUTURE := {"brass_l": Vector3(1.0, .72, .72), "brass": Vector3(.72, .22, .26), "brass_d": Vector3(.26, .05, .08), "glow": 0.7, "glow_col": Vector3(1., .3, .38)}
## 歯車: [大時計の中心からの位置, 半径, 歯の数, 回る向き]
const GEARS := [[Vector2(-140, -40), 40.0, 16.0, 1.0], [Vector2(-96, 52), 24.0, 11.0, -1.65], [Vector2(138, -58), 32.0, 14.0, -1.25], [Vector2(150, 30), 22.0, 10.0, 1.8], [Vector2(-30, -118), 26.0, 12.0, 1.5]]
const PEND_LEN := 236.0
## 顔の時計（絵の画素）: [中心, 半径, 縦のつぶれ, 傾き]。覚醒の1枚目（normal）・2枚目（distress）
const FACES := [[Vector2(169.5, 82.0), 8.6, 0.94, 0.12], [Vector2(172.5, 94.5), 8.6, 0.82, 0.2]]

var b_back: RBMHeroFxBatch
var b_rod_line: RBMHeroFxBatch
var b_rod: RBMHeroFxBatch
var b_add_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_line: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var big: ColorRect
var gears: Array = []
var bobs: Array = []
var blast: ColorRect
## 顔の時計に重ねる文字盤（描かれた顔と同じ大きさ・位置。針だけが回る）
var face_dial: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.done

func stops() -> Array:
	return [[T.done, 0.18]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.distress, 2], [T.early, 3], [T.late, 4], [T.done, 5]]

func _build() -> void:
	b_back = batch(back, false)
	big = dial_quad(back, {"seed": 11.0, "thick": 8.0})
	for g in GEARS:
		gears.append(gear_quad(back, {"teeth": g[2], "spokes": 6.0 if float(g[1]) > 30.0 else 5.0}))
	b_rod_line = batch(back, false)
	b_rod = batch(back, false)
	b_add_back = batch(back)
	for i in range(3):
		bobs.append(dial_quad(back, {"seed": 13.0 + i, "thick": 4.0}))
	# 顔に重ねる文字盤（色は立ち絵の顔に合わせる）
	face_dial = dial_quad(front, {"seed": 17.0, "thick": 0.0, "brass_l": Vector3(.93, .80, .50), "brass": Vector3(.74, .56, .28), "brass_d": Vector3(.40, .27, .12),
		"face_l": Vector3(.96, .93, .84), "face_d": Vector3(.84, .78, .64), "steel": Vector3(.16, .12, .12)})
	blast = blast_quad(front, BURST, BURST, {"amp": 30., "k": .05, "seed": 5.2, "glow": .7, "glow_col": Vector3(.5, .9, 1.), "glow_r": 50.})
	b_line = batch(front, false)
	b_front = batch(front, false)
	b_add = batch(front)

## 振り子の角度（0＝真下）。一本の間は真ん中を split で通るように揺れる。分かれた後は過去が左・未来が右へ大きく開き、converge から真ん中へ戻って done でぶつかる
func _swing(t: float, branch: int) -> float:
	var period := 1.1
	var amp := 0.34 * RBMHeroFx.ramp(t, T.early, T.early + 0.4)
	if t < T.split:
		return amp * sin((t - T.split) / period * TAU)
	var open := RBMHeroFx.ramp(t, T.split, T.late)
	var side := -1.0 if branch == 0 else 1.0
	var swing := side * (0.18 + 0.36 * open) * absf(sin((t - T.split) / period * TAU * 0.5 + 0.0001))
	var back := RBMHeroFx.ramp(t, T.converge, T.done)
	return lerpf(swing, 0.0, back * back)

func _step(t: float) -> void:
	b_back.reset(); b_rod_line.reset(); b_rod.reset(); b_add_back.reset(); b_add.reset(); b_line.reset(); b_front.reset()
	var ab := t - T.done
	var face := at("mark", 1) if t < T.distress else at("mark", 2 if t < T.early else (3 if t < T.late else 4))
	var dc := HOME + Vector2(0, -96)
	var silent := RBMHeroFx.env(t, T.silence, T.silence + 0.03, T.early - 0.1, T.early + 0.2)
	var branch := RBMHeroFx.ramp(t, T.split, T.split + 0.12) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.05))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.distress, 0.3], [T.silence, 0.45], [T.converge, 0.62], [T.done - 0.02, 0.72], [T.done + 0.1, 0.15], [T.end, 0.2]])
	view["dim_col"] = Color(0.0, 0.02, 0.05)
	# 顔の時計の針が狂ったように回る（止まると止まる）。2026-11-16 ユーザー「顔の針が変に見える。アイデアはいい」:
	# 顔の上に別の針を浮かべるのをやめ、描かれた顔と同じ大きさ・位置の文字盤を重ねて、その針だけを回す（FACES は絵を拡大して測った）
	var fd: Array = FACES[1] if t >= T.distress else FACES[0]
	if t >= T.spin and t < T.early:
		var spin := minf(t, T.silence) - T.spin
		var sp_ := spin * spin * 11.0 + spin * 2.0
		show_dial(face_dial, px(fd[0]), float(fd[1]), {"squash": float(fd[2]), "rot": float(fd[3]), "hour": 4.2 + sp_ * 0.083, "minute": sp_, "second": -1.0, "fade": 1.0 - RBMHeroFx.ramp(t, T.early - 0.1, T.early)})
	else:
		face_dial.visible = false
	if t < T.early:
		if t < T.silence:
			view["shake"] += Vector2(sin(t * 40.0), 0.0) * 0.6 * RBMHeroFx.ramp(t, T.spin, T.silence)
	# 時が止まる（静寂）
	time_stop_post(silent)
	sweep_hand(b_add, RBMHeroFx.ramp(t, T.silence - 0.02, T.silence + 0.24), Color(TEAL_L, 0.24))
	# 背後の大時計: 現れる → ひび → 分針が二本に分かれる（過去は逆へ・未来は先へ）→ 12時で重なる → 砕ける
	var app := RBMHeroFx.ramp(t, T.crack - 0.25, T.crack + 0.2)
	var crack := RBMHeroFx.ramp(t, T.crack, T.done)
	var shat := RBMHeroFx.ramp(ab, 0.0, 0.45)
	var run := maxf(0.0, t - T.early)
	var meet := RBMHeroFx.ramp(t, T.converge, T.done - 0.04)
	var past := lerp_angle(-run * 4.0, 0.0, meet * meet) if t >= T.split else -run * 0.6
	var future := lerp_angle(run * 4.0, 0.0, meet * meet) if t >= T.split else -run * 0.6
	if app > 0.0 and shat < 1.0:
		show_dial(big, dc, 128.0, {"squash": 0.94, "hour": lerp_angle(4.2, 0.0, meet), "minute": past, "second": future if branch > 0.5 else -1.0,
			"sec_col": Vector3(.95, .25, .3), "steel": Vector3(.12, .3, .36), "hot_mark": 0.0, "hot": meet,
			"glow": 0.25 + 0.6 * crack + 0.6 * meet, "glow_col": Vector3(.5, .92, 1.), "crack": crack, "shatter": shat, "fade": app, "dark": 0.5 - 0.3 * crack})
	else:
		big.visible = false
	var gon := RBMHeroFx.ramp(t, T.early - 0.1, T.early + 0.3) * (1.0 - RBMHeroFx.ramp(ab, 0.3, 0.6))
	for i in range(GEARS.size()):
		var g: Array = GEARS[i]
		var fly := RBMHeroFx.ramp(ab, 0.0, 0.6)
		var out := Vector2(g[0]).normalized() * 200.0 * fly + Vector2(0, 220.0 * fly * fly)
		# 分かれた後は左の歯車は逆へ、右の歯車は先へ（過去と未来）
		var dirsign := (-1.0 if float(g[0].x) < 0.0 else 1.0) if t >= T.split else 1.0
		show_gear(gears[i], dc + Vector2(g[0]) + out, float(g[1]), {"rot": run * 1.6 * float(g[3]) * dirsign + fly * 8.0, "fade": gon, "dark": 0.35 - 0.2 * crack, "glow": 0.35 * crack,
			"glow_col": Vector3(.5, .92, 1.) if float(g[0].x) < 0.0 else Vector3(1., .3, .38)})
	# 振り子: 一本 → 真ん中で二つに分かれる（青緑＝過去・深紅＝未来）→ 開く → 真ん中でぶつかる
	var pv := dc + Vector2(0, -132)
	var p_on := RBMHeroFx.ramp(t, T.early, T.early + 0.25) * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.2))
	if branch < 1.0:
		pendulum(b_rod_line, b_rod, bobs[2], pv, PEND_LEN, _swing(t, 0) if t < T.split else 0.0, 24.0, p_on * (1.0 - branch), {"glow": 0.3, "glow_col": Vector3(.6, .95, 1.), "dark": 0.1})
	else:
		bobs[2].visible = false
	for k in range(2):
		if branch > 0.0:
			var c := pendulum(b_rod_line, b_rod, bobs[k], pv, PEND_LEN, _swing(t, k), 24.0, p_on * branch, PAST if k == 0 else FUTURE)
			# 振り子の通った跡（その色の薄い弧）
			for j in range(1, 4):
				var aj := _swing(t - j * 0.03, k)
				var cj := pv + Vector2(sin(aj), cos(aj)) * PEND_LEN
				b_add_back.line(cj + Vector2(-14, 0), cj + Vector2(14, 0), 6.0, Color(CYAN if k == 0 else CRIMSON, 0.12 * (4 - j) * branch), Color(CYAN if k == 0 else CRIMSON, 0.0))
		else:
			bobs[k].visible = false
	# 分かれる瞬間: 真ん中で光が割れる
	var sa := t - T.split
	if sa >= 0.0 and sa < 0.5:
		var sc := pv + Vector2(0, PEND_LEN)
		sparks(b_add, sc, sa, 0.45, 40, 71, 300.0, CYAN, TEAL, PI, PI * 0.8, 60.0, 1.6)
		sparks(b_add, sc, sa, 0.45, 40, 73, 300.0, Color("#ffd0d4"), CRIMSON, 0.0, PI * 0.8, 60.0, 1.6)
		view["shake"] += hit_shake(sa, 5.0, 90.0, 0.2)
		set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(sa, 0.0, 0.12)), "flash_col": Vector3(.9, .95, 1.0)})
	# 分かれた後: 残像の過去は後ろへ（青緑）、未来は前へ（深紅）
	if branch > 0.0 and ab < 0.0:
		var pose_n := 3 if t < T.late else 4
		var amt := RBMHeroFx.ramp(t, T.split, T.late)
		for k in range(3):
			var f := float(k + 1)
			ghost(pose_n, Vector2(12.0 * f, 0) * amt, 0.2 * branch * (1.0 - k * 0.25), TEAL, 0.55)
			ghost(pose_n, Vector2(-12.0 * f, 0) * amt, 0.2 * branch * (1.0 - k * 0.25), CRIMSON, 0.55)
		embers(b_add, Rect2(HOME.x - 130, HOME.y - 220, 110, 220), t, 24, 19, -70.0, Color(CYAN, 0.9), branch, 2.0, 6.0)
		embers(b_add, Rect2(HOME.x + 20, HOME.y - 220, 110, 220), t, 24, 21, 90.0, Color(CRIMSON, 0.9), branch, 2.0, 6.0)
	# ぶつかる直前: 光が集まり、オーラが燃え始め、揺れが強まる
	var rush := RBMHeroFx.ramp(t, T.late, T.done)
	if ab < 0.0:
		inward(b_add, at("center", 4 if t >= T.late else 3), t, 40, 23, 10.0, 180.0, 1.6, Color(CYAN, 0.9), meet * meet, 2.2)
		view["hero"]["lit"] = 0.5 * rush
		view["hero"]["lit_col"] = CYAN
		view["hero"]["sun_aura"] = 2.0 * RBMHeroFx.ramp(t, T.late, T.done)
		view["shake"] += Vector2(sin(t * 37.0), cos(t * 29.0) * 0.5) * 3.0 * meet * meet
	# 鐘の一打: 二つの振り子が真ん中でぶつかり、両針が12時で重なる → 大時計が砕け、光の中から覚醒後
	if ab >= 0.0:
		view["hero"]["flash"] = 0.9 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3))
		view["hero"]["flash_col"] = Color("#e6fcff")
		view["hero"]["sun_aura"] = 1.0 + 1.6 * (1.0 - RBMHeroFx.ramp(ab, 0.1, 1.2))
		var hit_p := pv + Vector2(0, PEND_LEN)
		glass_shards(b_front, dc, ab, 1.5, 60, 41, 700.0, 8.0, Color(CREAM, 1.0), Color("#9ab8c0", 1.0), 240.0)
		glass_shards(b_front, dc, ab, 1.4, 30, 43, 620.0, 6.0, BRASS, BRASS_D, 280.0)
		glass_shards(b_add, hit_p, ab, 1.0, 26, 45, 560.0, 4.5, Color(CYAN, 0.9), Color(TEAL, 0.6), 200.0)
		glass_shards(b_add, hit_p, ab, 1.0, 26, 47, 560.0, 4.5, Color("#ffb0b8", 0.9), Color(CRIMSON, 0.6), 200.0)
		sparks(b_add, HOME + Vector2(0, -60), ab, 0.9, 150, 49, 860.0, Color("#e6fcff"), CYAN, 0.0, TAU, 140.0, 2.0)
		view["shake"] += hit_shake(ab, 20.0, 65.0, 0.7)
		set_post({"flash": 0.34 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.18)), "flash_col": Vector3(.85, .98, 1.0), "chroma": 0.005 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3)),
			"vig": 0.35 * (1.0 - RBMHeroFx.ramp(ab, 0.4, 1.4)), "vig_col": Vector3(.0, .04, .08), "vig_r": .3})
		ally_light(RBMHeroFx.env(ab, 0.0, 0.05, 0.3, 0.9), CYAN, -1.0)
	var ba := ab + 0.08
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.35, 0.8)
	blast.visible = ab >= 0.0 and bf > 0.0
	if blast.visible:
		var bc := HOME + Vector2(0, -50)
		show_blast(blast, blobs(bc, ba, 30, 27, 240.0, 150.0, 70.0, 90.0, .5, 0.0, 7.5), ba, {"flow": ba * .25, "cool": .05 + RBMHeroFx.ramp(ba, .2, .9) * .2, "erode": RBMHeroFx.ramp(ba, .25, .8), "fade": bf, "erode_noise": .4,
			"polar": 0.6, "detail": .5, "radial_heat": .45, "heat_center": w(bc), "heat_radius": 260.0 * RBMHeroFx.burst(ba, 7.5), "erode_radial": 160.0, "tone_cap": .98})
	# 余韻: 青緑の粒がゆっくり昇る
	embers(b_add, Rect2(HOME.x - 90, HOME.y - 160, 180, 160), t, 30, 51, 40.0, Color(CYAN, 0.8), RBMHeroFx.env(ab, 0.3, 0.8, 1.4, 1.8), 2.0, 8.0)
	b_back.commit(); b_rod_line.commit(); b_rod.commit(); b_add_back.commit(); b_add.commit(); b_line.commit(); b_front.commit()
