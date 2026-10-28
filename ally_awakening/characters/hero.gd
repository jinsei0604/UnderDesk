extends "res://ally_awakening/core/sequence.gd"
## Existing gather retained; release is a red-gold heat shell and cooling embers.
func _init() -> void:
	character_id="hero"
	color=Color("ef4847")
	duration=5.60
	release_time=3.00
	quiet_time=2.80
func pose_at(t: float) -> String:
	if t<.35:return "b:0"
	if t<.53:return "b:6"
	if t<release_time:return "s:12"
	if t<4.55:return "s:14"
	if t<4.80:return "s:15"
	return "b:0"
func _tongue(p: Vector2,w: float,h: float,phase: float,a: float,lean: float=0.0) -> void:
	if h<3 or w<2 or a<.01:return
	var tick:=floorf(age*15)/15.0
	for layer in 3:
		var scale_w: float=[1.0,.66,.30][layer]
		var scale_h: float=[1.0,.74,.44][layer]
		var c: Color=[Color("b52926"),Color("f36d23"),Color("ffce63")][layer]
		var height:=h*scale_h
		for row in range(0,int(height),2):
			var q:=row/height
			var bend:=(sin(q*6.1+phase+tick*7)*.22*q+lean*q*q)*w
			var broad:=pow(1-q,.65)*(.72+.24*sin(q*8+phase+tick*9))
			var left:=p.x+bend-w*scale_w*broad
			var right:=p.x+bend+w*scale_w*broad*(.84+.16*cos(q*10+phase))
			var origin:=Vector2(floorf(left/2)*2,floorf((p.y-row)/2)*2)
			draw_rect(Rect2(origin,Vector2(maxf(2,ceilf((right-left)/2)*2),2)),tint(c,a))
func _draw() -> void:
	if not active:return
	var gold:=Color("ffd67d")
	if age<release_time:
		var build:=smoothstep(.25,2.65,age)
		var squeeze:=smoothstep(quiet_time,release_time,age)
		for i in 7:
			var x:=(i-3)*26.0*(1-squeeze*.58)
			var h:=(34+float(i%3)*17)*build*(1+squeeze*.45)
			_tongue(Vector2(x,4),12*build,h,i*1.7,build*.9,-signf(x)*.5)
		for i in 30:
			var q:=fposmod(age*.46+i*.173,1)
			var p:=Vector2(sin(i*2.399)*(145-105*q)*build,-q*150)
			_tongue(p,3+q*2,9+q*12,i,build*sin(q*PI),-signf(p.x)*.5)
		if squeeze>0:_tongue(Vector2(0,-125),8+8*squeeze,26+24*squeeze,0,squeeze)
	else:
		var t:=age-release_time
		var center:=Vector2(0,-64)
		# A hot pressure shell opens outward. No flame columns or radial spokes.
		for layer in 3:
			var q:=t-layer*.085
			if q<0:continue
			var fade:=1-smoothstep(.22,1.12,q)
			var radius:=35+pow(q,.58)*230
			var width:=(38-layer*5)*fade
			_heat_shell(center,Vector2(radius,radius*.78),width,layer*.43,Color("bf302c"),fade*.90)
			_heat_shell(center,Vector2(radius-7,radius*.78-6),width*.53,layer*.43,Color("ff792d"),fade)
			_heat_shell(center,Vector2(radius-14,radius*.78-12),maxf(2,width*.16),layer*.43,Color("ffe1a0"),fade*.95)
		# Glowing fragments detach from the shell and cool through gold to crimson.
		for i in 54:
			var a:=i*2.399
			var speed:=95+float(i%7)*19
			var d:=Vector2(cos(a),sin(a)*.72)
			var p:=center+d*(28+t*speed)+Vector2(0,-26*t+t*t*24)
			var f:=1-smoothstep(.35+float(i%4)*.1,1.75+float(i%3)*.13,t)
			var size:=Vector2(4+i%3*2,4+i%2*2)*f
			var c:=Color("ffcb68").lerp(Color("d83a2f"),clampf(t/1.6,0,1))
			draw_rect(Rect2(p.snapped(Vector2(2,2)),size.snapped(Vector2(2,2))),tint(c,f))
		# Two low pressure fronts settle into the existing red persistent aura.
		for j in 2:
			var q:=maxf(0,t-j*.13)
			var f:=1-smoothstep(.25,1.25,q)
			_heat_shell(Vector2(0,2),Vector2(55+q*205,14+q*42),12*f,j*.7,Color("f26932"),f*.7)
func _heat_shell(p: Vector2,r: Vector2,width: float,offset: float,c: Color,alpha: float) -> void:
	if alpha<.01 or width<1:return
	# Filled facets carry mass; slight crenellation reads as pixel heat, not thin rays.
	for i in 72:
		var a:=offset+i*TAU/72
		var b:=offset+(i+1)*TAU/72
		var notch:=1.0+sin(i*2.7+floorf(age*12))*.018
		var da:=Vector2(cos(a),sin(a))
		var db:=Vector2(cos(b),sin(b))
		var inner:=Vector2(maxf(2,r.x-width),maxf(2,r.y-width*.78))
		poly(PackedVector2Array([p+da*r*notch,p+db*r*notch,p+db*inner,p+da*inner]),tint(c,alpha))
