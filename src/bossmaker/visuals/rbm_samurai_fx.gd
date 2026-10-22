extends RefCounted
const WIND=Color("a4d6af")
const LIGHT=Color("efffdc")

static func line(c: CanvasItem,a: Vector2,b: Vector2,color: Color,width: float=2) -> void:
	if a.round()!=b.round():c.draw_line(a.round(),b.round(),color,width,false)

static func glint(c: CanvasItem,p: Vector2,r: float,alpha: float) -> void:
	line(c,p-Vector2(r,0),p+Vector2(r,0),Color(LIGHT,alpha),2)
	line(c,p-Vector2(0,r),p+Vector2(0,r),Color(LIGHT,alpha),2)

static func stroke(c: CanvasItem,age: float,release: float,hit: float,kind: String,hand: Vector2,tip: Vector2,target: Vector2) -> void:
	var e:=age-hit
	if age>=release and e<0.10:
		var fade:=1-smoothstep(0.02,0.10,e)
		# The bright edge lies ON the current katana, not on an independent rotating arc.
		line(c,hand,tip,Color(LIGHT if kind!="normal" else Color("fff1d1"),fade*0.75),2)
	if kind!="normal" and age>=release+0.025 and e<0.26:
		var u:=clampf((age-release-0.025)/0.18,0,1)
		var fade:=1-smoothstep(0.06,0.26,e)
		var axis:=Vector2(1,-0.07) if kind=="all" else Vector2(-0.42,0.90)
		var length:=155.0 if kind=="all" else 65.0
		var end:=target+axis*(length*u)
		var start:=target-axis*(length*0.65*(1-u*0.6))
		line(c,start,end,Color(WIND,fade*0.65),4 if kind=="all" else 3)
		line(c,start+Vector2(0,-2),end,Color(LIGHT,fade),2)
		if kind=="all":
			for side in [-1,1]:
				var points:=PackedVector2Array()
				for i in 13:
					var p:=float(i)/12
					points.append((target+Vector2(-95+p*220,side*sin(p*PI)*(11+u*18))).round())
				c.draw_polyline(points,Color(WIND,fade*0.45),2,false)
	if e>=0 and e<0.22:
		var u:=e/0.22
		var color:=Color("f6e9cd") if kind=="normal" else WIND
		for i in 5:
			var axis:=Vector2.from_angle(float(i)*TAU/5+0.1)
			line(c,target+axis*(3+u*18),target+axis*(8+u*27),Color(color,1-u),2)
		if e<0.065:glint(c,target,9*(1-u),1-u)

static func stance(c: CanvasItem,age: float,hit: float,kind: String,foot: Vector2,hand: Vector2,tip: Vector2) -> void:
	if age>0.25 and age<hit+0.22:
		var u:=clampf((age-0.25)/(hit-0.25),0,1)
		var alpha:=smoothstep(0.25,0.42,age)*(1-smoothstep(hit,hit+0.22,age))
		for i in 2:
			var points:=PackedVector2Array()
			for j in 12:
				var theta:=float(j)/11*PI*1.1+u*PI+i*PI
				points.append((hand+Vector2(cos(theta)*(27-u*15),sin(theta)*10)).round())
			c.draw_polyline(points,Color(WIND,alpha*0.6),2,false)
	if age>=hit and age<hit+0.23:
		var u:=(age-hit)/0.23
		glint(c,hand if kind=="iai" else tip,7*(1-u),1-u)
		if kind=="counter":line(c,hand,tip,Color(LIGHT,(1-u)*0.7),2)
