extends "res://src/bossmaker/visuals/rbm_dragon_vfx.gd"
var screen_edge_x:=-96.0
var final_target:=Vector2(356,445)

func beam_values() -> Dictionary:
	var focused=kind=="focused_breath"
	var mouth: Vector2=body.mouth_point()
	var aim: Vector2=motion.contact
	if not focused:
		aim=Vector2.ZERO
		for hit in hits: aim+=hit
		aim/=maxi(hits.size(),1)
	var dir: Vector2=mouth.direction_to(aim)
	# Overscan covers the physical viewport edge even while the camera shakes.
	var span=(screen_edge_x-mouth.x)/minf(dir.x,-.01)
	var start=.82 if focused else .78
	var elapsed=age-start
	var travel=smoothstep(0,.10 if focused else .16,elapsed)
	var fade=1-smoothstep(2.68 if focused else 2.42,2.88 if focused else 2.62,age)
	return {"mouth":mouth,"dir":dir,"span":span,"travel":travel,"fade":fade,"elapsed":elapsed,"focused":focused}

func beam_core(c: Color) -> void:
	var b=beam_values()
	var focused: bool=b.focused
	charge(c,.18,.82 if focused else .78)
	if b.elapsed<0 or b.fade<=0: return
	var mouth: Vector2=b.mouth
	var dir: Vector2=b.dir
	var side=Vector2(-dir.y,dir.x)
	var span: float=b.span*b.travel
	# Opaque nested ribbons remain continuous from the mouth through the screen edge.
	# Only the final whole-beam fade changes visibility; the beam never retracts.
	for layer in range(4):
		var upper=[]
		var lower=[]
		var factor=[1.0,.82,.54,.30 if focused else .22][layer]
		for j in range(25):
			var u=j/24.0
			var center=mouth+dir*span*u
			var half_width=(28+88*pow(u,.60)) if focused else (17+174*pow(u,.78))
			var edge=half_width*factor*(1+sin(j*1.23-age*(30 if focused else 19))*.055)
			upper.append(center+side*edge)
			lower.push_front(center-side*edge)
		var col: Color=[c.darkened(.64 if focused else .43),c.darkened(.05),c.lightened(.43),c.lightened(.90 if focused else .68)][layer]
		col.a=b.fade
		poly(upper+lower,col)
	for i in range(84 if focused else 44):
		var u=fposmod(b.elapsed*(2.6 if focused else 1.5)+i*.079,1)
		var spread=(24+76*pow(u,.6)) if focused else (15+160*pow(u,.78))
		var tangent=sin(i*8.2)*spread*.76
		var p=mouth+dir*(span*u)+side*tangent
		var col=c.lightened(.60 if focused else .23)
		col.a=b.fade*.85
		line(p-dir*(26+u*(54 if focused else 34)),p,col,4 if i%4 else 8)
	if focused:
		# Bright pressure collars travel along an otherwise uninterrupted core.
		for i in range(5):
			var u=fposmod(b.elapsed*1.65+i*.20,1)
			var center=mouth+dir*span*u
			var radius=25+48*pow(u,.6)
			var col=c.lightened(.68)
			col.a=b.fade*.8
			line(center+side*radius+dir*8,center+side*radius*.55-dir*11,col,4)
			line(center-side*radius+dir*8,center-side*radius*.55-dir*11,col,4)
		impact(mouth,b.elapsed,c,1.6)
		ring(mouth,Vector2(24,35)*(1+sin(age*22)*.055),c.lightened(.5),8)
	for hit in hits:
		impact(hit,age-(1.04 if focused else 1.02),c,1.35 if focused else .86)
		if age>1.32 and age<(2.65 if focused else 2.38):
			var q=fposmod(age*3.6+hit.y*.03,1)
			var col=c.lightened(.28)
			col.a=(1-q)*.8
			line(hit+Vector2(-q*52,-18-q*18),hit+Vector2(-q*52-16,-26-q*18),col,4)


func prepare() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	meteors.clear()
	if kind!="meteors" or hits.is_empty(): return
	if not feet.is_empty():
		final_target=Vector2.ZERO
		for foot in feet: final_target+=foot
		final_target=final_target/feet.size()+Vector2(4,-2.5)
	for i in range(32):
		var target=hits[i%hits.size()]+Vector2(sin(i*7.3)*24,cos(i*4.1)*10)
		meteors.append({"target":target,"arrival":1.65+floorf(i/4.0)*.15+float(i%4)*.025,"radius":16.0+float(i%4)*5})
	meteors.append({"target":final_target,"arrival":4.15,"radius":82.0})

func cloud(p: Vector2,r: float,alpha: float) -> void:
	if r<2 or alpha<=.01: return
	disc(p,Vector2(r*1.3,r),Color(.055,.047,.064,alpha))
	disc(p+Vector2(-r*.15,r*.17),Vector2(r*.84,r*.69),Color(.019,.017,.027,alpha*.90))

func black_flame(p: Vector2,height: float,flip: bool,alpha: float) -> void:
	var sign_y=1.0 if flip else -1.0
	var points=[p+Vector2(-12,0),p+Vector2(-7,sign_y*height*.55),p+Vector2(-2,sign_y*height*.36),p+Vector2(4,sign_y*height),p+Vector2(8,sign_y*height*.43),p+Vector2(14,0)]
	poly(points,Color(.08,.02,.033,alpha))
	poly([p+Vector2(-8,0),p+Vector2(-3,sign_y*height*.40),p+Vector2(4,sign_y*height*.82),p+Vector2(9,0)],Color(.014,.013,.021,alpha))

func breath(c: Color) -> void:
	if kind=="breath":
		normal_breath(c)
		return
	var b=beam_values()
	var mouth: Vector2=b.mouth
	var dir: Vector2=b.dir
	var side=Vector2(-dir.y,dir.x)
	if age>=.12 and age<.82:
		var q=clampf((age-.12)/.70,0,1)
		for i in range(3):
			var a=i*2.399+q*3
			var p=mouth+Vector2(cos(a),sin(a))*(115*(1-q)+7)
			cloud(p,4+q*3,.10*sin(q*PI))
			if i%3==0: black_flame(p,8+q*7,false,.10*sin(q*PI))
			var ember=p+Vector2(4,-5)
			draw_rect(Rect2(ember.snapped(Vector2(3,3)),Vector2(3,3)),Color(.94,.04,.07,.15*sin(q*PI)))
	if b.elapsed>=0 and b.fade>0:
		# Awakening atmosphere sits OUTSIDE the attribute-colored continuous beam.
		for i in range(4):
			var u=fposmod(b.elapsed*1.0+i*.271,1)
			var sign_side=-1 if i%2 else 1
			var edge=34+95*pow(u,.60)
			var p=mouth+dir*(b.span*u*b.travel)+side*edge*sign_side
			cloud(p,5+u*5,b.fade*.08)
			black_flame(p,8+u*7,sign_side>0,b.fade*.08)
			if i%3==0:
				var ember=p+side*sign_side*(13+sin(age*13+i)*6)
				draw_rect(Rect2(ember.snapped(Vector2(3,3)),Vector2(3,5)),Color(.9,.035,.075,b.fade*.12))
	beam_core(c)
	if b.elapsed>=0 and b.elapsed<.62:
		var q=b.elapsed/.62
		var col=c
		col.a=1-q
		ring(mouth,Vector2.ONE*(30+q*250),col,8 if q<.4 else 4)
		ring(mouth,Vector2.ONE*(20+q*180),c.lightened(.5)*(Color(1,1,1,(1-q)*.7)),4)
	if age>=2.88 and age<4.32:
		var q=(age-2.88)/1.44
		for i in range(3):
			var p=mouth+Vector2(-32-i*17-q*60,sin(i*4.5)*43-q*72)
			cloud(p,5+q*6,(1-q)*.08)
			if i%2==0: draw_rect(Rect2((p+Vector2(0,-12)).snapped(Vector2(3,3)),Vector2(3,3)),Color(.88,.035,.065,(1-q)*.12))

func meteor_rain(c: Color) -> void:
	# Existing rock, trail and impact drawing is retained for the expanded schedule.
	meteor_rocks(c)
	for i in range(meteors.size()):
		var m=meteors[i]
		var t=age-m.arrival
		var big=i==32
		var life=1.7 if big else .55
		if t<0 or t>life: continue
		var q=t/life
		var center: Vector2=m.target
		var col=c
		col.a=1-q
		if big:
			cataclysm(center,t,c)
			ring(center,Vector2.ONE*(60+q*470),col,10 if q<.2 else 6)
			ring(center+Vector2(0,20),Vector2(90+q*490,20+q*100),col,8)
			if t<.11: disc(center,Vector2(108,126)*(1-t/.11),c.lightened(.78))
		else:
			ring(center+Vector2(0,12),Vector2(26+q*64,12+q*25),col,4)
			if t<.08: disc(center,Vector2(28,33)*(1-t/.08),c.lightened(.65))
		for j in range(34 if big else 5):
			var angle=j*2.399+i
			var spread=(60+q*245) if big else (12+q*44)
			var p=center+Vector2(cos(angle)*spread,sin(angle)*spread*.38-q*(125 if big else 47))
			cloud(p,(25+q*29) if big else (9+q*13),(1-q)*(.72 if big else .55))
			if j%3==0:
				var spark=center+Vector2(cos(angle),-absf(sin(angle)))*(q*(380 if big else 90))+Vector2(0,q*q*90)
				line(spark,spark+Vector2(0,-9),col,4)


func cataclysm(center: Vector2,t: float,c: Color) -> void:
	# A blast front crosses the whole battlefield, followed by expanding ground dust.
	if t<.14:
		var flash=c.lightened(.92)
		flash.a=(1-t/.14)*.94
		draw_rect(Rect2(-100,-100,1480,920),flash)
	for j in range(3):
		var dt=t-j*.09
		if dt<0 or dt>.95: continue
		var q=dt/.95
		var col=c.lightened(.45)
		col.a=pow(1-q,1.3)*.95
		var radius=75+pow(q,.65)*1450
		ring(center,Vector2(radius,radius*.63),col,28*(1-q)+4)
		ring(center+Vector2(0,25),Vector2(radius*1.12,radius*.24),col,18*(1-q)+4)
	if t<.8:
		var q=t/.8
		for j in range(22):
			var a=j*2.399
			var dir=Vector2(cos(a),sin(a)*.58)
			var col=c.lightened(.3)
			col.a=1-q
			line(center+dir*(60+q*180),center+dir*(160+q*930),col,6)
	for j in range(28):
		var q=clampf(t/1.7,0,1)
		var a=j*TAU/28
		var radius=90+pow(q,.65)*1050
		var pos=center+Vector2(cos(a)*radius,sin(a)*radius*.26-30-q*50)
		cloud(pos,28+q*75,(1-q)*.82)
	for j in range(12):
		var q=clampf(t/1.7,0,1)
		var pos=center+Vector2(sin(j*6.7)*(30+q*150),-q*(260+j%4*60))
		cloud(pos,28+q*62,(1-q)*.70)

func normal_breath(c: Color) -> void:
	var b=beam_values()
	var focused: bool=b.focused
	charge(c,.18,.82 if focused else .78)
	if b.elapsed<0 or b.fade<=0: return
	var mouth: Vector2=b.mouth
	var dir: Vector2=b.dir
	var side=Vector2(-dir.y,dir.x)
	var span: float=b.span*b.travel
	# Opaque nested ribbons remain continuous from the mouth through the screen edge.
	# Only the final whole-beam fade changes visibility; the beam never retracts.
	for layer in range(4):
		var upper=[]
		var lower=[]
		var factor=[1.0,.82,.54,.22][layer]
		for j in range(25):
			var u=j/24.0
			var center=mouth+dir*span*u
			var half_width=(20+61*pow(u,.60)) if focused else (17+174*pow(u,.78))
			var edge=half_width*factor*(1+sin(j*1.23-age*(30 if focused else 19))*.055)
			upper.append(center+side*edge)
			lower.push_front(center-side*edge)
		var col: Color=[c.darkened(.64 if focused else .43),c.darkened(.05),c.lightened(.43),c.lightened(.90 if focused else .68)][layer]
		col.a=b.fade
		poly(upper+lower,col)
	for i in range(56 if focused else 44):
		var u=fposmod(b.elapsed*(2.6 if focused else 1.5)+i*.079,1)
		var spread=(21+50*pow(u,.6)) if focused else (15+160*pow(u,.78))
		var tangent=sin(i*8.2)*spread*.76
		var p=mouth+dir*(span*u)+side*tangent
		var col=c.lightened(.60 if focused else .23)
		col.a=b.fade*.85
		line(p-dir*(26+u*(54 if focused else 34)),p,col,4 if i%4 else 8)
	if focused:
		# Bright pressure collars travel along an otherwise uninterrupted core.
		for i in range(5):
			var u=fposmod(b.elapsed*1.65+i*.20,1)
			var center=mouth+dir*span*u
			var radius=25+48*pow(u,.6)
			var col=c.lightened(.68)
			col.a=b.fade*.8
			line(center+side*radius+dir*8,center+side*radius*.55-dir*11,col,4)
			line(center-side*radius+dir*8,center-side*radius*.55-dir*11,col,4)
		impact(mouth,b.elapsed,c,1.6)
		ring(mouth,Vector2(24,35)*(1+sin(age*22)*.055),c.lightened(.5),8)
	for hit in hits:
		impact(hit,age-(1.04 if focused else 1.02),c,1.35 if focused else .86)
		if age>1.32 and age<(2.65 if focused else 2.38):
			var q=fposmod(age*3.6+hit.y*.03,1)
			var col=c.lightened(.28)
			col.a=(1-q)*.8
			line(hit+Vector2(-q*52,-18-q*18),hit+Vector2(-q*52-16,-26-q*18),col,4)


func meteor_rocks(c: Color) -> void:
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
		var flight=.90 if m.radius>60 else .60
		if t>=-flight and t<0:
			var q=1+t/flight
			var origin=target+Vector2(185+sin(i*5.2)*45,-470)
			var pos=origin.lerp(target,q*q)
			var dir=origin.direction_to(target)
			var side=Vector2(-dir.y,dir.x)
			if m.radius>60:
				for k in range(15):
					var u=k/14.0
					var wake=pos-dir*(55+u*240)+side*sin(k*7.3+age*22)*(18+u*32)
					var col=c.darkened(.35)
					col.a=(1-u)*.75
					disc(wake,Vector2(30-u*17,35-u*20),col)
				var rock=[]
				for k in range(13):
					var a=k*TAU/13+.23
					rock.append(pos+Vector2(cos(a),sin(a))*m.radius*(.80+fposmod(k*7.13,.29)))
				poly(rock,Color("24232c"))
				for k in range(13):
					var shade=Color("514b55") if k%3==0 else Color("35313d")
					poly([rock[k],rock[(k+1)%13],pos+Vector2(-18,-12)],shade)
				for k in range(5):
					var a=rock[k*2].lerp(pos,.3)
					var b=a.lerp(pos,.5)+Vector2(8,-11)
					line(a,b,c.lightened(.3),3)
					line(b,pos+Vector2(k*6-12,k*3),c.darkened(.1),3)
			else:
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

