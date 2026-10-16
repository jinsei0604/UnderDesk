extends "res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd"
## 騎士の登場（案B・第2版）。黒鉄の鎧・紫の布・紫に光る兜のすき間。重く、規律正しい。
## 寄り: 剣を地に立てて待つ騎士の兜。暗がりで、兜のすき間に紫の光が横に走って灯る（低い響き）。
## 引き: 剣を顔の前に立てて礼をし、刃に紫の光が下から上へ走る（澄んだ金属音）
## → 剣を払って低く構える（斬撃の弧・火花・地面の傷）→ 味方が身構える → 題字。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:knight_step", "enc:knight_visor", "enc:knight_raise", "enc:knight_ring", "enc:knight_swing"]

const PURPLE := Color(0.72, 0.42, 1.0)
## 兜のすき間（ポーズ画像 512×512 の上の画素）
const VISOR := {0: Vector2(280, 182), 7: Vector2(254, 190), 8: Vector2(256, 140), 2: Vector2(254, 222), 6: Vector2(232, 226), 3: Vector2(250, 218)}
## 剣を立てた姿勢（8）の刃の根元と先
const BLADE_8 := [Vector2(256, 236), Vector2(256, 104)]

var visor := 0.0
var blade_k := 0.0
var arc := 0.0
var flare := 0.0

func prepare() -> void:
	super.prepare()
	eye_color = PURPLE

func duration() -> float:
	return 4.5

func visor_point() -> Vector2:
	var pose := int(bs.get("pose", 0))
	return px(VISOR.get(pose, VISOR[0]), Vector2(bs.foot))

func extra_top(ci: CanvasItem) -> void:
	if bs.is_empty():
		return
	if visor > 0.0:
		var c := visor_point()
		var w := roundf(10.0 * clampf(visor * 1.4, 0.0, 1.0) / 2.0) * 2.0
		ci.draw_rect(Rect2(c - Vector2(w * 0.5 + 6, 5), Vector2(w + 12, 10)), Color(PURPLE, 0.18 * visor))
		ci.draw_rect(Rect2(c - Vector2(w * 0.5 + 3, 3), Vector2(w + 6, 6)), Color(PURPLE, 0.3 * visor))
		ci.draw_rect(Rect2(c - Vector2(w * 0.5, 1), Vector2(w, 2)), Color(PURPLE.lightened(0.5), minf(1.0, visor)))
		if flare > 0.0:
			# 灯る瞬間だけ、光が横へ長く伸びて消える
			var fl := roundf(60.0 * flare)
			ci.draw_rect(Rect2(c - Vector2(fl, 1), Vector2(fl * 2, 2)), Color(PURPLE.lightened(0.6), 0.8 * flare))
			ci.draw_rect(Rect2(c - Vector2(fl * 0.6, 2), Vector2(fl * 1.2, 4)), Color(PURPLE, 0.3 * flare))
	if blade_k > 0.0 and int(bs.get("pose", 0)) == 8:
		var a := px(BLADE_8[0], Vector2(bs.foot))
		var b := px(BLADE_8[1], Vector2(bs.foot))
		var head := a.lerp(b, clampf(blade_k, 0.0, 1.0))
		var tail := a.lerp(b, clampf(blade_k - 0.35, 0.0, 1.0))
		ci.draw_line(tail, head, Color(PURPLE, 0.5), 4.0, false)
		ci.draw_line(tail, head, Color(1, 0.92, 1.0, 0.95), 2.0, false)
		if blade_k >= 1.0:
			glint(ci, b, clampf(2.0 - blade_k, 0.0, 1.0), Color(0.95, 0.85, 1.0))
	if arc > 0.0:
		# 剣を払う弧（2pxの線の束。先が明るい）
		var f: Vector2 = Vector2(bs.foot)
		var center := f + Vector2(-20, -80)
		var start := -PI * 0.35
		var end := start - PI * 0.9 * clampf(arc, 0.0, 1.0)
		var fade := 1.0 - clampf((arc - 1.0) / 0.6, 0.0, 1.0)
		for i in range(3):
			ci.draw_arc(center, 90.0 - i * 6.0, end, start, 24, Color(PURPLE.lightened(0.3 * i), (0.55 - i * 0.15) * fade), 2.0, false)

func advance(t: float, _dt: float) -> void:
	var home: Vector2 = p.boss_foot()
	open_from_list(t)
	fade_in(t, 0.36, 0.3)
	bars(t, 0.30)
	# --- ショット1: 寄り。兜のすき間に光が灯る（0.36〜1.35） ---
	if t < 1.35:
		bs = {"pose": 7, "foot": home, "mod": Color(0.35, 0.33, 0.42), "rim": Color(0.6, 0.45, 0.9, 0.7), "rim_off": Vector2(-2, -2)}
		p.camera.cut(2, visor_point() + Vector2(-30, 40))
		dark_bg = 0.82
		ally_tint(Color(0.18, 0.18, 0.26))
		visor = 0.0
		flare = 0.0
		if t >= 0.8:
			visor = ease_out((t - 0.8) / 0.25)
			flare = 1.0 - clampf((t - 0.8) / 0.35, 0.0, 1.0)
		p.se(0.36, "enc:knight_step", -6.0)
		p.se(0.8, "enc:knight_visor", -2.0)
		return
	# --- ショット2: 引き（1.35〜） ---
	p.at(1.35, "cut2", func(): p.camera.cut(1, Vector2(640, 360)))
	flare = 0.0
	var lift := smoothstep(1.35, 1.55, t)
	dark_bg = 0.82 * (1.0 - lift) + 0.12 * lift
	ally_tint(Color(0.18, 0.18, 0.26).lerp(Color(0.9, 0.9, 0.95), lift))
	visor = 1.0
	bs = {"pose": 7, "foot": home, "mod": Color(0.35, 0.33, 0.42).lerp(Color.WHITE, lift)}
	# 剣を顔の前に立てて礼（8）。刃に光が走る
	if t >= 1.55:
		bs.pose = 8
		bs.erase("rim")
	p.se(1.55, "enc:knight_raise", -3.0)
	blade_k = 0.0
	if t >= 1.75 and t < 2.4:
		blade_k = (t - 1.75) / 0.3
	p.se(1.75, "enc:knight_ring", -1.0)
	# 剣を払って低く構える（9 → 3 → 2）
	if t >= 2.40:
		bs.pose = 9
	if t >= 2.52:
		bs.pose = 3
		arc = (t - 2.52) / 0.12
	if t >= 2.70:
		bs.pose = 2
	p.at(2.52, "swing", func():
		p.sfx.play("enc:knight_swing", 0.0)
		p.camera.shake(3, 0.25)
		p.fx.sparks(home + Vector2(-110, -6), 14, Color(1, 0.95, 1.0), PURPLE, -PI * 0.7, PI * 0.6, 0.9)
		p.fx_back.crack(home + Vector2(-110, 2), 60, Color(0.05, 0.03, 0.08, 0.9), 2.0, 1)
		p.fx_back.puff(home + Vector2(-90, 0), 8, 40, Color(0.6, 0.58, 0.62, 0.8), 0.8))
	p.at(2.55, "brace", func(): allies_brace(true, 4.0))
	p.at(3.6, "relax", func(): allies_brace(false))
	title_card(t, 2.80, PURPLE)
