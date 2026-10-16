extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## ゴーストの登場（案B・第2版）。橙色の布をかぶった亡霊。ちらつき・ささやき・浮遊。
## 寄り: 床を這う霧の中、何もない暗がりに二つの目だけが灯る（ささやき声）。
## 引き: 体が古い映像のようにちらつきながら現れ、ふわりと浮き上がる → 両腕を広げて叫ぶ（ゆがみの輪）
## → 味方が身構える → ゆらゆら漂う → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:ghost_whisper", "enc:ghost_eyes", "enc:ghost_flicker", "enc:ghost_shriek"]

const SPIRIT := Color(1.0, 0.72, 0.38, 0.55)
const FOG := Color(0.65, 0.68, 0.8, 0.35)
## 目の位置（ポーズ画像 512×512 の上の画素）
const EYES := {0: [Vector2(199, 124), Vector2(229, 124)], 5: [Vector2(239, 154), Vector2(269, 154)], 11: [Vector2(229, 186), Vector2(259, 186)], 9: [Vector2(236, 150), Vector2(262, 150)]}

var fog := 1.0

func extra_back(ci: CanvasItem) -> void:
	draw_fog(ci, fog, Color(0.55, 0.6, 0.75))

func extra_top(ci: CanvasItem) -> void:
	draw_fog(ci, fog * 0.8, Color(0.55, 0.6, 0.75), true)

func prepare() -> void:
	super.prepare()
	eye_color = Color(1.0, 0.82, 0.5)

func duration() -> float:
	return 4.5

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty():
		return out
	for e in EYES.get(int(bs.pose), EYES[0]):
		out.append(px(e, Vector2(bs.foot)))
	return out

func float_y(t: float) -> float:
	return roundf(6.0 * sin(t * 3.2) / 2.0) * 2.0

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り。暗がりに目だけ（0.36〜1.30） ---
	if t < 1.30:
		p.camera.cut(2, home + Vector2(-20, -120))
		dark_bg = 0.9
		ally_tint(Color(0.12, 0.12, 0.18))
		bs = {"pose": 0, "foot": home + Vector2(0, -10), "alpha": 0.0}
		eye = 0.0
		if t >= 0.70:
			eye = 1.0 if (t < 0.74 or t >= 0.80) else 0.0
			eye *= 0.6 if t < 0.74 else 1.0
		p.se(0.36, "enc:ghost_whisper", -3.0)
		p.se(0.70, "enc:ghost_eyes", -4.0)
		return
	# --- ショット2: 引き（1.30〜） ---
	p.at(1.30, "cut2", func(): p.camera.cut(1, Vector2(640, 360)))
	var lift := smoothstep(1.30, 1.6, t)
	fog = 1.0 - 0.5 * lift
	dark_bg = 0.9 * (1.0 - lift) + 0.25 * lift
	ally_tint(Color(0.12, 0.12, 0.18).lerp(Color(0.85, 0.85, 0.92), lift))
	# ちらつきながら現れる（一瞬ずつ見える → 薄く → はっきり）
	var alpha := 0.0
	var steps := [[1.36, 0.0], [1.40, 0.55], [1.44, 0.0], [1.52, 0.3], [1.58, 0.0], [1.62, 0.8], [1.66, 0.35], [1.74, 1.0]]
	for s in steps:
		if t >= float(s[0]):
			alpha = float(s[1])
	var rise := roundf(20.0 * ease_out((t - 1.36) / 0.8) / 2.0) * 2.0
	bs = {"pose": 0, "foot": home + Vector2(0, -rise + float_y(t)), "alpha": alpha}
	eye = 1.0
	p.se(1.36, "enc:ghost_flicker", -3.0)
	# 両腕を広げて叫ぶ（5）
	if t >= 2.15 and t < 2.95:
		bs.pose = 5 if t >= 2.22 else 11
	p.at(2.22, "shriek", func():
		p.sfx.play("enc:ghost_shriek", 0.0)
		p.camera.shake(3, 0.4)
		var c := px(Vector2(254, 200), Vector2(bs.foot))
		p.fx.shock(c, 12, 200, 0.6, Color(1.0, 0.8, 0.55, 0.65), 8.0, 1.0)
		p.fx.shock(c, 12, 140, 0.5, Color(1.0, 0.9, 0.7, 0.5), 4.0, 1.0)
		p.fx.wisps(c, 14, SPIRIT, 60.0, 50.0, 1.3))
	p.at(2.25, "brace", func(): allies_brace(true, 6.0))
	p.at(3.5, "relax", func(): allies_brace(false))
	title_card(t, 2.75, Color(1.0, 0.72, 0.38))
