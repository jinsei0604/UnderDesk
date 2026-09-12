extends Node2D

## 雷属性の少女ヒーラーの単体攻撃(healer_shock)着弾フィニッシュ。
## rbm_hero_fire_finish.gd/rbm_butler_ice_finish.gdと同じ手法(px/poly/
## stroke、外部からageを渡されるだけのNode2D)を踏襲するが、シルエット・
## 色・段階構成は雷専用(「落雷→着弾→弾ける→残光」、炎の「収束→白熱→
## 爆発」・氷の「凍結→静止→破砕」とは別の個性)。healer_shockは必殺技
## ではなく通常攻撃スキルのため、hero/butlerの必殺技フィニッシュより
## 速く・小ぶりに作ってある。
##
## 段階構成(合計 約0.85秒、雷らしく速く・鋭く):
##   雷(0.00-0.22): 幹(トランク)が上空から着弾点へ不規則にジグザグしながら
##     一気に伸び、途中3か所から細い副放電(ブランチ)が分岐する。単純な
##     直線1本ではなく、手作りの不規則な枝分かれ。何の前触れもなく始まる。
##   着弾(0.18-0.30): 幹が到達した瞬間、控えめな白熱フラッシュ(キャラクター
##     が見えなくなるほど強くはしない)と、地面を這う数本の角ばった放電
##     ウェッジ(butler_ice_finishのSHOCK_WEDGEと同じ思想: 輪でも放射状の
##     細線でもない)。
##   着弾爆発(0.25-0.47): 着弾フラッシュが収まり始めた直後(60fpsで約3
##     フレーム後)、着弾地点でもう一段階はっきりと弾ける。閃光コア→
##     不規則な衝撃バースト(角度・長さを不揃いにした8本のくさび、ピーク
##     直径は敵の体格の3〜4割程度)→電気の破片8個、という3段構成。
##   残光/放電(0.30-0.75): 爆発が収まった後、着弾点付近で短い副放電が
##     2回ちらつき、小さな火花(モート)が数個舞い上がって消える。
##   終了(0.75-0.85): 何も残らず消える。
##
## ヒーラーらしさ: メインは既存LIGHTNING属性色(motion_catalogのe4c76b)に
## 近い金色だが、杖の紫の宝石を連想する淡い紫の火花を残光・爆発にわずかに
## 混ぜ、「誰の雷でも同じ」にならないようにしている。

var age := -1.0
var floor_point := Vector2.ZERO
var canvas_size := Vector2(1280, 720)

const CORE_WHITE = Color('#fffbe6')
const BOLT_MAIN = Color('#ffe37a')
const BOLT_EDGE = Color('#e4c76b')
const SPARK_VIOLET = Color('#c9a6ff')
const GROUND_GLOW = Color('#f2b23d')

# 幹: 着弾点の上空(origin=(0,0))から着弾点付近(下方向,+y)まで、
# 不規則に左右へ振れながら降りてくる9セグメントの折れ線。直線でもなく、
# 等間隔なジグザグでもない――手作りの不規則さを保つ。
const BOLT_TRUNK = [0, 0, 30, 50, -10, 92, 36, 140, 6, 188, 48, 236, 14, 288, 42, 344, 4, 400, 24, 446]

# 副放電: 幹の途中(それぞれ異なる頂点)から分岐する、短く細い枝。
# 分岐位置・向き・長さはすべて異なる(同じ形の使い回しではない)。
const BOLT_BRANCHES = [
	{"from_vertex": 1, "path": [30, 50, 66, 40, 94, 58]},
	{"from_vertex": 2, "path": [-10, 92, -56, 118, -88, 160]},
	{"from_vertex": 4, "path": [6, 188, 62, 210, 108, 250]},
	{"from_vertex": 6, "path": [14, 288, -34, 312, -70, 350]},
]

# 着弾時の地面放電: butler_ice_finishのSHOCK_WEDGEと同じ思想
# (輪でも放射状の細線でもない、数本の不揃いな角ばったくさび形)。
const GROUND_WEDGE_A = [-10, 4, 58, -8, 68, 2, 14, 10]
const GROUND_WEDGE_B = [8, 4, -50, -10, -60, 0, -12, 10]
const GROUND_WEDGE_C = [-6, 2, 34, -14, 44, -2, 8, 8]

# 残光の副放電フリッカー: 幹よりずっと短い、着弾点付近だけの小さな枝2種。
const AFTER_ARC_A = [0, 0, -22, -18, -40, -44]
const AFTER_ARC_B = [0, 0, 26, -14, 46, -38]

# 火花モート(残光で舞い上がる小さな粒): 星形にならない非対称な小片。
const SPARK_MOTE_A = [0, -6, 4, -1, 2, 5, -3, 3]
const SPARK_MOTE_B = [0, -5, 3, 0, 1, 4, -3, 2]

# 着弾爆発: 火属性のような丸い火球にはせず、不規則な閃光コアと、そこから
# 飛び散る角ばった小さな破片(雷の破片、SPARK_MOTEより鋭く速い)で構成
# する。コアは8点の非対称な多角形――円でも整った星形でもない。
const EXPLOSION_CORE = [0, -16, 11, -8, 15, 3, 7, 13, -3, 15, -13, 6, -16, -4, -8, -13]
const EXPLOSION_SHARD_A = [0, -8, 5, -2, 2, 6, -4, 3]
const EXPLOSION_SHARD_B = [0, -7, 4, -1, 1, 5, -4, 2]

# 衝撃バースト: 中心から外側へ広がる、角度・長さを意図的に不揃いにした
# 角ばったくさび1種(EXPLOSION_WEDGE)を8方向へ配置する。角度は均等な
# 45度刻みではなく、長さ倍率も交互に大小をつけており、整った"輪"や
# 均等な放射状の"サンバースト"には見えないようにしている。
const EXPLOSION_WEDGE = [-9, 0, -4, -30, 5, -34, 10, -6, 6, 4]
const EXPLOSION_BURST_ANGLES = [0.15, 0.95, 1.55, 2.15, 2.85, 3.65, 4.35, 5.25]
const EXPLOSION_BURST_LENGTHS = [1.0, 0.65, 1.15, 0.55, 0.9, 0.7, 1.2, 0.6]

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

## 折れ線(幹または枝)をorigin基準でgrowth区間分だけ描き進める。先端の
## 座標を返す(枝が幹の途中頂点から伸びられるように)。
## butler_ice_finish.gd grow_path()と同じ考え方。
func grow_path(points: Array, growth: float, width: float, color: Color, origin: Vector2) -> Vector2:
	var count := points.size() / 2
	var reach := clampf(growth, 0, float(count - 1))
	var tip := origin + Vector2(points[0], points[1])
	for seg in range(count - 1):
		var seg_u := clampf(reach - float(seg), 0, 1)
		if seg_u <= 0:
			break
		var a := origin + Vector2(points[seg * 2], points[seg * 2 + 1])
		var full_b := origin + Vector2(points[(seg + 1) * 2], points[(seg + 1) * 2 + 1])
		var b := a.lerp(full_b, seg_u)
		stroke(a, b, width, color)
		tip = b
	return tip

func _draw() -> void:
	if age < 0 or age > 0.85:
		return
	var origin := floor_point + Vector2(-4, -450)

	# --- 雷(0.05-0.22): 何の前触れもなく、幹が不規則にジグザグしながら
	# 一気に着弾点まで伸び、途中3か所から細い副放電が分岐する。
	var trunk_u := clampf((age - 0.05) / 0.17, 0, 1)
	var trunk_grow := 1.0 - pow(1.0 - trunk_u, 3)
	var trunk_count := BOLT_TRUNK.size() / 2
	# 残光フェードで幹全体の不透明度を落とす(0.22以降ゆっくり消える)。
	var trunk_fade := 1.0
	if age >= 0.22:
		trunk_fade = clampf(1.0 - (age - 0.22) / 0.33, 0, 1)
	if trunk_grow > 0.001 and trunk_fade > 0.001:
		var reach := trunk_grow * float(trunk_count - 1)
		# 外側の太い縁取りストローク(暗め)を先に、内側の明るい芯を後に重ねる
		# ――単なる1本線ではなく、芯と縁を持つ「太さのある雷」にする。
		grow_path(BOLT_TRUNK, reach, 9.0, BOLT_EDGE * Color(1, 1, 1, trunk_fade * 0.85), origin)
		grow_path(BOLT_TRUNK, reach, 4.0, BOLT_MAIN * Color(1, 1, 1, trunk_fade), origin)
		grow_path(BOLT_TRUNK, reach, 2.0, CORE_WHITE * Color(1, 1, 1, trunk_fade * 0.9), origin)
		for branch in BOLT_BRANCHES:
			var from_vertex: int = branch["from_vertex"]
			if reach >= float(from_vertex) - 0.05:
				var branch_reach := clampf((reach - float(from_vertex)) * 1.6, 0, 2)
				var branch_path: Array = branch["path"]
				grow_path(branch_path, branch_reach, 4.0, BOLT_EDGE * Color(1, 1, 1, trunk_fade * 0.7), origin)
				grow_path(branch_path, branch_reach, 2.0, BOLT_MAIN * Color(1, 1, 1, trunk_fade * 0.85), origin)

	# --- 着弾(0.18-0.30): 到達の瞬間、控えめな白熱フラッシュ(キャラクター
	# が見えなくなるほど強くはしない)と、地面を這う角ばった放電ウェッジ。
	if age >= 0.18 and age < 0.30:
		var impact_u := clampf((age - 0.18) / 0.12, 0, 1)
		if age < 0.24:
			var flash := clampf(1.0 - (age - 0.18) / 0.06, 0, 1)
			px(Vector2.ZERO, canvas_size, Color(1.0, 0.97, 0.85, 0.5 * flash))
		var burst_grow := 1.0 - pow(1.0 - clampf(impact_u * 1.6, 0, 1), 2)
		var burst_fade := clampf(1.0 - impact_u, 0, 1)
		var jitter := Vector2(sin(age * 400.0), cos(age * 340.0)) * (6.0 * clampf(1.0 - impact_u * 2.0, 0, 1))
		var ground := floor_point + jitter
		poly(_scaled(GROUND_WEDGE_A, ground, burst_grow), GROUND_GLOW * Color(1, 1, 1, burst_fade))
		poly(_scaled(GROUND_WEDGE_B, ground, burst_grow * 0.85), BOLT_MAIN * Color(1, 1, 1, burst_fade))
		poly(_scaled(GROUND_WEDGE_C, ground, burst_grow * 0.7), GROUND_GLOW * Color(1, 1, 1, burst_fade))
		px(ground + Vector2(-8, -14), Vector2(16, 16) * burst_grow, CORE_WHITE * Color(1, 1, 1, burst_fade * 0.9))

	# --- 着弾爆発(0.25-0.47): 着弾フラッシュ(0.18-0.30)が収まり始めた
	# 直後、60fpsで約3フレーム後に、着弾地点で明確にもう一段階の爆発を
	# 起こす――「雷が消えるだけ」で終わらせず、直撃→フラッシュ→爆発→
	# 残光、の4段階を目視ではっきり区別できるようにする。火属性のような
	# 滑らかな円形火球にはせず、角ばった多角形とくさびだけで構成し
	# (draw_circle等の滑らかな図形は一切使わない)、地面を這うGROUND_WEDGE
	# とは別に、着弾点そのものが弾ける瞬間を担う。ピーク時の直径は敵の
	# 体格(golemで高さ約180px)の3〜4割程度に収め、敵全体は隠さない。
	if age >= 0.25 and age < 0.47:
		var boom_t := age - 0.25
		var boom_center := floor_point + Vector2(0, -22)

		# 閃光(0.00-0.05s): 小さく強い白〜黄色の閃光コア。
		var flash_fade := clampf(1.0 - boom_t / 0.09, 0, 1)
		if flash_fade > 0.001:
			var flash_grow := 1.0 - pow(1.0 - clampf(boom_t / 0.05, 0, 1), 2)
			poly(_scaled(EXPLOSION_CORE, boom_center, flash_grow * 2.2), CORE_WHITE * Color(1, 1, 1, flash_fade))
			poly(_scaled(EXPLOSION_CORE, boom_center, flash_grow * 1.5), BOLT_MAIN * Color(1, 1, 1, flash_fade * 0.9))

		# 衝撃バースト(0.02-0.16s): 不規則な角ばったくさびが一気に外側へ
		# 広がり、ピーク直後に縮んで消える。
		var burst_fade := clampf(1.0 - (boom_t - 0.05) / 0.11, 0, 1)
		if boom_t >= 0.02 and burst_fade > 0.001:
			var burst_grow := 1.0 - pow(1.0 - clampf((boom_t - 0.02) / 0.09, 0, 1), 2)
			for i in range(EXPLOSION_BURST_ANGLES.size()):
				var wedge_angle: float = EXPLOSION_BURST_ANGLES[i]
				var wedge_len: float = EXPLOSION_BURST_LENGTHS[i]
				var wedge_dir := Vector2(cos(wedge_angle), sin(wedge_angle) * 0.75 - 0.15)
				var wedge_p := boom_center + wedge_dir * (burst_grow * 62.0 * wedge_len * 0.6)
				var wedge_col: Color = BOLT_MAIN if i % 2 == 0 else GROUND_GLOW
				poly(_scaled(EXPLOSION_WEDGE, wedge_p, (0.7 + wedge_len * 0.5) * burst_grow, wedge_angle + PI * 0.5), wedge_col * Color(1, 1, 1, burst_fade))

		# 破片(0.05-0.22s): 電気を帯びた小さな破片が数個、外側へ飛び散る。
		var frag_fade := clampf(1.0 - (boom_t - 0.05) / 0.17, 0, 1)
		if boom_t >= 0.05 and frag_fade > 0.001:
			for i in range(8):
				var frag_seed := float(i) * 2.399 + 3.0
				var frag_dir := Vector2(cos(frag_seed * 1.7), sin(frag_seed * 1.7) * 0.8 - 0.2)
				var frag_dt := clampf((boom_t - 0.05 - float(i % 4) * 0.02) / 0.16, 0, 1)
				var frag_p := boom_center + frag_dir * (16.0 + frag_dt * 64.0)
				var frag_shape := EXPLOSION_SHARD_A if i % 2 == 0 else EXPLOSION_SHARD_B
				var frag_col: Color = BOLT_MAIN if i % 3 != 0 else SPARK_VIOLET
				poly(_scaled(frag_shape, frag_p, (1.2 + fmod(frag_seed, 0.7)) * (1.0 - frag_dt * 0.3)), frag_col * Color(1, 1, 1, frag_fade))

	# --- 残光/放電(0.30-0.75): 爆発が収まった後、着弾点付近で短い副放電が
	# 2回ちらつき、小さな火花(モート)が数個舞い上がって消える。
	if age >= 0.36 and age < 0.46:
		var flick_u := clampf((age - 0.36) / 0.06, 0, 1)
		var flick_fade := 1.0 - flick_u
		grow_path(AFTER_ARC_A, flick_u * 2.0, 3.0, SPARK_VIOLET * Color(1, 1, 1, flick_fade), floor_point + Vector2(-14, -20))
	if age >= 0.50 and age < 0.58:
		var flick_u2 := clampf((age - 0.50) / 0.06, 0, 1)
		var flick_fade2 := 1.0 - flick_u2
		grow_path(AFTER_ARC_B, flick_u2 * 2.0, 3.0, BOLT_MAIN * Color(1, 1, 1, flick_fade2), floor_point + Vector2(10, -18))
	if age >= 0.30 and age < 0.75:
		var mote_fade := clampf((0.75 - age) / 0.30, 0, 1)
		for i in range(7):
			var seed := float(i) * 2.399
			var delay := 0.02 + fmod(seed, 0.18)
			var dt := maxf(0.0, (age - 0.30) - delay)
			if dt <= 0 or dt > 0.5:
				continue
			var drift := Vector2(cos(seed) * 26.0, -60.0) * clampf(dt / 0.5, 0, 1) * dt
			var p := floor_point + Vector2(-16 + fmod(seed * 37.0, 32.0), -18) + drift
			var col: Color = BOLT_MAIN if i % 3 != 0 else SPARK_VIOLET
			var shape := SPARK_MOTE_A if i % 2 == 0 else SPARK_MOTE_B
			poly(_scaled(shape, p, 0.9 + fmod(seed, 0.4)), col * Color(1, 1, 1, mote_fade))

func _scaled(coords: Array, origin: Vector2, extent: float, rot: float = 0.0) -> Array:
	var points: Array = []
	for i in range(0, coords.size(), 2):
		var p := Vector2(coords[i], coords[i + 1])
		if rot != 0.0:
			p = p.rotated(rot)
		points.append(origin + p * extent)
	return points
