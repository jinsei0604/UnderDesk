extends RBMGentlemanFxLayer
## 異形紳士・覚醒後の単体「裂け目の二発」のエフェクト（2026-11-23 強化。動き・時刻は rbm_gentleman_vfx.gd のまま）。
## 世界が深紅の黒に沈み、相手のまわりの闇に赤い目が開く → 二丁の銃身の先に空間の裂け目が開き、撃ち込んだ弾が相手のそばの
## 裂け目から飛び出す（1発目は斜め上から、2発目は真横から）→ 2発目が当たると深紅の墨の大きな弾け・足元の割れ目・二重の衝撃の輪・
## 屈折・火花・花びら。

const EYES := [Vector2(-46, -52), Vector2(-24, -70), Vector2(30, -66), Vector2(52, -40), Vector2(-56, -16), Vector2(58, -8)]

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_mid: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var small: ColorRect
var cracks: ColorRect
var rings: Array = []

func _build() -> void:
	b_back = batch(back, false)
	b_back_add = batch(back)
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#120308", "#7a1026", "#ff5a6a", "#fff0f2"]), "seed": 4.6, "squash": .34, "line_w": .05, "glow_col": Vector3(1., .2, .3), "glow": .6})
	b_mid = batch(mid, false)
	small = blast_quad(front, CRIMSON_INK, INK_SMOKE, {"amp": 16., "k": .07, "seed": 2.6, "glow": .6, "glow_col": Vector3(.95, .15, .25), "glow_r": 22.})
	blast = blast_quad(front, CRIMSON_INK, INK_SMOKE, {"amp": 26., "k": .06, "seed": 8.8, "glow": .7, "glow_col": Vector3(.95, .15, .25), "glow_r": 40.})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i != 1 else RBMHeroFx.A4_DARK, {"squash": .45, "breakup": .5, "seed": 1.4 + i * 1.6, "glow": .5, "glow_col": Vector3(.95, .15, .25)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_mid.reset(); b_add.reset(); b_front.reset()
	var evs: Array = shots()
	var imp := impact()
	var a := t - imp
	var tgt := chest_of(0)
	var tf := foot_of(0)
	var first: float = evs[0].time if not evs.is_empty() else 1.3
	var first_hit: float = evs[0].hit if not evs.is_empty() else imp
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [first - 0.4, 0.3], [first_hit - 0.3, 0.45], [imp + 0.06, 0.3], [imp + 1.2, 0.15], [imp + 1.8, 0.0]])
	view["dim_col"] = Color(0.05, 0.0, 0.02)
	set_post({"vig": 0.2 + 0.4 * RBMHeroFx.env(t, first - 0.5, first, imp + 0.3, imp + 1.6), "vig_col": Vector3(.18, .0, .03), "vig_r": .3})
	# 相手のまわりの闇に赤い目が開く → 終わると閉じる
	for i in range(EYES.size()):
		var open := RBMHeroFx.env(t, first + 0.1 + 0.07 * i, first + 0.25 + 0.07 * i, imp - 0.05, imp + 0.1)
		eyes(b_add, tf + EYES[i], open * (0.6 + 0.4 * absf(sin(t * 3.0 + i))), 0.9 + 0.2 * (i % 3))
	# 二発: 銃身の先の裂け目 → 相手のそばの裂け目から当たる
	var hit_evs: Array = []
	for e in evs:
		hit_evs.append_array(draw_shot(e, t, b_add, b_front, b_mid, 1.0 if int(e.index) == 0 else 1.15))
	ally_hits(t, hit_evs, 1.0)
	# 1発目が当たる: 小さな深紅の弾け
	if not evs.is_empty():
		var a1 := t - first_hit
		var fin1 := 1.0 - RBMHeroFx.ramp(a1, 0.25, 0.6)
		small.visible = a1 >= 0.0 and fin1 > 0.0
		if small.visible:
			show_blast(small, blobs(tgt, a1, 12, 33, 22.0, 18.0, 10.0, 12.0, .5, .4, 8.0), a1, {"flow": a1 * .4, "cool": .05 + RBMHeroFx.ramp(a1, .1, .6) * .2, "erode": RBMHeroFx.ramp(a1, .1, .6), "fade": fin1, "erode_noise": .5,
				"polar": 1.0, "detail": .7, "amp": 16.0, "radial_heat": .4, "heat_center": w(tgt), "heat_radius": 40.0 * RBMHeroFx.burst(a1, 8.0), "erode_radial": 28.0, "tone_cap": 1.0})
		show_ring(rings[2], tgt, a1, 0.4, 50.0, 3.0, 7.0, 0.0)
		view["shake"] += hit_shake(a1, 5.0, 90.0, 0.25)
	# 2発目（最後の一撃）: 深紅の墨の大きな弾け・足元の割れ目・二重の衝撃の輪・屈折・火花・花びら
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.4, 0.95)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var c := tgt + Vector2(0, -4)
		show_blast(blast, blobs(c, a, 22, 41, 60.0, 44.0, 22.0, 40.0, .5, .4, 7.5), a, {"flow": a * .3, "cool": .02 + RBMHeroFx.ramp(a, .2, 1.0) * .14, "erode": RBMHeroFx.ramp(a, .2, .95), "fade": bfin, "erode_noise": .5,
			"polar": 1.0, "detail": .7, "amp": 26.0, "radial_heat": .4, "heat_center": w(c), "heat_radius": 110.0 * RBMHeroFx.burst(a, 7.0), "erode_radial": 70.0, "tone_cap": 1.0})
	cracks.visible = a >= 0.0 and a < 2.0
	if cracks.visible:
		sp(cracks, {"center": w(tf + Vector2(0, 2)), "reveal": 16.0 + 60.0 * RBMHeroFx.burst(a, 6.0), "fade": 1.0 - RBMHeroFx.ramp(a, 1.1, 2.0), "glow": 0.3 + 0.5 * (1.0 - RBMHeroFx.ramp(a, 0.0, 1.0))})
	show_ring(rings[0], tgt, a, 0.6, 140.0, 6.0, 6.0, 0.025)
	show_ring(rings[1], tgt, a - 0.07, 0.65, 110.0, 4.0, 5.5, 0.0)
	if a >= 0.0:
		refract_wave(tgt, a, 0.6, 220.0, 5.5, 0.035)
		sparks(b_add, tgt, a, 0.9, 110, 47, 520.0, PALE, RED, 0.0, TAU, 160.0, 2.0)
		ally_light(RBMHeroFx.env(a, 0.0, 0.04, 0.2, 0.6), RED, 0.0)
		set_post({"flash": 0.16 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.1)), "chroma": 0.005 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3))})
		view["shake"] += hit_shake(a, 12.0, 80.0, 0.45)
	petals(b_front, tgt, a, 1.8, 50, 53, 200.0, 1.0, 0.5)
	b_back.commit(); b_back_add.commit(); b_mid.commit(); b_add.commit(); b_front.commit()
