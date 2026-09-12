extends Node2D

## 無属性・ハンマー使い(tank)必殺技の、着弾ヒットストップ用の白黒
## インパクトフレーム。tools/vfx_prototype/rbm_tank_hammer_impact_frame_
## prototype_v8.gdの静止画部分を移植したもの——プロトタイプにあった
## frame_indexによる複数フレームぶんの伸び途中アニメーション(白黒反転
## フレーム含む)は簡略化し、表示された瞬間に完成形を1枚だけ描く
## (ヒットストップの実時間はrbm_battle_stage.gd側がTween.tween_interval()
## で確保するだけで、このNode2D自身は毎フレーム再計算しない)。
##
## rbm_hero_fire_finish.gd等と同じ低レベル手法(px/poly/stroke、外部から
## 座標を渡されるだけのNode2D)を踏襲する。

var tank_rect := Rect2()
var boss_rect := Rect2()
var hammer_facing := 1.0
var contact_point := Vector2.ZERO
var ground_y := 0.0
var canvas_size := Vector2(1280, 720)

const LINE_COUNT := 18
const CRACK_ANGLES := [-2.7, -1.7, -0.85, 0.65, 2.35]
const MAIN_CRACK_ANGLE := 1.52
const MAIN_CRACK_LENGTH := 460.0
const MAIN_CRACK_SEGMENTS := 9
const MAIN_CRACK_WIDTH_START := 15.0
const MAIN_CRACK_WIDTH_END := 3.0
const MAIN_CRACK_BRANCH_SEGS := [2, 4, 6, 7]
const GROUND_LINE_WIDTH := 3.0
const BURST_SIZE := 46.0

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

## キャラクターの矩形を、胴体+頭+(hammer_sideが0でなければ)もう1ブロック
## の3パーツで描く——正確な輪郭抽出ではなく意図的な簡略化。
func _silhouette(rect: Rect2, color: Color, hammer_side: float = 0.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var body_w: float = rect.size.x * 0.62
	var body_h: float = rect.size.y * 0.72
	var body_x: float = rect.position.x + (rect.size.x - body_w) * 0.5
	var body_y: float = rect.position.y + rect.size.y * 0.28
	px(Vector2(body_x, body_y), Vector2(body_w, body_h), color)
	var head_w: float = rect.size.x * 0.36
	var head_h: float = rect.size.y * 0.24
	var head_x: float = rect.position.x + (rect.size.x - head_w) * 0.5
	px(Vector2(head_x, rect.position.y), Vector2(head_w, head_h), color)
	if hammer_side != 0.0:
		var hw: float = rect.size.x * 0.34
		var hh: float = rect.size.y * 0.20
		var hx: float = body_x + (body_w - hw) * 0.5 + hammer_side * rect.size.x * 0.32
		var hy: float = rect.position.y + rect.size.y * 0.58
		px(Vector2(hx, hy), Vector2(hw, hh), color)

## 太/中/細の3段階を混在させた放射状衝撃線。
func _impact_lines(color: Color) -> void:
	for i in range(LINE_COUNT):
		var seed := float(i) * 2.93 + 7.0
		var ang := seed * 1.7
		var tier: int = 0
		if i % 6 == 0:
			tier = 2
		elif i % 3 == 0:
			tier = 1
		var length: float = (60.0 if tier == 2 else (44.0 if tier == 1 else 30.0)) + fmod(seed, 1.0) * 70.0
		var width: float = (9.0 if tier == 2 else (5.0 if tier == 1 else 2.0)) + fmod(seed * 1.3, 2.0)
		var jitter_ang: float = ang + sin(seed * 4.0) * 0.3
		var base_pt: Vector2 = contact_point + Vector2(cos(ang), sin(ang) * 0.9) * 6.0
		var tip: Vector2 = contact_point + Vector2(cos(jitter_ang), sin(jitter_ang) * 0.9) * length
		stroke(base_pt, tip, width, color)

## 接触点から短く伸びる亀裂スタブ。
func _crack_stub(base_angle: float, color: Color) -> void:
	var segments := 3
	var prev := contact_point
	var ang := base_angle
	for seg in range(segments):
		var seg_len := 15.0
		ang += sin(base_angle * 3.1 + float(seg) * 2.0) * 0.4
		var next: Vector2 = prev + Vector2(cos(ang), sin(ang)) * seg_len
		stroke(prev, next, 5.0 * (1.0 - float(seg) / float(segments) * 0.5), color)
		prev = next

## 画面下方向(MAIN_CRACK_ANGLE)へ大きく伸びるメイン亀裂。色復帰後は
## rbm_tank_hammer_finish.gd側が同じ角度・同じ形で引き継いで伸ばし続ける。
func _main_crack(color: Color) -> void:
	var segments := MAIN_CRACK_SEGMENTS
	var prev := contact_point
	var ang := MAIN_CRACK_ANGLE
	for seg in range(segments):
		var seg_len := MAIN_CRACK_LENGTH / float(segments)
		ang += sin(float(seg) * 1.7 + 3.0) * 0.5
		var next: Vector2 = prev + Vector2(cos(ang), sin(ang)) * seg_len
		var w: float = lerpf(MAIN_CRACK_WIDTH_START, MAIN_CRACK_WIDTH_END, float(seg) / float(segments))
		stroke(prev, next, w, color)
		if MAIN_CRACK_BRANCH_SEGS.has(seg):
			var seed_b: float = float(seg) * 3.1 + 5.0
			var branch_ang: float = ang + (0.9 if fmod(seed_b, 2.0) < 1.0 else -0.9)
			var depth_mult: float = 0.55 + (float(seg) / float(segments)) * 0.85
			var branch_len: float = seg_len * depth_mult
			var branch_end: Vector2 = next + Vector2(cos(branch_ang), sin(branch_ang)) * branch_len
			stroke(next, branch_end, w * (0.5 + depth_mult * 0.3), color)
		prev = next

## 接触点そのものを強調する、太い黒の角ばった破裂形状。
func _impact_burst(color: Color) -> void:
	var shape := [0, -18, 9, -8, 16, 2, 8, 14, -2, 18, -13, 10, -18, -3, -9, -14]
	poly(_scaled(shape, contact_point, BURST_SIZE / 18.0, 0.4), color)

func _draw() -> void:
	px(Vector2.ZERO, canvas_size, Color.WHITE)
	stroke(Vector2(0, ground_y), Vector2(canvas_size.x, ground_y), GROUND_LINE_WIDTH, Color(0, 0, 0, 0.7))
	_silhouette(tank_rect, Color.BLACK, hammer_facing)
	_silhouette(boss_rect, Color.BLACK)
	_impact_lines(Color.BLACK)
	for a in CRACK_ANGLES:
		_crack_stub(a, Color.BLACK)
	_main_crack(Color.BLACK)
	_impact_burst(Color.BLACK)
	px(contact_point - Vector2(10, 10), Vector2(20, 20), Color.WHITE)
