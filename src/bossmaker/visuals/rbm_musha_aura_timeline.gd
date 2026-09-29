extends RefCounted
## 朽ちた機械武者の覚醒後の常時オーラ(rbm_musha_aura.gd)の時間割。表示専用の純粋な
## 「経過時間 → 状態」の写像で、戦闘の状態・乱数・行動順には触れない。乱数はゆらぎ用の
## 決定論的なハッシュだけを使う(同じ経過時間なら必ず同じ結果)。
##
## 経過時間(age)は、オーラが現れてからの秒数(rbm_musha_aura.gd が数える)。
## 印象の優先順位は「静かで重い圧」。どの出来事も低頻度で、重なって派手にならないよう
## 間隔の最小値が継続時間より長くなっている。

const RAMP_SECONDS := 3.4     # 戦場全体への影響(彩度・輝度・光・画面端)が0→1へ広がる時間

# 単眼が少し強く光る(数秒に一度)。その瞬間だけ戦場が一段沈み、四隅の墨が強まり、足元の墨が膨らむ。
const EYE_FIRST := 4.0
const EYE_PERIOD := 4.6
const EYE_JITTER := 0.9
const EYE_SPAN := 3.4

# 空間圧(2〜3秒に1回、画面全体がごくわずか縮んで沈み、戻る)。
const COMPRESS_FIRST := 1.6
const COMPRESS_PERIOD := 2.6
const COMPRESS_JITTER := 0.8
const COMPRESS_SPAN := 0.9

# ごく低頻度の斬痕(黒中心・縁にわずかな暗赤の短い直線を一瞬だけ)。
const SLASH_FIRST := 6.5
const SLASH_PERIOD := 9.0
const SLASH_JITTER := 4.0
const SLASH_SPAN := 0.34

# 画面端から太い墨筆の掠れが入って消える。
const EDGE_FIRST := 3.0
const EDGE_PERIOD := 5.4
const EDGE_JITTER := 0.8
const EDGE_SPAN := 4.6

# 石畳の溝に沿って伸びて消える細い墨筆。
const TRACE_FIRST := 1.5
const TRACE_PERIOD := 1.25
const TRACE_POOL := 13

static func hash01(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

## k番目の出来事の開始時刻。
static func event_time(first: float, period: float, jitter: float, seed_a: float, k: int) -> float:
	return first + period * k + (hash01(seed_a, float(k)) - 0.5) * jitter

## 経過時間 age に開始済みの出来事のうち、直近のもの(index=-1なら無し)と、その経過。
static func latest_event(age: float, first: float, period: float, jitter: float, seed_a: float) -> Dictionary:
	if age < first - jitter * 0.5:
		return {"index": -1, "local": -1.0}
	var k0 := int(floor((age - first) / period))
	var best := -1
	var local := -1.0
	for k in range(maxi(k0 - 1, 0), k0 + 2):
		var l := age - event_time(first, period, jitter, seed_a, k)
		if l >= 0.0 and (best < 0 or l < local):
			best = k
			local = l
	return {"index": best, "local": local}

## 影響の広がり(0〜1)。raw(0〜1の線形)をなだらかにする。
static func amount_from_raw(raw: float) -> float:
	return smoothstep(0.0, 1.0, clampf(raw, 0.0, 1.0))

## 単眼の光(立ち上がり0.08秒・減衰0.4秒)。
static func eye_env(age: float) -> float:
	var e := latest_event(age, EYE_FIRST, EYE_PERIOD, EYE_JITTER, 11.0)
	var l: float = e.local
	if int(e.index) < 0 or l > EYE_SPAN:
		return 0.0
	return smoothstep(0.0, 0.08, l) * exp(-maxf(l - 0.08, 0.0) / 0.40)

## 戦場・墨の反応(立ち上がり0.25秒・減衰0.9秒。眼より少し遅れて大きい)。
static func jolt(age: float) -> float:
	var e := latest_event(age, EYE_FIRST, EYE_PERIOD, EYE_JITTER, 11.0)
	var l: float = e.local
	if int(e.index) < 0 or l > EYE_SPAN:
		return 0.0
	return smoothstep(0.0, 0.25, l) * exp(-maxf(l - 0.25, 0.0) / 0.90)

## 空間圧の強さ(0〜1)。素早く効いて、ゆっくり戻る。
static func compress(age: float) -> float:
	var e := latest_event(age, COMPRESS_FIRST, COMPRESS_PERIOD, COMPRESS_JITTER, 23.0)
	var l: float = e.local
	if int(e.index) < 0 or l >= COMPRESS_SPAN:
		return 0.0
	return smoothstep(0.0, 0.16, l) * (1.0 - smoothstep(0.22, COMPRESS_SPAN, l))

## 斬痕: {"index": k, "local": 経過秒}(出ていなければindex=-1)。
static func slash(age: float) -> Dictionary:
	var e := latest_event(age, SLASH_FIRST, SLASH_PERIOD, SLASH_JITTER, 37.0)
	if int(e.index) >= 0 and float(e.local) > SLASH_SPAN:
		return {"index": -1, "local": -1.0}
	return e

## 斬痕の位置(ボスの足元からの相対)と向き・長さ・太さ。
static func slash_shape(index: int) -> Dictionary:
	var s := float(index) * 3.1 + 7.7
	var side := -1.0 if hash01(s, 1.0) < 0.5 else 1.0
	return {
		"offset": Vector2(side * (56.0 + hash01(s, 2.0) * 26.0), -(62.0 + hash01(s, 3.0) * 78.0)),
		"angle": (0.28 + hash01(s, 4.0) * 0.32) * (-1.0 if hash01(s, 5.0) < 0.5 else 1.0),
		"length": 62.0 + hash01(s, 6.0) * 26.0,
		"width": 2.0 + hash01(s, 7.0) * 0.9,
	}

## 画面端の墨筆: {"index": k, "u": 0〜1の進行}(出ていなければindex=-1)。
static func edge(age: float) -> Dictionary:
	var e := latest_event(age, EDGE_FIRST, EDGE_PERIOD, EDGE_JITTER, 51.0)
	var l: float = e.local
	if int(e.index) < 0 or l >= EDGE_SPAN:
		return {"index": -1, "u": -1.0}
	return {"index": int(e.index), "u": l / EDGE_SPAN}

## 画面端の墨筆の形。stage_sizeに対する比率で入口を決める(左→右→上→下の順に巡る)。
static func edge_shape(index: int, stage_size: Vector2) -> Dictionary:
	var s := float(index) * 6.1 + 500.0
	var side := index % 4
	var base := Vector2.ZERO
	var theta := 0.0
	match side:
		0:
			base = Vector2(-26.0, stage_size.y * (0.29 + hash01(s, 1.0) * 0.42))
			theta = PI / 2.0 - 0.18 + hash01(s, 2.0) * 0.3
		1:
			base = Vector2(stage_size.x + 26.0, stage_size.y * (0.28 + hash01(s, 1.0) * 0.42))
			theta = -PI / 2.0 + 0.18 - hash01(s, 2.0) * 0.3
		2:
			base = Vector2(stage_size.x * (0.16 + hash01(s, 1.0) * 0.62), -20.0)
			theta = PI - 0.15 + hash01(s, 2.0) * 0.3
		_:
			base = Vector2(stage_size.x * (0.16 + hash01(s, 1.0) * 0.62), stage_size.y + 20.0)
			theta = 0.15 - hash01(s, 2.0) * 0.3
	return {
		"base": base, "theta": theta, "bend": (hash01(s, 3.0) - 0.5) * 0.5,
		"length": 190.0 + hash01(s, 4.0) * 90.0, "width": 38.0 + hash01(s, 5.0) * 18.0, "seed": s,
	}

## 溝に沿う墨筆のうち、経過 age で出ているもの: [{"index": k, "local": 秒, "life": 秒, "path": 溝の番号}]。
static func active_traces(age: float) -> Array:
	var out: Array = []
	if age < TRACE_FIRST:
		return out
	var last := int(floor((age - TRACE_FIRST) / TRACE_PERIOD))
	for k in range(maxi(last - 6, 0), last + 1):
		var local := age - (TRACE_FIRST + TRACE_PERIOD * k)
		var life := 5.0 + hash01(float(k), 4.0) * 1.2
		if local >= 0.0 and local <= life:
			out.append({"index": k, "local": local, "life": life, "path": k % TRACE_POOL, "width": 3.4 + hash01(float(k), 5.0) * 1.6, "seed": 40.0 + k * 3.3})
	return out
