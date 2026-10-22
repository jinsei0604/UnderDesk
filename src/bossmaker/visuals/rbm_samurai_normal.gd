extends "res://src/bossmaker/visuals/rbm_samurai_action.gd"
func _init() -> void:
	kind="normal";duration=0.86;release_time=0.31;impact_time=0.35;retreat_time=0.48
	poses=[[0,0],[0.05,1],[0.10,2],[0.15,3],[0.20,2],[0.24,4],[0.31,6],[0.40,7],[0.48,12],[0.56,13],[0.75,14],[0.81,15]]
	cues=[[release_time,"neutral_sword_swing",-6],[impact_time,"neutral_impact_light",-5]]
