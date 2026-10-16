extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 竜が倒れる: のけぞる → 崩れ落ちて伏せる（地響き）→ 体が火の粉になって昇っていく。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:dragon_cry", "enc:dragon_fall", "enc:dragon_burn"]
const DUST := Color(0.55, 0.6, 0.66, 0.9)
const EMBER := Color(1.0, 0.68, 0.28)

func duration() -> float:
	return 1.75

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	if t < 0.30:
		bs.pose = 11
		bs.foot = h + Vector2(14, -roundf(4.0 * sin(PI * t / 0.3)))
	else:
		bs.pose = 10
		bs.foot = h + Vector2(14, land_dip(t - 0.55))
	p.at(0.0, "cry", func(): p.sfx.play("enc:dragon_cry", 0.0))
	p.at(0.55, "fall", func():
		p.sfx.play("enc:dragon_fall", 0.0)
		p.camera.shake(6, 0.6)
		p.fx_back.puff(h + Vector2(-60, 0), 18, 90, DUST, 1.6)
		p.fx_back.puff(h + Vector2(70, 0), 16, 80, DUST, 1.4)
		p.fx_back.shock(h, 30, 260, 0.6, Color(0.9, 0.95, 1.0, 0.7), 8.0, 0.22))
	if t >= 0.95:
		dissolve = smoothstep(0.95, 1.70, t)
		edge = Color(1.0, 0.62, 0.22, 1.0)
		block = 5.0
		p.at(0.95, "burn", func(): p.sfx.play("enc:dragon_burn", -2.0))
		for k in [1.0, 1.12, 1.24, 1.36, 1.48]:
			p.at(k, "emb%s" % k, func(): p.fx.embers(h + Vector2(p.fx.rng.randf_range(-70, 70), -50), 14, EMBER, 60.0, 100.0, 1.4))
	if t >= 1.72:
		gone = true

static func land_dip(x: float) -> float:
	if x < 0.0 or x > 0.2:
		return 0.0
	return roundf(4.0 * sin(PI * x / 0.2))
