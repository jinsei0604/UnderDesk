extends "res://src/bossmaker/visuals/rbm_butler_action.gd"
func _init() -> void:
	kind="bolt";duration=1.12;release_time=0.42;impact_time=0.62
	poses=[[0,-1],[0.08,-2],[0.16,1],[0.28,5],[0.37,3],[0.42,6],[0.57,7],[0.79,2],[0.94,1],[1.02,-2],[1.09,-1]]
	cues=[[0.22,"ice_cast",-6],[release_time,"ice_move",-11],[impact_time,"ice_impact_light",-2]]
func _draw_effect() -> void:
	FX.bolt(self,age,release_time,impact_time,_watch_position(),_launch,_target)
