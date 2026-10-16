extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 宇宙飛行士の登場（案B・第2版）。静かで不思議な訪問者。覚醒の意匠（紫のバイザー・紫の渦）は使わない。
## 寄り: 夜空を、青白い光が尾を引いて斜めに落ちてくる（無線の雑音と電子音）。
## 引き: 光が戦場に降りて輪が広がり、宇宙飛行士が低い重力でゆっくり降り立つ（足元の噴射・ふわりと舞う砂）
## → 手元の端末で味方を走査する（水色の走査の輪・電子音）→ バイザーが光る → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:astro_radio", "enc:astro_fall", "enc:astro_arrive", "enc:astro_land", "enc:astro_beep", "enc:astro_visor"]

const CYAN := Color(0.55, 0.9, 1.0)
const DUST := Color(0.75, 0.78, 0.85, 0.7)
var streak := {}
var scan := 0.0

func prepare() -> void:
	super.prepare()
	eye_color = CYAN

func duration() -> float:
	return 4.6

func visor_point() -> Vector2:
	return px(Vector2(41, 28), Vector2(bs.foot))

func extra_back(ci: CanvasItem) -> void:
	if streak.is_empty():
		return
	# 落ちてくる光（頭の明るい点と、細くなる尾）
	var head: Vector2 = streak.head
	var dir: Vector2 = streak.dir
	for i in range(14):
		var q := (head - dir * i * 9.0).snapped(Vector2(2, 2))
		var a := (1.0 - i / 14.0) * float(streak.a)
		var s := 6.0 - i * 0.35
		ci.draw_rect(Rect2(q - Vector2(s, s) * 0.5, Vector2(s, s)), Color(CYAN, 0.35 * a))
	var hp := head.snapped(Vector2(2, 2))
	ci.draw_rect(Rect2(hp - Vector2(10, 10), Vector2(20, 20)), Color(CYAN, 0.15 * float(streak.a)))
	ci.draw_rect(Rect2(hp - Vector2(6, 6), Vector2(12, 12)), Color(CYAN, 0.3 * float(streak.a)))
	ci.draw_rect(Rect2(hp - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, float(streak.a)))

func extra_top(ci: CanvasItem) -> void:
	if scan > 0.0 and scan < 1.0 and not bs.is_empty():
		# 端末から味方へ広がる走査の輪（扇形の弧）
		var origin := px(Vector2(30, 52), Vector2(bs.foot))
		var r := 40.0 + 520.0 * scan
		var a := (1.0 - scan) * 0.8
		ci.draw_arc(origin, r, PI * 0.82, PI * 1.18, 32, Color(CYAN, a), 2.0, false)
		ci.draw_arc(origin, r - 8.0, PI * 0.85, PI * 1.15, 32, Color(CYAN, a * 0.35), 4.0, false)

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り。夜空を光が落ちてくる（0.36〜1.30） ---
	if t < 1.30:
		p.camera.cut(2, Vector2(820, 170))
		dark_bg = 0.45
		ally_tint(Color(0.4, 0.4, 0.5))
		bs = {}
		var k := clampf((t - 0.45) / 0.8, 0.0, 1.0)
		var dir := Vector2(-0.55, 1.0).normalized()
		streak = {"head": Vector2(1000, 40) + dir * 300.0 * ease_in(k), "dir": dir, "a": 1.0 if t >= 0.45 else 0.0}
		p.se(0.36, "enc:astro_radio", -3.0)
		p.se(0.45, "enc:astro_fall", -3.0)
		return
	streak = {}
	# --- ショット2: 引き。降り立つ（1.30〜） ---
	p.at(1.30, "cut2", func():
		p.camera.cut(1, Vector2(640, 360))
		p.fx_back.shock(home, 20, 260, 0.7, Color(CYAN, 0.7), 8.0, 0.22)
		p.fx.flash(home + Vector2(0, -40), 30, 0.25, Color(0.85, 0.97, 1.0, 0.9))
		p.sfx.play("enc:astro_arrive", -1.0))
	var lift := smoothstep(1.30, 1.5, t)
	dark_bg = 0.45 * (1.0 - lift)
	light_shaft_color = CYAN
	light_shaft_x = home.x
	light_shaft = (1.0 - smoothstep(2.1, 2.6, t)) if t >= 1.3 else 0.0
	ally_tint(Color(0.4, 0.4, 0.5).lerp(Color.WHITE, lift))
	# 低い重力: 上からゆっくり降り、着地の直前でさらに減速する
	var d := ease_out(clampf((t - 1.30) / 0.95, 0.0, 1.0))
	var y := roundf(lerpf(-300.0, 0.0, d) / 2.0) * 2.0
	bs = {"pose": 0, "foot": home + Vector2(0, y)}
	if t < 2.25 and int(t * 20.0) % 2 == 0:
		p.at(snappedf(t, 0.05), "thr%s" % snappedf(t, 0.05), func(): p.fx.embers(home + Vector2(0, y + 2), 2, CYAN, 6.0, -60.0, 0.4))
	p.at(2.25, "land", func():
		p.sfx.play("enc:astro_land", -2.0)
		p.fx_back.puff(home, 12, 60, DUST, 0.5, 2.5, 0.9))
	# 端末で走査（1）
	if t >= 2.55 and t < 3.55:
		bs.pose = 1
	scan = clampf((t - 2.70) / 0.7, 0.0, 1.0) if t >= 2.70 else 0.0
	p.se(2.60, "enc:astro_beep", -3.0)
	p.at(2.75, "brace", func(): allies_brace(true, 2.0))
	eye = 0.0
	if t >= 3.6:
		eye = 1.0 - smoothstep(3.6, 3.9, t)
	p.at(3.6, "visor", func(): p.sfx.play("enc:astro_visor", -5.0))
	p.at(3.7, "relax", func(): allies_brace(false))
	title_card(t, 2.85, CYAN)

func eye_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if bs.is_empty() or int(bs.pose) != 0:
		return out
	out.append(visor_point())
	return out
