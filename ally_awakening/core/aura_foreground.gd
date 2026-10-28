extends "res://ally_awakening/core/ink.gd"
## A small foreground arc and motes establish depth; torso and face stay clear.
func _draw() -> void:
	if strength<=0:return
	ring(Vector2(0,-1),Vector2(35,10),tint(color,.40),2,0,PI)
	for i in 4:
		var q:=fposmod(age*.36+i*.27,1)
		var p:=Vector2(sin(i*5.7+age*.3)*48,-q*32)
		draw_rect(Rect2(p.snapped(Vector2(2,2)),Vector2(2,2)),tint(color,sin(q*PI)*.60))
