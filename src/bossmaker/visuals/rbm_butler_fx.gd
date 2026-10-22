extends RefCounted
const INK=Color("183550")
const ICE=Color("509cf5")
const MID=Color("6dc6e7")
const FROST=Color("b8edf7")
const WHITE=Color("edfaff")

static func polygon(c: CanvasItem, points: Array, color: Color) -> void:
	var packed:=PackedVector2Array()
	for p in points: packed.append(Vector2(p).round())
	# All effect silhouettes are authored convex triangles/quads, no scanline/image parsing.
	if packed.size()==3 and absf((packed[1]-packed[0]).cross(packed[2]-packed[0]))<1: return
	c.draw_colored_polygon(packed,color)

static func line(c: CanvasItem, a: Vector2, b: Vector2, color: Color, width: float=2) -> void:
	if a.round()!=b.round(): c.draw_line(a.round(),b.round(),color,width,false)

static func needle(c: CanvasItem, point: Vector2, direction: Vector2, length: float, width: float, alpha: float=1.0) -> void:
	var axis:=direction.normalized()
	var side:=axis.orthogonal()
	var rear:=point-axis*length
	var ridge:=point-axis*length*0.70
	polygon(c,[point,rear+side*width,rear-side*width],Color(INK,alpha))
	polygon(c,[point,ridge+side*(width*0.67),rear],Color(MID,alpha))
	polygon(c,[point,rear,ridge-side*(width*0.6)],Color(FROST,alpha))
	line(c,point,point-axis*length*0.82,Color(WHITE,alpha),2)

static func dial(c: CanvasItem, center: Vector2, radius: float, progress: float, color: Color) -> void:
	for i in 8:
		var a:=float(i)*TAU/8
		var p:=center+Vector2.from_angle(a)*radius
		line(c,p,p+Vector2.from_angle(a)*3,color)
	line(c,center,center+Vector2.from_angle(-PI/2+progress*TAU)*radius*0.75,color)
	line(c,center,center+Vector2.from_angle(progress*TAU*0.24)*radius*0.5,color)

static func fragments(c: CanvasItem, center: Vector2, elapsed: float, lifetime: float, count: int, spread: float) -> void:
	if elapsed<0 or elapsed>=lifetime:return
	var u:=elapsed/lifetime
	for i in count:
		var axis:=Vector2.from_angle(float(i)*2.399+0.3)
		var p:=center+axis*(9+u*(spread+float(i%3)*9))+Vector2(0,u*u*18)
		needle(c,p,axis,7+float(i%4)*2,2+(i%2),1-u)

static func normal(c: CanvasItem, age: float, release: float, hit: float, hand: Vector2, launch: Vector2, target: Vector2) -> void:
	if age>release-0.09 and age<release+0.04:
		var alpha:=1-absf(age-release)/0.09
		line(c,hand+Vector2(-4,0),hand+Vector2(4,0),Color(1,0.95,0.76,alpha))
		line(c,hand+Vector2(0,-4),hand+Vector2(0,4),Color(1,0.95,0.76,alpha))
	if age>=release and age<hit:
		var u:=(age-release)/(hit-release)
		var p:=launch.lerp(target,pow(u,0.78))
		var axis:=(target-launch).normalized()
		line(c,p-axis*22,p,Color("cdd5df"),3)
		line(c,p-axis*11,p,Color("fff8df"),2)
		line(c,p-axis*28+Vector2(0,4),p-axis*13+Vector2(0,4),Color(0.6,0.67,0.73,0.65))
	var e:=age-hit
	if e>=0 and e<0.17:
		var u:=e/0.17
		for i in 5:
			var axis:=Vector2.from_angle(float(i)*TAU/5+0.25)
			var p:=target+axis*(4+u*18)
			line(c,p,p+axis*7*(1-u),Color(0.96,0.94,0.84,1-u))
		line(c,target+Vector2(-7,-11)*(1-u),target+Vector2(7,11)*(1-u),Color(1,1,1,1-u),3)

static func bolt(c: CanvasItem, age: float, release: float, hit: float, hand: Vector2, launch: Vector2, target: Vector2) -> void:
	if age>0.22 and age<release:
		var u:=smoothstep(0.22,release,age)
		needle(c,hand+Vector2(11,-2),Vector2.RIGHT,24*u,4*u,0.85)
		for i in 4:
			var p:=hand+Vector2.from_angle(float(i)*PI/2)*18*(1-u)
			c.draw_rect(Rect2(p.round(),Vector2(2,2)),Color(FROST,u))
	if age>=release and age<hit:
		var u:=(age-release)/(hit-release)
		var p:=launch.lerp(target,pow(u,0.75))
		var axis:=(target-launch).normalized()
		needle(c,p,axis,49,8)
		line(c,p-axis*60,p-axis*20,Color(0.5,0.79,0.94,0.45),3)
		for i in 3: c.draw_rect(Rect2((p-axis*(58+i*15)+Vector2(0,(i%2)*4-2)).round(),Vector2(3,2)),Color(FROST,0.5))
	var e:=age-hit
	if e>=0 and e<0.12:
		var u:=e/0.12
		line(c,target+Vector2(-23,13)*(1-u),target+Vector2(30,-17)*(1-u),Color(FROST,1-u),5)
		line(c,target+Vector2(-8,-22)*(1-u),target+Vector2(8,22)*(1-u),Color(WHITE,1-u),3)
	fragments(c,target,e,0.29,11,32)

static func storm(c: CanvasItem, age: float, release: float, hit: float, hand: Vector2, launch: Vector2, target: Vector2) -> void:
	if age>0.28 and age<release:
		var u:=smoothstep(0.28,release,age)
		for i in 3:
			var p:=hand+Vector2((i-1)*9,-9-u*5)
			needle(c,p,Vector2(0.5,-1),12*u,3*u,0.8)
	if age>=release and age<hit:
		var u:=(age-release)/(hit-release)
		for i in 5:
			var end:=target+Vector2((i-2)*34,absf(i-2)*5)
			var start:=launch+Vector2((i-2)*18,-22-absf(i-2)*17)
			var p:=start.lerp(end,smoothstep(0,1,u))+Vector2(0,-sin(u*PI)*(35+float(i%2)*8))
			needle(c,p,(end-start).normalized(),44+float(i%3)*8,6)
	var e:=age-hit
	if e>=0 and e<0.23:
		var u:=smoothstep(0.04,0.23,e)
		for i in 5:
			var center:=target+Vector2((i-2)*34,absf(i-2)*5)
			needle(c,center+Vector2(5,-(31+float(i%3)*9)*(1-u)),Vector2(0.25,-1),53*(1-u)+3,13*(1-u)+1,1-u)
		line(c,target+Vector2(-93,10),target+Vector2(93,10),Color(FROST,(1-u)*0.8),4)
	if e>=0 and e<0.34:
		for i in 3: fragments(c,target+Vector2((i-1)*52,0),e,0.34,5,28)

static func gift(c: CanvasItem, age: float, release: float, hit: float, hand: Vector2, launch: Vector2, target: Vector2, amount: int) -> void:
	const GOLD=Color("edd29a")
	const SP=Color("c5a4ef")
	if age>0.24 and age<release:
		var u:=smoothstep(0.24,release,age)
		dial(c,hand,7+u*5,u*0.2,Color(GOLD,u))
	if age>=release and age<hit:
		var u:=(age-release)/(hit-release)
		var p:=launch.lerp(target,smoothstep(0,1,u))+Vector2(0,-sin(u*PI)*48)
		dial(c,p,9,u*0.35,GOLD)
		for i in 5:
			var tail:=maxf(0,u-float(i+1)*0.045)
			var point:=launch.lerp(target,smoothstep(0,1,tail))+Vector2(0,-sin(tail*PI)*48)
			c.draw_rect(Rect2(point.round(),Vector2(2,2)),Color(SP,0.65-float(i)*0.1))
	var e:=age-hit
	if amount>0 and e>=0 and e<0.31:
		var u:=e/0.31
		for side in [-1,1]:
			var a:=target+Vector2(side*(19-u*7),-13+u*6)
			var b:=target+Vector2(side*(19-u*7),13-u*6)
			line(c,a,b,Color(SP,1-u))
			line(c,a,a+Vector2(-side*5,-4),Color(SP,1-u))
			line(c,b,b+Vector2(-side*5,4),Color(SP,1-u))
		for i in 4:
			var p:=target+Vector2((i-1.5)*7,-u*26-absf(i-1.5)*3)
			polygon(c,[p+Vector2(0,-4),p+Vector2(3,0),p+Vector2(0,4),p+Vector2(-3,0)],Color(GOLD,1-u))
