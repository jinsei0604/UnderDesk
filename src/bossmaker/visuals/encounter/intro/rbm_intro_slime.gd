extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## スライムの登場（案B・第2版）。赤い粘体。かわいさより「ねばっこい不気味さ」と弾む重さ。
## 寄り: 上から赤いしずくが一滴ずつ落ち、床の水たまりが広がっていく（ぽたっ、という音）。
## 引き: 水たまりから体が盛り上がって起き上がり、高く伸び上がって溜める → どすんと落ちて、しずくが味方の方へはねる
## → 怒った目でにらむ → 題字。動きはポーズの切り替えと、地面より下を描かない（湧き上がる）だけ。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:slime_drip", "enc:slime_bubble", "enc:slime_stretch", "enc:slime_splat", "enc:slime_glare"]

const RED := Color(0.86, 0.26, 0.24)
const RED_DARK := Color(0.55, 0.12, 0.14)

var puddle := 0.0

func prepare() -> void:
	super.prepare()
	eye_color = Color(1.0, 0.5, 0.45)

func duration() -> float:
	return 4.45

func extra_back(ci: CanvasItem) -> void:
	if puddle <= 0.0:
		return
	# 床の赤い水たまり（2pxの段の楕円）
	var f: Vector2 = p.boss_foot()
	var w := roundf(90.0 * puddle / 2.0) * 2.0
	ci.draw_set_transform(f.round(), 0.0, Vector2(1.0, 0.24))
	ci.draw_circle(Vector2.ZERO, w, Color(RED_DARK, 0.85), true, -1.0, false)
	ci.draw_circle(Vector2(-w * 0.2, -w * 0.15), w * 0.6, Color(RED, 0.75), true, -1.0, false)
	ci.draw_circle(Vector2(-w * 0.35, -w * 0.3), w * 0.18, Color(1.0, 0.7, 0.65, 0.7), true, -1.0, false)
	ci.draw_set_transform(Vector2.ZERO)

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.25)
	bars(t, 0.30)
	# --- ショット1: 寄り。しずくが落ちて水たまりが広がる（0.36〜1.40） ---
	if t < 1.40:
		p.camera.cut(2, home + Vector2(-30, -70))
		dark_bg = 0.5
		ally_tint(Color(0.35, 0.35, 0.45))
		bs = {}
		for i in range(4):
			var drop_t := 0.45 + i * 0.22
			p.at(drop_t, "drop%d" % i, func():
				p.fx.drops(home + Vector2(-10 + i * 6, -230), 1, RED, 0.02, home.y - 1, 0.0)
				p.fx.parts[-1].v = Vector2(0, 260)
				p.fx.parts[-1].r = 4.5)
			p.at(drop_t + 0.18, "plop%d" % i, func():
				p.sfx.play("enc:slime_drip", -4.0 + i, 0.0, -1.0, 1.0 + i * 0.06)
				p.fx.drops(home + Vector2(-10 + i * 6, -2), 4, RED, 0.35, home.y + 2))
		puddle = smoothstep(0.6, 1.35, t)
		return
	# --- ショット2: 引き（1.40〜） ---
	p.at(1.40, "cut2", func(): p.camera.cut(1, Vector2(640, 360)))
	var lift := smoothstep(1.40, 1.6, t)
	dark_bg = 0.5 * (1.0 - lift)
	ally_tint(Color(0.35, 0.35, 0.45).lerp(Color.WHITE, lift))
	puddle = 1.0 - smoothstep(1.75, 2.05, t)
	# 湧き上がる: 地面より下を描かないまま、足元を下から上げる
	if t < 1.95:
		var rise_k := ease_out((t - 1.42) / 0.5)
		bs = {"pose": 6, "foot": home + Vector2(0, roundf(150.0 * (1.0 - rise_k) / 2.0) * 2.0), "ground": home.y + 2}
		p.se(1.42, "enc:slime_bubble", -2.0)
		p.at(1.6, "bubbles", func(): p.fx.drops(home + Vector2(0, -10), 8, RED, 0.5, home.y + 2))
	elif t < 2.35:
		# 伸び上がって溜める（9 = 高く伸びる）
		bs = {"pose": 9 if t >= 2.05 else 0, "foot": home}
		p.se(2.05, "enc:slime_stretch", -3.0)
	else:
		bs = {"pose": 0, "foot": home}
	# どすんと落ちる（10 = つぶれる）
	var slam := 2.35
	if t >= slam and t < slam + 0.22:
		bs = {"pose": 10, "foot": home}
	p.at(slam, "slam", func():
		p.sfx.play("enc:slime_splat", 0.0)
		p.camera.shake(4, 0.35)
		# しずくは体の左右の縁から、味方の方へ大きく飛ぶ
		p.fx.drops(home + Vector2(-80, -20), 18, RED, 1.5, home.y + 40)
		p.fx.drops(home + Vector2(70, -20), 10, RED, 1.1, home.y + 30)
		p.fx_back.shock(home, 30, 260, 0.55, Color(1.0, 0.55, 0.5, 0.75), 10.0, 0.22))
	p.at(slam + 0.05, "brace", func(): allies_brace(true, 4.0))
	p.at(slam + 0.25, "glare", func(): p.sfx.play("enc:slime_glare", -4.0))
	# つぶれから戻る時に一度だけ小さく弾む（4 = 少し伸びる）
	if t >= slam + 0.22 and t < slam + 0.36:
		bs = {"pose": 4, "foot": home}
	p.at(3.5, "relax", func(): allies_brace(false))
	title_card(t, 2.75, Color(1.0, 0.5, 0.45))
