extends RBMClockFxBase
## 本番（2026-11-16 ユーザー「これが終わったら実装していいよ」）: 試作 prototypes/four_bosses_2026-11-11/scripts/clock/post_all.gd でユーザーが採用した内容をそのまま移した。
## 終刻の給仕長・覚醒後全体「終刻の制止」（2026-11-16 v3。ユーザー「迫力がない・技の一つ一つに意味があるように」。覚醒後全体は最大の見せ場）:
## 意味: 「お前たちの時間（寿命）は私が止め、壊す」。
## 世界が真夜中に沈み、オーラが燃え上がる → 両腕を交差して溜める: 四人の頭上に一人ずつの懐中時計が鎖で吊られて現れる（その人の時間。針が速く減っていく）。
##   空には巨大な大時計がせり上がり、針が12時（終刻）へ近づく
## → 片腕を高く掲げ、手のひらで制止する: 空の大時計の針が12時で重なった瞬間、時が止まる（巨大な秒針の影・色が抜ける）
## → 止まった時の中で、四人の懐中時計を一つずつ砕く（音もなく割れ、かけらは宙で止まったまま）
## → 時が動き出す: 止まっていたかけらが持ち主の胸へ一斉に飛び込む（自分の時間に貫かれる）→ 空の大時計も砕け、四人の所で光が弾ける（最後の一撃）
## → 真鍮の歯車とガラスが降る余韻。

const T := {"dark": 0.20, "charge": 0.45, "dials": 0.60, "release": 1.70, "stop": 1.74, "breaks": [2.05, 2.30, 2.55, 2.80], "resume": 3.20, "burst": 3.36, "settle": 3.90, "end": 5.80}
const BRASS := Color("#d8b468")
const BRASS_D := Color("#5a4420")
const CREAM := Color("#f0e8d0")
const CRIMSON := Color("#e03848")
const CYAN := Color("#7ee0ec")
const TEAL := Color("#4ab8c0")
const INK := Color("#141418")
const DARK_BRASS := {"brass_l": Vector3(.86, .72, .45), "brass": Vector3(.55, .40, .20), "brass_d": Vector3(.22, .14, .07), "face_l": Vector3(.86, .84, .80), "face_d": Vector3(.5, .48, .46),
	"steel": Vector3(.2, .04, .07), "sec_col": Vector3(.95, .2, .25)}
const FINAL_A := ["#145a78", "#1e78a0", "#2aa0c0", "#5ac8dc", "#9ae8f0", "#d8fafc", "#f0feff", "#ffffff"]
const FINAL_B := ["#6a0c18", "#a01830", "#d03040", "#f07080", "#ffb8c0", "#ffe0e4", "#fff4f6", "#ffffff"]
## 懐中時計のかけらの数（一人分）
const PIECES := 18
const DIAL_R := 22.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var sky: ColorRect
var dials: Array = []
var blast: ColorRect
var final_share := 0.4

func duration() -> float:
	return T.end

func impact() -> float:
	return T.burst

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([T.resume + 0.12, i])
	return out

func stops() -> Array:
	return [[T.burst, 0.16]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.release, 3], [T.settle, 4]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25 + Vector2(0, -20)

## その人の懐中時計の位置（頭の上）
func _dial_pos(i: int) -> Vector2:
	return target_chest(i) + Vector2(4, -48 - (i % 2) * 6)

func _build() -> void:
	b_back = batch(back, false)
	sky = dial_quad(back, DARK_BRASS.merged({"seed": 21.0, "thick": 10.0}))
	for i in range(4):
		dials.append(dial_quad(front, DARK_BRASS.merged({"seed": 31.0 + i, "thick": 3.0})))
	blast = blast_quad(front, FINAL_A, FINAL_B, {"amp": 38., "k": .048, "seed": 5.3, "glow": .7, "glow_col": Vector3(.6, .9, 1.), "glow_r": 52.})
	b_front = batch(front, false)
	b_add = batch(front)

## かけらの止まった位置（割れて 0.07秒だけ広がった所）
func _piece_frozen(o: Vector2, k: int, seed_: int) -> Vector2:
	var th := RBMHeroFx.r(k, seed_) * TAU
	var sp_ := 160.0 * (0.4 + 0.6 * RBMHeroFx.r(k, seed_ + 3))
	return o + Vector2.from_angle(th) * (6.0 + 14.0 * RBMHeroFx.r(k, seed_ + 7) + sp_ * 0.07)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var center := _center()
	var ar := t - T.resume
	var ab := t - T.burst
	var stopped := RBMHeroFx.env(t, T.stop, T.stop + 0.03, T.resume - 0.001, T.resume)
	var rt := t if t < T.stop else (T.stop if t < T.resume else t - (T.resume - T.stop))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.dark + 0.3, 0.6], [T.release, 0.72], [T.resume, 0.78], [T.burst + 0.3, 0.45], [T.end, 0.15]])
	view["dim_col"] = Color(0.0, 0.02, 0.04)
	time_stop_post(stopped, {"vig": 0.45 * stopped + 0.2, "vig_col": Vector3(.0, .03, .06), "vig_r": .26})
	sweep_hand(b_add, RBMHeroFx.ramp(t, T.stop - 0.02, T.stop + 0.26), Color(CYAN, 0.26))
	view["hero"]["sun_aura"] = 1.0 + 1.4 * RBMHeroFx.env(t, T.dark, T.charge + 0.3, T.burst, T.burst + 0.6)
	view["hero"]["lit"] = 0.4 * RBMHeroFx.env(t, T.charge, T.release, T.resume, T.resume + 0.3)
	view["hero"]["lit_col"] = CYAN
	# 空の大時計: せり上がり、針が12時（終刻）へ近づく → 12時で重なって時が止まる → 最後に砕ける
	var sky_on := RBMHeroFx.ramp(t, T.dark, T.dials + 0.6)
	var sky_c := Vector2(250, 40) + Vector2(0, 60.0 * (1.0 - sky_on))
	var k12 := RBMHeroFx.ramp(t, T.dials, T.stop)
	var s_shat := RBMHeroFx.ramp(ab, 0.0, 0.6)
	if sky_on > 0.0 and s_shat < 1.0:
		show_dial(sky, sky_c, 150.0, DARK_BRASS.merged({"squash": 0.8, "hour": lerp_angle(4.4, 0.0, k12 * k12), "minute": lerp_angle(2.6, 0.0, k12) - TAU * (1.0 - k12) * 2.0, "second": -1.0 if t >= T.stop else rt * 10.0,
			"hot_mark": 0.0, "hot_col": Vector3(1., .3, .38), "hot": k12 * k12, "glow": 0.2 + 0.5 * stopped + 0.4 * k12, "glow_col": Vector3(.5, .92, 1.),
			"crack": RBMHeroFx.ramp(t, T.breaks[0], T.burst), "shatter": s_shat, "fade": 0.8 * sky_on, "dark": 0.55}))
	else:
		sky.visible = false
	# 四人の頭上の懐中時計（その人の時間）: 鎖で吊られ、針が速く減る → 止まる → 一つずつ砕ける → かけらが持ち主へ飛び込む
	var breaks: Array = T.breaks
	for i in range(4):
		var pos := _dial_pos(i)
		var app := RBMHeroFx.ramp(t, T.dials + i * 0.1, T.dials + i * 0.1 + 0.25) * float(present[i])
		var bt := float(breaks[i])
		var shat := clampf((t - bt) / 0.08, 0.0, 1.0)
		if app > 0.0 and shat < 1.0:
			show_dial(dials[i], pos + Vector2(0, -6.0 * (1.0 - app)), DIAL_R, DARK_BRASS.merged({"squash": 0.9, "rot": -0.08 + 0.05 * i, "hour": -rt * 1.5 + i, "minute": -rt * 12.0 + i * 1.7,
				"second": -1.0 if t >= T.stop else -rt * 30.0, "glow": 0.3 + 0.4 * stopped, "glow_col": Vector3(.5, .92, 1.), "crack": clampf((t - (bt - 0.12)) / 0.12, 0.0, 1.0), "shatter": shat, "fade": app}))
			# 鎖（時計の下から頭へ）
			var top := target_chest(i) + Vector2(0, -22)
			var from := pos + Vector2(0, DIAL_R * 0.9)
			for c in range(5):
				var p0 := from.lerp(top, float(c) / 5.0)
				var p1 := from.lerp(top, (float(c) + 0.6) / 5.0)
				b_front.line(p0, p1, 1.6, Color(BRASS, app), Color(BRASS_D, app))
		else:
			dials[i].visible = false
		if not present[i] or t < bt:
			continue
		# かけら: 割れて少しだけ広がり、宙で止まる（止まった時の中）→ 時が動くと持ち主の胸へ飛び込む
		var chest := target_chest(i)
		var into := RBMHeroFx.ramp(ar, 0.0, 0.12)
		var gone := RBMHeroFx.ramp(ar, 0.1, 0.16)
		for k in range(PIECES):
			var fp := _piece_frozen(pos, k, 81 + i * 9)
			var spread := RBMHeroFx.ramp(t, bt, bt + 0.05)
			var p := pos.lerp(fp, spread).lerp(chest, into * into)
			var sz := (2.4 + 2.6 * RBMHeroFx.r(k, 84 + i * 9)) * (1.0 - gone)
			if sz > 0.3:
				var glass := k % 3 != 0
				b_front.shard(p, sz, RBMHeroFx.r(k, 85) * TAU + (t - bt) * 0.0, k * 3 + 1 + (k % 2), Color(CREAM, 0.95) if glass else BRASS, Color("#8a9aa0", 0.95) if glass else BRASS_D)
				if into > 0.0 and into < 1.0:
					b_add.line(p, p - (chest - fp).normalized() * 10.0 * into, 2.0, Color(CYAN, 0.6), Color(CYAN, 0.0))
		# 割れた瞬間だけ小さく揺れる（音のない割れ方）
		if t < T.resume:
			view["shake"] += hit_shake(t - bt, 3.0, 90.0, 0.12)
		# 飛び込んだ瞬間: 胸で光が弾ける
		var hi := ar - 0.12
		if hi >= 0.0:
			sparks(b_add, chest, hi, 0.5, 40, 93 + i, 460.0, Color("#e6fcff"), CYAN, 0.0, TAU, 120.0, 1.8)
			sparks(b_add, chest, hi, 0.45, 22, 97 + i, 380.0, Color("#ffd0d4"), CRIMSON, 0.0, TAU, 120.0, 1.6)
	var evs := []
	for i in range(4):
		evs.append([T.resume + 0.12, i])
	ally_hits(t, evs, 1.0)
	if ar >= 0.0 and ab < 0.0:
		set_post({"flash": 0.14 * (1.0 - RBMHeroFx.ramp(ar, 0.0, 0.1)), "flash_col": Vector3(.85, .97, 1.0)})
	view["shake"] += hit_shake(ar - 0.12, 8.0, 90.0, 0.2)
	# 最後の一撃: 空の大時計が砕け、四人の所で光が弾ける
	if ab >= 0.0:
		glass_shards(b_front, sky_c, ab, 1.8, 54, 101, 560.0, 9.0, Color(CREAM, 0.9), Color("#7a8a90", 0.9), 300.0, PI * 0.5, PI * 1.2)
		glass_shards(b_front, sky_c, ab, 1.7, 28, 103, 500.0, 7.0, BRASS, BRASS_D, 320.0, PI * 0.5, PI * 1.2)
		view["shake"] += hit_shake(ab, 22.0, 60.0, 0.85)
		ally_light(RBMHeroFx.env(ab, 0.0, 0.05, 0.4, 1.0), CYAN, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), 1.4 * RBMHeroFx.env(ab, 0.0, 0.05, 0.18, 0.65))
		set_post({"flash": 0.34 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.2)), "flash_col": Vector3(.85, .97, 1.0), "chroma": 0.005 * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3))})
	var ba := ab + 0.08
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.35, 0.8)
	blast.visible = ab >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(center, ba, 36, 29, 300.0, 140.0, 76.0, 70.0, .6, 0.15, 7.0), ba, {"flow": ba * .25, "cool": .05 + RBMHeroFx.ramp(ba, .2, .9) * .2, "erode": RBMHeroFx.ramp(ba, .25, .8), "fade": bf, "erode_noise": .4,
			"polar": 0.6, "detail": .5, "radial_heat": .45, "heat_center": w(center), "heat_radius": 300.0 * RBMHeroFx.burst(ba, 7.0), "erode_radial": 180.0, "tone_cap": .98})
	# 余韻: 真鍮の歯車とガラスが降る・青緑の粒
	embers(b_add, Rect2(-20, 0, 680, 300), t, 50, 107, -50.0, Color(CREAM, 0.7), RBMHeroFx.env(ab, 0.5, 1.0, 1.8, 2.4), 2.0, 14.0)
	embers(b_add, Rect2(HOME.x - 80, HOME.y - 150, 160, 150), t, 24, 109, 40.0, Color(CYAN, 0.8), RBMHeroFx.env(t, T.dark, T.charge, T.burst, T.burst + 0.5), 2.0, 8.0)
	b_back.commit(); b_add.commit(); b_front.commit()
