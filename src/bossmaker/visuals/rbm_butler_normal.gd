extends "res://src/bossmaker/visuals/rbm_butler_action.gd"
func _init() -> void:
	kind="normal";duration=0.80;release_time=0.24;impact_time=0.40
	poses=[[0,-1],[0.06,-2],[0.13,1],[0.24,2],[0.31,6],[0.49,1],[0.62,-2],[0.74,-1]]
	cues=[[0.23,"neutral_staff_tap",-4],[impact_time,"neutral_impact_light",-4]]
func _draw_effect() -> void:
	FX.normal(self,age,release_time,impact_time,_watch_position(),_launch,_target)
