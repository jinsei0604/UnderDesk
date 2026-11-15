extends RBMFlowerFxBase
## 本番（2026-11-16 ユーザー「どちらも実装して大丈夫」）: 試作 prototypes/four_bosses_2026-11-11/scripts/flower/intro.gd でユーザーが採用した内容をそのまま移した。
## 白磁のカラー・登場（2026-11-14 ユーザー案）: 画面全体に花びらが舞い始め、最初は少しだけ → だんだん多くなる
## → やがて全画面を花びらが覆い隠す（shaders/petal_veil.gdshader の3層の花びら。平らな白い幕にしない）
## → 一陣の風で花びらが吹き抜けて晴れると、光の中でお辞儀をしている白磁のカラーがいる → 顔を上げて構えへ。
## 本体は覚醒の2枚目（お辞儀・うなだれ）を借りる。

const T := {"start": 0.0, "cover": 2.3, "hold": 2.75, "clear": 3.05, "clear_end": 3.75, "rise": 4.5, "end": 5.3}
const WHITE := Color("#fbf8ee")
const IVORY := Color("#e8e2d0")
const LINE := Color("#4c5c4a")
const GLOW := Color("#f2f6c8")
const BOW := 9

var b_back: RBMHeroFxBatch
var b_glow: RBMHeroFxBatch
var b_front: RBMHeroFxBatch
var veil: ColorRect

func duration() -> float:
	return T.end

func impact() -> float:
	return T.clear

func extra_poses() -> Dictionary:
	return {BOW: ["awaken", 2]}

func pose_keys() -> Array:
	return [[0.0, BOW], [T.rise, 0]]

func _build() -> void:
	b_back = batch(back, false)
	b_glow = batch(back)
	b_front = batch(front, false)
	veil = pquad(front, Rect2(-40, -40, 720, 440), "petal_veil", {"size": Vector2(720, 440)})

func _step(t: float) -> void:
	b_back.reset(); b_glow.reset(); b_front.reset()
	# 花びらの数: 最初は少し → だんだん多く → 覆い隠す → 一陣の風で晴れる
	var k := RBMHeroFx.ramp(t, 0.0, T.cover)
	var clear := RBMHeroFx.ramp(t, T.clear, T.clear_end)
	var gust := RBMHeroFx.ramp(t, float(T.clear) - 0.1, T.clear_end)
	var travel := 130.0 * t + 40.0 * t * t + 620.0 * gust * gust
	# 最初はまばら → 後半で一気に増える（ユーザー「最初は少しだけど、だんだん多くなって」）
	var cover := pow(k, 1.8) * (1.0 - clear)
	veil.visible = cover > 0.0 or t < T.clear
	sp(veil, {"cover": cover, "travel": travel, "time": t, "fade": 1.0})
	view["dim"] = 0.25 * (1.0 - clear)
	view["dim_col"] = Color(0.04, 0.05, 0.04)
	# 本体: 花びらが覆っている間に現れている（お辞儀）。晴れると光の中にいる
	body["hidden"] = t < T.hold
	var shine := RBMHeroFx.env(t, T.clear, T.clear_end, T.rise, T.end)
	light_shaft(b_glow, HOME + Vector2(0, 4), 190.0, 18.0, 46.0, WHITE, 0.22 * shine)
	if shine > 0.0:
		view["hero"]["lit"] = 0.4 * shine
		view["hero"]["lit_col"] = WHITE
	# 晴れた後、足元に花びらがゆっくり舞い落ちる
	petal_cloud(b_front, HOME + Vector2(0, -60), t, 9, 21, 70.0, 4.4, WHITE, IVORY, RBMHeroFx.env(t, T.clear_end - 0.2, T.clear_end + 0.3, T.end - 0.5, T.end), "fall", 0.45, Color(LINE, 0.8))
	b_back.commit(); b_glow.commit(); b_front.commit()
