extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 狼の登場（案B・第2版）。速さ・野生・青い毛並み・黄色の目。
## 寄り: 暗がりの中、低く構えた狼の目だけが黄色く光り、白い息が漏れる（低いうなり）。
## 引き: 画面の右から一気に駆け込み（速さの線・足音）、前足で地面を削って滑り止まる（土煙）
## → 頭を上げて遠吠え（声の輪）→ 牙をむいて身を低くし、味方が身構える → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:wolf_growl", "enc:wolf_eye", "enc:wolf_run", "enc:wolf_skid", "enc:wolf_howl", "enc:wolf_snarl"]

const EYE := Color(1.0, 0.82, 0.25)
const DUST := Color(0.6, 0.6, 0.62, 0.85)
## 目の位置（ポーズ画像 512×512 の上の画素）
const EYES := {0: Vector2(166, 236), 5: Vector2(184, 194), 1: Vector2(150, 316), 10: Vector2(150, 306), 9: Vector2(196, 236), 4: Vector2(150, 308)}

func prepare() -> void:
	super.prepare()
	eye_color = EYE

func duration() -> float:
	return 4.5

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty() or not EYES.has(int(bs.pose)):
		return out
	out.append(px(EYES[int(bs.pose)], Vector2(bs.foot)))
	return out

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り。暗がりで光る目と白い息（0.36〜1.30） ---
	if t < 1.30:
		p.camera.cut(2, home + Vector2(-60, -60))
		dark_bg = 0.86
		ally_tint(Color(0.15, 0.15, 0.22))
		bs = {"pose": 4, "foot": home, "mod": Color(0.14, 0.16, 0.28), "rim": Color(0.55, 0.7, 1.0, 0.7), "rim_off": Vector2(2, -2)}
		eye = 0.0
		if t >= 0.72:
			eye = 0.5 if t < 0.78 else 1.0
		for k in [0.85, 1.15]:
			p.at(k, "breath%s" % k, func(): p.fx.wisps(px(Vector2(110, 330), home), 5, Color(0.85, 0.9, 1.0, 0.5), 6.0, 20.0, 0.8))
		p.se(0.40, "enc:wolf_growl", -4.0)
		p.se(0.72, "enc:wolf_eye", -4.0)
		return
	# --- ショット2: 引き。駆け込んで滑り止まる（1.30〜） ---
	p.at(1.30, "cut2", func():
		p.camera.cut(1, Vector2(640, 360))
		p.fx.speed_lines(Rect2(700, 300, 600, 180), 18, Vector2(-1, 0), Color(0.85, 0.92, 1.0, 0.5), 0.35))
	var lift := smoothstep(1.30, 1.45, t)
	dark_bg = 0.86 * (1.0 - lift)
	ally_tint(Color(0.15, 0.15, 0.22).lerp(Color.WHITE, lift))
	eye = 0.0
	if t < 1.62:
		# 駆ける: 2（跳ぶ）と3（伸びる）を交互に、右の画面外から（2px単位）
		var k := ease_in_out((t - 1.30) / 0.32)
		var run := int((t - 1.30) / 0.06) % 2 == 0
		bs = {"pose": 2 if run else 3, "foot": (home + Vector2(620, 0)).lerp(home + Vector2(40, 0), k).snapped(Vector2(2, 2)) + Vector2(0, -2 if run else 0)}
		p.se(1.30, "enc:wolf_run", -2.0)
	elif t < 1.92:
		# 滑り止まる: 前足で削る低い姿勢（10）で、少し流れて止まる
		var k := ease_out((t - 1.62) / 0.3)
		bs = {"pose": 10, "foot": (home + Vector2(40, 0)).lerp(home, k).snapped(Vector2(2, 2))}
		p.at(1.62, "skid", func():
			p.sfx.play("enc:wolf_skid", -1.0)
			p.camera.shake(3, 0.25)
			p.fx.puff(home + Vector2(-30, 0), 16, 50, DUST, 1.3, 0.5)
			p.fx.puff(home + Vector2(40, 0), 8, 40, DUST, 0.8, 0.5))
	elif t < 2.75:
		# 遠吠え（5 = 頭を上げる）
		bs = {"pose": 5, "foot": home}
		p.at(1.98, "howl", func():
			p.sfx.play("enc:wolf_howl", 0.0)
			var mouth := px(Vector2(172, 170), home)
			p.fx.shock(mouth, 6, 120, 0.7, Color(0.8, 0.9, 1.0, 0.55), 4.0, 1.0))
		p.at(2.25, "howl2", func(): p.fx.shock(px(Vector2(172, 170), home), 6, 160, 0.8, Color(0.8, 0.9, 1.0, 0.4), 3.0, 1.0))
	else:
		# 牙をむいて身を低くする（9 = 吠えかかる）→ 構え（0）
		bs = {"pose": 9 if t < 3.5 else 0, "foot": home}
		eye = 1.0 - 0.5 * smoothstep(3.2, 3.7, t)
		p.at(2.75, "snarl", func():
			p.sfx.play("enc:wolf_snarl", -1.0)
			p.camera.shake(2, 0.2))
		p.at(2.78, "brace", func(): allies_brace(true, 4.0))
	p.at(3.6, "relax", func(): allies_brace(false))
	title_card(t, 2.85, Color(0.55, 0.78, 1.0))
