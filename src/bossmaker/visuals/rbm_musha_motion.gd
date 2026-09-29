extends RefCounted
## 朽ちた機械武者の承認済みタイムライン(単体v3・全体v3・自己強化/回復v1)。
##
## 表示専用の純粋な時刻→状態の写像。戦闘の計算・対象選択・乱数・ダメージには
## 一切触れない(確定済みの対象位置を受け取るだけ)。プロトタイプの固定座標
## (HOME/FEET/CENTER)は使わず、本番の実際の足元から相対量で求める。

const IDLE := -1

## 完成トラックの再生ゲイン(dB)。ステージ既存の音量(RBMAudioの基準 -9dB)へ他の
## 音と揃えるための補正で、録音そのものは変えていない。
## - 攻撃/覚醒の5トラック(単体・全体・覚醒後の単体/全体・覚醒): 承認済みの相対バランス
##   (覚醒後 > 通常)を保ったまま一律+3dB。通常の単体は、同種の既存トラック(竜の通常ブレス、
##   最も大きい100msのレベル -12.3dB)へ一致し、覚醒系は竜の覚醒トラック(-5.9〜-9.1dB)の
##   レンジに入る。
## - 支援の2トラック(強化/回復): 録音が既存の支援SE(heal_hp/buff_atk、最も大きい100msが
##   約-20dB)より約18dB小さかったため+18dBで揃える。
## 実測(最も大きい100msのRMS)との一致はtests/bossmaker/test_musha_audio_levels.gdが検証する。
const TRACK_GAIN_DB := {
	"musha_single": 3.0, "musha_aoe": 3.0,
	"musha_awakening": 3.0, "musha_awakened_single": 3.0, "musha_awakened_aoe": 3.0,
	"musha_buff": 18.0, "musha_heal": 18.0,
}

static func track_gain(key: String) -> float:
	return float(TRACK_GAIN_DB.get(key, 0.0))

const SINGLE_DURATION := 5.2
const ALL_DURATION := 7.0
const SUPPORT_DURATION := 4.2

## strike通知(ダメージ表示の同期)は「巨大な最終斬撃」へ合わせる(初撃は文字なしの
## 演出のみ)。initial→finalの両方でstrikeは呼ばない。
const SINGLE_FIRST_HIT := 1.34
const SINGLE_FINAL := 2.75
const ALL_FIRST := 1.52
const ALL_FINAL := 4.15
const SUPPORT_RELIGHT := 2.30

## 単体: 背後の初撃位置は対象の足元からの相対(承認済み配置: 老執事の足元(266,492)
## に対しボス背後(147,505))。
const BEHIND_OFFSET := Vector2(-119, 13)

## 体のポーズ矩形(poses.png上のRect2)と足元アンカー(原画像上)。0.445倍で描画。
const POSE_RECTS := [
	Rect2(95, 50, 345, 438), Rect2(447, 50, 590, 438), Rect2(1190, 50, 332, 438),
	Rect2(20, 502, 435, 508), Rect2(535, 547, 454, 462), Rect2(1190, 543, 322, 465),
]
const POSE_ANCHORS := [
	Vector2(270, 475), Vector2(856, 475), Vector2(1360, 475),
	Vector2(280, 988), Vector2(823, 988), Vector2(1355, 988),
]
const POSE_SCALE := 0.445
## 静止姿(IDLE): 高さ180pxへ縮小して描く。design.png全体が使用領域。
const IDLE_DISPLAY_HEIGHT := 180.0

var home := Vector2.ZERO
var behind := Vector2.ZERO

func configure(home_foot: Vector2, single_target_foot: Vector2 = Vector2.ZERO) -> void:
	home = home_foot
	behind = single_target_foot + BEHIND_OFFSET

static func duration(kind: String) -> float:
	match kind:
		"single": return SINGLE_DURATION
		"all": return ALL_DURATION
	return SUPPORT_DURATION

static func strike_time(kind: String) -> float:
	match kind:
		"single": return SINGLE_FINAL
		"all": return ALL_FINAL
	return SUPPORT_RELIGHT

## 本体の描画状態。visible=falseは「瞬間的な消失」区間。
func body_state(kind: String, t: float) -> Dictionary:
	var state := {"pose": IDLE, "foot": home, "alpha": 1.0, "flip": false, "scale_y": 1.0, "visible": true}
	match kind:
		"single":
			if t < 0.4:
				pass
			elif t < 1.22:
				state["pose"] = 0
				state["scale_y"] = 1.0 - 0.035 * smoothstep(0.4, 0.72, t)
			elif t < 1.28:
				state["visible"] = false
			elif t < 1.85:
				state["pose"] = 1
				state["foot"] = behind
				state["flip"] = true
			elif t < 1.98:
				state["pose"] = 1
				state["foot"] = behind
				state["flip"] = true
				state["alpha"] = 1.0 - smoothstep(1.85, 1.98, t)
			elif t < 2.10:
				state["pose"] = 1
				state["alpha"] = smoothstep(1.98, 2.10, t)
			elif t < 2.75:
				state["pose"] = 2
		"all":
			if t < 0.75:
				pass
			elif t < 1.10:
				state["pose"] = 0
			elif t < 1.43:
				state["pose"] = 3
			elif t < 4.80:
				state["pose"] = 4
			elif t < 5.40:
				state["pose"] = 2
		_:
			if t >= 0.5 and t < 2.65:
				state["pose"] = 5
				state["scale_y"] = 1.0 - 0.018 * sin(clampf((t - 0.5) / 2.15, 0.0, 1.0) * PI)
	return state

## 画面揺れの強さ。最終一撃はforce=42から0.75秒で0へ減衰。
func shake_force(kind: String, t: float) -> float:
	if kind == "single":
		var age := t - SINGLE_FINAL
		if age >= 0.0 and age < 0.75:
			return 42.0 * (1.0 - age / 0.75)
	elif kind == "all":
		if t >= ALL_FINAL and t < ALL_FINAL + 0.75:
			return 42.0 * (1.0 - (t - ALL_FINAL) / 0.75)
		if t >= 2.48 and t < 3.73:
			return 3.0
		if t >= ALL_FIRST and t < 1.70:
			return 5.0
	return 0.0

static func shake_offset(t: float, force: float) -> Vector2:
	return Vector2(sin(t * 109.0), cos(t * 89.0) * 0.6) * force

## 筆文字。visibleでない時はsizeは無意味。ageは筆文字自身の経過時間。
## at_hitは単体の命中中心、centerは全体の中心。
func glyph_state(kind: String, t: float) -> Dictionary:
	if kind == "single":
		return {"age": t - SINGLE_FINAL, "size": 255.0, "anchor": "hit"}
	if kind == "all":
		if t < ALL_FINAL:
			return {"age": t - ALL_FIRST, "size": 130.0, "anchor": "center"}
		return {"age": t - ALL_FINAL, "size": 255.0, "anchor": "center"}
	return {"age": -1.0, "size": 0.0, "anchor": "center"}

## 命中中の被弾表現(対象のうちindex番目)。単体は対象が1体、全体は追撃の28本の
## うち4体へ巡回して当たる。
static func target_reacting(kind: String, t: float, index: int, count: int) -> bool:
	if kind == "single":
		return (t >= SINGLE_FIRST_HIT and t < 1.58) or (t >= SINGLE_FINAL and t < 3.35)
	if kind == "all":
		if t >= ALL_FIRST and t < 1.75:
			return true
		if t >= 2.48 and t < 3.73 and count > 0 and int((t - 2.48) * 24.0) % count == index:
			return true
		return t >= ALL_FINAL and t < 4.65
	return false

## 属性→筆文字(ink.pngの並びと同じ: 無・炎・氷・雷・風)。
const GLYPH_ATTRIBUTES := ["NEUTRAL", "FIRE", "ICE", "LIGHTNING", "WIND"]
static func glyph_index(attribute: String) -> int:
	return maxi(0, GLYPH_ATTRIBUTES.find(attribute))
