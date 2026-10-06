extends Node2D
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const Support=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const SUPPORT=Support.COLORS
var kind:="breath"
var age:=-1.0
var attack_attribute:="NEUTRAL"
var motion: RefCounted
var body: Node2D
var feet: Array[Vector2]=[]
var hits: Array[Vector2]=[]
var meteors: Array=[]

func prepare() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	meteors.clear()
	for i in range(16):
		if hits.is_empty(): break
		var target=hits[i%hits.size()]+Vector2(sin(i*7.3)*24,cos(i*4.1)*10)
		var arrival=1.65+floorf(i/4.0)*.18+float(i%4)*.035
		meteors.append({"target":target,"arrival":arrival,"radius":20.0+float(i%3)*5})

func advance(t: float) -> void:
	age=t
	queue_redraw()

func poly(points: Array,c: Color) -> void:
	var p=PackedVector2Array()
	for v in points:
		var point=(Vector2(v)/4).round()*4
		if not p.has(point): p.append(point)
	if p.size()<3: return
	var area=0.0
	for i in range(p.size()): area+=p[i].cross(p[(i+1)%p.size()])
	# Pixel snapping can collapse thin fading ribbons; omit subpixel remnants.
	if absf(area)>=8 and not Geometry2D.triangulate_polygon(p).is_empty(): draw_colored_polygon(p,c)
func line(a: Vector2,b: Vector2,c: Color,width: float=4) -> void:
	draw_line((a/4).round()*4,(b/4).round()*4,c,width,false)
func disc(p: Vector2,r: Vector2,c: Color) -> void:
	var points=[]
	for i in range(12): points.append(p+Vector2(cos(i*TAU/12)*r.x,sin(i*TAU/12)*r.y))
	poly(points,c)
func ring(p: Vector2,r: Vector2,c: Color,width: float=4) -> void:
	for i in range(20):
		var a=i*TAU/20
		var b=(i+1)*TAU/20
		line(p+Vector2(cos(a)*r.x,sin(a)*r.y),p+Vector2(cos(b)*r.x,sin(b)*r.y),c,width)

func _draw() -> void:
	if age<0 or not is_instance_valid(body): return
	var c: Color=Palette.color_for(attack_attribute)
	if kind in ["breath","focused_breath"]: breath(c)
	elif kind=="meteors": meteor_rain(c)
	elif kind in SUPPORT: roar(SUPPORT[kind])

func charge(c: Color,start: float,end: float) -> void:
	if age<start or age>end: return
	var q=(age-start)/(end-start)
	var mouth: Vector2=body.mouth_point()
	for i in range(12):
		var a=i*2.399+age*2
		var r=66*(1-q)+10
		var p=mouth+Vector2(cos(a),sin(a))*r
		line(p,p+(mouth-p).normalized()*9,c,4)
	disc(mouth,Vector2.ONE*(4+12*q),c)
	disc(mouth,Vector2.ONE*(2+5*q),c.lightened(.65))

func breath(c: Color) -> void:
	var focused=kind=="focused_breath"
	charge(c,.18,.76)
	var t=age-.68
	if t<0 or t>1.28: return
	var mouth: Vector2=body.mouth_point()
	var aim=motion.contact
	if not focused and not hits.is_empty():
		aim=Vector2.ZERO
		for hit in hits: aim+=hit
		aim/=hits.size()
	var dir=mouth.direction_to(aim)
	var side=Vector2(-dir.y,dir.x)
	var span=mouth.distance_to(aim)+(58 if focused else 130)
	var travel=smoothstep(0,.35 if not focused else .44,t)
	var fade=1-smoothstep(.99,1.28,t)
	var width=27.0 if focused else 100.0
	# Three nested, irregular ribbons make a continuous cone from the actual mouth.
	for layer in range(3):
		var upper=[]
		var lower=[]
		var factor=[1.0,.72,.28][layer]
		for j in range(13):
			var u=j/12.0
			var center=mouth+dir*span*u*travel
			var edge=(8+width*pow(u,.8))*factor*fade
			edge*=1+sin(j*1.7-age*24)*.12
			upper.append(center+side*edge)
			lower.push_front(center-side*edge)
		var col=c.darkened(.36) if layer==0 else (c if layer==1 else c.lightened(.68))
		col.a=fade
		poly(upper+lower,col)
	for i in range(24 if focused else 40):
		var q=fposmod(t*2.8+i*.071,1)
		var tangent=sin(i*8.2)*width*q*.8
		var p=mouth+dir*(span*q*travel)+side*tangent
		var col=c.lightened(.3)
		col.a=fade
		line(p-dir*(12+q*20),p,col,4 if i%3 else 8)
	if focused:
		ring(mouth,Vector2(18,30)*(1+sin(age*30)*.08),c.lightened(.4),4)
	for hit in hits: impact(hit,age-(1.12 if focused else 1.03),c,1.18 if focused else .82)

func impact(p: Vector2,t: float,c: Color,magnitude: float) -> void:
	if t<0 or t>.42: return
	var q=t/.42
	var col=c
	col.a=1-smoothstep(.40,1,q)
	ring(p,Vector2(24+q*62,18+q*45)*magnitude,col,8 if q<.3 else 4)
	for i in range(10):
		var a=i*TAU/10
		var dir=Vector2(cos(a),sin(a))
		line(p+dir*(8+q*42)*magnitude,p+dir*(28+q*60)*magnitude,col,4)
	if t<.10: disc(p,Vector2(23,28)*(1-t/.1)*magnitude,c.lightened(.65))

func meteor_rain(c: Color) -> void:
	if age>.58 and age<1.23:
		for i in range(3):
			var q=fposmod((age-.58)*2+i*.26,1)
			var col=c
			col.a=1-q
			ring(body.mouth_point()+Vector2(0,-q*88),Vector2(14+q*48,5+q*12),col,4)
	for i in range(meteors.size()):
		var m=meteors[i]
		var t=age-m.arrival
		var target: Vector2=m.target
		if t>=-.60 and t<0:
			var q=1+t/.60
			var origin=target+Vector2(185+sin(i*5.2)*45,-470)
			var pos=origin.lerp(target,q*q)
			var dir=origin.direction_to(target)
			var side=Vector2(-dir.y,dir.x)
			poly([pos-side*m.radius*1.35,pos-dir*(110+q*90)+side*9,pos+side*m.radius*1.35],c.darkened(.25))
			poly([pos-side*m.radius*.8,pos-dir*(85+q*50),pos+side*m.radius*.8],c)
			disc(pos,Vector2.ONE*m.radius,Color("292a34"))
			disc(pos+Vector2(-4,-5),Vector2.ONE*m.radius*.72,Color("55515e"))
			line(pos-side*m.radius*.6,pos+dir*9,c.lightened(.60),4)
		elif t>=0 and t<.50:
			impact(target,t,c,1.1)
			for j in range(6):
				var dir=Vector2(sin(j*5.2+i),-absf(cos(j*3.7))-.2)
				var p=target+dir*t*180+Vector2(0,t*t*310)
				var col=c.darkened(.50)
				col.a=1-t/.50
				disc(p,Vector2.ONE*(4+(j%2)*3),col)
		if t>=0 and t<.72:
			var col=c.darkened(.65)
			col.a=.8*(1-t/.72)
			ring(target+Vector2(0,15),Vector2(34+t*28,9+t*7),col,4)

func roar(c: Color) -> void:
	var mouth: Vector2=body.mouth_point()
	var home: Vector2=body.foot_point()
	if age>=.22 and age<.9:
		var q=(age-.22)/.68
		for i in range(15):
			var a=i*2.399
			var p=home+Vector2(0,-82)+Vector2(cos(a),sin(a))*(90*(1-q)+10)
			line(p,p+(home+Vector2(0,-82)-p).normalized()*8,c,4)
	if age>=.65 and age<1.83:
		for i in range(4):
			var q=(age-.65-i*.18)/.62
			if q<0 or q>1: continue
			var col=c
			col.a=1-smoothstep(.5,1,q)
			ring(mouth+Vector2(0,-q*90),Vector2(18+q*54,6+q*12),col,4)
	if age>=.9 and age<2.15:
		var q=(age-.9)/1.25
		var col=c
		col.a=1-smoothstep(.6,1,q)
		ring(home+Vector2(0,-3),Vector2(72+q*42,15+q*8),col,4)
		for i in range(14):
			var p=home+Vector2(sin(i*5.3)*(40+q*50),-q*155-(i%4)*12)
			line(p-Vector2(0,4),p+Vector2(0,4),col,4)
			if i%3==0: line(p-Vector2(4,0),p+Vector2(4,0),col,4)
