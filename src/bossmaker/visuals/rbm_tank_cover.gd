extends "res://src/bossmaker/visuals/rbm_tank_action.gd"
func _init() -> void:
	kind="cover";duration=1.22;release_time=.46;impact_time=.53;retreat_time=.78
	poses=[[0,0],[.06,1],[.12,2],[.25,3],[.38,16],[.50,17],[.70,16],[.81,14],[.95,15],[1.09,1]]
	cues=[[.10,"cover_move",-4],[.53,"guard_set",-3]]
