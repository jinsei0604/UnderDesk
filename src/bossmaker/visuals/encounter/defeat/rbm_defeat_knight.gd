extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 騎士が倒れる: よろめく → 剣を地に突き立てて体を支える（金属音・火花）→ 兜の奥の紫の光が漏れて消え、
## 鎧が下から紫の火の粉にほどけていく。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:knight_plant", "enc:knight_fade"]
const PURPLE := Color(0.72, 0.42, 1.0)
var visor := 1.0

func duration() -> float:
	return 1.55

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	if t < 0.3:
		bs.pose = 11
		bs.foot = h + Vector2(8 + roundf(6.0 * sin(PI * t / 0.3)), 0)
	else:
		bs.pose = 6
		bs.foot = h + Vector2(8, land(t - 0.3))
	p.at(0.3, "plant", func():
		p.sfx.play("enc:knight_plant", 0.0)
		p.camera.shake(3, 0.25)
		p.fx.sparks(h + Vector2(-6, -2), 14, Color(1, 0.95, 0.85), Color(0.8, 0.5, 1.0), -PI / 2, PI * 0.8, 0.8)
		p.fx_back.puff(h, 8, 50, Color(0.6, 0.58, 0.62, 0.8), 0.7))
	visor = 1.0 + 0.8 * smoothstep(0.45, 0.6, t) - 1.8 * smoothstep(0.6, 0.9, t)
	p.at(0.55, "escape", func():
		p.sfx.play("enc:knight_fade", -2.0)
		p.fx.ray_burst(visor_point(), 10, 60.0, 0.5, Color(PURPLE, 0.85), 2.0))
	if t >= 0.8:
		dissolve = smoothstep(0.80, 1.45, t)
		edge = Color(0.85, 0.6, 1.0, 1.0)
		rise = -0.6
		block = 4.0
		for k in [0.85, 1.0, 1.15, 1.3]:
			p.at(k, "e%s" % k, func(): p.fx.embers(h + Vector2(p.fx.rng.randf_range(-30, 30), -p.fx.rng.randf_range(10, 120)), 10, PURPLE, 30.0, 70.0, 1.1))
	if t >= 1.48:
		gone = true

func land(x: float) -> float:
	if x < 0.0 or x > 0.16:
		return 0.0
	return roundf(3.0 * sin(PI * x / 0.16))

func visor_point() -> Vector2:
	var m := Sprites.meta(asset)
	return (Vector2(bs.foot) + (Vector2(214, 196) - Vector2(m.foot)) * float(m.scale)).round()

func draw_top(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or visor <= 0.0 or dissolve > 0.6:
		return
	var c := visor_point()
	var k := clampf(visor, 0.0, 1.8)
	ci.draw_rect(Rect2(c - Vector2(5, 1), Vector2(10, 2)), Color(PURPLE.lightened(0.4), minf(1.0, k)))
	ci.draw_rect(Rect2(c - Vector2(8, 3), Vector2(16, 6)), Color(PURPLE, 0.25 * k))
