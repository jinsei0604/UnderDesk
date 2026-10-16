extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## ゴーレムが倒れる: よろめく → 体に光るひびが走る → 崩れて地面に沈み、破片と土煙だけが残る。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:golem_crack", "enc:golem_crumble"]
const ROCK := Color(0.40, 0.34, 0.50)
const DUST := Color(0.50, 0.47, 0.55, 0.9)
var cracks := 0.0

func duration() -> float:
	return 1.55

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	bs.pose = 11 if t < 0.55 else 5
	bs.foot = (h + Vector2(18 - roundf(4.0 * sin(t * 30.0) * (1.0 - t / 0.55)), 0)) if t < 0.55 else h + Vector2(10, 0)
	cracks = smoothstep(0.12, 0.5, t)
	p.at(0.12, "crack_se", func(): p.sfx.play("enc:golem_crack", -2.0))
	p.at(0.55, "crumble", func():
		p.sfx.play("enc:golem_crumble", 0.0)
		p.camera.shake(5, 0.8)
		p.fx_back.puff(h + Vector2(-40, 0), 16, 70, DUST, 1.4)
		p.fx_back.puff(h + Vector2(50, 0), 16, 70, DUST, 1.4)
		p.fx.rocks(h + Vector2(0, -70), 26, ROCK, 0.9, 1.1, h.y + 6))
	if t >= 0.55:
		sink = roundf(pow(clampf((t - 0.55) / 0.9, 0.0, 1.0), 2.0) * 200.0 / 2.0) * 2.0
		bs.ground = h.y + 2
		for k in [0.7, 0.85, 1.0, 1.15]:
			p.at(k, "deb%s" % k, func(): p.fx.rocks(h + Vector2(p.fx.rng.randf_range(-50, 50), -12), 6, ROCK, 0.6, 0.9, h.y + 6))
		p.at(1.2, "settle", func(): p.fx_back.smoke(h + Vector2(0, -6), 10, Color(0.45, 0.43, 0.5, 0.6), 40.0, 30.0))
	if t >= 1.45:
		gone = true

func draw_top(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or cracks <= 0.0:
		return
	var r := Sprites.pose_rect(asset, int(bs.pose), Vector2(bs.foot) + Vector2(0, sink))
	var c := r.get_center()
	var lines := [[Vector2(-30, -40), Vector2(10, 0), Vector2(-6, 34)], [Vector2(20, -50), Vector2(-4, -10), Vector2(30, 30)], [Vector2(-50, 10), Vector2(-20, 20), Vector2(-40, 50)]]
	for li in range(lines.size()):
		var k := clampf(cracks * 3.0 - li, 0.0, 1.0)
		var pts: Array = lines[li]
		for i in range(pts.size() - 1):
			var a: Vector2 = c + Vector2(pts[i])
			var b: Vector2 = c + Vector2(pts[i + 1])
			var e := a.lerp(b, k)
			var steps := int(a.distance_to(e) / 2.0)
			for s in range(steps):
				var q := a.lerp(e, float(s) / maxf(1, steps)).snapped(Vector2(2, 2))
				if r.has_point(q) and q.y < Vector2(bs.foot).y:
					ci.draw_rect(Rect2(q - Vector2(1, 1), Vector2(4, 4)), Color(1.0, 0.7, 0.3, 0.35))
					ci.draw_rect(Rect2(q, Vector2(2, 2)), Color(1.0, 0.92, 0.6, 0.95))
