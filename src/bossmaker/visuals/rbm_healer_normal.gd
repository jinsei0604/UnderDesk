extends "res://src/bossmaker/visuals/rbm_healer_action.gd"
func _init() -> void:
	kind="normal";duration=0.80;release_time=0.30;impact_time=0.43
	poses=[[0,-1],[0.08,0],[0.15,1],[0.24,2],[0.30,3],[0.46,2],[0.54,4],[0.65,0],[0.73,-1]]
	cues=[[release_time,"neutral_staff_tap",-5],[impact_time,"neutral_impact_light",-5]]
func _draw_effect() -> void:
	FX.normal(self,age,release_time,impact_time,_wand_position(),_launch,_target)
