extends Node2D
## Small snapped geometry vocabulary. No screen texture reads, RNG or simulation.
var age := 0.0
var color := Color.WHITE
var strength := 1.0
func line(points: PackedVector2Array, c: Color, width: float = 2.0) -> void:
	if c.a < 0.005 or points.size()<2: return
	for i in points.size(): points[i]=points[i].snapped(Vector2(2,2))
	draw_polyline(points,c,width,false)
func poly(points: PackedVector2Array,c: Color) -> void:
	if c.a<0.005:return
	for i in points.size():points[i]=points[i].snapped(Vector2(2,2))
	# Tiny fading geometry can collapse on the 2px grid; do not submit invalid polygons.
	if Geometry2D.triangulate_polygon(points).is_empty():return
	draw_colored_polygon(points,c)
func tint(c: Color,a: float) -> Color:
	return Color(c,clampf(a*strength,0,1))
func ring(p: Vector2,r: Vector2,c: Color,w: float=2.0,start: float=0.0,arc: float=TAU) -> void:
	if r.x<1 or r.y<1 or c.a<0.005:return
	var pts:=PackedVector2Array()
	for i in 65:
		var a:=start+arc*i/64.0
		pts.append(p+Vector2(cos(a)*r.x,sin(a)*r.y))
	line(pts,c,w)
func ray(p: Vector2,d: Vector2,length: float,width: float,c: Color) -> void:
	var side:=Vector2(-d.y,d.x)*width
	poly(PackedVector2Array([p-side,p+d*length,p+side]),c)
func star(p: Vector2,r: float,c: Color) -> void:
	poly(PackedVector2Array([p+Vector2(-r,0),p+Vector2(-2,-2),p+Vector2(0,-r*1.8),p+Vector2(2,-2),p+Vector2(r,0),p+Vector2(2,2),p+Vector2(0,r*1.8),p+Vector2(-2,2)]),c)
func diamond(p: Vector2,w: float,h: float,c: Color) -> void:
	poly(PackedVector2Array([p+Vector2(0,-h),p+Vector2(w,0),p+Vector2(0,h),p+Vector2(-w,0)]),c)
func flame(p: Vector2,w: float,h: float,phase: float,c: Color) -> void:
	var sway:=sin(phase)*w*.55
	poly(PackedVector2Array([p+Vector2(-w,0),p+Vector2(-w*.85,-h*.32),p+Vector2(-w*.45,-h*.62),p+Vector2(sway,-h),p+Vector2(w*.26+sway,-h*.52),p+Vector2(w*.9,-h*.25),p+Vector2(w,0)]),c)
func bolt(a: Vector2,b: Vector2,seed: int,c: Color,w: float=2.0) -> void:
	var points:=PackedVector2Array([a])
	var side:=(b-a).orthogonal().normalized()
	for j in range(1,7):points.append(a.lerp(b,j/7.0)+side*sin(seed*8.1+j*13.3)*12)
	points.append(b)
	line(points,c,w)
