extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/awaken.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー → 喪華のカラー女王「喪色の開花」（2026-11-13 作り直し。ユーザー案: ボスが大きな花の咲く木に変わり、
## その木が一気に枯れて、その中からボスが出てくる。変化が難しければ画面を花びらで覆う）:
## うなだれる → 足元から根が走り、幹が伸びて体を包む（体は木の色の影になって幹の中へ）→ 枝が広がり、大きな花が次々と咲く満開の木
## → 一気に枯れる（花はしおれて枯れ色へ、花びらが一斉に落ちる、木肌は灰色に）→ 幹に喪色の光のひびが走る
## → 木が砕け、暗い花びらの嵐が画面を覆う（木の破片が飛ぶ）→ 花びらの向こうから覚醒後の姿 → 背に巨大な喪色の花が開く。
## 本体はキーポーズだけ（1 構え → 2 うなだれ → 4 変わり終わり → 5 覚醒後）。木・花・花びらはエフェクト。

const T := {"distress": 0.45, "roots": 0.85, "trunk": 1.00, "trunk_end": 1.85, "branch": 1.55, "branch_end": 2.45, "bloom": 2.15, "bloom_end": 3.00,
	"wither": 3.55, "wither_end": 4.20, "crack": 4.30, "burst": 4.85, "done": 5.05, "end": 7.10}
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const MAUVE := Color("#8a2a4a")
const DEEP := Color("#4a0e26")
const PINK := Color("#e8a8c0")
const BLUSH := Color("#c06080")
const VIOLET := Color("#b060e0")
const PALE := Color("#fff0f4")
const BROWN := Color("#6a5a40")
const DARKBLOOM := ["#0c0408", "#1e0814", "#3a0c22", "#5a1a32", "#8a2a4a", "#c06080", "#e8b8c8", "#fff0f4"]
## 木の花（白から淡い桃）
const BLOSSOM := ["#3a1a28", "#6a3048", "#9a5a74", "#c88aa2", "#e8b4c6", "#f6d4e0", "#fdeef3", "#ffffff"]
## 喪華（背に開く巨大な花）
const MOURN := ["#08020a", "#160412", "#26081c", "#3a0e28", "#521634", "#6e2244", "#8e3458", "#b45276"]
## 木肌（生きている時・枯れた時）
const BARK := [Color("#1e140e"), Color("#4a3424"), Color("#7a5a3c"), Color("#a07c56")]
const BARK_DEAD := [Color("#141210"), Color("#34302c"), Color("#565048"), Color("#746c62")]

## 幹（足元からの論理ドット）
const TRUNK := [Vector2(0, 2), Vector2(-5, -28), Vector2(4, -58), Vector2(-3, -90), Vector2(2, -120)]
## 根（幹の根元の中から地面へ潜るように張る。2026-11-14 指摘「根元が変に丸まっていて本物の木に見えない」→ 板根の形に）
const ROOTS := [[Vector2(-8, -14), Vector2(-24, -2), Vector2(-46, 5), Vector2(-70, 8)], [Vector2(8, -14), Vector2(26, -2), Vector2(48, 5), Vector2(72, 7)],
	[Vector2(-4, -8), Vector2(-14, 4), Vector2(-26, 11), Vector2(-36, 15)], [Vector2(5, -8), Vector2(16, 4), Vector2(30, 11), Vector2(42, 14)],
	[Vector2(-12, -18), Vector2(-34, -8), Vector2(-58, -2)], [Vector2(12, -18), Vector2(36, -9), Vector2(60, -4)]]
## 枝: [幹のどこから(0〜1), 形（枝の根元からの点）, 根元の太さ, 先の太さ, 遅れ]
const BRANCHES := [[0.80, [Vector2(0, 0), Vector2(-26, -22), Vector2(-58, -42), Vector2(-90, -50)], 11.0, 3.0, 0.00],
	[0.84, [Vector2(0, 0), Vector2(24, -22), Vector2(56, -46), Vector2(90, -56)], 11.0, 3.0, 0.05],
	[0.68, [Vector2(0, 0), Vector2(-30, -6), Vector2(-66, -2), Vector2(-100, 8)], 9.0, 2.5, 0.10],
	[0.72, [Vector2(0, 0), Vector2(30, -8), Vector2(66, -6), Vector2(100, 4)], 9.0, 2.5, 0.12],
	[0.96, [Vector2(0, 0), Vector2(-10, -30), Vector2(-26, -60), Vector2(-34, -88)], 9.0, 3.0, 0.08],
	[0.98, [Vector2(0, 0), Vector2(12, -30), Vector2(28, -58), Vector2(44, -80)], 8.0, 3.0, 0.10]]

var b_back: RBMHeroFxBatch
var b_cloak: RBMHeroFxBatch
var b_tree: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_add: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var blast: ColorRect
var mourn: ColorRect
var blossoms: Array = []
var rings: Array = []

func duration() -> float:
	return T.end

func impact() -> float:
	return T.done

func stops() -> Array:
	return [[T.burst, 0.12]]

func pose_keys() -> Array:
	return [[0.0, 1], [T.distress, 2], [T.burst, 4], [float(T.done) + 0.3, 5]]

func _build() -> void:
	b_back = batch(back, false)
	blast = blast_quad(back, DARKBLOOM, DARKBLOOM, {"amp": 34., "k": .05, "seed": 4.4, "glow": .6, "glow_col": Vector3(.8, .2, .45), "glow_r": 50.})
	mourn = bloom_quad(back, MOURN, [], {"petals": 12.0, "seed": 9.0, "outline_col": Vector3(.06, .01, .04), "core_a": Vector3(.95, .6, 1.0), "core_b": Vector3(.55, .2, .7), "glow_col": Vector3(.9, .4, .8), "tilt": Vector3(8., 24., 44.)})
	b_cloak = batch(back, false)
	b_glow = batch(front)
	b_tree = batch(front, false)
	for i in range(12):
		blossoms.append(bloom_quad(front, BLOSSOM, [], {"petals": 8.0, "seed": 20.0 + i, "outline_col": Vector3(.2, .08, .12), "core_a": Vector3(1., .86, .4), "core_b": Vector3(.8, .5, .2)}))
	for i in range(3):
		rings.append(ring_quad(front, ["#5a1a32", "#c06080", "#e8b8c8", "#fff0f4"], {"squash": .34, "breakup": .45, "seed": 2.0 + i * 2.2, "glow": .4, "glow_col": Vector3(.8, .2, .45)}))
	b_front = batch(front, false)
	b_add = batch(front)

# --- 木 ----------------------------------------------------------------------

## なめらかな線（Catmull-Rom で点を増やす）
static func smooth_path(pts: Array, steps: int = 4) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		for s in range(steps):
			var u := float(s) / steps
			var u2 := u * u
			var u3 := u2 * u
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3))
	out.append(pts[-1])
	return out

## 枝・幹（太さが根元から先へ細る。濃い縁 → 木肌 → 片側の照り）。grow（0〜1）まで伸びる。終わりの点を返す。
## 枝・幹（2026-11-14 指摘「根元と幹に変な茶色の丸がある」→ 継ぎ目に丸を描かず、点ごとの向きを平均した1本の帯で描く）。
## 太さは根元から先へ細る。flare は根元の広がり（地面のすぐ近くだけ凹んだ曲線で太る）。濃い縁 → 木肌（片側が暗い）→ 片側の照り。
## grow（0〜1）まで伸びる。終わりの点を返す。
func limb(b: RBMHeroFxBatch, pts: Array, w0: float, w1: float, grow: float, cols: Array, flare: float = 0.0) -> Vector2:
	if grow <= 0.0 or pts.size() < 2:
		return pts[0]
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] - pts[i]).length()
	var reach := total * clampf(grow, 0.0, 1.0)
	# 伸びた所までの点・太さ・向き（隣の線分の向きの平均。継ぎ目で帯が割れない）
	var ps: Array = [pts[0]]
	var ws: Array = []
	var s := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var seg := (c - a).length()
		if s + seg >= reach:
			ps.append(a.lerp(c, (reach - s) / maxf(seg, 0.001)))
			break
		ps.append(c)
		s += seg
	var acc := 0.0
	for i in range(ps.size()):
		if i > 0:
			acc += ((ps[i] as Vector2) - (ps[i - 1] as Vector2)).length()
		ws.append(lerpf(w0, w1, acc / total) + flare * pow(maxf(0.0, 1.0 - acc / 16.0), 3.0))
	if ps.size() < 2:
		return ps[0]
	var ns: Array = []
	for i in range(ps.size()):
		var d0: Vector2 = ((ps[mini(i + 1, ps.size() - 1)] as Vector2) - (ps[maxi(i - 1, 0)] as Vector2)).normalized()
		ns.append(d0.orthogonal())
	var dark: Color = cols[0]
	var mid: Color = cols[1]
	var side_dark: Color = (cols[0] as Color).lerp(cols[1], 0.45)
	var lite: Color = cols[2]
	for i in range(ps.size() - 1):
		var a: Vector2 = ps[i]
		var c: Vector2 = ps[i + 1]
		var na: Vector2 = ns[i]
		var nc: Vector2 = ns[i + 1]
		var wa: float = ws[i] * 0.5
		var wc: float = ws[i + 1] * 0.5
		# 濃い縁
		b.quad(a + na * (wa + 1.0), c + nc * (wc + 1.0), c - nc * (wc + 1.0), a - na * (wa + 1.0), dark, dark, dark, dark)
		# 木肌（片側が暗い）
		b.quad(a + na * wa, c + nc * wc, c, a, side_dark, side_dark, mid, mid)
		b.quad(a, c, c - nc * wc, a - na * wa, mid, mid, mid, mid)
		# 片側の照り
		b.quad(a - na * wa * 0.12, c - nc * wc * 0.12, c - nc * wc * 0.36, a - na * wa * 0.36, lite, lite, lite, lite)
	return ps[-1]

## 点の列を足元からの位置へ
static func at_home(pts: Array, origin: Vector2) -> Array:
	var out: Array = []
	for p in pts:
		out.append(origin + Vector2(p))
	return out

## 幹の上の位置（0〜1）
func trunk_point(u: float) -> Vector2:
	var pts: Array = smooth_path(at_home(TRUNK, HOME), 4)
	var idx := clampf(u, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(idx), pts.size() - 2)
	return (pts[i] as Vector2).lerp(pts[i + 1], idx - i)

## 花を付ける所: [位置, 大きさ, 咲く遅れ]
func blossom_spots() -> Array:
	var out: Array = []
	for bi in range(BRANCHES.size()):
		var br: Array = BRANCHES[bi]
		var root := trunk_point(float(br[0]))
		var shape: Array = br[1]
		out.append([root + Vector2(shape[3]), 22.0 - bi * 1.0, float(br[4]) + bi * 0.05])
		if bi < 4:
			out.append([root + Vector2(shape[2]) + Vector2(0, -8), 15.0, float(br[4]) + 0.18 + bi * 0.04])
	out.append([trunk_point(1.0) + Vector2(0, -14), 24.0, 0.25])
	out.append([trunk_point(0.88) + Vector2(-6, -4), 14.0, 0.3])
	return out

func _step(t: float) -> void:
	b_back.reset(); b_cloak.reset(); b_glow.reset(); b_tree.reset(); b_add.reset(); b_front.reset()
	var a2 := t - T.done
	var ab := t - T.burst
	var wither := RBMHeroFx.ramp(t, T.wither, T.wither_end)
	var gone := t >= T.burst
	var bark: Array = []
	for i in range(4):
		bark.append((BARK[i] as Color).lerp(BARK_DEAD[i], wither))
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.0], [T.distress, 0.12], [T.trunk, 0.3], [T.bloom_end, 0.22], [T.wither, 0.3], [T.wither_end, 0.62], [T.burst - 0.05, 0.8], [T.burst + 0.2, 0.55], [T.end, 0.3]])
	view["dim_col"] = Color(0.04, 0.0, 0.03)
	# うなだれ: 白い花びらが静かに舞う
	var calm := 1.0 - RBMHeroFx.ramp(t, T.trunk, T.trunk + 0.4)
	petal_cloud(b_front, HOME + Vector2(0, -50), t, 14, 3, 50.0, 4.0, WHITE, IVORY, calm, "orbit", 0.5, Color("#4c5c4a", 0.8))
	# 体は木の色の影になって幹の中へ
	view["hero"]["silhouette"] = RBMHeroFx.ramp(t, T.trunk + 0.15, T.trunk + 0.55) * (0.0 if gone else 1.0)
	view["hero"]["sil_col"] = bark[1]
	body["hidden"] = t >= float(T.trunk) + 0.6 and t < T.burst
	if not gone:
		# 根が走る
		var rg := RBMHeroFx.ramp(t, T.roots, T.roots + 0.35)
		for ri in range(ROOTS.size()):
			limb(b_tree, smooth_path(at_home(ROOTS[ri], HOME), 4), 13.0 - ri * 1.2, 1.6, rg, bark)
		if rg > 0.0 and rg < 1.0:
			rocks(b_front, HOME + Vector2(0, 2), t - T.roots, 0.5, 10, 5, 90.0, 2.0, 30.0)
		# 幹が伸びて体を包む
		var tg := RBMHeroFx.ramp(t, T.trunk, T.trunk_end)
		tg = 1.0 - pow(1.0 - tg, 2.0)
		limb(b_tree, smooth_path(at_home(TRUNK, HOME), 4), 30.0, 11.0, tg, bark, 26.0)
		# 木肌の筋（縦のうねる溝。丸い節は描かない）
		if tg > 0.15:
			for k in range(9):
				var x0 := (float(k) / 8.0 - 0.5) * 0.8
				var prev := Vector2.ZERO
				for j in range(9):
					var u := 0.04 + 0.11 * j
					if u > tg:
						break
					var wd := lerpf(28.0, 11.0, u)
					var p := trunk_point(u) + Vector2(x0 * wd + sin(u * 9.0 + k) * 2.0, 0.0)
					if j > 0 and RBMHeroFx.r(k * 13 + j, 71) > 0.25:
						b_tree.line(prev, p, 1.0, bark[0], bark[0])
					prev = p
		# 枝が広がる
		for bi in range(BRANCHES.size()):
			var br: Array = BRANCHES[bi]
			var bg := RBMHeroFx.ramp(t, float(T.branch) + float(br[4]), float(T.branch_end) + float(br[4]))
			var root := trunk_point(float(br[0]))
			var pts := smooth_path(at_home(br[1], root), 4)
			limb(b_tree, pts, float(br[2]), float(br[3]), bg, bark)
			# 小枝
			if bg > 0.5:
				var mid: Vector2 = root + Vector2(br[1][2])
				for s in [-1.0, 1.0]:
					var twig := [mid, mid + Vector2(s * 10.0, -14.0), mid + Vector2(s * 16.0, -24.0)]
					limb(b_tree, twig, 3.0, 1.2, RBMHeroFx.ramp(bg, 0.5, 1.0), bark)
		# 大きな花が次々と咲く満開の木 → 一気に枯れる
		var spots := blossom_spots()
		for i in range(blossoms.size()):
			var q: ColorRect = blossoms[i]
			if i >= spots.size():
				q.visible = false
				continue
			var sp_: Array = spots[i]
			var o := RBMHeroFx.ramp(t, float(T.bloom) + float(sp_[2]), float(T.bloom) + float(sp_[2]) + 0.4)
			if o <= 0.0:
				q.visible = false
				continue
			var droop := Vector2(0, 10.0 * wither)
			# 枯れた花はトゲのような形にしない: しおれ始めたら点描で崩れて散る
			var crumble := RBMHeroFx.ramp(t, float(T.wither) + 0.25 + i * 0.02, float(T.wither_end) + 0.05)
			show_bloom(q, Vector2(sp_[0]) + droop, float(sp_[1]), {"open": o, "rot": i * 0.6 + t * 0.15, "squash": 0.72, "wither": wither * 0.6, "crumble": crumble,
				"glow": 0.25 * RBMHeroFx.env(t, T.bloom_end - 0.2, T.bloom_end, T.wither, T.wither + 0.3), "fade": 1.0})
		# 満開の光
		var full := RBMHeroFx.env(t, T.bloom_end - 0.3, T.bloom_end, T.wither, T.wither + 0.3)
		petal_cloud(b_front, trunk_point(0.9) + Vector2(0, 30), t, 30, 31, 110.0, 4.5, PALE, PINK, full, "fall", 0.45, Color(DEEP, 0.7))
		# 一気に枯れる: 花びらが一斉に落ちる
		petal_cloud(b_front, trunk_point(0.9) + Vector2(0, 40), t, 70, 33, 130.0, 5.0, BROWN, BLUSH, RBMHeroFx.env(t, T.wither, T.wither + 0.15, T.burst, T.burst + 0.1), "fall", 0.45, Color("#2a1e14", 0.8))
		view["shake"] += hit_shake(t - T.wither, 5.0, 60.0, 0.35)
		# 幹に喪色の光のひびが走る
		for ci in range(5):
			var ct := t - (float(T.crack) + ci * 0.09)
			if ct < 0.0:
				continue
			var u0 := 0.15 + ci * 0.15
			var p0 := trunk_point(u0) + Vector2((RBMHeroFx.r(ci, 81) - 0.5) * 16.0, 0)
			var ln := 20.0 * RBMHeroFx.ramp(ct, 0.0, 0.1)
			var d := Vector2.from_angle(-PI * 0.5 + (RBMHeroFx.r(ci, 82) - 0.5) * 1.2)
			var p1 := p0 + d * ln
			var p2 := p1 + d.rotated(0.6 * (1.0 if ci % 2 == 0 else -1.0)) * ln * 0.7
			b_add.line(p0, p1, 2.0, Color(VIOLET, 0.9), Color(PINK, 0.9))
			b_add.line(p1, p2, 1.5, Color(PINK, 0.9), Color(VIOLET, 0.6))
			disc(b_glow, p0, 10.0, Color(VIOLET, 0.25))
			view["shake"] += hit_shake(ct, 4.0, 90.0, 0.15)
		var tm := RBMHeroFx.ramp(t, T.crack, T.burst)
		inward(b_add, trunk_point(0.4), t, 90, 17, 8.0, 220.0, 2.0, PINK, tm, 2.2)
		view["hero"]["lit"] = 0.0
	else:
		for q in blossoms:
			(q as ColorRect).visible = false
	# 木が砕け、暗い花びらの嵐が画面を覆う（木の破片が飛ぶ）
	if ab >= 0.0:
		shards(b_front, trunk_point(0.45), ab, 1.2, 60, 91, 520.0, 6.0, bark[2], bark[0], 260.0)
		shards(b_front, trunk_point(0.85), ab, 1.2, 40, 93, 460.0, 5.0, bark[2], bark[0], 260.0)
		petal_wind(b_front, ab, 260, 95, 1.0 - RBMHeroFx.ramp(ab, 0.55, 1.1))
		petal_cloud(b_front, trunk_point(0.4), ab, 160, 97, 520.0, 7.0, DEEP, PINK, 1.0, "burst", 0.45, Color("#1a0610", 0.85))
		if ab < 0.14:
			view["hero"]["flash"] = 1.0 - ab / 0.14
			view["hero"]["flash_col"] = PALE
	var bf := 1.0 - RBMHeroFx.ramp(ab, 0.55, 1.0)
	blast.visible = ab >= 0.0 and bf > 0.0
	if blast.visible:
		var c2 := HOME + Vector2(0, -50)
		show_blast(blast, blobs(c2, ab, 40, 29, 380.0, 200.0, 90.0, 120.0, .6, 0.0, 6.4), ab, {"flow": ab * .22, "cool": .05 + RBMHeroFx.ramp(ab, .2, 1.0) * .22, "erode": RBMHeroFx.ramp(ab, .3, .98), "fade": bf, "erode_noise": .4,
			"polar": 1.0, "detail": .55, "amp": 34.0, "radial_heat": .45, "heat_center": w(c2), "heat_radius": 360.0 * RBMHeroFx.burst(ab, 6.4), "erode_radial": 180.0, "tone_cap": .95})
		refract_wave(HOME, ab, 0.8, 560.0, 5.0, 0.03)
	show_ring(rings[0], HOME, ab, 0.7, 520.0, 8.0, 5.0, 0.03)
	view["shake"] += hit_shake(ab, 15.0, 70.0, 0.55)
	# 覚醒後の常時オーラ（喪華の深紅〜紫。2026-11-14 ユーザー「覚醒後はオーラ、ボスに合った色で」）
	view["hero"]["sun_aura"] = RBMHeroFx.ramp(ab, 0.1, 0.8)
	# 覚醒後の姿: 背に巨大な喪色の花が開く（正面向きの立体の花）
	var om := RBMHeroFx.ramp(ab, 0.15, 0.75)
	var mf := 1.0 - RBMHeroFx.ramp(a2, 1.3, 1.9)
	if om > 0.0 and mf > 0.0:
		show_bloom(mourn, HOME + Vector2(6, -62), 92.0, {"open": om, "rot": t * 0.1, "squash": 0.92, "glow": 0.45 * om * mf, "fade": mf})
	else:
		mourn.visible = false
	show_ring(rings[1], HOME + Vector2(0, -50), a2, 0.7, 300.0, 6.0, 5.0, 0.025)
	show_ring(rings[2], HOME, a2 - 0.1, 0.8, 420.0, 7.0, 5.0, 0.02)
	if a2 >= 0.0:
		view["hero"]["lit"] = 0.5 * (1.0 - RBMHeroFx.ramp(a2, 0.2, 0.9))
		view["hero"]["lit_col"] = BLUSH
		if a2 < 0.12:
			view["hero"]["flash"] = maxf(float(view["hero"].get("flash", 0.0)), 0.7 * (1.0 - a2 / 0.12))
			view["hero"]["flash_col"] = PALE
	ally_light(0.5 * RBMHeroFx.env(ab, 0.0, 0.05, 0.3, 0.8), BLUSH, -1.0)
	petal_cloud(b_front, Vector2(240, 140), t, 34, 61, 200.0, 4.5, DEEP, PINK, RBMHeroFx.env(a2, 0.5, 1.0, T.end - T.done - 0.4, T.end - T.done), "fall", 0.45, Color("#1a0610", 0.8))
	set_post({"desat": 0.45 * wither * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.3)), "vig": 0.5 * wither * (1.0 - RBMHeroFx.ramp(ab, 0.0, 0.4)) + 0.15, "vig_col": Vector3(.03, .0, .02), "vig_r": .26})
	b_back.commit(); b_cloak.commit(); b_glow.commit(); b_tree.commit(); b_add.commit(); b_front.commit()

## 画面を横切る花びらの壁（砕けた瞬間から右から左へ吹き抜ける。画面を覆って変わり目を隠す）
func petal_wind(b: RBMHeroFxBatch, age: float, n: int, seed_: int, alpha: float) -> void:
	if alpha <= 0.01 or age < 0.0:
		return
	for i in range(n):
		var r1 := RBMHeroFx.r(i, seed_)
		var r2 := RBMHeroFx.r(i, seed_ + 1)
		var r3 := RBMHeroFx.r(i, seed_ + 2)
		var sp_ := 700.0 + 500.0 * r2
		var x := HOME.x + 40.0 - (age * sp_ - r1 * 260.0)
		var y := 20.0 + 330.0 * r3 + sin(age * 4.0 + i) * 12.0
		if x < -20.0 or x > HOME.x + 60.0:
			continue
		var col := DEEP.lerp(PINK, r2 * 0.8)
		col.a *= alpha
		var tip := MAUVE.lerp(PALE, r1 * 0.5)
		tip.a *= alpha
		var ln := 6.0 + 6.0 * r1
		var spin := age * (3.0 + r3 * 4.0) + r1 * TAU
		petal(b, Vector2(x, y) - Vector2.from_angle(spin) * 0.8, spin, ln + 1.6, ln * 0.6 + 1.4, Color("#1a0610", 0.85 * alpha), Color("#1a0610", 0.85 * alpha))
		petal(b, Vector2(x, y), spin, ln, ln * 0.6, col, tip)
