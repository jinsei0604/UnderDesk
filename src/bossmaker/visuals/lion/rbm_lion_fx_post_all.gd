extends RBMLionFxBase
## 日蝕の獅皇・覚醒後全体「獅皇の踏破」（2026-11-12 作り直し）: 獅皇は立ち姿のまま動かない。四人の頭上に金の太陽が現れ、
## 覚醒と同じ黒い月が重なっていく（世界が陰る）→ 皆既の瞬間に縁の一点が光り、闇が落ちる（赤黒い世界・鼓動の揺らぎ・灰）
## → 光冠から破滅の光が四人へ順に落ちる → 日蝕が四人の上へ崩れ落ち、画面全体を覆う黒金と深紅の大爆発 → 余韻。

const T := {"crouch": 3.02, "sun": 0.40, "bite": 0.60, "total": 1.95, "beams": [2.30, 2.55, 2.80, 3.05], "fall": 3.30, "collapse": 3.55, "settle": 4.75, "end": 5.70}
const ORDER := [1, 3, 0, 2]
const GOLD := Color("#ffd27a")
const HOT := Color("#fff1c8")
const RED := Color("#e0402a")
const BEAM := ["#1a0608", "#5a1014", "#c0301c", "#f07a20", "#ffd27a", "#fff4d8"]

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var eclipse: ColorRect
var beams: Array = []
var blast: ColorRect
var rings: Array = []
var final_share := 0.4

func duration() -> float:
	return T.end

func impact() -> float:
	return T.collapse

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.beams[i]), ORDER[i]])
	return out

func stops() -> Array:
	return [[T.collapse, 0.14]]

## 立ち姿のまま日蝕を起こす → 太陽が落ちてくる直前に一瞬かがむ → 落ちてくる所で前脚を突いて咆哮（1回だけ）→ 立ち姿。
## 後脚で立つポーズは使わない（2026-11-12 ユーザー指定）
func pose_keys() -> Array:
	return [[0.0, 4], [T.crouch, 1], [T.fall, 3], [T.settle, 4]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"], [T.fall, Vector2.ZERO, "snap"], [T.fall + 0.05, Vector2(-6, 0), "out"], [T.settle, Vector2(-6, 0), "snap"], [T.settle + 0.25, Vector2.ZERO, "out"]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25

func _build() -> void:
	b_back = batch(back)
	eclipse = pquad(back, Rect2(0, 0, 10, 10), "eclipse", {"pal": RBMHeroFx.pal(ECLIPSE), "seed": 7.7})
	for i in range(4):
		beams.append(quad(back, Rect2(0, -100, 120, 360), "pillar", {"pal": RBMHeroFx.pal(BEAM), "seed": 3.0 + i, "glow_col": Vector3(1., .3, .1)}))
	blast = blast_quad(back, BLACKGOLD, RBMHeroFx.DARK, {"amp": 42., "k": .045, "seed": 9.9, "glow": .8, "glow_col": Vector3(.95, .3, .1), "glow_r": 60.})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_RED if i != 1 else RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 1.0 + i * 2.3, "glow": .4, "glow_col": Vector3(.95, .3, .1)}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var party := _center()
	var sky := Vector2(party.x + 6, 66)
	var a := t - T.collapse
	var sun := RBMHeroFx.ramp(t, T.sun, T.sun + 0.4)
	var bite := RBMHeroFx.ramp(t, T.bite, T.total)
	bite = bite * bite * (3.0 - 2.0 * bite)
	var total := RBMHeroFx.ramp(t, T.total - 0.05, T.total + 0.05)
	var dread := RBMHeroFx.ramp(t, T.bite + 0.6, T.total + 0.1)
	var drop := RBMHeroFx.ramp(t, T.fall, T.collapse)
	var r := 46.0 * (1.0 - 0.35 * drop * drop)
	var corona := 18.0 + 16.0 * bite + 34.0 * total + 26.0 * RBMHeroFx.env(t, T.fall, T.fall + 0.1, T.collapse, T.collapse + 0.05)
	var center := sky.lerp(party + Vector2(0, -20), drop * drop)
	if a < 0.06:
		show_eclipse(eclipse, center, r, corona, {"flow": t * 1.1, "power": 0.6 + 0.4 * bite + 0.5 * total, "bite": Vector2(lerpf(2.3, 0.0, bite) * r, -lerpf(0.5, 0.0, bite) * r), "fade": sun,
			"sun_fill": 1.0 - total, "dread": dread, "rim": 1.0})
	else:
		eclipse.visible = false
	# 皆既の瞬間: 縁の一点が強く光る
	var ring_flash := RBMHeroFx.env(t, T.total - 0.12, T.total - 0.02, T.total + 0.05, T.total + 0.4)
	if ring_flash > 0.0:
		var bead := center + Vector2(-0.72, -0.7) * r
		disc(b_add, bead, 4.0 + 10.0 * ring_flash, Color(HOT, 0.9 * ring_flash))
		disc(b_add, bead, 2.0 + 4.0 * ring_flash, Color(1, 1, 1, ring_flash))
	# 世界: 陰り、皆既で赤黒く落ちる。四人は深紅に照らされ、縮み上がる
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.bite, 0.1], [T.total - 0.1, 0.6], [T.total + 0.1, 0.88], [T.collapse, 0.92], [T.collapse + 0.3, 0.5], [T.end, 0.15]])
	view["dim_col"] = Color(0.05, 0.0, 0.01).lerp(Color(0.04, 0.03, 0.01), 1.0 - dread)
	set_post({"desat": 0.45 * dread * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3)), "vig": 0.15 + 0.5 * dread * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.5)), "vig_col": Vector3(.12, .0, .01), "vig_r": .24})
	for k in range(3):
		var pt := T.total + 0.1 + k * 0.4
		refract_wave(center, t - pt, 0.6, 300.0, 4.0, 0.015 + 0.005 * k)
	embers(b_add, Rect2(40, 10, 400, 40), t, 70, 3, -260.0, Color(0.45, 0.35, 0.33), total * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.2)), 2.0, 12.0)
	if a < 0.0:
		ally_light(0.5 * total, RED, -1.0)
	# 獅皇は立ち姿のまま: 日蝕の後は深紅の縁の光と胸の宝石の光だけ
	view["hero"]["lit"] = 0.55 * dread * (1.0 - RBMHeroFx.ramp(a, 0.3, 1.0))
	view["hero"]["lit_col"] = RED
	view["hero"]["lit_side"] = -1.0
	var gem := at("mark")
	disc(b_add, gem, 3.0 + 3.0 * total, Color(RED, 0.8 * total * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.5))))
	# 破滅の光が四人へ順に落ちる
	for i in range(4):
		var bt := t - float(T.beams[i])
		var tgt: Vector2 = targets[ORDER[i]]
		var bf := RBMHeroFx.ramp(bt, 0.0, 0.03) * (1.0 - RBMHeroFx.ramp(bt, 0.22, 0.5))
		var q: ColorRect = beams[i]
		q.visible = bt >= 0.0 and bf > 0.0 and present[ORDER[i]]
		if q.visible:
			q.position = Vector2(tgt.x - 60, -100)
			q.size = Vector2(120, tgt.y + 100)
			sp(q, {"width": lerpf(.05, .55, RBMHeroFx.burst(bt, 14.0)) * (1.0 - .5 * RBMHeroFx.ramp(bt, .12, .45)), "flow": t * 3.0, "fade": bf, "flare": .9})
		if bt >= 0.0 and present[ORDER[i]]:
			sparks(b_add, tgt + Vector2(0, -6), bt, 0.5, 50, 7 + i, 420.0, HOT, RED, -PI * 0.5, PI * 1.1, 260.0, 2.0)
			view["shake"] += hit_shake(bt, 6.0, 80.0, 0.25)
	var evs := []
	for i in range(4):
		evs.append([float(T.beams[i]), ORDER[i]])
	ally_hits(t, evs, 1.0)
	# 日蝕が崩れ落ち、画面全体の大爆発
	var bfin := 1.0 - RBMHeroFx.ramp(a, 0.75, 1.3)
	blast.visible = a >= 0.0 and bfin > 0.0
	if blast.visible:
		var c := party + Vector2(10, -10)
		show_blast(blast, blobs(c, a, 48, 27, 640.0, 300.0, 120.0, 160.0, .55, 0.25, 6.0), a, {"flow": a * .22, "cool": .05 + RBMHeroFx.ramp(a, .25, 1.2) * .24, "erode": RBMHeroFx.ramp(a, .42, 1.25), "fade": bfin, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 42.0, "radial_heat": .38, "heat_center": w(c), "heat_radius": 520.0 * RBMHeroFx.burst(a, 6.0), "erode_radial": 240.0, "tone_cap": .92})
		refract_wave(c, a, 0.9, 700.0, 4.6, 0.04)
		sparks(b_add, c, a, 1.2, 200, 33, 1300.0, HOT, RED, 0.0, TAU, 160.0, 2.6)
		shards(b_front, c + Vector2(0, -10), a, 1.2, 60, 35, 900.0, 7.0, RED, Color(0.05, 0.02, 0.02), 220.0)
	for i in range(3):
		show_ring(rings[i], party + Vector2(10, -10), a - i * 0.08, 0.8, 640.0, 10.0 - i * 2.0, 5.0, 0.03)
	view["shake"] += hit_shake(a, 20.0, 70.0, 0.7) + hit_shake(t - T.fall, 6.0, 60.0, 0.3) + hit_shake(t - T.fall, 9.0, 60.0, 0.45)
	refract_wave(at("front", 3, 0, -40), t - T.fall, 0.7, 360.0, 4.5, 0.03)
	if a >= 0.0:
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.4, 0.9), RED, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.2, 0.6) * 1.3)
	embers(b_add, Rect2(-20, 100, 680, 250), a, 160, 45, 260.0, RED, RBMHeroFx.env(a, .4, .7, 1.8, 2.4), 2.2, 18.0)
	b_back.commit(); b_add.commit(); b_front.commit()
