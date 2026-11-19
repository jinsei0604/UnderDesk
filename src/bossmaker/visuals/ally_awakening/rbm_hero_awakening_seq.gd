extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_seq.gd"
## 勇者の覚醒「炎の誓い」の再生（2026-11-19 第2版）。中身は rbm_hero_awakening_fx.gd、音は assets_bossmaker/audio/ally_awakening/hero.wav。
## 本体は既存の12ポーズを切り替えるだけ（中割りなし）: 立ち（0）→ 片膝で剣を頭上に掲げる（8）→ 剣を顔の前に立てる（6）→ 立ち（0）。
const Fx = preload("res://src/bossmaker/visuals/ally_awakening/rbm_hero_awakening_fx.gd")

func _init() -> void:
	character_id = "hero"
	fx_script = Fx
	sound_path = "res://assets_bossmaker/audio/ally_awakening/hero.wav"
	duration = float(Fx.T.end)
	release_time = float(Fx.T.release)
	quiet_time = float(Fx.T.release)

func shake_amplitude() -> float:
	return 7.0

func pose_at(t: float) -> String:
	if t < Fx.T.kneel:
		return "b:0"
	if t < Fx.T.oath:
		return "b:8"
	if t < Fx.T.settle:
		return "b:6"
	return "b:0"
