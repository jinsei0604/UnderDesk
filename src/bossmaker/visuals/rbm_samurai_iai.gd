extends "res://src/bossmaker/visuals/rbm_samurai_action.gd"
func _init() -> void:
	kind="iai";duration=1.12;release_time=0.52;impact_time=0.72
	poses=[[0,0],[0.12,11],[0.29,16],[0.48,17],[0.68,18]]
	cues=[[0.30,"wind_cast",-15],[impact_time,"buff_atk",-10]]
