extends "res://src/bossmaker/visuals/rbm_healer_action.gd"
func _init() -> void:
	kind="sp";duration=1.48;release_time=0.61;impact_time=0.97
	poses=[[0,-1],[0.08,0],[0.18,4],[0.28,5],[0.40,8],[0.51,9],[0.61,10],[1.08,9],[1.18,8],[1.28,11],[1.37,0],[1.43,-1]]
	cues=[[release_time,"neutral_staff_tap",-12],[impact_time,"heal_sp",-5]]
func _draw_effect() -> void:
	FX.sp(self,age,release_time,impact_time,_wand_position(),_launch,_recipients)
