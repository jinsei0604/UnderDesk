class_name RBMLionFxBase
extends RBMHeroFxBase
## 金環の聖獣／日蝕の獅皇（lion）のエフェクト1種類の土台（表示専用。戦闘の状態・乱数には触れない）。
## ヒーローのエフェクトの部品（RBMHeroFxBase の粒・爆炎・輪・柱・後処理）をそのまま使い、獅子の部品（日蝕・暗がりの目）を足す。
## 本体はキーポーズの完成した全身の絵をそのまま切り替える（pose_keys）。動きは位置の移動（move_keys）と
## 命中のヒットストップ（stops）だけ。座標は 640×360 の論理ドット（ステージの半分）。絵の画素は px() で直す。

const ORIGIN := RBMLionMotion.ORIGIN
const HOME := Vector2(390, 237)
const SHADER_ROOT := "res://src/bossmaker/visuals/lion/shaders/"
const GOLDEN := ["#2a1e0c", "#4a3412", "#7a5418", "#b07a20", "#e0a83a", "#ffd27a", "#fff1c8", "#ffffff"]
const ECLIPSE := ["#3a0f1a", "#7a1020", "#c0301c", "#f07a20", "#ffd27a", "#fff4d8"]
## 日蝕の恐ろしい色（金から移る深紅と黒）
const DREAD := ["#0a0204", "#2a0608", "#5a0c10", "#a01818", "#e0302a", "#ff8a70"]
const BLACKGOLD := ["#08060a", "#140c10", "#2a1414", "#4a1c14", "#8a2a14", "#d0601c", "#ffb040", "#fff0c0"]

## 技の名前（RBMLionMotion.MOVES）
var seq := ""
## 本体の今の状態（つなぎが読む）: pose=1始まりの番号（0＝立ち姿）, off=位置のずれ, ghosts=残像, alpha, hidden
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

## 実時間 → 演出の中の時刻（ヒットストップの間は止まる）。stops() は演出の中の秒の順に並べる。
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

## 位置: [[秒, Vector2(論理ドット), "snap" / "lin" / "out" / "in" / "inout"], ...]
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

# --- 位置 ------------------------------------------------------------------

## 今のポーズ（または pose 番目）の、測った場所（front / top / center / mark）を論理ドットで。
func at(which: String, pose: int = -1, dx: float = 0.0, dy: float = 0.0) -> Vector2:
	var p := pose if pose > 0 else int(body.get("pose", 1))
	var list: Array = RBMLionMotion.anchors().get(seq, [])
	if p >= 1 and p <= list.size():
		var a: Array = list[p - 1][which]
		return px(Vector2(float(a[0]) + dx, float(a[1]) + dy))
	return HOME

## 絵の画素 → 論理ドット（今の本体の位置で）。
func px(p: Vector2) -> Vector2:
	return HOME + Vector2(body.get("off", Vector2.ZERO)) + (p - ORIGIN)

## 残像（同じ絵を単色で薄く重ねる。形は変えない）
func ghost(pose: int, off: Vector2, alpha: float, col: Color, sil: float = 0.55) -> void:
	if alpha > 0.01:
		body["ghosts"].append({"pose": pose, "off": off.round(), "a": alpha, "col": col, "sil": sil})

# --- 図形（すべて論理ドット。三角形の配列でまとめて描く） ------------------

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

## 三日月形の斬撃（a0〜a1 の弧。両端は細く、真ん中が太い）。
func crescent(b: RBMHeroFxBatch, c: Vector2, r: float, a0: float, a1: float, w: float, col_in: Color, col_out: Color, squash: float = 1.0) -> void:
	if w <= 0.1 or (col_in.a <= 0.01 and col_out.a <= 0.01):
		return
	var segs := 20
	for i in range(segs):
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var t0 := lerpf(a0, a1, u0)
		var t1 := lerpf(a0, a1, u1)
		var w0 := sin(u0 * PI) * w
		var w1 := sin(u1 * PI) * w
		var p0 := c + Vector2(cos(t0) * r, sin(t0) * r * squash)
		var p1 := c + Vector2(cos(t1) * r, sin(t1) * r * squash)
		var q0 := c + Vector2(cos(t0) * (r - w0), sin(t0) * (r - w0) * squash)
		var q1 := c + Vector2(cos(t1) * (r - w1), sin(t1) * (r - w1) * squash)
		b.quad(p0, p1, q1, q0, col_out, col_out, col_in, col_in)

# --- 剣（登場の剣の雨・撃破の後に床に残る剣） ---------------------------------

## 剣の色: 金（登場・覚醒前の撃破）
const SWORD_GOLD := {"steel": Color("#e6ecf6"), "steel_d": Color("#8a96aa"), "core": Color("#fff1c8"), "guard": Color("#ffd27a"), "grip": Color("#4a2e18"),
	"aura_a": Color("#ff9f29"), "aura_b": Color("#ffd27a"), "aura_c": Color("#fff1c8")}
## 剣の色: 深紅（覚醒後の撃破の大剣。黒い刃に深紅の筋、金の鍔）
const SWORD_CRIMSON := {"steel": Color("#ff8a70"), "steel_d": Color("#3a1418"), "core": Color("#ffd0b0"), "guard": Color("#ffd27a"), "grip": Color("#1a0a0c"),
	"aura_a": Color("#a01818"), "aura_b": Color("#e0402a"), "aura_c": Color("#ffb080")}

## 剣（tip が地面に刺さった先端、向きは ang、長さ length、幅 wide）。刃・鍔・柄は b_body、オーラ（縁へ向かって消える帯）は加算の b_glow。
func draw_sword(b_body: RBMHeroFxBatch, b_glow: RBMHeroFxBatch, tip: Vector2, ang: float, length: float, wide: float, aura: float, alpha: float = 1.0, cols: Dictionary = SWORD_GOLD) -> void:
	if alpha <= 0.01:
		return
	var up := Vector2(sin(ang), -cos(ang))
	var side := up.orthogonal()
	var guard := tip + up * length * 0.76
	var pommel := tip + up * length
	if aura > 0.0:
		soft_band(b_glow, tip - up * 2.0, pommel + up * 4.0, wide * 4.4, Color(cols.aura_a, 0.20 * aura * alpha), Color(cols.aura_b, 0.26 * aura * alpha))
		soft_band(b_glow, tip + up * 1.0, pommel, wide * 2.4, Color(cols.aura_b, 0.30 * aura * alpha), Color(cols.aura_c, 0.30 * aura * alpha))
	# 刃（根元から先へ細くなる。中央に明るい筋）
	var base_l := guard + side * wide * 0.5
	var base_r := guard - side * wide * 0.5
	var mid := tip + up * length * 0.12
	var sd := Color(cols.steel_d, alpha)
	b_body.quad(base_l, base_r, mid - side * wide * 0.32, mid + side * wide * 0.32, sd, sd, sd, sd)
	b_body.tri(mid + side * wide * 0.32, mid - side * wide * 0.32, tip, sd, sd, sd)
	b_body.line(guard, tip + up * 3.0, maxf(1.0, wide * 0.32), Color(cols.steel, alpha), Color(cols.core, alpha))
	# 鍔・柄・柄頭
	b_body.line(guard + side * wide * 1.5, guard - side * wide * 1.5, maxf(1.5, wide * 0.42), Color(cols.guard, alpha), Color(cols.guard, alpha))
	b_body.line(guard + up * 1.0, pommel - up * wide * 0.4, maxf(1.0, wide * 0.36), Color(cols.grip, alpha), Color(cols.grip, alpha))
	disc(b_body, pommel, maxf(1.2, wide * 0.42), Color(cols.guard, alpha))

## 線の周りの柔らかい光の帯（中心の色 → 両縁で透明。a→c で色が変わる）
func soft_band(b: RBMHeroFxBatch, a: Vector2, c: Vector2, wd: float, col_a: Color, col_c: Color) -> void:
	var side := (c - a).orthogonal().normalized() * wd * 0.5
	var ta := Color(col_a, 0.0)
	var tc := Color(col_c, 0.0)
	b.quad(a, c, c + side, a + side, col_a, col_c, tc, ta)
	b.quad(a, c, c - side, a - side, col_a, col_c, tc, ta)

# --- 獅子のシェーダー -------------------------------------------------------

## 獅子のシェーダーの矩形（論理ドット）。
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

## 日蝕の光輪を center に半径 r で出す（矩形はその周りに作り直す）。
func show_eclipse(q: ColorRect, center: Vector2, r: float, corona_len: float, params: Dictionary) -> void:
	var half := r + corona_len * 1.6 + 8.0
	q.visible = true
	q.position = center - Vector2(half, half)
	q.size = Vector2(half, half) * 2.0
	var p := {"size": q.size, "center": Vector2(half, half), "radius": r, "corona": corona_len, "pal2": RBMHeroFx.pal(DREAD)}
	p.merge(params, true)
	sp(q, p)

## 暗がりに灯る目の光（機械武者の覚醒の目 rbm_musha_awakened_vfx.gd の _eye_glow と同じ形: 淡い光の輪・外側の淡い四角・
## 十字のにじみ・明るい芯）。座標は論理ドット（武者の画面の画素の半分の大きさで同じ見え方）。k は強さ（0〜1 以上）。
func eye_glow(b: RBMHeroFxBatch, at_pos: Vector2, k: float, col: Color = Color(1.0, 0.16, 0.12)) -> void:
	if k <= 0.0:
		return
	var p := at_pos.round()
	disc(b, p, 8.0, Color(col, 0.05 * k))
	disc(b, p, 3.5, Color(col, 0.10 * k))
	_sq(b, p - Vector2(3, 3), Vector2(6, 6), Color(col, 0.08 * k))
	_sq(b, p - Vector2(1.5, 1.5), Vector2(3, 3), Color(col, 0.22 * k))
	for d in [Vector2(-2.5, -0.5), Vector2(1.5, -0.5), Vector2(-0.5, -2), Vector2(-0.5, 1)]:
		_sq(b, p + d, Vector2(1, 1), Color(col, 0.45 * k))
	_sq(b, p - Vector2(0.5, 0.5), Vector2(1, 1), Color(col.lightened(0.6), minf(1.0, 1.2 * k)))

func _sq(b: RBMHeroFxBatch, pos: Vector2, size: Vector2, col: Color) -> void:
	b.quad(pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y), col, col, col, col)
