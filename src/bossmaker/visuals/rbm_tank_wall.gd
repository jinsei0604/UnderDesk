extends "res://src/bossmaker/visuals/rbm_tank_action.gd"
func _init() -> void:
	kind="wall";duration=1.38;release_time=.48;impact_time=.68;retreat_time=1.04
	poses=[[0,0],[.08,1],[.23,16],[.40,13],[.57,19],[1.02,13],[1.20,1]]
	cues=[[.68,"guard_hit",-3],[.77,"guard_set",-6]]
