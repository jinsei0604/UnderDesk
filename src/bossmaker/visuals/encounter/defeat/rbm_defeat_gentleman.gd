extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 異形紳士が倒れる（覚醒前）「最後の一礼」: 帽子に手をかけ、敗北を認めるように深く一礼する（要所の絵: hat_reach → bow_down）
## → 一礼したまま、深紅の縁の煙になってほどけ、体から深紅の薔薇の花びらが風に吹かれて舞い上がる → 煙の中に赤い目だけが少し残り、
## 立っていた頃の高さへ上ってまばたきして消える → 遠くで鐘が鳴る。二丁拳銃・覚醒のコマは使わない。
## 2026-11-23 強化（ユーザー「全体的にエフェクトが弱くてクオリティが低い」。前の版は煙と火の粉だけ）。絵は戦闘と同じく要所の絵
## （中割りのコマを繋げない。GMotion.key_pose）。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:gent_bow", "enc:gent_vanish", "enc:gent_bell"]
## 本番の紳士のコマ（motion_frames。要所の絵だけ）。
const FRAMES := ["hat_reach_00", "hat_reach_15", "bow_down_04", "bow_down_08", "bow_down_15"]
const GMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const UNIT := 160.0 / 94.0
const SMOKE := Color(0.32, 0.32, 0.38, 0.75)
const PETAL := Color(0.76, 0.1, 0.18)
const PETAL_DARK := Color(0.42, 0.04, 0.1)
const PETAL_LIGHT := Color(1.0, 0.56, 0.6)
const EYE := Color(1.0, 0.18, 0.2)
## ほどけ始め・目が残る間・鐘
const FADE_AT := 0.95
const EYES_AT := 1.25
const BELL_AT := 1.5
## 目の位置（足元からの相対、絵の画素）: 一礼の絵の目 → 立っていた頃の目の高さ
const EYE_BOW := Vector2(-23, -52)
const EYE_STAND := Vector2(-4, -80)
var frame := "hat_reach_00"

func duration() -> float:
	return 1.8

func impact_pose() -> void:
	(p.stage.get("_visuals")["boss"] as Control).visible = false
	bs = {"pose": 11, "foot": home() + Vector2(8, 0)}
	frame = ""

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	p.at(BELL_AT, "bell", func(): p.sfx.play("enc:gent_bell", -9.0, 0.0, 2.2))
	if gone:
		return
	bs.foot = h + Vector2(8, 0)
	# 0.0〜0.5 帽子に手 / 0.5〜1.0 一礼（要所の絵）
	if t < 0.5:
		frame = GMotion.key_pose("hat_reach_%02d" % clampi(int(t / 0.5 * 16.0), 0, 15))
	elif t < 1.0:
		frame = GMotion.key_pose("bow_down_%02d" % clampi(int((t - 0.5) / 0.5 * 16.0), 0, 15))
	else:
		frame = "bow_down_15"
	p.at(0.05, "cloth", func(): p.sfx.play("enc:gent_bow", -3.0))
	if t >= FADE_AT:
		dissolve = smoothstep(FADE_AT, 1.62, t)
		edge = Color(0.9, 0.16, 0.24, 1.0)
		rise = 0.5
		block = 3.0
		p.at(FADE_AT, "smoke", func():
			p.sfx.play("enc:gent_vanish", -1.0)
			p.fx.smoke(h + Vector2(0, -60), 18, SMOKE, 30.0, 40.0)
			p.fx.embers(h + Vector2(0, -60), 12, Color(0.95, 0.25, 0.3), 30.0, 50.0, 1.2))
		p.at(1.2, "smoke2", func(): p.fx.smoke(h + Vector2(0, -30), 12, SMOKE, 40.0, 35.0))
	if t >= 1.65:
		gone = true

func draw_sprite(ci: CanvasItem, mod: Color) -> void:
	var foot: Vector2 = Vector2(bs.foot)
	if frame.is_empty():
		Sprites.draw(ci, asset, int(bs.get("pose", 11)), foot, mod)
		return
	ci.draw_set_transform(foot.round(), 0.0, Vector2(UNIT, UNIT))
	ci.draw_texture(GMotion.texture(frame), Vector2(-72, -112), mod)
	ci.draw_set_transform(Vector2.ZERO)

static func _n(i: int, k: int) -> float:
	return fposmod(sin(i * 127.1 + k * 311.7 + 17.3) * 43758.5453, 1.0)

## 花びら（体の上の方から先に、風に吹かれて右上へ舞う）と、煙の中に残る赤い目。
func draw_top(ci: CanvasItem) -> void:
	if age < FADE_AT:
		return
	var e := age - FADE_AT
	var base := home() + Vector2(8, 0)
	for i in range(110):
		var start := base + Vector2(-40.0 + 72.0 * _n(i, 1), -8.0 - 130.0 * _n(i, 2))
		var a := e - 0.45 * (1.0 - _n(i, 2))
		var life := 1.1 + 0.9 * _n(i, 3)
		if a < 0.0 or a > life:
			continue
		var v := Vector2(-60.0 + 320.0 * _n(i, 4), -90.0 - 170.0 * _n(i, 5))
		var pos := start + v * a + Vector2(sin(a * 6.0 + i) * 12.0, 60.0 * a * a)
		var f := 1.0 - smoothstep(life * 0.55, life, a)
		var flip := absf(sin(a * (7.0 + 5.0 * _n(i, 6)) + i))
		var col := PETAL.lerp(PETAL_DARK, _n(i, 7) * 0.7)
		var big := 2.0 if _n(i, 8) < 0.6 else 1.0
		ci.draw_rect(Rect2(pos.round(), (Vector2(4, 3) if flip > 0.4 else Vector2(2, 3)) * big), Color(col, f))
		if flip > 0.75:
			ci.draw_rect(Rect2((pos + Vector2(1, 0) * big).round(), Vector2(2, 1) * big), Color(PETAL_LIGHT, f * 0.9))
	# 煙の中に赤い目が残り、立っていた頃の高さへ上ってまばたきして消える
	var k := smoothstep(EYES_AT - 0.1, EYES_AT, age) * (1.0 - smoothstep(1.95, 2.15, age))
	var blink := 0.15 if age >= 1.72 and age < 1.8 else 1.0
	if k > 0.0:
		var u := smoothstep(EYES_AT, 1.75, age)
		var c := base + EYE_BOW.lerp(EYE_STAND, u) * UNIT
		for s in [-1.0, 1.0]:
			var at: Vector2 = (c + Vector2(s * 6.0, 0)).round()
			ci.draw_rect(Rect2(at - Vector2(14, 8), Vector2(28, 16)), Color(EYE, 0.06 * k * blink))
			ci.draw_rect(Rect2(at - Vector2(7, 4), Vector2(14, 8)), Color(EYE, 0.18 * k * blink))
			ci.draw_rect(Rect2(at - Vector2(22, 1), Vector2(44, 2)), Color(EYE, 0.3 * k * blink))
			ci.draw_rect(Rect2(at - Vector2(3, 2), Vector2(6, 4)), Color(1.0, 0.7, 0.65, k * blink))
