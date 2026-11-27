class_name RBMDragonFxBase
extends RBMHeroFxBase
## 竜（翠鱗の竜／覚醒後）の攻撃のエフェクト1種類の土台（2026-11-26 ユーザー承認。表示専用。戦闘の状態・乱数には触れない）。
## ヒーローのエフェクトの部品（RBMHeroFxBase の粒・爆炎・輪・帯・後処理）を使い、竜の部品（息吹の帯・段階色）を足す。
## 座標はステージの2分の1の論理ドット（ワールド）。竜の絵は host（rbm_dragon_attack_host.gd）が描き、口・目・足元の位置だけを受け取る。

## 技の属性（攻撃の段階色を決める）と、覚醒後かどうか
var attr := "NEUTRAL"
var awakened := false
## host が毎コマ入れる位置（ワールド）
var mouth := Vector2.ZERO
var eye := Vector2.ZERO
var home := Vector2.ZERO
## 相手の数（targets の先頭から）
var count := 4

## 属性ごとの段階色（0=冷えた煙 … 7=白）。覚醒後は暗い側を黒紅にする。
const RAMPS := {
	"FIRE": ["#1c1418", "#3a2226", "#7a1f1a", "#c8361c", "#f0641e", "#ff9f29", "#ffd27a", "#fff4d8"],
	"ICE": ["#141a26", "#1d2a44", "#1f4a8c", "#2f78d8", "#509cf5", "#8cc8ff", "#cdeaff", "#ffffff"],
	"LIGHTNING": ["#1c1a14", "#33301c", "#6a5214", "#b88a1c", "#f2cd55", "#ffe38a", "#fff4c4", "#ffffff"],
	"WIND": ["#141c14", "#1f3320", "#2f5e1c", "#5ea42a", "#a4f255", "#ccff8a", "#ecffcc", "#ffffff"],
	"NEUTRAL": ["#16161c", "#2a2a34", "#4a4c58", "#7c808c", "#b7bbc2", "#d6d9de", "#eef0f2", "#ffffff"],
}
const DARK_LOW := ["#05030a", "#1c0a22", "#5a0e30"]

func ramp8() -> Array:
	var r: Array = (RAMPS.get(attr, RAMPS["NEUTRAL"]) as Array).duplicate()
	if awakened:
		for i in range(3):
			r[i] = DARK_LOW[i]
	return r

## 段階色を Color にしたもの（属性・覚醒後かどうかが変わった時だけ作り直す）。
## 2026-11-27 重さの改善: col() は1コマに百回以上呼ばれ、そのたびに表の複製と文字列からの色の読み取りをしていた（CPU）。色は同じ。
var _cols: Array[Color] = []
var _cols_key := ""

func col(i: int, a: float = 1.0) -> Color:
	var key := attr + ("+" if awakened else "-")
	if key != _cols_key:
		_cols_key = key
		_cols.clear()
		for h in ramp8():
			_cols.append(Color(str(h)))
	var c: Color = _cols[clampi(i, 0, 7)]
	c.a = a
	return c

## 技の長さ・命中・相手ごとの当たり（[時刻, 相手の番号]）
func duration() -> float:
	return 2.0

func impact() -> float:
	return 1.0

func hits() -> Array:
	return []

## 何回も当たる攻撃: {相手の番号: [途中の当たりの時刻]}（最後の一撃 impact() は含めない）と、最後の一撃の割合
func multi_plan() -> Dictionary:
	return {}

func final_share() -> float:
	return 0.4

## 技の途中で鳴らす音: [[時刻, 音の名前, 音量dB], ...]（演出の時間に合わせて host が鳴らす）
func sounds() -> Array:
	return []

## 体の状態: {pose, off（足元からのずれ・ステージの画素）, scale, hidden, ghosts:[{pose, off, a, col}], flash, sil}
func body_at(_t: float) -> Dictionary:
	return {"pose": 0, "off": Vector2.ZERO, "scale": Vector2.ONE}

## 円（輪郭の線だけ）。batch に足す。
func circle_line(b: RBMHeroFxBatch, c: Vector2, r: float, w: float, col_: Color, segs: int = 28, squash: float = 1.0) -> void:
	if r <= 0.5 or col_.a <= 0.0:
		return
	var prev := c + Vector2(r, 0)
	for i in range(1, segs + 1):
		var th := TAU * float(i) / segs
		var p := c + Vector2(cos(th) * r, sin(th) * r * squash)
		b.line(prev, p, w, col_, col_)
		prev = p

## 塗りの楕円（三角形の扇）。
func disc(b: RBMHeroFxBatch, c: Vector2, rx: float, ry: float, col_: Color, edge: Color = Color(0, 0, 0, -1), segs: int = 20) -> void:
	if rx <= 0.3 or col_.a <= 0.0:
		return
	var e := edge if edge.a >= 0.0 else col_
	var prev := c + Vector2(rx, 0)
	for i in range(1, segs + 1):
		var th := TAU * float(i) / segs
		var p := c + Vector2(cos(th) * rx, sin(th) * ry)
		b.tri(c, prev, p, col_, e, e)
		prev = p

## 息吹の帯（shaders/dragon_breath.gdshader）を、口から dir の向きへ長さ length・高さ height で置く。
func breath_strip(parent: Node2D, pal_hex: Array, params: Dictionary = {}) -> ColorRect:
	var root := Node2D.new()
	parent.add_child(root)
	var q := ColorRect.new()
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://src/bossmaker/visuals/dragon/shaders/dragon_breath.gdshader")
	q.material = m
	q.visible = false
	root.add_child(q)
	sp(q, {"pal": RBMHeroFx.pal(pal_hex)})
	sp(q, params)
	return q

func place_strip(q: ColorRect, from: Vector2, dir: Vector2, length: float, height: float) -> void:
	var root := q.get_parent() as Node2D
	root.position = from
	root.rotation = dir.angle()
	q.position = Vector2(0, -height * 0.5)
	q.size = Vector2(length, height)
	sp(q, {"aspect": length / maxf(height, 1.0)})

## 黒い稲妻（黒い芯＋紅い光）。glow は加算の batch、core は普通の batch。
func black_bolt(glow_b: RBMHeroFxBatch, core_b: RBMHeroFxBatch, a: Vector2, c: Vector2, seed_: int, wide: float, power: float, glow_col: Color = Color("#ed274c"), segs: int = 10, amp: float = 0.22, branch: bool = true) -> void:
	if power <= 0.0:
		return
	var g := Color("#a0132f")
	g.a = 0.8 * power
	var g2 := glow_col
	g2.a = 0.75 * power
	var k := Color("#05030a")
	k.a = power
	var d := c - a
	var nv := Vector2(-d.y, d.x).normalized()
	var length := d.length()
	var prev := a
	for i in range(1, segs + 1):
		var u := float(i) / segs
		var p := a + d * u
		if i < segs:
			p += nv * (RBMHeroFx.r(i, seed_) - 0.5) * 2.0 * amp * length * sin(u * PI)
		# 紅い光（外側だけ）→ 黒い芯（太め）。芯が細いと桃色の稲妻に見えるので、芯を光の半分の太さにする
		glow_b.line(prev, p, wide * 3.4, g, g)
		glow_b.line(prev, p, wide * 2.2, g2, g2)
		core_b.line(prev, p, wide * 1.6, k, k)
		if branch and i % 3 == 1 and i < segs:
			var th := d.angle() + (RBMHeroFx.r(i, seed_ + 5) - 0.5) * 2.2
			black_bolt(glow_b, core_b, p, p + Vector2.from_angle(th) * length * (0.18 + 0.2 * RBMHeroFx.r(i, seed_ + 9)), seed_ + i * 7, wide * 0.6, power, glow_col, 4, amp, false)
		prev = p
