extends RBMHeroFxBase
## 老執事の覚醒「凍てつく刻」（2026-11-19 第2版。表示専用）。時刻は T（音の build もここを読む）。座標は論理ドット（足元からの相対）。
## 意味: 胸に手を当てて落ち着く → 懐中時計を高く掲げると、背後に大きな文字盤（振り子の給仕長と同じ懐中時計の盤を、銀と氷の色で）が現れ、
## 時を刻むたびに秒針が進み、足元から霜が床へ、文字盤のガラスにも霜のひびが広がる → 解放の直前に針がすべて12時へ走って重なる（時が凍る）
## → 解放: 両腕を広げると凍った文字盤が砕け散り、床を霜の輪が走り、冷たい霧が流れ、雪がゆっくり舞う。
## 2026-11-19 ユーザー「老執事は時計の要素を残して、ボスと関連があるのがわかるように」で文字盤を足した。
## 同日「前の床に時計があった演出も戻して（良いと思っていた）」で、足元の霜の文字盤を戻した: 胸に手を当てると床に文字盤が凍りつきながら描かれ、
## 秒針が刻むたびに目盛りから霜の枝が外へ伸びる → 針が12時へ走って一周し、全部の目盛りに霜が付いたところで止まる（時が凍る）→ 解放。
## 背後の文字盤の秒針は、床の秒針と同じ時刻を指す。
## 尖った氷の柱・三角のトゲ・雪の結晶の図形は使わない（霜のひびのシェーダー・千切れた輪・爆炎のシェーダーの冷たい色・粒）。

const T := {"compose": 0.25, "raise": 0.9, "rush": 1.55, "release": 1.9, "spread_end": 2.7, "settle": 3.3, "end": 3.7}
const CLOCKFACE := preload("res://src/bossmaker/visuals/clock/shaders/clockface.gdshader")
## 文字盤（背後の上。半径は論理ドット）
const DIAL_C := Vector2(0, -46)
const DIAL_R := 25.0
## 銀と氷の色（給仕長の真鍮・白磁の盤を冷たい色へ）
const SILVER := {"brass_l": Vector3(.92, .97, 1.), "brass": Vector3(.64, .74, .86), "brass_d": Vector3(.28, .36, .50), "face_l": Vector3(.50, .66, .84), "face_d": Vector3(.24, .36, .54), "ink": Vector3(.86, .94, 1.), "steel": Vector3(.96, .99, 1.), "sec_col": Vector3(.45, .88, 1.), "glow_col": Vector3(.55, .9, 1.), "hot_col": Vector3(.6, .95, 1.)}
## 時計（frames/08 の掲げた時計）・両手（frames/05）・胸（足元からの相対、論理ドット）
const WATCH := Vector2(-10, -49)
const HAND_L := Vector2(-26, -34)
const HAND_R := Vector2(28, -34)
const CHEST := Vector2(0, -36)
## 時を刻む間隔（秒）・針が12時へ走る間の速い刻みの間隔（音の build と同じ）
const TICK := 0.25
const RUSH_TICK := 0.05
## 足元の文字盤（論理ドット。前の版と同じ大きさ: 横46・縦はつぶし0.26）
const FLOOR_R := 46.0
const FLOOR_SQ := 0.26
const ICE := Color("#9fe6ff")
const FROST := Color("#e6fbff")
const DEEP := Color("#3f7fb3")
const ICE_PAL := ["#16203a", "#2a4a72", "#3f7fb3", "#6fb8e0", "#a8e0f5", "#d8f6ff", "#f0fcff", "#ffffff"]
const FROST_LINES := ["#2a5a80", "#7fc4e8", "#c8f0ff", "#ffffff"]

var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_floor: RBMHeroFxBatch
var frost: ColorRect
var ring: ColorRect
var dial: ColorRect

func _build() -> void:
	frost = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(FROST_LINES), "seed": 4.6, "squash": .3, "line_w": .03, "glow_col": Vector3(.5, .85, 1.), "glow": .35})
	b_floor = batch(back)
	ring = ring_quad(back, RBMHeroFx.R_BLUE, {"squash": .3, "breakup": .5, "seed": 3.7, "glow": .5, "glow_col": Vector3(.5, .85, 1.)})
	dial = ColorRect.new()
	dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = CLOCKFACE
	dial.material = dm
	dial.visible = false
	back.add_child(dial)
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_add.reset(); b_front.reset(); b_floor.reset()
	var ra := t - T.release
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.raise, 0.36], [T.release, 0.48], [T.release + 0.3, 0.32], [T.end, 0.0]])
	view["dim_col"] = Color(0.02, 0.04, 0.08)
	var raised := t >= T.raise and t < T.release
	var watch := foot + WATCH
	# 霜のひび: 針が12時へ走る間に文字盤の内側へ広がり（時が凍る）、解放で一気に外へ → 消える。ためる間は床の文字盤だけにする
	var reveal := 8.0 + 26.0 * RBMHeroFx.ramp(t, T.rush, T.release) + 60.0 * RBMHeroFx.burst(maxf(ra, 0.0), 6.0)
	var ff := 0.6 * RBMHeroFx.ramp(t, T.rush, T.rush + 0.2) * (1.0 - RBMHeroFx.ramp(ra, 0.6, 1.4))
	frost.visible = ff > 0.0
	if frost.visible:
		sp(frost, {"center": w(foot + Vector2(0, 1)), "reveal": reveal, "fade": ff})
	_floor_dial(t, ra)
	_dial(t, ra)
	# 時計を掲げる: 時を刻むたびに脈打つ光・冷気の粒が時計へ集まる
	if raised or (t >= T.release and ra < 0.05):
		var tick_age := fmod(t - T.raise, TICK)
		var beat := 1.0 - RBMHeroFx.ramp(tick_age, 0.0, 0.18)
		var gather := RBMHeroFx.ramp(t, T.raise, T.release)
		RBMHeroRooftop.glow(b_add, watch, 5.0 + 4.0 * gather + 3.0 * beat, Color(ICE, 0.45 + 0.35 * beat))
		RBMHeroRooftop.glow(b_add, watch, 2.0 + 1.0 * beat, Color(FROST, 0.9))
		_gather(watch, t, gather)
	# 胸に手を当てている間: 吐く息のような冷気が少し
	if t >= T.compose and t < T.raise:
		var c := RBMHeroFx.ramp(t, T.compose, T.raise)
		embers(b_add, Rect2(foot.x - 16, foot.y - 10, 32, 8), t, 8, 21, 22.0, Color(FROST, 0.8), c, 1.2, 4.0)
	# 解放: 冷気が弾ける・霜の輪・低く広がる冷たい霧・雪
	if ra >= 0.0:
		show_ring(ring, foot + Vector2(0, -1), ra, 0.6, 72.0, 4.0, 6.0, 0.0)
		_mist(ra)
		# 両手から冷気の粒が弾ける
		for hand in [HAND_L, HAND_R]:
			sparks(b_add, foot + hand, ra, 0.6, 16, 31 + int(hand.x), 120.0, FROST, ICE, (hand - CHEST).angle(), 1.2, 40.0, 1.2)
		sparks(b_add, foot + CHEST, ra, 0.7, 30, 35, 170.0, Color.WHITE, ICE, -PI * 0.5, PI * 1.6, 60.0, 1.3)
		_snow(t, ra)
		view["hero"]["flash"] = 0.65 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.22))
		view["hero"]["flash_col"] = FROST
		view["hero"]["lit"] = 0.45 * (1.0 - RBMHeroFx.ramp(ra, 0.2, 1.3))
		view["hero"]["lit_col"] = ICE
		set_post({"flash": 0.14 * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.1))})
	b_add.commit(); b_front.commit(); b_floor.commit()

## 秒針の角度（0＝12時、時計回り）。胸に手を当てると12時から刻み始め、掲げた後に残りを速く刻んで一周し、12時で止まる
func _hand_angle(t: float) -> float:
	if t >= T.release:
		return TAU
	if t >= T.rush:
		return (5.0 + minf(floorf((t - T.rush) / RUSH_TICK) + 1.0, 7.0)) * TAU / 12.0
	return clampf(floorf((t - T.compose) / TICK), 0.0, 5.0) * TAU / 12.0

## 秒針が目盛り m（1〜12）に届く時刻
func _mark_time(m: int) -> float:
	if m <= 5:
		return T.compose + float(m) * TICK
	return T.rush + float(m - 6) * RUSH_TICK

## 床の円を画面へ（縦をつぶす）
func _fl(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * FLOOR_SQ)

## 光る霜の線（にじみ＋芯）
func _frost_line(a: Vector2, b: Vector2, k: float, wide: float = 1.0) -> void:
	if k <= 0.003:
		return
	b_floor.line(a, b, 2.4 * wide, Color(ICE, 0.26 * k), Color(ICE, 0.26 * k))
	b_floor.line(a, b, 0.9 * wide, Color(FROST, 0.72 * k), Color(FROST, 0.72 * k))

## 足元の霜の文字盤（前の版の床の時計を戻したもの）: 外周が12時から凍りつきながら描かれ、秒針が刻むたびに目盛りから霜の枝が伸びる。
## 一周して12時で止まると全体が一段明るくなり、解放の霜の輪がここから走る。
func _floor_dial(t: float, ra: float) -> void:
	var appear := RBMHeroFx.ramp(t, T.compose, T.compose + 0.35)
	var a := appear * (1.0 - RBMHeroFx.ramp(ra, 0.15, 0.75))
	if a <= 0.003:
		return
	var c := foot + Vector2(0, 1)
	var flare := 1.0 + 0.6 * RBMHeroFx.ramp(t, _mark_time(12), T.release) * (1.0 - RBMHeroFx.ramp(ra, 0.0, 0.3))
	var k := a * flare
	# 外周と内周（霜らしく、区間ごとに明るさを少し変える）
	var n := 56
	for i in range(n):
		var u0 := float(i) / float(n)
		if u0 > appear:
			break
		var a0 := -PI * 0.5 + u0 * TAU
		var a1 := -PI * 0.5 + (u0 + 1.0 / float(n)) * TAU
		var jit := 0.7 + 0.3 * RBMHeroFx.r(i, 101)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		_frost_line(c + _fl(d0 * FLOOR_R), c + _fl(d1 * FLOOR_R), k * jit)
		_frost_line(c + _fl(d0 * FLOOR_R * 0.8), c + _fl(d1 * FLOOR_R * 0.8), k * jit * 0.5, 0.8)
	# 12の目盛り（3・6・9・12は長く明るい）と、秒針が届いた目盛りから外へ伸びる霜の枝
	for m in range(1, 13):
		var ang := -PI * 0.5 + float(m) * TAU / 12.0
		var dv := Vector2(cos(ang), sin(ang))
		var quarter := m % 3 == 0
		var mk := k * RBMHeroFx.ramp(appear, float(m) / 12.0 - 0.06, float(m) / 12.0)
		_frost_line(c + _fl(dv * FLOOR_R * (0.72 if quarter else 0.84)), c + _fl(dv * FLOOR_R * 0.97), mk * (1.0 if quarter else 0.65))
		var reach := _mark_time(m)
		if t < reach:
			continue
		var grow := RBMHeroFx.ramp(t, reach, reach + 0.12)
		grow = 1.0 - (1.0 - grow) * (1.0 - grow)
		var length := (10.0 + 6.0 * RBMHeroFx.r(m, 103)) * grow
		_frost_line(c + _fl(dv * FLOOR_R), c + _fl(dv * (FLOOR_R + length)), k * 0.9)
		for s in [-1.0, 1.0]:
			var sf := float(s)
			var mid := dv * (FLOOR_R + length * (0.42 + 0.12 * sf))
			_frost_line(c + _fl(mid), c + _fl(mid + dv.rotated(0.75 * sf) * length * 0.36), k * 0.6, 0.8)
		# 枝が生まれた瞬間のきらめき（小さく短く）
		var glint := 1.0 - RBMHeroFx.ramp(t, reach, reach + 0.15)
		if glint > 0.0:
			RBMHeroRooftop.glow(b_floor, c + _fl(dv * (FLOOR_R + length)), 3.0, Color(FROST, 0.7 * glint * a))
	# 秒針（中心から目盛りの手前まで）
	if t >= T.compose:
		var hang := -PI * 0.5 + _hand_angle(t)
		var tip := c + _fl(Vector2(cos(hang), sin(hang)) * FLOOR_R * 0.74)
		b_floor.line(c, tip, 2.8, Color(ICE, 0.35 * k), Color(ICE, 0.25 * k))
		b_floor.line(c, tip, 1.1, Color(1, 1, 1, 0.95 * a), Color(FROST, 0.9 * a))
		RBMHeroRooftop.glow(b_floor, c, 2.5, Color(FROST, 0.6 * a))

## 冷気の粒が、まわりから弧を描いて時計へ集まる（短い尾の粒）
func _gather(target: Vector2, t: float, power: float) -> void:
	if power <= 0.0:
		return
	for i in range(16):
		var q := fmod(t * (0.7 + 0.4 * RBMHeroFx.r(i, 61)) + RBMHeroFx.r(i, 62), 1.0)
		var a0 := RBMHeroFx.r(i, 63) * TAU
		var start := target + Vector2(cos(a0) * 34.0, sin(a0) * 22.0 + 10.0)
		var ctrl := start.lerp(target, 0.5) + Vector2(sin(a0) * 10.0, -cos(a0) * 10.0)
		var e := q * q * (3.0 - 2.0 * q)
		var e2 := maxf(0.0, e - 0.1)
		var p := start.lerp(ctrl, e).lerp(ctrl.lerp(target, e), e)
		var p2 := start.lerp(ctrl, e2).lerp(ctrl.lerp(target, e2), e2)
		var a := sin(q * PI) * power
		b_add.streak(p2, p, 1.4, Color(ICE, 0.8 * a), Color(DEEP, 0.0))
		b_add.dot_px(p, 1.3, Color(FROST, a))

## 雪がゆっくり舞い落ちる（解放の後。小さな粒が揺れながら落ちる）
func _snow(t: float, ra: float) -> void:
	var power := RBMHeroFx.ramp(ra, 0.05, 0.25) * (1.0 - RBMHeroFx.ramp(ra, 1.2, 1.8))
	if power <= 0.0:
		return
	for i in range(26):
		var x0 := foot.x + (RBMHeroFx.r(i, 71) - 0.5) * 90.0
		var y0 := foot.y - 70.0 - RBMHeroFx.r(i, 72) * 30.0
		var fall := ra * (14.0 + 10.0 * RBMHeroFx.r(i, 73))
		var p := Vector2(x0 + sin(ra * 3.0 + float(i)) * 4.0, y0 + fall)
		var tw := 0.6 + 0.4 * sin(t * 9.0 + float(i) * 2.1)
		b_add.dot_px(p, 1.2 + RBMHeroFx.r(i, 74), Color(FROST, 0.8 * power * tw))

## 冷たい霧が足元から床を外へ流れる（薄いもやの粒。丸い玉や平たい円盤にしない）
func _mist(ra: float) -> void:
	var power := 1.0 - RBMHeroFx.ramp(ra, 0.4, 1.1)
	if power <= 0.0:
		return
	for i in range(16):
		var a0 := RBMHeroFx.r(i, 81) * TAU
		var dir := Vector2(cos(a0), sin(a0) * 0.28)
		var dist := (10.0 + 50.0 * RBMHeroFx.r(i, 82)) * RBMHeroFx.burst(ra, 4.0)
		var p := foot + Vector2(0, -2) + dir * dist
		var rad := 5.0 + 6.0 * RBMHeroFx.ramp(ra, 0.0, 0.8)
		RBMHeroRooftop.glow(b_add, p, rad, Color(ICE, 0.16 * power))

## 背後の文字盤: 掲げると現れ、時を刻むたびに秒針が進み、ガラスに霜のひびが広がる → 針がすべて12時へ走る → 解放で砕け散る
func _dial(t: float, ra: float) -> void:
	var appear := RBMHeroFx.ramp(t, T.raise, T.raise + 0.25)
	var gone := RBMHeroFx.ramp(ra, 0.25, 0.65)
	var fade := appear * (1.0 - gone)
	if fade <= 0.003:
		dial.visible = false
		return
	var rush := RBMHeroFx.ramp(t, T.rush, T.release)
	rush = rush * rush
	# 秒針は床の秒針と同じ時刻（一周して12時で止まる）。分針・時針は解放の直前に12時へ走る
	var second := fmod(_hand_angle(t), TAU)
	var minute := lerpf(2.6, 0.0, rush) if t < T.release else 0.0
	var hour := lerpf(4.2, 0.0, rush) if t < T.release else 0.0
	var p := {"squash": 0.96, "thick": 3.0, "hour": hour, "minute": minute, "second": second,
		"glow": 0.3 + 0.5 * RBMHeroFx.ramp(t, T.raise, T.release), "crack": 0.38 * RBMHeroFx.ramp(t, T.raise + 0.2, T.release), "crack_at": Vector2(.25, -.3),
		"shatter": RBMHeroFx.ramp(ra, 0.0, 0.45), "hot_mark": 0.0, "hot": RBMHeroFx.ramp(t, T.rush, T.release), "fade": fade * 0.85, "seed": 2.0}
	p.merge(SILVER, true)
	var c := foot + DIAL_C
	var half := Vector2(DIAL_R * 1.45 + 6.0, DIAL_R * 1.45 + 12.0)
	dial.visible = true
	dial.position = (c - half).round()
	dial.size = (half * 2.0).round()
	p["size"] = dial.size
	p["center"] = c - dial.position
	p["r"] = DIAL_R
	sp(dial, p)
