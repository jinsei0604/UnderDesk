extends RBMClockFxBase
## 本番（2026-11-16 ユーザー「これが終わったら実装していいよ」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/post_single.gd でユーザーが採用した内容をそのまま移した。
## 終刻の給仕長・覚醒後単体「狂針の宣告」（2026-11-16 v3。ユーザー「迫力がない・技の一つ一つに意味があるように」）:
## 意味: 「宣告（お前の終わりの時刻）→ 執行」。
## 顔に手を添える → 相手の前に黒ずんだ文字盤が浮かび、深紅の秒針が狂ったように回る
## → 宣告: 秒針がぴたりと12時で止まり、12時の目盛りが深紅に光る（一拍の静けさ）→ 時が止まる（巨大な秒針の影・色が抜ける）
## → 止まった時の中で、相手の周りの六か所へ次々と移り、そのたびに深紅の針を一本ずつ打ち込んでいく（止まった時の中の連撃）
## → 時が動く: 止まっていた連撃が一気に届く（六本の針が次々と貫き、当たりの数字が六回たたみかける。2026-11-16 ユーザー「時間が止まっていた間に連撃を繰り出したように」）→ 執行: 頭上から巨大な振り子のおもりが振り下ろされ、文字盤ごと相手を打ち砕く（最後の一撃）→ 戻る。冷酷で洗練。

const T := {"windup": 0.30, "dial": 0.42, "sentence": 0.80, "stop": 0.94, "places": [1.00, 1.07, 1.14, 1.21, 1.28, 1.35], "resume": 1.52, "pendulum": 1.84, "follow": 1.88, "back": 2.22, "end": 2.70}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#5a4420")
const CREAM := Color("#f0e8d0")
const CRIMSON := Color("#e03848")
const CRIMSON_D := Color("#6a0c18")
const TEAL := Color("#4ab8c0")
const CYAN := Color("#7ee0ec")
const INK := Color("#141418")
const RED_STEEL := [Color("#3a0c16"), Color("#ff6a74"), Color("#08040a")]
## 黒ずんだ真鍮（覚醒後）
const DARK_BRASS := {"brass_l": Vector3(.86, .72, .45), "brass": Vector3(.55, .40, .20), "brass_d": Vector3(.22, .14, .07), "face_l": Vector3(.86, .84, .80), "face_d": Vector3(.5, .48, .46),
	"steel": Vector3(.2, .04, .07), "sec_col": Vector3(.95, .2, .25)}
## 止まった時の中で移る3か所（相手の胸から）
const SPOTS := [Vector2(-38, -40), Vector2(42, -30), Vector2(-4, 38), Vector2(40, 22), Vector2(-46, 6), Vector2(8, -48)]
## 時が動いた後、止めていた連撃が届く間隔（秒）
const FLURRY := 0.05

var b_add: RBMHeroFxBatch
var b_add_back: RBMHeroFxBatch
var b_line: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var b_rod_line: RBMHeroFxBatch
var b_rod: RBMHeroFxBatch
var watch: ColorRect
var bob: ColorRect
var blast: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.pendulum

func hits() -> Array:
	var out := []
	for k in range(SPOTS.size()):
		out.append([T.resume + k * FLURRY, 3])
	return out

func stops() -> Array:
	return [[T.resume, 0.06], [T.pendulum, 0.14]]

func _reach() -> Vector2:
	return Vector2(-108, 26) + focus_delta

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.places[0], 3], [T.follow, 4], [T.back, 1]]

func move_keys() -> Array:
	var r := _reach()
	var p: Array = T.places
	return [[0.0, Vector2.ZERO, "snap"], [p[0], Vector2.ZERO, "snap"], [float(p[0]) + 0.001, r, "snap"], [T.back, r, "snap"], [T.back + 0.001, Vector2.ZERO, "snap"]]

func _build() -> void:
	b_rod_line = batch(back, false)
	b_rod = batch(back, false)
	b_add_back = batch(back)
	blast = blast_quad(back, ["#6a0c18", "#a01830", "#d03040", "#f07080", "#ffb8c0", "#ffe0e4", "#fff4f6", "#ffffff"], ["#145a78", "#1e78a0", "#2aa0c0", "#5ac8dc", "#9ae8f0", "#d8fafc", "#f0feff", "#ffffff"], {"amp": 22., "k": .065, "seed": 4.4, "glow": .5, "glow_col": Vector3(1., .4, .5), "glow_r": 30.})
	watch = dial_quad(front, DARK_BRASS.merged({"seed": 6.0, "thick": 3.0}))
	bob = dial_quad(front, DARK_BRASS.merged({"seed": 8.0, "thick": 6.0}))
	b_line = batch(front, false)
	b_front = batch(front, false)
	b_add = batch(front)

func _step(t: float) -> void:
	b_add.reset(); b_add_back.reset(); b_line.reset(); b_front.reset(); b_rod_line.reset(); b_rod.reset()
	var hit := target_chest(3)
	var wc := hit + Vector2(18, -6)
	var stopped := RBMHeroFx.env(t, T.stop, T.stop + 0.03, T.resume - 0.001, T.resume)
	var ar := t - T.resume
	var ap := t - T.pendulum
	view["dim"] = 0.22 * RBMHeroFx.env(t, T.windup, T.dial, T.follow, T.back) + 0.14 * stopped
	view["dim_col"] = Color(0.03, 0.0, 0.03)
	# 文字盤: 深紅の秒針が狂ったように回る → 宣告で12時にぴたりと止まり、12時の目盛りが深紅に光る
	var on := RBMHeroFx.ramp(t, T.dial, T.dial + 0.12)
	var shat := RBMHeroFx.ramp(ap, 0.0, 0.3)
	var mad := t * t * 30.0
	var sec := mad if t < T.sentence else 0.0
	var decl := RBMHeroFx.ramp(t, T.sentence, T.sentence + 0.06)
	if t >= T.sentence and t < T.sentence + 0.1:
		view["shake"] += Vector2(1.5 if int(t * 60.0) % 2 == 0 else -1.5, 0.0)
	if on > 0.0 and shat < 1.0:
		show_dial(watch, wc, 22.0, DARK_BRASS.merged({"squash": 0.9, "rot": 0.1, "hour": 0.0, "minute": 0.0, "second": sec,
			"hot_mark": 0.0, "hot_col": Vector3(1., .25, .3), "hot": decl, "glow": 0.25 + 0.55 * decl, "glow_col": Vector3(1., .3, .4),
			"crack": RBMHeroFx.ramp(ar, 0.0, 0.1) * 0.6 + RBMHeroFx.ramp(ap, 0.0, 0.04), "shatter": shat, "fade": on}))
	else:
		watch.visible = false
	# 時が止まる
	time_stop_post(stopped)
	sweep_hand(b_add, RBMHeroFx.ramp(t, T.stop - 0.02, T.stop + 0.2), Color(CYAN, 0.24))
	# 止まった時の中で六か所へ移り、針を一本ずつ打ち込む（打ち込んだ針は宙で止まる）→ 時が動くと次々と貫く
	var places: Array = T.places
	for i in range(SPOTS.size()):
		var pt := float(places[i])
		var sp_: Vector2 = SPOTS[i]
		var placed := RBMHeroFx.ramp(t, pt, pt + 0.04) * (1.0 - RBMHeroFx.ramp(ar - i * FLURRY, 0.1, 0.24))
		if t >= pt and t < T.resume:
			ghost(3, _reach() + sp_ * 0.7 + Vector2(34, 0), 0.34 * (1.0 - RBMHeroFx.ramp(t, pt, pt + 0.3)), CRIMSON, 0.6)
		if t >= pt and t < pt + 0.06:
			view["shake"] += Vector2(1.0, 0.0)
		if placed > 0.0:
			var dir := (-sp_).normalized()
			var strike := RBMHeroFx.ramp(ar - i * FLURRY, 0.0, 0.03)
			var tip := hit + sp_ * (0.42 - 0.42 * strike) - dir * 4.0 * (1.0 - strike)
			breguet_hand(b_line, b_front, tip - dir * 38.0, tip, 2.2, RED_STEEL, placed)
			if stopped > 0.5:
				b_add.line(tip - dir * 38.0, tip, 4.0, Color(CRIMSON, 0.0), Color(CRIMSON, 0.3))
	if ar >= 0.0:
		if ap < 0.0:
			set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(ar, 0.0, 0.1)), "flash_col": Vector3(1.0, 0.85, 0.88)})
	# 連撃が次々と届く: 一本ごとに火花とかけら・小さな揺れ
	var evs := []
	for k in range(SPOTS.size()):
		var hk := ar - k * FLURRY
		evs.append([T.resume + k * FLURRY, 3])
		if hk >= 0.0 and ap < 0.3:
			var from: Vector2 = SPOTS[k]
			glass_shards(b_add, hit, hk, 0.32, 6, 51 + k * 5, 240.0, 2.4, Color(CRIMSON, 0.9), Color(CRIMSON_D, 0.7), 110.0, (-from).angle(), 1.6)
			sparks(b_add, hit, hk, 0.26, 16, 53 + k * 5, 300.0, Color("#ffd0d4"), CRIMSON, (-from).angle(), 1.4, 70.0, 1.4)
			view["shake"] += hit_shake(hk, 5.0, 95.0, 0.12)
	ally_hits(t, evs, 0.7)
	# 執行: 頭上から巨大な振り子のおもり（命中の瞬間に相手に届き、振り抜ける）
	var pv := hit + Vector2(70, -340)
	var plen := pv.distance_to(hit)
	var sw := RBMHeroFx.ramp(t, T.resume + 0.06, T.pendulum)
	var after := RBMHeroFx.ramp(ap, 0.0, 0.5)
	var hit_ang := atan2(hit.x - pv.x, hit.y - pv.y)
	var ang := lerpf(-1.05, hit_ang, sw * sw) if ap < 0.0 else hit_ang + 0.6 * (1.0 - pow(1.0 - after, 2.0))
	var p_on := RBMHeroFx.ramp(t, T.resume + 0.04, T.resume + 0.1) * (1.0 - RBMHeroFx.ramp(t, T.back - 0.15, T.back))
	if p_on > 0.0:
		pendulum(b_rod_line, b_rod, bob, pv, plen, ang, 34.0, p_on, DARK_BRASS.merged({"glow": 0.4 + 0.5 * sw, "glow_col": Vector3(1., .3, .4), "dark": 0.1}))
		# 振り下ろしの軌跡（おもりの通った幅の帯。深紅）
		if sw > 0.05 and ap < 0.15:
			for j in range(1, 6):
				var aj := ang - 0.045 * j
				var cj := pv + Vector2(sin(aj), cos(aj)) * plen
				var n := Vector2(cos(aj), -sin(aj))
				b_add_back.line(cj - n * 30.0, cj + n * 30.0, 7.0, Color(CRIMSON, 0.14 * (6 - j) * sw), Color(CRIMSON, 0.14 * (6 - j) * sw))
	else:
		bob.visible = false
	# 打ち砕く（最後の一撃）
	if ap >= 0.0:
		set_post({"flash": 0.3 * (1.0 - RBMHeroFx.ramp(ap, 0.0, 0.14)), "flash_col": Vector3(1.0, 0.86, 0.9), "chroma": 0.004 * (1.0 - RBMHeroFx.ramp(ap, 0.0, 0.25))})
		glass_shards(b_front, wc, ap, 1.0, 34, 61, 560.0, 5.4, Color(CREAM, 1.0), Color("#8a9aa0", 1.0), 240.0, 0.5, 2.8)
		glass_shards(b_front, wc, ap, 0.9, 18, 63, 480.0, 4.4, BRASS, BRASS_D, 280.0, 0.5, 2.8)
		sparks(b_add, wc, ap, 0.7, 90, 65, 760.0, Color("#ffd0d4"), CRIMSON, 0.5, PI * 1.6, 140.0, 1.9)
		sparks(b_add, wc, ap, 0.6, 50, 67, 620.0, Color("#e6fcff"), CYAN, 0.5, PI * 1.4, 120.0, 1.7)
		view["shake"] += hit_shake(ap, 18.0, 75.0, 0.45)
	ally_hits(t, [[T.pendulum, 3]], 1.6)
	var ba := ap + 0.06
	var bf := 1.0 - RBMHeroFx.ramp(ap, 0.22, 0.5)
	blast.visible = ap >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(wc, ba, 20, 71, 130.0, 80.0, 40.0, 30.0, .5, 0.35, 9.0), ba, {"flow": ba * .3, "cool": .05, "erode": RBMHeroFx.ramp(ba, .12, .45), "fade": bf, "erode_noise": .4, "polar": 0.6, "detail": .5, "radial_heat": .5, "heat_center": w(wc), "heat_radius": 140.0 * RBMHeroFx.burst(ba, 9.0), "erode_radial": 100.0, "tone_cap": .98})
	# 戻る（相手の前に残像）
	if t >= T.back and t < T.back + 0.3:
		ghost(4, _reach(), 0.4 * (1.0 - RBMHeroFx.ramp(t, T.back, T.back + 0.3)), CRIMSON, 0.6)
	b_add.commit(); b_add_back.commit(); b_line.commit(); b_front.commit(); b_rod_line.commit(); b_rod.commit()
