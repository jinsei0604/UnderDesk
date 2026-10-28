extends "res://ally_awakening/core/sequence.gd"
## 味方の覚醒の発動演出の共通部分（2026-10-28 ユーザーが採用。勇者・老執事・侍・ハンマー使い。少女は Codex の版のまま）。Codex の sequence.gd（再生・音・合図）をそのまま使い、
## 絵だけを別に描く。音は各味方の Codex の音（charge/release）を同じ解放の時刻で鳴らすので、duration/release_time は Codex の版と同じ。
## 描画は1フレーム1回の三角形の一括描画にまとめる（Codex の勇者の版の重さの反省）。全画面の閃光は 0.10 秒・1秒に1回まで。
var dark_peak := 0.5
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
## 解放の後の短い止め（見た目の時間だけ止める。音・ポーズ・合図は止めない）。
var hold := 0.0

## 見た目の時間（解放の直後に hold 秒だけ止まる）。
func vt() -> float:
	if age < release_time:
		return age
	return release_time + maxf(0.0, age - release_time - hold)

func advance(t: float) -> void:
	super.advance(t)
	if not active:
		return
	# 暗転は味方ごとの深さで（Codex の 0.43 を上書き）。閃光は解放の 0.10 秒だけ。
	var d := smoothstep(.12, 1.2, age) * dark_peak * (1 - smoothstep(release_time + .35, duration - .25, age))
	var f := maxf(0, 1 - (age - release_time) / .10) if age >= release_time else 0.0
	screen_requested.emit(d + extra_dark(), f * .2 * flash_strength)

## 区間ごとの暗転の上乗せ（侍の鼓動など）。
func extra_dark() -> float:
	return 0.0

func q_rect(r: Rect2, c: Color) -> void:
	if c.a < 0.005:
		return
	r = Rect2(r.position.snapped(Vector2(2, 2)), r.size.snapped(Vector2(2, 2)).max(Vector2(2, 2)))
	var n := _pts.size()
	_pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_cols.append_array([c, c, c, c])
	_idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])

## 凸の多角形（扇形に三角形へ分ける）。2px に揃える。
func q_poly(points: PackedVector2Array, c: Color) -> void:
	if c.a < 0.005 or points.size() < 3:
		return
	var n := _pts.size()
	for p in points:
		_pts.append(p.snapped(Vector2(2, 2)))
		_cols.append(c)
	for i in range(1, points.size() - 1):
		_idx.append_array([n, n + i, n + i + 1])

func q_tri(a: Vector2, b: Vector2, c2: Vector2, c: Color) -> void:
	q_poly(PackedVector2Array([a, b, c2]), c)

## 太さのある線（区間ごとの四角）。
func q_line(points: PackedVector2Array, c: Color, w: float = 2.0) -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).orthogonal().normalized() * w * .5
		q_poly(PackedVector2Array([a - side, b - side, b + side, a + side]), c)

## 楕円の帯（輪）。
func q_ring(p: Vector2, r: Vector2, width: float, c: Color, start := 0.0, arc := TAU, segs := 40) -> void:
	if r.x < 1 or r.y < 1 or width < 1:
		return
	var inner := Vector2(maxf(1, r.x - width), maxf(1, r.y - width * r.y / r.x))
	for i in segs:
		var a := start + arc * i / segs
		var b := start + arc * (i + 1) / segs
		var da := Vector2(cos(a), sin(a))
		var db := Vector2(cos(b), sin(b))
		q_poly(PackedVector2Array([p + da * r, p + db * r, p + db * inner, p + da * inner]), c)

## 菱形（氷・葉）。
func q_diamond(p: Vector2, w: float, h: float, c: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array([Vector2(0, -h), Vector2(w, 0), Vector2(0, h), Vector2(-w, 0)])
	for i in pts.size():
		pts[i] = p + pts[i].rotated(rot)
	q_poly(pts, c)

func flush() -> void:
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _pts, _cols)
	_pts.clear()
	_cols.clear()
	_idx.clear()

## 0〜1 の擬似乱数（i ごとに固定。戦闘の乱数は使わない）。
static func h1(i: float) -> float:
	return fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
