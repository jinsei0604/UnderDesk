extends "res://src/bossmaker/visuals/ally_awakening/rbm_ally_awakening_seq.gd"
## ハンマー使いの覚醒「熔鉱・地裂」の再生（2026-11-19 第2版）。中身は rbm_tank_awakening_fx.gd、音は assets_bossmaker/audio/ally_awakening/tank.wav。
## 本体は既存の12ポーズを切り替えるだけ（中割りの s:N はドット密度が違うので使わない、2026-10-28 ユーザーの指摘）:
## 立ち（0）→ 肩に担いで力を込める（8）→ 頭上に振りかぶる（4）→ 地面へ叩きつけ（5）→ 構え直し（6）→ 立ち（0）。
const Fx = preload("res://src/bossmaker/visuals/ally_awakening/rbm_tank_awakening_fx.gd")

func _init() -> void:
	character_id = "tank"
	fx_script = Fx
	sound_path = "res://assets_bossmaker/audio/ally_awakening/tank.wav"
	duration = float(Fx.T.end)
	release_time = float(Fx.T.release)
	quiet_time = float(Fx.T.release)

func shake_amplitude() -> float:
	return 8.0

func pose_at(t: float) -> String:
	if t < Fx.T.heft:
		return "b:0"
	if t < Fx.T.raise:
		return "b:8"
	if t < Fx.T.release:
		return "b:4"
	if t < Fx.T.recover:
		return "b:5"
	if t < Fx.T.settle:
		return "b:6"
	return "b:0"
