extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/post_all.gd でユーザーが採用した内容をそのまま移した。
## 噴界炉の巨神・覚醒後全体「噴界の大火砕流」（2026-11-14 新しい技。指摘「安っぽい素材を重ねて動かしているだけ。聖獣やヒーローを参考に新しくいい技を」）:
## 大きな見せ場を1つ（足元の火口からの大噴火）に絞り、段階を踏んで盛り上げる:
## 炉を抱えて溜める（溶岩の色のオーラが大きく燃え上がる・地面が震える）→ 炉を開くと熱の波が地面を走り、四人の足元が下から赤く光る
## → 四人の足元に火口が開き、渦を巻く溶岩がのぞく → 一人ずつの下から炎が噴く（当たり）
## → 火口から巨大な噴火の柱が四人を突き抜けて天へ（最後の一撃: 白い閃光・衝撃波・溶岩の塊が四方へ）
## → 柱が崩れて火砕流（灰と炎の壁）が地面を左右へなぎ払う → 灰が降り、火口が冷えていく。

const T := {"charge": 0.35, "open_furnace": 1.20, "glow": 1.30, "open": 1.80, "jets": [2.10, 2.26, 2.42, 2.58], "erupt": 2.95, "surge": 3.45, "settle": 4.20, "end": 6.30}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
const ASH := Color(0.55, 0.5, 0.48)

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var caldera: ColorRect
var column: ColorRect
var spurts: Array = []
var surge: ColorRect
var blast: ColorRect
var rings: Array = []
var final_share := 0.4

func duration() -> float:
	return T.end

func impact() -> float:
	return T.erupt

func hits() -> Array:
	var out := []
	for i in range(4):
		out.append([float(T.jets[i]), i])
	return out

func stops() -> Array:
	return [[T.erupt, 0.14]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.charge, 2], [T.open_furnace, 3], [T.settle, 4]]

func _center() -> Vector2:
	var c := Vector2.ZERO
	for i in range(4):
		c += Vector2(targets[i])
	return c * 0.25

func _build() -> void:
	b_back = batch(back, false)
	caldera = caldera_quad(back, {"seed": 5.0})
	surge = blast_quad(back, LAVA, SMOKE, {"amp": 26., "k": .06, "seed": 3.1, "glow": .4, "glow_col": Vector3(1., .45, .15), "glow_r": 30.})
	surge.set_meta("blast_reach", Vector3.ZERO)
	blast = blast_quad(back, LAVA, LAVA, {"amp": 40., "k": .046, "seed": 3.8, "glow": .9, "glow_col": Vector3(1., .5, .15), "glow_r": 56.})
	blast.set_meta("blast_reach", Vector3.ZERO)
	for i in range(4):
		spurts.append(eruption_quad(front, {"seed": 20.0 + i, "smoke": 0.35}))
	column = eruption_quad(front, {"seed": 4.0, "smoke": 0.55})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 1.5 + i * 2.6, "glow": .45, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

## 火砕流の玉（火口から左右へ地面を這って広がる灰と炎の壁。下の前の方は炎、上は灰）
func surge_blobs(c: Vector2, age: float) -> PackedVector4Array:
	var out := PackedVector4Array()
	for k in range(40):
		var side := -1.0 if k % 2 == 0 else 1.0
		var r1 := RBMHeroFx.r(k, 101)
		var r2 := RBMHeroFx.r(k, 103)
		var dist := (40.0 + 380.0 * (1.0 - exp(-2.2 * age))) * (0.35 + 0.65 * r1)
		var up := 12.0 + 70.0 * r2 * (0.4 + 0.6 * minf(1.0, age * 1.5))
		var p := c + Vector2(side * dist * (1.0 if side > 0.0 else 1.3), -up + 6.0)
		var rad := (16.0 + 26.0 * r2) * (0.5 + 0.7 * minf(1.0, age * 2.0))
		# 前の下の方は炎（正）、上と後ろは灰（負）
		var front_k := r1 * (1.0 - r2)
		var heat := (0.9 - 0.6 * minf(1.0, age)) if front_k > 0.45 else -(0.5 + 0.3 * r2)
		out.append(Vector4(p.x - RBMHeroFx.WORLD.position.x, p.y - RBMHeroFx.WORLD.position.y, rad, heat))
	return out

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var center := _center()
	var ground := center + Vector2(0, 6)
	var core := at("mark", 3) if t >= T.open_furnace else at("center", 2, -14, 8)
	var ch := RBMHeroFx.ramp(t, T.charge, T.open_furnace)
	var ae := t - T.erupt
	var as_ := t - T.surge
	var cool := RBMHeroFx.ramp(ae, 1.0, 3.0)
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [float(T.charge) + 0.3, 0.5], [T.open, 0.65], [T.erupt, 0.72], [float(T.erupt) + 0.08, 0.25], [T.surge, 0.5], [T.end, 0.2]])
	view["dim_col"] = Color(0.06, 0.015, 0.0)
	# 溜め: 溶岩の色のオーラが大きく燃え上がる・地面が震える
	view["hero"]["sun_aura"] = 1.0 + 0.9 * ch * (1.0 - RBMHeroFx.ramp(t, T.open_furnace, float(T.open_furnace) + 0.5))
	view["hero"]["lit"] = 0.3 + 0.4 * ch * (1.0 - RBMHeroFx.ramp(t, T.open_furnace, float(T.open_furnace) + 0.4))
	view["hero"]["lit_col"] = EMBER
	disc(b_add, core, 3.0 + 6.0 * ch, Color(WHITE, 0.6 * ch * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.3))))
	inward(b_add, core, t, 70, 3, 6.0, 140.0, 1.6, HOT, ch * (1.0 - RBMHeroFx.ramp(t, T.open_furnace, float(T.open_furnace) + 0.1)), 2.2)
	view["shake"] += Vector2(sin(t * 29.0), cos(t * 21.0) * 0.6) * (1.0 * ch * (1.0 - RBMHeroFx.ramp(t, T.open_furnace, float(T.open_furnace) + 0.2)) + 1.6 * RBMHeroFx.env(t, T.open, float(T.open) + 0.3, T.erupt, float(T.erupt) + 0.05))
	# 炉を開く: 熱の波が地面を走って四人の足元へ
	var of := t - T.open_furnace
	if of >= 0.0 and of < 0.6:
		var head := HOME.lerp(ground, RBMHeroFx.ramp(of, 0.0, 0.35))
		refract_wave(head, of, 0.6, 60.0, 6.0, 0.04)
		embers(b_add, Rect2(head.x - 30, head.y - 16, 60, 16), t, 24, 5, 60.0, EMBER, 1.0 - of / 0.6, 2.0, 6.0)
		disc(b_add, core, 18.0 * (1.0 - of / 0.6), Color(HOT, 0.5 * (1.0 - of / 0.6)))
		view["shake"] += hit_shake(of, 8.0, 70.0, 0.3)
	# 足元が下から赤く光る → 火口が開く → 噴火の後に冷えていく
	var glow_k := RBMHeroFx.ramp(t, T.glow, float(T.glow) + 0.4)
	var open := RBMHeroFx.ramp(t, T.open, float(T.open) + 0.45)
	if glow_k > 0.0:
		show_caldera(caldera, ground, 104.0 * (0.8 + 0.2 * open), {"squash": 0.3, "open": open, "heat": clampf(0.7 + 0.5 * RBMHeroFx.ramp(t, T.open, T.erupt) - 0.6 * cool, 0.0, 1.2) * glow_k, "flow": t, "fade": 1.0 - RBMHeroFx.ramp(t, T.end - 0.5, T.end)})
	else:
		caldera.visible = false
	if open > 0.0 and ae < 0.0:
		lava_drops(b_front, ground + Vector2(-60, 0), fmod(t * 1.2, 0.5), 0.5, 4, 11, 130.0, 2.0, -PI * 0.5, 0.8, 320.0)
		lava_drops(b_front, ground + Vector2(70, 2), fmod(t * 1.2 + 0.25, 0.5), 0.5, 4, 13, 130.0, 2.0, -PI * 0.5, 0.8, 320.0)
	# 一人ずつの下から炎が噴く（当たり）
	for i in range(4):
		var q: ColorRect = spurts[i]
		if not present[i]:
			q.visible = false
			continue
		var jt := t - float(T.jets[i])
		var foot: Vector2 = targets[i]
		var g := RBMHeroFx.ramp(jt, 0.0, 0.08) * (1.0 - RBMHeroFx.ramp(jt, 0.3, 0.55))
		show_eruption(q, foot + Vector2(0, 3), 15.0, 110.0, g, {"flow": t * 1.5 + i, "heat": 1.0})
		if jt >= 0.0 and jt < 0.6:
			lava_drops(b_front, foot, jt, 0.6, 12, 31 + i, 280.0, 2.6, -PI * 0.5, PI * 0.9, 420.0)
			view["shake"] += hit_shake(jt, 5.0, 70.0, 0.22)
	ally_hits(t, hits(), 0.9)
	# 大噴火: 巨大な噴火の柱が四人を突き抜けて天へ
	if t >= T.open and ae < 0.0:
		inward(b_add, ground + Vector2(0, -20), t, 70, 41, 8.0, 200.0, 1.8, HOT, RBMHeroFx.ramp(t, float(T.jets[3]), T.erupt), 2.6)
	var cg := RBMHeroFx.ramp(ae, 0.0, 0.1)
	var cdown := RBMHeroFx.ramp(as_, -0.05, 0.4)
	if ae >= 0.0 and cdown < 1.0:
		show_eruption(column, ground + Vector2(0, 2), 64.0 * (1.0 - 0.5 * cdown), 440.0, cg, {"flow": t * 1.3, "heat": 1.0, "smoke": 0.45 + 0.45 * cdown, "fade": 1.0 - cdown})
	else:
		column.visible = false
	var bf := 1.0 - RBMHeroFx.ramp(ae, 0.35, 0.8)
	blast.visible = ae >= 0.0 and bf > 0.0
	if blast.visible:
		var c := ground + Vector2(0, -40)
		show_blast(blast, blobs(c, ae, 32, 29, 320.0, 140.0, 80.0, 100.0, .6, 0.0, 6.6), ae, {"flow": ae * .22, "cool": .05 + RBMHeroFx.ramp(ae, .2, 1.0) * .25, "erode": RBMHeroFx.ramp(ae, .25, .8), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .6, "amp": 38.0, "radial_heat": .42, "heat_center": w(c), "heat_radius": 360.0 * RBMHeroFx.burst(ae, 6.6), "erode_radial": 190.0, "tone_cap": .95})
		refract_wave(ground, ae, 0.9, 640.0, 4.8, 0.04)
	for i in range(3):
		show_ring(rings[i], ground, ae - i * 0.08, 0.8, 620.0 - i * 100.0, 9.0 - i * 2.0, 5.0, 0.035 * float(i == 0))
	if ae >= 0.0:
		if ae < 0.14:
			set_post({"flash": 0.3 * (1.0 - ae / 0.14), "flash_col": Vector3(1.0, 0.85, 0.6)})
		lava_drops(b_front, ground + Vector2(0, -80), ae, 1.4, 50, 61, 640.0, 3.8, -PI * 0.5, PI * 1.5, 440.0)
		rocks(b_front, ground, ae, 1.4, 30, 63, 760.0, 7.0, 16.0)
		ally_light(RBMHeroFx.env(ae, 0.0, 0.05, 0.4, 1.0), ORANGE, 0.0)
		for i in range(4):
			view["allies"][i]["force"] = maxf(float(view["allies"][i].get("force", 0.0)), RBMHeroFx.env(ae, 0.0, 0.05, 0.25, 0.7) * 1.4)
		for k in range(10):
			var to := Vector2(30 + k * 58 + RBMHeroFx.r(k, 71) * 30.0, 170 + RBMHeroFx.r(k, 72) * 110.0)
			var bt := ae - 0.2 - k * 0.07
			lava_bomb(b_front, b_add, ground + Vector2(0, -230), to, bt, 0.75, 3.0 + RBMHeroFx.r(k, 73) * 2.0, 50.0)
			if bt >= 0.75 and bt < 1.15:
				lava_drops(b_front, to, bt - 0.75, 0.4, 8, 75 + k, 160.0, 2.0, -PI * 0.5, PI * 1.1, 360.0)
	view["shake"] += hit_shake(ae, 22.0, 55.0, 0.8)
	# 火砕流: 灰と炎の壁が地面を左右へなぎ払う
	var sf := 1.0 - RBMHeroFx.ramp(as_, 1.1, 1.8)
	surge.visible = as_ >= 0.0 and sf > 0.0
	if surge.visible:
		show_blast(surge, surge_blobs(ground, as_), as_, {"flow": as_ * .3, "cool": .1 + .3 * minf(1.0, as_), "erode": RBMHeroFx.ramp(as_, .6, 1.8), "fade": sf, "erode_noise": .5, "tone_cap": .9})
		view["shake"] += Vector2(sin(t * 41.0), cos(t * 33.0) * 0.5) * 3.0 * (1.0 - RBMHeroFx.ramp(as_, 0.0, 1.0))
	# 灰が降る
	embers(b_add, Rect2(-20, 40, 680, 300), t, 140, 47, -60.0, ASH, RBMHeroFx.env(as_, 0.3, 0.9, 2.2, 2.8) * 0.8, 2.0, 18.0)
	embers(b_add, Rect2(-20, 100, 680, 250), t, 120, 49, 200.0, ORANGE, RBMHeroFx.env(ae, 0.3, 0.6, 2.2, 2.8), 2.2, 16.0)
	set_post({"vig": 0.45 * ch * (1.0 - RBMHeroFx.ramp(ae, 0.0, 0.5)) + 0.15, "vig_col": Vector3(.06, .01, .0), "vig_r": .26})
	b_back.commit(); b_add.commit(); b_front.commit()
