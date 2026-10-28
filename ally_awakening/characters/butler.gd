extends "res://ally_awakening/core/sequence.gd"
func _init() -> void:
	character_id="butler"
	color=Color("509cf5")
	duration=5.90
	release_time=3.25
	quiet_time=2.95
func shake_amplitude() -> float:return 4.0
func pose_at(t: float) -> String:
	if t<.48:return "b:0"
	if t<.72:return "s:1"
	if t<2.7:return "s:2"
	if t<3.25:return "s:3"
	if t<3.40:return "s:3"
	if t<4.95:return "s:1"
	return "b:0"
func _crystal(p: Vector2,w: float,h: float,a: float) -> void:
	diamond(p,w,h,tint(Color("244c90"),a*.75))
	poly(PackedVector2Array([p+Vector2(0,-h),p+Vector2(w,0),p+Vector2(0,h*.4)]),tint(color,a))
	line(PackedVector2Array([p+Vector2(-w,0),p+Vector2(0,-h),p+Vector2(w,0)]),tint(Color("d0f7ff"),a),2)
	line(PackedVector2Array([p+Vector2(0,-h),p+Vector2(-w*.22,0),p+Vector2(0,h*.4)]),tint(Color("d0f7ff"),a*.6),2)
	line(PackedVector2Array([p+Vector2(-w,0),p+Vector2(w,0)]),tint(Color("a0daff"),a*.4),2)
func _frost_arm(a: float,r: float,alpha: float) -> void:
	var d:=Vector2(cos(a),sin(a))
	var side:=d.orthogonal()
	var center:=Vector2(0,-67)
	line(PackedVector2Array([center+d*36,center+d*r]),tint(color,alpha),3)
	for j in range(2,6):
		var p:=center+d*r*j/7.0
		for s in [-1,1]:
			line(PackedVector2Array([p,p-d*15+side*s*(r*.13)]),tint(Color("c6eaff"),alpha*.8),2)
func _draw() -> void:
	if not active:return
	var g:=gather()
	var pale:=Color("daf7ff")
	var center:=Vector2(0,-67)
	if age<release_time:
		# Frost traces a precise hexagonal seal; six crystal spires lock in sequence.
		var built:=smoothstep(.4,2.7,age)
		var compress:=smoothstep(quiet_time,release_time,age)
		for i in 6:
			var a:=i*TAU/6
			var r:=(96-74*compress)*built
			var p:=center+Vector2(cos(a)*r,sin(a)*r*.78)
			var b:=clampf((age-.5-i*.18)*1.6,0,1)
			_crystal(p,15*b*(1-compress*.65),47*b*(1-compress*.6),built)
			line(PackedVector2Array([center+Vector2(cos(a),sin(a))*(32*built),p]),tint(color,built*.4))
			_frost_arm(a,130*built*(1-compress*.75),built*.6)
			ring(center,Vector2(115,94)*built,tint(color,built*.6),2,a,.22)
		for i in 30:
			var q:=fposmod(i*.13+age*.26,1)
			var p:=Vector2(sin(i*7.1)*140*(1-q),-q*150)
			diamond(p,2,4,tint(pale,g*sin(q*PI)*.75))
		ring(Vector2.ZERO,Vector2(105,27)*built,tint(color,built*.75),2)
		if compress>0:star(center,8+compress*15,tint(pale,compress))
	else:
		var t:=age-release_time
		var k:=tail(1.65)
		for i in 12:
			var a:=i*TAU/12
			var d:=Vector2(cos(a),sin(a)*.8)
			var p:=center+d*(30+pow(t,.6)*210)
			_crystal(p,10*k,35*k,k)
			line(PackedVector2Array([center+d*65,p]),tint(color,k*.6),3)
			if i%2==0:_frost_arm(a,155+sqrt(t)*120,k*.65)
		for i in 3:
			var q:=maxf(0,t-i*.10)
			ring(center,Vector2(1,.8)*(45+sqrt(q)*260),tint(pale,maxf(0,1-q/1.0)*.8),maxf(2,6-q*5))
		for i in 36:
			var d:=Vector2(cos(i*2.399),sin(i*2.399))
			var p:=center+d*(45+t*180)+Vector2(0,t*t*70)
			diamond(p,3*k,8*k,tint(pale,k*.9))
		# Low frost glides outward and thins rather than obscuring the face.
		for i in 7:
			ring(Vector2(sin(i*3.3)*110,5+i%2*7),Vector2(30+t*65,5+t*8),tint(color,k*.12),6)
