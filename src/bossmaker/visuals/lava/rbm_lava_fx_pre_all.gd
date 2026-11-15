extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/pre_all.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人・覚醒前全体「炉門開放」（2026-11-14 作り直し2。ユーザー案は同じ: 溶岩を腹から出してパーティー側の上空に集める → 垂れる → 一気に落とす。
## 指摘「溶岩の形が集合体すぎて気持ち悪い・動きがださい」→ 網目の模様をやめ、溶けた液体の溶岩（shaders/molten.gdshader）で描く）:
## 構え → 炉を抱えて溜める（炉が脈打つ）→ 腹の炉門を開くと、太い溶岩の流れが噴き出して弧を描き、四人の上空へ流れ込んで、うねる大きな塊になる
## → 塊の底が一人ずつの上でふくらみ、首が細く伸びてちぎれ、溶岩が落ちる（当たり。跳ねる飛沫と小さな溜まり）
## → 塊が崩れ落ちる（下から先に落ち、引き伸ばされた滝のように）→ 地面で大きく跳ねて広がる（最後の一撃）→ 冷えていく → 構えへ。

const T := {"charge": 0.30, "release": 1.05, "gather_end": 2.00, "drips": [2.12, 2.30, 2.48, 2.66], "drop": 2.92, "impact": 3.16, "settle": 3.70, "end": 4.80}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
## 流れの1粒が腹から塊まで飛ぶ秒
const TRAVEL := 0.42
## 塊の大きさ
const MASS_R := 32.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var stream: ColorRect
var mass: ColorRect
var drops: ColorRect
var puddles: ColorRect
var big_puddle: ColorRect
var blast: ColorRect
var smoke: ColorRect
var rings: Array = []
var final_share := 0.45

func duration() -> float:
	return T.end

func impact() -> float:
	return T.impact

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.drips[i]) + 0.14, i])
	return out

func stops() -> Array:
	return [[T.impact, 0.12]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.release, 3], [T.settle, 1]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25

func gather_point() -> Vector2:
	return _center() + Vector2(6, -120)

func _build() -> void:
	b_back = batch(back, false)
	big_puddle = molten_quad(back, {"seed": 7.0, "squash": 0.3, "glow": 0.6})
	puddles = molten_quad(back, {"seed": 8.0, "squash": 0.32, "glow": 0.5})
	smoke = blast_quad(back, SMOKE, SMOKE, {"amp": 26., "k": .06, "seed": 8.1, "glow": 0.0, "glow_r": 20.})
	blast = blast_quad(back, LAVA, LAVA, {"amp": 32., "k": .05, "seed": 9.4, "glow": .8, "glow_col": Vector3(1., .5, .15), "glow_r": 46.})
	blast.set_meta("blast_reach", Vector3.ZERO)
	stream = molten_quad(front, {"seed": 3.0, "glow": 0.6})
	mass = molten_quad(front, {"seed": 5.0, "glow": 0.7})
	drops = molten_quad(front, {"seed": 6.0, "glow": 0.5})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 2.0 + i * 3.0, "glow": .4, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

## 腹から塊への弧（u: 0〜1）
func arc_at(core: Vector2, g: Vector2, u: float) -> Vector2:
	var ctrl := Vector2((core.x + g.x) * 0.5 + 40.0, minf(core.y, g.y) - 70.0)
	return core.lerp(ctrl, u).lerp(ctrl.lerp(g, u), u)

## 塊の丸（うねる。落ちる時は下から先に落ちる）
func mass_balls(t: float, g: Vector2, grow: float) -> Array:
	var out: Array = []
	if grow <= 0.0:
		return out
	var fall_t := t - T.drop
	# いびつにうねる塊（真ん丸の火の玉にしない: 外側の丸を大きさも距離もばらばらに）
	var pts: Array = [[Vector2.ZERO, MASS_R * 0.8]]
	for i in range(9):
		var a := float(i) * TAU / 9.0 + t * (0.6 if i % 2 == 0 else -0.45) + RBMHeroFx.r(i, 5) * 0.6
		var d := (26.0 + 14.0 * RBMHeroFx.r(i, 7)) * (1.0 + 0.22 * sin(t * 2.6 + i * 1.3))
		pts.append([Vector2(cos(a) * d * 1.35, sin(a) * d * 0.75), (10.0 + 9.0 * RBMHeroFx.r(i, 9)) * (0.8 + 0.25 * sin(t * 2.1 + i * 1.7))])
	pts.append([Vector2(-12, 20), 15.0])
	pts.append([Vector2(14, 18), 13.0])
	pts.append([Vector2(2, 26), 9.0 + 3.0 * sin(t * 4.0)])
	for e in pts:
		var off: Vector2 = e[0]
		var r: float = float(e[1]) * grow
		var p := g + off * grow
		if fall_t > 0.0:
			# 下の丸から先に落ちる（引き伸ばされた滝のように）
			var delay := clampf((off.y * -1.0 + 30.0) / 60.0, 0.0, 1.0) * 0.1
			var ft := maxf(0.0, fall_t - delay)
			p.y += 0.5 * 6200.0 * ft * ft
			r *= 1.0 - 0.25 * clampf(ft / 0.2, 0.0, 1.0)
		out.append(Vector4(p.x, p.y, r, 0.85 - 0.3 * clampf(off.length() / 40.0, 0.0, 1.0)))
	return out

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var core := at("center", 3, -14, 8) if t >= T.release else at("center", 2, -14, 8)
	var center := _center()
	var g := gather_point()
	var ch := RBMHeroFx.ramp(t, T.charge, T.release)
	var a := t - T.impact
	var cool := RBMHeroFx.ramp(a, 0.5, 1.5)
	var endf := 1.0 - RBMHeroFx.ramp(t, T.end - 0.4, T.end)
	view["dim"] = 0.3 * ch + 0.25 * RBMHeroFx.env(t, T.release, T.release + 0.3, T.impact, T.settle)
	view["dim_col"] = Color(0.06, 0.02, 0.01)
	# 炉が脈打つ
	disc(b_add, core, 3.0 + 5.0 * ch, Color(WHITE, 0.5 * ch * (0.6 + 0.4 * sin(t * 14.0)) * (1.0 - RBMHeroFx.ramp(t, T.release, T.release + 0.3))))
	embers(b_add, Rect2(HOME.x - 50, HOME.y - 70, 100, 70), t, 40, 3, 90.0, ORANGE, ch * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.3)), 2.0, 6.0)
	if ch > 0.0 and t < T.release:
		inward(b_add, core, t, 40, 7, 4.0, 70.0, 1.2, HOT, ch, 2.2)
		refract_wave(core, fmod(t * 1.6, 0.6), 0.6, 60.0, 3.0, 0.012 * ch)
	view["hero"]["lit"] = 0.35 * ch + 0.3 * RBMHeroFx.env(t, T.release, T.release + 0.2, T.gather_end, T.gather_end + 0.3)
	view["hero"]["lit_col"] = EMBER
	# 噴き出す溶岩（大小の塊が次々と腹から塊へ飛ぶ。ところどころでくっつき、しぶきが散る）
	var sb: Array = []
	var s0 := float(T.release)
	var s1 := float(T.gather_end) - 0.15
	var k := 0
	while true:
		var st := s0 + k * 0.028
		if st > s1:
			break
		var u := (t - st) / TRAVEL
		if u >= 0.0 and u <= 1.0:
			# 大きさのばらばらな溶岩の塊が弧を描いて飛ぶ（つながった太い1本＝触手に見える形にしない）
			var u3 := u * (0.92 + 0.16 * RBMHeroFx.r(k, 13))
			var side := (RBMHeroFx.r(k, 15) - 0.5) * 16.0
			var p := arc_at(core, g, clampf(u3, 0.0, 1.0)) + Vector2(side * 0.6, side)
			var r := (3.5 + 6.5 * RBMHeroFx.r(k, 11)) * (1.0 - 0.3 * u)
			sb.append(Vector4(p.x, p.y, r, 1.0 - 0.3 * u))
		k += 1
	if sb.is_empty():
		stream.visible = false
	else:
		show_molten(stream, sb.slice(0, 32), {"flow": t * 2.0, "heat": 1.0})
	var ra := t - T.release
	if ra >= 0.0 and t < T.gather_end:
		lava_drops(b_front, core, fmod(ra, 0.35), 0.35, 6, 31, 160.0, 2.2, -PI * 0.7, 1.0, 320.0)
		view["shake"] += Vector2(sin(t * 40.0), 0.0) * 1.5
	# 上空の塊（うねる。流れが流れ込んで大きくなる）
	var grow := RBMHeroFx.ramp(t, T.release + TRAVEL * 0.8, T.gather_end)
	grow = 1.0 - pow(1.0 - grow, 2.0)
	var mb := mass_balls(t, g, grow) if t < T.impact else []
	# 一人ずつの上で底がふくらみ、首が伸びてちぎれる
	var db: Array = []
	for i in range(4):
		if not present[i]:
			continue
		var foot: Vector2 = targets[i]
		var chest := target_chest(i)
		var dt := t - float(T.drips[i])
		var top := g + Vector2(clampf(foot.x - g.x, -MASS_R * 1.1, MASS_R * 1.1), MASS_R * 0.75)
		if dt >= -0.16 and dt < 0.0:
			var sw := RBMHeroFx.ramp(dt, -0.16, 0.0)
			mb.append(Vector4(top.x, top.y + 8.0 * sw, 9.0 + 4.0 * sw, 0.8))
			mb.append(Vector4(top.x, top.y + 16.0 * sw, 6.0 * sw, 0.8))
		if dt >= 0.0 and dt < 0.14:
			var u2 := dt / 0.14
			var p2 := (top + Vector2(0, 16)).lerp(chest, u2 * u2)
			db.append(Vector4(p2.x, p2.y, 7.0, 0.9))
			db.append(Vector4(p2.x, p2.y - 9.0, 5.0, 0.85))
			if dt < 0.06:
				# ちぎれる首（細くなって消える）
				mb.append(Vector4(top.x, top.y + 12.0, 6.0 * (1.0 - dt / 0.06), 0.8))
		var ht := dt - 0.14
		if ht >= 0.0:
			lava_drops(b_front, chest + Vector2(0, 6), ht, 0.7, 12, 51 + i, 210.0, 2.6, -PI * 0.5, PI * 1.2, 380.0)
			sparks(b_add, chest, ht, 0.35, 16, 37 + i, 260.0, HOT, ORANGE, 0.0, TAU, 160.0, 1.4)
			view["shake"] += hit_shake(ht, 4.5, 70.0, 0.2)
	if mb.is_empty():
		mass.visible = false
	else:
		show_molten(mass, mb.slice(0, 32), {"flow": t * 1.4, "heat": 0.85})
	if db.is_empty():
		drops.visible = false
	else:
		show_molten(drops, db, {"flow": t * 2.0, "heat": 1.0})
	# 足元の小さな溜まり（垂れた溶岩）
	var pb: Array = []
	for i in range(4):
		if not present[i]:
			continue
		var ht2 := t - (float(T.drips[i]) + 0.14)
		if ht2 >= 0.0:
			var foot2: Vector2 = targets[i]
			var rr := 12.0 * RBMHeroFx.burst(ht2, 7.0)
			pb.append(Vector4(foot2.x, foot2.y + 2.0, rr, 0.6))
			pb.append(Vector4(foot2.x - rr * 0.9, foot2.y + 2.0, rr * 0.7, 0.5))
			pb.append(Vector4(foot2.x + rr * 0.9, foot2.y + 3.0, rr * 0.75, 0.5))
	if pb.is_empty():
		puddles.visible = false
	else:
		show_molten(puddles, pb, {"flow": t, "heat": 1.0 - 0.5 * cool, "fade": endf})
	var evs := []
	for i in range(4):
		evs.append([float(T.drips[i]) + 0.14, i])
	ally_hits(t, evs, 0.8)
	# 崩れ落ちて地面で大きく跳ねて広がる
	if a >= 0.0:
		var spread := RBMHeroFx.burst(a, 6.0)
		var bp: Array = []
		for k2 in range(10):
			var ang := float(k2) / 10.0 * TAU
			var d2 := 70.0 * spread * (0.7 + 0.3 * RBMHeroFx.r(k2, 21))
			bp.append(Vector4(center.x + cos(ang) * d2 * 1.4, center.y + 4.0 + sin(ang) * d2 * 0.25, 22.0 * (0.6 + 0.4 * spread), 0.75))
		bp.append(Vector4(center.x, center.y + 4.0, 30.0, 0.9))
		show_molten(big_puddle, bp, {"flow": t, "heat": 1.0 - 0.5 * cool, "fade": endf})
		lava_drops(b_front, center + Vector2(0, -10), a, 1.2, 56, 61, 580.0, 3.8, -PI * 0.5, PI * 1.3, 460.0)
		rocks(b_front, center, a, 1.0, 18, 41, 520.0, 5.0, 6.0)
		set_post({"flash": 0.14 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.12)), "flash_col": Vector3(1.0, 0.7, 0.4)})
		ally_light(RBMHeroFx.env(a, 0.0, 0.05, 0.35, 0.9), ORANGE, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(a, 0.0, 0.05, 0.15, 0.55) * 1.1)
	else:
		big_puddle.visible = false
	var bf := 1.0 - RBMHeroFx.ramp(a, 0.45, 0.85)
	blast.visible = a >= 0.0 and bf > 0.0
	if blast.visible:
		show_blast(blast, blobs(center + Vector2(0, -16), a, 28, 23, 260.0, 110.0, 70.0, 80.0, .6, 0.0, 7.0), a, {"flow": a * .22, "cool": .05 + RBMHeroFx.ramp(a, .2, 1.0) * .25, "erode": RBMHeroFx.ramp(a, .25, .85), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 30.0, "radial_heat": .4, "heat_center": w(center), "heat_radius": 260.0 * RBMHeroFx.burst(a, 7.0), "erode_radial": 150.0, "tone_cap": .95})
		refract_wave(center, a, 0.8, 520.0, 5.0, 0.035)
	var mf := 1.0 - RBMHeroFx.ramp(a, 0.9, 1.6)
	smoke.visible = a >= 0.25 and mf > 0.0
	if smoke.visible:
		show_blast(smoke, blobs(center + Vector2(0, -40), a, 18, 27, 180.0, 60.0, 36.0, 120.0, .2, 0.0, 3.0), a, {"flow": a * .15, "cool": 0.0, "erode": RBMHeroFx.ramp(a, .5, 1.5), "fade": mf * 0.5, "erode_noise": .6, "tone_cap": .6})
	for i in range(3):
		show_ring(rings[i], center, a - i * 0.08, 0.7, 420.0 - i * 60.0, 8.0 - i * 2.0, 5.0, 0.03 * float(i == 0))
	view["shake"] += hit_shake(a, 20.0, 60.0, 0.6)
	embers(b_add, Rect2(-20, 100, 680, 250), a, 120, 43, 240.0, ORANGE, RBMHeroFx.env(a, .3, .6, 1.2, 1.6), 2.2, 16.0)
	b_back.commit(); b_add.commit(); b_front.commit()
