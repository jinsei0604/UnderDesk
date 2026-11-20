class_name RBMKnightFx
extends RBMHeroFxBase
## 騎士の技のエフェクト（2026-11-20 作り直し。表示専用。戦闘の状態・乱数には触れない）。
## 2026-11-20 ユーザー「次は騎士。たぶん一番問題がある」（調査では: 単体はほぼエフェクトなし・全体は灰色の平たい三日月1つ・支援は剣を掲げるだけ）。
## ゴーレム・狼と同じ考え方（動きは少なく、要所の絵を切り替える。エフェクトはヒーロー・聖獣と同じ部品）で作り直す。
## 騎士の色: 紫の闇（鎧の色）＋技の属性の色。尖った星形・平たい輪・三角の棘は使わない。
## mode: "single"（剣圧の一閃: 頭上で溜め → 振り下ろすと三日月の剣圧が飛んで相手を斬る）
##       "aoe"（横薙ぎ: 剣を水平に掲げて溜め → 薙ぎ払うと巨大な三日月の剣圧が四人を薙ぐ）
##       "buff" / "heal"（剣を立てて祈ると、光の柱が降りて足元に光の輪）
## 座標は 640×360 の論理ドット（ステージの半分）。foot は騎士の足元。

const VIOLET := ["#12061e", "#2a0c46", "#4c1a7a", "#7a3ab4", "#b88ae8", "#f2e6ff"]
const VIOLET_WAKE := ["#08020e", "#160622", "#260a3a", "#3a1258", "#56207a", "#7a3aa0"]
const DUST := ["#3a3046", "#4e4258", "#62566c", "#786c80", "#8e8296", "#a698ac", "#c0b4c4", "#dcd2de"]
const PALE := Color("#f6eeff")
const PURPLE := Color("#9a5ad8")
## 絵の剣（騎士の足元から、論理ドット。frames を測った値）: 頭上で構えた剣（9）・振り下ろした剣先（2）・水平に掲げた剣（4）・突き出した剣先（5）・立てた剣先（8）
const BLADE_UP := [Vector2(-3, -86), Vector2(39, -53)]
const BLADE_DOWN := Vector2(-46, -3)
const BLADE_FLAT := [Vector2(-33, -65), Vector2(38, -66)]
const BLADE_THRUST := Vector2(-62, -49)
const BLADE_TIP_UP := Vector2(-9, -95)

var mode := "single"
var accent := Color("b7bbc2")
## 単体: 当たる所（相手の胸）と時刻
var contact := Vector2.ZERO
var hit_time := 0.84
var swing_time := 0.64
## 全体: 剣圧が四人の真ん中を通る時刻（最後の一撃）
var aoe_swing := 0.62

var b_back: RBMHeroFxBatch
var b_back_add: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var swing_arc: RBMHeroFxRibbon
var wave_wake: RBMHeroFxRibbon
var wave: RBMHeroFxRibbon
var wave_core: RBMHeroFxRibbon
var cuts: Array = []
var rings: Array = []
var pillar: ColorRect
var cracks: ColorRect

func _pal() -> Array:
	return [accent.darkened(0.85).to_html(false), accent.darkened(0.6).to_html(false), accent.darkened(0.3).to_html(false), accent.to_html(false), accent.lightened(0.55).to_html(false), "#ffffff"]

func _build() -> void:
	var glow_col := RBMHeroFx.v3(accent.lerp(PURPLE, 0.4))
	b_back = batch(back, false)
	b_back_add = batch(back)
	cracks = quad(back, RBMHeroFx.WORLD, "cracks", {"size": RBMHeroFx.WORLD.size, "pal": RBMHeroFx.pal(["#0e0618", "#2a1040", "#5a2a8a", accent.darkened(0.1).to_html(false)]), "seed": 4.4, "squash": .3, "line_w": .05, "glow_col": glow_col, "glow": .35})
	if mode in ["buff", "heal"]:
		pillar = quad(back, Rect2(0, -100, 120, 400), "pillar", {"pal": RBMHeroFx.pal(_pal()), "seed": 3.3, "glow_col": RBMHeroFx.v3(accent), "glow": .7})
	wave_wake = ribbon(back, VIOLET_WAKE, {"body": .85, "taper": .55, "skew": .7, "rough": .45, "rough_freq": 12., "streak": .5, "gain": 1.0, "glow": 0.0, "seed": 2.0})
	wave = ribbon(front, VIOLET, {"body": .7, "taper": .7, "skew": .6, "rough": .25, "rough_freq": 16., "streak": .45, "gain": 1.15, "glow": .6, "glow_col": glow_col, "seed": 3.0})
	wave_core = ribbon(front, _pal(), {"body": .55, "taper": .85, "skew": .5, "rough": .1, "streak": .3, "gain": 1.3, "glow": .8, "glow_col": RBMHeroFx.v3(accent), "seed": 4.0})
	swing_arc = ribbon(front, _pal(), {"body": .6, "taper": .8, "skew": .6, "rough": .15, "streak": .4, "gain": 1.25, "glow": .7, "glow_col": RBMHeroFx.v3(accent), "seed": 5.0})
	for i in range(6):
		cuts.append(ribbon(front, _pal(), {"body": .55, "taper": .9, "skew": .5, "rough": .1, "streak": .3, "gain": 1.3, "glow": .7, "glow_col": RBMHeroFx.v3(accent), "seed": 7.0 + i}))
	for i in range(3):
		rings.append(ring_quad(front, ["#3a1458", "#8a4ac8", "#e8d8ff", "#ffffff"], {"squash": .32, "breakup": .5, "seed": 1.0 + i * 2.1, "glow": .45, "glow_col": glow_col}))
	b_add = batch(front)
	b_front = batch(front, false)

func _step(t: float) -> void:
	b_back.reset(); b_back_add.reset(); b_add.reset(); b_front.reset()
	match mode:
		"single": _single(t)
		"aoe": _aoe(t)
		_: _support(t)
	b_back.commit(); b_back_add.commit(); b_add.commit(); b_front.commit()

## 剣に力が集まる: 刃に沿った光の筋・刃のまわりの光・刃へ吸い込まれる光の線・足元の紫の闇
func _charge(a: Vector2, b: Vector2, t: float, t0: float, t1: float, out_t: float) -> void:
	var p := RBMHeroFx.env(t, t0, t1, out_t, out_t + 0.06)
	if p <= 0.0:
		return
	var mid := (a + b) * 0.5
	var pulse := 0.85 + 0.15 * sin(t * 30.0)
	b_add.line(a, b, 4.0 * p * pulse, Color(accent, 0.35 * p), Color(accent, 0.35 * p))
	b_add.line(a, b, 1.4 * p, Color(PALE, 0.9 * p), Color(PALE, 0.9 * p))
	RBMHeroRooftop.glow(b_add, mid, 14.0 + 8.0 * p, Color(accent, 0.3 * p))
	RBMHeroRooftop.glow(b_add, b, 4.0 + 3.0 * p * pulse, Color(PALE, 0.8 * p))
	inward(b_add, mid, t - t0, 18, 31, 70.0, 4.0, 1.2, Color(accent.lerp(PURPLE, 0.4), 1.0), p, 2.2)
	RBMHeroRooftop.glow(b_back, foot + Vector2(0, -2), 26.0 * p, Color(0.08, 0.02, 0.14, 0.5 * p))
	embers(b_add, Rect2(foot.x - 24, foot.y - 50, 48, 50), t, 16, 33, 40.0, Color(PURPLE, 1.0), p, 1.4, 6.0)

## 単体: 頭上で溜める → 振り下ろした剣の軌跡（弧）→ 三日月の剣圧が相手へ飛ぶ → 相手を斜めに斬る（光・火花・切り傷）
func _single(t: float) -> void:
	_charge(foot + BLADE_UP[0], foot + BLADE_UP[1], t, 0.15, 0.55, swing_time - 0.02)
	var s := t - swing_time
	# 振り下ろした剣の軌跡（頭上の後ろから足元の前へ、大きな弧）
	swing_arc.visible = s >= 0.0 and s < 0.3
	if swing_arc.visible:
		var pts := PackedVector2Array()
		# 右上（頭上の後ろ）から頭の上を通って左下（足元の前）へ
		for k in range(20):
			var ang := lerpf(-0.6, -3.94, float(k) / 19.0)
			pts.append(foot + Vector2(-4, -50) + Vector2(cos(ang), sin(ang)) * Vector2(46, 44))
		swing_arc.set_path(pts, 4.5)
		sp(swing_arc, {"head": RBMHeroFx.ramp(s, 0.0, 0.05), "tail": RBMHeroFx.ramp(s, 0.06, 0.28), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(s, 0.18, 0.3)})
	# 三日月の剣圧: 剣を振り下ろした所から相手へ（縦に長い三日月、前へふくらむ）
	var from := foot + Vector2(-48, -34)
	var travel := hit_time - swing_time - 0.02
	var u := clampf((s - 0.02) / travel, 0.0, 1.0)
	var on := s >= 0.02 and t < hit_time + 0.05
	var c := from.lerp(contact + Vector2(6, 0), u)
	_crescent(c, 1.0 if on else 0.0, 38.0, t, true, 1.1)
	if on:
		# 地面をなめる剣圧の跡と火花
		embers(b_add, Rect2(c.x - 6, c.y - 20, 12, 40), t, 8, 41, 30.0, Color(accent, 1.0), 0.8, 1.3, 4.0)
	var a := t - hit_time
	if a < 0.0:
		wave_wake.visible = false
		for r in cuts:
			(r as RBMHeroFxRibbon).visible = false
		return
	# 当たった: 斜めの大きな切り傷（2本、少しずれて）・白い芯・属性の光・火花・衝撃の輪
	for k in range(2):
		var r: RBMHeroFxRibbon = cuts[k]
		var ca := a - 0.04 * k
		r.visible = ca >= 0.0 and ca < 0.45
		if r.visible:
			var off := Vector2(-5.0 + 10.0 * k, -3.0 + 6.0 * k)
			r.set_path(RBMHeroFx.bow(contact + off + Vector2(32, -38), contact + off + Vector2(-30, 32), 7.0, 16), 5.0 - 1.5 * k)
			sp(r, {"head": RBMHeroFx.ramp(ca, 0.0, 0.05), "tail": RBMHeroFx.ramp(ca, 0.1, 0.42), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(ca, 0.25, 0.45)})
	if a < 0.1:
		var k2 := 1.0 - a / 0.1
		RBMHeroRooftop.glow(b_add, contact, 12.0 * k2 + 4.0, Color(PALE, 0.85 * k2))
		RBMHeroRooftop.glow(b_add, contact, 24.0 * k2 + 6.0, Color(accent, 0.55 * k2))
	sparks(b_add, contact, a, 0.55, 60, 51, 300.0, PALE, accent, PI, 1.6, 160.0, 1.8)
	shards(b_front, contact, a, 0.6, 8, 53, 120.0, 2.2, Color(accent.lightened(0.4), 1.0), Color(accent.darkened(0.5), 1.0), 200.0, PI, 1.4)
	show_ring(rings[0], contact + Vector2(0, 26), a, 0.45, 60.0, 3.5, 6.5, 0.02)
	refract_wave(contact, a, 0.45, 140.0, 6.0, 0.03)
	view["shake"] += hit_shake(a, 8.0, 80.0, 0.35)
	set_post({"flash": 0.08 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08))})

## 三日月の剣圧（縦に長く、前＝左へふくらむ。紫の闇の尾・属性の色・白い芯の3重）
func _crescent(c: Vector2, on: float, half_h: float, t: float, wake_on: bool = true, thick: float = 1.0) -> void:
	for r in [wave_wake, wave, wave_core]:
		(r as RBMHeroFxRibbon).visible = on > 0.01
	if on <= 0.01:
		return
	var pts := PackedVector2Array()
	var pts_w := PackedVector2Array()
	for k in range(22):
		var v := float(k) / 21.0 * 2.0 - 1.0
		var bulge := (1.0 - v * v)
		pts.append(c + Vector2(-0.4 * half_h * bulge, v * half_h))
		pts_w.append(c + Vector2(-0.4 * half_h * bulge + 0.5 * half_h * (1.0 - absf(v)), v * half_h * 0.9))
	wave_core.set_path(pts, 3.6 * thick)
	wave.set_path(pts, 9.0 * thick)
	sp(wave_core, {"head": 1.0, "tail": 0.0, "flow": t * 3.0, "fade": on})
	sp(wave, {"head": 1.0, "tail": 0.0, "flow": t * 3.0, "fade": 0.9 * on})
	wave_wake.visible = wake_on and on > 0.01
	if wave_wake.visible:
		wave_wake.set_path(pts_w, 18.0 * thick)
		sp(wave_wake, {"head": 1.0, "tail": 0.0, "flow": t * 2.0, "fade": 0.7 * on})
	# 三日月のまわりの光と、後ろへ流れる光の筋
	RBMHeroRooftop.glow(b_add, c + Vector2(-0.3 * half_h, 0), half_h * 0.9, Color(accent, 0.22 * on))
	for k in range(7):
		var v2 := (float(k) / 6.0 * 2.0 - 1.0) * 0.85
		var p0 := c + Vector2(-0.4 * half_h * (1.0 - v2 * v2), v2 * half_h)
		b_add.streak(p0 + Vector2(30.0 + 20.0 * RBMHeroFx.r(k, 5), 0), p0, 1.4 * thick, Color(PALE, 0.0), Color(PALE, 0.7 * on))

## 全体: 水平に掲げた剣に力が集まる → 突き出すように薙ぐ（剣の前に大きな弧）→ 巨大な三日月の剣圧が地面を裂きながら四人を薙ぐ
## → 通るたびに一人ずつ斬れる（光・火花）→ 四人の真ん中で大きな衝撃（輪・屈折・揺れ）
func _aoe(t: float) -> void:
	_charge(foot + BLADE_FLAT[0], foot + BLADE_FLAT[1], t, 0.12, 0.5, aoe_swing - 0.02)
	var s := t - aoe_swing
	# 薙ぎの軌跡（剣の前で、上から下へ大きく）
	swing_arc.visible = s >= 0.0 and s < 0.32
	if swing_arc.visible:
		var pts := PackedVector2Array()
		for k in range(20):
			var ang := lerpf(-1.2, 1.2, float(k) / 19.0)
			pts.append(foot + Vector2(-10, -40) + Vector2(-cos(ang) * 60.0, sin(ang) * 42.0))
		swing_arc.set_path(pts, 5.5)
		sp(swing_arc, {"head": RBMHeroFx.ramp(s, 0.0, 0.06), "tail": RBMHeroFx.ramp(s, 0.07, 0.3), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(s, 0.2, 0.32)})
	# 巨大な三日月の剣圧: 四人の真ん中を impact の時刻に通る（速さ一定）
	var cen := _party_center()
	var speed := 480.0
	var x := cen.x - (t - hit_time) * speed
	var start_x := foot.x - 46.0
	var grow := RBMHeroFx.ramp(t, aoe_swing + 0.06, aoe_swing + 0.18)
	# 四人を通り過ぎて左へ抜けながら消える（x が cen.x-150 から cen.x-210 へ減る間に 1→0）
	var on := grow * clampf((x - (cen.x - 210.0)) / 60.0, 0.0, 1.0)
	if x > start_x:
		x = start_x
	var c := Vector2(x, cen.y - 30.0)
	_crescent(c, on, 70.0 * (0.4 + 0.6 * grow), t, true, 1.6)
	if on > 0.0:
		# 地面を裂きながら進む: 先端の下に土煙と火花、通った跡に光る裂け目
		var g := Vector2(x, cen.y + 30.0)
		RBMHeroRooftop.glow(b_back, g + Vector2(6, -2), 10.0, Color(0.6, 0.55, 0.65, 0.4 * on))
		sparks(b_add, g, fmod(t * 8.0, 0.25), 0.25, 14, 61 + int(t * 8.0), 180.0, PALE, accent, -PI * 0.3, 1.0, 200.0, 1.3)
		var x0 := minf(start_x, x + 6.0)
		b_back_add.line(Vector2(start_x, g.y + 1), Vector2(x0, g.y + 1), 1.2, Color(accent, 0.6 * on), Color(accent, 0.6 * on))
		b_back.line(Vector2(start_x, g.y + 2), Vector2(x0, g.y + 2), 2.0, Color(0.06, 0.02, 0.1, 0.7 * on), Color(0.06, 0.02, 0.1, 0.7 * on))
	# 一人ずつ斬れる（剣圧が通った時）
	for i in range(mini(targets.size(), 4)):
		if not present[i]:
			continue
		var chest: Vector2 = Vector2(targets[i]) + Vector2(0, -26)
		var pass_t := hit_time + (cen.x - chest.x) / speed
		var pa := t - pass_t
		if pa < 0.0 or pa > 0.6:
			if i + 2 < cuts.size():
				(cuts[i + 2] as RBMHeroFxRibbon).visible = false
			continue
		var r: RBMHeroFxRibbon = cuts[i + 2]
		r.visible = pa < 0.4
		if r.visible:
			r.set_path(RBMHeroFx.bow(chest + Vector2(4, -26), chest + Vector2(-4, 24), 7.0, 14), 3.0)
			sp(r, {"head": RBMHeroFx.ramp(pa, 0.0, 0.04), "tail": RBMHeroFx.ramp(pa, 0.08, 0.38), "flow": t * 2.0, "fade": 1.0 - RBMHeroFx.ramp(pa, 0.22, 0.4)})
		if pa < 0.08:
			var k3 := 1.0 - pa / 0.08
			RBMHeroRooftop.glow(b_add, chest, 10.0 * k3 + 4.0, Color(PALE, 0.8 * k3))
			RBMHeroRooftop.glow(b_add, chest, 20.0 * k3 + 5.0, Color(accent, 0.5 * k3))
		sparks(b_add, chest, pa, 0.5, 40, 71 + i, 260.0, PALE, accent, PI, 1.8, 160.0, 1.6)
	var a := t - hit_time
	if a < 0.0:
		return
	show_ring(rings[0], cen + Vector2(0, 8), a, 0.55, 150.0, 4.5, 6.0, 0.03)
	show_ring(rings[1], cen + Vector2(0, 8), a - 0.07, 0.5, 110.0, 3.0, 6.0, 0.0)
	refract_wave(cen + Vector2(0, -20), a, 0.6, 260.0, 5.0, 0.035)
	cracks.visible = a < 1.4
	if cracks.visible:
		sp(cracks, {"center": w(cen + Vector2(0, 10)), "reveal": 20.0 + 70.0 * RBMHeroFx.burst(a, 7.0), "fade": 1.0 - RBMHeroFx.ramp(a, 0.8, 1.4), "glow": 0.2 + 0.4 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.8))})
	view["shake"] += hit_shake(a, 10.0, 80.0, 0.4)
	set_post({"flash": 0.1 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.08))})

func _party_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for i in range(mini(targets.size(), 4)):
		if present[i]:
			c += Vector2(targets[i])
			n += 1
	return c / float(n) if n > 0 else Vector2(175, 225)

## 支援: 剣を立てて祈る → 剣先に光が集まる → 光の柱が降りて騎士を包む（impact）→ 足元に光の輪、光の粒が立ちのぼる
func _support(t: float) -> void:
	var tip := foot + BLADE_TIP_UP
	var gather := RBMHeroFx.env(t, 0.25, 0.6, hit_time, hit_time + 0.1)
	if gather > 0.0:
		RBMHeroRooftop.glow(b_add, tip, 4.0 + 5.0 * gather * (0.85 + 0.15 * sin(t * 24.0)), Color(PALE, 0.85 * gather))
		RBMHeroRooftop.glow(b_add, tip, 14.0 * gather, Color(accent, 0.4 * gather))
		inward(b_add, tip, t - 0.25, 16, 81, 60.0, 3.0, 1.2, Color(accent, 1.0), gather, 2.0)
	var a := t - hit_time
	var pf := RBMHeroFx.env(t, hit_time - 0.08, hit_time, hit_time + 0.5, hit_time + 1.2)
	pillar.visible = pf > 0.0
	if pillar.visible:
		pillar.position = Vector2(foot.x - 60, -100)
		pillar.size = Vector2(120, foot.y + 104)
		sp(pillar, {"width": lerpf(.1, .5, RBMHeroFx.burst(maxf(a, 0.0), 10.0)) * (1.0 - .4 * RBMHeroFx.ramp(a, .4, 1.2)), "flow": t * 2.0, "fade": pf * 0.85, "flare": .6})
	var aura := RBMHeroFx.env(t, hit_time, hit_time + 0.2, 1.9, 2.6)
	if aura > 0.0:
		RBMHeroRooftop.glow(b_back_add, foot + Vector2(0, -40), 40.0, Color(accent, 0.16 * aura))
		embers(b_add, Rect2(foot.x - 30, foot.y - 90, 60, 90), t, 30, 91, 50.0, Color(accent, 1.0), aura, 1.6, 8.0)
	if a >= 0.0:
		show_ring(rings[0], foot, a, 0.6, 110.0, 5.0, 6.0, 0.02)
		show_ring(rings[1], foot, a - 0.1, 0.6, 80.0, 3.5, 6.0, 0.0)
		if a < 0.12:
			RBMHeroRooftop.glow(b_add, foot + Vector2(0, -44), 30.0 + 12.0 * (1.0 - a / 0.12), Color(accent, 0.45 * (1.0 - a / 0.12)))
		sparks(b_add, foot + Vector2(0, -44), a, 0.7, 40, 93, 200.0, PALE, accent, -PI * 0.5, PI * 1.4, 80.0, 1.6)
		view["hero"]["lit"] = 0.0
