extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 共通の倒れ方（表示専用）: 専用の倒れ方が覚醒前のコマ絵に依存しているボス（武者・紳士）を、覚醒した後に倒した時に使う。
## 覚醒後の12ポーズの絵をそのまま使い（伸縮・回転しない）、のけぞる → 崩れて伏せる（地響き）→ ボスの色の粒になってほどける。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:dragon_fall"]
const DUST := Color(0.5, 0.52, 0.58, 0.9)

## ほどける縁と粒の色（ボスごと）。
var tint := Color(1.0, 0.92, 0.8)

func setup() -> void:
	super.setup()
	if asset.begins_with("musha"):
		tint = Color(0.35, 0.32, 0.4)
	elif asset.begins_with("gentleman"):
		tint = Color(1.0, 0.3, 0.3)

func duration() -> float:
	return 1.5

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
		bs.foot = h + Vector2(14, 0)
	p.at(0.30, "fall", func():
		p.sfx.play("enc:dragon_fall", -3.0)
		p.camera.shake(4, 0.4)
		p.fx_back.puff(h + Vector2(-50, 0), 14, 70, DUST, 1.3)
		p.fx_back.puff(h + Vector2(60, 0), 12, 60, DUST, 1.2))
	if t >= 0.65:
		dissolve = smoothstep(0.65, 1.42, t)
		edge = Color(tint, 1.0)
		block = 5.0
		for k in [0.72, 0.9, 1.08, 1.26]:
			p.at(k, "emb%s" % k, func(): p.fx.embers(h + Vector2(p.fx.rng.randf_range(-60, 60), -60), 10, tint, 50.0, 90.0, 1.2))
	if t >= 1.45:
		gone = true
