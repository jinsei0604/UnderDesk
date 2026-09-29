extends RefCounted
## 朽ちた機械武者の覚醒(封剣機構・解放)と覚醒後の単体/全体攻撃の承認済み
## タイムライン(v4)。表示専用の純粋な時刻→状態の写像で、戦闘の計算・対象選択・
## 乱数・ダメージには一切触れない。試作の固定座標は使わず、本番の実際の足元から
## 相対量で求める。

const AWAKENING_DURATION := 6.9
const SINGLE_DURATION := 4.5
const ALL_DURATION := 7.0

## 着弾(=ダメージ表示の通知)。覚醒自体は着弾を持たない(stage側が終了時にimpactを出す)。
const SINGLE_IMPACT := 2.15
const ALL_IMPACT := 4.85
## 覚醒の風圧解放(斬撃痕+全画面の風)。
const AWAKENING_RELEASE := 4.80
## 持続オーラの出現区間(覚醒演出中のみ。以後は覚醒状態に追従して常時)。
const AURA_FADE_IN_START := 5.15
const AURA_FADE_IN_END := 5.65
## 覚醒後の外見へ切り替える時刻(本体が抜刀待機になる時)。
const APPEARANCE_SWITCH := 5.3

const SWEEP_DURATION := 0.10

## 覚醒アトラス(awakened.png)の矩形と足元(原画像上)。倍率0.335。
const ATLAS_RECTS := [
	Rect2(177, 17, 328, 581), Rect2(777, 24, 365, 578),
	Rect2(110, 639, 513, 579), Rect2(672, 640, 456, 579),
]
const ATLAS_FEET := [Vector2(351, 596), Vector2(959, 600), Vector2(370, 1215), Vector2(971, 1215)]
const ATLAS_EYES := [Vector2(294, 126), Vector2(897, 129), Vector2(324, 741), Vector2(925, 742)]
const ATLAS_SCALE := 0.335
## 振り下ろし4コマ(swing.png)。倍率0.415、足元アンカーは動かさない。
const SWING_RECTS := [
	Rect2(40, 20, 390, 710), Rect2(451, 140, 502, 589),
	Rect2(956, 240, 586, 490), Rect2(1560, 266, 505, 468),
]
const SWING_FEET := [Vector2(232, 708), Vector2(786, 708), Vector2(1380, 708), Vector2(1890, 708)]
const SWING_SCALE := 0.415

## 解錠の小さなロックバー(肩左右→腕左右→脚左右)。
const LOCK_START := 1.8
const LOCK_INTERVAL := 0.2
const LOCK_OFFSETS := [Vector2(-23, -127), Vector2(22, -124), Vector2(-29, -85), Vector2(29, -79), Vector2(-14, -33), Vector2(18, -28)]

static func duration(kind: String) -> float:
	match kind:
		"awakening": return AWAKENING_DURATION
		"single": return SINGLE_DURATION
	return ALL_DURATION

static func impact_time(kind: String) -> float:
	return SINGLE_IMPACT if kind == "single" else ALL_IMPACT

static func sweep_start(kind: String) -> float:
	return 0.92 if kind == "single" else 1.38

## 画面揺れの強さ(覚醒最大55/単体38/全体68。着弾から1.25秒で減衰)。
static func shake_force(kind: String, t: float) -> float:
	var peak := 55.0 if kind == "awakening" else (38.0 if kind == "single" else 68.0)
	var at := AWAKENING_RELEASE if kind == "awakening" else impact_time(kind)
	var dt := t - at
	return peak * maxf(0.0, 1.0 - dt / 1.25) if dt >= 0.0 else 0.0

static func shake_offset(t: float, force: float) -> Vector2:
	return Vector2(sin(t * 111.0), cos(t * 93.0) * 0.55) * force

## 本体の描画状態。source: "awakened"(atlas index) / "swing"(4コマ)。
## eye: 赤い眼を描くか。bands: 外套の横帯変形の強さ(0なら通常描画)。
static func body_state(kind: String, t: float) -> Dictionary:
	if kind == "awakening":
		var index := 3
		var eye := true
		if t < 3.3:
			index = 0
			eye = t < 0.8
		elif t < 3.8:
			index = 0
		elif t < 4.35:
			index = 1
		elif t < 5.3:
			index = 2
		var bands := 0.0
		if t >= 2.8 and t < 5.3:
			bands = sin(clampf((t - 2.8) / 2.5, 0.0, 1.0) * PI)
		return {"source": "awakened", "index": index, "eye": eye, "bands": bands}
	var start := 0.60 if kind == "single" else 0.75
	var sweep := sweep_start(kind)
	if t < start or (t > 3.55 and kind == "single") or t > 6.15:
		return {"source": "awakened", "index": 3, "eye": true, "bands": 0.0}
	var frame := 3
	if t < sweep:
		frame = 0
	elif t < sweep + SWEEP_DURATION * 0.34:
		frame = 1
	elif t < sweep + SWEEP_DURATION * 0.67:
		frame = 2
	return {"source": "swing", "index": frame, "eye": true, "bands": 0.0}

## 持続オーラの強さ(覚醒演出中のみ出現区間を持つ)。
static func aura_power(t: float) -> float:
	return smoothstep(AURA_FADE_IN_START, AURA_FADE_IN_END, t)

## 着弾直後の被弾表現(.24秒)。単体は対象1体、全体は全員。
static func target_reacting(kind: String, t: float) -> bool:
	var at := impact_time(kind)
	return t >= at and t < at + 0.24

## ロックバー(i番目)の経過。範囲外はnegative。
static func lock_age(index: int, t: float) -> float:
	var u := t - (LOCK_START + index * LOCK_INTERVAL)
	return u if u >= 0.0 and u < 0.6 else -1.0

## 毛筆(2文字合成)。属性文字+「境」(単体)/「界」(全体)。着弾と同時に出て1.5秒で消える。
static func brush_age(kind: String, t: float) -> float:
	var dt := t - impact_time(kind)
	return dt if dt >= 0.0 and dt < 1.5 else -1.0
