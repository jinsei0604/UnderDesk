extends "res://src/bossmaker/visuals/rbm_musha_awakened_vfx.gd"
## 覚醒後の単体/全体の前面VFX(承認済み 2026-09-27): 元の前面VFXのうち「技名の下地」だけを残す。
## 赤い衝撃波・白い閃光・白黒の断裂・煙・予兆の線は描かない(すべて墨の層 rbm_musha_ink_director.gd が墨で描く)。

func _draw() -> void:
	if kind != "awakening":
		_draw_name_plaque(age)
