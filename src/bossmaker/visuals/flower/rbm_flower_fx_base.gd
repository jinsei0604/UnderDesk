class_name RBMFlowerFxBase
extends RBMHeroFxBase
## 白磁のカラー／喪華のカラー女王（flower）のエフェクト1種類の土台（表示専用。戦闘の状態・乱数には触れない）。
## ヒーローのエフェクトの部品（RBMHeroFxBase の粒・爆炎・輪・柱・後処理）をそのまま使い、花の部品（立体の花 bloom・カラー calla・花びら・蔦・光の筋）を足す。
## 2026-11-11〜16 の試作（prototypes/four_bosses_2026-11-11/scripts/proto_fx.gd）でユーザーが採用した部品を、このボスが使う物だけ移した。
## 本体はキーポーズの完成した全身の絵をそのまま切り替える（pose_keys）。動きは位置の移動（move_keys）と
## 命中のヒットストップ（stops）だけ。座標は 640×360 の論理ドット（ステージの半分）。絵の画素は px() で直す。
## 他の技のキーポーズを借りる技（支援・登場・撃破）は extra_poses() に {番号: [技, 何枚目]} を書く（借りた絵の場所は at_seq()）。

const ORIGIN := RBMFlowerMotion.ORIGIN
const HOME := Vector2(390, 237)
const SHADER_ROOT := "res://src/bossmaker/visuals/flower/shaders/"

## ボスの名前（試作の部品の書き方のまま）
var boss := "flower"
## 技の名前（RBMFlowerMotion.MOVES。支援・登場・撃破は借りた絵の技）
var seq := ""
## 本体の今の状態（つなぎが読む）: pose=1始まりの番号（0＝立ち姿）, off=位置のずれ, ghosts=残像, alpha, hidden, dissolve など
var body := {}

## 技の秒（子で上書き）
func duration() -> float:
	return 3.0

## 最後の一撃（HP の表示が変わる所）の秒
func impact() -> float:
	return 1.0

## 途中の当たり: [[秒, 味方の基準の番号(0〜3)], ...]（最後の一撃より前）
func hits() -> Array:
	return []

## ヒットストップ: [[演出の中の秒, 実時間の長さ], ...]。この間は本体もエフェクトも止まる（揺れだけ続く）。
func stops() -> Array:
	return []

## 実時間 → 演出の中の時刻（ヒットストップの間は止まる）。stops() の秒は演出の中の時刻で、順に並べる。
func warp(t: float) -> float:
	var shift := 0.0
	for s in stops():
		var start := float(s[0]) + shift
		if t < start:
			break
		if t < start + float(s[1]):
			return float(s[0])
		shift += float(s[1])
	return t - shift

## 演出の中の時刻 → 実時間（その時刻に始まるヒットストップの前）。
func unwarp(te: float) -> float:
	var shift := 0.0
	for s in stops():
		if te > float(s[0]) + 0.0001:
			shift += float(s[1])
	return te + shift

## キーポーズの切り替え: [[秒, 番号], ...]（切り替えは一瞬。間を埋めない）
func pose_keys() -> Array:
	return [[0.0, 1]]

## 位置: [[秒, Vector2(論理ドット), "snap" / "lin" / "out" / "in" / "inout"], ...]。前の点からこの点まで、指定の速さで動く。
func move_keys() -> Array:
	return [[0.0, Vector2.ZERO, "snap"]]

static func pose_at(keys: Array, t: float) -> int:
	var p := int(keys[0][1])
	for k in keys:
		if t >= float(k[0]):
			p = int(k[1])
	return p

static func move_at(keys: Array, t: float) -> Vector2:
	var prev_t := float(keys[0][0])
	var prev: Vector2 = keys[0][1]
	for k in keys:
		var kt := float(k[0])
		var kv: Vector2 = k[1]
		if t < kt:
			var mode := str(k[2]) if k.size() > 2 else "lin"
			if mode == "snap" or kt <= prev_t:
				return prev
			var u := clampf((t - prev_t) / (kt - prev_t), 0.0, 1.0)
			match mode:
				"out": u = 1.0 - pow(1.0 - u, 3.0)
				"in": u = u * u * u
				"inout": u = u * u * (3.0 - 2.0 * u)
			return prev.lerp(kv, u)
		prev_t = kt
		prev = kv
	return prev

## つなぎから毎フレーム呼ぶ: 本体の状態を決めてからエフェクトを作る。
func advance_pose(t: float) -> void:
	body = {"pose": pose_at(pose_keys(), t), "off": move_at(move_keys(), t).round(), "ghosts": []}
	advance(t, "", HOME + Vector2(body.off), HOME + Vector2(body.off))
	view["body"] = body

## 他の技のキーポーズを借りる: {番号: [技, 何枚目]}（つなぎがその絵を読む。番号は 9 など、技の絵と重ならない数）
func extra_poses() -> Dictionary:
	return {}

# --- 位置 ------------------------------------------------------------------

## 今のポーズ（または pose 番目）の、測った場所（front / top / center / mark）を論理ドットで。
func at(which: String, pose: int = -1, dx: float = 0.0, dy: float = 0.0) -> Vector2:
	var p := pose if pose > 0 else int(body.get("pose", 1))
	return at_seq(seq, p, which, dx, dy)

## 別の技の絵（extra_poses で借りたポーズなど）の seq_name の pose 枚目の which を論理ドットで。
func at_seq(seq_name: String, pose: int, which: String, dx: float = 0.0, dy: float = 0.0) -> Vector2:
	var list: Array = RBMFlowerMotion.anchors().get(seq_name, [])
	if pose >= 1 and pose <= list.size():
		var a: Array = list[pose - 1][which]
		return px(Vector2(float(a[0]) + dx, float(a[1]) + dy))
	return HOME

## 絵の画素 → 論理ドット（今の本体の位置で）。
func px(p: Vector2) -> Vector2:
	return HOME + Vector2(body.get("off", Vector2.ZERO)) + (p - ORIGIN)


## 残像（同じ絵を色だけで薄く重ねる。形は変えない）
func ghost(pose: int, off: Vector2, alpha: float, col: Color, sil: float = 0.55) -> void:
	if alpha > 0.01:
		body["ghosts"].append({"pose": pose, "off": off.round(), "a": alpha, "col": col, "sil": sil})

# --- 図形（すべて論理ドット。三角形の配列でまとめて描く） ------------------

## 花びら（しずく形）。base から dir の向きに length、幅 width。
func petal(b: RBMHeroFxBatch, base: Vector2, ang: float, length: float, width: float, col_base: Color, col_tip: Color) -> void:
	if length <= 0.5 or (col_base.a <= 0.01 and col_tip.a <= 0.01):
		return
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	var prev_l := base
	var prev_r := base
	var steps := 8
	for i in range(1, steps + 1):
		var u := float(i) / steps
		# 先の丸い楕円（尖らせない。星の形に見えないように）
		var wv := (sin(u / 0.62 * PI * 0.5) if u < 0.62 else sqrt(maxf(0.0, 1.0 - pow((u - 0.62) / 0.38, 2.0)))) * width * 0.5
		var c := base + d * length * u
		var l := c + n * wv
		var r := c - n * wv
		var ca := col_base.lerp(col_tip, float(i - 1) / steps)
		var cb := col_base.lerp(col_tip, u)
		b.quad(prev_l, l, r, prev_r, ca, cb, cb, ca)
		prev_l = l
		prev_r = r

## 上から差す光の筋（2026-11-14 上端を硬く切らない: 上は透明 → 3割の所で半分 → 足元で一番明るい。左右の端も透明）。
func light_shaft(b: RBMHeroFxBatch, foot: Vector2, height: float, w_top: float, w_bot: float, col: Color, a: float) -> void:
	if a <= 0.005:
		return
	var ys := [0.0, 0.35, 1.0]
	var al := [0.0, 0.55, 1.0]
	for s in range(2):
		var y0: float = foot.y - height * (1.0 - float(ys[s]))
		var y1: float = foot.y - height * (1.0 - float(ys[s + 1]))
		var w0: float = lerpf(w_top, w_bot, float(ys[s]))
		var w1: float = lerpf(w_top, w_bot, float(ys[s + 1]))
		var c0 := Color(col, a * float(al[s]))
		var c1 := Color(col, a * float(al[s + 1]))
		var e := Color(col, 0.0)
		b.quad(Vector2(foot.x - w0, y0), Vector2(foot.x, y0), Vector2(foot.x, y1), Vector2(foot.x - w1, y1), e, c0, c1, e)
		b.quad(Vector2(foot.x, y0), Vector2(foot.x + w0, y0), Vector2(foot.x + w1, y1), Vector2(foot.x, y1), c0, e, e, c1)

## カラーの花を一輪（2026-11-14 白磁のカラーの撃破に残る花・支援の花。上から見た放射状の花は小さいと星に見えるので、横から見た一輪にする）。
## base は茎の根元（地面）、h は高さ、open 0〜1 で茎が伸びて苞が開く、lean は傾き（右が正）。
## sp = [苞の奥（喉）, 苞, 苞の明るい先], stem = [茎の濃い側, 明るい側]。輪郭 line_c。
func calla(b: RBMHeroFxBatch, base: Vector2, h: float, open: float, lean: float, sp: Array, line_c: Color, stem: Array, spadix: Color) -> void:
	if open <= 0.0:
		return
	var g := RBMHeroFx.ramp(open, 0.0, 0.6)
	var o := RBMHeroFx.ramp(open, 0.35, 1.0)
	var hh := h * (0.35 + 0.65 * g)
	var top := base + Vector2(sin(lean) * hh, -cos(lean) * hh)
	var ctrl := base + Vector2(sin(lean) * hh * 0.15 - 2.0, -hh * 0.5)
	var pts: Array = []
	for i in range(9):
		var u := float(i) / 8.0
		pts.append(base.lerp(ctrl, u).lerp(ctrl.lerp(top, u), u))
	# 根元の葉（2枚、外へ開く）
	for side in [-1.0, 1.0]:
		var la: float = -PI * 0.5 + float(side) * (0.75 + 0.15 * g)
		var ll := h * 0.42 * g
		petal(b, base - Vector2.from_angle(la) * 0.8, la, ll + 1.8, ll * 0.36 + 1.6, line_c, line_c)
		petal(b, base, la, ll, ll * 0.36, Color(stem[0]), Color(stem[1]))
	for i in range(1, pts.size()):
		b.line(pts[i - 1], pts[i], 3.4, line_c, line_c)
	for i in range(1, pts.size()):
		b.line(pts[i - 1], pts[i], 1.6, Color(stem[0]), Color(stem[1]))
	# 苞（ラッパ形: 根元が細く先が広い。先は丸い）と、中の喉の影・黄色の芯
	if o > 0.0:
		var ang := -PI * 0.5 + lean + 0.5
		var d := Vector2.from_angle(ang)
		var nn := d.orthogonal()
		var L := h * 0.6 * (0.5 + 0.5 * o)
		var W := L * (0.3 + 0.32 * o)
		petal(b, top - d * 1.0, ang, L + 2.0, W + 1.8, line_c, line_c)
		petal(b, top, ang, L, W, Color(sp[1]), Color(sp[2]))
		petal(b, top + d * L * 0.18 - nn * W * 0.08, ang, L * 0.62 * o, W * 0.46 * o, Color(sp[0]), Color(sp[1]))
		b.line(top + d * L * 0.12, top + d * L * (0.12 + 0.34 * o), maxf(1.0, W * 0.16), spadix, spadix.lightened(0.35))

## 塗りの円（楕円）。
func disc(b: RBMHeroFxBatch, c: Vector2, r: float, col: Color, squash: float = 1.0, edge: Color = Color(0, 0, 0, -1)) -> void:
	if r <= 0.3 or col.a <= 0.01:
		return
	var e := col if edge.a < 0.0 else edge
	var segs := clampi(int(r * 0.8), 12, 48)
	for i in range(segs):
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		b.tri(c, c + Vector2(cos(a0) * r, sin(a0) * r * squash), c + Vector2(cos(a1) * r, sin(a1) * r * squash), col, e, e)

## 輪（楕円の線）。a0〜a1 の範囲だけも描ける。
func ring_line(b: RBMHeroFxBatch, c: Vector2, r: float, w: float, col: Color, squash: float = 1.0, a0: float = 0.0, a1: float = TAU, col_out: Color = Color(0, 0, 0, -1)) -> void:
	if r <= 0.3 or col.a <= 0.01 or w <= 0.0:
		return
	var co := col if col_out.a < 0.0 else col_out
	var segs := clampi(int(r * 0.9 * (a1 - a0) / TAU), 10, 96)
	for i in range(segs):
		var t0 := a0 + (a1 - a0) * i / segs
		var t1 := a0 + (a1 - a0) * (i + 1) / segs
		var i0 := c + Vector2(cos(t0) * (r - w * .5), sin(t0) * (r - w * .5) * squash)
		var o0 := c + Vector2(cos(t0) * (r + w * .5), sin(t0) * (r + w * .5) * squash)
		var i1 := c + Vector2(cos(t1) * (r - w * .5), sin(t1) * (r - w * .5) * squash)
		var o1 := c + Vector2(cos(t1) * (r + w * .5), sin(t1) * (r + w * .5) * squash)
		b.quad(i0, o0, o1, i1, col, co, co, col)

## このボスのシェーダー（shaders/）の矩形（論理ドット）。
func pquad(parent: Node, rect: Rect2, shader_name: String, params: Dictionary = {}) -> ColorRect:
	var q := ColorRect.new()
	q.position = rect.position
	q.size = rect.size
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_ROOT + shader_name + ".gdshader")
	q.material = m
	q.visible = false
	sp(q, params)
	parent.add_child(q)
	return q

## 蔦: p0 から p1 へ、横へ bend だけ膨らむ曲線。grow（0〜1）まで伸びる。thorns で小さな棘、leaves で葉。
func vine(b: RBMHeroFxBatch, p0: Vector2, p1: Vector2, bend: float, grow: float, width: float, col_dark: Color, col_light: Color, seed_: int, thorns: bool = false, leaves: bool = false) -> void:
	if grow <= 0.0 or col_dark.a <= 0.01:
		return
	var n := (p1 - p0).orthogonal().normalized()
	var ctrl := (p0 + p1) * 0.5 + n * bend
	var steps := 18
	var last := int(ceil(steps * clampf(grow, 0.0, 1.0)))
	var prev := p0
	for i in range(1, last + 1):
		var u := minf(float(i) / steps, grow)
		var p := p0.lerp(ctrl, u).lerp(ctrl.lerp(p1, u), u)
		var wv := width * (1.0 - 0.6 * u)
		b.line(prev, p, wv + 1.0, col_dark, col_dark)
		b.line(prev, p, maxf(0.8, wv * 0.4), col_light, col_light)
		var d := (p - prev).normalized()
		if thorns and i % 3 == 1:
			var side := 1.0 if i % 2 == 0 else -1.0
			var base := p - d * 1.5
			b.tri(base + d * 1.2, base - d * 1.2, base + d.orthogonal() * side * (2.0 + wv * 0.5) - d * 1.5, col_dark, col_dark, col_dark)
		if leaves and i % 4 == 2:
			var side2 := 1.0 if (i / 4) % 2 == 0 else -1.0
			petal(b, p, d.angle() + side2 * 0.9, 4.0 + width, 2.4 + width * 0.4, col_dark, col_light)
		prev = p

## 花（中心 c、花びら n 枚、長さ length、開き open 0〜1、回転 rot）。花びらは内側の色から外側の色へ。
func bloom(b: RBMHeroFxBatch, c: Vector2, n: int, length: float, open: float, rot: float, col_in: Color, col_out: Color, width_k: float = 0.55, squash: float = 1.0) -> void:
	if open <= 0.0:
		return
	for i in range(n):
		var a := rot + TAU * i / n
		var l := length * open
		var dir := Vector2(cos(a), sin(a) * squash)
		petal(b, c, dir.angle(), l * dir.length(), l * width_k, col_in, col_out)

## 花（shaders/bloom.gdshader。2026-11-13 白磁のカラー「花の形が安っぽい」→ 3段の花びら・陰影・輪郭・芯）。色は暗→明の8色。
func bloom_quad(parent: Node, pal_hex: Array, pal_w_hex: Array = [], params: Dictionary = {}) -> ColorRect:
	var p := {"pal": RBMHeroFx.pal(pal_hex), "pal_w": RBMHeroFx.pal(pal_w_hex if not pal_w_hex.is_empty() else WITHERED)}
	p.merge(params, true)
	return pquad(parent, Rect2(0, 0, 10, 10), "bloom", p)

## 花を c に半径 r で出す（矩形はその周りに作り直す）。params は bloom.gdshader の uniform（open・rot・squash・wither・crumble・fade・glow など）。
func show_bloom(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	var half := r * 1.2 + 6.0
	q.visible = true
	q.position = c - Vector2(half, half)
	q.size = Vector2(half, half) * 2.0
	var p := {"size": q.size, "center": Vector2(half, half), "radius": r}
	p.merge(params, true)
	sp(q, p)

## 蔦（2026-11-13 白磁のカラー用の作り直し）: p0 → p1 の二次曲線（ctrl で曲がる）。濃い縁・本体・照り・丸い節・縁取りの葉。
## 尖ったトゲは使わない。cols = [縁, 本体, 本体の明るい側, 照り, 葉の縁, 葉, 葉の明るい側]。grow まで伸びる。先の位置を返す。
func vine_rich(b: RBMHeroFxBatch, p0: Vector2, ctrl: Vector2, p1: Vector2, grow: float, width: float, seed_: int, cols: Array, leaves: bool = true) -> Vector2:
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
			var wv := width * (1.0 - 0.55 * float(i) / steps)
			var nn := (c - a).orthogonal().normalized()
			match pass_i:
				0: b.line(a, c, wv + 2.0, cols[0], cols[0])
				1: b.line(a, c, wv, cols[1], cols[2])
				2: b.line(a + nn * wv * 0.22, c + nn * wv * 0.22, maxf(0.8, wv * 0.3), cols[3], cols[3])
	for i in range(2, pts.size(), 4):
		var p: Vector2 = pts[i]
		var wv := width * (1.0 - 0.55 * float(i) / steps)
		disc(b, p, wv * 0.62 + 0.8, cols[0])
		disc(b, p + Vector2(-0.4, -0.4), wv * 0.42, cols[2])
		if leaves and i % 8 == 6:
			var d: Vector2 = ((pts[i] as Vector2) - (pts[i - 1] as Vector2)).normalized()
			var side := 1.0 if (i / 8) % 2 == 0 else -1.0
			var ang := d.angle() + side * 1.0
			petal(b, p, ang, 9.0 + width, 5.0 + width * 0.4, cols[4], cols[4])
			petal(b, p + Vector2.from_angle(ang) * 0.8, ang, 7.0 + width, 3.4 + width * 0.3, cols[5], cols[6])
	var tip: Vector2 = pts[-1]
	disc(b, tip, width * 0.5 + 1.0, cols[0])
	disc(b, tip, width * 0.35, cols[3])
	return tip

## 相手に螺旋に巻き付く蔦（相手の後ろ側は b_far、手前は b_near）。tight で締まる。cols は vine_rich と同じ。
func coil_vine(b_far: RBMHeroFxBatch, b_near: RBMHeroFxBatch, c: Vector2, height: float, rad: float, turns: float, grow: float, width: float, tight: float, cols: Array, phase: float = 0.0) -> void:
	if grow <= 0.0:
		return
	var n := 40
	var last := int(n * clampf(grow, 0.0, 1.0))
	var prev := Vector2.ZERO
	for i in range(last + 1):
		var u := float(i) / n
		var th := u * turns * TAU + phase
		var r := rad * (1.0 - 0.35 * tight)
		var p := c + Vector2(cos(th) * r, -u * height + sin(th) * r * 0.35)
		if i > 0:
			var near := sin(th) > 0.0
			var bb := b_near if near else b_far
			bb.line(prev, p, width + 2.0, cols[0], cols[0])
			bb.line(prev, p, width, cols[1] if near else (cols[0] as Color).lerp(cols[1], 0.5), cols[2] if near else cols[1])
			if near:
				bb.line(prev + Vector2(0, -width * 0.25), p + Vector2(0, -width * 0.25), maxf(0.8, width * 0.3), cols[3], cols[3])
		prev = p

## 画面を横切る花びらの波（from_x から左へ吹き抜ける）。cols = [根元の暗い色, 明るい色, 縁]。
func petal_sweep(b: RBMHeroFxBatch, age: float, n: int, seed_: int, from_x: float, y0: float, y1: float, alpha: float, cols: Array, speed: float = 700.0, size_: float = 6.0) -> void:
	if alpha <= 0.01 or age < 0.0:
		return
	for i in range(n):
		var r1 := RBMHeroFx.r(i, seed_)
		var r2 := RBMHeroFx.r(i, seed_ + 1)
		var r3 := RBMHeroFx.r(i, seed_ + 2)
		var x := from_x - (age * speed * (0.7 + 0.7 * r2) - r1 * 260.0)
		var y := lerpf(y0, y1, r3) + sin(age * 4.0 + i) * 12.0
		if x < -20.0 or x > from_x + 20.0:
			continue
		var col: Color = (cols[0] as Color).lerp(cols[1], r2 * 0.8)
		col.a *= alpha
		var tip: Color = (cols[1] as Color)
		tip.a *= alpha
		var oc: Color = cols[2]
		oc.a *= alpha
		var ln := size_ * (1.0 + r1)
		var spin := age * (3.0 + r3 * 4.0) + r1 * TAU
		petal(b, Vector2(x, y) - Vector2.from_angle(spin) * 0.8, spin, ln + 1.6, ln * 0.6 + 1.4, oc, oc)
		petal(b, Vector2(x, y), spin, ln, ln * 0.6, col, tip)

## 枯れた花の色（灰色がかった茶）
const WITHERED := ["#140e0a", "#241a12", "#3a2c1e", "#54402a", "#6c5636", "#86704a", "#9c8862", "#b0a07c"]

## 舞う花びら（中心 c の周り）。mode: "orbit"=回る, "burst"=外へ吹き出す（age から）, "fall"=降る（領域 c, r）
## outline の a>0 で、花びらの周りに濃い縁を付ける（小さくても形が読めるように）。
func petal_cloud(b: RBMHeroFxBatch, c: Vector2, t: float, n: int, seed_: int, radius: float, size_: float, col_a: Color, col_b: Color, alpha: float, mode: String = "orbit", squash: float = 0.45, outline: Color = Color(0, 0, 0, 0)) -> void:
	if alpha <= 0.01:
		return
	for i in range(n):
		var r1 := RBMHeroFx.r(i, seed_)
		var r2 := RBMHeroFx.r(i, seed_ + 1)
		var r3 := RBMHeroFx.r(i, seed_ + 2)
		var p := c
		var spin := t * (2.0 + r3 * 3.0) + r1 * TAU
		var fade := alpha
		match mode:
			"orbit":
				var a := r1 * TAU + t * (0.9 + r2 * 0.8)
				var rr := radius * (0.55 + 0.45 * r2)
				p = c + Vector2(cos(a) * rr, sin(a) * rr * squash + (r3 - 0.5) * radius * 0.5)
			"burst":
				var a := r1 * TAU
				var sp_ := radius * (0.4 + 0.8 * r2)
				var k := 3.2
				p = c + Vector2(cos(a), sin(a) * 0.7) * sp_ * (1.0 - exp(-k * t)) / k * 3.0 + Vector2(0, 30.0 * t * t)
				fade = alpha * (1.0 - smoothstep(0.5 + r3 * 0.6, 1.2 + r3 * 0.6, t))
			"fall":
				var q := fmod(t * (0.18 + 0.12 * r2) + r1, 1.0)
				p = c + Vector2((r3 - 0.5) * radius * 2.0 + sin(t * 1.6 + float(i)) * 10.0, -radius * 0.6 + q * radius * 1.4)
				fade = alpha * sin(q * PI)
		var col := col_a.lerp(col_b, r2)
		col.a *= fade
		var tip := col_b
		tip.a *= fade
		var ln := size_ * (0.7 + 0.6 * r3)
		if outline.a > 0.0:
			var oc := Color(outline, outline.a * fade)
			petal(b, p - Vector2.from_angle(spin) * 0.8, spin, ln + 1.6, ln * 0.6 + 1.4, oc, oc)
		petal(b, p, spin, ln, ln * 0.6, col, tip)

# --- 溶岩・煙・時計の色 ------------------------------------------------------
