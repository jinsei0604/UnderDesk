extends RefCounted
const HP=Color("6bd6a3")
const HP_LIGHT=Color("d6ffe4")
const SP=Color("b69bea")
const SP_LIGHT=Color("f1e3ff")
const GOLD=Color("e8ce96")

static func line(c: CanvasItem,a: Vector2,b: Vector2,color: Color,width: float=2) -> void:
	if a.round()!=b.round():c.draw_line(a.round(),b.round(),color,width,false)

static func diamond(c: CanvasItem,p: Vector2,size: float,color: Color) -> void:
	var r:=maxf(1,roundf(size))
	c.draw_colored_polygon(PackedVector2Array([(p+Vector2(0,-r)).round(),(p+Vector2(r*0.65,0)).round(),(p+Vector2(0,r)).round(),(p+Vector2(-r*0.65,0)).round()]),color)

static func cross(c: CanvasItem,p: Vector2,r: float,color: Color) -> void:
	line(c,p+Vector2(-r,0),p+Vector2(r,0),color,3)
	line(c,p+Vector2(0,-r),p+Vector2(0,r),color,3)

static func arc_point(a: Vector2,b: Vector2,u: float,height: float) -> Vector2:
	return a.lerp(b,u)+Vector2(0,-sin(u*PI)*height)

static func trail(c: CanvasItem,a: Vector2,b: Vector2,u: float,height: float,color: Color) -> void:
	for i in 6:
		var tail:=maxf(0,u-float(i)*0.035)
		var end:=maxf(0,tail-0.04)
		line(c,arc_point(a,b,tail,height),arc_point(a,b,end,height),Color(color,(1-float(i)/7)*0.7),2)

static func normal(c: CanvasItem,age: float,release: float,hit: float,hand: Vector2,launch: Vector2,target: Vector2) -> void:
	if age>release-0.08 and age<release:
		diamond(c,hand,3*smoothstep(release-0.08,release,age),GOLD)
	if age>=release and age<hit:
		var u:=pow((age-release)/(hit-release),0.8)
		var p:=launch.lerp(target,u)
		var axis:=(target-launch).normalized()
		line(c,p-axis*18,p,Color("9daaba"),3)
		line(c,p-axis*10,p,Color("fff6da"),3)
		diamond(c,p,4,Color("fffbea"))
	var e:=age-hit
	if e>=0 and e<0.20:
		var u:=e/0.20
		for i in 6:
			var axis:=Vector2.from_angle(float(i)*TAU/6+0.2)
			line(c,target+axis*(3+u*20),target+axis*(9+u*24),Color(0.97,0.94,0.84,1-u))
		if e<0.075:cross(c,target,7*(1-u),Color(1,1,0.95,1-u))

static func heal(c: CanvasItem,age: float,release: float,hit: float,hand: Vector2,launch: Vector2,recipients: Array[Dictionary]) -> void:
	if age>0.26 and age<release:
		var u:=smoothstep(0.26,release,age)
		for i in 4:
			var p:=hand+Vector2.from_angle(float(i)*TAU/4-PI/4)*(18*(1-u)+4)
			diamond(c,p,2+u,Color(HP,u))
		cross(c,hand,4*u,Color(HP_LIGHT,u))
	for recipient in recipients:
		var center: Vector2=recipient.center
		if age>=release and age<hit:
			var u:=smoothstep(release,hit,age)
			var p:=arc_point(launch,center,u,28)
			trail(c,launch,center,u,28,HP)
			diamond(c,p,4,HP_LIGHT)
		var e:=age-hit
		if e>=0 and e<0.41:
			var u:=e/0.41
			var alpha:=1-smoothstep(0.14,0.41,e)
			# Two rising ribbons wrap the recipient, their core remains above the log.
			for side in [-1,1]:
				for i in 6:
					var y:=14-float(i)*5-u*17
					var p:=center+Vector2(side*(13+4*sin(float(i)*0.55+u*PI)),y)
					line(c,p,p+Vector2(side*2,-4),Color(HP,alpha*(1-float(i)*0.08)))
			cross(c,center+Vector2(0,-4-u*16),5,Color(HP_LIGHT,alpha))
			for i in 4:
				var p:=center+Vector2((i-1.5)*12,-u*31-absf(i-1.5)*5)
				diamond(c,p,2,Color(HP,alpha))

static func sp(c: CanvasItem,age: float,release: float,hit: float,hand: Vector2,launch: Vector2,recipients: Array[Dictionary]) -> void:
	if age>0.32 and age<release:
		var u:=smoothstep(0.32,release,age)
		for i in 3:
			var p:=hand+Vector2((i-1)*8,-8-absf(i-1)*4)*(1.6-u*0.6)
			diamond(c,p,3,Color(SP,u))
		diamond(c,hand,4*u,Color(GOLD,u))
	for index in recipients.size():
		var center: Vector2=recipients[index].center
		var bend:=36+float(index)*12
		if age>=release and age<hit:
			var u:=smoothstep(release,hit,age)
			var p:=arc_point(launch,center,u,bend)
			trail(c,launch,center,u,bend,SP)
			diamond(c,p,5,SP)
			diamond(c,p+Vector2(0,-1),2,SP_LIGHT)
		var e:=age-hit
		if e>=0 and e<0.40:
			var u:=e/0.40
			var alpha:=1-smoothstep(0.12,0.40,e)
			for i in 3:
				var p:=center+Vector2((i-1)*10,-u*19-absf(i-1)*7)
				diamond(c,p,4,Color(SP,alpha))
				diamond(c,p,2,Color(SP_LIGHT,alpha))
			for side in [-1,1]:
				var a:=center+Vector2(side*(11+u*12),9-u*8)
				line(c,a,a+Vector2(side*5,-7),Color(GOLD,alpha))
