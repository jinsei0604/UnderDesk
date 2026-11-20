class_name RBMWolfFx
extends RBMHeroFxBase
## 狼の技のエフェクト（2026-11-20 作り直し。表示専用。戦闘の状態・乱数には触れない）。
## 2026-11-20 ユーザー「狼はエフェクトも変えてほしい。動きのアイデアはいいけど機械的な動きだからそれを修正」→ 動きは rbm_wolf_motion.gd、
## エフェクトはヒーロー・聖獣と同じ部品（RBMHeroFxBase の帯・衝撃の輪・粒・屈折）で描き直す。前の版の灰色の細い爪の線の散らかり・
## 四角い粒の輪は使わない。
## mode: "single"（牙: 飛びかかって噛みつく）・"aoe"（疾走: 四人のまわりを駆け抜け、通り過ぎた後で爪の跡が一斉に裂ける）・"buff"/"heal"（遠吠え）。
## 座標は 640×360 の論理ドット（ステージの半分）。狼の位置の履歴は motion.sample() を過去の時刻で読む（ステージの座標）。

const WIND := ["#142440", "#24406c", "#3e6aa8", "#7aaee6", "#cfe6ff", "#ffffff"]
const FANG := ["#2a3650", "#5a74a0", "#a8c4ec", "#e4f0ff", "#ffffff", "#ffffff"]
const SNOW := Color("#e8f2ff")
const PALE := Color("#ffffff")
const MotionScript := preload("res://src/bossmaker/visuals/rbm_wolf_motion.gd")

var mode := "single"
var accent := Color("b7bbc2")
var motion: RefCounted
## 単体: 噛みつく所（論理ドット）
var contact := Vector2.ZERO
## 時刻（前のままの値）
var hit_time := 0.58
var claw_times: Array = []
## 着地 [[秒, 足元（ステージの座標）], ...]（土煙を出す）
var _landings: Array = []

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var trail: RBMHeroFxRibbon
var jaws: Array = []
var claws: Array = []
var arcs: Array = []
var rings: Array = []
## 全体: 見えない速さの斬撃（駆け抜けるたびに1本）と、最後に四人を貫く十字の斬撃
var dash_slashes: Array = []
var x_slashes: Array = []

func _build() -> void:
	b_back = batch(back, false)
	var glow_col := RBMHeroFx.v3(accent.lerp(Color("#9fd0ff"), 0.5))
	trail = ribbon(back, WIND, {"body": .55, "taper": .7, "skew": .9, "rough": .35, "rough_freq": 16., "streak": .6, "gain": 1.05, "glow": .35, "glow_col": Vector3(.5, .75, 1.), "seed": 3.0})
	for i in range(2):
		jaws.append(ribbon(front, FANG, {"body": .6, "taper": .85, "skew": .4, "rough": .1, "streak": .3, "gain": 1.2, "glow": .6, "glow_col": glow_col, "seed": 1.0 + i}))
	for i in range(12):
		claws.append(ribbon(front, FANG, {"body": .5, "taper": .9, "skew": .5, "rough": .15, "streak": .35, "gain": 1.2, "glow": .55, "glow_col": glow_col, "seed": 5.0 + i}))
	for i in range(3):
		arcs.append(ribbon(front, WIND, {"body": .5, "taper": .8, "skew": .5, "rough": .3, "streak": .5, "gain": 1.1, "glow": .5, "glow_col": RBMHeroFx.v3(accent), "seed": 9.0 + i}))
	if mode == "aoe":
		for i in range(MotionScript.AOE_LEGS):
			dash_slashes.append(ribbon(front, FANG, {"body": .55, "taper": .8, "skew": .6, "rough": .2, "streak": .4, "gain": 1.25, "glow": .7, "glow_col": glow_col, "seed": 20.0 + i}))
		for i in range(2):
			x_slashes.append(ribbon(front, FANG, {"body": .6, "taper": .85, "skew": .5, "rough": .15, "streak": .35, "gain": 1.3, "glow": .8, "glow_col": glow_col, "seed": 40.0 + i}))
	for i in range(2):
		rings.append(ring_quad(front, ["#2a4a7a", "#7aaee6", "#e4f0ff", "#ffffff"], {"squash": .32, "breakup": .55, "seed": 2.0 + i * 1.7, "glow": .45, "glow_col": glow_col}))
	b_add = batch(front)
	b_front = batch(front, false)
	if motion != null and mode in ["single", "aoe"]:
		_landings = motion.landings(mode, 3.0)

func _state(t: float) -> Dictionary:
	return motion.sample(mode, t) if motion != null else {"foot": foot * 2.0, "lift": 0.0, "air": false}

func _pos(t: float) -> Vector2:
	if motion == null:
		return foot
	var st: Dictionary = motion.sample("single" if mode == "single" else ("aoe" if mode == "aoe" else mode), t)
	return Vector2(st.foot) * 0.5

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	match mode:
		"single": _single(t)
		"aoe": _aoe(t)
		_: _howl(t)
	b_back.commit(); b_add.commit(); b_front.commit()

## 2026-11-20 第2版（ユーザー「浮いて絵を動かしてるように見える」「忙しい」）: 跳んでいる間は地面に影（高く跳ぶほど小さく薄く）、
## 着地した所だけ雪の土煙。走る間ずっと出していた雪の粒はやめた。風の帯は薄く。
func _ground(t: float) -> void:
	var st := _state(t)
	var lift := float(st.get("lift", 0.0))
	var g := (Vector2(st.foot) + Vector2(0, lift)) * 0.5
	var k := clampf(1.0 - lift / 40.0, 0.4, 1.0)
	_ellipse(b_back, g + Vector2(0, 1), 22.0 * k, 3.5 * k, Color(0.05, 0.05, 0.1, 0.45 * k) if bool(st.get("air", false)) and not bool(st.get("hidden", false)) else Color(0, 0, 0, 0))
	for l in _landings:
		var a := t - float(l[0])
		if a < 0.0 or a > 0.6:
			continue
		var p := Vector2(l[1]) * 0.5
		for k2 in range(5):
			var side := -1.0 if k2 % 2 == 0 else 1.0
			var q := RBMHeroFx.burst(a, 6.0)
			RBMHeroRooftop.glow(b_back, p + Vector2(side * (4.0 + 14.0 * q) * (0.6 + 0.4 * RBMHeroFx.r(k2, 3)), -2.0 - 4.0 * q * RBMHeroFx.r(k2, 4)), 3.0 + 4.0 * q, Color(SNOW, 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.1, 0.6))))
		for k3 in range(6):
			var v := Vector2((RBMHeroFx.r(k3, 7) - 0.5) * 50.0, -20.0 - 30.0 * RBMHeroFx.r(k3, 8))
			var pp := p + v * a + Vector2(0, 90.0 * a * a)
			if pp.y <= p.y + 1.0:
				b_front.dot_px(pp, 1.0, Color(SNOW, 0.85 * (1.0 - RBMHeroFx.ramp(a, 0.15, 0.5))))

## やわらかい楕円の影
func _ellipse(b: RBMHeroFxBatch, c: Vector2, rx: float, ry: float, col: Color) -> void:
	if col.a <= 0.005:
		return
	var edge := Color(col, 0.0)
	for i in range(20):
		var a0 := TAU * float(i) / 20.0
		var a1 := TAU * float(i + 1) / 20.0
		b.tri(c, c + Vector2(cos(a0) * rx, sin(a0) * ry), c + Vector2(cos(a1) * rx, sin(a1) * ry), col, edge, edge)

## 走る間: 体の後ろに薄い風の帯（跳んでいる時だけ）
func _run_wind(t: float, power: float) -> void:
	var pts := PackedVector2Array()
	for k in range(16):
		var p := _pos(t - 0.012 * k)
		pts.append(p + Vector2(0, -15))
	# 速さは少し前までの最大（一瞬止まる間も、駆け抜けた筋が少し残る）
	var speed := 0.0
	for k in range(4):
		var tk := t - 0.02 * k
		speed = maxf(speed, _pos(tk).distance_to(_pos(tk - 0.03)) / 0.03)
	var on := clampf((speed - 120.0) / 200.0, 0.0, 1.0) * power
	trail.visible = on > 0.02
	if trail.visible:
		trail.set_path(pts, 4.5 * on)
		sp(trail, {"head": 1.0, "tail": 0.0, "flow": t * 3.0, "fade": 0.5 * on})

## 牙: 飛び出しの風 → 噛みついた所で上下の牙の光が閉じる・白い芯・属性の火花・雪が弾ける
func _single(t: float) -> void:
	_ground(t)
	_run_wind(t, 1.0 - RBMHeroFx.ramp(t, hit_time + 0.05, hit_time + 0.2) + RBMHeroFx.ramp(t, 0.98, 1.1) * (1.0 - RBMHeroFx.ramp(t, 1.4, 1.55)))
	var a := t - hit_time
	for i in range(2):
		var r: RBMHeroFxRibbon = jaws[i]
		var s := -1.0 if i == 0 else 1.0
		var on := a >= -0.04 and a < 0.32
		r.visible = on
		if on:
			var p0 := contact + Vector2(-2, s * 18)
			var p1 := contact + Vector2(-14, s * 1.5)
			r.set_path(RBMHeroFx.bow(p0, p1, s * -6.0, 14), 2.6)
			sp(r, {"head": RBMHeroFx.ramp(a, -0.04, 0.02), "tail": RBMHeroFx.ramp(a, 0.06, 0.3), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(a, 0.18, 0.32)})
	if a < 0.0:
		return
	if a < 0.1:
		var k := 1.0 - a / 0.1
		RBMHeroRooftop.glow(b_add, contact + Vector2(-8, 0), 7.0 + 5.0 * k, Color(PALE, k))
		RBMHeroRooftop.glow(b_add, contact + Vector2(-8, 0), 15.0 + 6.0 * k, Color(accent, 0.55 * k))
	refract_wave(contact, a, 0.4, 100.0, 6.0, 0.025)
	sparks(b_add, contact + Vector2(-8, 0), a, 0.45, 46, 21, 260.0, PALE, accent, PI, 1.6, 160.0, 1.6)
	_snow_burst(contact + Vector2(-8, 4), a, 1.0, 31)
	var tf := Vector2(contact.x - 3, contact.y + 30)
	show_ring(rings[0], tf, a - 0.02, 0.45, 50.0, 4.0, 7.0, 0.0)

func _snow_burst(o: Vector2, a: float, power: float, seed_: int) -> void:
	if a < 0.0 or a > 0.9:
		return
	for i in range(int(16 * power)):
		var th := PI + (RBMHeroFx.r(i, seed_) - 0.5) * 2.4
		var v := Vector2.from_angle(th) * (40.0 + 70.0 * RBMHeroFx.r(i, seed_ + 1)) * power
		var p := o + v * a + Vector2(0, 60.0 * a * a)
		var f := 1.0 - RBMHeroFx.ramp(a, 0.3, 0.9)
		b_front.dot_px(p, 1.0 if i % 3 else 2.0, Color(SNOW, f))
	for k in range(4):
		RBMHeroRooftop.glow(b_back, o + Vector2(-10.0 * k * a * 4.0, -4.0 * k * a * 3.0), 4.0 + 10.0 * a, Color(SNOW, 0.3 * (1.0 - RBMHeroFx.ramp(a, 0.1, 0.7))))

## 全体（2026-11-20 第5版。ユーザー「切り刻む時は狼の姿を見せない」「切り刻むエフェクトをもっと派手に豪華に」）:
## 構えた狼が雪煙を残して消える → 四方八方から四人を突っ切る光の斬撃（太い帯・属性の光・雪と火花）だけが見えない速さで走る
## → 相手を通るたびに白い切り傷と光が弾ける → 元の場所に雪煙とともに現れ、振り向いてうなる
## → 爪の跡（大きな3本）と四人を貫く大きな十字の斬撃が一斉に裂け、光・衝撃の輪・雪と火花が吹き上がる。
func _aoe(t: float) -> void:
	_ground(t)
	var legs: Array = motion.aoe_legs() if motion != null else []
	var period: float = MotionScript.AOE_DASH + MotionScript.AOE_STOP
	var start: float = MotionScript.AOE_START
	var run_end: float = start + MotionScript.AOE_RUN
	# 消える・現れる: 雪煙と光の粒
	var home: Vector2 = (Vector2(motion.home) if motion != null else foot * 2.0) * 0.5
	_vanish(home, t - start, 61)
	_vanish(home, t - run_end, 63)
	# 見えない速さの斬撃（駆け抜けるたびに1本。頭が一瞬で走り、尾が追って消える）
	for i in range(mini(legs.size(), dash_slashes.size())):
		var r: RBMHeroFxRibbon = dash_slashes[i]
		var la := t - (start + float(i) * period)
		r.visible = la >= 0.0 and la < 0.42
		if not r.visible:
			continue
		var a: Vector2 = Vector2(legs[i][0]) * 0.5 + Vector2(0, -18)
		var b: Vector2 = Vector2(legs[i][1]) * 0.5 + Vector2(0, -18)
		var d := (b - a).normalized()
		r.set_path(RBMHeroFx.bow(a - d * 12.0, b + d * 12.0, (8.0 if i % 2 == 0 else -8.0), 24), 4.2)
		sp(r, {"head": RBMHeroFx.ramp(la, 0.0, MotionScript.AOE_DASH), "tail": RBMHeroFx.ramp(la, 0.05, 0.36), "flow": t * 3.0, "fade": 1.0 - RBMHeroFx.ramp(la, 0.24, 0.42)})
		# 走り抜けた後に残る細い光の筋
		var core := 1.0 - RBMHeroFx.ramp(la, 0.04, 0.22)
		if core > 0.0 and la >= MotionScript.AOE_DASH * 0.5:
			b_add.line(a, b, 0.8, Color(PALE, 0.8 * core), Color(PALE, 0.8 * core))
	var hit := t - hit_time
	var n := mini(targets.size(), 4)
	var c := Vector2.ZERO
	var m := 0
	for i in range(n):
		if not present[i]:
			continue
		c += Vector2(targets[i])
		m += 1
		var chest: Vector2 = Vector2(targets[i]) + Vector2(0, -26)
		# 相手を通るたびに: 白い切り傷（太く先細り）・属性の光・火花・雪
		var passes: Array = claw_times[i] if i < claw_times.size() else []
		for k in range(passes.size()):
			var pa := t - float(passes[k])
			if pa < 0.0 or pa > 0.35:
				continue
			var ang := -0.8 + 1.6 * RBMHeroFx.r(i * 7 + k, 81)
			var dir := Vector2.from_angle(ang + (PI if k % 2 == 1 else 0.0))
			var f := 1.0 - pa / 0.35
			var grow := RBMHeroFx.ramp(pa, 0.0, 0.04)
			var p0 := chest - dir * 18.0
			var p1 := p0 + dir * 36.0 * grow
			b_add.line(p0, p1, 5.0 * f, Color(accent, 0.35 * f), Color(accent, 0.35 * f))
			b_add.streak(p0, p1, 2.6 * f, Color(PALE, f), Color(PALE, 0.0))
			if pa < 0.08:
				var k2 := 1.0 - pa / 0.08
				RBMHeroRooftop.glow(b_add, chest, 10.0 * k2 + 3.0, Color(PALE, 0.7 * k2))
				RBMHeroRooftop.glow(b_add, chest, 18.0 * k2 + 4.0, Color(accent, 0.5 * k2))
			sparks(b_add, chest, pa, 0.32, 20, 91 + i * 9 + k, 220.0, PALE, accent, dir.angle(), 1.1, 140.0, 1.4)
			_snow_burst(chest + Vector2(0, 8), pa, 0.45, 131 + i * 11 + k)
		# 爪の跡が一斉に裂ける（大きな3本、少しずつずれて）
		for k in range(3):
			var r: RBMHeroFxRibbon = claws[i * 3 + k]
			var ca := hit - 0.035 * k
			r.visible = ca >= 0.0 and ca < 0.5
			if r.visible:
				var off := Vector2(-9.0 + 9.0 * k, -6.0 + 6.0 * k)
				r.set_path(RBMHeroFx.bow(chest + off + Vector2(22, -24), chest + off + Vector2(-22, 22), 5.0, 14), 3.4)
				sp(r, {"head": RBMHeroFx.ramp(ca, 0.0, 0.05), "tail": RBMHeroFx.ramp(ca, 0.1, 0.45), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(ca, 0.28, 0.5)})
		if hit >= 0.0:
			if hit < 0.1:
				var k3 := 1.0 - hit / 0.1
				RBMHeroRooftop.glow(b_add, chest, 14.0 * k3 + 5.0, Color(PALE, 0.75 * k3))
				RBMHeroRooftop.glow(b_add, chest, 26.0 * k3 + 6.0, Color(accent, 0.55 * k3))
			sparks(b_add, chest, hit, 0.55, 46, 41 + i, 300.0, PALE, accent, 0.0, TAU, 180.0, 1.8)
			_snow_burst(chest + Vector2(0, 10), hit, 1.0, 51 + i)
	if m == 0 or hit < 0.0:
		for x in x_slashes:
			(x as RBMHeroFxRibbon).visible = false
		return
	c /= float(m)
	# 四人を貫く大きな十字の斬撃
	for j in range(x_slashes.size()):
		var r: RBMHeroFxRibbon = x_slashes[j]
		var xa := hit - 0.04 * j
		r.visible = xa >= 0.0 and xa < 0.5
		if r.visible:
			var dir := Vector2(1.0, -0.42 if j == 0 else 0.42).normalized()
			var mid := c + Vector2(0, -22)
			r.set_path(RBMHeroFx.bow(mid - dir * 120.0, mid + dir * 120.0, 10.0 * (1.0 if j == 0 else -1.0), 28), 5.0)
			sp(r, {"head": RBMHeroFx.ramp(xa, 0.0, 0.06), "tail": RBMHeroFx.ramp(xa, 0.12, 0.46), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(xa, 0.3, 0.5)})
	show_ring(rings[0], c + Vector2(0, 6), hit, 0.55, 150.0, 5.0, 6.0, 0.03)
	show_ring(rings[1], c + Vector2(0, 6), hit - 0.07, 0.5, 110.0, 3.5, 6.0, 0.0)
	refract_wave(c + Vector2(0, -20), hit, 0.7, 300.0, 5.0, 0.04)
	view["shake"] += hit_shake(hit, 10.0, 80.0, 0.45)
	set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(hit, 0.0, 0.1))})
	ally_light(RBMHeroFx.env(hit, 0.0, 0.04, 0.2, 0.6), Color("#cfe6ff"), 0.0)

## 消える・現れる時の雪煙と光の粒
func _vanish(p: Vector2, a: float, seed_: int) -> void:
	if a < 0.0 or a > 0.7:
		return
	var f := 1.0 - RBMHeroFx.ramp(a, 0.15, 0.7)
	var q := RBMHeroFx.burst(a, 7.0)
	for k in range(7):
		var side := -1.0 if k % 2 == 0 else 1.0
		RBMHeroRooftop.glow(b_back, p + Vector2(side * (6.0 + 22.0 * q * (0.5 + 0.5 * RBMHeroFx.r(k, seed_))), -4.0 - 14.0 * q * RBMHeroFx.r(k, seed_ + 1)), 5.0 + 8.0 * q, Color(SNOW, 0.45 * f))
	if a < 0.08:
		RBMHeroRooftop.glow(b_add, p + Vector2(0, -20), 16.0 * (1.0 - a / 0.08) + 4.0, Color(PALE, 0.5 * (1.0 - a / 0.08)))
	sparks(b_add, p + Vector2(0, -18), a, 0.4, 24, seed_ + 5, 160.0, PALE, Color("#9fd0ff"), 0.0, TAU, 60.0, 1.2)

## 遠吠え: 上げた口から音の弧が広がり、体のまわりに色の光の粒が立ちのぼる → 足元に色の衝撃の輪
func _howl(t: float) -> void:
	var mouth := foot + Vector2(-27, -72)
	var strength := RBMHeroFx.env(t, 0.3, 0.5, 1.6, 2.1)
	for i in range(3):
		var r: RBMHeroFxRibbon = arcs[i]
		var a := t - 0.5 - 0.22 * i
		r.visible = a >= 0.0 and a < 0.7
		if r.visible:
			var rad := 10.0 + 70.0 * RBMHeroFx.burst(a, 4.0)
			var pts := PackedVector2Array()
			for k in range(14):
				var ang := lerpf(-2.6, -1.0, float(k) / 13.0)
				pts.append(mouth + Vector2(cos(ang), sin(ang)) * rad)
			r.set_path(pts, 2.4 * (1.0 - a / 0.7) + 0.6)
			sp(r, {"head": 1.0, "tail": 0.0, "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(a, 0.35, 0.7)})
	embers(b_add, Rect2(foot.x - 34, foot.y - 80, 68, 80), t, 30, 61, 50.0, accent, strength, 1.6, 8.0)
	RBMHeroRooftop.glow(b_back, foot + Vector2(0, -34), 36.0, Color(accent, 0.14 * strength))
	var a2 := t - hit_time
	show_ring(rings[0], foot, a2, 0.6, 110.0, 6.0, 6.0, 0.02)
	show_ring(rings[1], foot, a2 - 0.08, 0.6, 80.0, 4.0, 6.0, 0.0)
	if a2 >= 0.0 and a2 < 0.12:
		RBMHeroRooftop.glow(b_add, foot + Vector2(0, -36), 26.0 + 12.0 * (1.0 - a2 / 0.12), Color(accent, 0.4 * (1.0 - a2 / 0.12)))
	sparks(b_add, foot + Vector2(0, -36), a2, 0.7, 36, 71, 180.0, PALE, accent, -PI * 0.5, PI * 1.4, 80.0, 1.5)
