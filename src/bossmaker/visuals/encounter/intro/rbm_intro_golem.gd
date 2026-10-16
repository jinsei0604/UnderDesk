extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## ゴーレムの登場（案B・第2版）。重さ・石・紫の岩・黄色の目。
## 寄り: 暗がりにうずくまる石の塊。上から月の光の筋とちり、小石が落ち、目が二度瞬いて灯る（低いうなり）。
## 引き: 重く起き上がる（沈み込み）→ 両拳を高く振り上げて溜める → 叩きつける（地割れ・衝撃の帯・岩の破片・土煙、味方がたじろぐ）→ 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:golem_pebbles", "enc:golem_rumble", "enc:golem_eyes", "enc:golem_rise", "enc:golem_windup", "enc:golem_slam"]

const ROCK := Color(0.40, 0.34, 0.50)
const DUST := Color(0.50, 0.47, 0.55, 0.9)
const EYE := Color(1.0, 0.84, 0.30)
## 目の位置（ポーズ画像 512×512 の上の画素。原画を拡大して測った値）
const EYES := {0: [Vector2(222, 210), Vector2(238, 210)], 1: [Vector2(199, 224), Vector2(225, 224)],
	3: [Vector2(213, 224), Vector2(235, 224)], 4: [Vector2(214, 252), Vector2(238, 252)],
	5: [Vector2(208, 302), Vector2(232, 302)], 6: [Vector2(203, 270), Vector2(223, 270)],
	9: [Vector2(230, 230), Vector2(252, 230)]}

func prepare() -> void:
	super.prepare()
	eye_color = EYE
	light_shaft_color = Color(0.7, 0.75, 1.0)

func duration() -> float:
	return 4.55

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty() or not EYES.has(int(bs.pose)):
		return out
	for e in EYES[int(bs.pose)]:
		out.append(px(Vector2(e) + Vector2(2, 2), Vector2(bs.foot)))
	return out

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り（0.36〜1.45） ---
	if t < 1.45:
		pan(t, 0.36, 1.45, 2, home + Vector2(-20, -84), home + Vector2(-20, -96))
		dark_bg = 0.82
		ally_tint(Color(0.2, 0.2, 0.3))
		light_shaft = 1.0
		light_shaft_x = home.x - 10
		bs = {"pose": 5, "foot": home, "mod": Color(0.34, 0.30, 0.46), "rim": Color(0.62, 0.66, 1.0, 0.75), "rim_off": Vector2(-2, -2)}
		eye = 0.0
		if t >= 0.92:
			var on := t < 0.97 or t >= 1.04
			eye = (0.6 if t < 0.97 else 1.0) if on else 0.0
		p.at(0.40, "motes", func(): p.fx_back.motes(Rect2(home + Vector2(-60, -190), Vector2(120, 170)), 26, Color(0.8, 0.85, 1.0), Vector2(0, 8), 2.0))
		p.at(0.62, "pebbles", func():
			p.fx.fall(Rect2(home + Vector2(-40, -150), Vector2(80, 20)), 7, ROCK.lightened(0.15))
			p.sfx.play("enc:golem_pebbles", -6.0))
		p.se(0.36, "enc:golem_rumble", -3.0)
		p.se(0.92, "enc:golem_eyes", -2.0)
		return
	# --- ショット2: 引き（1.45〜） ---
	p.at(1.45, "cut2", func():
		p.camera.cut(1, Vector2(640, 360))
		p.fx_back.clear())
	var lift := smoothstep(1.45, 1.75, t)
	dark_bg = 0.82 * (1.0 - lift) + 0.18 * lift
	light_shaft = 1.0 - lift
	ally_tint(Color(0.2, 0.2, 0.3).lerp(Color(0.86, 0.86, 0.92), lift))
	var mod := Color(0.34, 0.30, 0.46).lerp(Color.WHITE, lift)
	bs = {"pose": 5, "foot": home, "mod": mod}
	eye = 1.0 - 0.6 * smoothstep(1.6, 2.2, t)
	# 起き上がる: 5（うずくまる）→ 1（膝を起こす）→ 0（立つ・沈み込み）
	if t >= 1.52:
		bs.pose = 1
		bs.foot = home + Vector2(0, roundf(6.0 * (1.0 - ease_out((t - 1.52) / 0.16))))
	if t >= 1.70:
		bs.pose = 0
		bs.foot = home + Vector2(0, land_dip(t - 1.70, 4.0))
	p.se(1.50, "enc:golem_rise", -2.0)
	p.at(1.70, "stand", func():
		p.camera.shake(2, 0.16)
		p.fx_back.puff(home, 8, 60, DUST, 0.6))
	# 溜め: 両拳を高く振り上げ、少し伸び上がって止まる
	if t >= 1.92:
		bs.pose = 4
		bs.foot = home + Vector2(0, -roundf(4.0 * ease_out((t - 1.92) / 0.2)))
	p.se(1.92, "enc:golem_windup", -4.0)
	# 叩きつけ
	var slam := 2.24
	if t >= slam:
		bs.pose = 5
		bs.foot = home + Vector2(0, land_dip(t - slam, 4.0))
	if t >= slam + 0.42:
		bs.pose = 1
	if t >= slam + 0.62:
		bs.pose = 0
	p.at(slam, "slam", func():
		var hit := home + Vector2(-16, 2)
		p.camera.shake(6, 0.5)
		p.sfx.play("enc:golem_slam", 0.0)
		p.fx_back.crack(hit, 200, Color(0.05, 0.035, 0.07, 0.95), 2.4)
		p.fx_back.shock(hit, 24, 300, 0.6, Color(0.9, 0.86, 1.0, 0.9), 10.0, 0.2)
		p.fx.flash(hit + Vector2(0, -8), 30, 0.18, Color(1.0, 0.94, 0.85, 0.95))
		p.fx.rocks(hit + Vector2(0, -6), 24, ROCK, 1.1, 1.0, hit.y + 8)
		p.fx.puff(hit + Vector2(-60, 0), 16, 90, DUST, 2.0, 0.6, 1.3)
		p.fx.puff(hit + Vector2(60, 0), 16, 90, DUST, 2.0, 0.6, 1.3)
		p.fx.sparks(hit, 10, Color(1.0, 0.95, 0.8), Color(1.0, 0.6, 0.3), -PI / 2, PI * 0.9, 0.9))
	p.at(slam + 0.06, "brace", func(): allies_brace(true, 4.0))
	p.at(slam + 0.9, "relax", func(): allies_brace(false))
	title_card(t, 2.62, Color(0.75, 0.62, 1.0))
