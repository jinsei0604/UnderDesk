extends "res://ally_awakening/core/sequence.gd"
func _init() -> void:
	character_id="healer"
	color=Color("f2cd55")
	duration=6.10
	release_time=3.35
	quiet_time=3.13
func shake_amplitude() -> float:return 4.0
func pose_at(t: float) -> String:
	if t<.4:return "b:0"
	if t<.66:return "s:4"
	if t<1.3:return "s:5"
	if t<3.35:return "s:6"
	if t<4.05:return "s:7"
	if t<4.5:return "s:6"
	if t<4.8:return "s:4"
	return "b:0"
func _petal(a: float,r: float,open: float,c: Color) -> void:
	var d:=Vector2(cos(a),sin(a))
	var s:=d.orthogonal()
	var p:=Vector2(0,-62)
	var pts:=PackedVector2Array()
	for side in [-1,1]:
		for j in 17:
			var q:=j/16.0 if side==-1 else 1-j/16.0
			pts.append(p+d*lerpf(35,r,q)+s*sin(q*PI)*open*side)
	poly(pts,c)
	pts.append(pts[0])
	line(pts,tint(Color("fff2b8"),c.a*1.8),2)
	line(PackedVector2Array([p+d*45,p+d*r*.9]),tint(Color("fff2b8"),c.a*.8),2)
func _draw() -> void:
	if not active:return
	var g:=gather()
	var p:=Vector2(0,-62)
	var white:=Color("fff5d2")
	if age<release_time:
		var b:=smoothstep(.4,2.9,age)
		# Eight lights take orbital paths, then a lightning-thread mandala resolves.
		for i in 8:
			var a:=i*TAU/8+age*.38
			var rad:=150-80*b
			var q:=p+Vector2(cos(a)*rad,sin(a)*rad*.65)
			star(q,4+b*4,tint(white,b))
			if age>1.6:
				_petal(a,105*b,15*b,tint(color,b*.20))
				bolt(q,p+Vector2(cos(a+.2),sin(a+.2))*42,i,tint(color,g*.40))
		ring(p,Vector2(104,104)*b,tint(color,b*.65),2,-age*.3,TAU*.92)
		ring(Vector2(0,-4),Vector2(100,24)*b,tint(color,b*.8),2,age*.4)
		for i in 24:
			var q:=fposmod(age*.31+i*.173,1)
			star(Vector2(sin(i*4.8)*100*(1-q),-q*180),2+q*2,tint(white,g*sin(q*PI)*.65))
		if age>=quiet_time:star(p,20,tint(white,1))
	else:
		var t:=age-release_time
		var k:=tail(1.9)
		var expansion:=smoothstep(0,.25,t)
		for i in 16:
			var a:=i*TAU/16+PI/16
			var d:=Vector2(cos(a),sin(a))
			ray(p+d*55,d,120+expansion*120,5,tint(color,k*.2))
		for i in 8:
			var a:=i*TAU/8-PI/8
			_petal(a,75+expansion*150,13+expansion*20,tint(color,k*.35))
			var edge:=p+Vector2(cos(a),sin(a))*(75+expansion*150)
			star(edge,9*k,tint(white,k))
			if t<.42:bolt(p+Vector2(cos(a),sin(a))*55,edge,i+2,tint(white,(1-t/.42)*.8),3)
		# A single lightning pillar is the impact; light petals remain after it.
		if t<.42:
			var w:=22*(1-t/.42)
			poly(PackedVector2Array([Vector2(-w,8),Vector2(-w*.6,-310),Vector2(w*.6,-310),Vector2(w,8)]),tint(white,(1-t/.42)*.65))
		for i in 3:
			var q:=maxf(0,t-i*.15)
			ring(p,Vector2.ONE*(45+sqrt(q)*200),tint(color,maxf(0,1-q/1.2)*.55),3)
		for i in 30:
			var a:=i*2.399
			var q:=p+Vector2(cos(a),sin(a))*(100+t*95)+Vector2(0,-t*24)
			star(q,3+(i%3),tint(white,k*.8))
