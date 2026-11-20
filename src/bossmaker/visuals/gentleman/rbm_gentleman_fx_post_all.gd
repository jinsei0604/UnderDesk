extends RBMGentlemanFxBase
## 異形紳士・覚醒後の全体「深紅の終幕」（2026-11-20 作り直し。前の版は影12人の射撃）。
## 2026-11-20 ユーザー「覚醒後の全体攻撃はそもそも作り直したい。今は案が思いつかないから、聖獣やヒーローくらいのクオリティで」。
## 意味（劇場の終幕）: 紳士が帽子に手をやると、画面の両端に深紅の幕が下りて世界が暗くなる → 両腕を広げると、四人を囲む闇に
## 赤い目が開き、空間の裂け目が6つ開き、四人に舞台の光が落ちる → 二丁の銃を広げて構え、左右交互に撃つ。弾は銃口の先の裂け目に
## 吸い込まれ、四人を囲む裂け目から飛び出して当たる → 二丁を前にそろえて溜める（裂け目が脈打ち、赤い糸が四人へ伸びる）→ 一斉に
## 撃つと6つの裂け目すべてから光が四人の中心へ収束し、深紅の墨の大爆発・衝撃の輪・石畳の割れ目・薔薇の花びらが吹き上がる
## → 花びらが降る中、紳士が深くお辞儀をし（カーテンコール）、幕が上がって世界が戻る。
## 弾の向き: 紳士の銃は絵のとおり水平（左の銃は左、右の銃は右）に撃ち、銃口のすぐ先の裂け目に入る。四人に当たる弾は
## 裂け目（銃ではない）から出るので、どの向きからでもよい。

const T := {"lift": 0.25, "reveal": 0.85, "raise": 1.5, "shots": 1.82, "step": 0.12, "count": 10, "cross": 3.15, "fire": 3.6, "impact": 3.72,
	"bow": 4.45, "bow_deep": 4.7, "rise": 5.4, "stand": 5.65, "curtain_up": 4.9, "end": 6.1}
## 四人を囲む裂け目（四人の中心からの位置）
const RIFTS := [Vector2(-112, -28), Vector2(-62, -78), Vector2(8, -88), Vector2(84, -58), Vector2(104, 12), Vector2(-104, 38)]
## 闇の中の目（画面の位置。四人のまわりの暗い所）
const EYES := [Vector2(28, 150), Vector2(64, 128), Vector2(18, 215), Vector2(52, 300), Vector2(108, 118), Vector2(286, 150), Vector2(300, 300), Vector2(150, 318), Vector2(250, 120), Vector2(30, 262)]

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var curtains: Array = []
var valance: RBMHeroFxRibbon
var spot: ColorRect
var cracks: ColorRect
var blast: ColorRect
var rings: Array = []
var threads: Array = []
var final_share := 0.45

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func _shot_time(i: int) -> float:
	return T.shots + T.step * float(i)

func _shot_target(i: int) -> int:
	var live: Array = []
	for k in range(mini(targets.size(), 4)):
		if present[k]:
			live.append(k)
	return int(live[i % live.size()]) if not live.is_empty() else 0

func hits() -> Array:
	var out := []
	for i in range(T.count):
		out.append([_shot_time(i) + 0.09, _shot_target(i)])
	return out

func pose_keys() -> Array:
	var keys := [[0.0, "hat_reach_00"], [T.lift, "hat_reach_15"], [T.reveal, "legacy_reveal"], [T.raise, "dual_open_raise_07"], [T.raise + 0.12, "dual_open_raise_15"]]
	for i in range(T.count):
		var st := _shot_time(i)
		# 左の銃（near）と右の銃（far）を交互に。撃った瞬間だけ反動の絵
		keys.append([st, "dual_open_fire_09" if i % 2 == 0 else "dual_open_fire_03"])
		keys.append([st + 0.06, "dual_open_fire_15"])
	keys.append([T.cross - 0.12, "dual_forward_raise_08"])
	keys.append([T.cross, "dual_forward_raise_15"])
	keys.append([T.fire, "dual_forward_fire_03"])
	keys.append([T.fire + 0.1, "dual_forward_fire_15"])
	keys.append([T.bow - 0.2, "hat_reach_15"])
	keys.append([T.bow, "bow_down_08"])
	keys.append([T.bow_deep, "bow_down_15"])
	keys.append([T.rise, "bow_up_08"])
	keys.append([T.stand, "hat_reach_00"])
	return keys

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	spot = quad(back, Rect2(0, -100, 160, 400), "pillar", {"pal": RBMHeroFx.pal(["#1a1014", "#3a2a2a", "#7a6058", "#c8b4a0", "#f4e8d8", "#ffffff"]), "seed": 4.2, "glow_col": Vector3(1., .85, .75), "glow": .4})
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120308", "#7a1026", "#ff5a6a", "#fff0f2"]), "seed": 5.1, "squash": .34, "line_w": .05, "glow_col": Vector3(1., .2, .3), "glow": .6})
	blast = blast_quad(mid, CRIMSON_INK, INK_SMOKE, {"amp": 30., "k": .055, "seed": 6.6, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 48.})
	b_mid = batch(mid, false)
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i != 1 else RBMHeroFx.A4_DARK, {"squash": .36, "breakup": .5, "seed": 2.0 + i * 1.7, "glow": .5, "glow_col": Vector3(.95, .15, .25)}))
	for i in range(6):
		threads.append(ribbon(front, ["#3a0a1c", "#7a1026", "#c22a44", "#ff5a6a", "#ff8a96", "#fff0f2"], {"body": .5, "taper": .6, "skew": .5, "rough": .3, "streak": .5, "gain": 1.15, "glow": .5, "glow_col": Vector3(1., .2, .3), "seed": 1.0 + i}))
	for side in range(2):
		for i in range(5):
			curtains.append(ribbon(front, VELVET, {"body": .95, "taper": .1, "skew": .3, "rough": .2, "rough_freq": 7., "streak": .18, "gain": .95, "glow": 0.0, "seed": 3.0 + side * 5 + i}))
	valance = ribbon(front, VELVET, {"body": .95, "taper": .1, "skew": .2, "rough": .2, "rough_freq": 7., "streak": .18, "gain": .95, "glow": 0.0, "seed": 9.5})
	b_add = batch(front)
	b_front = batch(front, false)

func _rift_pos(i: int) -> Vector2:
	return party_center() + Vector2(0, -22) + RIFTS[i]

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var pc := party_center()
	var a := t - T.impact
	# 世界が暗くなる（深紅の黒）
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.reveal, 0.5], [T.raise, 0.58], [T.fire, 0.7], [T.impact + 0.05, 0.45], [T.curtain_up, 0.5], [T.end - 0.3, 0.1], [T.end, 0.0]])
	view["dim_col"] = Color(0.05, 0.0, 0.02)
	set_post({"vig": 0.2 + 0.4 * RBMHeroFx.env(t, T.lift, T.reveal, T.curtain_up, T.end), "vig_col": Vector3(.18, .0, .03), "vig_r": .3})
	_curtains(t)
	# 闇に赤い目が開く（両腕を広げた時）→ 終幕で閉じる
	for i in range(EYES.size()):
		var open := RBMHeroFx.env(t, T.reveal + 0.05 + 0.06 * i, T.reveal + 0.2 + 0.06 * i, T.impact - 0.05, T.impact + 0.1)
		eyes(b_add, EYES[i], open * (0.55 + 0.45 * absf(sin(t * 3.0 + i))), 1.0 + 0.3 * (i % 3))
	# 舞台の光が四人に落ちる
	var sp_on := RBMHeroFx.env(t, T.reveal + 0.1, T.reveal + 0.5, T.impact - 0.1, T.impact + 0.05)
	spot.visible = sp_on > 0.0
	if spot.visible:
		spot.position = Vector2(pc.x - 80, -100)
		spot.size = Vector2(160, pc.y + 112)
		sp(spot, {"width": 0.5, "flow": t * 0.4, "fade": 0.3 * sp_on, "flare": 0.2})
		RBMHeroRooftop.glow(b_back_add, pc + Vector2(0, 6), 70.0, Color(1.0, 0.9, 0.8, 0.08 * sp_on))
	# 裂け目が開く（四人を囲む6つ）。溜めで脈打つ
	var pulse := RBMHeroFx.ramp(t, T.cross, T.fire)
	for i in range(6):
		var open := RBMHeroFx.env(t, T.reveal + 0.15 + 0.08 * i, T.reveal + 0.4 + 0.08 * i, T.impact + 0.05, T.impact + 0.3)
		rift(b_mid, b_add, _rift_pos(i), open * (1.0 + 0.25 * pulse * absf(sin(t * 18.0 + i))), 12.0, t, 40 + i)
	# 紳士の銃口の先の裂け目（弾が入る）
	var entry := RBMHeroFx.env(t, T.raise, T.shots - 0.1, T.cross - 0.1, T.cross + 0.1)
	var ln := gun_at("dual_open_fire_15", "near")
	var rn := gun_at("dual_open_fire_15", "far")
	if not ln.is_empty():
		rift(b_mid, b_add, ln.p + ln.d * 12.0, entry, 9.0, t, 70)
		rift(b_mid, b_add, rn.p + rn.d * 12.0, entry, 9.0, t, 71)
	# 左右交互の射撃: 銃口 → すぐ先の裂け目へ。四人を囲む裂け目から飛び出して当たる
	for i in range(T.count):
		var st := _shot_time(i)
		var hand := "near" if i % 2 == 0 else "far"
		var g := gun_at("dual_open_fire_15", hand)
		if g.is_empty():
			continue
		muzzle(b_add, g.p, g.d, t - st, 1.0)
		tracer(b_add, g.p, g.p + g.d * 12.0, t - st, 0.03, PALE)
		var from := _rift_pos(i % 6)
		var tgt: Vector2 = target_chest(_shot_target(i))
		RBMHeroRooftop.glow(b_add, from, 6.0 * RBMHeroFx.env(t - st, 0.0, 0.02, 0.05, 0.12), Color(ROSE, 0.9))
		tracer(b_add, from, tgt, t - st - 0.02, 0.07, ROSE)
		bullet_hit(b_add, b_front, tgt, (tgt - from).normalized(), t - st - 0.09, 100 + i * 7, 0.9)
		view["shake"] += hit_shake(t - st - 0.09, 2.5, 90.0, 0.15)
	var evs := []
	for h in hits():
		evs.append(h)
	ally_hits(t, evs, 0.8)
	# 溜め: 赤い糸が裂け目から四人の中心へ伸び、本体の縁が赤く光る
	var charge := RBMHeroFx.env(t, T.cross, T.fire - 0.15, T.fire, T.impact + 0.05)
	for i in range(6):
		var r: RBMHeroFxRibbon = threads[i]
		r.visible = charge > 0.01
		if r.visible:
			var from := _rift_pos(i)
			r.set_path(RBMHeroFx.bow(from, pc + Vector2(0, -18), 6.0 * (1.0 if i % 2 == 0 else -1.0), 16), 1.6 + 2.5 * RBMHeroFx.ramp(t, T.fire - 0.05, T.impact))
			sp(r, {"head": RBMHeroFx.ramp(t, T.cross + 0.04 * i, T.cross + 0.3 + 0.04 * i), "tail": 0.0, "flow": t * 3.0, "fade": charge})
	view["hero"]["lit"] = 0.6 * RBMHeroFx.env(t, T.cross - 0.1, T.fire - 0.2, T.impact, T.impact + 0.5)
	view["hero"]["lit_col"] = RED
	# 一斉射撃: 前にそろえた二丁から水平に撃ち（銃口の先の裂け目へ）、6つの裂け目すべてから光が中心へ
	var fn := gun_at("dual_forward_fire_15", "near")
	var ff := gun_at("dual_forward_fire_15", "far")
	if not fn.is_empty():
		muzzle(b_add, fn.p, fn.d, t - T.fire, 1.6)
		muzzle(b_add, ff.p, ff.d, t - T.fire, 1.6)
		rift(b_mid, b_add, ff.p + ff.d * 12.0, RBMHeroFx.env(t, T.cross, T.fire - 0.05, T.fire + 0.08, T.fire + 0.3), 13.0, t, 72)
	var volley := RBMHeroFx.env(t, T.fire + 0.02, T.fire + 0.06, T.impact, T.impact + 0.12)
	for i in range(6):
		RBMHeroRooftop.beam(b_add, _rift_pos(i), pc + Vector2(0, -18), 9.0, 3.0, ROSE, volley * 1.6)
	view["hero"]["flash"] = 0.35 * (1.0 - RBMHeroFx.ramp(t - T.fire, 0.0, 0.12)) if t >= T.fire else 0.0
	view["hero"]["flash_col"] = PALE
	# 終幕の一撃: 深紅の墨の大爆発・衝撃の輪・割れ目・花びら
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.45, 1.0)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var c := pc + Vector2(0, -12)
		show_blast(blast, blobs(c, a, 30, 41, 210.0, 90.0, 62.0, 70.0, .5, .4, 7.0), a, {"flow": a * .3, "cool": .02 + RBMHeroFx.ramp(a, .2, 1.0) * .14, "erode": RBMHeroFx.ramp(a, .2, .95), "fade": bfin, "erode_noise": .5,
			"polar": 1.0, "detail": .7, "amp": 30.0, "radial_heat": .4, "heat_center": w(c), "heat_radius": 260.0 * RBMHeroFx.burst(a, 6.0), "erode_radial": 140.0, "tone_cap": 1.0})
		refract_wave(c, a, 0.8, 360.0, 5.0, 0.035)
		sparks(b_add, c, a, 1.1, 160, 33, 900.0, PALE, RED, 0.0, TAU, 140.0, 2.2)
	cracks.visible = a >= 0.0 and a < 2.3
	if cracks.visible:
		sp(cracks, {"center": w(pc + Vector2(0, 8)), "reveal": 30.0 + 120.0 * RBMHeroFx.burst(a, 6.0), "fade": 1.0 - RBMHeroFx.ramp(a, 1.3, 2.3), "glow": 0.3 + 0.5 * (1.0 - RBMHeroFx.ramp(a, 0.0, 1.2))})
	for i in range(3):
		show_ring(rings[i], pc + Vector2(0, -6), a - i * 0.07, 0.75, 260.0 - i * 30.0, 9.0 - i * 2.0, 5.5, 0.02)
	if a >= 0.0:
		ally_light(RBMHeroFx.env(a, 0.0, 0.04, 0.3, 0.8), RED, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.25, 0.65) * 1.25)
		set_post({"flash": 0.22 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), "chroma": 0.006 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3))})
	view["shake"] += hit_shake(a, 16.0, 70.0, 0.6) + hit_shake(t - T.fire, 5.0, 80.0, 0.2)
	petals(b_front, pc + Vector2(0, -16), a, 2.4, 90, 51, 260.0, 1.0, 0.6)
	_petal_rain(t)
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()

## 深紅の幕: 画面の両端と上に下りて（帽子に手をやった時）、終幕の後に上がる
func _curtains(t: float) -> void:
	var down := RBMHeroFx.ramp(t, T.lift, T.reveal + 0.1)
	down = 1.0 - pow(1.0 - down, 3.0)
	var up := RBMHeroFx.ramp(t, T.curtain_up, T.end - 0.2)
	var hang := down * (1.0 - up * up)
	for side in range(2):
		for i in range(5):
			var r: RBMHeroFxRibbon = curtains[side * 5 + i]
			r.visible = hang > 0.01
			if not r.visible:
				continue
			var x := (-6.0 + 15.0 * i) if side == 0 else (646.0 - 15.0 * i)
			var length := (150.0 + 60.0 * float(4 - i) / 4.0) * hang
			var sway := sin(t * 1.6 + i * 0.9 + side) * 3.0
			var pts := PackedVector2Array()
			for k in range(10):
				var f := float(k) / 9.0
				pts.append(Vector2(x + sway * f * f + (8.0 * f * f if side == 0 else -8.0 * f * f) * float(4 - i) / 4.0, -12.0 + length * f))
			r.set_path(pts, 12.0)
			sp(r, {"head": 1.0, "tail": 0.0, "flow": t * 0.2, "fade": 0.95})
	valance.visible = hang > 0.01
	if valance.visible:
		var pts := PackedVector2Array()
		for k in range(24):
			var f := float(k) / 23.0
			pts.append(Vector2(-20.0 + 680.0 * f, -16.0 + 30.0 * hang + 7.0 * absf(sin(f * PI * 7.0))))
		valance.set_path(pts, 12.0)
		sp(valance, {"head": 1.0, "tail": 0.0, "flow": t * 0.1, "fade": 0.95})

## カーテンコールの間に降る花びら
func _petal_rain(t: float) -> void:
	var on := RBMHeroFx.env(t, T.impact + 0.3, T.impact + 0.6, T.end - 0.5, T.end)
	if on <= 0.0:
		return
	for i in range(46):
		var x := 40.0 + 300.0 * RBMHeroFx.r(i, 61)
		var q := fmod(t * (0.22 + 0.12 * RBMHeroFx.r(i, 62)) + RBMHeroFx.r(i, 63), 1.0)
		var p := Vector2(x + sin(t * 2.0 + i) * 8.0, -8.0 + 330.0 * q)
		var col := RED.lerp(Color("#7a1026"), RBMHeroFx.r(i, 64) * 0.6)
		b_front.dot_px(p, 2.0, Color(col, on * 0.9))
		if absf(sin(t * 7.0 + i)) > 0.5:
			b_front.dot_px(p + Vector2(2, 0), 1.0, Color(ROSE, on * 0.8))
