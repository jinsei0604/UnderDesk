extends "res://src/bossmaker/visuals/rbm_samurai_action.gd"
func _init() -> void:
	kind="counter";duration=1.08;release_time=0.38;impact_time=0.61
	poses=[[0,0],[0.12,1],[0.30,6],[0.48,19]]
	cues=[[0.32,"wind_move",-15],[impact_time,"guard_set",-8]]
