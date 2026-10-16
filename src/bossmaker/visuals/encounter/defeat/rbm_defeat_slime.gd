extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## スライムが倒れる: ぷるぷる震える（つぶれた姿勢と伸びた姿勢を細かく切り替える）→ べちゃっと平たく広がる
## → しずくになってはじけ、水たまりが湯気になって消える。

## この演出で鳴らす音（事前読み込みの宣言）。
const SOUNDS := ["enc:slime_wobble", "enc:slime_splat", "enc:slime_fizz"]
const RED := Color(0.86, 0.26, 0.24)

func duration() -> float:
	return 1.45

func advance(t: float, _dt: float) -> void:
	age = t
	var h := home()
	if gone:
		return
	if t < 0.42:
		# 震え: 10（つぶれ）と 11（目を閉じる）を細かく切り替え、左右に2px揺れる
		bs.pose = 10 if int(t / 0.06) % 2 == 0 else 11
		bs.foot = h + Vector2(8 + (2 if int(t / 0.04) % 2 == 0 else -2), 0)
	else:
		bs.pose = 3
		bs.foot = h + Vector2(8, 0)
	p.at(0.0, "wobble", func(): p.sfx.play("enc:slime_wobble", -2.0))
	p.at(0.42, "splat", func():
		p.sfx.play("enc:slime_splat", 0.0)
		p.camera.shake(3, 0.25)
		p.fx.drops(h + Vector2(0, -24), 26, RED, 1.1, h.y + 4)
		p.fx_back.puff(h, 6, 60, Color(0.7, 0.35, 0.35, 0.5), 0.6))
	if t >= 0.62:
		dissolve = smoothstep(0.62, 1.30, t)
		edge = Color(1.0, 0.75, 0.7, 0.9)
		block = 4.0
		rise = 0.2
		p.at(0.8, "steam", func():
			p.sfx.play("enc:slime_fizz", -4.0)
			p.fx.wisps(h + Vector2(0, -8), 16, Color(1.0, 0.85, 0.85, 0.55), 50.0, 50.0, 1.2))
	if t >= 1.32:
		gone = true
