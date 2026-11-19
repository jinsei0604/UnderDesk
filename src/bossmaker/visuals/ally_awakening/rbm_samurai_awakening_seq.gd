extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_seq.gd"
## 侍の覚醒「墨風・一閃」の再生（2026-11-19 第2版）。中身は rbm_samurai_awakening_fx.gd、音は assets_bossmaker/audio/ally_awakening/samurai.wav。
## 本体は最初から最後まで「目を閉じて立つ」1枚（b:0。つなぎが s:18 の閉じた目で描く）。
## 2026-11-19 ユーザー「侍は前の目をつむって立った状態にして、エフェクトは今のように墨と風」→ 居合の構え・振り抜き・納刀のポーズはやめ、
## 目を閉じたまま立っている間に、見えない速さで抜いて納める（一閃と墨と納刀の音だけが見える・聞こえる）。
const Fx = preload("res://src/bossmaker/visuals/ally_awakening/rbm_samurai_awakening_fx.gd")

func _init() -> void:
	character_id = "samurai"
	fx_script = Fx
	sound_path = "res://assets_bossmaker/audio/ally_awakening/samurai.wav"
	duration = float(Fx.T.end)
	release_time = float(Fx.T.release)
	quiet_time = float(Fx.T.still)

func shake_amplitude() -> float:
	return 6.0

func pose_at(_t: float) -> String:
	return "b:0"
