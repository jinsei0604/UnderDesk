extends Node2D

## 風属性の侍「カウンター必殺技」フィニッシュ。rbm_hero_fire_finish.gd/
## rbm_butler_ice_finish.gd/rbm_healer_lightning_finish.gdと同じ手法
## (px/poly/stroke、外部からageを渡されるだけのNode2D)を踏襲する。
##
## 段階構成(合計 約2.77秒。IMPACT_START=0.62、EXPLOSION_START≈0.953、
## AFTERMATH_START≈1.373、AFTERMATH_DURATION=1.40):
##   ①侍の周囲を大きく回る風(0.00-0.38) → ②足元を走る地面の風圧
##   (0.08-0.42) → ③刀に沿った巨大な風の斬撃+③b侍から敵へ移動する風
##   (0.25-0.85) → ④a着弾の接触〜タメ(IMPACT_START〜EXPLOSION_START) →
##   ④敵への着弾・大爆発(EXPLOSION_START〜+0.42) → ⑤大爆発後の残風
##   (AFTERMATH_START〜+AFTERMATH_DURATION)。
##
## ⑤は⑤a(敵を中心に大きな風の帯が渦を巻く。出現後は各帯とも"hold"の間
## フル強度を保ち、その後は帯ごとに個別のタイミング(hold+decay)で
## 千切れ始める——弧のスイープ角・太さを狭めて中央にgapを作り2本へ分裂
## させる"形"の変化が主体で、回転速度も裂けが進むほど遅くなる)→
## ⑤b(千切れた帯の両端から生まれる中〜小の断片。敵を中心に弧を描き
## ながら回り込みつつ外側へ流れ、角速度・広がり方ともease-outで減速する)
## →⑤c(最後まで残る1〜2本の細い風。⑤bのどの断片よりも明確に長生きし、
## 敵を軽く回り込む弧を描いたあと外側へ加速しながら抜けて消える)という
## 3段階で徐々に静まる——Follow-through/Overlapping Action/Slow-out/Arcs
## を踏まえた設計。色は白・淡い青白・淡い水色・淡い青緑を主体に、既存
## WIND属性色(motion_catalogのaac68e)を中間色として残している。

var age := -1.0
var origin := Vector2.ZERO          ## 侍の胸元(毎フレーム外部から更新)
var target := Vector2.ZERO          ## 敵の着弾点(毎フレーム外部から更新)
var floor_point := Vector2.ZERO     ## 侍の足元(地面の風圧の基準)
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

## 弧をorigin_pt中心・radius半径でstart_angleからsweep分だけ、reach(0〜1)
## で描き進める。4pxグリッドへスナップされるため、既存の斬撃/雷/氷と
## 同じ荒さになる。
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

## 太い風の帯(リボン): 弧の内周・外周を別々に辿り、太さが始点→終点で
## 変化する帯として塗る——単なる一定幅のstroke()の弧よりも「風の帯が
## 巻いている」厚みを出す。
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
	# inner half must be reversed to close the ribbon shape without a twist.
	var reversed_inner: Array = []
	for i in range(inner.size() - 1, -1, -1):
		reversed_inner.append(inner[i])
	poly(outer + reversed_inner, color)

## 鋭い風帯を1本描く: base→tipの経路に沿って、根元やや細い→中央太い→
## 先端で鋭く尖る紡錘形を、中央付近で一部途切れさせた2ピースで描く——
## 「丸い風の塊」ではなく「引き裂かれた風の奔流」として見せる。暗め外側
## →本体色→中心の明るい芯、の3層をドット絵として段階的に塗り分け、
## 滑らかなグラデーションは使わない。
func _wind_streak(base: Vector2, tip: Vector2, max_width: float, bow: float, alpha: float, body_col: Color) -> void:
	if alpha <= 0.01 or max_width <= 0.5:
		return
	var diff := tip - base
	if diff.length() < 2.0:
		return
	var dir := diff.normalized()
	var n := dir.orthogonal()
	var steps := 8
	var pos: Array = []
	var wid: Array = []
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var bend := sin(u * PI) * bow
		pos.append(base.lerp(tip, u) + n * bend)
		var w := max_width * sin(PI * clampf(u, 0.03, 0.97))
		if u > 0.82:
			w *= (1.0 - u) / 0.18
		wid.append(maxf(w, 0.0))
	# 中央付近(u=0.375〜0.5)を描かずに空けることで、風帯の内部に千切れた
	# 「抜け」を作る——ベタ塗りの物体ではなく圧縮された空気の流れとして
	# 見せる。
	for seg in [[0, 3], [4, steps]]:
		_wind_streak_band(pos, wid, n, seg[0], seg[1], 1.0, WIND_DEEP, alpha * 0.4)
	for seg in [[0, 3], [4, steps]]:
		_wind_streak_band(pos, wid, n, seg[0], seg[1], 0.56, body_col, alpha * 0.85)
	for seg in [[0, 3], [4, steps]]:
		_wind_streak_band(pos, wid, n, seg[0], seg[1], 0.2, CORE_WHITE, alpha)

func _wind_streak_band(pos: Array, wid: Array, n: Vector2, i0: int, i1: int, width_scale: float, color: Color, alpha: float) -> void:
	var outer: Array = []
	var inner: Array = []
	for i in range(i0, i1 + 1):
		var w: float = wid[i] * width_scale
		outer.append(pos[i] + n * w * 0.5)
		inner.append(pos[i] - n * w * 0.5)
	var rev: Array = []
	for i in range(inner.size() - 1, -1, -1):
		rev.append(inner[i])
	poly(outer + rev, color * Color(1, 1, 1, alpha))

## 侍の周囲を大きく回る風: 径90〜200pxの弧6本(氷finishのFROST_HALO/
## SPIKE級の画面占有率が基準)。
const ARCS = [
	{"radius": 92.0, "start_angle": -2.7, "sweep": 2.3, "delay": 0.00, "width": 14.0},
	{"radius": 130.0, "start_angle": -3.0, "sweep": 2.7, "delay": 0.03, "width": 18.0},
	{"radius": 165.0, "start_angle": -2.2, "sweep": 2.1, "delay": 0.06, "width": 13.0},
	{"radius": 200.0, "start_angle": -3.2, "sweep": 3.1, "delay": 0.09, "width": 16.0},
	{"radius": 115.0, "start_angle": 0.35, "sweep": 1.9, "delay": 0.045, "width": 11.0},
	{"radius": 150.0, "start_angle": 0.6, "sweep": 1.6, "delay": 0.075, "width": 9.0},
]

## 太い風の帯4本(径110〜190px)。
const RIBBONS = [
	{"radius": 140.0, "start_angle": -2.5, "sweep": 2.9, "delay": 0.015, "w0": 6.0, "w1": 28.0},
	{"radius": 175.0, "start_angle": -3.1, "sweep": 2.5, "delay": 0.06, "w0": 8.0, "w1": 24.0},
	{"radius": 110.0, "start_angle": -1.7, "sweep": 2.6, "delay": 0.04, "w0": 5.0, "w1": 20.0},
	{"radius": 190.0, "start_angle": 0.2, "sweep": 2.0, "delay": 0.09, "w0": 6.0, "w1": 18.0},
]

## 地面を這う風のウェッジ(不揃いな角ばったくさび、輪でも放射状の細線
## でもない——butler_ice_finish/healer_lightning_finishと同じ思想)。
const GROUND_WEDGES = [
	{"dir": Vector2(-1.0, -0.04), "length": 280.0, "width": 34.0, "delay": 0.00},
	{"dir": Vector2(-0.82, -0.22), "length": 200.0, "width": 24.0, "delay": 0.04},
	{"dir": Vector2(0.55, -0.08), "length": 178.0, "width": 28.0, "delay": 0.02},
	{"dir": Vector2(0.86, -0.20), "length": 280.0, "width": 38.0, "delay": 0.07},
	{"dir": Vector2(0.30, -0.05), "length": 130.0, "width": 20.0, "delay": 0.09},
	{"dir": Vector2(-0.32, -0.05), "length": 140.0, "width": 20.0, "delay": 0.10},
	{"dir": Vector2(0.95, 0.05), "length": 220.0, "width": 26.0, "delay": 0.05},
	{"dir": Vector2(-0.95, 0.05), "length": 170.0, "width": 22.0, "delay": 0.12},
]

## 砂塵の破片(丸い火花ではなく細長い薄片)。
const DUST_A = [0, -8, 5, -2, 2, 6, -4, 3]
const DUST_B = [0, -6, 3, -1, 1, 5, -3, 2]

## 破片(着弾で飛び散る、細長く鋭い薄片2種)。
const SHARD_A = [0, -14, 8, -3, 3, 10, -6, 4]
const SHARD_B = [0, -11, 6, -2, 2, 8, -4, 3]

## 着弾の衝撃波(不揃いな角ばったくさび10方向、角度・長さを意図的に不揃い
## にして輪や均等なサンバーストに見えないようにしている)。
const IMPACT_ANGLES = [0.1, 0.65, 1.15, 1.6, 2.0, 2.55, 3.1, 3.7, 4.3, 5.0]
const IMPACT_LENGTHS = [1.0, 0.65, 1.2, 0.55, 1.1, 0.7, 1.15, 0.6, 1.05, 0.75]
const IMPACT_WEDGE = [-13, 0, -5, -42, 8, -50, 15, -8, 9, 8]

## 着弾の瞬間に大きく広がる風の輪(円弧状/三日月状——完全な均等円には
## しない、既存の_arc()を局所的に大きく使うことで「爆発」を表現する)。
const IMPACT_RINGS = [
	{"radius": 130.0, "start_angle": -3.0, "sweep": 5.6, "delay": 0.00, "width": 16.0},
	{"radius": 185.0, "start_angle": -2.4, "sweep": 5.9, "delay": 0.02, "width": 20.0},
	{"radius": 235.0, "start_angle": -3.3, "sweep": 5.4, "delay": 0.045, "width": 14.0},
]

## 大爆発の直後、敵を中心に大きな風の帯が渦を巻きながら舞う演出。参考
## 画像(鋭く尖った複数の弧状の風帯が対象を囲む)を踏まえ、完全な円形
## リングにはせず、半径・角度・delay・widthをそれぞれ変えた5本の帯を
## 配置している。各帯は"hold"(出現後、裂け始めるまでフル強度を保つ
## 時間)と"decay"(裂け始めてから完全に千切れて⑤bの断片へ引き継がれる
## までの時間)を個別に持ち、5本すべてが同じフレームで裂け始めることが
## ない——(delay+hold+decay)がそのまま各帯の寿命が尽きる時刻になる。
const ENEMY_SWIRL_BANDS = [
	{"angle": -2.6, "arc": 2.3, "radius": 150.0, "delay": 0.00, "width": 26.0, "hold": 0.30, "decay": 0.38},
	{"angle": -0.5, "arc": 2.0, "radius": 125.0, "delay": 0.05, "width": 22.0, "hold": 0.38, "decay": 0.42},
	{"angle": 1.5, "arc": 2.5, "radius": 175.0, "delay": 0.10, "width": 20.0, "hold": 0.48, "decay": 0.40},
	{"angle": 3.3, "arc": 1.8, "radius": 105.0, "delay": 0.04, "width": 24.0, "hold": 0.34, "decay": 0.50},
	{"angle": -4.3, "arc": 2.1, "radius": 195.0, "delay": 0.16, "width": 16.0, "hold": 0.50, "decay": 0.34},
]

## 風の斬撃(および移動する風)が的へ到達する瞬間。刃のtravel完了・
## blade_fade開始・接触表現の開始のすべてをこの1点へ一致させることで、
## 「刃の到達」が着弾から浮いた別ヒットに見えないようにしている。
const IMPACT_START := 0.62

## 着弾(到達)から実際の大爆発が始まるまでの、「タメ」の長さ。「当たった
## →溜まる→さらに圧縮→限界→爆発する」という段階をはっきり感じさせる
## ためだけの値で、爆発そのものの形・大きさ・持続時間には一切影響しない
## ——爆発コード側(および⑤残風・音)の開始時刻をこの分だけ後ろへずらす
## のみ。
const HOLD_DURATION := 20.0 / 60.0
const EXPLOSION_START := IMPACT_START + HOLD_DURATION

## 大爆発(④、EXPLOSION_START〜+0.42)が完全に収まったあとの残風区間の
## 開始時刻と長さ。1.40秒間ずっと同じ大きな風を出し続けるのではなく、
## ⑤a(大きな帯、個別のhold/decayで段階的に千切れる)→⑤b(千切れた帯の
## 両端から生まれる中〜小の断片、弧を描きながら減速して漂う)→⑤c(最後
## まで残る1〜2本の細い風、他のどの断片よりも長く生き延びて弧を描き
## ながら退場する)という3段階を経て徐々に静まっていく構成にしている。
const AFTERMATH_START := EXPLOSION_START + 0.42
const AFTERMATH_DURATION := 1.40

func _draw() -> void:
	if age < 0 or age > AFTERMATH_START + AFTERMATH_DURATION:
		return

	# ①侍の周囲を大きく回る風(0.00-0.38)。
	if age < 0.14:
		var flash_fade := 1.0 - age / 0.14
		var flash_grow := 1.0 - pow(1.0 - clampf(age / 0.07, 0, 1), 2)
		px(origin - Vector2(1, 1) * 70.0 * flash_grow, Vector2(140, 140) * flash_grow, CORE_WHITE * Color(1, 1, 1, flash_fade * 0.55))

	# ARCSの各エントリの"start_angle+sweep*0.5"を代表方向とし、その方向へ
	# 侍のすぐ近くから径radiusまで伸びる風帯を1本ずつ発生させる——「侍を
	# 囲む円形リング」ではなく「刀の振り方向へ斜めに抜ける風」として
	# 見せる。後方には既存の鋭いSHARD破片を残す。
	for arc_i in range(ARCS.size()):
		var arc = ARCS[arc_i]
		var delay: float = arc["delay"]
		var t := age - delay
		if t < 0 or t > 0.36:
			continue
		var reach: float = clampf(t / 0.14, 0, 1)
		var fade: float = clampf(1.0 - (t - 0.17) / 0.19, 0, 1)
		if fade <= 0.001:
			continue
		var w: float = arc["width"]
		var radius: float = arc["radius"]
		var ang: float = float(arc["start_angle"]) + float(arc["sweep"]) * 0.5
		var dirv: Vector2 = Vector2(cos(ang), sin(ang))
		var base_pt: Vector2 = origin + dirv * (radius * 0.22)
		var tip_pt: Vector2 = origin + dirv * (radius * reach)
		var bow: float = sin(float(arc_i) * 2.3) * (radius * 0.10)
		_wind_streak(base_pt, tip_pt, w * 1.7, bow, fade, WIND_TEAL)
		if reach > 0.55:
			var frag_pos: Vector2 = origin + dirv * (radius * reach * 0.62)
			var frag_shape := SHARD_A if arc_i % 2 == 0 else SHARD_B
			poly(_scaled(frag_shape, frag_pos, (0.8 + fmod(float(arc_i), 0.6)) * fade, ang + PI * 0.5), WIND_FROST * Color(1, 1, 1, fade * 0.65))

	for ribbon_i in range(RIBBONS.size()):
		var ribbon = RIBBONS[ribbon_i]
		var delay2: float = ribbon["delay"]
		var t2 := age - delay2
		if t2 < 0 or t2 > 0.34:
			continue
		var reach2: float = clampf(t2 / 0.15, 0, 1)
		var fade2: float = clampf(1.0 - (t2 - 0.15) / 0.18, 0, 1)
		if fade2 <= 0.001:
			continue
		var radius2: float = ribbon["radius"]
		var ang2: float = float(ribbon["start_angle"]) + float(ribbon["sweep"]) * 0.5
		var dirv2: Vector2 = Vector2(cos(ang2), sin(ang2))
		var w1: float = ribbon["w1"]
		var base_pt2: Vector2 = origin + dirv2 * (radius2 * 0.18)
		var tip_pt2: Vector2 = origin + dirv2 * (radius2 * reach2)
		var bow2: float = sin(float(ribbon_i) * 3.1 + 1.4) * (radius2 * 0.13)
		_wind_streak(base_pt2, tip_pt2, w1 * 1.3, bow2, fade2 * 0.9, WIND_FROST)

	# ②足元を走る地面の風圧(0.08-0.42): 足元から左右・敵方向へウェッジ+
	# 砂塵の破片。
	for wedge in GROUND_WEDGES:
		var t3 := age - 0.08 - float(wedge["delay"])
		if t3 < 0 or t3 > 0.30:
			continue
		var grow3: float = 1.0 - pow(1.0 - clampf(t3 / 0.11, 0, 1), 2)
		var fade3: float = clampf(1.0 - (t3 - 0.13) / 0.17, 0, 1)
		if fade3 <= 0.001:
			continue
		var dir: Vector2 = wedge["dir"]
		var length: float = wedge["length"] * grow3
		var wwidth: float = wedge["width"]
		var side := dir.orthogonal() * wwidth * 0.5
		var base := floor_point
		var tip := base + dir * length
		poly([base + side, base - side, tip], WIND_MAIN * Color(1, 1, 1, fade3 * 0.75))
		poly(_scaled([-1, 0, 1, 0, 0, -1], (base + tip) * 0.5, wwidth * 0.4), CORE_WHITE * Color(1, 1, 1, fade3 * 0.5))
	if age >= 0.08 and age < 0.42:
		var dust_fade := clampf((0.42 - age) / 0.26, 0, 1)
		for i in range(12):
			var seed := float(i) * 2.399 + 2.0
			var delay4 := 0.03 + fmod(seed, 0.16)
			var dt4 := maxf(0.0, (age - 0.08) - delay4)
			if dt4 <= 0 or dt4 > 0.30:
				continue
			var side_sign := 1.0 if i % 2 == 0 else -1.0
			var dir4 := Vector2(side_sign * (0.7 + fmod(seed, 0.3)), -0.15 - fmod(seed, 0.2)).normalized()
			var p4 := floor_point + dir4 * (18.0 + dt4 * 190.0) + Vector2(0, -8.0 - dt4 * 34.0)
			var shape4 := DUST_A if i % 2 == 0 else DUST_B
			poly(_scaled(shape4, p4, 0.9 + fmod(seed, 0.6), dir4.angle() + PI * 0.5), WIND_FROST * Color(1, 1, 1, dust_fade))

	# ③刀に沿った巨大な風の斬撃(0.25-0.85): 三日月型の刃が生まれ、敵の
	# 位置まで飛ぶ。
	if age >= 0.25 and age < IMPACT_START + 0.14:
		var travel := clampf((age - 0.30) / (IMPACT_START - 0.30), 0, 1)
		var blade_grow := 1.0 - pow(1.0 - clampf((age - 0.25) / 0.10, 0, 1), 2)
		# 刀元で発生する扇状の風(解放バースト)は発生直後の0.16秒だけに
		# 限定し、そのあとは下の独立した「移動する風」フェーズへ完全に
		# 引き継ぐ——着弾用エフェクトが敵の近くでずっと動いて見える問題を
		# 避けるための構成。
		var blade_fade := clampf(1.0 - (age - 0.25) / 0.16, 0, 1)
		if blade_fade > 0.001 and blade_grow > 0.001:
			var travel_eased := 1.0 - pow(1.0 - travel, 3)
			var blade_pos := origin.lerp(target, travel_eased)
			var dir5 := (target - origin).normalized()
			var half_sweep := 1.1
			var center_angle := dir5.angle()
			var blade_start := center_angle - half_sweep
			var blade_radius := 145.0 * blade_grow
			# 後方へちぎれる風の塊。
			for i in range(3):
				var trail_u := clampf(travel_eased - float(i + 1) * 0.11, 0, 1)
				if trail_u <= 0:
					continue
				var trail_pos := origin.lerp(target, trail_u)
				var trail_fade := blade_fade * (1.0 - float(i) / 3.0) * 0.65
				var trail_shape := SHARD_A if i % 2 == 0 else SHARD_B
				poly(_scaled(trail_shape, trail_pos + dir5.orthogonal() * (16.0 - i * 4.0), 1.5 - float(i) * 0.25, dir5.angle() + PI * 0.5), WIND_TEAL * Color(1, 1, 1, trail_fade))
			for i in range(2):
				var trail_u2 := clampf(travel_eased - float(i + 1) * 0.09, 0, 1)
				if trail_u2 <= 0:
					continue
				var trail_pos2 := origin.lerp(target, trail_u2)
				var trail_fade2 := blade_fade * (1.0 - float(i) / 2.0) * 0.4
				stroke(trail_pos2 + dir5.orthogonal() * (20.0 - i * 4.0), trail_pos2 - dir5.orthogonal() * (20.0 - i * 4.0), 4.0, WIND_FROST * Color(1, 1, 1, trail_fade2))
			# 圧縮された風の奔流(本体): 三日月の扇に沿って、中央(進行方向
			# 側)ほど太く長い鋭い風帯、両端(後方側)ほど細く短い風帯を放射状
			# に配置する——「侍から敵方向へ切り抜ける複数本の風の奔流」。
			for i in range(7):
				var frac3 := float(i) / 6.0
				var ang3 := blade_start + half_sweep * 2.0 * frac3
				var front_bias: float = 1.0 - absf(frac3 - 0.5) * 1.7
				if front_bias < 0.1:
					continue
				var dirv3 := Vector2(cos(ang3), sin(ang3))
				var inner_r := blade_radius * 0.18
				var outer_r := blade_radius * (0.7 + front_bias * 0.55)
				var base_pt3 := blade_pos + dirv3 * inner_r
				var tip_pt3 := blade_pos + dirv3 * (outer_r * blade_grow)
				var bow3 := sin(float(i) * 1.9) * (blade_radius * 0.06)
				var streak_w := (9.0 + front_bias * 26.0) * blade_grow
				_wind_streak(base_pt3, tip_pt3, streak_w, bow3, blade_fade * (0.6 + front_bias * 0.4), WIND_FROST)
			# 進行方向の中心軸に沿う、最も長く太い一本(最前面の切っ先)。
			_wind_streak(blade_pos + dir5 * (blade_radius * 0.1), blade_pos + dir5 * (blade_radius * 1.05 * blade_grow), 34.0 * blade_grow, 0.0, blade_fade, WIND_FROST)
			# 周囲へ散る細かな乱流の風片。
			for i in range(4):
				var seed9 := float(i) * 2.7 + 3.0
				var ang4 := blade_start + half_sweep * 2.0 * fmod(seed9, 1.0)
				var jitter_r := blade_radius * (0.55 + fmod(seed9, 0.55))
				var p9 := blade_pos + Vector2(cos(ang4), sin(ang4)) * jitter_r
				var shape9 := SHARD_A if i % 2 == 0 else SHARD_B
				poly(_scaled(shape9, p9, (0.6 + fmod(seed9, 0.4)) * blade_grow, ang4 + PI * 0.5), WIND_FROST * Color(1, 1, 1, blade_fade * 0.5))

		# ③b 侍から敵へ移動する風: 上の刀元の解放バーストとも、下の着弾
		# エフェクトとも完全に別個の描画。age=0.28からIMPACT_STARTまでの
		# 間だけ存在し、smoothstepでほぼ一定速度に移動して、IMPACT_STARTの
		# 瞬間にちょうど敵へ到達して消える。
		var comet_start := 0.28
		if age >= comet_start and age < IMPACT_START:
			var comet_progress: float = clampf((age - comet_start) / (IMPACT_START - comet_start), 0, 1)
			var comet_eased: float = comet_progress * comet_progress * (3.0 - 2.0 * comet_progress)
			var comet_in: float = clampf((age - comet_start) / 0.05, 0, 1)
			var dir6 := (target - origin).normalized()
			var perp6 := dir6.orthogonal()
			var wobble: float = sin(age * 46.0) * 7.0 * (1.0 - comet_progress * 0.6)
			var comet_head: Vector2 = origin.lerp(target, comet_eased) + perp6 * wobble
			var tail_len: float = lerpf(30.0, 95.0, comet_progress)
			var head_len: float = 16.0 + sin(age * 30.0) * 4.0
			var lane_gap: float = 13.0
			for lane in range(3):
				var lane_off: float = float(lane - 1) * lane_gap
				var base6: Vector2 = comet_head - dir6 * tail_len + perp6 * lane_off
				var tip6: Vector2 = comet_head + dir6 * head_len + perp6 * (lane_off * 0.4)
				var lane_w: float = 16.0 - absf(float(lane - 1)) * 4.0
				_wind_streak(base6, tip6, lane_w, wobble * 0.4, comet_in * (0.85 - absf(float(lane - 1)) * 0.15), WIND_FROST)
			# 後方へ千切れる風片。
			for i in range(3):
				var seed10 := float(i) * 2.9 + 1.0
				var drop_u: float = clampf(comet_progress - float(i + 1) * 0.12, 0, 1)
				if drop_u <= 0.0:
					continue
				var drop_pos: Vector2 = origin.lerp(target, drop_u) + perp6 * (sin(seed10 * 3.0) * 10.0)
				var frag_fade10: float = comet_in * (1.0 - float(i) / 3.0) * 0.6
				var shape10 := SHARD_A if i % 2 == 0 else SHARD_B
				poly(_scaled(shape10, drop_pos, 1.0 - float(i) * 0.15, dir6.angle() + PI * 0.5), WIND_TEAL * Color(1, 1, 1, frag_fade10))

	# ④a 着弾の接触〜タメ(IMPACT_START〜EXPLOSION_START): 風が敵へ実際に
	# 到達したことを示す小さな接触の光と、大爆発が始まる直前の「タメ」。
	if age >= IMPACT_START and age < EXPLOSION_START:
		var hold_t: float = clampf((age - IMPACT_START) / HOLD_DURATION, 0, 1)
		var contact_fade: float = clampf(1.0 - hold_t / 0.25, 0, 1)
		if contact_fade > 0.001:
			var contact_grow: float = 1.0 - pow(1.0 - clampf(hold_t / 0.16, 0, 1), 2)
			px(target - Vector2(1, 1) * 26.0 * contact_grow, Vector2(52, 52) * contact_grow, CORE_WHITE * Color(1, 1, 1, contact_fade * 0.85))
		var pulse: float = 0.85 + sin(hold_t * PI * 3.0) * 0.15 * (1.0 - hold_t * 0.5)
		for i in range(4):
			var seed_h := float(i) * 2.2 + 1.0
			var ang_h := seed_h * 2.3 + age * 22.0
			var r_h := (10.0 + hold_t * 14.0) * pulse
			var p_h := target + Vector2(cos(ang_h), sin(ang_h) * 0.8) * r_h
			var shape_h := SHARD_A if i % 2 == 0 else SHARD_B
			poly(_scaled(shape_h, p_h, 0.5 + hold_t * 0.4, ang_h + PI * 0.5), WIND_FROST * Color(1, 1, 1, 0.55 + hold_t * 0.35))
		# 予兆の閃光: タメの終盤だけ、着弾地点の明るさを爆発サイズまで
		# 広げずにほんの少しだけ強める——「限界に達した」合図。
		if hold_t > 0.82:
			var pre_u: float = clampf((hold_t - 0.82) / 0.18, 0, 1)
			px(target - Vector2(1, 1) * 22.0 * pre_u, Vector2(44, 44) * pre_u, CORE_WHITE * Color(1, 1, 1, pre_u * 0.7))

	# ④敵への着弾・大爆発(EXPLOSION_START〜+0.42): 強い閃光+大きく広がる
	# 風の輪(円弧状)3本+角ばった衝撃波+破片。氷/炎の大技フィニッシュと
	# 同格の画面占有率(半径200px超級)。
	if age >= EXPLOSION_START and age < EXPLOSION_START + 0.42:
		var it := age - EXPLOSION_START
		var impact_center := target
		if it < 0.12:
			var iflash := 1.0 - it / 0.12
			var flash_grow: float = 1.0 - pow(1.0 - clampf(it / 0.06, 0, 1), 2)
			px(impact_center - Vector2(1, 1) * 130.0 * flash_grow, Vector2(260, 260) * flash_grow, CORE_WHITE * Color(1, 1, 1, iflash * 0.9))
			px(impact_center - Vector2(1, 1) * 78.0 * flash_grow, Vector2(156, 156) * flash_grow, WIND_FROST * Color(1, 1, 1, iflash))
		for ring in IMPACT_RINGS:
			var delay6: float = ring["delay"]
			var t6 := it - delay6
			if t6 < 0 or t6 > 0.32:
				continue
			var reach6: float = 1.0 - pow(1.0 - clampf(t6 / 0.10, 0, 1), 2)
			var fade6: float = clampf(1.0 - (t6 - 0.12) / 0.18, 0, 1)
			if fade6 <= 0.001:
				continue
			var w6: float = ring["width"]
			_arc(impact_center, float(ring["radius"]) * reach6, float(ring["start_angle"]), float(ring["sweep"]), 1.0, w6 + 5.0, WIND_DEEP * Color(1, 1, 1, fade6 * 0.55))
			_arc(impact_center, float(ring["radius"]) * reach6, float(ring["start_angle"]), float(ring["sweep"]), 1.0, w6, WIND_MAIN * Color(1, 1, 1, fade6 * 0.95))
			_arc(impact_center, float(ring["radius"]) * reach6, float(ring["start_angle"]), float(ring["sweep"]), 1.0, w6 * 0.4, CORE_WHITE * Color(1, 1, 1, fade6))
		var burst_grow: float = 1.0 - pow(1.0 - clampf(it / 0.13, 0, 1), 2)
		var burst_fade: float = clampf(1.0 - (it - 0.13) / 0.24, 0, 1)
		if burst_fade > 0.001:
			for i in range(IMPACT_ANGLES.size()):
				var angle6: float = IMPACT_ANGLES[i]
				var len6: float = IMPACT_LENGTHS[i]
				var dir6 := Vector2(cos(angle6), sin(angle6) * 0.8 - 0.1)
				var p6 := impact_center + dir6 * (burst_grow * 225.0 * len6)
				var col6: Color = WIND_MAIN if i % 2 == 0 else WIND_TEAL
				poly(_scaled(IMPACT_WEDGE, p6, (1.5 + len6 * 1.15) * burst_grow, angle6 + PI * 0.5), col6 * Color(1, 1, 1, burst_fade))
		var frag_fade: float = clampf(1.0 - (it - 0.10) / 0.30, 0, 1)
		if it >= 0.10 and frag_fade > 0.001:
			for i in range(22):
				var seed7 := float(i) * 2.399 + 4.0
				var dir7 := Vector2(cos(seed7 * 1.6), sin(seed7 * 1.6) * 0.85 - 0.15)
				var dt7 := clampf((it - 0.10 - float(i % 4) * 0.03) / 0.27, 0, 1)
				var p7 := impact_center + dir7 * (30.0 + dt7 * 250.0)
				var shape7 := SHARD_A if i % 2 == 0 else SHARD_B
				var col7: Color = CORE_WHITE if i % 3 == 0 else (WIND_MAIN if i % 3 == 1 else WIND_TEAL)
				poly(_scaled(shape7, p7, (1.7 + fmod(seed7, 0.9)) * (1.0 - dt7 * 0.25), dir7.angle() + PI * 0.5), col7 * Color(1, 1, 1, frag_fade))

	# ⑤大爆発後の残風(AFTERMATH_START〜+AFTERMATH_DURATION)。
	if age >= AFTERMATH_START and age < AFTERMATH_START + AFTERMATH_DURATION:
		var at := age - AFTERMATH_START

		# ⑤a 敵を中心に大きな風の帯が渦を巻く。
		for i in range(ENEMY_SWIRL_BANDS.size()):
			var band = ENEMY_SWIRL_BANDS[i]
			var b_delay: float = band["delay"]
			var bt: float = at - b_delay
			var hold_end: float = band["hold"]
			var decay_dur: float = band["decay"]
			var tear_time: float = hold_end + decay_dur
			if bt < 0 or bt > tear_time:
				continue
			var grow: float = 1.0 - pow(1.0 - clampf(bt / 0.30, 0, 1), 2)
			if grow <= 0.02:
				continue
			var ang: float = band["angle"]
			var arcw: float = band["arc"]
			var radius: float = band["radius"]
			var w: float = float(band["width"])
			var decay_t: float = clampf((bt - hold_end) / decay_dur, 0, 1) if bt > hold_end else 0.0
			var spin_speed: float = 0.5 * (1.0 - decay_t * 0.7)
			var ang_drift: float = ang + spin_speed * minf(bt, tear_time)
			var eff_arc: float = arcw * (1.0 - decay_t * 0.4)
			var eff_w: float = w * (1.0 - decay_t * 0.3)
			var b_alpha: float = grow * (1.0 - decay_t * 0.55)
			if b_alpha <= 0.02:
				continue
			if decay_t < 0.4:
				_ribbon(target, radius, ang_drift, eff_arc, grow, eff_w * 0.12, eff_w, WIND_DEEP * Color(1, 1, 1, b_alpha * 0.5))
				_ribbon(target, radius, ang_drift, eff_arc, grow, eff_w * 0.10, eff_w * 0.72, WIND_TEAL * Color(1, 1, 1, b_alpha * 0.9))
				_arc(target, radius, ang_drift, eff_arc, grow, eff_w * 0.24, CORE_WHITE * Color(1, 1, 1, b_alpha))
			else:
				# decay_t>=0.4: 中央にgapが広がりながら2本の短い帯へ分裂
				# していく(大きな帯→中サイズの帯2本、という"形"の変化)。
				var split_t: float = (decay_t - 0.4) / 0.6
				var gap: float = eff_arc * 0.5 * split_t
				var half_arc: float = maxf(eff_arc * 0.5 - gap, 0.03)
				_ribbon(target, radius, ang_drift, half_arc, 1.0, eff_w * 0.10, eff_w * 0.7, WIND_TEAL * Color(1, 1, 1, b_alpha * 0.85))
				_arc(target, radius, ang_drift, half_arc, 1.0, eff_w * 0.22, CORE_WHITE * Color(1, 1, 1, b_alpha))
				var second_start: float = ang_drift + eff_arc * 0.5 + gap
				_ribbon(target, radius, second_start, half_arc, 1.0, eff_w * 0.7, eff_w * 0.10, WIND_TEAL * Color(1, 1, 1, b_alpha * 0.85))
				_arc(target, radius, second_start, half_arc, 1.0, eff_w * 0.22, CORE_WHITE * Color(1, 1, 1, b_alpha))

		# ⑤b 千切れた帯の両端(2ヶ所)から生まれる中〜小サイズの断片。
		for k in range(10):
			var band_idx: int = k / 2
			var end_idx: int = k % 2
			var fband = ENEMY_SWIRL_BANDS[band_idx]
			var f_tear: float = float(fband["delay"]) + float(fband["hold"]) + float(fband["decay"])
			var f_life: float = 0.30 + 0.05 * float(k % 3)
			var ft: float = at - f_tear
			if ft < 0 or ft > f_life:
				continue
			var ftn: float = ft / f_life
			var decel: float = 1.0 - pow(1.0 - ftn, 2)
			var frag_angle0: float = float(fband["angle"]) if end_idx == 0 else float(fband["angle"]) + float(fband["arc"])
			var spin_dir: float = -1.0 if end_idx == 0 else 1.0
			var f_ang: float = frag_angle0 + spin_dir * 0.9 * decel
			var f_radius: float = float(fband["radius"]) + 35.0 * decel
			var f_arc: float = lerpf(float(fband["arc"]) * 0.22, 0.05, ftn)
			var f_w: float = float(fband["width"]) * lerpf(0.5, 0.10, ftn)
			var f_alpha: float = clampf(1.0 - maxf(0.0, (ftn - 0.55) / 0.45), 0, 1) * 0.75
			if f_alpha <= 0.02:
				continue
			_arc(target, f_radius, f_ang, f_arc, 1.0, f_w + 3.0, WIND_DEEP * Color(1, 1, 1, f_alpha * 0.5))
			_arc(target, f_radius, f_ang, f_arc, 1.0, f_w, WIND_TEAL * Color(1, 1, 1, f_alpha * 0.9))
			_arc(target, f_radius, f_ang, f_arc, 1.0, f_w * 0.35, CORE_WHITE * Color(1, 1, 1, f_alpha))

		# ⑤c 最後まで残る1〜2本の細い風。
		var final_wisps := [
			{"start": 0.78, "angle": 2.3, "spin": -1.0, "radius": 60.0, "col": WIND_FROST},
			{"start": 0.90, "angle": -0.4, "spin": 1.0, "radius": 70.0, "col": WIND_TEAL},
		]
		for fw in final_wisps:
			var fw_start: float = fw["start"]
			var fw_life: float = AFTERMATH_DURATION - fw_start
			var fw_ft: float = at - fw_start
			if fw_ft < 0 or fw_ft > fw_life or fw_life <= 0.01:
				continue
			var fw_n: float = fw_ft / fw_life
			var curve_e: float = 1.0 - pow(1.0 - clampf(fw_n / 0.7, 0, 1), 2)
			var release_e: float = clampf((fw_n - 0.6) / 0.4, 0, 1)
			release_e = release_e * release_e
			var fw_ang: float = float(fw["angle"]) + float(fw["spin"]) * 1.1 * curve_e
			var fw_radius: float = float(fw["radius"]) + 40.0 * curve_e + 90.0 * release_e
			var fw_arc: float = lerpf(0.5, 0.05, fw_n)
			var fw_w: float = lerpf(10.0, 2.0, fw_n)
			var fw_alpha: float = (1.0 - fw_n) * 0.55
			if fw_alpha <= 0.01:
				continue
			var fw_col: Color = fw["col"]
			_arc(target, fw_radius, fw_ang, fw_arc, 1.0, fw_w, fw_col * Color(1, 1, 1, fw_alpha * 0.85))
			_arc(target, fw_radius, fw_ang, fw_arc * 0.5, 1.0, fw_w * 0.35, CORE_WHITE * Color(1, 1, 1, fw_alpha))
