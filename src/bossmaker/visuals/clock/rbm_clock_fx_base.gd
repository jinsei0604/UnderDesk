class_name RBMClockFxBase
extends RBMHeroFxBase
## 振り子の給仕長／終刻の給仕長（clock）のエフェクト1種類の土台（表示専用。戦闘の状態・乱数には触れない）。
## ヒーローのエフェクトの部品（RBMHeroFxBase の粒・爆炎・輪・柱・後処理）をそのまま使い、時計の部品（厚みのある懐中時計の文字盤 dial・真鍮の歯車 gear・ブレゲ針・ガラスのかけら・時が止まる見た目・振り子）を足す。
## 2026-11-11〜16 の試作（prototypes/four_bosses_2026-11-11/scripts/proto_fx.gd）でユーザーが採用した部品を、このボスが使う物だけ移した。
## 本体はキーポーズの完成した全身の絵をそのまま切り替える（pose_keys）。動きは位置の移動（move_keys）と
## 命中のヒットストップ（stops）だけ。座標は 640×360 の論理ドット（ステージの半分）。絵の画素は px() で直す。
## 他の技のキーポーズを借りる技（支援・登場・撃破）は extra_poses() に {番号: [技, 何枚目]} を書く（借りた絵の場所は at_seq()）。

const ORIGIN := RBMClockMotion.ORIGIN
const HOME := Vector2(390, 237)
const SHADER_ROOT := "res://src/bossmaker/visuals/clock/shaders/"

## ボスの名前（試作の部品の書き方のまま）
var boss := "clock"
## 技の名前（RBMClockMotion.MOVES。支援・登場・撃破は借りた絵の技）
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
	var list: Array = RBMClockMotion.anchors().get(seq_name, [])
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

const BRASS_PAL := ["#2a2014", "#4a3a20", "#7a6030", "#b08a48", "#d8b468", "#f0d890", "#fff4d0", "#ffffff"]

## 懐中時計の文字盤（shaders/clockface.gdshader）。show_dial で中心・半径を決める。
func dial_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	return pquad(parent, Rect2(0, 0, 10, 10), "clockface", params)

func show_dial(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	if r <= 2.0 or float(params.get("fade", 1.0)) <= 0.003:
		q.visible = false
		return
	var half := Vector2(r * 1.45 + 6.0, r * 1.45 + 12.0)
	q.visible = true
	q.position = (c - half).round()
	q.size = (half * 2.0).round()
	var p := {"size": q.size, "center": c - q.position, "r": r}
	p.merge(params, true)
	sp(q, p)

## 真鍮の歯車（shaders/gear.gdshader）。
func gear_quad(parent: Node, params: Dictionary = {}) -> ColorRect:
	return pquad(parent, Rect2(0, 0, 10, 10), "gear", params)

func show_gear(q: ColorRect, c: Vector2, r: float, params: Dictionary = {}) -> void:
	if r <= 2.0 or float(params.get("fade", 1.0)) <= 0.003:
		q.visible = false
		return
	var half := Vector2(r + 12.0, r + 12.0)
	q.visible = true
	q.position = (c - half).round()
	q.size = (half * 2.0).round()
	var p := {"size": q.size, "center": c - q.position, "r": r}
	p.merge(params, true)
	sp(q, p)

## ブレゲ針（時計の針の形の刃）: 根元 base から tip へ。先の手前に丸い輪（尖った矢にしない）。濃い輪郭つき。
## b_line: 輪郭（通常の重ね）、b_metal: 本体（通常の重ね）。cols = [暗い金属, 明るい金属, 輪郭]
func breguet_hand(b_line: RBMHeroFxBatch, b_metal: RBMHeroFxBatch, base: Vector2, tip: Vector2, w: float, cols: Array, alpha: float = 1.0) -> void:
	if alpha <= 0.01 or base.distance_to(tip) < 2.0:
		return
	var dir := (tip - base).normalized()
	var n := Vector2(-dir.y, dir.x)
	var L := base.distance_to(tip)
	var moon := base + dir * L * 0.74
	var mr := maxf(2.2, w * 1.5)
	var dk := Color(cols[0], alpha)
	var lt := Color(cols[1], alpha)
	var ln := Color(cols[2], alpha)
	# 輪郭（ひと回り大きく）
	var o := 1.0
	b_line.quad(base - dir * (w + o) - n * (w + o), base - dir * (w + o) + n * (w + o), moon - dir * mr + n * (w * 0.7 + o), moon - dir * mr - n * (w * 0.7 + o), ln, ln, ln, ln)
	b_line.quad(moon + dir * mr - n * (w * 0.6 + o), moon + dir * mr + n * (w * 0.6 + o), tip + dir * o + n * o * 0.5, tip + dir * o - n * o * 0.5, ln, ln, ln, ln)
	ring_line(b_line, moon, mr, 2.0 + o * 2.0, ln)
	# 本体（光の側が明るい）
	b_metal.quad(base - dir * w - n * w, base - dir * w + n * w, moon - dir * mr + n * w * 0.7, moon - dir * mr - n * w * 0.7, dk, lt, lt, dk)
	b_metal.quad(moon + dir * mr - n * w * 0.6, moon + dir * mr + n * w * 0.6, tip + n * 0.3, tip - n * 0.3, dk, lt, lt, dk)
	ring_line(b_metal, moon, mr, 1.6, lt, 1.0, 0.0, TAU, dk)

## 文字盤のガラスと真鍮のかけら（shards と同じ飛び方。三角を作らず4〜5角だけ＝尖って見せない）。
## age は呼び出し側で止められる（止まった時の中で空中に浮いたままのかけら）。
func glass_shards(b: RBMHeroFxBatch, o: Vector2, age: float, life: float, n: int, seed_: int, speed: float, size_: float, lit: Color, dark: Color, grav: float = 220.0, ang: float = 0.0, spread: float = TAU) -> void:
	if age < 0.0 or age > life:
		return
	for i in range(n):
		var li := life * (0.55 + 0.45 * RBMHeroFx.r(i, seed_ + 1))
		if age > li:
			continue
		var q := age / li
		var th := ang + (RBMHeroFx.r(i, seed_) - 0.5) * spread
		var sp_ := speed * (0.35 + 0.65 * RBMHeroFx.r(i, seed_ + 3))
		var dir := Vector2.from_angle(th)
		var k := 3.4
		var p := o + dir * (6.0 + 20.0 * RBMHeroFx.r(i, seed_ + 7)) + dir * sp_ * (1.0 - exp(-k * age)) / k + Vector2(0, grav * age * age)
		var sz := size_ * (0.45 + 0.85 * RBMHeroFx.r(i, seed_ + 4)) * (1.0 - q * q) * RBMHeroFx.ramp(age, 0.0, 0.05)
		b.shard(p, sz, age * (3.0 + 6.0 * RBMHeroFx.r(i, seed_ + 5)) * (1 if i % 2 == 0 else -1), i * 3 + 1 + (i % 2), lit, dark)

## 時が止まる見た目（色が抜ける・冷たい周辺減光・わずかな色ずれ）。stopped 0〜1。
func time_stop_post(stopped: float, extra: Dictionary = {}) -> void:
	if stopped <= 0.001 and extra.is_empty():
		return
	var v := {"desat": 0.88 * stopped, "vig": 0.38 * stopped, "vig_col": Vector3(.0, .05, .07), "vig_r": .3, "chroma": 0.0015 * stopped}
	v.merge(extra, true)
	set_post(v)

## 時が止まる瞬間に画面を横切る、巨大な半透明の秒針（画面の上の外の軸から振り下ろす）。k 0〜1 で振り抜く。
func sweep_hand(b: RBMHeroFxBatch, k: float, col: Color, from_ang: float = -0.95, to_ang: float = 0.95, pivot: Vector2 = Vector2(320, -210)) -> void:
	if k <= 0.0 or k >= 1.0:
		return
	var a := lerpf(from_ang, to_ang, k * k * (3.0 - 2.0 * k))
	var f := sin(PI * k)
	for j in range(4):
		var aj := a - float(j) * 0.035
		var dir := Vector2(sin(aj), cos(aj))
		var n := Vector2(-dir.y, dir.x)
		var w := 5.0 - float(j)
		var c := Color(col, col.a * f * (1.0 - 0.25 * j))
		b.quad(pivot + n * w, pivot - n * w, pivot + dir * 640.0 - n * 1.0, pivot + dir * 640.0 + n * 1.0, c, c, Color(c, 0.0), Color(c, 0.0))

## 振り子: pivot から角度 ang（0＝真下、正で右へ）に長さ length の棒と、真鍮のおもり（dial_quad の plain=1）。
## 返り値はおもりの中心。棒は濃い輪郭と真鍮の2本の線。
func pendulum(b_line: RBMHeroFxBatch, b_metal: RBMHeroFxBatch, bob: ColorRect, pivot: Vector2, length: float, ang: float, bob_r: float, alpha: float = 1.0, params: Dictionary = {}) -> Vector2:
	var dir := Vector2(sin(ang), cos(ang))
	var c := pivot + dir * length
	if alpha <= 0.01:
		bob.visible = false
		return c
	var n := Vector2(-dir.y, dir.x)
	var ln := Color("#0e0a08", alpha)
	b_line.quad(pivot - n * 2.4, pivot + n * 2.4, c + n * 2.4, c - n * 2.4, ln, ln, ln, ln)
	b_metal.quad(pivot - n * 1.2, pivot + n * 1.2, c + n * 1.2, c - n * 1.2, Color("#7a5a24", alpha), Color("#f0d080", alpha), Color("#f0d080", alpha), Color("#7a5a24", alpha))
	var p := {"plain": 1.0, "squash": 1.0, "rot": -ang, "fade": alpha}
	p.merge(params, true)
	show_dial(bob, c, bob_r, p)
	return c
