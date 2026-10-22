extends "res://src/bossmaker/visuals/rbm_tank_action.gd"
func _init() -> void:
	kind="boost";duration=1.20;release_time=.45;impact_time=.62;retreat_time=.89
	poses=[[0,0],[.07,1],[.20,16],[.39,19],[.53,18],[.85,19],[1.02,1]]
	cues=[[.38,"guard_hit",-10],[.62,"guard_set",-3]]
