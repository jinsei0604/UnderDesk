class_name RBMHeroRooftop
extends RefCounted
## ヒーローの戦闘背景（救難基地の屋上、assets_bossmaker/battle/backgrounds/hero_boss/background.png）の2つの照射器の光（表示専用）。
## 光の帯は登場（救難信号）で使う（2026-11-19 から支援・撃破では照らさない。丸い光 glow は支援・撃破でも使う）。座標は 640×360 の論理ドット＝背景の画素。
## レンズの位置は背景の絵を拡大して測った（2026-11-17）。光は平らな円・楕円にせず、レンズから先へ細る帯（先は消える）で描く。

## 左右の照射器のレンズの中心
const LENS_L := Vector2(151, 26)
const LENS_R := Vector2(541, 33)
const WARM := Color("#fff1c8")
const PALE := Color("#c8f4ff")

## 照射器の光の帯: from（レンズ）から to へ。w0 は根元の幅、w1 は先の幅。a は強さ（0で消える）。先へ行くほど薄く、両端は透明。
static func beam(b: RBMHeroFxBatch, from: Vector2, to: Vector2, w0: float, w1: float, col: Color, a: float) -> void:
	if a <= 0.005 or from.distance_to(to) < 2.0:
		return
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	# 外側のやわらかい光（帯の真ん中が明るく、両側の縁は透明）
	for side in [-1.0, 1.0]:
		var c_in := Color(col, 0.16 * a)
		var c_out := Color(col, 0.0)
		var c_far := Color(col, 0.0)
		b.quad(from, from + n * side * w0 * 0.5, to + n * side * w1 * 0.5, to, c_in, c_out, c_far, Color(col, 0.05 * a))
	# 芯（細く明るい）
	for side in [-1.0, 1.0]:
		b.quad(from, from + n * side * w0 * 0.2, to + n * side * w1 * 0.16, to, Color(col, 0.32 * a), Color(col, 0.0), Color(col, 0.0), Color(col, 0.08 * a))
	# レンズのにじみ（丸いやわらかい光）
	glow(b, from, 7.0, Color(col, 0.55 * a))

## 丸いやわらかい光（中心が明るく、縁で消える）。星形・十字を作らない。
static func glow(b: RBMHeroFxBatch, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.3 or col.a <= 0.005:
		return
	var segs := clampi(int(r * 1.2), 10, 40)
	var edge := Color(col, 0.0)
	for i in range(segs):
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		b.tri(c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, col, edge, edge)

## 照射器が向く先（角度で補間）: 初めの向き a から b へ k で回す。長さは len。
static func swing(lens: Vector2, from_dir: Vector2, to_point: Vector2, k: float, length: float) -> Vector2:
	var a0 := from_dir.angle()
	var a1 := (to_point - lens).angle()
	var ang := lerp_angle(a0, a1, k)
	var l := lerpf(length, lens.distance_to(to_point), k)
	return lens + Vector2.from_angle(ang) * l
