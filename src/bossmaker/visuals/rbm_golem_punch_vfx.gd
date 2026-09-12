extends Node2D
## Approved golem-only pressure wave; no actor textures or simulation state.
var contact := Vector2.ZERO
var impact_color := Color.WHITE
var age := -1.0
func _draw() -> void:
	if age < 0.0: return
	if age < .30: _shockwave(age)
	if age < .52: _impact(age)
func _shockwave(t: float) -> void:
	var expansion:=1.0-pow(1.0-clampf(t/.23,0,1),2.0)
	var radius:=22.0+80.0*expansion
	var alpha:=smoothstep(0,.025,t)*(1.0-smoothstep(.13,.29,t))
	# Broken pressure front: a clear center, uneven edge and no glyphs.
	for y in range(-96,97,4):
		for x in range(-112,113,4):
			var p:=Vector2(x,float(y)/.82)
			var angle:=atan2(p.y,p.x)
			var edge:=radius+sin(angle*7.0+.7)*3.0+sin(angle*13.0)*2.0
			var dist:=p.length()
			var width:=15.0+5.0*sin(angle*3.0+1.0)
			var broken:=sin(angle*11.0+1.3)
			if broken>.91 or dist>edge or dist<edge-width: continue
			var color:=impact_color
			if dist<edge-width+5.0: color=color.lightened(.55)
			color.a=alpha*(.95 if x<18 else .60)
			draw_rect(Rect2(contact+Vector2(x,y),Vector2(4,4)),color)

func _impact(t: float) -> void:
	# Five short unequal impact strokes, not a flash or radial explosion.
	if t<.12:
		for spec in [Vector3(-22,-24,9),Vector3(8,-30,7),Vector3(-27,9,12),Vector3(15,20,6),Vector3(-5,31,8)]:
			var axis:=Vector2(spec.x,spec.y).normalized()
			var p: Vector2=(contact+Vector2(spec.x,spec.y)).snapped(Vector2(2,2))
			for i in range(int(spec.z/2.0)):
					var accent:=impact_color.lightened(.22)
					accent.a=1.0-t/.12
					draw_rect(Rect2((p+axis*i*2).snapped(Vector2(2,2)),Vector2(2,2)),accent)
	# Two medium chips and six small stones, with unequal gravity arcs.
	for i in range(8):
		var velocities: Array[Vector2]=[Vector2(-63,-80),Vector2(35,-62),Vector2(-92,-35),Vector2(-42,-103),Vector2(52,-30),Vector2(-17,-75),Vector2(11,-110),Vector2(-70,4)]
		var p: Vector2=(contact+velocities[i]*t+Vector2(0,210*t*t)).snapped(Vector2(2,2))
		var side:=6 if i<2 else 2
		var tint:=Color(0.49,0.45,0.52,1.0-smoothstep(.30,.52,t))
		draw_rect(Rect2(p,Vector2(side,side-2 if i<2 else 2)),tint)
		if i<2: draw_rect(Rect2(p+Vector2(2,-2),Vector2(4,4)),tint.lightened(.18))
	# A brief torn dust patch, kept below the fist; no circular puffs.
	var fade: float=smoothstep(0.0,.06,t)*(1.0-smoothstep(.17,.44,t))*.24
	for i in range(9):
		var p: Vector2=(contact+Vector2(-12+(i%4)*7-t*18,10+(i/4)*6+t*14)).snapped(Vector2(2,2))
		draw_rect(Rect2(p,Vector2(8 if i%2 else 6,4)),Color(.62,.58,.51,fade))

