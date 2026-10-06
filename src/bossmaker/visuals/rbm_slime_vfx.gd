extends Node2D
## Approved texture deformation and fluid accents, separate from combat playback.
const Motion=preload("res://src/bossmaker/visuals/rbm_slime_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const Support=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
const SUPPORT=Support.COLORS
var motion: RefCounted
var kind:="single"
var age:=-1.0
var state: Dictionary={}
var attack_attribute:="NEUTRAL"
var slime: Texture2D
var pixel_scale:=.75
var feet: Array[Vector2]=[]
var particles: Array=[]

func prepare_particles() -> void:
	particles.clear()
	if feet.is_empty(): return
	var rng=RandomNumberGenerator.new()
	rng.seed=7613
	for i in range(76):
		var lane=i%feet.size()
		var target=feet[lane]+Vector2(rng.randf_range(-45,38),rng.randf_range(-95,-22))
		particles.append({"target":target,"delay":rng.randf_range(0,.14),"life":rng.randf_range(.41,.61),"radius":rng.randf_range(4,11),"arc":rng.randf_range(-55,22),"lane":lane})

func snap(p: Vector2) -> Vector2:
	return (p/4).round()*4
func poly(points: Array,c: Color) -> void:
	var out=PackedVector2Array()
	for p in points:
		var at=snap(p)
		if not out.has(at): out.append(at)
	if out.size()<3: return
	var area=0.0
	for i in range(out.size()): area+=out[i].cross(out[(i+1)%out.size()])
	if absf(area)<8: return
	draw_colored_polygon(out,c)
func blob(pos: Vector2,r: Vector2,c: Color) -> void:
	var pts=[]
	for i in range(12):
		var a=i*TAU/12
		pts.append(pos+Vector2(cos(a)*r.x,sin(a)*r.y))
	poly(pts,c)
func line(a: Vector2,b: Vector2,c: Color,w: float) -> void:
	draw_line(snap(a),snap(b),c,w,false)


func advance(t: float) -> void:
	age=t
	state=motion.sample(kind,t)
	queue_redraw()

func _draw() -> void:
	if state.is_empty() or age<0: return
	blob(motion.home+Vector2(0,1),Vector2(101*state.scale.x,12),Color(.07,.03,.06,.3))
	if kind in SUPPORT: support_back()
	if kind=="single" and state.arm>.001: arm()
	body()
	if kind=="aoe": splash()
	if kind=="single": impact(motion.contact,age-.91,.36,Palette.color_for(attack_attribute),1.0)
	if kind in SUPPORT: support_front()

func body() -> void:
	var sc=state.scale*pixel_scale
	# Deform the existing texture in strips: no new face, palette, or design.
	for y in range(0,200,4):
		var wob=0.0
		if kind=="single" and state.ripple>0:
			wob=sin(float(y)*.065-age*21)*state.ripple*.42
		var pos=motion.home+state.offset+Vector2((-140)*sc.x+wob,(float(y)-196)*sc.y)
		var bottom=roundf(pos.y+4*sc.y)
		draw_texture_rect_region(slime,Rect2(pos.round(),Vector2(roundf(284*sc.x),bottom-roundf(pos.y))),Rect2(116,264+y,284,4))

func arm() -> void:
	var start=motion.home+Vector2(-44,-55)+state.offset
	var tip=start.lerp(motion.contact,float(state.arm))
	var length=start.distance_to(tip)
	if length<7: return
	var upper=[]
	var lower=[]
	var centers=[]
	for i in range(25):
		var q=float(i)/24
		var p=start.lerp(tip,q)
		p.y+=sin(q*PI*3-age*22)*state.ripple*sin(q*PI)
		var thick=lerpf(28,16,q)+sin(q*PI)*4
		upper.append(p+Vector2(0,-thick))
		lower.push_front(p+Vector2(0,thick))
		centers.append(p)
	poly(upper+lower,Color("732434"))
	var up=[]
	var down=[]
	for i in range(25):
		var q=float(i)/24
		var p=centers[i]
		var thick=lerpf(21,11,q)
		up.append(p+Vector2(0,-thick))
		down.push_front(p+Vector2(0,thick))
	poly(up+down,Color("c33e47"))
	for i in range(23): line(centers[i]+Vector2(0,-12),centers[i+1]+Vector2(0,-12),Color("ef6055"),8)
	var rad=Vector2(34-19*state.crush,25+20*state.crush)
	blob(tip+Vector2(11,0),rad+Vector2(4,4),Color("792333"))
	blob(tip+Vector2(11,-2),rad,Color("cd424b"))
	blob(tip+Vector2(12,-10),rad*Vector2(.74,.43),Color("f6755d"))
	if state.crush>.1:
		line(tip+Vector2(-4,-22),tip+Vector2(-4,20),Color("ff9a70"),4)

func impact(pos: Vector2,t: float,life: float,c: Color,magnitude: float) -> void:
	if t<0 or t>life: return
	var q=t/life
	var col=c
	col.a=1-smoothstep(.35,1,q)
	for i in range(10):
		var a=float(i)*TAU/10
		var dir=Vector2(cos(a),sin(a))
		var r=(16+q*55)*magnitude
		line(pos+dir*r,pos+dir*(r+18*(1-q)*magnitude),col,4 if q>.5 else 8)
	if q<.3:
		var pts=[]
		for i in range(16):
			var a=i*TAU/16
			pts.append(pos+Vector2(cos(a),sin(a))*(34 if i%2==0 else 13)*magnitude)
		poly(pts,c.lightened(.35))

func splash() -> void:
	var t=age-Motion.BURST
	if t<0 or t>1.10: return
	var source=motion.home+Vector2(-20,-53)
	for i in range(particles.size()):
		var p=particles[i]
		var q=(t-p.delay)/p.life
		if q<0: continue
		if q<1:
			var at=source.lerp(p.target,q)+Vector2(0,sin(q*PI)*p.arc)
			var dir=source.direction_to(p.target)
			var r=p.radius
			# Colored accents follow the fluid; the slime itself stays red.
			line(at-dir*(12+20*q),at+dir*4,Palette.color_for(attack_attribute).darkened(.25),maxf(4,r))
			blob(at,Vector2(r*1.4,r),Color("8e293c"))
			blob(at+Vector2(-2,-2),Vector2(r,r*.75),Color("e55153"))
			if i%3==0: blob(at+Vector2(-2,-4),Vector2(r*.6,3),Color("ff9a70"))
		else:
			var h=(q-1)*p.life
			if h<.26:
				for j in range(3):
					var dir=Vector2(-1.0+j,-1.5+absf(j-1)*.4)
					var at=p.target+dir*h*100+Vector2(0,h*h*230)
					var col=Color("e55153")
					col.a=1-h/.26
					blob(at,Vector2(4,4)*(1-h/.32),col)
	for i in range(feet.size()): impact(feet[i]+Vector2(0,-52),age-(1.38+i*.016),.34,Palette.color_for(attack_attribute),.67)
	# Close-range ejection spikes, visible only at the burst.
	if t<.15:
		for i in range(9):
			var a=PI*.64+i*PI*.085
			var dir=Vector2(cos(a),sin(a))
			line(source+dir*40,source+dir*(70+t*120),Color("e55153"),12)

func support_back() -> void:
	if age<.2 or age>2.85: return
	var c=SUPPORT[kind]
	var center=motion.home+Vector2(0,-62)
	if age<1.28:
		for i in range(22):
			var q=clampf((age-.20-float(i%5)*.06)/.85,0,1)
			if q<=0 or q>=1: continue
			var a=i*2.399+q*.32
			var dir=Vector2(cos(a),sin(a)*.75)
			var p=center+dir*lerpf(158,3,q)
			line(p+dir*12,p,c.darkened(.2),4)
			blob(p,Vector2(4,4),c.lightened(.25))
	if age>1.12 and age<2.35:
		var q=(age-1.12)/1.23
		var col=c
		col.a=(1-q)*.8
		for i in range(24):
			var a=i*TAU/24
			var b=a+.10
			var r=75+q*80
			line(motion.home+Vector2(cos(a)*r,sin(a)*r*.22),motion.home+Vector2(cos(b)*r,sin(b)*r*.22),col,4)

func support_front() -> void:
	if age<.35 or age>2.65: return
	var c=SUPPORT[kind]
	var center=motion.home+Vector2(0,-64*state.scale.y)
	if age<1.52:
		var q=smoothstep(.35,1.12,age)*(1-smoothstep(1.20,1.52,age))
		var rad=6+q*13
		var col=c
		col.a=q*.85
		blob(center,Vector2(rad,rad),col)
		line(center-Vector2(rad+7,0),center+Vector2(rad+7,0),col,4)
		line(center-Vector2(0,rad+7),center+Vector2(0,rad+7),col,4)
	if age>=1.5:
		for i in range(14):
			var q=(age-1.5)/1.15
			var a=i*2.399
			var p=center+Vector2(cos(a)*(65+q*36),sin(a)*(65+q*36)-q*20)
			var col=c
			col.a=1-q
			line(p-Vector2(5,0),p+Vector2(5,0),col,4)
			line(p-Vector2(0,5),p+Vector2(0,5),col,4)
