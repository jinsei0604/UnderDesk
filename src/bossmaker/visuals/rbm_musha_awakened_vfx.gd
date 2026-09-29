extends Node2D
## 覚醒/覚醒後攻撃の前面VFX(承認済みv4試作のfront.gdの描画を移植)。数値・発火時刻は
## 変更していない。白い棒状/発光する刀軌跡や遠方へ飛ぶ斬撃波は描かない。頂点は2px
## 単位に丸めアンチエイリアス無し。表示専用: 確定済みの対象位置と経過時間だけを読む。
##
## 持続オーラ(覚醒後に本体を包み続けるもの)はここではなくrbm_musha_aura.gdに
## 独立している。wind_release()(覚醒の瞬間的な風圧解放)はオーラとは無関係。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")

## "awakening" | "single" | "all"
var kind := "awakening"
var age := 0.0
## 属性色(細い外縁と着弾の衝撃だけに使う)。
var tint := Color.WHITE
var home := Vector2.ZERO
## 単体の着弾中心(対象の胴)/全体の中心(対象群から求めた点)。
var hit_at := Vector2.ZERO
var center := Vector2.ZERO
## 実際の戦闘領域(全画面の暗転・閃光の矩形)。
var screen := Rect2(0, 0, 1280, 720)
## 毛筆の中心(画面右上)。技名が読めるよう、背後に薄い明色の下地を敷く。
var brush_at := Vector2.ZERO

func advance(t: float) -> void:
	age = t
	queue_redraw()

func col(alpha: float = 1.0) -> Color:
	var c := tint
	c.a = alpha
	return c

func _cover() -> Rect2:
	return Rect2(screen.position - Vector2(80, 80), screen.size + Vector2(160, 160))

func poly(points: Array, c: Color) -> void:
	var p := PackedVector2Array()
	for v in points:
		p.append(Vector2(v).snapped(Vector2(2, 2)))
	if Geometry2D.triangulate_polygon(p).size() > 0:
		draw_colored_polygon(p, c)

func ring(at: Vector2, r: float, c: Color, w: float, flat: float = 1.0) -> void:
	var p := PackedVector2Array()
	for i in range(97):
		var a := i * TAU / 96.0
		p.append((at + Vector2(cos(a), sin(a) * flat) * r).snapped(Vector2(2, 2)))
	draw_polyline(p, c, maxf(2.0, w), false)

func cloud(at: Vector2, r: float, c: Color) -> void:
	var p: Array = []
	for i in range(16):
		var a := i * TAU / 16.0
		p.append(at + Vector2(cos(a), sin(a)) * (r * (.80 + .20 * sin(i * 8.3))))
	poly(p, c)

## 一本のテーパーした風の帯(半透明の重なりを避けるため1枚のポリゴンで描く)。
func wind_arc(at: Vector2, r: float, start: float, span: float, c: Color, width: float, flat: float = 1.0) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var centerline := PackedVector2Array()
	for i in range(25):
		var q := i / 24.0
		var a := start + q * span
		var d := Vector2(cos(a), sin(a) * flat)
		var half := sin(q * PI) * width * .5
		outer.append(at + d * (r + half))
		inner.append(at + d * (r - half))
		centerline.append(at + d * r)
	if width <= 2.0:
		draw_polyline(centerline, c, width, false)
	else:
		for i in range(23, 0, -1):
			outer.append(inner[i])
		if Geometry2D.triangulate_polygon(outer).size() > 0:
			draw_colored_polygon(outer, c)

## 攻撃爆発。5重の圧力波(85ms間隔、各1.12秒)、白閃光.15秒、煙/破片32個、2.05秒で消滅。
func cataclysm(at: Vector2, u: float, factor: float, c: Color) -> void:
	if u < 0.0 or u > 2.05:
		return
	if u < .15:
		draw_rect(_cover(), Color(.98, .96, .90, (1.0 - u / .15) * .96))
	for i in range(5):
		var dt := u - i * .085
		if dt < 0.0 or dt > 1.12:
			continue
		var q := dt / 1.12
		var radius := 35.0 + pow(q, .66) * 1950.0 * factor
		ring(at, radius, Color(c, .85 * (1.0 - q)), (44.0 * (1.0 - q) + 7.0) * factor)
		ring(at, radius - 19.0, Color(.91, .90, .86, .94 * (1.0 - q)), 22.0 * (1.0 - q) + 4.0)
		ring(at + Vector2(0, 65), radius * 1.2, Color(c, .6 * (1.0 - q)), 22.0 * (1.0 - q) + 4.0, .28)
	for i in range(32):
		var a := i * 2.399
		var q := clampf(u / 1.9, 0.0, 1.0)
		var d := Vector2(cos(a), sin(a) * .75)
		var pos := at + d * (45.0 + (i % 5) * 27.0 + pow(q, .65) * (950.0 + (i % 7) * 160.0)) * factor
		var r := (13.0 + i % 4 * 11.0 + q * 42.0) * factor
		cloud(pos, r, Color(.04, .036, .05, (1.0 - q) * .83))
		if i % 2 == 0:
			var side := Vector2(-d.y, d.x)
			poly([pos - d * 70.0, pos + side * 5.0, pos + d * 22.0, pos - side * 5.0], Color(c, (1.0 - q) * .85))
	if u < .38:
		var q := u / .38
		var points: Array = []
		for i in range(26):
			var a := i * TAU / 26.0
			var radius := (85.0 + q * 270.0) * factor * ((.72 + fposmod(i * 1.37, .45)) if i % 2 == 0 else .16)
			points.append(at + Vector2(cos(a), sin(a)) * radius)
		poly(points, Color(c, (1.0 - q) * .9))
		cloud(at, 60.0 + q * 140.0, Color(.97, .96, .9, (1.0 - q) * .92))

## 白黒の断裂: 上が太く下が鋭い針状。白い芯を厚い黒縁で挟む。属性色は細い外縁だけ。
func incision(at: Vector2, u: float, huge: bool) -> void:
	var length := 1280.0 if huge else 530.0
	var opening := (840.0 if huge else 112.0) * smoothstep(0.0, .12, u) * (1.0 - smoothstep(.72, 1.3, u))
	var alpha := 1.0 - smoothstep(1.0, 1.35, u)
	var axis := Vector2(.22, 1).normalized()
	var side := Vector2(1, -.22).normalized()
	var start := at - axis * length * .64
	var left: Array = []
	var right: Array = []
	var core_left: Array = []
	var core_right: Array = []
	var widths := [1.0, .94, .79, .68, .47, .22, 0.0]
	var fractions := [0.0, .17, .33, .48, .65, .82, 1.0]
	var bites := [0, 2, -2, 3, -1, 1, 0]
	for i in range(7):
		var f: float = fractions[i]
		var c := start + axis * length * f
		var w: float = opening * widths[i] * .5
		var bite: float = (3.0 if huge else 1.0) * bites[i]
		left.append(c - side * (w + bite))
		right.append(c + side * (w - bite * .55))
		core_left.append(c - side * w * .64)
		core_right.append(c + side * w * .62)
	var outer: Array = left.duplicate()
	var core: Array = core_left.duplicate()
	for i in range(5, -1, -1):
		outer.append(right[i])
		core.append(core_right[i])
	poly(outer, Color(.008, .009, .014, alpha))
	draw_polyline(PackedVector2Array(left), col(alpha * .86), 4.0 if huge else 2.0, false)
	draw_polyline(PackedVector2Array(right), col(alpha * .86), 4.0 if huge else 2.0, false)
	poly(core, Color(.96, .975, .975, alpha))
	# 少数の角状の黒片(多数の枝状裂け目や楕円・目の形にはしない)。
	for i in range(5):
		var f := .19 + i * .105
		var side_sign := -1 if i % 2 == 0 else 1
		var c := start + axis * length * f + side * side_sign * opening * (1.0 - f) * .58
		var n := (8.0 if huge else 3.0) * (1.0 - smoothstep(.45, 1.2, u))
		poly([c - axis * n, c + side * n, c + axis * n * .6, c - side * n * .8], Color(.008, .009, .014, alpha))

## 覚醒の風圧解放: 5重の風圧(85ms間隔、1.12秒で半径1950pxへ)、地面に沿う楕円風圧、
## 風筋30本、少量の鉄灰の塵。2.05秒で一時VFXを消す。
func wind_release(at: Vector2, u: float) -> void:
	if u < 0.0 or u > 2.05:
		return
	if u < .11:
		draw_rect(_cover(), Color(.79, .85, .85, (1.0 - u / .11) * .78))
	for i in range(5):
		var dt := u - i * .085
		if dt < 0.0 or dt > 1.12:
			continue
		var q := dt / 1.12
		var radius := 35.0 + pow(q, .66) * 1950.0
		for j in range(5):
			var angle := j * TAU / 5.0 + i * .24 + q * .35
			wind_arc(at, radius, angle, 1.05, Color(.48, .58, .61, (1.0 - q) * .80), 30.0 * (1.0 - q) + 3.0, .83)
			wind_arc(at, radius - 12.0, angle + .04, .82, Color(.83, .86, .83, (1.0 - q) * .94), 13.0 * (1.0 - q) + 2.0, .83)
		for j in range(3):
			wind_arc(at + Vector2(0, 75), radius * 1.15, j * TAU / 3.0 + .2, 1.80, Color(.70, .76, .74, (1.0 - q) * .8), 16.0 * (1.0 - q) + 2.0, .23)
	for i in range(30):
		var q := clampf(u / 1.6, 0.0, 1.0)
		var a := i * 2.399 + q * .25
		var r := 50.0 + pow(q, .64) * (1000.0 + i % 5 * 175.0)
		wind_arc(at, r, a, .10 + .18 * (1.0 - q), Color(.69, .75, .75, (1.0 - q) * .45), 2.0 + i % 3, .65)
		if i % 3 == 0:
			var pos := at + Vector2(cos(a), sin(a) * .65) * r
			poly([pos - Vector2(3, 2), pos + Vector2(9, 0), pos + Vector2(1, 4)], Color(.31, .36, .37, (1.0 - q) * .7))

func _draw() -> void:
	var t := age
	if kind == "awakening":
		_draw_awakening(t)
	else:
		_draw_attack(t)

func _draw_awakening(t: float) -> void:
	var c := home - Vector2(0, 95)
	var power := smoothstep(1.4, 4.4, t) * (1.0 - smoothstep(4.8, 6.2, t))
	draw_rect(_cover(), Color(.07, .095, .12, power * .72))
	for i in range(22):
		var a := i * 2.399 + t * .10
		var radius := 250.0 + fmod(i * 71.0 - t * 100.0 + 1600.0, 640.0)
		cloud(c + Vector2(cos(a), sin(a) * .65) * radius, 70.0 + i % 5 * 25.0, Color(.13, .16, .18, power * .28))
	# 画面の縁から収束する大きな圧力の影(密な赤い線ではない)。
	for i in range(3):
		var r := 100.0 + fposmod(1050.0 - t * 240.0 + i * 290.0, 1050.0)
		wind_arc(c, r, -2.9 + i * .8, 1.45, Color(.52, .60, .63, power * .45), 8.0, .65)
	if t > 3.3 and t < 4.8:
		var a := smoothstep(3.3, 4.6, t) * .78
		draw_rect(_cover(), Color(.025, .045, .058, a))
		draw_line(c + Vector2(-23, -61), c + Vector2(-13, -61), Color(1, .03, .04), 3.0, false)
	if t >= Motion.AWAKENING_RELEASE and t < Motion.AWAKENING_RELEASE + .24:
		for i in range(14):
			var p := screen.position + Vector2(50.0 + fposmod(i * 197.0, 1180.0), 100.0 + fposmod(i * 119.0, 510.0))
			var d := Vector2.from_angle(-.7 + i * .83) * 150.0
			draw_line(p - d, p + d, Color(.7, .68, .64, (1.0 - (t - Motion.AWAKENING_RELEASE) / .24) * .8), 3.0, false)
	wind_release(c, t - Motion.AWAKENING_RELEASE)
	# 小さなロックバーが外側へ順に解錠する(肩左右→腕左右→脚左右)。
	for i in range(6):
		var u := Motion.lock_age(i, t)
		if u < 0.0:
			continue
		var at: Vector2 = home + Motion.LOCK_OFFSETS[i]
		var side := -1 if i % 2 == 0 else 1
		draw_rect(Rect2(at + Vector2(side * minf(u * 18.0, 7.0), 0), Vector2(7, 3)), Color(.62, .59, .51, 1.0 - u / .6))

func _draw_attack(t: float) -> void:
	# 100msの空切り(薄い空気の筋を.24秒だけ)。白い棒状/発光する刀軌跡は描かない。
	var sweep := Motion.sweep_start(kind)
	if t >= sweep and t < sweep + .24:
		var u := t - sweep
		var q := clampf(u / Motion.SWEEP_DURATION, 0.0, 1.0)
		var c := home + Vector2(-33, -104)
		for i in range(3):
			var fade := (1.0 - smoothstep(.055, .24, u)) * (.42 - i * .08)
			var angle := lerpf(-2.35, -4.05, q) + i * .045
			wind_arc(c + Vector2(-u * 35.0, i * 4), 97.0 + i * 10.0, angle, .40 + u * .9, Color(.12, .18, .20, fade), 2.0)
			wind_arc(c + Vector2(-u * 35.0, i * 4), 100.0 + i * 10.0, angle, .28 + u * .8, Color(.55, .65, .66, fade * .60), 1.0)
	if kind == "single":
		if t >= 1.3 and t < Motion.SINGLE_IMPACT:
			draw_line(hit_at - Vector2(30, 220), hit_at + Vector2(30, 220), col(), 2.0, false)
		if t >= Motion.SINGLE_IMPACT and t < 3.5:
			incision(hit_at, t - Motion.SINGLE_IMPACT, false)
		cataclysm(hit_at, t - Motion.SINGLE_IMPACT, .78, tint)
	else:
		if t >= 2.15 and t < 4.55:
			var power := smoothstep(2.15, 4.55, t)
			draw_rect(_cover(), Color(.005, .01, .02, power * .45))
			draw_line(center + Vector2(-64, -445), center + Vector2(64, 435), col(.5 + power * .5), 2.0 + power * 3.0, false)
			# 空間が一本の巨大な断裂へ引き寄せられる(多数の亀裂にはしない)。
			var shift := center - Vector2(340, 365)
			for i in range(14):
				var x := 90.0 + fposmod(i * 157.0 - t * 85.0 + 1000.0, 600.0)
				var y := 150.0 + fposmod(i * 117.0, 410.0)
				draw_line(Vector2(x, y) + shift, Vector2(x + 13.0, y - 2.0) + shift, col(power * .3), 2.0, false)
		if t >= 4.55 and t < 5.95:
			incision(center, t - 4.55, true)
		cataclysm(center, t - Motion.ALL_IMPACT, 1.25, tint)
	_draw_name_plaque(t)

func _draw_name_plaque(t: float) -> void:
	var u := Motion.brush_age(kind, t)
	if u < 0.0:
		return
	var a := 1.0 - smoothstep(1.05, 1.5, u)
	var o := brush_at - Vector2(996, 224)
	poly([Vector2(784, 159) + o, Vector2(900, 122) + o, Vector2(1178, 145) + o, Vector2(1215, 231) + o, Vector2(1140, 296) + o, Vector2(797, 274) + o], Color(.78, .77, .73, .12 * a))
	if u > .95:
		for i in range(18):
			var p := Vector2(804.0 + fposmod(i * 73.0, 380.0), 125.0 + fposmod(i * 51.0, 180.0)) + o
			draw_rect(Rect2(p + Vector2(40, -30) * (u - .95), Vector2(3, 3)), Color(0, 0, 0, a))
