extends "res://src/bossmaker/visuals/rbm_samurai_action.gd"
func _init() -> void:
	kind="single";duration=1.14;release_time=0.41;impact_time=0.455;retreat_time=0.73
	poses=[[0,0],[0.06,1],[0.14,2],[0.20,3],[0.27,2],[0.34,4],[0.41,6],[0.51,7],[0.66,11],[0.73,12],[0.82,13],[1.03,14],[1.09,15]]
	cues=[[0.17,"wind_move",-13],[release_time,"wind_swing",-6],[impact_time,"wind_impact_light",-5]]
