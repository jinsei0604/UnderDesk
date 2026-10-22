extends "res://src/bossmaker/visuals/rbm_samurai_action.gd"
func _init() -> void:
	kind="all";duration=1.36;release_time=0.52;impact_time=0.57;retreat_time=0.95
	poses=[[0,0],[0.07,1],[0.16,2],[0.22,3],[0.31,2],[0.38,8],[0.52,9],[0.66,10],[0.86,11],[0.95,12],[1.04,13],[1.25,14],[1.31,15]]
	cues=[[0.19,"wind_move",-13],[release_time,"wind_swing",-4],[impact_time,"wind_impact_heavy",-7]]
