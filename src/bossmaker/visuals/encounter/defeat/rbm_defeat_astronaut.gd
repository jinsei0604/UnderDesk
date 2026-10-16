extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 宇宙飛行士が倒れる: 無線が途切れる音とともによろめき → 重さを失ったようにゆっくり浮き上がり
## → 星屑にほどけて夜空へ消える。覚醒の意匠（紫のバイザー・紫の渦）は使わない。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:astro_static", "enc:astro_float"]
const STAR := Color(0.85, 0.92, 1.0)

func duration() -> float:
	return 1.6

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	bs.pose = 11 if t < 0.35 else 0
	var lift := roundf(48.0 * pow(smoothstep(0.35, 1.5, t), 1.4) / 2.0) * 2.0
	bs.foot = h + Vector2(8 + roundf(4.0 * sin(t * 3.0)), -lift)
	p.at(0.0, "static", func(): p.sfx.play("enc:astro_static", -2.0))
	p.at(0.35, "float", func():
		p.sfx.play("enc:astro_float", -2.0)
		p.fx_back.puff(h, 8, 40, Color(0.75, 0.78, 0.85, 0.5), 0.4, 0.3))
	if t >= 0.7:
		dissolve = smoothstep(0.70, 1.50, t)
		edge = Color(0.85, 0.95, 1.0, 1.0)
		rise = 0.8
		block = 3.0
		for k in [0.75, 0.9, 1.05, 1.2, 1.35]:
			p.at(k, "s%s" % k, func():
				var c := chest_point() + Vector2(0, -lift)
				p.fx.stars(c + Vector2(p.fx.rng.randf_range(-30, 30), p.fx.rng.randf_range(-40, 30)), 4, STAR, 16.0)
				p.fx.embers(c, 6, STAR, 30.0, 60.0, 1.4))
	if t >= 1.52:
		gone = true
