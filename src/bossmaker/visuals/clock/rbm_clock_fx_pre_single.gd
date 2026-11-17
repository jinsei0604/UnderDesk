extends RBMClockFxBase
## 本番（2026-11-16 ユーザー「これが終わったら実装していいよ」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/pre_single.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長・覚醒前単体「指針突き」（2026-11-16 v3。ユーザー「迫力がない・技の一つ一つに意味があるように。ぽいやつをつなげているように見える」）:
## 意味: 「お前が打たれる時刻はもう決まっている」。
## 構え → 相手の胸の前に懐中時計を差し出す（蓋が開くように現れる。12時の目盛りが青く光る＝定められた時刻）
## → 秒針が 9 → 10 → 11 と一刻ずつ進む（かち、かち、かち）→ 12 に届いた瞬間、時が止まる（巨大な秒針の影が横切り、色が抜け、塵が宙で止まる）
## → 止まった時の中で相手の前へ移り、指先から長い針を突き出す: 針は懐中時計の真ん中を通り、胸の手前で止まる（何も起きない静寂）
## → 時が動き出した瞬間、止めていた一撃がまとめて届く（色が一気に戻る・閃光・ヒットストップ・懐中時計が砕け散る・大きな揺れ・相手が大きく吹き飛ぶ）→ 元の位置へ一瞬で戻る。

const T := {"draw": 0.22, "dial": 0.30, "ticks": [0.58, 0.80, 1.02], "stop": 1.02, "appear": 1.08, "thrust": 1.14, "resume": 1.58, "follow": 1.80, "back": 2.08, "end": 2.55}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#7a6030")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const INK := Color("#141418")
const STEEL := [Color("#1a2440"), Color("#8aa2e0"), Color("#0a0a12")]

var b_add: RBMHeroFxBatch
var b_line: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var watch: ColorRect
var blast: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.resume

func stops() -> Array:
	return [[T.resume, 0.11]]

func _reach() -> Vector2:
	return Vector2(-112, 26) + focus_delta

func pose_keys() -> Array:
	return [[0.0, 1], [T.draw, 2], [T.appear, 3], [T.follow, 4], [T.back, 1]]

func move_keys() -> Array:
	var r := _reach()
	return [[0.0, Vector2.ZERO, "snap"], [T.appear, Vector2.ZERO, "snap"], [T.appear + 0.001, r, "snap"], [T.back, r, "snap"], [T.back + 0.001, Vector2.ZERO, "snap"]]

func _build() -> void:
	blast = blast_quad(back, ["#145a78", "#1e78a0", "#2aa0c0", "#5ac8dc", "#9ae8f0", "#d8fafc", "#f0feff", "#ffffff"], BRASS_PAL, {"amp": 16., "k": .08, "seed": 2.6, "glow": .5, "glow_col": Vector3(.5, .9, 1.), "glow_r": 26.})
	watch = dial_quad(front, {"seed": 4.0, "thick": 3.0})
	b_line = batch(front, false)
	b_front = batch(front, false)
	b_add = batch(front)

## 移った後の指先（構えの前でも、移った先の指先の位置を出す）
func _finger() -> Vector2:
	return at("front", 3) - Vector2(body.get("off", Vector2.ZERO)) + _reach()

func _step(t: float) -> void:
	b_add.reset(); b_line.reset(); b_front.reset()
	var hit := target_chest(3)
	var finger := _finger()
	# 懐中時計は指先と胸を結ぶ線の上（針が真ん中を通る）
	var wc := finger.lerp(hit, 0.7) + Vector2(0, -2)
	var stopped := RBMHeroFx.env(t, T.stop, T.stop + 0.03, T.resume - 0.001, T.resume)
	var a := t - T.resume
	# 懐中時計: 蓋が開くように現れる（縦につぶれた所から開く）。秒針は 9時から一刻ずつ 12時へ
	var on := RBMHeroFx.ramp(t, T.dial, T.dial + 0.16)
	var sec := -PI * 0.5
	var ticks: Array = T.ticks
	for i in range(ticks.size()):
		var tk := float(ticks[i])
		sec += PI / 6.0 * smoothstep(tk - 0.03, tk, t)
		if t >= tk and t < tk + 0.08:
			view["shake"] += Vector2(1.0 if int(t * 60.0) % 2 == 0 else -1.0, 0.0) * (1.0 - (t - tk) / 0.08)
	var shat := RBMHeroFx.ramp(a, 0.0, 0.26)
	if on > 0.0 and shat < 1.0:
		show_dial(watch, wc, 22.0, {"squash": 0.92 * (0.15 + 0.85 * on * on), "rot": -0.1, "hour": 5.24, "minute": 0.0, "second": sec,
			"hot_mark": 0.0, "hot_col": Vector3(.55, .95, 1.), "hot": 0.6 + 0.4 * sin(t * 18.0) * float(t < T.stop),
			"glow": 0.15 + 0.6 * stopped, "crack": RBMHeroFx.ramp(t, T.thrust, T.thrust + 0.05) * 0.35 + RBMHeroFx.ramp(a, 0.0, 0.05), "shatter": shat, "fade": on})
	else:
		watch.visible = false
	# 12時に届いた瞬間、時が止まる
	time_stop_post(stopped)
	view["dim"] = 0.16 * stopped
	view["dim_col"] = Color(0.0, 0.03, 0.05)
	sweep_hand(b_add, RBMHeroFx.ramp(t, T.stop - 0.02, T.stop + 0.2), Color(TEAL_L, 0.24))
	var frozen := minf(t, T.stop) if t < T.resume else t - (T.resume - T.stop)
	embers(b_add, Rect2(hit.x - 60, hit.y - 60, 120, 80), frozen, 18, 17, 12.0, Color(CREAM, 0.8), RBMHeroFx.env(t, T.dial, T.stop, T.resume, T.resume + 0.3), 1.6, 6.0)
	# 止まった間に移る（元の位置に残像）
	if t >= T.appear and t < T.back:
		ghost(2, Vector2.ZERO, 0.42 * (1.0 - RBMHeroFx.ramp(t, T.appear, T.resume + 0.2)), TEAL, 0.6)
	# 指先から長い針: 懐中時計の真ん中を通り、胸の手前で止まる → 時が動くと胸を貫く
	if t >= T.thrust - 0.06 and t < T.follow:
		var ext := RBMHeroFx.ramp(t, T.thrust - 0.06, T.thrust)
		var rest := hit + (finger - hit).normalized() * 7.0
		var tip := finger.lerp(rest, ext)
		if a >= 0.0:
			tip = rest.lerp(hit + (hit - finger).normalized() * 16.0, RBMHeroFx.ramp(a, 0.0, 0.03))
		var fade := 1.0 - RBMHeroFx.ramp(t, T.follow - 0.12, T.follow)
		breguet_hand(b_line, b_front, finger, tip, 2.0, STEEL, fade)
		if stopped > 0.5:
			b_add.line(finger, tip, 4.0, Color(TEAL_L, 0.0), Color(TEAL_L, 0.3))
	# 時が動き出す: 止めていた一撃がまとめて届く（色が一気に戻る・閃光・砕け散る・大きな揺れ）
	if a >= 0.0:
		set_post({"flash": 0.3 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.12)), "flash_col": Vector3(.85, .98, 1.0), "chroma": 0.004 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2))})
		glass_shards(b_front, wc, a, 0.85, 30, 11, 420.0, 4.6, Color(CREAM, 1.0), Color("#9ab8c0", 1.0), 220.0, -0.3, 2.4)
		glass_shards(b_front, wc, a, 0.75, 12, 19, 360.0, 3.6, BRASS, BRASS_D, 260.0, -0.3, 2.4)
		glass_shards(b_add, hit, a, 0.6, 16, 13, 380.0, 3.4, Color(TEAL_L, 0.9), Color(TEAL, 0.7), 160.0, -0.2, 2.0)
		sparks(b_add, hit, a, 0.5, 60, 15, 560.0, Color("#eafcff"), TEAL_L, -0.2, PI * 1.2, 120.0, 1.8)
		view["shake"] += hit_shake(a, 15.0, 85.0, 0.35)
		view["hero"]["lit"] = 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25))
		view["hero"]["lit_col"] = TEAL_L
	ally_hits(t, [[T.resume, 3]], 1.5)
	var ba := a + 0.06
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.15, 0.35)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(hit, ba, 14, 21, 70.0, 46.0, 26.0, 16.0, .4, 0.0, 10.0), ba, {"flow": ba * .3, "cool": .05, "erode": RBMHeroFx.ramp(ba, .1, .3), "fade": bf, "erode_noise": .4, "polar": 0.6, "detail": .5, "radial_heat": .5, "heat_center": w(hit), "heat_radius": 80.0 * RBMHeroFx.burst(ba, 10.0), "erode_radial": 60.0, "tone_cap": .98})
	# 戻る: 一瞬で元の位置へ（相手の前に残像）
	if t >= T.back and t < T.back + 0.3:
		ghost(4, _reach(), 0.4 * (1.0 - RBMHeroFx.ramp(t, T.back, T.back + 0.3)), TEAL, 0.6)
	b_add.commit(); b_line.commit(); b_front.commit()
