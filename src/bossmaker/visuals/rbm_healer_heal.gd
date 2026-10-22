extends "res://src/bossmaker/visuals/rbm_healer_action.gd"
func _init() -> void:
	kind="heal";duration=1.30;release_time=0.53;impact_time=0.82
	poses=[[0,-1],[0.08,0],[0.16,4],[0.25,5],[0.36,6],[0.53,7],[0.93,4],[1.06,11],[1.15,0],[1.23,-1]]
	cues=[[release_time,"neutral_staff_tap",-12],[impact_time,"heal_hp",-5]]
func _draw_effect() -> void:
	FX.heal(self,age,release_time,impact_time,_wand_position(),_launch,_recipients)
