extends "res://src/bossmaker/visuals/clock/rbm_clock_presentation.gd"
## 振り子の給仕長／終刻の給仕長の覚醒（rbm_battle_stage.gd の振り分けの表から使う）。中身は rbm_clock_presentation.gd。

func _init() -> void:
	kind = "awakening"
