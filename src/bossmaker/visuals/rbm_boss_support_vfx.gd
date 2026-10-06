extends Node2D
## UI-semantic support colors; never read the boss's attack attribute.
const COLORS={"buff":Color("ef4847"),"heal":Color("71da87")}
var origin:=Vector2(840,490)
var age:=-1.0
var mode:="buff"

func pixel_rect(p: Vector2,extent: Vector2,c: Color) -> void:
	draw_rect(Rect2((p/4).floor(),extent),c)

func _draw() -> void:
	if age<.22 or age>2.8: return
	var base: Color=COLORS[mode]
	var strength:=smoothstep(.22,.65,age)*(1-smoothstep(2.05,2.8,age))
	# Sparse square motes ascend independently. No flame contours or leaf shapes.
	for i in range(22):
		var delay:=fmod(i*.173,.95)
		var t:=age-.24-delay
		if t<0 or t>1.62: continue
		var x:=sin(i*2.39)*93
		var y:=-12-fmod(i*17,54)-t*(50+fmod(i*11,36))
		var p:=origin+Vector2(x+sin(t*1.7+i)*5,y)
		var c:=base.lightened(.24 if i%4==0 else 0)
		c.a=strength*smoothstep(0,.13,t)*(1-smoothstep(1.15,1.62,t))*.82
		pixel_rect(p,Vector2(2,2) if i%5==0 else Vector2.ONE,c)
		if i%3==0:
			c.a*=.26
			pixel_rect(p+Vector2(0,8),Vector2(1,2),c)
	# Short, broken upward accents frame the body rather than forming a magic circle.
	for spec in [Vector3(-93,-32,24),Vector3(-77,-92,32),Vector3(79,-42,36),Vector3(97,-112,20)]:
		var c:=base
		c.a=strength*.20
		var p:=origin+Vector2(spec.x,spec.y-age*10)
		pixel_rect(p,Vector2(1,spec.z/4),c)
		c.a*=.45
		pixel_rect(p+Vector2(4,8),Vector2(1,spec.z/8),c)
	# One small pressure-free pulse: an incomplete soft border around the torso.
	var pulse:=age-1.50
	if pulse>=0 and pulse<.42:
		var q:=pulse/.42
		var rx:=76+27*q
		var ry:=88+20*q
		var alpha:=sin(q*PI)*.43
		for y in range(-112,113,4):
			for x in range(-112,113,4):
				var v:=Vector2(x/rx,y/ry)
				var d:=v.length()
				if d<.955 or d>1.03 or sin(v.angle()*7+.8)>.45: continue
				var c:=base.lightened(.24)
				c.a=alpha
				pixel_rect(origin+Vector2(x,y-96),Vector2.ONE,c)
