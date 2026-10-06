extends Node2D
## Astronaut-only effects, drawn in a low-resolution transparent viewport.
## All coordinates use the same pixel grid as the approved 66 px body/props.
const Timeline = preload("res://src/bossmaker/visuals/rbm_astronaut_timeline.gd")
const ROCKET = preload("res://assets_bossmaker/battle/astronaut/props/rocket.png")
const PLANET = preload("res://assets_bossmaker/battle/astronaut/props/planet.png")
const METEOR = preload("res://assets_bossmaker/battle/astronaut/props/meteor.png")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
var kind := "single"
var age := 0.0
var boss := Vector2(492,270)
var target := Vector2(226,282)
var center := Vector2(153,228)
var canvas_size := Vector2(640,360)
var attack_attribute := "NEUTRAL"
var hit_points: Array[Vector2] = []
var aura_only := false
var power := 1.0

func _init() -> void: texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func sample(i: int, channel: int = 0) -> float:
	return fposmod(sin(float(i*127+channel*311+19))*43758.5453, 1.0)

func ink(hex: String, alpha: float = 1.0) -> Color:
	var c := Color(hex); c.a = clampf(alpha,0,1); return c

func line(points: Array, color: Color, width: float = 1) -> void:
	if color.a <= 0: return
	var p := PackedVector2Array()
	for v in points: p.append(Vector2(v).round())
	if p.size() > 1: draw_polyline(p,color,maxf(1,roundf(width)),false)

func poly(points: Array, color: Color) -> void:
	if color.a <= 0: return
	var p := PackedVector2Array()
	for v in points: p.append(Vector2(v).round())
	# Very small collapsing silhouettes can become degenerate after pixel snapping.
	if absf(_area(p)) > .1: draw_colored_polygon(p,color)

func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size(): a += p[i].cross(p[(i+1)%p.size()])
	return a*.5

func ellipse(c: Vector2, radius: Vector2, color: Color, width: float = 0) -> void:
	if radius.x < .6 or radius.y < .6 or color.a <= 0: return
	var p: Array = []
	for i in range(65): p.append(c + Vector2(cos(i*TAU/64)*radius.x,sin(i*TAU/64)*radius.y))
	if width > 0: line(p,color,width)
	else: poly(p.slice(0,64),color)

func star(c: Vector2, radius: float, color: Color) -> void:
	line([c-Vector2(radius,0),c+Vector2(radius,0)],color)
	line([c-Vector2(0,radius),c+Vector2(0,radius)],color)
	if radius > 4: ellipse(c,Vector2.ONE*radius*.35,color)

func glow(c: Vector2, radius: Vector2, color: Color, strength: float) -> void:
	for i in range(8,0,-1): ellipse(c,radius*float(i)/8,Color(color.r,color.g,color.b,strength*.045))

func blob(c: Vector2, radius: float, id: int, colors: Array, stretch: float, alpha: float) -> void:
	for j in colors.size():
		var pts: Array = []
		for k in range(22):
			var a := k*TAU/22
			var rough := 1+.13*sin(k*2.4+id)+.07*sin(k*5.2-id+age*4)
			var r := radius*(1-j*.19)*rough
			pts.append(c-Vector2(j*radius*.12,j*radius*.15)+Vector2(cos(a)*r,sin(a)*r*stretch))
		poly(pts,ink(colors[j],alpha))

func rays(c: Vector2, t: float, strength: float, reach: float, inward: bool, count: int, color: Color) -> void:
	for i in count:
		var a := i*2.399+sample(i)*.3
		var p := fposmod(t*(.55+sample(i,2)) + sample(i,1),1.0)
		var r := (1-p if inward else p)*reach
		var dir := Vector2(cos(a),sin(a)*.65)
		line([c+dir*r,c+dir*(r+8+sample(i,3)*35)],Color(color.r,color.g,color.b,strength*(1-p)*.8),1 if i%4 else 2)

func aura(t: float, strength: float = 1.0) -> void:
	var c := boss-Vector2(0,45)
	glow(c,Vector2(64,84),ink("292659"),strength*.75)
	for k in range(9):
		var phase := fposmod(t*.42+k*.083,1)
		var width := 20+(1-phase)*40*strength
		var yy := boss.y+8-phase*(104+strength*19)
		var angle := t*2+k*1.7
		var pts: Array = []
		for j in range(24):
			var q := j/23.0; var a := q*PI*1.25+angle
			pts.append(Vector2(c.x+cos(a)*width,yy+sin(a)*width*.26+q*22))
		line(pts,ink("423a93",.48*strength),5)
		line(pts,ink("827afa",.68*strength),2)
	for k in range(2):
		var tilt := -.62 if k==0 else .44
		var pts: Array = []
		for j in range(97): pts.append(c+Vector2(cos(j*TAU/96)*55,sin(j*TAU/96)*24).rotated(tilt))
		line(pts,ink("4a64b5",.40*strength),2)
		star(pts[int(t*17+k*55)%96],3,ink("e9f5ff",strength))
	for i in range(36):
		var p := fposmod(t*.17+sample(i),1)
		var xy := c+Vector2(sin(i*2.399+t*.4)*(25+sample(i,1)*40),55-p*124)
		star(xy,1 if i%8 else 2,ink("ada4f4",sin(p*PI)*strength*.8))

func reticle(t: float, all_party: bool) -> void:
	var u := t-(1.1 if all_party else .8)
	if u < 0 or u > 2.55: return
	var c := target-Vector2(0,29)
	var fade := 1-smoothstep(2.2,2.55,u)
	var red := ink("ff453b",fade)
	var r := lerpf(54,89 if all_party else 25,smoothstep(0,.45,u))
	if all_party: ellipse(target,Vector2(r,r*.35),red,2)
	else:
		for sx in [-1,1]:
			for sy in [-1,1]:
				var p := c+Vector2(sx*r,sy*r)
				line([p-Vector2(sx*9,0),p,p-Vector2(0,sy*9)],red,2)
		ellipse(c,Vector2.ONE*13,ink("ff453b",fade*.75),1)
		ellipse(target,Vector2(25,7),red,2)
	if .5 < u and u < 2.15:
		var p := target-Vector2(0,89)
		poly([p-Vector2(0,9),p+Vector2(-10,8),p+Vector2(10,8)],ink("ff6335",fade))
		line([p-Vector2(0,4),p+Vector2(0,2)],ink("fff5c9"),2)
		draw_rect(Rect2(p+Vector2(-1,5),Vector2(3,2)),ink("fff5c9"))
		for side in [-1,1]: line([p+Vector2(side*15,0),p+Vector2(side*28,0)],red,2)

func console(t: float, large: bool = false) -> void:
	if t < .5 or t > 2.2: return
	var p := boss+Vector2(-18,-35)
	var q := sin(clampf((t-.5)/1.7,0,1)*PI)
	poly([p+Vector2(-8,-5),p+Vector2(6,-4),p+Vector2(8,4),p+Vector2(-7,3)],ink("182736",q))
	if large: ellipse(p,Vector2(4,3),ink("ff5b48",q))
	else:
		for i in 3: line([p+Vector2(-5,-2+i*2),p+Vector2(2+i,-2+i*2)],ink("87f4ff",q))
	star(p,3,ink("d7efff",q*.8))

func fissures(c: Vector2, u: float, radius: float, cold: bool) -> void:
	if u < 0 or u > 3.8: return
	for k in 14:
		var pts: Array = [c]
		for j in range(1,6):
			var r := j*radius/5*smoothstep(0,.34,u)*(.6+sample(k)*.4)
			var a := k*2.399+sin(k*5+j*7)*.15
			pts.append(c+Vector2(cos(a)*r,sin(a)*r*.25))
		line(pts,ink("09080f",.85*(1-smoothstep(1.5,3.8,u))),3)
		line(pts,ink("6692fb" if cold else "e56427",.65*(1-smoothstep(1.5,3.8,u))),1)

func explosion(c: Vector2, u: float, magnitude: float, cold: bool) -> void:
	if u < 0 or u >= 4: return
	var big := magnitude >= 2
	var scale_effect := magnitude*1.95
	var fade := 1-smoothstep(3.30,4,u)
	var hot: Array = ["761e25","d23719","f87e1c","ffcc4e","fff6bf"]
	var smoke: Array = ["191b26","2b2a33","41393d","584540"]
	if cold:
		hot = ["252269","4249c0","5a9af4","9fdffe","f0f7ff"]
		smoke = ["141932","222d48","313f62","48567c"]
	var col := ink("82c4ff" if cold else "ffad44")
	var white := ink("e7f4ff" if cold else "fff4c7")
	var energy := c-Vector2(0,26*magnitude)
	fissures(c,u,68*scale_effect,cold)
	glow(energy,Vector2(210 if big else 115,150 if big else 82),col,.85*(1-smoothstep(.12,.95,u)))
	if u > .14:
		var strength := (1-smoothstep(1.65,3.8,u))*smoothstep(.14,.42,u)*fade
		for k in range(int(20+scale_effect*13)):
			var a := sample(k)*TAU; var spread := (12+28*smoothstep(0,.8,u))*scale_effect
			var p := c+Vector2(cos(a)*spread*(.3+sample(k,1)),-12*scale_effect-sample(k,2)*32*scale_effect-u*(11+sample(k,3)*14))
			blob(p,(7+sample(k,4)*13+u*3)*scale_effect,k,smoke,.83,.72*strength)
	if u < 1.75:
		var strength := (1-smoothstep(.7,1.75,u))*fade
		var grow := smoothstep(0,.30,u)
		for k in range(35 if big else 20):
			var a := k*2.399; var r := (5+sample(k)*32)*scale_effect*grow
			var p := c+Vector2(cos(a)*r,-12*scale_effect+sin(a)*r*.65-u*(20+sample(k,1)*40))
			blob(p,(7+sample(k,2)*12)*scale_effect*(.35+.8*grow),k,hot,1.15,.94*strength)
		if u < .22: ellipse(energy,Vector2(50,44)*scale_effect*smoothstep(0,.13,u),Color(white.r,white.g,white.b,1-smoothstep(.06,.22,u)))
	# Five thick pressure fronts and spherical shells retain the approved huge hit.
	for k in range(5 if big else 3):
		var dt := u-k*.10
		if dt < 0 or dt >= 1.35: continue
		var q := dt/1.35; var r := 12+(470 if big else 245)*pow(q,.66)
		var strength := pow(1-q,1.7)*fade
		ellipse(c,Vector2(r,r*.27),Color(col.r,col.g,col.b,.88*strength),14*strength)
		ellipse(c,Vector2(maxf(1,r-9),maxf(1,r*.27-3)),Color(white.r,white.g,white.b,.9*strength),4*strength)
		if k < 3: ellipse(energy,Vector2(r*.82,r*.68),Color(col.r,col.g,col.b,.58*strength),6*strength)
	if u < .85:
		for k in range(44 if big else 26):
			var a := k*2.399; var strength := 1-smoothstep(.25,.85,u)
			var r := (45+(210 if big else 110)*smoothstep(0,.4,u))*(.65+sample(k)*.5)
			var dir := Vector2(cos(a),sin(a)*.64); var n := Vector2(-sin(a),cos(a))*(2+sample(k,1)*6)*strength
			poly([energy+dir*r*.35,energy+dir*r-n,energy+dir*(r+28*strength),energy+dir*r+n],Color(white.r,white.g,white.b,.82*strength))
	if u > .30 and u < 3.35:
		var dt := u-.30; var spread := (190 if big else 100)*smoothstep(0,1.1,dt)
		for k in range(34 if big else 19):
			var a := k*2.399; var p := c+Vector2(cos(a)*spread*(.6+sample(k)*.5),sin(a)*spread*.18-7-dt*5)
			blob(p,(8+sample(k,1)*12)*(1+dt*.23),k,smoke,.58,.82*(1-smoothstep(1.7,3.05,dt))*smoothstep(0,.15,dt))
	for k in range(90 if big else 42):
		var dt := u-sample(k)*.35
		if dt < 0: continue
		var a := -PI+sample(k,1)*PI; var speed: float = (80+sample(k,2)*190)*(1 if big else .55)
		var p := c+Vector2(cos(a)*speed*dt,-12+sin(a)*speed*dt+38*dt*dt)
		if p.y > c.y+14: continue
		line([p-Vector2(cos(a),sin(a))*8,p],Color(col.r,col.g,col.b,.86*(1-smoothstep(.7,2.65,dt))),2 if k%5==0 else 1)

func _single(t: float) -> void:
	console(t); reticle(t,false)
	var entry := Vector2(target.x+61, maxf(15,target.y-262))
	if 2.0 < t and t < 3.10:
		var f := smoothstep(2,2.45,t)*(1-smoothstep(2.9,3.10,t))
		glow(entry,Vector2.ONE*28,ink("97ccff"),f); star(entry,12*f,ink("e5f5ff",f))
	if 2.91 < t and t < 3.27:
		var p := (t-2.91)/.36; var c := entry.lerp(target-Vector2(0,7),pow(p,1.7))
		for j in 4:
			var col: Array = ["66242d","e83d18","ff8923","ffe089"]
			var w := 15-j*3
			poly([c+Vector2(-w,-6),c+Vector2(34-j*3,-85-45*p),c+Vector2(w,-2),c+Vector2(0,8)],ink(col[j],.9))
		draw_texture(METEOR,(c-Vector2(METEOR.get_width()/2.0,METEOR.get_height()/2.0)).round())
	explosion(target,t-3.27,1.18,false)

func _rocket(t: float) -> void:
	console(t,true); reticle(t,true)
	if 1.3 < t and t < 3.25:
		var q := smoothstep(1.3,3.2,t)
		ellipse(target,Vector2(15+q*83,5+q*21),ink("050812",q*.75))
		star(Vector2(target.x,maxf(8,target.y-275)),14*smoothstep(1.7,2.5,t),ink("dfefff",1-smoothstep(2.4,2.8,t)))
	if 2.35 < t and t < 3.25:
		var p := (t-2.35)/.90
		var bottom := lerpf(-20,target.y,pow(p,2.25))
		var c := Vector2(target.x,bottom-ROCKET.get_height())
		for k in 40:
			var x := target.x+(sample(k)-.5)*95; var y := bottom-20-sample(k,1)*240
			line([Vector2(x,y-35-sample(k,2)*55),Vector2(x,y)],ink("ffc475",.6),1 if k%3 else 2)
		draw_texture(ROCKET,(c-Vector2(ROCKET.get_width()/2.0,0)).round())
	explosion(target,t-3.25,2.8,false)

func _planet(t: float) -> void:
	var pressure := smoothstep(.75,3.2,t)*(1-smoothstep(4.3,5.3,t))
	if pressure > 0:
		draw_rect(Rect2(Vector2.ZERO,canvas_size),ink("030614",pressure*.30))
		ellipse(target,Vector2(30+pressure*87,8+pressure*25),ink("01040f",pressure*.53))
		fissures(target,t-.95,105,true)
	if 2.8 < t and t < 4.15:
		var p := (t-2.8)/1.35
		var c := Vector2(target.x,lerpf(-144,target.y-116,pow(p,1.75)))
		for k in 58:
			var q := c+Vector2((sample(k)-.5)*263,-80+sample(k,1)*130)
			line([q-Vector2(0,20+sample(k,2)*64),q],ink("7bb6f7",.4+.35*p),1 if k%3 else 2)
		for j in 4: ellipse(c,Vector2.ONE*(117+j*2),ink("5ea4fb",.45-j*.08),2)
		draw_texture(PLANET,(c-PLANET.get_size()/2).round())
	explosion(target,t-4.15,3.05,true)
	if t >= 4.15: rays(target-Vector2(0,38),t-4.15,1-smoothstep(.2,1.5,t-4.15),300,false,85,ink("a5d5ff"))

func _awakening(t: float) -> void:
	var build := smoothstep(.7,6.2,t); var after := smoothstep(6.45,10.7,t)
	var c := boss-Vector2(0,85)
	draw_rect(Rect2(Vector2.ZERO,canvas_size),ink("04091f",build*(1-after*.75)*.62))
	for k in range(28):
		var a := k*.74+t*.2
		var r := 15+sample(k)*290*build
		var p := c+Vector2(cos(a)*r,sin(a)*r*.36).rotated(-.24)
		glow(p,Vector2(30+sample(k,1)*65,10+sample(k,2)*20),ink("343976" if k%2 else "44306d"),build*(1-after)*.5)
	for k in 180:
		var p := Vector2(sample(k)*canvas_size.x,sample(k,1)*canvas_size.y)
		star(p,1 if k%19 else 3,ink("bab9f2",build*(1-after)*(.3+.6*pow(sin(t*2+k),2))))
	for k in 58:
		var a := t*(.45+sample(k))+k*2.399; var r := (23+sample(k,1)*99)*(1-build*.15)
		var p := boss+Vector2(cos(a)*r,-7-sample(k,2)*135*build+sin(a)*r*.3)
		star(p,2 if k%7==0 else 1,ink("aaa4ff",build*(1-after*.7)))
	for k in 20:
		var p := boss+Vector2((sample(k)-.5)*170,-sample(k,1)*94*smoothstep(1.5,4,t)+sin(t+k)*4)
		poly([p-Vector2(3,0),p-Vector2(0,4),p+Vector2(4,1),p+Vector2(0,3)],ink("6f768d",build*(1-after)))
	aura(t,build*(1-after*.2))
	if t > 3.2 and t < 6.45: rays(boss-Vector2(0,45),t,smoothstep(3.2,6.2,t),390,true,70,ink("9faaff"))
	if t >= 6.45:
		var dt := t-6.45
		for k in 5:
			var u := dt-k*.12
			if u < 0 or u > 2.1: continue
			ellipse(boss-Vector2(0,45),Vector2(1,.5)*(20+350*pow(u/2.1,.7)),ink("bfe2ff",pow(1-u/2.1,1.5)),5*(1-u/2.1))
		rays(boss-Vector2(0,45),dt,1-smoothstep(.5,2.4,dt),650,false,110,ink("bfe2ff"))
		if dt < .13: draw_rect(Rect2(Vector2.ZERO,canvas_size),ink("dfe8ff",.88*(1-dt/.13)))

func _rift(t: float) -> void:
	if t < 1.15 or t >= 2.40: return
	var opening := smoothstep(1.15,1.8,t)
	var fold := smoothstep(1.95,2.38,t)
	var height := (5+71*opening)*pow(1-fold,1.15)
	var width := (1+7*opening)*(1-fold)
	var fade := 1-smoothstep(2.34,2.4,t)
	# A: razor-straight tall incision, pointed tips, very sparse cold edge glints.
	var left: Array = []; var right: Array = []
	for i in range(41):
		var q := i/20.0-1; var envelope := pow(maxf(0,1-absf(q)),.65)
		var notch := (sample(i)-.5)*1.8*envelope*opening*(1-fold)
		left.append(center+Vector2(-width*envelope+notch,q*height))
		right.append(center+Vector2(width*envelope*.6+notch,q*height))
	var silhouette: Array = left.duplicate(); var reversed := right.duplicate(); reversed.reverse(); silhouette.append_array(reversed)
	poly(silhouette,ink("010008",fade))
	line(left,ink("716fd0",fade*.85),1); line(right,ink("303354",fade*.7),1)
	for section in [[0,8],[17,22],[31,41]]:
		line(right.slice(section[0],section[1]),ink("d2e5ff",fade*opening),1)
	star(center-Vector2(0,height*.86),3*opening*(1-fold),ink("b7caff",fade))
	star(center+Vector2(0,height*.9),3*opening*(1-fold),ink("b7caff",fade))

func disk_point(a: float, radius: float) -> Vector2:
	return center+Vector2(cos(a)*radius*2.3,sin(a)*radius*.36).rotated(-.16)

func _blackhole(t: float) -> void:
	_rift(t)
	var r := Timeline.radius(t)
	if r > 0:
		var formation := smoothstep(2.25,2.65,t)
		glow(center,Vector2.ONE*r*2.6,ink("4b367f"),.8*formation)
		for layer in range(9):
			var pts: Array = []
			for j in range(97): pts.append(disk_point(j*TAU/96,r*(1+layer*.018)))
			line(pts,ink("6859b0" if layer%2 else "adbcf9",(.17+layer*.045)*formation),1)
		ellipse(center,Vector2.ONE*r*1.15,ink("4a3c82",.7))
		ellipse(center,Vector2.ONE*r,ink("010006"))
		for k in range(5):
			var pts: Array = []
			for j in range(34):
				var a := j*PI/33+t*1.8+k*.25
				pts.append(disk_point(a,r*(1.03+k*.024)))
			line(pts,ink("d7e5ff",formation*.48),1)
	if 2.38 < t and t < 5.12:
		var force := Timeline.pull(t)
		for k in 100:
			var p := fposmod(sample(k)+(t-2.38)*(.25+force*1.8),1)
			var rad := (30+sample(k,1)*160)*pow(1-p,1.35)
			var a := k*2.399+p*(1+force*3)
			var c := center+Vector2(cos(a)*rad,sin(a)*rad*.65)
			var prev := center+Vector2(cos(a-.09)*rad*(1.04+force*.1),sin(a-.09)*rad*.65*(1.04+force*.1))
			line([prev,c],ink("b8a0fb",smoothstep(2.38,2.9,t)*sin(p*PI)),1 if k%4 else 2)
			if k%13==0: star(c,2,ink("dfeaff",sin(p*PI)))
	if t >= 5.12:
		var dt := t-5.12
		# Approved blue explosion, including its full-strength core and shortened tail.
		var blast_time := dt if dt < .8 else lerpf(.8,4.0,clampf((dt-.8)/1.15,0,1))
		explosion(center,blast_time,2.5,true)
		rays(center,dt,1-smoothstep(.3,1.6,dt),213,false,90,ink("becefe"))
		if dt < .11: draw_rect(Rect2(Vector2(maxf(0,center.x-220),0),Vector2(minf(canvas_size.x,center.x+220)-maxf(0,center.x-220),canvas_size.y)),ink("e8f0ff",.6*(1-dt/.11)))

func _support(t: float) -> void:
	console(t)
	var color := ink("71da87" if kind=="heal" else "ef4847")
	var strength := smoothstep(.3,1.5,t)*(1-smoothstep(1.7,3,t))
	glow(boss-Vector2(0,35),Vector2(45,60),color,strength)
	for i in 32:
		var p := fposmod(sample(i)+t*.35,1)
		var c := boss+Vector2((sample(i,1)-.5)*64,-p*92)
		star(c,1 if i%5 else 3,Color(color.r,color.g,color.b,strength*sin(p*PI)))
	ellipse(boss,Vector2(20+age*8,6+age*2),Color(color.r,color.g,color.b,strength),2)

func _draw() -> void:
	if aura_only: aura(age,power); return
	match kind:
		"single": _single(age)
		"all": _rocket(age)
		"planet": _planet(age)
		"awakening": _awakening(age)
		"blackhole": _blackhole(age)
		"buff", "heal": _support(age)
	if kind in ["single","all","planet","blackhole"]:
		var dt: float = age-float(Timeline.IMPACTS[kind])
		if .04 < dt and dt < .38:
			var accent := Palette.color_for(attack_attribute)
			accent.a = 1-smoothstep(.16,.38,dt)
			for p in hit_points: star(p,9*(1-dt/.38),accent)
