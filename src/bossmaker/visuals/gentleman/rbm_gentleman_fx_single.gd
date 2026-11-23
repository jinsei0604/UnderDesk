extends RBMGentlemanFxLayer
## 異形紳士・覚醒前の単体「霧の決闘」のエフェクト（2026-11-23 強化。動きは rbm_gentleman_vfx.gd のまま）。
## 霧になって消える所・相手と同じ高さに現れる所で黒い墨が弾けて花びらが散り、赤い目の残像が霧の中を走る → 構えると世界が
## 暗くなり、銃口から相手の胸へ赤い照準の線がちらつく → 撃つと大きな銃火と光の筋、当たった所で深紅の墨が弾け、衝撃の輪・
## 屈折・火花・花びら → 銃口から硝煙が上り、また霧になって元の場所へ戻る。

const Vfx := preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var vanish: ColorRect
var appear: ColorRect
var blast: ColorRect
var ring_hit: ColorRect
var ring_hit2: ColorRect
var ring_ground: ColorRect

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	vanish = blast_quad(mid, INK_SMOKE, INK_SMOKE, {"amp": 18., "k": .08, "seed": 3.1, "glow": .3, "glow_col": Vector3(.6, .05, .12), "glow_r": 22.})
	appear = blast_quad(mid, INK_SMOKE, INK_SMOKE, {"amp": 18., "k": .08, "seed": 5.7, "glow": .3, "glow_col": Vector3(.6, .05, .12), "glow_r": 22.})
	b_mid = batch(mid, false)
	ring_ground = ring_quad(back, RBMHeroFx.A4_DARK, {"squash": .3, "breakup": .55, "seed": 1.3, "glow": .4, "glow_col": Vector3(.9, .1, .2)})
	blast = blast_quad(front, CRIMSON_INK, INK_SMOKE, {"amp": 20., "k": .07, "seed": 7.3, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 30.})
	ring_hit = ring_quad(front, RBMHeroFx.A4_RED, {"squash": .5, "breakup": .45, "seed": 2.2, "glow": .5, "glow_col": Vector3(.95, .15, .25)})
	ring_hit2 = ring_quad(front, RBMHeroFx.A4_DARK, {"squash": .5, "breakup": .6, "seed": 4.8, "glow": .3, "glow_col": Vector3(.95, .15, .25)})
	b_add = batch(front)
	b_front = batch(front, false)

func _ink_burst(q: ColorRect, c: Vector2, a: float, seed_: int) -> void:
	var fin := 1.0 - RBMHeroFx.ramp(a, 0.25, 0.7)
	q.visible = a >= 0.0 and fin > 0.0
	if q.visible:
		show_blast(q, blobs(c, a, 14, seed_, 26.0, 30.0, 13.0, 26.0, .3, .6, 6.0), a, {"flow": a * .5, "cool": .5, "erode": RBMHeroFx.ramp(a, .1, .7), "fade": fin, "erode_noise": .6, "detail": .6, "amp": 18.0, "tone_cap": .7})

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var boss_foot := vp(vfx.get("boss"))
	var duel := vp(vfx.call("duel_foot"))
	var h := host()
	var out0: float = Vfx.STEP_OUT[0]
	var in0: float = Vfx.STEP_IN[0]
	var back0: float = Vfx.BACK_OUT[0]
	var back1: float = Vfx.BACK_IN[0]
	var e: Dictionary = shots()[0]
	var shot: float = e.time
	var hit_t: float = e.hit
	var tgt: Vector2 = chest_of(0)
	var a := t - hit_t
	# 構えると世界が暗くなる（決闘）→ 当たった後に戻る
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [out0, 0.12], [in0 + 0.2, 0.3], [shot - 0.3, 0.42], [hit_t + 0.05, 0.3], [back0, 0.12], [back1 + 0.4, 0.0]])
	view["dim_col"] = Color(0.04, 0.0, 0.02)
	set_post({"vig": 0.15 + 0.35 * RBMHeroFx.env(t, in0, shot - 0.2, hit_t + 0.3, back0), "vig_col": Vector3(.15, .0, .03), "vig_r": .32})
	# 霧になって消える・現れる（行き・帰り）: 黒い墨が弾け、花びらが散る
	var vanish_at := out0 if t < back0 - 0.3 else back0
	var vanish_p := (boss_foot if t < back0 - 0.3 else duel) + Vector2(0, -26)
	_ink_burst(vanish, vanish_p, t - vanish_at, 31)
	var appear_at := in0 if t < back1 - 0.1 else back1
	var appear_p := (duel if t < back1 - 0.1 else boss_foot) + Vector2(0, -26)
	_ink_burst(appear, appear_p, t - appear_at, 47)
	show_ring(ring_ground, appear_p + Vector2(0, 25), t - appear_at, 0.55, 70.0, 4.0, 6.0, 0.0)
	for k in range(2):
		var at: float = [out0, back0][k]
		var from: Vector2 = [boss_foot, duel][k] + Vector2(0, -30)
		petals(b_front, from, t - at, 1.1, 22, 300 + k * 10, 120.0, 0.9, 0.5)
		ink_puff(b_back, from + Vector2(0, 26), t - at, 0.8, 8, 320 + k * 10, 26.0, 6.0, 10.0)
	for k in range(2):
		var at2: float = [in0, back1][k]
		var to: Vector2 = [duel, boss_foot][k] + Vector2(0, -30)
		petals(b_front, to, t - at2, 1.0, 16, 340 + k * 10, 90.0, 0.8, 0.3)
		view["shake"] += hit_shake(t - at2, 2.5, 80.0, 0.18)
	# 霧の中を走る赤い目の残像（消えてから現れるまで）
	for k in range(2):
		var s0: float = [out0, back0][k]
		var s1: float = [in0 + 0.04, back1 + 0.04][k]
		var from_e := eye_of("hat_reach_00", [boss_foot, duel][k])
		var to_e := eye_of("hat_reach_00", [duel, boss_foot][k])
		if t >= s0 and t <= s1 + 0.12:
			var u := RBMHeroFx.ramp(t, s0 + 0.05, s1)
			var head := from_e.lerp(to_e, u * u * (3.0 - 2.0 * u))
			var tail := from_e.lerp(to_e, maxf(0.0, u - 0.45))
			var f := 1.0 - RBMHeroFx.ramp(t, s1, s1 + 0.12)
			for sgn in [-1.0, 1.0]:
				var o := Vector2(sgn * 1.6, 0)
				b_add.streak(tail + o, head + o, 1.2, Color(ROSE, f), Color(RED, 0.0))
			RBMHeroRooftop.glow(b_add, head, 5.0, Color(RED, 0.5 * f))
	# 本体の赤い目（構えている間は強く）
	var vis: float = vfx.call("host_alpha")
	var pose_now: String = Motion.frame("single", t)
	var glare := (0.45 + 0.55 * RBMHeroFx.env(t, in0 + 0.1, in0 + 0.4, hit_t + 0.4, back0)) * vis
	eyes(b_add, eye_of(pose_now, h), glare, 0.9)
	# 赤い照準の線（撃つ前にちらつく）と、相手の胸の小さな光
	var sight := RBMHeroFx.env(t, shot - 0.42, shot - 0.3, shot - 0.04, shot)
	if sight > 0.0:
		var flick := 0.55 + 0.45 * absf(sin(t * 47.0))
		b_add.line(e.mouth, e.dest, 0.7, Color(RED, 0.75 * sight * flick), Color(RED, 0.25 * sight * flick))
		RBMHeroRooftop.glow(b_add, e.dest, 3.5, Color(ROSE, 0.8 * sight * flick))
	# 撃つ: 大きな銃火・光の筋・本体の閃き
	var evs := draw_shot(e, t, b_add, b_front, b_mid, 1.25)
	view["hero"]["flash"] = 0.18 * (1.0 - RBMHeroFx.ramp(t - shot, 0.0, 0.08)) if t >= shot else 0.0
	view["hero"]["flash_col"] = Color(1.0, 0.85, 0.6)
	if t >= shot and t < shot + 0.08:
		set_post({"flash": 0.06 * (1.0 - (t - shot) / 0.08)})
	# 当たる: 深紅の墨の弾け・衝撃の輪・屈折・火花・花びら
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.3, 0.75)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var dir: Vector2 = e.d
		var c := tgt + dir * 4.0
		show_blast(blast, blobs(c, a, 16, 23, 28.0, 22.0, 12.0, 14.0, .5, .4, 8.0), a, {"flow": a * .4, "cool": .04 + RBMHeroFx.ramp(a, .15, .7) * .2, "erode": RBMHeroFx.ramp(a, .15, .7), "fade": bfin, "erode_noise": .5,
			"polar": 1.0, "detail": .7, "amp": 20.0, "radial_heat": .4, "heat_center": w(c), "heat_radius": 60.0 * RBMHeroFx.burst(a, 8.0), "erode_radial": 40.0, "tone_cap": 1.0})
	show_ring(ring_hit, tgt, a, 0.45, 70.0, 4.0, 7.0, 0.02)
	show_ring(ring_hit2, tgt, a - 0.05, 0.5, 52.0, 3.0, 6.0, 0.0)
	if a >= 0.0:
		refract_wave(tgt, a, 0.5, 150.0, 6.0, 0.03)
		sparks(b_add, tgt, a, 0.7, 70, 29, 360.0, PALE, RED, Vector2(e.d).angle(), 2.2, 200.0, 1.8)
		petals(b_front, tgt, a, 1.4, 26, 37, 150.0, 1.0, 0.4)
		set_post({"flash": 0.12 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08)), "chroma": 0.004 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.25))})
		view["shake"] += hit_shake(a, 9.0, 85.0, 0.35)
		ally_light(RBMHeroFx.env(a, 0.0, 0.03, 0.15, 0.45) * 0.8, RED, 0.0)
	ally_hits(t, evs, 1.0)
	# 銃口から上る硝煙
	var smoke := RBMHeroFx.env(t, shot + 0.05, shot + 0.2, back0 - 0.3, back0)
	if smoke > 0.0:
		for k in range(6):
			var q := fmod((t - shot) * 0.7 + RBMHeroFx.r(k, 51), 1.0)
			var p: Vector2 = Vector2(e.mouth) + Vector2(sin(t * 2.0 + k) * 2.5 - 4.0 * q, -26.0 * q)
			RBMHeroRooftop.glow(b_front, p, 2.0 + 5.0 * q, Color(0.62, 0.6, 0.68, 0.32 * smoke * sin(q * PI)))
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()
