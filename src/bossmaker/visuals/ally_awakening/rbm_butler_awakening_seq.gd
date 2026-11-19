extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_seq.gd"
## 老執事の覚醒「凍てつく刻」の再生（2026-11-19 第2版）。中身は rbm_butler_awakening_fx.gd、音は assets_bossmaker/audio/ally_awakening/butler.wav。
## 本体は既存の12ポーズを切り替えるだけ: 立ち（0）→ 胸に手（6）→ 懐中時計を高く掲げる（8）→ 両腕を広げる（5）→ 胸に手（6）→ 立ち（0）。
const Fx = preload("res://src/bossmaker/visuals/ally_awakening/rbm_butler_awakening_fx.gd")

func _init() -> void:
	character_id = "butler"
	fx_script = Fx
	sound_path = "res://assets_bossmaker/audio/ally_awakening/butler.wav"
	duration = float(Fx.T.end)
	release_time = float(Fx.T.release)
	quiet_time = float(Fx.T.release)

func shake_amplitude() -> float:
	return 5.0

func pose_at(t: float) -> String:
	if t < Fx.T.compose:
		return "b:0"
	if t < Fx.T.raise:
		return "b:6"
	if t < Fx.T.release:
		return "b:8"
	if t < Fx.T.spread_end:
		return "b:5"
	if t < Fx.T.settle:
		return "b:6"
	return "b:0"
