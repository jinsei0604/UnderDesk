extends "res://src/bossmaker/visuals/rbm_dragon_vfx.gd"
func _draw() -> void:
	if age<.58 or age>4.9: return
	var opacity=smoothstep(.58,1.05,age)*(1-smoothstep(4.15,4.9,age))
	for row in range(14):
		draw_rect(Rect2(0,row*23,1280,23),Color(.023,.006,.020,opacity*(.84-row*.048)))
	var center=Vector2(393,140)
	for layer in range(5):
		var points=PackedVector2Array()
		for i in range(39):
			var q=i/38.0
			var a=q*TAU*.82+age*(.9+layer*.09)+layer*1.7
			var radius=80+layer*34+q*28
			points.append((center+Vector2(cos(a)*radius,sin(a)*radius*.28)).snapped(Vector2(4,4)))
		draw_polyline(points,Color(.25+layer*.025,.013,.041,opacity*.86),8,false)
	for i in range(58):
		var q=fposmod((age-.58)*.65+i*.137,1)
		var p=Vector2(160+i%13*37+sin(i*7.1)*20,105+q*260)
		draw_rect(Rect2(p.snapped(Vector2(3,3)),Vector2(3,5)),Color(.83,.025,.058,sin(q*PI)*opacity*.74))
