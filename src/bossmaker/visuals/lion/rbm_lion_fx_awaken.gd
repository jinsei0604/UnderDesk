extends RBMLionFxBase
## 金環の聖獣 → 日蝕の獅皇「王衣の目覚め」（2026-11-12 作り直し）: 聖獣の背に金の太陽が昇る → 黒い月がゆっくり重なっていく
## （世界が少しずつ陰り、光が金から深紅へ）→ 皆既の瞬間に縁の一点が強く光り、闇が落ちる（赤黒い世界・鼓動の揺らぎ）
## → 深紅の王衣が噴き出す（一段目）→ 立ち上がって吠え、光冠が大きく燃え広がる（二段目）→ 力が集まる（鼓動3回）
## → 覚醒完了の咆哮: 光冠が爆ぜて黒金の炎が外へ噴き出す → 覚醒後の立ち姿。光冠は途中で縮めない。

const T := {"sun": 0.15, "distress": 1.00, "bite": 0.90, "total": 3.30, "early": 3.55, "late": 4.55, "tame": 5.15, "beats": [5.25, 5.50, 5.72], "done": 5.90, "stance": 6.90, "end": 7.90}
## 目の位置（絵の画素。awaken の2〜4枚目。2026-11-12 拡大して測った）
const EYES := {2: Vector2(142, 108), 3: Vector2(131, 107), 4: Vector2(124, 79)}
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const RED := Color("#e0402a")
const BLOOD := Color("#a01818")

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var eclipse: ColorRect
var surge: ColorRect
var blast: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.done

func stops() -> Array:
	return [[T.done, 0.14]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.distress, 2], [T.early, 3], [T.late, 4], [T.done, 5], [T.stance, 0]]

func _build() -> void:
	b_back = batch(back)
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(ECLIPSE), "seed": 3.1})
	surge = blast_quad(back, RBMHeroFx.DARK, BLACKGOLD, {"amp": 26., "k": .07, "seed": 4.2, "glow": .6, "glow_col": Vector3(.9, .2, .1), "glow_r": 36.})
	blast = blast_quad(back, BLACKGOLD, RBMHeroFx.DARK, {"amp": 42., "k": .045, "seed": 8.8, "glow": .8, "glow_col": Vector3(.95, .2, .1), "glow_r": 58.})
	for i in range(4):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i % 2 == 0 else RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .5, "seed": 2.0 + i * 3.1, "glow": .4, "glow_col": Vector3(.95, .2, .1)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var c := HOME + Vector2(16, -86)
	var r := 44.0
	var a2 := t - T.done
	var sun := RBMHeroFx.ramp(t, T.sun, T.sun + 0.6)
	var bite := RBMHeroFx.ramp(t, T.bite, T.total)
	bite = bite * bite * (3.0 - 2.0 * bite)
	var total := RBMHeroFx.ramp(t, T.total - 0.05, T.total + 0.05)
	# 光冠: 皆既で一段、二段目でさらに、覚醒完了で爆ぜる（途中で縮めない）
	var corona := 16.0 + 14.0 * bite + 26.0 * total + 22.0 * RBMHeroFx.ramp(t, T.late, T.done) + 70.0 * RBMHeroFx.burst(maxf(a2, 0.0), 6.0) * RBMHeroFx.ramp(a2, -0.01, 0.0)
	var dread := RBMHeroFx.ramp(t, T.bite + 0.8, T.total + 0.1)
	# 爆ぜた光冠は広がりながら薄れて消える（縮めない）。日蝕そのものは立ち姿の間に消える
	var fade := sun * (1.0 - RBMHeroFx.ramp(a2, 0.25, 1.1))
	show_eclipse(eclipse, c, r, corona, {"flow": t * 0.9, "power": 0.6 + 0.4 * bite + 0.5 * total + 0.4 * RBMHeroFx.ramp(t, T.late, T.done), "bite": Vector2(lerpf(2.3, 0.0, bite) * r, -lerpf(0.5, 0.0, bite) * r), "fade": fade,
		"sun_fill": 1.0 - total, "dread": dread, "rim": 1.0})
	# 皆既の瞬間: 縁の一点が強く光る（ダイヤモンドリング）
	var ring_flash := RBMHeroFx.env(t, T.total - 0.12, T.total - 0.02, T.total + 0.05, T.total + 0.4)
	if ring_flash > 0.0:
		var bead := c + Vector2(-0.72, -0.7) * r
		disc(b_add, bead, 4.0 + 10.0 * ring_flash, Color(HOT, 0.9 * ring_flash))
		disc(b_add, bead, 2.0 + 4.0 * ring_flash, Color(1, 1, 1, ring_flash))
		ring_line(b_add, c, r + 1.0, 2.0, Color(HOT, 0.7 * ring_flash))
	# 世界: 少しずつ陰り、皆既で赤黒く落ちる
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.bite, 0.05], [T.total - 0.1, 0.55], [T.total + 0.1, 0.86], [T.done, 0.9], [T.done + 0.3, 0.6], [T.stance, 0.45], [T.end, 0.15]])
	view["dim_col"] = Color(0.05, 0.0, 0.01).lerp(Color(0.04, 0.03, 0.01), 1.0 - dread)
	set_post({"desat": 0.5 * dread * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.3)), "vig": 0.15 + 0.5 * dread * (1.0 - RBMHeroFx.ramp(a2, 0.2, 1.0)), "vig_col": Vector3(.12, .0, .01), "vig_r": .24})
	# 聖獣への光: 最初は金の後光、皆既の後は深紅の縁の光（逆光）
	view["hero"]["lit"] = 0.45 * sun * (1.0 - dread) + 0.6 * dread * (1.0 - RBMHeroFx.ramp(a2, 0.3, 1.0))
	view["hero"]["lit_col"] = GOLD.lerp(RED, dread)
	view["hero"]["lit_side"] = 1.0
	# 陰っていく間: 体が小さく震え、金の粒が落ちて消える
	if t >= T.distress and t < T.early:
		view["shake"] += Vector2(sin(t * 41.0), 0.0) * 0.6 * bite
		embers(b_add, Rect2(HOME.x - 70, HOME.y - 110, 140, 40), t, 40, 7, -120.0, GOLD, (1.0 - dread) * bite, 2.0, 6.0)
	# 皆既の後: 鼓動のたびに日蝕から屈折の波、灰が降る
	for k in range(6):
		var pt := T.total + 0.1 + k * 0.42
		if pt < T.done:
			refract_wave(c, t - pt, 0.6, 260.0, 4.0, 0.012 + 0.004 * k)
	embers(b_add, Rect2(0, 20, 480, 40), t, 70, 11, -280.0, Color(0.45, 0.35, 0.33), total * (1.0 - RBMHeroFx.ramp(a2, 0.5, 1.5)), 2.0, 14.0)
	# 一段目: 深紅の王衣が噴き出す
	var a1 := t - T.early
	var f1 := 1.0 - RBMHeroFx.ramp(a1, 0.35, 0.7)
	surge.visible = a1 >= 0.0 and f1 > 0.0 and t < T.late + 0.3
	if surge.visible:
		var c1 := at("center", 3, 10, -6)
		show_blast(surge, blobs(c1, a1, 26, 7, 130.0, 80.0, 42.0, 70.0, .8, 0.0, 9.0), a1, {"flow": a1 * .4, "cool": .1, "erode": RBMHeroFx.ramp(a1, .2, .7), "fade": f1, "erode_noise": .4, "tone_cap": .9})
	show_ring(rings[0], HOME + Vector2(0, -2), a1, 0.6, 240.0, 6.0, 5.0, 0.025)
	view["shake"] += hit_shake(a1, 9.0, 70.0, 0.3) + hit_shake(t - T.late, 12.0, 70.0, 0.35)
	show_ring(rings[1], HOME + Vector2(0, -2), t - T.late, 0.7, 320.0, 7.0, 5.0, 0.03)
	# 影になっている間は体の周りの火の粉を出さない（目だけが光って見えるように）
	var mantle := RBMHeroFx.ramp(t, T.early, T.late) * (1.0 - RBMHeroFx.ramp(a2, 0.5, 1.2)) * (1.0 if a2 >= 0.0 else 0.15)
	embers(b_add, Rect2(HOME.x - 70, HOME.y - 60, 140, 60), t, 60, 13, 140.0, RED, mantle, 2.0, 8.0)
	embers(b_add, Rect2(HOME.x - 60, HOME.y - 50, 120, 50), t + 0.4, 40, 15, 120.0, GOLD, mantle * 0.7, 2.0, 8.0)
	# 溜め: 周りの光が体へ集まる（鼓動3回）
	var tm := RBMHeroFx.ramp(t, T.tame, T.done)
	if t >= T.tame and a2 < 0.0:
		inward(b_add, at("center"), t, 130, 21, 10.0, 280.0, 2.2, RED, tm, 2.4)
		inward(b_add, at("center"), t + 0.3, 70, 23, 8.0, 220.0, 1.8, GOLD, tm, 2.0)
		view["shake"] += Vector2(sin(t * 33.0), cos(t * 27.0) * 0.6) * tm * 1.5
	for at_t in T.beats:
		view["shake"] += hit_shake(t - float(at_t), 6.0, 60.0, 0.18)
		refract_wave(c, t - float(at_t), 0.5, 300.0, 4.0, 0.02)
	# 覚醒完了: 光冠が爆ぜ、黒金の炎が外へ噴き出す
	var bf := 1.0 - RBMHeroFx.ramp(a2, 0.65, 1.15)
	blast.visible = a2 >= 0.0 and bf > 0.0
	if blast.visible:
		var cb := HOME + Vector2(0, -50)
		show_blast(blast, blobs(cb, a2, 48, 17, 560.0, 270.0, 112.0, 160.0, .6, 0.3, 6.0), a2, {"flow": a2 * .22, "cool": .05 + RBMHeroFx.ramp(a2, .2, 1.1) * .24, "erode": RBMHeroFx.ramp(a2, .38, 1.1), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 42.0, "radial_heat": .4, "heat_center": w(cb), "heat_radius": 480.0 * RBMHeroFx.burst(a2, 6.0), "erode_radial": 230.0, "tone_cap": .92})
		refract_wave(HOME, a2, 0.9, 640.0, 5.0, 0.04)
		sparks(b_add, cb, a2, 1.1, 180, 31, 1150.0, HOT, RED, 0.0, TAU, 160.0, 2.4)
		shards(b_front, cb, a2, 1.1, 50, 33, 800.0, 6.0, RED, Color(0.05, 0.02, 0.02), 200.0)
	show_ring(rings[2], HOME, a2, 0.8, 600.0, 9.0, 5.0, 0.035)
	show_ring(rings[3], c, a2 - 0.06, 0.8, 520.0, 7.0, 5.0, 0.025)
	view["shake"] += hit_shake(a2, 18.0, 65.0, 0.7)
	if a2 >= 0.0 and a2 < 0.12:
		view["hero"]["flash"] = 1.0 - a2 / 0.12
		view["hero"]["flash_col"] = HOT
	ally_light(0.6 * RBMHeroFx.env(a2, 0.0, 0.05, 0.4, 1.0), RED, -1.0)
	if a2 >= 0.0:
		view["hero"]["lit"] = 0.5 * (1.0 - RBMHeroFx.ramp(a2, 0.2, 1.0))
		view["hero"]["lit_col"] = RED
	embers(b_add, Rect2(-20, 120, 680, 230), a2, 160, 41, 240.0, RED, RBMHeroFx.env(a2, .3, .6, 1.4, 1.9), 2.2, 16.0)
	# 竜と同じく、皆既から覚醒完了まで姿は影になって見えず、目だけが光る（2026-11-12 ユーザー指定）
	var sil := RBMHeroFx.ramp(t, T.total - 0.08, T.total + 0.12) * (1.0 - RBMHeroFx.ramp(a2, -0.001, 0.0))
	if sil > 0.0:
		view["hero"]["silhouette"] = sil
		view["hero"]["sil_col"] = Color(0.03, 0.005, 0.01)
		var pose := int(body.get("pose", 1))
		if EYES.has(pose):
			var eye := px(EYES[pose])
			var beat := 0.0
			for at_t in T.beats:
				beat = maxf(beat, RBMHeroFx.env(t, float(at_t), float(at_t) + 0.04, float(at_t) + 0.1, float(at_t) + 0.35))
			var open := RBMHeroFx.ramp(t, T.total + 0.15, T.total + 0.45)
			# 暗がりに灯る赤い目（機械武者の覚醒の目と同じ光り方。2026-11-12 ユーザー指定）。鼓動で少し強くなる
			eye_glow(b_front, eye, sil * open * (1.0 + 0.3 * beat))
	# 覚醒完了と同時に太陽のオーラが燃え上がり、そのまま常時のオーラへ
	view["hero"]["sun_aura"] = RBMHeroFx.ramp(a2, 0.0, 0.08) * (1.0 + 0.8 * (1.0 - RBMHeroFx.ramp(a2, 0.1, 0.9)))
	b_back.commit(); b_add.commit(); b_front.commit()
