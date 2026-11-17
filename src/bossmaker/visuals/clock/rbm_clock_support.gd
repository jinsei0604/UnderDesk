extends "res://src/bossmaker/visuals/clock/rbm_clock_presentation.gd"
## 振り子の給仕長／終刻の給仕長の支援（回復・強化。rbm_battle_stage.gd の振り分けの表から使う）。中身は rbm_clock_presentation.gd と rbm_clock_fx_support.gd。

func _init() -> void:
	kind = "support"
