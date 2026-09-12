extends Node2D

## 無属性・巨大な筋肉のハンマー使い(tank)「渾身の一撃」フィニッシュ。
## rbm_hero_fire_finish.gd/rbm_butler_ice_finish.gd/rbm_healer_lightning_
## finish.gd/rbm_samurai_wind_finish.gdと同じ手法(px/poly/stroke、外部
## からageを渡されるだけのNode2D)を踏襲する。
##
## tools/vfx_prototype/rbm_tank_hammer_finish_prototype_v8.gd(ユーザー
## 承認済みのプロトタイプ最終版)の着弾以降の描画をほぼそのまま移植した
## もの。プロトタイプにあった以下の要素は、本番の既存基盤へ統合する際に
## 意図的に簡略化している(他の必殺技と同じ既存の仕組みを再利用し、
## 新しい共通基盤を増やさないため):
##   ・キャラクターが敵まで歩く演出(足音ダスト・一歩ずつの重量歩行)は、
##     他の近接攻撃(tank_smash等)と同じ既存の汎用windup/travelスライド
##     移動をそのまま利用する(rbm_battle_stage.gdのplay_entry()を参照、
##     このファイルはage=0=着弾直前の振り下ろし開始から始まる)。
##   ・白黒ヒットストップの複数フレームぶんの成長アニメーションは、
##     rbm_tank_hammer_impact_frame.gd側で1枚の完成形として簡略化し、
##     実時間の確保はrbm_battle_stage.gd側のTween.tween_interval()に
##     任せている(詳細はそちらのコメント参照)。
##
## 段階構成(ageはrbm_battle_stage.gdが着弾直前から駆動を開始する。
## IMPACT_MOMENT以降がヒットストップ明け=色復帰の瞬間):
##   ①振り下ろし(0〜IMPACT_MOMENT): 重い塊がoriginからimpact_pointへ
##     向かって加速しながら落下する(ease-in——重力で"落ちる"感覚)。
##     着弾直前だけハンマースメア(縦方向へ引き伸ばした残像)を重ねる。
##   ②着弾(IMPACT_MOMENT〜): 放射状の衝撃線+土煙の爆発的な膨らみ。
##   ③衝撃波: 地面に沿って這う、荒く不揃いな輪。
##   ④地面破壊: 放射状の亀裂+画面下方向へ大きく伸びるメイン亀裂
##     (白黒フレーム側から同じ角度・同じ形で継ぎ目なく伸び続ける)+
##     大小の岩片が重力付きの放物線で四方八方へ飛び散る。
##   ⑤遅れての二段目の衝撃(IMPACT_MOMENT+SECOND_IMPACT_DELAY〜): 追加の
##     衝撃波・岩片・亀裂の伸長。メイン亀裂の途中から追加の枝亀裂を
##     生やす(「最初にできた巨大亀裂がさらに崩壊する」)。
##   ⑥余韻(AFTERMATH_START〜): 岩片が重力で落下・着地し、砂埃が薄れ、
##     亀裂は最後にだけアルファを落として消える。

var age := -1.0
var origin := Vector2.ZERO        ## ハンマーを振りかぶった開始位置(頭上)
var impact_point := Vector2.ZERO  ## ハンマーが地面へ着弾する位置
var canvas_size := Vector2(1280, 720)

const CORE_WHITE = Color('#fbf6ec')
const DUST_LIGHT = Color('#d9c9a3')
const DUST_MID = Color('#a98f66')
const ROCK_LIGHT = Color('#8a7a63')
const ROCK_MID = Color('#5c4f3f')
const ROCK_DARK = Color('#332a20')
const CRACK_COLOR = Color('#1b130c')

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

func _ground_ring(center: Vector2, radius: float, squash: float, width: float, color: Color, seed_offset: float) -> void:
	var segments := 20
	for seg in range(segments):
		if fmod(float(seg) * 1.7 + seed_offset, 3.1) < 0.5:
			continue
		var a0 := TAU * float(seg) / float(segments)
		var a1 := TAU * float(seg + 1) / float(segments)
		var jitter := sin(float(seg) * 2.7 + seed_offset) * radius * 0.09
		var r := radius + jitter
		var p0 := center + Vector2(cos(a0), sin(a0) * squash) * r
		var p1 := center + Vector2(cos(a1), sin(a1) * squash) * r
		stroke(p0, p1, width, color)

func _crack(origin_pt: Vector2, base_angle: float, length: float, reach: float, seed: float, width: float, color: Color) -> void:
	var segments := 5
	var grown := clampf(reach, 0, 1) * float(segments)
	var prev := origin_pt
	var ang := base_angle
	for seg in range(segments):
		var seg_u := clampf(grown - float(seg), 0, 1)
		if seg_u <= 0:
			break
		var seg_len := (length / float(segments)) * seg_u
		ang += sin(seed * 2.7 + float(seg) * 1.9) * 0.45
		var next: Vector2 = prev + Vector2(cos(ang), sin(ang)) * seg_len
		var w := width * (1.0 - float(seg) / float(segments) * 0.65)
		stroke(prev, next, w, color)
		if seg == 2 and seg_u >= 1.0:
			var branch_ang := ang + (0.85 if fmod(seed, 2.0) < 1.0 else -0.85)
			var branch_end: Vector2 = next + Vector2(cos(branch_ang), sin(branch_ang)) * (seg_len * 1.3)
			stroke(next, branch_end, w * 0.55, color)
		prev = next

const ROCK_A = [0, -16, 10, -10, 14, 2, 6, 14, -6, 12, -14, 0, -8, -12]
const ROCK_B = [0, -12, 8, -6, 10, 4, 2, 10, -8, 8, -10, -2, -4, -10]
const ROCK_C = [0, -9, 6, -4, 7, 5, 0, 9, -7, 4, -6, -5]
const ROCKS := [ROCK_A, ROCK_B, ROCK_C]

const DUST_A = [0, -7, 4, -2, 2, 5, -3, 3]
const DUST_B = [0, -5, 3, -1, 1, 4, -2, 2]

const CRACKS = [
	{"angle": -2.7, "length": 150.0, "width": 8.0, "delay": 0.00},
	{"angle": -1.7, "length": 190.0, "width": 7.0, "delay": 0.025},
	{"angle": -0.85, "length": 130.0, "width": 9.0, "delay": 0.01},
	{"angle": -0.15, "length": 175.0, "width": 6.0, "delay": 0.04},
	{"angle": 0.65, "length": 145.0, "width": 8.0, "delay": 0.015},
	{"angle": 2.35, "length": 165.0, "width": 7.0, "delay": 0.03},
]

## 振り下ろし速度。この時間の終わりが着弾(=ヒットストップ開始)の瞬間。
const SWING_DURATION := 0.16
const IMPACT_MOMENT := SWING_DURATION

const HAMMER_SMEAR_WINDOW := 0.05
const HAMMER_SMEAR_STRETCH := 2.2

## 白黒フレーム側の亀裂スタブとの継ぎ目をなくすためのreachの下駄。
const CRACK_HEAD_START := 0.15

## 画面下方向へ大きく伸びるメイン亀裂(白黒フレーム側と同じ角度・形)。
const MAIN_CRACK_ANGLE := 1.52
const MAIN_CRACK_LENGTH := 620.0
const MAIN_CRACK_SEGMENTS := 10
const MAIN_CRACK_WIDTH_START := 19.0
const MAIN_CRACK_WIDTH_END := 4.0
const MAIN_CRACK_HEAD_START := 0.30
const MAIN_CRACK_GROW_DURATION := 0.22
const MAIN_CRACK_BRANCH_SEGS := [2, 4, 6, 8]

const IMPACT_LINE_COUNT := 12
const IMPACT_LINE_LENGTH := 95.0
const IMPACT_LINE_LIFETIME := 0.20

const EXPLOSION_PLUME_SIZE := 130.0
const EXPLOSION_PLUME_LIFETIME := 0.50

const SHOCKWAVE_SPEED := 900.0
const SHOCKWAVE_SIZE := 340.0
const ROCK_COUNT := 26
const ROCK_SPEED_MIN := 200.0
const ROCK_SPEED_MAX := 420.0
const ROCK_SIZE_MIN := 0.7
const ROCK_SIZE_MAX := 2.2
const ROCK_GRAVITY := 640.0
const DUST_AMOUNT := 22
const SECOND_IMPACT_DELAY := 0.12
const SECOND_ROCK_COUNT := 14
const SECOND_SHOCKWAVE_SIZE := 190.0
const SECOND_SHOCKWAVE_SPEED := 520.0
const AFTERMATH_START := IMPACT_MOMENT + SECOND_IMPACT_DELAY + 0.35
const AFTERMATH_DURATION := 1.10
const TOTAL_DURATION := AFTERMATH_START + AFTERMATH_DURATION

func _draw() -> void:
	if age < 0 or age > TOTAL_DURATION:
		return

	# =====================================================================
	# ①振り下ろし(0〜IMPACT_MOMENT): 重い塊がoriginからimpact_pointへ
	# 向かって加速しながら落下する(ease-in)。
	# =====================================================================
	if age < IMPACT_MOMENT:
		var fall_t: float = clampf(age / SWING_DURATION, 0, 1)
		var fall_eased: float = fall_t * fall_t
		var head: Vector2 = origin.lerp(impact_point, fall_eased)
		var trail_u: float = maxf(0.0, fall_eased - 0.22)
		var tail: Vector2 = origin.lerp(impact_point, trail_u)
		var dir := (head - tail)
		if dir.length() > 2.0:
			var n := dir.normalized().orthogonal()
			var w0 := 30.0
			var w1 := 12.0
			poly([tail + n * w1 * 0.5, head + n * w0 * 0.5, head - n * w0 * 0.5, tail - n * w1 * 0.5], ROCK_DARK * Color(1, 1, 1, 0.85))
			poly([tail + n * w1 * 0.3, head + n * w0 * 0.3, head - n * w0 * 0.3, tail - n * w1 * 0.3], ROCK_MID * Color(1, 1, 1, 0.9))
		px(head - Vector2(9, 9), Vector2(18, 18), CORE_WHITE * Color(1, 1, 1, 0.6))
		if age >= IMPACT_MOMENT - HAMMER_SMEAR_WINDOW:
			var smear_t: float = clampf((age - (IMPACT_MOMENT - HAMMER_SMEAR_WINDOW)) / HAMMER_SMEAR_WINDOW, 0, 1)
			var smear_len: float = 26.0 * HAMMER_SMEAR_STRETCH * smear_t
			var smear_tail: Vector2 = head - dir.normalized() * smear_len
			var sn := dir.normalized().orthogonal()
			poly([smear_tail + sn * 8.0, head + sn * 16.0, head - sn * 16.0, smear_tail - sn * 8.0], ROCK_DARK * Color(1, 1, 1, 0.7 * smear_t))
			poly([smear_tail + sn * 4.0, head + sn * 9.0, head - sn * 9.0, smear_tail - sn * 4.0], DUST_MID * Color(1, 1, 1, 0.55 * smear_t))
		for i in range(3):
			var seed_f := float(i) * 2.1 + 2.0
			var drop_u: float = clampf(fall_t - float(i) * 0.12, 0, 1)
			if drop_u <= 0:
				continue
			var p := origin.lerp(impact_point, drop_u * 0.4) + Vector2(sin(seed_f * 3.0) * 14.0, 0)
			poly(_scaled(DUST_A, p, 0.5, seed_f), DUST_LIGHT * Color(1, 1, 1, (1.0 - drop_u) * 0.5))

	# =====================================================================
	# ②以降(IMPACT_MOMENT〜): 着弾。放射状の衝撃線+土煙+衝撃波+地面破壊+
	# 岩片+遅れての二段目の衝撃+余韻。
	# =====================================================================
	if age >= IMPACT_MOMENT:
		var it := age - IMPACT_MOMENT

		var lines_t: float = it - 0.02
		if lines_t >= 0.0 and lines_t < IMPACT_LINE_LIFETIME:
			var lines_fade: float = 1.0 - lines_t / IMPACT_LINE_LIFETIME
			var lines_grow: float = 1.0 - pow(1.0 - clampf(lines_t / 0.06, 0, 1), 2)
			for i in range(IMPACT_LINE_COUNT):
				var seed_l := float(i) * 2.63 + 11.0
				var ang_l := seed_l * 1.9
				var len_l: float = IMPACT_LINE_LENGTH * (0.6 + fmod(seed_l, 0.6)) * lines_grow
				var dir_l := Vector2(cos(ang_l), sin(ang_l) * 0.85)
				var mid_l: Vector2 = impact_point + dir_l * (len_l * 0.45)
				var jitter_ang: float = ang_l + (0.18 if i % 2 == 0 else -0.18)
				var tip_l: Vector2 = mid_l + Vector2(cos(jitter_ang), sin(jitter_ang) * 0.85) * (len_l * 0.55)
				var col_l: Color = CORE_WHITE if i % 3 == 0 else ROCK_MID
				stroke(impact_point + dir_l * 8.0, mid_l, 4.0 * lines_grow, col_l * Color(1, 1, 1, lines_fade * 0.85))
				stroke(mid_l, tip_l, 2.5 * lines_grow, col_l * Color(1, 1, 1, lines_fade * 0.6))

		var plume_t: float = it - 0.02
		if plume_t >= 0.0 and plume_t < EXPLOSION_PLUME_LIFETIME:
			var plume_u: float = plume_t / EXPLOSION_PLUME_LIFETIME
			var plume_grow: float = 1.0 - pow(1.0 - clampf(plume_t / 0.16, 0, 1), 2)
			var plume_fade: float = clampf(1.0 - (plume_u - 0.25) / 0.75, 0, 1)
			if plume_fade > 0.01:
				for i in range(12):
					var seed_p := float(i) * 2.87 + 13.0
					var ang_p := seed_p * 1.6
					var dir_p := Vector2(cos(ang_p), sin(ang_p) * 0.7 - 0.25)
					var p := impact_point + dir_p * (EXPLOSION_PLUME_SIZE * 0.35 * plume_grow) + Vector2(0, -EXPLOSION_PLUME_SIZE * 0.12 * plume_grow)
					var shape_p := DUST_A if i % 2 == 0 else DUST_B
					var col_p: Color = DUST_LIGHT if i % 2 == 0 else DUST_MID
					poly(_scaled(shape_p, p, (1.8 + fmod(seed_p, 1.1)) * plume_grow, ang_p + PI * 0.5), col_p * Color(1, 1, 1, plume_fade * 0.55))
				px(impact_point - Vector2(1, 1) * (EXPLOSION_PLUME_SIZE * 0.5) * plume_grow, Vector2(EXPLOSION_PLUME_SIZE, EXPLOSION_PLUME_SIZE * 0.6) * plume_grow, DUST_MID * Color(1, 1, 1, plume_fade * 0.28))

		var shock_t: float = it - 0.05
		if shock_t >= 0.0:
			var shock_reach: float = clampf((shock_t * SHOCKWAVE_SPEED) / SHOCKWAVE_SIZE, 0, 1)
			if shock_reach > 0.0 and shock_reach < 1.15:
				var shock_fade: float = clampf(1.0 - (shock_reach - 0.55) / 0.6, 0, 1)
				if shock_fade > 0.01:
					_ground_ring(impact_point, SHOCKWAVE_SIZE * shock_reach, 0.30, 13.0, ROCK_DARK * Color(1, 1, 1, shock_fade * 0.6), 0.0)
					_ground_ring(impact_point, SHOCKWAVE_SIZE * shock_reach * 0.7, 0.26, 9.0, DUST_MID * Color(1, 1, 1, shock_fade * 0.75), 1.7)
					var dust_ring_segs := 16
					for seg in range(dust_ring_segs):
						var seed_dr := float(seg) * 1.9 + 33.0
						if fmod(seed_dr, 2.6) < 0.5:
							continue
						var a_dr := TAU * float(seg) / float(dust_ring_segs)
						var height_jitter: float = 0.20 + fmod(seed_dr, 0.5)
						var r_dr := SHOCKWAVE_SIZE * shock_reach * (0.78 + fmod(seed_dr, 0.18))
						var p_dr := impact_point + Vector2(cos(a_dr), sin(a_dr) * (0.24 + height_jitter * 0.3)) * r_dr
						var shape_dr := DUST_A if seg % 2 == 0 else DUST_B
						poly(_scaled(shape_dr, p_dr, (0.8 + height_jitter) * shock_reach, a_dr + PI * 0.5), DUST_LIGHT * Color(1, 1, 1, shock_fade * 0.5))
					for i in range(10):
						var seed_s := float(i) * 2.71 + 21.0
						var ang_s := seed_s * 1.4
						if fmod(ang_s, 2.4) < 0.6:
							continue
						var p_s := impact_point + Vector2(cos(ang_s), sin(ang_s) * 0.32) * (SHOCKWAVE_SIZE * shock_reach)
						var shape_s := DUST_A if i % 2 == 0 else DUST_B
						poly(_scaled(shape_s, p_s, 0.6 + fmod(seed_s, 0.5), ang_s + PI * 0.5), DUST_LIGHT * Color(1, 1, 1, shock_fade * 0.6))
					for i in range(6):
						var seed_pb := float(i) * 3.3 + 41.0
						var ang_pb := seed_pb * 1.1
						var trail_r: float = SHOCKWAVE_SIZE * shock_reach * (0.55 + fmod(seed_pb, 0.3))
						var p_pb := impact_point + Vector2(cos(ang_pb), sin(ang_pb) * 0.22) * trail_r
						var bounce: float = absf(sin(shock_reach * 14.0 + seed_pb)) * 6.0
						poly(_scaled(ROCKS[i % ROCKS.size()], p_pb - Vector2(0, bounce), 0.09, shock_reach * 6.0 + seed_pb), ROCK_DARK * Color(1, 1, 1, shock_fade * 0.65))

		for crack in CRACKS:
			var c_delay: float = crack["delay"]
			var c_t: float = it - c_delay
			if c_t < 0:
				continue
			var c_reach: float = clampf(CRACK_HEAD_START + c_t / 0.30, 0, 1)
			var seed_c: float = float(crack["angle"]) * 3.0
			_crack(impact_point, float(crack["angle"]), float(crack["length"]), c_reach, seed_c, float(crack["width"]), CRACK_COLOR * Color(1, 1, 1, _crack_alpha(age)))

		var main_reach: float = clampf(MAIN_CRACK_HEAD_START + it / MAIN_CRACK_GROW_DURATION, 0, 1)
		_main_crack(main_reach, _crack_alpha(age))

		for i in range(ROCK_COUNT):
			_draw_rock(i, it, ROCK_SPEED_MIN, ROCK_SPEED_MAX, ROCK_SIZE_MIN, ROCK_SIZE_MAX)

		var dust_life: float = 1.1
		if it < dust_life:
			var dust_t: float = it / dust_life
			var dust_fade2: float = 1.0 - dust_t
			for i in range(DUST_AMOUNT):
				var seed_d := float(i) * 2.399 + 5.0
				var ang_d := seed_d * 1.7
				var dir_d := Vector2(cos(ang_d), sin(ang_d) * 0.8 - 0.35)
				var spread_u: float = clampf((it - fmod(seed_d, 0.15)) / 0.85, 0, 1)
				var p := impact_point + dir_d * (20.0 + spread_u * (90.0 + fmod(seed_d, 60.0)))
				var shape_d := DUST_A if i % 2 == 0 else DUST_B
				var col_d: Color = DUST_LIGHT if i % 3 != 0 else DUST_MID
				poly(_scaled(shape_d, p, (0.7 + fmod(seed_d, 0.7)) * (1.0 - spread_u * 0.2), ang_d + PI * 0.5), col_d * Color(1, 1, 1, dust_fade2 * 0.7))

		if it >= SECOND_IMPACT_DELAY:
			var it2 := it - SECOND_IMPACT_DELAY
			var shock2_reach: float = clampf((it2 * SECOND_SHOCKWAVE_SPEED) / SECOND_SHOCKWAVE_SIZE, 0, 1)
			if shock2_reach > 0.0 and shock2_reach < 1.15:
				var shock2_fade: float = clampf(1.0 - (shock2_reach - 0.55) / 0.6, 0, 1)
				if shock2_fade > 0.01:
					_ground_ring(impact_point, SECOND_SHOCKWAVE_SIZE * shock2_reach, 0.28, 9.0, ROCK_DARK * Color(1, 1, 1, shock2_fade * 0.55), 4.2)
					_ground_ring(impact_point, SECOND_SHOCKWAVE_SIZE * shock2_reach * 0.7, 0.24, 6.0, DUST_MID * Color(1, 1, 1, shock2_fade * 0.7), 6.1)
			if it2 < 0.7:
				var col_t: float = it2 / 0.7
				var col_fade: float = 1.0 - col_t
				for i in range(14):
					var seed_e := float(i) * 2.53 + 8.0
					var up_bias: float = -0.75 - fmod(seed_e, 0.5)
					var dir_e := Vector2(sin(seed_e * 3.1) * 0.6, up_bias).normalized()
					var p := impact_point + dir_e * (10.0 + col_t * (70.0 + fmod(seed_e, 50.0)))
					var shape_e := DUST_A if i % 2 == 0 else DUST_B
					poly(_scaled(shape_e, p, 0.7 + fmod(seed_e, 0.5), dir_e.angle() + PI * 0.5), DUST_MID * Color(1, 1, 1, col_fade * 0.75))
			for i in range(SECOND_ROCK_COUNT):
				_draw_rock(i + 100, it2, ROCK_SPEED_MIN * 0.6, ROCK_SPEED_MAX * 0.7, ROCK_SIZE_MIN * 0.8, ROCK_SIZE_MAX * 0.9)
			for crack in CRACKS:
				var c_t2: float = it2 - float(crack["delay"])
				if c_t2 < 0 or c_t2 > 0.25:
					continue
				var seed_c2: float = float(crack["angle"]) * 3.0 + 9.0
				var extra_len: float = float(crack["length"]) * 0.35
				var tip: Vector2 = impact_point + Vector2(cos(float(crack["angle"])), sin(float(crack["angle"]))) * float(crack["length"])
				_crack(tip, float(crack["angle"]) + 0.3, extra_len, clampf(c_t2 / 0.2, 0, 1), seed_c2, float(crack["width"]) * 0.5, CRACK_COLOR * Color(1, 1, 1, _crack_alpha(age)))
			if it2 < 0.25:
				var main_dir := Vector2(cos(MAIN_CRACK_ANGLE), sin(MAIN_CRACK_ANGLE))
				var branch_pt: Vector2 = impact_point + main_dir * (MAIN_CRACK_LENGTH * 0.45)
				var branch_reach2: float = clampf(it2 / 0.2, 0, 1)
				_crack(branch_pt, MAIN_CRACK_ANGLE + 1.0, 95.0, branch_reach2, 77.0, 7.0, CRACK_COLOR * Color(1, 1, 1, _crack_alpha(age)))
				_crack(branch_pt, MAIN_CRACK_ANGLE - 1.1, 75.0, branch_reach2, 82.0, 6.0, CRACK_COLOR * Color(1, 1, 1, _crack_alpha(age)))

## 画面下方向(MAIN_CRACK_ANGLE)へ大きく伸びるメイン亀裂。白黒フレーム側
## (rbm_tank_hammer_impact_frame.gd)と同じ角度・同じジグザグ式・同じ
## 枝分かれの考え方をそのまま踏襲し、色が戻ったあとも同じ亀裂が伸び続けて
## 見えるようにしている(MAIN_CRACK_HEAD_STARTで継ぎ目を近似的に解消)。
func _main_crack(reach: float, alpha: float) -> void:
	var segments := MAIN_CRACK_SEGMENTS
	var grown := clampf(reach, 0, 1) * float(segments)
	var prev := impact_point
	var ang := MAIN_CRACK_ANGLE
	var color := CRACK_COLOR * Color(1, 1, 1, alpha)
	for seg in range(segments):
		var seg_u := clampf(grown - float(seg), 0, 1)
		if seg_u <= 0:
			break
		var seg_len := (MAIN_CRACK_LENGTH / float(segments)) * seg_u
		ang += sin(float(seg) * 1.7 + 3.0) * 0.5
		var next: Vector2 = prev + Vector2(cos(ang), sin(ang)) * seg_len
		var w: float = lerpf(MAIN_CRACK_WIDTH_START, MAIN_CRACK_WIDTH_END, float(seg) / float(segments))
		stroke(prev, next, w, color)
		if seg_u >= 1.0 and MAIN_CRACK_BRANCH_SEGS.has(seg):
			var seed_b: float = float(seg) * 3.1 + 5.0
			var branch_ang: float = ang + (0.9 if fmod(seed_b, 2.0) < 1.0 else -0.9)
			var depth_mult: float = 0.55 + (float(seg) / float(segments)) * 0.85
			var branch_len: float = seg_len * depth_mult
			var branch_end: Vector2 = next + Vector2(cos(branch_ang), sin(branch_ang)) * branch_len
			stroke(next, branch_end, w * (0.5 + depth_mult * 0.3), color)
		prev = next

## 岩片1個を弾道(重力付き放物線)で描画する。小/中/大の3段階のサイズ層を
## 混在させる——大サイズほど噴き上げの角度を真上寄りに狭め、回転を遅くする。
func _draw_rock(index: int, local_t: float, speed_min: float, speed_max: float, size_min: float, size_max: float) -> void:
	var seed := float(index) * 2.71 + 3.0
	var delay: float = fmod(seed, 0.16)
	var t: float = local_t - delay
	if t < 0:
		return
	var life := 1.6 + fmod(seed, 0.5)
	if t > life:
		return
	var tier_mult: float = 1.0
	var speed_mult: float = 1.0
	var spin_mult: float = 1.0
	var cone_width: float = 2.3
	if index % 8 == 0:
		tier_mult = 1.9
		speed_mult = 0.72
		spin_mult = 0.30
		cone_width = 1.1
	elif index % 3 == 0:
		tier_mult = 1.3
		speed_mult = 0.88
		spin_mult = 0.55
		cone_width = 1.7
	var ang: float = -1.57 + (fmod(seed * 1.3, cone_width) - cone_width * 0.5)
	var speed: float = lerpf(speed_min, speed_max, fmod(seed, 1.0)) * speed_mult
	var dir := Vector2(cos(ang), sin(ang))
	var pos: Vector2 = impact_point + dir * speed * t + Vector2(0, 1) * 0.5 * ROCK_GRAVITY * t * t
	if pos.y > impact_point.y + 6.0:
		pos.y = impact_point.y + 6.0 - (pos.y - (impact_point.y + 6.0)) * 0.15
	var size: float = lerpf(size_min, size_max, fmod(seed * 1.7, 1.0)) * tier_mult
	var fade: float = clampf(1.0 - (t - life * 0.7) / (life * 0.3), 0, 1)
	if fade <= 0.02:
		return
	var shape: Array = ROCKS[index % ROCKS.size()]
	var spin: float = t * (2.0 + fmod(seed, 2.0)) * spin_mult * (1.0 if index % 2 == 0 else -1.0)
	poly(_scaled(shape, pos, 0.16 * size, spin), ROCK_DARK * Color(1, 1, 1, fade))
	poly(_scaled(shape, pos, 0.11 * size, spin), ROCK_LIGHT * Color(1, 1, 1, fade * 0.8))

## 亀裂の最終的な見え方: 大部分の間ははっきり残し、余韻の終盤にだけ
## アルファを落として消す(地面に刻まれた傷跡として長く残すのが自然)。
func _crack_alpha(current_age: float) -> float:
	if current_age < AFTERMATH_START + AFTERMATH_DURATION * 0.5:
		return 0.9
	var fade_t: float = (current_age - (AFTERMATH_START + AFTERMATH_DURATION * 0.5)) / (AFTERMATH_DURATION * 0.5)
	return clampf(0.9 * (1.0 - fade_t), 0, 0.9)
