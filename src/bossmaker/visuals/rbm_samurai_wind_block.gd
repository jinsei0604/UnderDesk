extends Node2D

## 侍「カウンター成立(接触の瞬間)」専用の受け止めエフェクト。
## rbm_samurai_wind_finish.gd(巨大な風の必殺技本体)とは完全に別の、
## 接触の瞬間だけを表現する短い追加レイヤー(合計 約0.35秒)。同じ
## px/poly/stroke/_arc/_ribbon手法・同じWIND色パレットを再利用し、
## 「敵の攻撃を風の力で受け止めた」ことだけを短く表現する——風の必殺技
## 本体(巨大な風・風斬撃・着弾)のデザイン・タイミングには一切触れない。
##
## 段階構成(いずれも通常の被弾(赤フラッシュ・吹き飛び)ではなく風属性の
## カウンター成立を表現する形状・色のみで構成):
##   ①閃光(0.00-0.10): 接触点に鋭い白〜淡い青緑の閃光+放射状の風の
##     斬線8本。
##   ②風の衝撃(0.02-0.22): 侍を中心に部分的な弧3本+半円状の風の帯2本が
##     一気に広がる——完全な円形バリアにはせず、"受け止めた"という
##     非対称な広がり方にする。
##   ③残光(0.18-0.35): 刀元に小さな風の粒子が数個だけ残り、静かに
##     消えていく。

var age := -1.0
var origin := Vector2.ZERO         ## 侍の胸元(毎フレーム外部から更新)
var contact_point := Vector2.ZERO  ## 敵の拳が実際に接触する位置
var canvas_size := Vector2(1280, 720)

const CORE_WHITE = Color('#f6fbf6')
const WIND_FROST = Color('#dcf0ea')
const WIND_TEAL = Color('#8fd0bd')
const WIND_MAIN = Color('#aac68e')
const WIND_DEEP = Color('#48624a')

func px(p: Vector2, s: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.snapped(Vector2(4, 4)), s.max(Vector2(4, 4)).snapped(Vector2(4, 4))), c)

func poly(points: Array, c: Color) -> void:
	var lo := 4096.0
	var hi := -4096.0
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	for y in range(mini(0, int(lo / 4) * 4), maxi(int(canvas_size.y), int(hi) + 4), 4):
		var xs: Array[float] = []
		for i in range(points.size()):
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % points.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			px(Vector2(xs[i], y), Vector2(xs[i + 1] - xs[i], 4), c)

func stroke(a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var n: Vector2 = (b - a).normalized().orthogonal() * w * .5
	poly([a + n, b + n, b - n, a - n], c)

func _scaled(coords: Array, at: Vector2, extent: float, rot: float = 0.0) -> Array:
	var points: Array = []
	for i in range(0, coords.size(), 2):
		var p := Vector2(coords[i], coords[i + 1])
		if rot != 0.0:
			p = p.rotated(rot)
		points.append(at + p * extent)
	return points

func _arc(origin_pt: Vector2, radius: float, start_angle: float, sweep: float, reach: float, width: float, color: Color) -> void:
	var segments := 12
	var grown := clampf(reach, 0, 1) * float(segments)
	for seg in range(segments):
		var seg_u := clampf(grown - float(seg), 0, 1)
		if seg_u <= 0:
			break
		var angle_a := start_angle + sweep * float(seg) / float(segments)
		var angle_b_full := start_angle + sweep * float(seg + 1) / float(segments)
		var angle_b := lerpf(angle_a, angle_b_full, seg_u)
		var pa := origin_pt + Vector2(cos(angle_a), sin(angle_a)) * radius
		var pb := origin_pt + Vector2(cos(angle_b), sin(angle_b)) * radius
		stroke(pa, pb, width, color)

func _ribbon(origin_pt: Vector2, radius: float, start_angle: float, sweep: float, reach: float, width_start: float, width_end: float, color: Color) -> void:
	var segments := 12
	var grown := clampf(reach, 0, 1)
	var last_seg := int(ceil(grown * float(segments)))
	if last_seg <= 0:
		return
	var outer: Array = []
	var inner: Array = []
	for seg in range(last_seg + 1):
		var u := clampf(float(seg) / float(segments), 0, grown)
		var angle := start_angle + sweep * u
		var w := lerpf(width_start, width_end, u)
		var p := origin_pt + Vector2(cos(angle), sin(angle)) * radius
		var n := Vector2(cos(angle), sin(angle))
		outer.append(p + n * w * 0.5)
		inner.append(p - n * w * 0.5)
	var reversed_inner: Array = []
	for i in range(inner.size() - 1, -1, -1):
		reversed_inner.append(inner[i])
	poly(outer + reversed_inner, color)

## 侍を中心とした部分的な風の衝撃弧3本(完全な円形バリアにはしない、
## 非対称な開き方——"受け止めた"手応えを表す)。
const SHOCK_ARCS = [
	{"radius": 55.0, "start_angle": -2.6, "sweep": 2.0, "delay": 0.00, "width": 9.0},
	{"radius": 78.0, "start_angle": -3.0, "sweep": 2.4, "delay": 0.02, "width": 11.0},
	{"radius": 100.0, "start_angle": -2.2, "sweep": 1.8, "delay": 0.04, "width": 8.0},
]

## 侍を半分だけ包む風の帯2本。
const CATCH_RIBBONS = [
	{"radius": 62.0, "start_angle": -2.4, "sweep": 2.0, "delay": 0.01, "w0": 4.0, "w1": 16.0},
	{"radius": 88.0, "start_angle": -2.9, "sweep": 2.2, "delay": 0.03, "w0": 5.0, "w1": 14.0},
]

## 接触点から放射状に走る鋭い風の斬線8本(不揃いな角度・長さ)。
const CUT_LINE_ANGLES = [0.2, 1.0, 1.8, 2.6, 3.4, 4.2, 5.0, 5.8]
const CUT_LINE_LENGTHS = [26.0, 34.0, 22.0, 30.0, 24.0, 32.0, 20.0, 28.0]

## 残光の風の欠片(小さく細長い薄片)。
const RESIDUE_A = [0, -9, 5, -2, 2, 7, -4, 3]
const RESIDUE_B = [0, -7, 4, -1, 1, 5, -3, 2]

func _draw() -> void:
	if age < 0 or age > 0.35:
		return

	# ①接触点の閃光(0.00-0.10): 白い強い閃光+放射状の鋭い風の斬線8本。
	if age < 0.10:
		var flash_fade := 1.0 - age / 0.10
		var flash_grow := 1.0 - pow(1.0 - clampf(age / 0.045, 0, 1), 2)
		px(contact_point - Vector2(1, 1) * 38.0 * flash_grow, Vector2(76, 76) * flash_grow, CORE_WHITE * Color(1, 1, 1, flash_fade * 0.95))
		px(contact_point - Vector2(1, 1) * 20.0 * flash_grow, Vector2(40, 40) * flash_grow, WIND_FROST * Color(1, 1, 1, flash_fade))
		for i in range(CUT_LINE_ANGLES.size()):
			var a: float = CUT_LINE_ANGLES[i]
			var reach_len: float = CUT_LINE_LENGTHS[i] * flash_grow
			var dir := Vector2(cos(a), sin(a) * 0.85)
			var tip := contact_point + dir * reach_len
			stroke(contact_point, tip, 5.0, (CORE_WHITE if i % 2 == 0 else WIND_TEAL) * Color(1, 1, 1, flash_fade))

	# ②侍を中心とした風の衝撃(0.02-0.22): 部分的な弧3本+半円状の帯2本。
	for arc in SHOCK_ARCS:
		var delay: float = arc["delay"]
		var t := age - delay
		if t < 0 or t > 0.20:
			continue
		var reach: float = clampf(t / 0.05, 0, 1)
		var fade: float = clampf(1.0 - (t - 0.06) / 0.14, 0, 1)
		if fade <= 0.001:
			continue
		var w: float = arc["width"]
		_arc(origin, float(arc["radius"]), float(arc["start_angle"]), float(arc["sweep"]), reach, w + 4.0, WIND_DEEP * Color(1, 1, 1, fade * 0.6))
		_arc(origin, float(arc["radius"]), float(arc["start_angle"]), float(arc["sweep"]), reach, w, WIND_MAIN * Color(1, 1, 1, fade))
		_arc(origin, float(arc["radius"]), float(arc["start_angle"]), float(arc["sweep"]), reach, w * 0.4, CORE_WHITE * Color(1, 1, 1, fade * 0.9))

	for ribbon in CATCH_RIBBONS:
		var delay2: float = ribbon["delay"]
		var t2 := age - delay2
		if t2 < 0 or t2 > 0.18:
			continue
		var reach2: float = clampf(t2 / 0.06, 0, 1)
		var fade2: float = clampf(1.0 - (t2 - 0.07) / 0.11, 0, 1)
		if fade2 <= 0.001:
			continue
		_ribbon(origin, float(ribbon["radius"]), float(ribbon["start_angle"]), float(ribbon["sweep"]), reach2, float(ribbon["w0"]), float(ribbon["w1"]), WIND_TEAL * Color(1, 1, 1, fade2 * 0.6))

	# ③残光(0.18-0.35): 刀元に小さな風の粒子が数個だけ残り、消えていく。
	if age >= 0.18 and age < 0.35:
		var rt := (age - 0.18) / 0.17
		var res_fade := 1.0 - rt
		for i in range(5):
			var seed := float(i) * 2.399 + 1.0
			var dir4 := Vector2(cos(seed * 1.7), sin(seed * 1.7) * 0.7 - 0.3)
			var p4 := origin + dir4 * (14.0 + rt * 30.0) + Vector2(0, -6.0 * rt)
			var shape4 := RESIDUE_A if i % 2 == 0 else RESIDUE_B
			poly(_scaled(shape4, p4, 0.8 + fmod(seed, 0.4), dir4.angle() + PI * 0.5), (WIND_FROST if i % 2 == 0 else WIND_MAIN) * Color(1, 1, 1, res_fade))
