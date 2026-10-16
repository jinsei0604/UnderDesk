extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 狼が倒れる: 鳴いてのけぞる → 崩れるように伏せる（砂ぼこり）→ 青い霊気になって、遠吠えの名残とともに昇る。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:wolf_yelp", "enc:wolf_down", "enc:wolf_fade"]
const DUST := Color(0.6, 0.6, 0.62, 0.85)
const SPIRIT := Color(0.55, 0.75, 1.0, 0.75)

func duration() -> float:
	return 1.5

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	if t < 0.32:
		bs.pose = 11
		bs.foot = h + Vector2(8 + roundf(8.0 * ease_o(t / 0.32)), 0)
	else:
		bs.pose = 6
		bs.foot = h + Vector2(16, 0)
	p.at(0.0, "yelp", func(): p.sfx.play("enc:wolf_yelp", -1.0))
	p.at(0.32, "down", func():
		p.sfx.play("enc:wolf_down", -1.0)
		p.camera.shake(3, 0.3)
		p.fx_back.puff(h + Vector2(10, 0), 12, 70, DUST, 1.0))
	if t >= 0.7:
		dissolve = smoothstep(0.70, 1.40, t)
		edge = Color(0.75, 0.88, 1.0, 1.0)
		block = 4.0
		p.at(0.7, "spirit", func(): p.sfx.play("enc:wolf_fade", -3.0))
		for k in [0.75, 0.9, 1.05, 1.2]:
			p.at(k, "w%s" % k, func(): p.fx.wisps(h + Vector2(p.fx.rng.randf_range(-50, 50), -40), 8, SPIRIT, 40.0, 70.0, 1.3))
	if t >= 1.42:
		gone = true

static func ease_o(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)
