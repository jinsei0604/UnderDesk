extends RefCounted
## Visual-only IAI mantle. No timer guesses: lifetime comes from the resolved state.
const DEEP=Color("365e55")
const WIND=Color("a4d6af")
const CORE=Color("efffdc")

static func is_active(state: Dictionary) -> bool:
	return not bool(state.get("is_downed",false)) and float(state.get("next_attack_bonus_multiplier",1.0))>1.0

static func ribbon(c: CanvasItem,center: Vector2,radius: Vector2,start: float,sweep: float,width: float,alpha: float,tilt: float=0.0) -> void:
	if alpha<=0.001 or width<0.5:return
	var outer:=PackedVector2Array();var inner:=PackedVector2Array();var core:=PackedVector2Array()
	for i in 17:
		var u:=float(i)/16
		var a:=start+sweep*u
		var p: Vector2=center+(Vector2(cos(a),sin(a))*radius).rotated(tilt)
		var n:=Vector2(cos(a),sin(a)).rotated(tilt)
		var w:=width*pow(sin(u*PI),0.8)
		# Preserve non-degenerate contour geometry for triangulation. Rendering
		# is still unfiltered/aliased; rounding subpixel tail widths collapses it.
		outer.append(p+n*w*0.5);inner.append(p-n*w*0.5)
		core.append((p+n*w*0.15).round())
	var shape:=outer.duplicate()
	for i in range(15,0,-1):shape.append(inner[i])
	c.draw_colored_polygon(shape,Color(WIND,alpha*0.8))
	c.draw_polyline(outer,Color(DEEP,alpha*0.75),2,false)
	c.draw_polyline(core,Color(CORE,alpha),2,false)

static func mantle(c: CanvasItem,foot: Vector2,hand: Vector2,tip: Vector2,t: float,alpha: float,back: bool=false) -> void:
	if alpha<=0.001:return
	# Broken ribbons leave the face and torso readable; no full glowing ring.
	var phase:=t*2.7
	if back:
		ribbon(c,foot+Vector2(0,-36),Vector2(42,18),phase+PI,PI*0.80,6,alpha*0.66,-0.25)
		return
	ribbon(c,foot+Vector2(0,-32),Vector2(42,17),phase,PI*0.87,6,alpha*0.82,-0.25)
	ribbon(c,foot+Vector2(0,-68),Vector2(32,11),phase*0.87+2.4,PI*0.72,4,alpha*0.62,-0.3)
	if hand.distance_to(tip)>12:
		var axis:=tip-hand;var n:=axis.normalized().orthogonal()
		var path:=PackedVector2Array()
		for i in 13:
			var u:=float(i)/12
			path.append((hand+axis*u+n*sin(u*TAU-phase*2)*4*sin(u*PI)).round())
		c.draw_polyline(path,Color(DEEP,alpha*0.65),6,false)
		c.draw_polyline(path,Color(WIND,alpha*0.9),4,false)
		c.draw_line(hand.round(),tip.round(),Color(CORE,alpha*0.85),2,false)

static func attack(c: CanvasItem,hand: Vector2,tip: Vector2,target: Vector2,t: float,release: float,hit: float,wide: bool) -> void:
	var e:=t-hit
	if t<release+0.012 or e>0.38:return
	var u:=smoothstep(release+0.012,hit+0.09,t)
	var alpha:=1-smoothstep(hit+0.08,hit+0.38,t)
	# Its leading end starts at the actual blade; only after contact does the
	# released gust expand at the target. The wide slash has a horizontal wake.
	var center:=hand.lerp(target,smoothstep(release,hit+0.06,t))
	var reach:=maxf(hand.distance_to(tip),26)
	var radius:=Vector2(lerpf(reach,115.0 if wide else 64.0,u),lerpf(reach*0.7,27.0 if wide else 56.0,u))
	var bearing:=(tip-hand).angle()
	var start:=lerpf(bearing-1.15,-0.9 if wide else -1.7,u)
	ribbon(c,center,radius,start,lerpf(0.3,PI*1.12,u),12 if wide else 10,alpha,-0.09 if wide else -0.20)
	if e>0.015:
		ribbon(c,target,Vector2(131 if wide else 76,35 if wide else 64),-1.4+u*0.4,PI*0.67,5,alpha*0.65,-0.12)

static func support(c: CanvasItem,foot: Vector2,t: float,hit: float) -> void:
	var e:=t-hit
	if e<0 or e>0.32:return
	var u:=e/0.32
	ribbon(c,foot+Vector2(0,-41),Vector2(40+u*16,25+u*12),-1.6+u*2.0,PI*1.18,7*(1-u),1-u,-0.25)
