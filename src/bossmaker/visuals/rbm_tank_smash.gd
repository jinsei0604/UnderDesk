extends "res://src/bossmaker/visuals/rbm_tank_action.gd"
func _init() -> void:
	kind="smash";duration=1.34;release_time=.47;impact_time=.59;retreat_time=.84
	poses=[[0,0],[.05,1],[.10,2],[.21,3],[.31,8],[.39,9],[.50,10],[.59,11],[.65,12],[.76,11],[.84,13],[.91,14],[1.04,15],[1.16,14],[1.25,1]]
	cues=[[.46,"neutral_blunt_swing",0],[.59,"neutral_impact_heavy",-1]]
