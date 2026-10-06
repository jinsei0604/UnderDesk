extends Node2D
const Motion=preload("res://src/bossmaker/visuals/rbm_ghost_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
var kind:="single"
var attribute:="NEUTRAL"
var age:=-1.0
var motion: RefCounted
var state: Dictionary={}
var frames: Array[Texture2D]=[]
var foot:=Vector2(256,460)
var canvas:=Vector2(512,512)
var pixel_scale:=160.0/412.0
var targets: Array[Vector2]=[]

func configure(stage: Control) -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets_bossmaker/battle/ghost/frames.json"))
	foot=Vector2(data.foot[0],data.foot[1])
	canvas=Vector2(data.canvas[0],data.canvas[1])
	pixel_scale=stage.Assets.display_height("ghost")/float(data.body_height)
	for i in range(12): frames.append(stage.Assets.texture("ghost",i))

func advance(t: float) -> void:
	age=t
	state=motion.sample(kind,t)
	queue_redraw()

func color_for() -> Color:
	if kind=="buff": return Color("ef4847")
	if kind=="heal": return Color("71da87")
	return Palette.color_for(attribute)

func segment(a: Vector2,b: Vector2,c: Color,width: float=2.0) -> void:
	draw_line(a.snapped(Vector2(2,2)),b.snapped(Vector2(2,2)),c,width,false)
func poly(points: Array,c: Color) -> void:
	var p=PackedVector2Array()
	for v in points:
		var q=Vector2(v).snapped(Vector2(2,2))
		if not p.has(q): p.append(q)
	if p.size()>=3 and not Geometry2D.triangulate_polygon(p).is_empty(): draw_colored_polygon(p,c)

func spirit(pos: Vector2,c: Color,size: float,opacity: float,wave_phase: float) -> void:
	if opacity<=0: return
	draw_set_transform(pos.snapped(Vector2(2,2)),0,Vector2.ONE*size)
	var curl=sin(wave_phase)*4
	var outline=c.darkened(.52)
	outline.a=opacity*.85
	poly([Vector2(-12,-6),Vector2(-8,-14),Vector2(6,-14),Vector2(12,-6),Vector2(12,2),Vector2(20+curl,10),Vector2(10,12),Vector2(4,8),Vector2(0,16),Vector2(-6,10),Vector2(-12,6)],outline)
	var fill=c
	fill.a=opacity
	poly([Vector2(-10,-6),Vector2(-6,-12),Vector2(4,-12),Vector2(10,-6),Vector2(8,4),Vector2(16+curl,8),Vector2(8,8),Vector2(4,6),Vector2(0,12),Vector2(-4,8),Vector2(-10,4)],fill)
	draw_rect(Rect2(-6,-6,4,5),Color(.055,.055,.085,opacity))
	draw_rect(Rect2(2,-6,4,5),Color(.055,.055,.085,opacity))
	draw_set_transform(Vector2.ZERO)

func ghost(s: Dictionary,extra_alpha: float=1.0) -> void:
	if s.alpha<=0: return
	var sc: Vector2=s.scale
	if s.flip: sc.x=-sc.x
	draw_set_transform(Vector2(s.foot).round(),0,sc)
	var tint=Color(1,1,1,s.alpha*extra_alpha)
	var texture=frames[int(s.pose)]
	if s.ripple<.01:
		draw_texture_rect(texture,Rect2((-foot*pixel_scale).round(),canvas*pixel_scale),false,tint)
	else:
		# Nearest horizontal bands make a brief spectral ripple without blurring the art.
		for y in range(0,int(canvas.y),8):
			var offset=roundf(sin(y*.07-age*24)*s.ripple/2)*2
			var rect=Rect2((Vector2(0,y)-foot)*pixel_scale+Vector2(offset,0),Vector2(canvas.x,8)*pixel_scale)
			draw_texture_rect_region(texture,rect,Rect2(0,y,canvas.x,8),tint)
	draw_set_transform(Vector2.ZERO)

func burst(pos: Vector2,t: float,c: Color,magnitude: float=1.0) -> void:
	if t<0 or t>.44: return
	var q=t/.44
	var col=c
	col.a=1-smoothstep(.35,1,q)
	for i in range(16):
		var a=float(i)*TAU/16
		var b=float(i+1)*TAU/16
		var r=Vector2(17+q*44,24+q*55)*magnitude
		if i%4!=0: segment(pos+Vector2(cos(a),sin(a))*r,pos+Vector2(cos(b),sin(b))*r,col,4 if q<.3 else 2)
	for i in range(9):
		var a=i*TAU/9
		var d=Vector2(cos(a),sin(a))
		segment(pos+d*(9+q*38)*magnitude,pos+d*(26+q*60)*magnitude,col,2)
	if t<.09:
		var pale=c.lightened(.65)
		pale.a=(1-t/.09)*.8
		poly([pos+Vector2(-15,0),pos+Vector2(0,-30),pos+Vector2(15,0),pos+Vector2(0,30)],pale)

func swarm_point(i: int,t: float) -> Vector2:
	var center=motion.home+Vector2(0,-111)
	var a=float(i)*TAU/maxi(targets.size()*3,1)
	var origin=center+Vector2(cos(a)*116,sin(a)*78)
	if t<1.04: return origin+Vector2(sin(t*6+i)*4,cos(t*5+i)*4)
	var q=clampf((t-1.04)/.58,0,1)
	var target=targets[i%targets.size()]+Vector2(0,(i/targets.size()-1)*12)
	if t<=1.62:
		return origin.lerp(target,q)+Vector2(0,sin(q*PI)*(-52+float(i%3)*52))
	return target+Vector2(-180*(t-1.62)/.36,sin(i*3.2)*35*(t-1.62)/.36)

func absorption_point(i: int,t: float,count: int,late: bool=false) -> Dictionary:
	var start=2.03+float(i)*.055 if late else .50+float(i)*.022
	var length=.66 if late else 1.50
	var q=clampf((t-start)/length,0,1)
	var a=float(i)*TAU/count+q*TAU*(1.1 if late else 1.4)
	var radius=(100 if late else 128)*pow(1-q,1.15)
	var center=Vector2(state.foot)+Vector2(0,-83)
	var p=center+Vector2(cos(a)*radius,sin(a)*radius*.68)
	var fade=smoothstep(.27,.55,t)*(1-smoothstep(.88,1,q))
	return {"point":p,"alpha":fade,"q":q}

func soul_effects(c: Color) -> void:
	if kind=="all":
		if age>=.38 and age<2.05:
			for i in range(targets.size()*3):
				var opacity=smoothstep(.38,.82,age)*(1-smoothstep(1.85,2.05,age))
				if age>1.04:
					for j in range(5):
						var col=c
						col.a=opacity*(.48-j*.08)
						segment(swarm_point(i,age-j*.025),swarm_point(i,age-(j+1)*.025),col,4)
				spirit(swarm_point(i,age),c,1.05+float(i%3)*.13,opacity,age*14+i)
		for i in range(4):
			var s=absorption_point(i,age,4,true)
			if age>=.5 and age<2.9: spirit(s.point,c,.80,s.alpha*.8,age*9+i)
		for target in targets: burst(target,age-Motion.ALL_HIT,c,.80)
	elif kind in ["buff","heal"]:
		if age>=.27 and age<2.42:
			for i in range(18):
				var s=absorption_point(i,age,18)
				for j in range(4):
					var previous=absorption_point(i,age-(j+1)*.025,18)
					var col=c
					col.a=s.alpha*(.3-j*.065)
					segment(s.point,previous.point,col,2)
				spirit(s.point,c,.66+float(i%3)*.10,s.alpha,age*10+i)
		burst(Vector2(state.foot)+Vector2(0,-83),age-2.40,c,.90)


func _draw() -> void:
	if state.is_empty(): return
	if kind=="single" and age>=1.32 and age<1.68:
		for i in range(4,0,-1): ghost(motion.sample(kind,age-i*.025),.07+float(4-i)*.035)
	ghost(state)
	var c=color_for()
	if kind=="single":
		if not targets.is_empty(): burst(targets[0],age-Motion.SINGLE_HIT,c,1.15)
		for t in [1.04,2.25]:
			var h=age-float(t)
			if h>=0 and h<.25:
				var center=(motion.target_foot+Vector2(-132,-80)) if t==1.04 else (motion.home-Vector2(0,80))
				for i in range(8):
					var a=i*TAU/8
					var p=center+Vector2(cos(a)*40,sin(a)*70)*(1-h/.25)
					segment(p,p+Vector2(0,-8),Color(.7,.73,.76,(1-h/.25)*.65),2)
	else: soul_effects(c)
