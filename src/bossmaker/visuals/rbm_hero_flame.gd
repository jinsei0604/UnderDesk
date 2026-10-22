extends RefCounted
## Hero-only weapon fire. Gather is shared verbatim by Flame Wrap and the finisher.
## Lifetime comes exclusively from the presenter's detached combat snapshot.
static func is_active(state: Dictionary, actor_key: String) -> bool:
	var unit: Dictionary = state.get("party", {}).get(actor_key, {})
	return unit.get("character_id", "") == "hero" and RBMConstants.timed_effect_active(unit.get("timed_effects", {}), "atk_buff", int(state.get("turn", 0)))

static func draw_gather(canvas: CanvasItem, age: float, home: Vector2, hand: Vector2, tip: Vector2) -> void:
	if age < 0.23 or age>0.94: return
	var power := smoothstep(0.23,0.40,age)*(1-smoothstep(0.75,0.94,age))
	var gather:=smoothstep(0.23,0.32,age)*(1-smoothstep(0.45,0.61,age))
	for j in 5:
		var x:=float(j-2)*11
		var base:=home+Vector2(x,-22-absf(x)*0.4)
		var height:=16+sin(age*19+j*1.7)*7
		var points:=PackedVector2Array([base+Vector2(-3,0),base+Vector2(-5,-height*0.6),base+Vector2(2,-height),base+Vector2(5,-height*0.35),base+Vector2(3,0)])
		for n in points.size():points[n]=points[n].round()
		canvas.draw_colored_polygon(points,Color(1,0.29,0.035,gather*0.8))
	for i in 16:
		var phase := clampf((age-0.24-float(i)*0.012)/0.34,0,1)
		var origin := home+Vector2(sin(float(i)*2.4)*26,-20-float(i%5)*12)
		var p := origin.lerp(hand,phase)+Vector2(sin(phase*PI)*10,-sin(phase*PI)*12)
		if phase>0 and phase<1: canvas.draw_rect(Rect2(p.round(),Vector2(2,3)),Color(1,0.44,0.08,power))
	if age>0.43:
		var fill := smoothstep(0.43,0.61,age)
		canvas.draw_line(hand.round(),hand.lerp(tip,fill).round(),Color(0.9,0.2,0.03,power*0.7),8,false)
		canvas.draw_line(hand.round(),hand.lerp(tip,fill).round(),Color(1,0.82,0.30,power),2,false)
		for i in 6:
			var p := hand.lerp(tip,float(i)/6.0)+Vector2(sin(age*27+i*2)*4,-4)
			canvas.draw_rect(Rect2(p.round(),Vector2(2,4)),Color(1,0.47,0.05,power))

static func draw_blade(canvas: CanvasItem, hand: Vector2, tip: Vector2, time: float, strength: float = 1.0) -> void:
	if strength <= 0: return
	var axis := (tip-hand).normalized()
	var side := axis.orthogonal()
	# Thin translucent flame keeps the original blade silhouette readable.
	canvas.draw_line(hand.round(),tip.round(),Color(1,0.23,0.025,0.65*strength),7,false)
	canvas.draw_line(hand.round(),tip.round(),Color(1,0.79,0.30,0.8*strength),2,false)
	for i in 6:
		var phase := fmod(time*2.0+float(i)*0.163,1.0)
		var p := hand.lerp(tip,0.12+0.84*float(i)/6.0)
		var direction := 1.0 if i%2==0 else -1.0
		var edge := p+side*direction*(3+sin(time*9+i*2)*1.5)
		var end := edge+Vector2(0,-5-phase*4)+axis*3
		var a: Vector2=(p-side*2).round()
		var b: Vector2=(p+side*2).round()
		var c: Vector2=end.round()
		if absf((b-a).cross(c-a))>=1.0:
			canvas.draw_colored_polygon(PackedVector2Array([a,b,c]),Color(1,0.39+phase*0.15,0.04,(0.8-phase*0.4)*strength))
