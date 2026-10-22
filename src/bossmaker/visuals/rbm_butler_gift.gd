extends "res://src/bossmaker/visuals/rbm_butler_action.gd"
func _init() -> void:
	kind="gift";duration=1.30;release_time=0.49;impact_time=0.86
	poses=[[0,-1],[0.07,-2],[0.19,12],[0.32,13],[0.49,14],[0.89,15],[1.11,-2],[1.24,-1]]
	cues=[[0.25,"neutral_staff_tap",-9],[impact_time,"heal_sp",-1]]
func _draw_effect() -> void:
	FX.gift(self,age,release_time,impact_time,_watch_position(),_launch,_target,_recovered_amount)
