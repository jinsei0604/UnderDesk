extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/post_single.gd でユーザーが採用した内容をそのまま移した。
## 喪華のカラー女王・覚醒後単体「女王の鉤指」（2026-11-13 作り直し: 片手だけでなく両手で蔦を放ち、もっと派手に）:
## 構え → 両腕を振りかぶる（両手に蔦が絡み、喪色の光が集まる。相手の足元に暗い輪）
## → 鉤状の両手を払うと、前の手から低く3本、後ろの手から頭上を越えて3本、蔦が一斉に走る（地面からも2本突き上がる）
## → 蔦が相手に螺旋に巻き付く（当たり。後ろ側は相手の陰に、前側は手前に）→ 締め上げ、相手の上に喪色の花が咲いて弾ける（最後の一撃）
## → 蔦がほどけて両手へ戻る。優雅なまま、美しく恐ろしい。蔦は丸い節と縁取りの葉（尖ったトゲは使わない）。

const T := {"windup": 0.30, "lash": 0.82, "wrap": 0.98, "squeeze": 1.40, "follow": 1.48, "back": 2.05, "end": 2.70}
const MAUVE := Color("#8a2a4a")
const DEEP := Color("#4a0e26")
const PINK := Color("#e8a8c0")
const BLUSH := Color("#c06080")
const VIOLET := Color("#b060e0")
const PALE := Color("#fff0f4")
const VINE_D := Color("#1a0c12")
const VINE := Color("#3e2432")
const VINE_M := Color("#6a4252")
const VINE_L := Color("#8c6474")
const LEAF_D := Color("#1c1a14")
const LEAF := Color("#4a4a30")
const LEAF_L := Color("#7a7a50")
const DARKBLOOM := ["#0c0408", "#1e0814", "#3a0c22", "#5a1a32", "#8a2a4a", "#c06080", "#e8b8c8", "#fff0f4"]
const MOURN := ["#08020a", "#160412", "#26081c", "#3a0e28", "#521634", "#6e2244", "#8e3458", "#b45276"]
## 攻撃のポーズ（3枚目）の両手（絵の画素）。前の手は低く前へ、後ろの手は背の高い所
const HAND_F := Vector2(110, 120)
const HAND_B := Vector2(192, 106)
## 溜めのポーズ（2枚目）の両手
const WIND_A := Vector2(157, 74)
const WIND_B := Vector2(178, 110)

var b_back: RBMHeroFxBatch
var b_coil_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var burst: ColorRect
var flower: ColorRect
var rings: Array = []
var final_share := 0.5

func duration() -> float:
	return T.end

func impact() -> float:
	return T.squeeze

func hits() -> Array:
	return [[T.wrap, 3]]

func stops() -> Array:
	return [[T.wrap, 0.07], [T.squeeze, 0.13]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.windup, 2], [T.lash, 3], [T.follow, 4], [T.back, 1]]

func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"], [T.lash, Vector2.ZERO, "snap"], [T.lash + 0.04, Vector2(-16, 0), "out"], [T.back, Vector2(-16, 0), "snap"], [T.back + 0.3, Vector2.ZERO, "out"]]

func _build() -> void:
	b_back = batch(back, false)
	burst = blast_quad(back, DARKBLOOM, DARKBLOOM, {"amp": 26., "k": .07, "seed": 3.7, "glow": .6, "glow_col": Vector3(.8, .2, .45), "glow_r": 36.})
	b_coil_back = batch(back, false)
	flower = bloom_quad(front, MOURN, [], {"petals": 10.0, "seed": 5.0, "outline_col": Vector3(.05, .01, .03), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8)})
	for i in range(2):
		rings.append(ring_quad(front, ["#5a1a32", "#c06080", "#e8b8c8", "#fff0f4"], {"squash": .4, "breakup": .45, "seed": 5.0 + i * 2.1, "glow": .4, "glow_col": Vector3(.8, .2, .45)}))
	b_glow = batch(front)
	b_front = batch(front, false)
	b_add = batch(front)

## 蔦（p0 → p1 の二次曲線。ctrl で曲がる）。濃い縁・本体・照り・丸い節・縁取りの葉。grow まで伸びる。先の位置を返す。
func vine2(b: RBMHeroFxBatch, p0: Vector2, ctrl: Vector2, p1: Vector2, grow: float, width: float, seed_: int, leaves: bool = true) -> Vector2:
	if grow <= 0.0:
		return p0
	var steps := 22
	var last := int(ceil(steps * clampf(grow, 0.0, 1.0)))
	var pts: Array = []
	for i in range(last + 1):
		var u := minf(float(i) / steps, grow)
		var wob := sin(u * 9.0 + seed_) * 2.0 * (1.0 - u)
		var p := p0.lerp(ctrl, u).lerp(ctrl.lerp(p1, u), u)
		var d := (ctrl.lerp(p1, u) - p0.lerp(ctrl, u)).normalized()
		pts.append(p + d.orthogonal() * wob)
	for pass_i in range(3):
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var c: Vector2 = pts[i]
			var u := float(i) / steps
			var wv := width * (1.0 - 0.55 * u)
			match pass_i:
				0: b.line(a, c, wv + 2.0, VINE_D, VINE_D)
				1: b.line(a, c, wv, VINE, VINE_M)
				2: b.line(a + (c - a).orthogonal().normalized() * wv * 0.22, c + (c - a).orthogonal().normalized() * wv * 0.22, maxf(0.8, wv * 0.3), VINE_L, VINE_L)
	for i in range(2, pts.size(), 4):
		var p: Vector2 = pts[i]
		var u := float(i) / steps
		var wv := width * (1.0 - 0.55 * u)
		disc(b, p, wv * 0.62 + 0.8, VINE_D)
		disc(b, p + Vector2(-0.4, -0.4), wv * 0.42, VINE_M)
		if leaves and i % 8 == 6:
			var d: Vector2 = ((pts[i] as Vector2) - (pts[i - 1] as Vector2)).normalized()
			var side := 1.0 if (i / 8) % 2 == 0 else -1.0
			var ang := d.angle() + side * 1.0
			petal(b, p, ang, 9.0 + width, 5.0 + width * 0.4, LEAF_D, LEAF_D)
			petal(b, p + Vector2.from_angle(ang) * 0.8, ang, 7.0 + width, 3.4 + width * 0.3, LEAF, LEAF_L)
	var tip: Vector2 = pts[-1]
	disc(b, tip, width * 0.5 + 1.0, VINE_D)
	disc(b, tip, width * 0.35, VINE_L)
	return tip

## 相手に螺旋に巻き付く蔦（後ろ半分は b_back、前半分は b_front）。tight で締まる。
func coil(c: Vector2, height: float, rad: float, turns: float, grow: float, width: float, tight: float) -> void:
	if grow <= 0.0:
		return
	var n := 40
	var last := int(n * clampf(grow, 0.0, 1.0))
	var prev := Vector2.ZERO
	for i in range(last + 1):
		var u := float(i) / n
		var th := u * turns * TAU
		var r := rad * (1.0 - 0.35 * tight)
		var p := c + Vector2(cos(th) * r, -u * height + sin(th) * r * 0.35)
		if i > 0:
			var front_side := sin(th) > 0.0
			var bb := b_front if front_side else b_coil_back
			bb.line(prev, p, width + 2.0, VINE_D, VINE_D)
			bb.line(prev, p, width, VINE if front_side else VINE_D.lerp(VINE, 0.5), VINE_M if front_side else VINE)
			if front_side:
				bb.line(prev + Vector2(0, -width * 0.25), p + Vector2(0, -width * 0.25), maxf(0.8, width * 0.3), VINE_L, VINE_L)
		prev = p

func _step(t: float) -> void:
	b_back.reset(); b_coil_back.reset(); b_glow.reset(); b_add.reset(); b_front.reset()
	var hit := target_chest(3)
	var foot: Vector2 = targets[3]
	var a1 := t - T.wrap
	var a2 := t - T.squeeze
	var ch := RBMHeroFx.ramp(t, T.windup, T.lash)
	var ch_on := ch * (1.0 - RBMHeroFx.ramp(t, T.lash, T.lash + 0.08))
	view["dim"] = 0.3 * ch + 0.32 * RBMHeroFx.env(t, T.lash, T.wrap, T.squeeze + 0.2, T.back + 0.2)
	view["dim_col"] = Color(0.04, 0.0, 0.03)
	# 溜め: 両手に蔦が絡み、喪色の光が集まる。相手の足元に暗い輪
	if t < T.lash + 0.05:
		for hand in [px(WIND_A), px(WIND_B)]:
			for i in range(3):
				var ang := t * 2.4 + TAU * i / 3.0
				var p0: Vector2 = hand + Vector2(cos(ang) * 9.0, sin(ang) * 4.0)
				var p1: Vector2 = hand + Vector2(cos(ang + 2.0) * 13.0, -16.0 + sin(ang) * 4.0)
				vine2(b_front, p0, (p0 + p1) * 0.5 + Vector2(6, -4), p1, ch_on, 1.8, 3 + i, false)
			disc(b_glow, hand, 6.0 + 8.0 * ch, Color(BLUSH, 0.25 * ch_on))
			inward(b_add, hand, t, 30, 5, 3.0, 50.0, 1.2, PINK, ch_on, 2.2)
		petal_cloud(b_front, at("center", 2, 0, -14), t, 14, 7, 34.0, 4.0, DEEP, MAUVE, ch_on, "orbit", 0.5, Color(VINE_D, 0.8))
	var mark := RBMHeroFx.env(t, T.windup + 0.2, T.lash, T.squeeze + 0.2, T.back)
	if mark > 0.0:
		ring_line(b_coil_back, foot + Vector2(0, 1), 26.0 + 4.0 * sin(t * 6.0), 2.0, Color(MAUVE, 0.8 * mark), 0.35)
		ring_line(b_coil_back, foot + Vector2(0, 1), 18.0, 1.0, Color(BLUSH, 0.6 * mark), 0.35)
	view["hero"]["lit"] = 0.45 * ch_on
	view["hero"]["lit_col"] = BLUSH
	# 払い: 両手から蔦が一斉に走る（前の手から低く3本、後ろの手から頭上を越えて3本）、地面からも2本
	var grow := RBMHeroFx.ramp(t, T.lash, T.wrap) * (1.0 - RBMHeroFx.ramp(t, T.squeeze + 0.25, T.back))
	if t >= T.lash:
		var hf := px(HAND_F)
		var hb := px(HAND_B)
		for i in range(3):
			var tgt := hit + Vector2(8, -12 + i * 12)
			vine2(b_front, hf + Vector2(0, -2 + i * 2), hf.lerp(tgt, 0.5) + Vector2(0, 24.0 - i * 20.0), tgt, grow, 4.4 - i * 0.6, 9 + i)
			var tgt2 := hit + Vector2(4, -20 + i * 10)
			var top := hb.lerp(tgt2, 0.5) + Vector2(0, -70.0 - i * 16.0)
			vine2(b_front, hb + Vector2(0, -2 + i * 2), top, tgt2, RBMHeroFx.ramp(t, T.lash + 0.03, T.wrap + 0.02) * (1.0 - RBMHeroFx.ramp(t, T.squeeze + 0.25, T.back)), 4.0 - i * 0.5, 19 + i)
		# 地面から突き上がる2本
		var gg := RBMHeroFx.ramp(t, T.lash + 0.06, T.wrap) * (1.0 - RBMHeroFx.ramp(t, T.squeeze + 0.3, T.back))
		for s in [-1.0, 1.0]:
			var root: Vector2 = foot + Vector2(s * 26.0, 3)
			vine2(b_front, root, root + Vector2(s * 4.0, -30), hit + Vector2(s * 6.0, -18), gg, 5.0, 29 + int(s), true)
		if t < T.wrap:
			sparks(b_add, foot, t - T.lash, 0.3, 20, 41, 160.0, VINE_L, VINE, -PI * 0.5, PI * 0.8, 200.0, 1.6)
	# 螺旋に巻き付く → 締め上げ
	var wrap := RBMHeroFx.ramp(t, T.wrap - 0.04, T.wrap + 0.12) * (1.0 - RBMHeroFx.ramp(t, T.squeeze + 0.2, T.squeeze + 0.5))
	var tight := RBMHeroFx.ramp(t, T.squeeze - 0.24, T.squeeze)
	coil(foot + Vector2(0, -2), 46.0, 16.0, 3.2, wrap, 3.4, tight)
	if a1 >= 0.0 and a1 < 0.4:
		sparks(b_add, hit, a1, 0.35, 34, 11, 300.0, PINK, BLUSH, PI, PI * 1.4, 100.0, 1.6)
		petal_cloud(b_front, hit, a1, 18, 13, 70.0, 4.0, DEEP, PINK, 1.0, "burst", 0.45, Color(VINE_D, 0.8))
		view["shake"] += hit_shake(a1, 7.0, 90.0, 0.22)
	if tight > 0.0 and a2 < 0.0:
		disc(b_glow, hit, 16.0 * tight, Color(BLUSH, 0.16 * tight))
		inward(b_add, hit, t, 40, 15, 4.0, 60.0, 1.2, PINK, tight, 2.6)
	# 最後の一撃: 相手の上に喪色の花が咲いて弾ける
	var open := RBMHeroFx.ramp(a2, 0.0, 0.16)
	var ff := 1.0 - RBMHeroFx.ramp(a2, 0.35, 0.6)
	if a2 >= 0.0 and ff > 0.0:
		show_bloom(flower, hit + Vector2(0, -4), 40.0, {"open": open, "rot": a2 * 0.6, "squash": 0.8, "glow": 0.25 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.2)), "crumble": RBMHeroFx.ramp(a2, 0.28, 0.6), "fade": 1.0})
	else:
		flower.visible = false
	if a2 >= 0.0:
		disc(b_add, hit, 14.0 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.07)), Color(PINK, 0.6 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.07))))
		petal_cloud(b_front, hit, a2, 70, 21, 200.0, 5.5, DEEP, PINK, 1.0, "burst", 0.45, Color(VINE_D, 0.85))
		shards(b_front, hit, a2, 0.9, 24, 23, 300.0, 3.0, VINE_M, VINE_D, 260.0)
		sparks(b_add, hit, a2, 0.6, 70, 25, 520.0, PALE, BLUSH, 0.0, TAU, 120.0, 2.0)
		view["shake"] += hit_shake(a2, 15.0, 80.0, 0.45)
		view["allies"][3]["force"] = maxf(float(view["allies"][3].get("force", 0.0)), RBMHeroFx.env(a2, 0.0, 0.05, 0.15, 0.5))
		set_post({"flash": 0.18 * (1.0 - RBMHeroFx.ramp(a2, 0.0, 0.15)), "flash_col": Vector3(1.0, 0.8, 0.9)})
	var bf := 1.0 - RBMHeroFx.ramp(a2, 0.3, 0.65)
	burst.visible = a2 >= 0.0 and bf > 0.0
	if burst.visible:
		show_blast(burst, blobs(hit, a2, 26, 31, 140.0, 90.0, 42.0, 50.0, .7, 0.0, 9.0), a2, {"flow": a2 * .3, "cool": .06, "erode": RBMHeroFx.ramp(a2, .15, .6), "fade": bf, "erode_noise": .4, "polar": 1.0, "detail": .5, "radial_heat": .5, "heat_center": w(hit), "heat_radius": 120.0 * RBMHeroFx.burst(a2, 9.0), "erode_radial": 120.0, "tone_cap": .95})
		refract_wave(hit, a2, 0.5, 200.0, 6.0, 0.03)
	show_ring(rings[0], hit, a2, 0.5, 150.0, 6.0, 6.0, 0.025)
	show_ring(rings[1], foot, a2 - 0.06, 0.6, 200.0, 5.0, 5.0, 0.0)
	ally_hits(t, [[T.wrap, 3], [T.squeeze, 3]], 0.9)
	set_post({"vig": 0.3 * RBMHeroFx.env(t, T.windup, T.lash, T.squeeze + 0.3, T.back), "vig_col": Vector3(.04, .0, .03), "vig_r": .3})
	b_back.commit(); b_coil_back.commit(); b_glow.commit(); b_add.commit(); b_front.commit()
