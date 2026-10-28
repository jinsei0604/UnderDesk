extends "res://ally_awakening/core/sequence.gd"
func _init() -> void:
	character_id="samurai"
	color=Color("a4f255")
	duration=5.35
	release_time=2.85
	quiet_time=2.54
func pose_at(_t: float) -> String:
	return "s:18"
func _draw() -> void:
	if not active:return
	var g:=gather()
	var white:=Color("eaffc9")
	var center:=Vector2(0,-55)
	if age<release_time:
		# Wind planes narrow to a blade-line. The deliberate pause is 310ms.
		var b:=smoothstep(.25,2.5,age)
		for i in 6:
			var y:=-18-i*24
			var r:=150-i*12
			var squash:=1-smoothstep(2.15,quiet_time,age)*.92
			ring(Vector2(0,y*squash-25*(1-squash)),Vector2(r,18)*b,tint(color,g*.8),2,age*(1.1+i*.07)+i,PI*1.2)
		for i in 24:
			var q:=fposmod(age*.55+i*.173,1)
			var a:=i*2.399+q*1.8
			var p:=center+Vector2(cos(a)*180,sin(a)*90)*(1-q)
			line(PackedVector2Array([p,p+Vector2(16, -5)]),tint(white,g*sin(q*PI)*.7))
		if age>=quiet_time:
			var c:=smoothstep(quiet_time,release_time,age)
			line(PackedVector2Array([Vector2(-85,-52),Vector2(130,-52)]),tint(white,.65+c*.35),2)
			star(Vector2(32,-52),8+c*9,tint(white,1))
	else:
		var t:=age-release_time
		var k:=tail(1.5)
		# One long cut, then two oblique wind wakes open from the slash.
		if t<.30:
			var w:=14*(1-t/.3)
			poly(PackedVector2Array([center+Vector2(-340,-w),center+Vector2(380,-22),center+Vector2(30,w)]),tint(white,1-t/.3))
		for i in 3:
			var q:=maxf(0,t-i*.09)
			var r:=50+pow(q,.55)*260
			var ribbon:=PackedVector2Array()
			for j in 33:
				var a:=-.8-i*.2+j/32.0*PI*1.5
				ribbon.append(center+Vector2(cos(a)*r,sin(a)*r*.46))
			for j in range(32,-1,-1):
				var a:=-.8-i*.2+j/32.0*PI*1.5
				var w:=sin(j/32.0*PI)*18*k
				ribbon.append(center+Vector2(cos(a)*(r-w),sin(a)*(r*.46-w)))
			poly(ribbon,tint(color,k*.20))
			ring(center+Vector2(t*35,-t*12),Vector2(r,r*.46),tint(color,maxf(0,1-q/1.2)),maxf(2,8-q*6),-.8-i*.2,PI*1.5)
		for i in 30:
			var a:=i*2.399
			var d:=Vector2(cos(a),sin(a)*.45)
			var p:=center+d*(80+t*260)
			ray(p,d,20+20*k,2,tint(white,k*.8))
		# Low ribbons trail behind the cutting plane, never a full-screen strobe.
		for i in 3:
			ring(Vector2(0,-4-i*18),Vector2(90+t*95,17),tint(color,k*.5),2,-t*2+i,PI)
