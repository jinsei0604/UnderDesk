extends RefCounted
## V4 native integer polygons: spatial wounds, unknown mass, cloth-pressure release.
## All positions are snapped on the final grid. No antialiasing, blur or RNG.
const INK=Color("050409")
const PURPLE=Color("593965")
const LILAC=Color("a385b0")
const IVORY=Color("dfd5cb")

static func poly(ci: CanvasItem, points: Array, color: Color) -> void:
	var p:=PackedVector2Array()
	for v in points:p.append(Vector2(v).round())
	if Geometry2D.triangulate_polygon(p).size()>0:ci.draw_colored_polygon(p,color)

static func mass(ci: CanvasItem,c: Vector2,rx: float,ry: float,time: float,color: Color) -> void:
	if rx<2 or ry<2:return
	var p: Array=[]
	for i in range(40):
		var a:=float(i)*TAU/40
		var lobe:=1+.10*sin(float(i)*1.8+floor(time*12)*.3)+.06*cos(float(i)*2.3)
		p.append(c+Vector2(cos(a)*rx,sin(a)*ry)*lobe)
	poly(ci,p,color)

static func pressure(ci: CanvasItem,c: Vector2,r: float,width: float,flat: float,color: Color) -> void:
	if width<1:return
	for i in range(64):
		var a:=i*TAU/64.0;var b:=(i+1)*TAU/64.0
		var ja:=1+.014*sin(a*7)+.009*cos(a*13)
		var jb:=1+.014*sin(b*7)+.009*cos(b*13)
		var da:=Vector2(cos(a),sin(a)*flat);var db:=Vector2(cos(b),sin(b)*flat)
		poly(ci,[c+da*r*ja,c+db*r*jb,c+db*(r-width)*jb,c+da*(r-width)*ja],color)

static func awakening_back(ci: CanvasItem,t: float,home: Vector2) -> void:
	var build:=smoothstep(.5,3.9,t)*(1-smoothstep(4.9,6.5,t))
	ci.draw_rect(Rect2(-80,-80,1440,880),Color(.018,.009,.028,build*.6))
	var center:=home+Vector2(0,-90)
	# V5 uses a continuous native smoke mantle behind the body.
	if t>1.3 and t<4.9:
		var q:=smoothstep(1.3,4.6,t)
		pressure(ci,home+Vector2(0,2),260-140*q,16+12*q,.27,Color(.25,.13,.31,build*.8))
	var u:=t-4.9
	if u>=0 and u<1.65:
		for i in range(3):
			var dt:=u-i*.13
			if dt<0 or dt>1.2:continue
			var q:=dt/1.2
			pressure(ci,home,65+pow(q,.68)*1200,38*(1-q)+6,.32,Color(.40,.22,.47,(1-q)*.9))

static func awakening_front(ci: CanvasItem,t: float,home: Vector2,stage: Control) -> void:
	# Six stitches/cloth plugs break in a clear sequence, following the body.
	var seams: Array=[Vector2(-34,-116),Vector2(31,-119),Vector2(-30,-76),Vector2(39,-71),Vector2(-17,-37),Vector2(20,-36)]
	for i in range(6):
		var u:=t-(1.25+i*.22)
		if u<0 or u>.55:continue
		var dir:=Vector2(-1 if i%2==0 else 1,-.3)
		var c: Vector2=home+seams[i]+dir*(8+u*52)
		poly(ci,[c+Vector2(-3,-3),c+Vector2(5,-2),c+Vector2(3,4),c+Vector2(-4,3)],Color(.78,.67,.51,1-u/.55))
	if t>=2.85 and t<3.65:
		var u:=t-2.85
		for i in range(6):
			var a:=i*TAU/6.0
			stage.fx(ci,"cotton",i,home+Vector2(cos(a)*(36+u*90),-90+sin(a)*(24+u*65)),1-u/.8)
	var dt:=t-4.9
	if dt<0 or dt>1.8:return
	# Release fills the battlefield, while the character stays visible in the center.
	for i in range(18):
		var a:=i*2.399;var q:=clampf(dt/(.85+float(i%4)*.18),0,1)
		if q>=1:continue
		var direction:=Vector2(cos(a),sin(a)*.65)
		var c:=home+Vector2(0,-85)+direction*(85+pow(q,.72)*(420+i%4*95))
		if i%3==0:stage.fx(ci,"cotton",i,c,(1-q)*.85)
		else:
			var side:=Vector2(-direction.y,direction.x)
			var w:=7.0+float(i%4)*3
			poly(ci,[c-direction*19,c+side*w,c+direction*11,c-side*w*.6],Color(.46,.31,.27,(1-q)*.85))
	for i in range(2):
		var u:=dt-i*.12
		if u>=0 and u<.9:
			var q:=u/.9
			pressure(ci,home+Vector2(0,-85),100+q*960,28*(1-q)+4,.75,Color(.38,.22,.44,(1-q)*.7))

static func gash(ci: CanvasItem,c: Vector2,length: float,width: float,alpha: float) -> void:
	if width<1 or alpha<=0:return
	var axis:=Vector2(-.54,.84);var side:=Vector2(.84,.54)
	var left: Array=[];var right: Array=[]
	var rim: Array=[];var core: Array=[]
	for j in range(9):
		var f:=j/8.0;var taper:=pow(maxf(0,sin(f*PI)),.65)
		var bite:=([0,2,-1,3,-2,2,-1,1,0][j]) as float
		var p:=c+axis*(f-.5)*length
		left.append(p-side*(width*taper+bite));right.push_front(p+side*width*taper)
		core.append(p-side*maxf(0,width*taper-4));rim.push_front(p-side*maxf(0,width*taper-1))
	poly(ci,left+right,Color(LILAC,alpha))
	var inner: Array=[];var other: Array=[]
	for j in range(9):
		var f:=j/8.0;var w:=maxf(0,width*pow(maxf(0,sin(f*PI)),.65)-3)
		var p:=c+axis*(f-.5)*length
		inner.append(p-side*w);other.push_front(p+side*w)
	poly(ci,inner+other,Color(INK,alpha))
	poly(ci,core+rim,Color(IVORY,alpha*.8))

static func unknown_front(ci: CanvasItem,t: float,home: Vector2) -> void:
	if t<.9 or t>=2.2:return
	var p:=smoothstep(.9,1.95,t)
	var c:=home+Vector2(-4,-81)
	# No eyes, teeth, limbs or recognisable anatomy: only a heavy emerging surface.
	mass(ci,c+Vector2(-42*p,-10*p),8+100*p,10+55*p,t,Color("302235"))
	mass(ci,c+Vector2(-46*p,-9*p),6+94*p,8+51*p,t,INK)
	if p>.25:
		poly(ci,[c+Vector2(-28*p,-35*p),c+Vector2(-70*p,-45*p),c+Vector2(-123*p,-24*p),c+Vector2(-74*p,-33*p)],Color("211927"))

static func blackout_alpha(t: float) -> float:
	return smoothstep(1.72,2.10,t)*(1-smoothstep(3.55,4.25,t))

static func screen(ci: CanvasItem,t: float,stage: Control) -> void:
	if t<1.45 or t>4.65:return
	var alpha:=blackout_alpha(t)
	# The expanding, asymmetrical veil is seen for a moment before total darkness.
	if t<2.10:
		var q:=pow(clampf((t-1.45)/.65,0,1),2)
		mass(ci,stage.home+Vector2(-38-270*q,-84),45+1450*q,30+900*q,t,Color(INK,minf(1,q*3)))
	ci.draw_rect(Rect2(-8,-8,1296,736),Color(0,0,0,alpha))
	var n:=0
	for id in stage.HOMES:
		var u:=t-2.35-n*.12
		if u>=0 and u<.60:
			var foot: Vector2=stage.HOMES[id]
			var grow:=smoothstep(0,.05,u);var fade:=1-smoothstep(.16,.60,u)
			# Only the wounds and blows are visible inside the dark, never their source.
			gash(ci,foot+Vector2(-8,-56),146*grow,(13+8*sin(minf(u/.16,1)*PI))*grow,fade)
			stage.fx(ci,"impact",clampi(int(u*20),0,8),foot+Vector2(3,-45),fade)
			if u<.23:
				for k in range(5):
					var d:=Vector2.from_angle(k*TAU/5+.35)
					var side:=Vector2(-d.y,d.x)
					var center:=foot+Vector2(1,-49)
					poly(ci,[center+d*7-side*5,center+d*(26+u*95),center+d*8+side*8],Color(.76,.66,.79,(1-u/.23)*.9))
			for j in range(4):
				var p:=foot+Vector2(-8,-48)+Vector2.from_angle(j*1.7+float(n))*(10+u*95)
				poly(ci,[p+Vector2(-3,-2),p+Vector2(3,-3),p+Vector2(2,4),p+Vector2(-2,3)],Color(.53,.40,.57,fade))
		n+=1
