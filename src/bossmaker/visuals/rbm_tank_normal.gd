extends "res://src/bossmaker/visuals/rbm_tank_action.gd"
func _init() -> void:
	kind="normal";duration=1.04;release_time=.35;impact_time=.44;retreat_time=.60
	poses=[[0,0],[.045,1],[.09,2],[.18,3],[.27,4],[.37,5],[.44,6],[.51,7],[.61,13],[.66,14],[.78,15],[.88,14],[.96,1]]
	cues=[[.34,"neutral_blunt_swing",-3],[.44,"neutral_impact_light",0]]
