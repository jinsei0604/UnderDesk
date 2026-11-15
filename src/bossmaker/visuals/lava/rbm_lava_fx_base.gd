class_name RBMLavaFxBase
extends RBMHeroFxBase
## 熔鉱炉の番人／噴界炉の巨神（lava）のエフェクト1種類の土台（表示専用。戦闘の状態・乱数には触れない）。
## ヒーローのエフェクトの部品（RBMHeroFxBase の粒・爆炎・輪・柱・後処理）をそのまま使い、溶岩の部品（溶岩の溜まり magma・液体の溶岩 molten・噴火の柱 eruption・火口 caldera・溶岩の塊と飛沫・暗がりの目）を足す。
## 2026-11-11〜16 の試作（prototypes/four_bosses_2026-11-11/scripts/proto_fx.gd）でユーザーが採用した部品を、このボスが使う物だけ移した。
## 本体はキーポーズの完成した全身の絵をそのまま切り替える（pose_keys）。動きは位置の移動（move_keys）と
## 命中のヒットストップ（stops）だけ。座標は 640×360 の論理ドット（ステージの半分）。絵の画素は px() で直す。
## 他の技のキーポーズを借りる技（支援・登場・撃破）は extra_poses() に {番号: [技, 何枚目]} を書く（借りた絵の場所は at_seq()）。

const ORIGIN := RBMLavaMotion.ORIGIN
const HOME := Vector2(390, 237)
const SHADER_ROOT := "res://src/bossmaker/visuals/lava/shaders/"

## ボスの名前（試作の部品の書き方のまま）
var boss := "lava"
## 技の名前（RBMLavaMotion.MOVES。支援・登場・撃破は借りた絵の技）
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
	var list: Array = RBMLavaMotion.anchors().get(seq_name, [])
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

## 溶岩（shaders/magma.gdshader。2026-11-13 溶岩の巨人の作り直し）。色は LAVA（暗→明の8色）。
func magma_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	var p := {"pal": RBMHeroFx.pal(LAVA), "seed": 1.0}
	p.merge(params, true)
	return pquad(parent, Rect2(0, 0, 10, 10), "magma", p)

## 地面に広がる溶岩溜まり（c に半径 r、squash で寝かせる）。params: crust（冷え 0〜1）・heat・flow・fade
func show_pool(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	if r <= 0.5:
		q.visible = false
		return
	var sq := float(params.get("squash", 0.32))
	var half := Vector2(r * 1.25 + 4.0, r * sq * 1.25 + 4.0)
	q.visible = true
	q.position = c - half
	q.size = half * 2.0
	var p := {"size": q.size, "center": half, "radius": r, "mode": 0, "squash": sq, "front": -100000.0, "rim_hot": 1.0, "sphere": 0.0}
	p.merge(params, true)
	# 流れる先端（世界の x）→ 矩形の中の x
	if params.has("front_world"):
		p["front"] = float(params["front_world"]) - q.position.x
		p.erase("front_world")
	sp(q, p)

## 溶岩の柱・奔流（base から d の向きへ reach×grow、太さ wd）。params: flow・heat・fade
func show_jet(q: ColorRect, base: Vector2, d: Vector2, reach: float, wd: float, grow: float, params: Dictionary = {}) -> void:
	if grow <= 0.0:
		q.visible = false
		return
	var dn := d.normalized()
	var tip := base + dn * reach * grow
	var pad := wd * 2.6 + 6.0
	var lo := Vector2(minf(base.x, tip.x), minf(base.y, tip.y)) - Vector2(pad, pad)
	var hi := Vector2(maxf(base.x, tip.x), maxf(base.y, tip.y)) + Vector2(pad, pad)
	q.visible = true
	q.position = lo
	q.size = hi - lo
	var p := {"size": q.size, "center": base - lo, "mode": 1, "dir": dn, "reach": reach, "grow": grow, "width": wd}
	p.merge(params, true)
	sp(q, p)

## 落ちてくる溶岩の塊（from から to へ放物線。age 0〜life で着地。暗い殻と光る割れ目、尾を引く）
func lava_bomb(b_body: RBMHeroFxBatch, b_glow: RBMHeroFxBatch, from: Vector2, to: Vector2, age: float, life: float, size_: float, arc: float = 120.0) -> void:
	if age < 0.0 or age > life:
		return
	var u := age / life
	var p := from.lerp(to, u) + Vector2(0, -arc * 4.0 * u * (1.0 - u))
	var u0 := maxf(0.0, u - 0.08)
	var p0 := from.lerp(to, u0) + Vector2(0, -arc * 4.0 * u0 * (1.0 - u0))
	b_glow.streak(p0 - (p - p0) * 2.0, p, size_ * 1.4, Color("#f07a20", 0.0), Color("#ffb040", 0.8))
	disc(b_glow, p, size_ * 2.0, Color("#ff9a24", 0.35))
	disc(b_body, p, size_ + 1.0, Color("#1a1210"))
	disc(b_body, p, size_, Color("#3a2018"))
	disc(b_body, p + Vector2(-size_ * 0.3, -size_ * 0.3), size_ * 0.5, Color("#ffb040"))
	b_body.line(p + Vector2(-size_ * 0.6, 0), p + Vector2(size_ * 0.5, size_ * 0.3), 1.0, Color("#ffe08a"), Color("#f07a20"))

## 溶岩の飛沫（しずく形。飛ぶ向きに伸び、濃い縁と明るい芯。2026-11-14 溶岩の巨人の質を上げる）
func lava_drops(b: RBMHeroFxBatch, o: Vector2, age: float, life: float, n: int, seed_: int, speed: float, size_: float, ang: float = -PI * 0.5, spread: float = PI, grav: float = 320.0) -> void:
	if age < 0.03 or age > life:
		return
	var f := (1.0 - smoothstep(life * 0.6, life, age)) * smoothstep(0.03, 0.07, age)
	for i in range(n):
		var th := ang + (RBMHeroFx.r(i, seed_) - 0.5) * spread
		var v := speed * (0.35 + 0.65 * RBMHeroFx.r(i, seed_ + 1))
		var d := Vector2.from_angle(th)
		var vel := d * v + Vector2(0, grav * age)
		# 出た瞬間に全部が同じ点に重なって花・星の形に見えないよう、少し外から出す（2026-11-14 指摘「ボスの中心に変なマーク」）
		var p := o + d * (v * age + size_ * 3.0) + Vector2(0, 0.5 * grav * age * age)
		var sz := size_ * (0.6 + 0.8 * RBMHeroFx.r(i, seed_ + 2))
		var ln := sz * (1.4 + minf(2.0, vel.length() / 220.0))
		var a := vel.angle() + PI
		petal(b, p - Vector2.from_angle(a) * 0.6, a, ln + 1.6, sz + 1.4, Color("#1a1210", f), Color("#1a1210", f))
		petal(b, p, a, ln, sz, Color("#ffd870", f), Color("#c84a1c", f))
		disc(b, p + Vector2.from_angle(a) * sz * 0.3, sz * 0.32, Color("#fff6d8", f))

## 溶岩の流れの帯（p0 → p1 の二次曲線。濃い縁・赤橙・黄色の芯・流れる明るい粒）。grow まで伸びる。先の位置を返す。
func lava_ribbon(b: RBMHeroFxBatch, p0: Vector2, ctrl: Vector2, p1: Vector2, grow: float, width: float, t: float, fade: float = 1.0) -> Vector2:
	if grow <= 0.0 or fade <= 0.0:
		return p0
	var steps := 24
	var last := int(ceil(steps * clampf(grow, 0.0, 1.0)))
	var pts: Array = []
	for i in range(last + 1):
		var u := minf(float(i) / steps, grow)
		var wob := sin(u * 14.0 - t * 9.0) * width * 0.12
		var p := p0.lerp(ctrl, u).lerp(ctrl.lerp(p1, u), u)
		var dd := (ctrl.lerp(p1, u) - p0.lerp(ctrl, u)).normalized()
		pts.append(p + dd.orthogonal() * wob)
	for pass_i in range(3):
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var c: Vector2 = pts[i]
			var u := float(i) / steps
			var wv := width * (0.75 + 0.25 * sin(u * 9.0 + t * 6.0))
			match pass_i:
				0: b.line(a, c, wv + 2.4, Color("#1a1210", fade), Color("#1a1210", fade))
				1: b.line(a, c, wv, Color("#a0301a", fade), Color("#f07a20", fade))
				2: b.line(a, c, maxf(1.0, wv * 0.42), Color("#ffd870", fade), Color("#ffb040", fade))
	for k in range(6):
		var q := fmod(t * 1.6 + k / 6.0, 1.0)
		var idx := int(q * (pts.size() - 1))
		if idx < pts.size():
			disc(b, pts[idx], width * 0.3, Color("#fff6d8", 0.9 * fade))
	return pts[-1]

## 溶岩の玉（magma.gdshader の溜まりを丸く。表面に冷えた岩の板と光る割れ目）
func show_lava_ball(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	var p := {"squash": 1.0, "rim_hot": 0.15, "sphere": 1.0}
	p.merge(params, true)
	show_pool(q, c, r, p)

## 溶けた溶岩の液体（shaders/molten.gdshader。2026-11-14 網目の模様をやめた溶岩）。balls は世界の [Vector4(x, y, 半径, 熱)]。
func molten_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	var p := {"pal": RBMHeroFx.pal(LAVA), "seed": 1.0}
	p.merge(params, true)
	return pquad(parent, Rect2(0, 0, 10, 10), "molten", p)

func show_molten(q: ColorRect, balls: Array, params: Dictionary = {}) -> void:
	if balls.is_empty():
		q.visible = false
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in balls:
		var bv: Vector4 = b
		var m := bv.z * 2.4 + 4.0
		lo = Vector2(minf(lo.x, bv.x - m), minf(lo.y, bv.y - m))
		hi = Vector2(maxf(hi.x, bv.x + m), maxf(hi.y, bv.y + m))
	q.visible = true
	q.position = lo
	q.size = hi - lo
	var arr := PackedVector4Array()
	for b in balls:
		var bv: Vector4 = b
		if arr.size() >= 32:
			break
		arr.append(Vector4(bv.x - lo.x, bv.y - lo.y, bv.z, bv.w))
	var count := arr.size()
	while arr.size() < 32:
		arr.append(Vector4.ZERO)
	var p := {"size": q.size, "balls": arr, "count": count}
	p.merge(params, true)
	sp(q, p)

## 噴火の柱（shaders/eruption.gdshader）。色は黒煙 → 白の8色。
const ERUPT := ["#141012", "#2a1c1c", "#6a1e10", "#b8380e", "#f0701a", "#ffb040", "#ffe48a", "#fff8e0"]

func eruption_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	var p := {"pal": RBMHeroFx.pal(ERUPT), "seed": 1.0}
	p.merge(params, true)
	return pquad(parent, Rect2(0, 0, 10, 10), "eruption", p)

func show_eruption(q: ColorRect, base_pos: Vector2, wd: float, height: float, grow: float, params: Dictionary = {}) -> void:
	if grow <= 0.0:
		q.visible = false
		return
	var h := height * grow
	var lo := Vector2(base_pos.x - wd * 3.4 - 8.0, base_pos.y - h - wd * 2.4 - 8.0)
	# soft_base（根元を地面の楕円の縁に沿わせる）の時は下へはみ出す分も入れる（四角の下端で切れないように）
	var hi := Vector2(base_pos.x + wd * 3.4 + 8.0, base_pos.y + 6.0 + float(params.get("soft_base", 0.0)) * wd * 0.62)
	q.visible = true
	q.position = lo
	q.size = hi - lo
	var p := {"size": q.size, "base": base_pos - lo, "width": wd, "height": height, "grow": grow}
	p.merge(params, true)
	sp(q, p)

## 火口（shaders/caldera.gdshader）
func caldera_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	var p := {"pal": RBMHeroFx.pal(LAVA), "seed": 1.0}
	p.merge(params, true)
	return pquad(parent, Rect2(0, 0, 10, 10), "caldera", p)

func show_caldera(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	if r <= 1.0:
		q.visible = false
		return
	var sq := float(params.get("squash", 0.3))
	var half := Vector2(r * 1.7 + 6.0, r * sq * 1.7 + 6.0)
	q.visible = true
	q.position = c - half
	q.size = half * 2.0
	var p := {"size": q.size, "center": half, "radius": r}
	p.merge(params, true)
	sp(q, p)

const LAVA := ["#1a1210", "#3a2018", "#6a2a14", "#b0401a", "#f07a20", "#ffb040", "#ffe08a", "#fff8e0"]

const SMOKE := ["#141214", "#1e1a1c", "#2a2426", "#363032", "#433c3e", "#514a4c", "#5e5658", "#6c6466"]

## 暗がりに灯る目の光（機械武者の覚醒・登場の目と同じ形: 淡い光の輪・外側の淡い四角・十字のにじみ・明るい芯）。
## 座標は論理ドット（武者の画面の画素の半分の大きさで同じ見え方）。k は強さ（0〜1 以上）。b は通常の重ね方のまとめ描き。
func eye_glow(b: RBMHeroFxBatch, at: Vector2, k: float, col: Color = Color(1.0, 0.16, 0.12)) -> void:
	if k <= 0.0:
		return
	var p := at.round()
	disc(b, p, 8.0, Color(col, 0.05 * k))
	disc(b, p, 3.5, Color(col, 0.10 * k))
	_sq(b, p - Vector2(3, 3), Vector2(6, 6), Color(col, 0.08 * k))
	_sq(b, p - Vector2(1.5, 1.5), Vector2(3, 3), Color(col, 0.22 * k))
	for d in [Vector2(-2.5, -0.5), Vector2(1.5, -0.5), Vector2(-0.5, -2), Vector2(-0.5, 1)]:
		_sq(b, p + d, Vector2(1, 1), Color(col, 0.45 * k))
	_sq(b, p - Vector2(0.5, 0.5), Vector2(1, 1), Color(col.lightened(0.6), minf(1.0, 1.2 * k)))

func _sq(b: RBMHeroFxBatch, pos: Vector2, size: Vector2, col: Color) -> void:
	b.quad(pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y), col, col, col, col)
