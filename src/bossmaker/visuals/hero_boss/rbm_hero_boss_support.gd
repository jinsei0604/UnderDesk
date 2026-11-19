extends "res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_presentation.gd"
## ヒーローの支援（回復・強化。rbm_battle_stage.gd の振り分けの表から使う）。中身は rbm_hero_boss_presentation.gd と rbm_hero_fx_support.gd。

func _init() -> void:
	kind = "support"
