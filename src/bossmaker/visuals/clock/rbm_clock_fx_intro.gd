extends RBMClockFxBase
## 本番（2026-11-17 ユーザー「これでいいね」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/intro.gd でユーザーが採用した内容をそのまま移した。
## 振り子の給仕長・登場（2026-11-16）:
## 意味: 「時が止まった時には、もうそこにいる」。
## 戦場が少し暗くなり、時計の刻む音 → 上から鎖に吊られた大きな懐中時計が降りてきて、振り子のように揺れながら秒針が 9 → 10 → 11 と刻む
## → 12時に届いた瞬間、懐中時計にひびが走って砕ける（かけらが飛び散る）→ 飛び散る途中で、時が止まる:
##   かけらがぴたりと宙で止まり（止まったかけらは青白く縁取られて小さくきらめく）、色が懐中時計の所から画面の外へ抜けていき、巨大な秒針の影が横切る
##   （2026-11-16 ユーザー「時計が割れる時に時が止まっているアニメーションを」）
## → 止まった時の中、宙に止まったかけらの奥に給仕長が一礼して現れる（割れる前は体を出さない＝ユーザー「壊れる前に後ろにボスの足が出ちゃってる」）
## → 時が動き出す（色が戻る・かけらが散る）→ 身を起こして構え・題字。
## 本体は全体の1枚目（手を差し出す一礼の姿）を借り、最後に立ち姿へ。

const T := {"dim": 0.20, "drop": 0.45, "ticks": [1.20, 1.55, 1.90], "twelve": 2.25, "burst": 2.33, "stop": 2.45, "bow": 2.80, "resume": 3.40, "rise": 3.90, "end": 4.95}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#7a6030")
const CREAM := Color("#f0e8d0")
const TEAL := Color("#4ab8c0")
const TEAL_L := Color("#a8f0f0")
const BOW := 9

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_chain: RBMHeroFxBatch
var watch: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.resume

func stops() -> Array:
	return [[T.stop, 0.08]]

func extra_poses() -> Dictionary:
	return {BOW: ["pre_all", 1]}

func pose_keys() -> Array:
	return [[0.0, BOW], [T.rise, 0]]

func _build() -> void:
	b_back = batch(back, false)
	b_chain = batch(front, false)
	watch = dial_quad(front, {"seed": 3.0, "thick": 4.0})
	b_front = batch(front, false)
	b_add = batch(front)

## 懐中時計の揺れ（降りてくる間は大きく、12時へ近づくほど小さく）
func _swing(t: float) -> float:
	var amp := 0.35 * (1.0 - RBMHeroFx.ramp(t, T.drop, T.stop))
	return amp * sin((t - T.drop) * 3.2)

## 止まった時の中で、色が抜けていく広がり（懐中時計の所から外へ。0〜1）
func _drain(t: float) -> float:
	return RBMHeroFx.ramp(t, T.stop, T.stop + 0.3)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset(); b_chain.reset()
	var stopped := RBMHeroFx.env(t, T.stop, T.stop + 0.03, T.resume - 0.001, T.resume)
	var a := t - T.resume
	view["dim"] = 0.3 * RBMHeroFx.ramp(t, 0.0, T.dim + 0.3) * (1.0 - RBMHeroFx.ramp(a, 0.2, 1.0)) + 0.14 * stopped
	view["dim_col"] = Color(0.0, 0.02, 0.05)
	# 本体: 懐中時計が砕けて時が止まってから、止まった時の中で一礼して現れる（割れる前は出さない）
	body["hidden"] = t < T.bow
	if t >= T.bow and t < T.bow + 0.12:
		body["alpha"] = RBMHeroFx.ramp(t, T.bow, T.bow + 0.12)
	# 上から鎖に吊られた懐中時計が降りてくる（振り子のように揺れる）
	var pivot := HOME + Vector2(0, -260)
	var fall := RBMHeroFx.ramp(t, T.drop, T.drop + 0.55)
	var length := lerpf(60.0, 196.0, 1.0 - pow(1.0 - fall, 3.0))
	var ang := _swing(minf(t, T.twelve))
	var wc := pivot + Vector2(sin(ang), cos(ang)) * length
	var shat := RBMHeroFx.ramp(t, T.burst, T.burst + 0.06)
	var sec := -PI * 0.5
	var ticks: Array = T.ticks
	for tk in ticks:
		sec += PI / 6.0 * smoothstep(float(tk) - 0.03, float(tk), t)
	sec += PI / 6.0 * smoothstep(T.twelve - 0.03, T.twelve, t)
	if fall > 0.0 and shat < 1.0:
		for c in range(14):
			var p0 := pivot.lerp(wc, float(c) / 14.0)
			var p1 := pivot.lerp(wc, (float(c) + 0.6) / 14.0)
			b_chain.line(p0, p1, 1.8, Color(BRASS, 1.0), Color(BRASS_D, 1.0))
		show_dial(watch, wc, 30.0, {"squash": 0.95, "rot": -ang, "hour": 5.24, "minute": 0.0, "second": sec, "hot_mark": 0.0, "hot": RBMHeroFx.ramp(t, T.ticks[0], T.twelve),
			"glow": 0.2 + 0.4 * RBMHeroFx.ramp(t, T.twelve, T.burst), "crack": RBMHeroFx.ramp(t, T.twelve, T.burst), "crack_at": Vector2(0.0, 0.0), "shatter": shat})
	else:
		watch.visible = false
	# 刻むたびに小さく揺れる・12時でひびが走る
	for tk in ticks + [T.twelve]:
		if t >= float(tk) and t < float(tk) + 0.08:
			view["shake"] += Vector2(1.0 if int(t * 60.0) % 2 == 0 else -1.0, 0.0) * (2.0 if float(tk) == T.twelve else 1.0)
	# 砕けたかけら: 飛び散る途中で時が止まり、宙でぴたりと止まる → 時が動くと散る
	var fly := T.stop - T.burst
	var age := 0.0
	if t >= T.burst:
		age = (t - T.burst) if t < T.stop else (fly if t < T.resume else fly + (t - T.resume))
		glass_shards(b_front, wc, age, 1.3, 40, 11, 380.0, 4.8, Color(CREAM, 0.95), Color("#9ab8c0", 0.95), 240.0)
		glass_shards(b_front, wc, age, 1.2, 16, 13, 320.0, 3.8, BRASS, BRASS_D, 280.0)
		glass_shards(b_add, wc, age, 1.0, 14, 15, 300.0, 3.2, Color(TEAL_L, 0.9), Color(TEAL, 0.6), 200.0)
		if t < T.stop:
			sparks(b_add, wc, t - T.burst, 0.3, 30, 17, 300.0, Color("#eafcff"), BRASS, 0.0, TAU, 60.0, 1.6)
			view["shake"] += hit_shake(t - T.burst, 4.0, 90.0, 0.12)
	# 止まっている間: 宙に止まったかけらが青白く縁取られ、小さくきらめく（止まっているのが分かる）
	if stopped > 0.0 and t >= T.burst:
		for k in range(16):
			var r1 := RBMHeroFx.r(k, 11)
			var r3 := RBMHeroFx.r(k, 14)
			var th := (r1 - 0.5) * TAU
			var dir := Vector2.from_angle(th)
			var sp_ := 380.0 * (0.35 + 0.65 * r3)
			var kk := 3.4
			var p := wc + dir * (6.0 + 20.0 * RBMHeroFx.r(k, 18)) + dir * sp_ * (1.0 - exp(-kk * fly)) / kk + Vector2(0, 240.0 * fly * fly)
			var tw := 0.5 + 0.5 * sin(t * 9.0 + float(k) * 1.7)
			b_add.dot_px(p, 2.0, Color(TEAL_L, 0.55 * stopped * tw))
	# 時が止まる: 色が懐中時計の所から抜けていく（全体の色抜けを少し遅れて重ね、広がるように見せる）・巨大な秒針の影
	var dr := _drain(t)
	time_stop_post(stopped * dr, {"vig": 0.45 * stopped * (1.0 - 0.5 * dr), "vig_col": Vector3(.0, .05, .07), "vig_r": .3 - 0.12 * (1.0 - dr)})
	sweep_hand(b_add, RBMHeroFx.ramp(t, T.stop - 0.02, T.stop + 0.26), Color(TEAL_L, 0.26))
	# 時が動き出す: 色が一気に戻る・閃光
	if a >= 0.0:
		set_post({"flash": 0.22 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.14)), "flash_col": Vector3(.85, .98, 1.0)})
		view["shake"] += hit_shake(a, 6.0, 80.0, 0.3)
		view["hero"]["lit"] = 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.5))
		view["hero"]["lit_col"] = TEAL_L
	# 一礼している間の足元の淡い光（止まった時の中では止まっている）
	if t >= T.bow and t < T.rise:
		embers(b_add, Rect2(HOME.x - 40, HOME.y - 90, 80, 90), minf(t, T.resume), 14, 21, 30.0, Color(TEAL_L, 0.8), RBMHeroFx.env(t, T.bow, T.bow + 0.2, T.rise - 0.2, T.rise), 1.6, 6.0)
	b_back.commit(); b_add.commit(); b_front.commit(); b_chain.commit()
