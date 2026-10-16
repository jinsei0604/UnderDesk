extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## ゴーストが倒れる: 両腕を広げて叫ぶ（ゆがみの輪）→ 体が震えながら薄れ → 上へほどけて霊気になり、目の光が最後に消える。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:ghost_shriek"]
const SPIRIT := Color(1.0, 0.72, 0.38, 0.7)
var eyes := 1.0

func duration() -> float:
	return 1.45

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	bs.pose = 11 if t < 0.2 else 5
	var jitter := 0.0 if t < 0.2 else (2.0 if int(t / 0.04) % 2 == 0 else -2.0)
	bs.foot = h + Vector2(8 + jitter, -roundf(6.0 * smoothstep(0.2, 1.2, t)))
	p.at(0.2, "shriek", func():
		p.sfx.play("enc:ghost_shriek", 0.0)
		p.fx.shock(chest_point(), 10, 160, 0.5, Color(1.0, 0.8, 0.55, 0.7), 6.0, 1.0)
		p.fx.shock(chest_point(), 10, 110, 0.4, Color(1.0, 0.9, 0.7, 0.5), 4.0, 1.0))
	if t >= 0.45:
		dissolve = smoothstep(0.45, 1.25, t)
		edge = Color(1.0, 0.85, 0.6, 1.0)
		rise = 0.9
		block = 4.0
		for k in [0.5, 0.65, 0.8, 0.95, 1.1]:
			p.at(k, "w%s" % k, func(): p.fx.wisps(chest_point() + Vector2(p.fx.rng.randf_range(-40, 40), p.fx.rng.randf_range(-40, 30)), 7, SPIRIT, 30.0, 80.0, 1.4))
	eyes = 1.0 - smoothstep(1.1, 1.35, t)
	if t >= 1.38:
		gone = true

func eye_points() -> Array[Vector2]:
	var m := Sprites.meta(asset)
	var f: Vector2 = Vector2(bs.foot)
	return [(f + (Vector2(242, 196) - Vector2(m.foot)) * float(m.scale)).round(), (f + (Vector2(266, 196) - Vector2(m.foot)) * float(m.scale)).round()]

func draw_top(ci: CanvasItem) -> void:
	if gone or bs.is_empty() or eyes <= 0.0 or dissolve < 0.5:
		return
	for e in eye_points():
		ci.draw_rect(Rect2(e - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.75, 0.35, 0.3 * eyes))
		ci.draw_rect(Rect2(e - Vector2(1, 1), Vector2(2, 2)), Color(1.0, 0.95, 0.75, eyes))
