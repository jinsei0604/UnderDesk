extends RBMLavaFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/lava/intro.gd でユーザーが採用した内容をそのまま移した。
## 熔鉱炉の番人・登場（2026-11-14 ユーザー案）: 画面の右上から溶岩の塊が火の尾を引いて降ってくる → 巨人の立ち位置に落ちて地面が揺れ、
## 塊がつぶれて溶岩の小山になる → 小山がだんだん震え始める（震えが強く・速く、割れ目の光が脈打ち、湯気と火の粉）
## → 一気に爆発（閃光・溶岩の大爆発・飛沫・岩・衝撃の輪）→ 爆炎の中から溶岩の巨人が両腕を広げて現れる（覚醒前全体の3枚目を借りる）→ 構えへ。

const T := {"fall0": 0.15, "land": 1.05, "tremble": 1.35, "boom": 3.05, "stance": 3.95, "end": 5.20}
const HOT := Color("#ffe08a")
const ORANGE := Color("#f07a20")
const EMBER := Color("#ff9a24")
const WHITE := Color("#fff6d8")
const STEAM := Color(0.62, 0.58, 0.56)
const REVEAL := 9
## 降り始め（画面の右上の外）と落ちる所（立ち位置の少し上 = 小山の中心）
const SKY := Vector2(700, -70)
const R_MASS := 30.0

var b_back: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var mass: ColorRect
var pool: ColorRect
var smoke: ColorRect
var trail: ColorRect
var steam: ColorRect
var blast: ColorRect
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.boom

func stops() -> Array:
	return [[T.land, 0.06], [T.boom, 0.12]]

func extra_poses() -> Dictionary:
	return {REVEAL: ["pre_all", 3]}

func pose_keys() -> Array:
	# 最後は待機の絵（0）。登場には技の絵の並びが無いので 1 は使わない
	return [[0.0, REVEAL], [T.stance, 0]]

func _build() -> void:
	b_back = batch(back, false)
	pool = molten_quad(back, {"seed": 4.0, "squash": 0.3, "glow": 0.6})
	trail = blast_quad(back, SMOKE, SMOKE, {"amp": 14., "k": .08, "seed": 1.7, "glow": 0.0, "glow_r": 16.})
	steam = blast_quad(back, SMOKE, SMOKE, {"amp": 18., "k": .07, "seed": 3.3, "glow": 0.0, "glow_r": 20.})
	smoke = blast_quad(back, SMOKE, SMOKE, {"amp": 28., "k": .06, "seed": 5.1, "glow": 0.0, "glow_r": 20.})
	blast = blast_quad(back, LAVA, LAVA, {"amp": 40., "k": .05, "seed": 8.4, "glow": .9, "glow_col": Vector3(1., .5, .15), "glow_r": 56.})
	blast.set_meta("blast_reach", Vector3.ZERO)
	mass = molten_quad(front, {"seed": 2.0, "glow": 0.75})
	for i in range(3):
		rings.append(ring_quad(front, RBMHeroFx.A4_AMBER, {"squash": .34, "breakup": .55, "seed": 2.0 + i * 2.5, "glow": .4, "glow_col": Vector3(1., .5, .15)}))
	b_front = batch(front, false)
	b_add = batch(front)

func _landing() -> Vector2:
	return HOME + Vector2(0, -R_MASS * 0.8)

## 落ちている塊の位置（右上から、少し弧を描いて加速しながら）
func _fall_pos(u: float) -> Vector2:
	var e := u * u
	return SKY.lerp(_landing(), e) + Vector2(0, -60.0 * sin(PI * u) * (1.0 - u))

## 溶岩の塊の形（金属球の集まり）。落下中は進む向きに伸びたしずく形、着地後はつぶれた小山。
func _mass_balls(t: float, shake_px: Vector2, pulse: float) -> Array:
	var out: Array = []
	if t < T.land:
		var u := RBMHeroFx.ramp(t, T.fall0, T.land)
		var p := _fall_pos(u)
		var back_dir := (_fall_pos(maxf(0.0, u - 0.05)) - p).normalized()
		if back_dir == Vector2.ZERO:
			back_dir = (SKY - _landing()).normalized()
		out.append(Vector4(p.x, p.y, R_MASS * 0.75, 1.0))
		for k in range(5):
			var q := p + back_dir * (10.0 + k * 8.0) + back_dir.orthogonal() * sin(t * 12.0 + k) * 2.0
			out.append(Vector4(q.x, q.y, R_MASS * (0.55 - k * 0.08), 1.0))
		return out
	var la := t - T.land
	# 着地: 一度つぶれて広がり、少し戻る（小山）
	var sq := 1.0 + 0.35 * exp(-la * 7.0) * cos(la * 18.0)
	var c := _landing() + shake_px
	var h := pulse
	out.append(Vector4(c.x, c.y + 6.0, R_MASS * 0.95 * sq, 0.7 + 0.3 * h))
	out.append(Vector4(c.x - 22.0 * sq, c.y + 16.0, R_MASS * 0.62, 0.6 + 0.3 * h))
	out.append(Vector4(c.x + 22.0 * sq, c.y + 16.0, R_MASS * 0.62, 0.6 + 0.3 * h))
	out.append(Vector4(c.x - 4.0, c.y - 16.0 / sq, R_MASS * 0.6, 0.8 + 0.2 * h))
	out.append(Vector4(c.x + 9.0, c.y - 8.0 / sq, R_MASS * 0.5, 0.8 + 0.2 * h))
	return out

func _step(t: float) -> void:
	b_back.reset(); b_add.reset(); b_front.reset()
	var la := t - T.land
	var ab := t - T.boom
	var ground := HOME + Vector2(2, 4)
	var tr := RBMHeroFx.ramp(t, T.tremble, T.boom)
	# 震え: だんだん強く・速く（1〜4px、2px の格子）
	var freq := 18.0 + 40.0 * tr
	var shake_px := Vector2(sin(t * freq) * (1.0 + 3.0 * tr * tr), cos(t * freq * 0.7) * tr).round() * float(tr > 0.0 and ab < 0.0)
	# 割れ目の光の脈（だんだん速く）
	var pulse := 0.5 + 0.5 * sin(t * (5.0 + 22.0 * tr * tr))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.35], [T.land, 0.4], [T.boom - 0.05, 0.6], [float(T.boom) + 0.05, 0.15], [T.stance, 0.3], [T.end, 0.0]])
	view["dim_col"] = Color(0.05, 0.01, 0.0)
	body["hidden"] = ab < 0.02
	# 塊: 落下 → 小山 → 震え → 爆発で消える
	# 破裂の直前は白熱してふくらむ（爆発の出始めの形を見せない。ヒットストップの間はこの白熱した塊が見える）
	if ab < 0.05:
		var swell := RBMHeroFx.ramp(t, T.boom - 0.25, float(T.boom) + 0.05)
		var mb := _mass_balls(t, shake_px, pulse * tr)
		if swell > 0.0:
			var c := _landing()
			for i in range(mb.size()):
				var bv: Vector4 = mb[i]
				mb[i] = Vector4(c.x + (bv.x - c.x) * (1.0 + 0.3 * swell), c.y + (bv.y - c.y) * (1.0 + 0.3 * swell) - 4.0 * swell, bv.z * (1.0 + 0.3 * swell), 1.0)
		show_molten(mass, mb, {"flow": t * 1.6, "heat": (0.9 if la < 0.0 else 0.55 + 0.45 * pulse * tr + 0.25 * exp(-la * 4.0)) + 0.6 * swell, "glow": 0.75 + 0.6 * swell})
	else:
		mass.visible = false
	# 落下中: 火の尾・煙・火の粉
	if la < 0.0 and t >= T.fall0:
		var u := RBMHeroFx.ramp(t, T.fall0, T.land)
		var p := _fall_pos(u)
		var tail := _fall_pos(maxf(0.0, u - 0.18))
		b_add.streak(tail, p, R_MASS * 1.3, Color(ORANGE, 0.0), Color(HOT, 0.55))
		b_add.streak(_fall_pos(maxf(0.0, u - 0.08)), p, R_MASS * 0.6, Color(EMBER, 0.0), Color(WHITE, 0.6))
		# 黒煙の尾（爆炎と同じ煙の質感。通った跡ほど太く薄く）
		var td := PackedVector4Array()
		for k in range(14):
			var ku := maxf(0.0, u - 0.025 * k - 0.03)
			var kp := _fall_pos(ku) + Vector2(RBMHeroFx.r(k, 3) - 0.5, RBMHeroFx.r(k, 4) - 0.5) * (6.0 + k * 1.5)
			td.append(Vector4(kp.x - RBMHeroFx.WORLD.position.x, kp.y - RBMHeroFx.WORLD.position.y, 8.0 + k * 1.6, 0.02))
		show_blast(trail, td, t, {"flow": t * .4, "cool": 0.0, "erode": 0.0, "fade": 0.75 * RBMHeroFx.ramp(t, T.fall0, float(T.fall0) + 0.15), "erode_noise": .5, "tone_cap": .6})
		embers(b_add, Rect2(p.x - 20, p.y - 30, 70, 50), t, 24, 5, -40.0, EMBER, 1.0, 2.0, 8.0)
		# 落ちる所の地面に影と赤い照り返しが濃くなる
		disc(b_back, ground, 38.0 * (0.3 + 0.7 * u), Color(0.06, 0.02, 0.0, 0.35 * u), 0.28)
	else:
		trail.visible = false
	# 着地: 揺れ・飛沫・岩・土煙・溶岩の溜まり
	if la >= 0.0:
		view["shake"] += hit_shake(la, 12.0, 60.0, 0.45)
		lava_drops(b_front, ground + Vector2(0, -10), la, 1.0, 26, 11, 380.0, 3.0, -PI * 0.5, PI * 1.2, 520.0)
		rocks(b_front, ground, la, 0.9, 16, 13, 360.0, 5.0, 4.0)
		var pb: Array = []
		for k in range(7):
			var ang := -PI + float(k) / 6.0 * PI
			var rr := (26.0 + 18.0 * RBMHeroFx.r(k, 21)) * RBMHeroFx.burst(la, 9.0)
			pb.append(Vector4(ground.x + cos(ang) * rr * 1.5, ground.y + 2.0 + absf(sin(ang)) * 3.0, 9.0 + 5.0 * RBMHeroFx.r(k, 22), 0.8))
		pb.append(Vector4(ground.x, ground.y + 2.0, 26.0, 0.9))
		show_molten(pool, pb, {"flow": t, "heat": (0.6 + 0.4 * pulse * tr) * (1.0 - 0.6 * RBMHeroFx.ramp(ab, 0.5, 1.8)), "fade": 1.0 - RBMHeroFx.ramp(t, T.end - 0.4, T.end)})
	else:
		pool.visible = false
	# 震える間: 割れ目から湯気・小さな噴き出し・火の粉・地面の揺れ
	if tr > 0.0 and ab < 0.0:
		view["shake"] += Vector2(sin(t * freq * 1.3), 0.0) * (0.5 + 2.5 * tr * tr)
		embers(b_add, Rect2(ground.x - 40, ground.y - 70, 80, 70), t, 30, 31, 70.0, EMBER, tr, 2.0, 6.0)
		for k in range(3):
			var st := fmod(t * (0.8 + tr * 1.6) + k / 3.0, 1.0)
			var sp_ := _landing() + Vector2(-16 + k * 16, -10 - k * 4) + shake_px
			lava_drops(b_front, sp_, st * 0.5, 0.5, 3, 41 + k, 90.0 + 80.0 * tr, 1.8, -PI * 0.5 + (k - 1) * 0.5, 0.6, 300.0)
		# 中から光が漏れる（体の内側から押し出されるように）
		inward(b_add, _landing(), t, 40, 33, 6.0, 90.0, 1.4, HOT, RBMHeroFx.ramp(t, T.boom - 0.6, T.boom), 2.6)
	var sa := la - 0.2
	var sf := 1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3)
	steam.visible = sa >= 0.0 and sf > 0.0
	if steam.visible:
		show_blast(steam, blobs(_landing() + Vector2(0, -50 - sa * 10.0), sa * 0.4, 14, 17, 60.0, 30.0, 18.0, 70.0, .1, 0.0, 2.0), sa, {"flow": sa * .15, "cool": 0.0, "erode": 0.0, "fade": sf * RBMHeroFx.ramp(sa, 0.0, 0.5) * (0.35 + 0.35 * tr), "erode_noise": .6, "tone_cap": .6})
	# 一気に爆発 → 巨人が現れる
	if ab >= 0.0:
		if ab < 0.12:
			set_post({"flash": 0.3 * (1.0 - ab / 0.12), "flash_col": Vector3(1.0, 0.85, 0.6)})
		lava_drops(b_front, _landing(), ab, 1.3, 50, 51, 640.0, 3.6, -PI * 0.5, PI * 1.6, 440.0)
		rocks(b_front, ground, ab, 1.3, 30, 53, 700.0, 7.0, 14.0)
		for k in range(10):
			var to := Vector2(40 + k * 60 + RBMHeroFx.r(k, 61) * 30.0, 180 + RBMHeroFx.r(k, 62) * 120.0)
			var bt := ab - 0.1 - k * 0.06
			lava_bomb(b_front, b_add, _landing() + Vector2(0, -30), to, bt, 0.75, 2.6 + RBMHeroFx.r(k, 63) * 2.4, 60.0)
			if bt >= 0.75 and bt < 1.15:
				lava_drops(b_front, to, bt - 0.75, 0.4, 6, 71 + k, 140.0, 1.8, -PI * 0.5, PI * 1.1, 360.0)
		view["hero"]["lit"] = 0.7 * (1.0 - RBMHeroFx.ramp(ab, 0.2, 1.2))
		view["hero"]["lit_col"] = EMBER
		if ab < 0.14:
			view["hero"]["flash"] = 0.85 * (1.0 - ab / 0.14)
			view["hero"]["flash_col"] = WHITE
	view["shake"] += hit_shake(ab, 22.0, 55.0, 0.8)
	# 爆炎は少し育った所から出す（出始めの小さな形は尖った星に見えるので見せない）
	var ba := ab + 0.08
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.35, 0.85)
	blast.visible = ab >= 0.03 and bf > 0.0
	if blast.visible:
		var c := _landing() + Vector2(0, -10)
		show_blast(blast, blobs(c, ba, 34, 31, 300.0, 140.0, 80.0, 110.0, .6, 0.0, 6.8), ba, {"flow": ba * .22, "cool": .05 + RBMHeroFx.ramp(ba, .2, 1.0) * .25, "erode": RBMHeroFx.ramp(ba, .25, .85), "fade": bf, "erode_noise": .4,
			"polar": 0.6, "detail": .6, "amp": 40.0, "radial_heat": .42, "heat_center": w(c), "heat_radius": 340.0 * RBMHeroFx.burst(ba, 6.8), "erode_radial": 180.0, "tone_cap": .95})
		refract_wave(c, ab, 0.8, 520.0, 5.0, 0.04)
	# 衝撃の輪は少し広がった所から出す（出始めの小さな輪が塊の根元に印のように見えた）
	for i in range(2):
		var ra := ab - i * 0.09
		if ra >= 0.03:
			show_ring(rings[i], ground, ra + 0.05, 0.8, 560.0 - i * 140.0, 9.0 - i * 3.0, 5.0, 0.035 * float(i == 0))
		else:
			(rings[i] as ColorRect).visible = false
	var mf := 1.0 - RBMHeroFx.ramp(ab, 0.8, 1.9)
	smoke.visible = ab >= 0.2 and mf > 0.0
	if smoke.visible:
		show_blast(smoke, blobs(ground + Vector2(0, -120), ab - 0.2, 22, 37, 220.0, 70.0, 46.0, 110.0, .2, 0.0, 2.4), ab - 0.2, {"flow": t * .15, "cool": 0.0, "erode": RBMHeroFx.ramp(ab, .8, 1.9), "fade": mf * 0.55, "erode_noise": .6, "tone_cap": .6})
	embers(b_add, Rect2(-20, 100, 680, 250), t, 100, 49, 200.0, ORANGE, RBMHeroFx.env(ab, 0.3, 0.6, 1.6, 2.1), 2.2, 16.0)
	set_post({"vig": 0.35 * (1.0 - RBMHeroFx.ramp(ab, 0.3, 1.5)) + 0.1, "vig_col": Vector3(.06, .01, .0), "vig_r": .28})
	b_back.commit(); b_add.commit(); b_front.commit()
