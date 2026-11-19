extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_seq.gd"
## 少女の覚醒「天雷の祈り」の再生（2026-11-19 第2版。Codex の版を置き換え）。中身は rbm_healer_awakening_fx.gd、音は assets_bossmaker/audio/ally_awakening/healer.wav。
## 本体は既存の12ポーズを切り替えるだけ: 立ち（0）→ 目を閉じて杖を胸に抱く（4）→ 杖を天へ掲げる（9。雷を杖で受ける）→ 両腕を広げる（5）→ 立ち（0）。
const Fx = preload("res://src/bossmaker/visuals/ally_awakening/rbm_healer_awakening_fx.gd")

func _init() -> void:
	character_id = "healer"
	fx_script = Fx
	sound_path = "res://assets_bossmaker/audio/ally_awakening/healer.wav"
	duration = float(Fx.T.end)
	release_time = float(Fx.T.release)
	quiet_time = float(Fx.T.release)

func shake_amplitude() -> float:
	return 6.0

func pose_at(t: float) -> String:
	if t < Fx.T.pray:
		return "b:0"
	if t < Fx.T.raise:
		return "b:4"
	if t < Fx.T.cast:
		return "b:9"
	if t < Fx.T.settle:
		return "b:5"
	return "b:0"
