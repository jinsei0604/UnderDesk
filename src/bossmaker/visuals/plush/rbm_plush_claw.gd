extends RefCounted
## Claw flight -> contact -> local space split. Pure presentation, no battle state.
## References: Knight's layered cutting edge and Musha's flying stroke / arrival split.
const FX=preload("res://src/bossmaker/visuals/plush/rbm_plush_fx.gd")
const LAUNCH=1.17
const IMPACT=1.50
const ORIGIN=Vector2(646,370)
const AXIS=Vector2(-.42,.907524)
const SIDE=Vector2(.907524,.42)

static func opening(t: float) -> float:
	return smoothstep(IMPACT,IMPACT+.10,t)*(1-smoothstep(IMPACT+.52,IMPACT+1.05,t))

static func claw(ci: CanvasItem,c: Vector2,travel: float,alpha: float,flat: float=0.0) -> void:
	for digit in range(3):
		var center:=c+SIDE*(digit-1)*19
		var length:=105+travel*31-float(digit%2)*11
		# A broad hooked cutting ribbon, dark back -> purple body -> narrow pale edge.
		for layer in range(3):
			var outer: Array=[];var inner: Array=[]
			for j in range(19):
				var f:=j/18.0;var taper:=pow(maxf(0,sin(f*PI)),.75)
				var bow: float=(25+travel*9)*sin(f*PI)*(1-flat)
				var p:=center+AXIS*(f-.5)*length-SIDE*bow
				var width: float=(17.0 if layer==0 else (9.0 if layer==1 else 2.0))*(1-flat*.85)*taper
				outer.append(p);inner.push_front(p+SIDE*width)
			var col: Color=[Color("0a0712"),Color("68477c"),Color("c7b3ce")][layer]
			FX.poly(ci,outer+inner,Color(col,alpha))

static func draw(ci: CanvasItem,t: float,target: Vector2,origin: Vector2=ORIGIN) -> void:
	var contact:=target+Vector2(0,-48)
	if t>=LAUNCH and t<IMPACT:
		var q:=clampf((t-LAUNCH)/(IMPACT-LAUNCH),0,1)
		var travel:=pow(q,1.15)
		var c:=origin.lerp(contact,travel)
		# Short remnants trail behind the attack; no stationary portal at the caster.
		for j in range(2,0,-1):
			var oldq:=maxf(0,travel-j*.12)
			claw(ci,origin.lerp(contact,oldq),oldq,.16/float(j))
		claw(ci,c,travel,smoothstep(0,.08,q))
		for j in range(5):
			var p:=c+Vector2(22+j*8,-22+j*13)
			FX.poly(ci,[p+Vector2(-3,-2),p+Vector2(6,0),p+Vector2(-1,3)],Color(.30,.19,.38,(1-q)*.7))
	if t<IMPACT or t>IMPACT+1.35:return
	var u:=t-IMPACT
	# Flatten the travelling shape on contact, then the screen split takes over.
	if u<.14:claw(ci,contact,1,1-smoothstep(.06,.14,u),smoothstep(0,.07,u))
	# Local impact crown and solid chips, all born at the actual target position.
	for j in range(12):
		var q:=clampf(u/(.44+(j%3)*.12),0,1)
		if q>=1:continue
		var angle:=j*2.399
		var dir:=Vector2(cos(angle),sin(angle))
		var p:=contact+dir*(10+pow(q,.65)*(35+j%4*12))+Vector2(0,q*q*32)
		var w: float=(3.0+j%3)*(1-q*.65)
		FX.poly(ci,[p-dir*7-SIDE*w,p+dir*8,p+SIDE*w,p-dir*5+SIDE*w],Color(.39,.27,.46,1-q))
		if j%3==0:FX.poly(ci,[p-dir*7-SIDE*w,p+dir*8,p-dir*4],Color(.72,.61,.76,1-q))
	# An irregular dark landing scar fades with the split, never before arrival.
	var fade:=1-smoothstep(.45,1.25,u)
	var g:=target+Vector2(-3,0)
	FX.poly(ci,[g+Vector2(-50,-7),g+Vector2(-21,-15),g+Vector2(-2,-10),g+Vector2(20,-13),g+Vector2(42,2),g+Vector2(13,9),g+Vector2(-5,5),g+Vector2(-27,9)],Color(.045,.027,.065,fade*.8))
