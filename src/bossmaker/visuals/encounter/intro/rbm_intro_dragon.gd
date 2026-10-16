extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 竜の登場（案B・第2版）。覚醒前の緑の竜だけを使う（黒い体・赤い翼の覚醒後の外見は出さない）。
## 寄り: 夕暮れの空を、大きな翼の影が風を切って横切る（風の線・羽ばたきの音）。
## 引き: 上から羽ばたきながら舞い降りて着地（衝撃の帯・土煙・揺れ）。
## 寄り: 首をもたげて咆哮（口から広がる輪・火の粉、画面が震える）。
## 引き: 翼を広げ切って見下ろす → 味方が身構える → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:dragon_wind", "enc:dragon_wing", "enc:dragon_land", "enc:dragon_roar"]

const DragonBody = preload("res://src/bossmaker/visuals/rbm_dragon_body.gd")
const EYE := Color(1.0, 0.62, 0.2)
const DUST := Color(0.55, 0.6, 0.66, 0.9)
const EMBER := Color(1.0, 0.62, 0.22)

func prepare() -> void:
	super.prepare()
	eye_color = EYE

func duration() -> float:
	return 4.6

## 目・口の位置（本番の竜の本体と同じ目印。frames.json の範囲で写す）
func mark(pose: int, kind: String, foot: Vector2) -> Vector2:
	var m := Sprites.meta(asset)
	var rec: Dictionary = (m.poses as Array)[pose]
	var point: Vector2 = DragonBody.NORMAL_MARKS[pose][{"mouth": 0, "eye": 1, "tail": 2}[kind]]
	var src: Array = rec.source_bbox
	var b: Array = rec.bbox
	var raw := Vector2(b[0], b[1]) + (point - Vector2(src[0], src[1])) * Vector2(float(b[2]) / src[2], float(b[3]) / src[3])
	return (foot + (raw - Vector2(m.foot)) * float(m.scale)).round()

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty() or float(bs.get("alpha", 1.0)) < 0.5 or shadow > 0.5:
		return out
	out.append(mark(int(bs.pose), "eye", bs.foot))
	return out

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.25)
	bars(t, 0.30)
	# --- ショット1: 寄り。空を翼の影が横切る（0.36〜1.25） ---
	if t < 1.25:
		p.camera.cut(2, Vector2(560, 190))
		dark_bg = 0.35
		ally_tint(Color(0.5, 0.5, 0.6))
		var k := clampf((t - 0.48) / 0.62, 0.0, 1.0)
		if t >= 0.48 and t < 1.12:
			var x := lerpf(1160.0, -60.0, k)
			bs = {"pose": 9, "foot": Vector2(x, 360 + 26 * sin(k * PI)).round()}
			shadow = 0.94
		else:
			bs = {}
		p.at(0.40, "wind", func(): p.fx.speed_lines(Rect2(300, 80, 600, 260), 16, Vector2(-1, 0.05), Color(0.9, 0.95, 1.0, 0.35), 0.5))
		p.at(0.70, "wind2", func(): p.fx.speed_lines(Rect2(300, 80, 600, 260), 12, Vector2(-1, 0.05), Color(0.9, 0.95, 1.0, 0.3), 0.45))
		p.se(0.36, "enc:dragon_wind", -4.0)
		p.se(0.55, "enc:dragon_wing", -1.0)
		p.at(0.78, "pass_shake", func(): p.camera.shake(2, 0.25))
		return
	shadow = 0.0
	# --- ショット2: 引き。舞い降りて着地（1.25〜2.10） ---
	if t < 2.10:
		p.at(1.25, "cut2", func(): p.camera.cut(1, Vector2(640, 360)))
		var lift := smoothstep(1.25, 1.45, t)
		dark_bg = 0.35 * (1.0 - lift)
		ally_tint(Color(0.5, 0.5, 0.6).lerp(Color.WHITE, lift))
		var d := clampf((t - 1.25) / 0.5, 0.0, 1.0)
		if t < 1.75:
			# 羽ばたき: 翼を広げた姿勢と、少し縮めた姿勢を交互に（落ちる速さは着地へ向けて速くなる）
			var flap := int((t - 1.25) / 0.12) % 2 == 0
			bs = {"pose": 9 if flap else 4, "foot": (home + Vector2(70, -440)).lerp(home, ease_in(d) * 0.85 + d * 0.15).round()}
			p.at(1.37, "flap1", func(): p.sfx.play("enc:dragon_wing", -3.0))
			p.at(1.61, "flap2", func(): p.sfx.play("enc:dragon_wing", -2.0))
		elif t < 1.95:
			bs = {"pose": 10, "foot": home + Vector2(0, land_dip(t - 1.75, 6.0))}
		else:
			bs = {"pose": 0, "foot": home}
		p.at(1.75, "land", func():
			p.camera.shake(6, 0.45)
			p.sfx.play("enc:dragon_land", 0.0)
			p.fx_back.shock(home + Vector2(-10, 0), 30, 300, 0.55, Color(0.9, 0.95, 1.0, 0.8), 10.0, 0.22)
			p.fx.puff(home + Vector2(-90, 0), 16, 70, DUST, 1.7)
			p.fx.puff(home + Vector2(80, 0), 14, 60, DUST, 1.5)
			p.fx.rocks(home + Vector2(-20, -2), 10, Color(0.42, 0.46, 0.5), 0.8, 0.8, home.y + 6))
		p.at(1.80, "brace", func(): allies_brace(true, 4.0))
		eye = 0.0
		return
	# --- ショット3: 寄り。咆哮（2.10〜2.85） ---
	if t < 2.85:
		var mouth := mark(8, "mouth", home)
		p.at(2.10, "cut3", func(): p.camera.cut(2, mouth + Vector2(70, 46)))
		bs = {"pose": 1 if t < 2.2 else 8, "foot": home}
		eye = 1.0
		p.at(2.20, "roar", func():
			# 声を低くした分、体感の音量が約1.3dB下がるので、鳴らす音量を上げて迫力を保つ
			p.sfx.play("enc:dragon_roar", 2.0)
			p.camera.shake(4, 0.6)
			p.fx.shock(mouth, 8, 140, 0.5, Color(1.0, 0.92, 0.8, 0.85), 6.0, 1.0)
			p.fx.embers(mouth + Vector2(-8, 6), 16, EMBER, 12.0, 90.0, 1.0))
		p.at(2.42, "roar2", func(): p.fx.shock(mouth, 8, 170, 0.55, Color(1.0, 0.8, 0.55, 0.6), 4.0, 1.0))
		p.at(2.62, "roar3", func(): p.fx.shock(mouth, 8, 200, 0.6, Color(1.0, 0.7, 0.4, 0.45), 3.0, 1.0))
		return
	# --- ショット4: 引き。翼を広げ切る → 題字（2.85〜） ---
	p.at(2.85, "cut4", func():
		p.camera.cut(1, Vector2(640, 360))
		p.sfx.play("enc:dragon_wing", -4.0))
	bs = {"pose": 9 if t < 3.75 else 0, "foot": home}
	eye = 1.0 - 0.6 * smoothstep(3.0, 3.6, t)
	p.at(3.75, "relax", func(): allies_brace(false))
	title_card(t, 2.95, Color(0.55, 0.95, 0.5))
