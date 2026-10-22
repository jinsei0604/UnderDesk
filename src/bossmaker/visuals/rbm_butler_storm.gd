extends "res://src/bossmaker/visuals/rbm_butler_action.gd"
func _init() -> void:
	kind="storm";duration=1.40;release_time=0.56;impact_time=0.82
	poses=[[0,-1],[0.08,-2],[0.18,1],[0.29,5],[0.43,3],[0.56,11],[0.72,10],[1.00,2],[1.16,1],[1.28,-2],[1.35,-1]]
	cues=[[0.24,"ice_cast",-4],[release_time,"ice_move",-9],[impact_time,"ice_impact_heavy",-2]]
func _draw_effect() -> void:
	FX.storm(self,age,release_time,impact_time,_watch_position(),_launch,_target)
