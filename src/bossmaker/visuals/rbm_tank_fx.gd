extends RefCounted
const EDGE=Color("403e38")
const METAL=Color("b7bbc2")
const LIGHT=Color("fff2d4")
const GUARD=Color("ccb779")
static func shield(c: CanvasItem,p: Vector2,r: float,alpha: float) -> void:
	var points:=PackedVector2Array([p+Vector2(-r,-r),p+Vector2(r,-r),p+Vector2(r,r*0.3),p+Vector2(0,r),p+Vector2(-r,r*0.3),p+Vector2(-r,-r)])
	c.draw_colored_polygon(points,Color(EDGE,alpha*0.33));c.draw_polyline(points,Color(GUARD,alpha),2,false)
	c.draw_line(p+Vector2(0,-r*.65),p+Vector2(0,r*.5),Color(LIGHT,alpha),2,false)
static func plate(c: CanvasItem,p: Vector2,r: float,alpha: float) -> void:
	c.draw_rect(Rect2((p-Vector2(r,r*.65)).round(),Vector2(r*2,r*1.3)),Color(EDGE,alpha*.5))
	c.draw_rect(Rect2((p-Vector2(r,r*.65)).round(),Vector2(r*2,r*1.3)),Color(METAL,alpha),false,2)
	c.draw_line(p+Vector2(-r,r*.85),p+Vector2(r,r*.85),Color(GUARD,alpha),2,false)
static func chevron(c: CanvasItem,p: Vector2,r: float,alpha: float) -> void:
	c.draw_polyline(PackedVector2Array([p+Vector2(-r,0),p+Vector2(0,-r*.65),p+Vector2(r,0)]),Color(GUARD,alpha),3,false)
	c.draw_polyline(PackedVector2Array([p+Vector2(-r,r*.6),p+Vector2(0,0),p+Vector2(r,r*.6)]),Color(LIGHT,alpha),2,false)
static func battlement(c: CanvasItem,foot: Vector2,u: float,alpha: float) -> void:
	if u<0.001 or alpha<0.001:return
	var base:=foot+Vector2(35,3)
	for i in 3:
		var p:=base+Vector2(i*14,-i*3)
		var h:=(33.0 if i!=1 else 40.0)*u
		var bevel:=minf(5,h*.2)
		var shape:=PackedVector2Array([p+Vector2(-7,0),p+Vector2(-7,-h+bevel),p+Vector2(-3,-h),p+Vector2(5,-h),p+Vector2(7,-h+bevel*.6),p+Vector2(7,0),p+Vector2(-7,0)])
		c.draw_colored_polygon(shape,Color(Color("777b7d"),alpha*.40))
		c.draw_polyline(shape,Color(METAL,alpha),2,false)
		c.draw_line(p+Vector2(-4,-h+6),p+Vector2(-4,-4),Color(LIGHT,alpha*.8),2,false)
		c.draw_rect(Rect2((p+Vector2(1,-h+9)).round(),Vector2(2,2)),Color(GUARD,alpha))
	c.draw_line(base+Vector2(-9,3),base+Vector2(37,-4),Color(GUARD,alpha*.9),3,false)
static func strike(c: CanvasItem,t: float,hit: float,head: Vector2,target: Vector2,heavy: bool) -> void:
	var e:=t-hit
	if e>=-0.04 and e<0.05:
		# A short, blunt head wake, not a sword crescent or elemental slash.
		var direction:=Vector2(-24,-43) if heavy else Vector2(-46,4)
		c.draw_line(head+direction,head,Color(METAL,.55),8 if heavy else 5,false)
		c.draw_line(head+direction*.6,head,Color(LIGHT,.8),2,false)
	if e<0 or e>0.35:return
	var a:=1-smoothstep(0.08,0.35,e)
	var r:=lerpf(5,28 if heavy else 18,smoothstep(0,0.10,e))
	for i in 7:
		var angle:=i*TAU/7+0.2
		var v:=Vector2(cos(angle),sin(angle))
		c.draw_line((target+v*r*.45).round(),(target+v*r).round(),Color(METAL,a),4 if heavy else 2,false)
	if e<0.065:c.draw_rect(Rect2((target-Vector2(4,4)).round(),Vector2(8,8)),Color(LIGHT,a))
	if not heavy:return
	# Low dust and pressure at the physical hammer contact; no finisher fissure.
	for i in 10:
		var x:=(float(i)-4.5)*7
		var p:=target+Vector2(x*(1+e*2),-sin(e*PI/.35)*(8+float(i%3)*4)+5)
		c.draw_rect(Rect2(p.round(),Vector2(5+i%3*2,3+i%2*2)),Color(Color("897b66") if i%2 else Color("b4aa96"),a*.65))
	var u:=smoothstep(0,.25,e)
	c.draw_polyline(PackedVector2Array([target+Vector2(-42*u,5),target+Vector2(0,12*u),target+Vector2(42*u,5)]),Color(METAL,a*.7),2,false)
static func support(c: CanvasItem,t: float,hit: float,kind: String,foot: Vector2,targets: Array[Vector2]) -> void:
	var e:=t-hit
	if e<-.16 or e>.42:return
	var u:=smoothstep(-.16,.06,e)
	var a:=u*(1-smoothstep(.18,.42,e))
	if kind=="cover":
		shield(c,foot+Vector2(34,-47),24,a)
		for p in targets:shield(c,p+Vector2(33,-47),15,a*.7)
	elif kind=="boost":
		for p in targets:
			chevron(c,p+Vector2(35,-36-u*15),14,a)
			c.draw_line(p+Vector2(-18,2),p+Vector2(18,2),Color(GUARD,a*.7),2,false)
	else:
		for p in targets:battlement(c,p,u,a)
