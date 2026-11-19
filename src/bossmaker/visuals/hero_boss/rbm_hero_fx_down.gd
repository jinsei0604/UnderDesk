extends RBMHeroFxBase
## ヒーローの覚醒前の撃破「力尽きる」（2026-11-17。表示専用。戦闘の状態・乱数には触れない）。時刻は RBMHeroFxTiming.DOWN。
## 意味: 力が尽きていく → 倒れる → 光になって消える（2026-11-19 ユーザーの指摘で、最後に照射器で照らす所を外した）。
## よろめく・鎧の継ぎ目から火花（短い放電）→ 胸の灯が赤く点滅し、だんだん速くなる（小さな光。画面の20%よりずっと小さい）
## → 片膝をつく（土ぼこり・小さな揺れ）→ 胸の灯が一度強く光って消える → 青い光の粒になって昇る（本体の消え方は共通の四角い粒）→ 粒が消えて終わる。
## 本体の絵は持たない（つなぎ rbm_hero_boss_defeat.gd が描く）。本体への指示は view["hero"]（flash・desat）。カメラは寄らない（揺れだけ）。

const T := RBMHeroFxTiming.DOWN
const BLUE := Color("#5cc6fa")
const PALE := Color("#c8f4ff")
## 胸の灯（力が尽きる知らせの赤）
const RED := Color("#ff3d3d")
const RED_HOT := Color("#ffb0a0")
## 火花が出る鎧の継ぎ目（足元中央からの相対。立ち姿 release0 の肩・胸・腰・膝・腕）
const SPARK_AT := [Vector2(-16, -70), Vector2(14, -55), Vector2(-6, -32), Vector2(18, -74), Vector2(-12, -48)]
const SPARK_DIR := [-2.4, -0.6, -1.9, -0.9, -2.7]

var b_front: RBMHeroFxBatch
var b_add: RBMHeroFxBatch

func _build() -> void:
	b_front = batch(front, false)
	b_add = batch(front)

## 胸の灯の点滅の位相（回数）。速さは blink_f0 → blink_f1 回/秒へ一様に上がる。音（tools/hero_boss/audio/build.mjs）も同じ式で鳴らす。
static func blink_phase(t: float) -> float:
	var b := float(T.blink)
	var o := float(T.out)
	if t <= b:
		return 0.0
	var tt := minf(t, o) - b
	var f0 := float(T.blink_f0)
	var f1 := float(T.blink_f1)
	return f0 * tt + (f1 - f0) * tt * tt / (2.0 * (o - b))

static func blink_on(t: float) -> bool:
	return t >= float(T.blink) and t < float(T.out) and fmod(blink_phase(t), 1.0) < 0.5

func _step(t: float) -> void:
	b_front.reset(); b_add.reset()
	# 暗くなる（力が尽きるほど）→ 消えた後は少し戻る
	view["dim"] = RBMHeroFx.key(t, [[0.0, 0.12], [float(T.kneel), 0.3], [float(T.out), 0.42], [float(T.gone), 0.36], [float(T.end), 0.2]])
	view["dim_col"] = Color(0.02, 0.03, 0.08)
	view["hero"]["flash"] = 0.0
	# 鎧の継ぎ目から火花（短い放電）
	for i in range(T.sparks.size()):
		var a := t - float(T.sparks[i])
		if a < 0.0 or a > 0.45 or t > float(T.melt):
			continue
		var at := body_foot + Vector2(SPARK_AT[i])
		if t >= float(T.kneel):
			at = anchor("chest") + Vector2(SPARK_AT[i]) * 0.4
		sparks(b_add, at, a, 0.38, 22, 61 + i * 7, 190.0, Color.WHITE, BLUE, float(SPARK_DIR[i]), PI * 0.9, 300.0, 1.4)
		if a < 0.1:
			for j in range(2):
				var ang := float(SPARK_DIR[i]) + (float(j) - 0.5) * 1.3
				arc(b_add, at, at + Vector2.from_angle(ang) * (8.0 + 4.0 * j), 70 + i * 5 + j + int(a * 60.0), 0.8, Color(BLUE, 0.8), Color.WHITE, 4, 0.4, false)
		RBMHeroRooftop.glow(b_add, at, 8.0 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.14)), Color(PALE, 0.8))
		view["hero"]["flash"] = maxf(float(view["hero"]["flash"]), 0.3 * (1.0 - RBMHeroFx.ramp(a, 0.0, 0.07)))
		view["shake"] += hit_shake(a, 4.0, 90.0, 0.12)
	# 胸の灯: 赤く点滅し、だんだん速くなる。消えている間も小さく赤く残る
	var chest := anchor("chest")
	if t >= float(T.blink) and t < float(T.out):
		if blink_on(t):
			RBMHeroRooftop.glow(b_add, chest, 10.0, Color(RED, 0.9))
			RBMHeroRooftop.glow(b_add, chest, 3.4, Color(RED_HOT, 1.0))
		else:
			RBMHeroRooftop.glow(b_add, chest, 4.0, Color(RED, 0.4))
	# 胸の灯が消える: 一度強く光って消える
	var oa := t - float(T.out)
	if oa >= 0.0 and oa < 0.4:
		var k := 1.0 - RBMHeroFx.ramp(oa, 0.0, 0.4)
		RBMHeroRooftop.glow(b_add, chest, 18.0 * k, Color(RED, 0.7 * k))
		RBMHeroRooftop.glow(b_add, chest, 7.0 * k, Color(1, 1, 1, 0.9 * k))
		view["hero"]["flash"] = maxf(float(view["hero"]["flash"]), 0.5 * (1.0 - RBMHeroFx.ramp(oa, 0.0, 0.16)))
		view["shake"] += hit_shake(oa, 8.0, 70.0, 0.25)
	# 力が抜けて色が褪せる
	view["hero"]["desat"] = 0.55 * RBMHeroFx.ramp(t, float(T.out), float(T.out) + 0.2)
	# 片膝をつく: 土ぼこり・小さな揺れ
	var ka := t - float(T.kneel)
	if ka >= 0.0:
		rocks(b_front, body_foot + Vector2(-18, -2), ka, 0.6, 7, 33, 120.0, 2.2, 0.0)
		rocks(b_front, body_foot + Vector2(14, -2), ka, 0.6, 5, 37, 100.0, 2.0, 0.0)
		view["shake"] += hit_shake(ka, 12.0, 70.0, 0.3)
	# 青い光の粒になって昇る
	var ma := t - float(T.melt)
	if ma >= 0.0:
		var power := RBMHeroFx.ramp(ma, 0.0, 0.3) * (1.0 - RBMHeroFx.ramp(t, float(T.gone) + 0.1, float(T.end)))
		embers(b_add, Rect2(body_foot.x - 26, body_foot.y - 66, 52, 60), t, 30, 81, 70.0, Color(PALE, 1.0), power, 2.0, 6.0)
		embers(b_add, Rect2(body_foot.x - 18, body_foot.y - 50, 36, 44), t, 14, 83, 90.0, Color(BLUE, 1.0), power, 2.4, 4.0)
	b_front.commit(); b_add.commit()
