extends Node2D
## Pixel-grid ink, gunfire, ruptured paving and smoke; no detached-arm animation.
const Motion=preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
## Impact sheets (8x7 cells of 320px) each action draws for its hits of power>=1.1; every other
## hit is drawn procedurally. Keep in step with the powers impact() is called with in _draw().
const IMPACT_STYLES := {"single":["duel"],"awakened_single":["first","heavy"],"awakened_all":["first"]}
var kind := "single"
var age := 0.0
var boss := Vector2.ZERO
var target := Vector2.ZERO
var feet: Array[Vector2]=[]
var points: Array[Vector2]=[]
var party_feet: Array[Vector2]=[]
var canvas_size := Vector2(752,424)
var attribute := "NEUTRAL"
var awakened := false
var data: Dictionary
## The stage's rbm_gentleman_impact_sheets.gd; without one the sheets are loaded here.
var impact_sheets: Node
var _impact_textures: Dictionary={}
var _soft_smoke: GradientTexture2D

static func impact_path(attribute: String, style: String) -> String:
	var attr:=attribute.to_lower()
	if not Palette.COLORS.has(attribute):attr="neutral"
	return Motion.ROOT+"impacts/"+attr+"_"+style+".png"

func _ready() -> void:
	_soft_smoke=GradientTexture2D.new()
	_soft_smoke.width=32;_soft_smoke.height=32
	_soft_smoke.fill=GradientTexture2D.FILL_RADIAL
	_soft_smoke.fill_from=Vector2(.5,.5);_soft_smoke.fill_to=Vector2(1,.5)
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.35,.65,1])
	gradient.colors=PackedColorArray([Color(1,1,1,.95),Color(1,1,1,.6),Color(1,1,1,.25),Color(1,1,1,0)])
	_soft_smoke.gradient=gradient
	if not is_instance_valid(impact_sheets):
		for style in IMPACT_STYLES.get(kind,[]):_impact_textures[style]=load(impact_path(attribute,style))

## Taken from the stage's sheets on the first frame that draws it, seconds after the attack began.
func _impact_texture(style: String) -> Texture2D:
	if not _impact_textures.has(style):
		_impact_textures[style]=impact_sheets.texture(attribute,style) if is_instance_valid(impact_sheets) else load(impact_path(attribute,style))
	return _impact_textures[style]

func q(seed: int, channel: int=0) -> float:
	return fposmod(sin(seed*127.1+channel*311.7+91.3)*43758.5453,1.0)
func c(color: Color, alpha: float) -> Color:
	return Color(color,clampf(alpha,0,1))
func point(index: int) -> Vector2:
	return points[posmod(index,points.size())] if not points.is_empty() else target-Vector2(0,32)
func foot(index: int) -> Vector2:
	return feet[posmod(index,feet.size())] if not feet.is_empty() else target
func center() -> Vector2:
	var p:=Vector2.ZERO
	for v in party_feet:p+=v
	return p/maxi(1,party_feet.size())
func shadow_foot(index: int) -> Vector2:
	var src: Array=data.shadow_positions[index]
	var offset:=Vector2(src[0],src[1])-Vector2(190,247)
	var p:=center()+offset
	p.x=clampf(p.x,35,minf(canvas_size.x-35,boss.x-65))
	p.y=clampf(p.y,110,canvas_size.y-18)
	return p
func sprite(name: String, p: Vector2, flip: bool=false, tint: Color=Color.WHITE) -> void:
	draw_set_transform(p.round(),0,Vector2(-1 if flip else 1,1))
	draw_texture(Motion.texture(name),Vector2(-72,-112),tint)
	draw_set_transform(Vector2.ZERO)
func ray(a: Vector2,b: Vector2,color: Color,width: float=1) -> void:
	draw_line(a.round(),b.round(),color,width,false)
func tri(a: Vector2,b: Vector2,d: Vector2,color: Color) -> void:
	var aa:=a.round();var bb:=b.round();var dd:=d.round()
	if absf((bb-aa).cross(dd-aa))<.5:return
	draw_colored_polygon(PackedVector2Array([aa,bb,dd]),color)
func fill_polygon(vertices: PackedVector2Array,color: Color) -> void:
	var clean:=PackedVector2Array()
	for p in vertices:
		var rounded:=p.round()
		if clean.is_empty() or clean[-1]!=rounded:clean.append(rounded)
	if clean.size()>1 and clean[0]==clean[-1]:clean.remove_at(clean.size()-1)
	if clean.size()<3:return
	if Geometry2D.triangulate_polygon(clean).size()<3:return
	draw_colored_polygon(clean,color)
func mist(p: Vector2,t: float,power: float,width: float=55,rise: float=38,seed: int=0,ink: Color=Color(.09,.08,.14)) -> void:
	if power<=0:return
	for i in 20:
		var f:=fposmod(t*.36+q(seed+i),1.0)
		var pos:=p+Vector2((q(seed+i,1)-.5)*width+sin(t+i)*5,-f*rise)
		var radius: float=4+q(seed+i,2)*12+f*7
		if is_instance_valid(_soft_smoke):draw_texture_rect(_soft_smoke,Rect2((pos-Vector2.ONE*radius).round(),Vector2.ONE*round(radius*2)),false,c(ink,sin(f*PI)*power*.6))
func bullet(a: Vector2,b: Vector2,t: float,duration: float,color: Color) -> void:
	if t<0 or t>=duration:return
	var p:=clampf(t/duration,0,1)
	var tip:=a.lerp(b,p)
	ray(a.lerp(b,maxf(0,p-.28)),tip,c(color,.9),2)
	ray(a.lerp(b,maxf(0,p-.12)),tip,Color(.98,.96,.91),1)
func muzzle(p: Vector2,direction: Vector2,t: float) -> void:
	if t<0 or t>=.12:return
	var a:=1-t/.12
	var d:=direction.normalized();var side:=d.orthogonal()
	tri(p-side*4*a,p+d*22*a,p+side*4*a,c(Color(.99,.95,.85),a))
	ray(p-side*7*a,p+side*7*a,c(Color(.99,.98,.96),a),1)
func rift(p: Vector2,t: float,opening: float) -> void:
	if opening<.04:return
	var h:=27*opening;var w:=7*opening
	var polygon:=PackedVector2Array([p+Vector2(0,-h),p+Vector2(w,-h*.3),p+Vector2(w*.6,h*.6),p+Vector2(0,h),p+Vector2(-w,h*.1),p+Vector2(-w*.5,-h*.7)])
	fill_polygon(polygon,Color(.003,.003,.02))
	ray(p+Vector2(0,-h),p+Vector2(w,-h*.3),c(Color(.58,.25,.36),opening))
	mist(p+Vector2(0,10),t,opening,32,40,93)
func envelope(a: float,b: float,d: float,e: float,t: float) -> float:
	return smoothstep(a,b,t)*(1-smoothstep(d,e,t))
func impact(p: Vector2,t: float,color: Color,power: float,seed: int=0) -> void:
	if t<0 or t>1.65:return
	if power>=1.1 and IMPACT_STYLES.has(kind):
		var style: String="duel" if power<1.5 else ("first" if power<2 else "heavy")
		var index:=clampi(int(t*30),0,49)
		draw_texture_rect_region(_impact_texture(style),Rect2((p-Vector2(160,160)).round(),Vector2(320,320)),Rect2(Vector2(index%8*320,floori(float(index)/8.0)*320),Vector2(320,320)))
		return
	var fade:=1-smoothstep(.12,.55,t)
	var growth:=.3+.7*smoothstep(0,.10,t)
	if fade>0:
		for i in (8 if power<1.0 else 27):
			var theta:=q(seed+i)*TAU
			var dir:=Vector2.from_angle(theta)
			var radius: float=(9+q(seed+i,1)*28)*power*growth
			tri(p+dir.orthogonal()*2*fade,p+dir*radius,p-dir.orthogonal()*2*fade,c(color,fade*.86))
		var shape:=PackedVector2Array()
		for i in 16:shape.append((p+Vector2.from_angle(i*TAU/16)*(15 if i%2==0 else 5)*power*growth).round())
		fill_polygon(shape,c(Color(.02,.015,.04),fade))
		if t<.13:
			ray(p-Vector2(8,0)*power,p+Vector2(8,0)*power,c(Color(.99,.98,.93),1-t/.13),3)
			ray(p-Vector2(0,12)*power,p+Vector2(0,12)*power,c(Color(.99,.98,.93),1-t/.13),2)
	if power>1:
		mist(p+Vector2(0,12),t,1.5*(1-smoothstep(.65,1.6,t)),55*power,35*power,seed)
		for i in 32:
			var theta:=q(seed+i+45)*TAU
			var velocity:=Vector2(cos(theta)*45,-35-65*q(seed+i,2))*power
			var pos:=p+velocity*t+Vector2(0,70*t*t)
			if t>.04:ray(pos-velocity*.018,pos,c(color,(1-smoothstep(.35,1.3,t))*.8),1)
func rupture(t: float) -> void:
	if t<0 or t>=2.95:return
	var accent:=Palette.color_for(attribute)
	var power:=1.23 if awakened else 1.0
	var midpoint:=Vector2.ZERO
	for p in points:midpoint+=p
	midpoint/=maxi(points.size(),1)
	var fade:=1-smoothstep(.20,.56,t)
	var growth:=.25+.75*smoothstep(0,.095,t)
	if fade>0:
		for i in (39 if awakened else 29):
			var theta:=PI+(q(i+211)-.5)*1.95
			if i%4==0:theta=q(i+211)*TAU
			var dir:=Vector2(cos(theta),sin(theta)*.66)
			var tip:=midpoint+dir*(74+q(i+211,1)*100)*power*growth
			tip=tip.clamp(Vector2(15,15),canvas_size-Vector2(15,15))
			var width: float=(4+q(i+211,2)*14)*fade
			tri(midpoint+dir.orthogonal()*width,tip,midpoint-dir.orthogonal()*width,c(Color(.006,.006,.025),fade*.94))
			if i%3==0:ray(midpoint,tip,c(accent,fade*.8))
		if t<.14:
			tri(midpoint-Vector2(155,10),midpoint+Vector2(165,8),midpoint-Vector2(0,6),c(Color(.98,.96,.91),1-t/.14))
	for index in feet.size():
		var p:=feet[index];var body:=point(index)
		var ground:=1-smoothstep(1.55,2.85,t)
		for i in 7:
			var angle:=q(i+index*13+27)*TAU
			var path:=PackedVector2Array([p])
			for j in range(1,6):path.append((p+Vector2(cos(angle),sin(angle)*.3)*(18+q(i+index*13,1)*49)*growth*j/5.0+Vector2(0,sin(i+j*3)*2)).round())
			draw_polyline(path,c(Color(.005,.01,.025),ground),3)
		if .035<t and t<.93:
			var rise:=smoothstep(.035,.18,t)
			var height: float=(92+18*(index%2))*power*rise
			for layer in 4:
				var polygon:=PackedVector2Array()
				for side in [-1,1]:
					for k in (range(9) if side<0 else range(8,-1,-1)):
						var f: float=k/8.0
						polygon.append((p+Vector2(-f*37*power+side*19*power*(1-.68*f)*(1+q(index*15+k)*.65)*(1-layer*.18),-f*height*(1-layer*.045)-layer*2)).round())
				fill_polygon(polygon,c([Color(.03,.03,.07),Color(.17,.16,.21),Color(.37,.35,.41),Color(.73,.71,.75)][layer],(1-smoothstep(.30,.93,t))*(.84-layer*.09)))
		impact(body,t,accent,.96,index*40)
		mist(body-Vector2(t*24,t*25),t,2*(1-smoothstep(.7,2.65,t)),85,68,index*31)
		for i in (33 if awakened else 24):
			var velocity:=Vector2((-1 if q(i+index*29)<.74 else 1)*(12+q(i,2)*72),-(38+q(i,3)*112))*power
			var pos:=p+velocity*t+Vector2(0,65*t*t)
			if t>.04 and t<2.2 and Rect2(Vector2(10,10),canvas_size-Vector2(20,20)).has_point(pos):
				draw_rect(Rect2(pos.round(),Vector2(3,2) if i%3 else Vector2(5,4)),c(Color(.37,.35,.40),1-smoothstep(.7,2.2,t)))
func awakening_effects() -> void:
	var dim:=envelope(2.8,4.8,9.3,11.5,age)
	draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(0,0,.012,dim*.48))
	var reveal:=envelope(5.4,6.8,8.3,9.6,age)
	if reveal>0:
		for i in 19:
			var side: float=-1 if i%2 else 1
			var base:=boss+Vector2(side*(10+70*q(i+104))*smoothstep(5.8,7.6,age),-45)
			tri(boss-Vector2(0,10),base+Vector2(side*12,-75-q(i,1)*25),base+Vector2(-side*14,0),Color(.01,.01,.035,reveal*.65))
			if 6.9<age and age<7.91 and i%3==0:
				ray(base+Vector2(-3,-20),base+Vector2(3,-21),Color(.9,.12,.2,reveal))
		mist(boss,age,reveal*4,190,140,212)
	var dt:=age-8.08
	if dt>=0 and dt<2.8:
		var growth:=smoothstep(0,.35,dt)
		var fade:=1-smoothstep(.3,2.5,dt)
		for i in 42:
			var dir:=Vector2.from_angle(q(i+270)*TAU)
			var tip:=boss-Vector2(0,45)+dir*Vector2(1,.67)*(50+140*q(i,1))*(.3+.7*growth)
			tri(boss-Vector2(0,45),tip,boss-Vector2(0,45)+dir.orthogonal()*10,Color(.01,.01,.035,fade*.75))
			if i%2==0:ray(tip,tip-dir*17,Color(.81,.22,.35,fade*.8))
		mist(boss-Vector2(60,0),dt+1,3*fade,320,120,212)
		if dt<.10:draw_rect(Rect2(Vector2.ZERO,canvas_size),Color(.87,.76,.83,(1-dt/.10)*.5))

func _draw() -> void:
	if data.is_empty():return
	var accent:=Palette.color_for(attribute)
	if kind=="awakening":awakening_effects()
	if data.has("shadow_frames"):
		var row: Array=data.shadow_frames[Motion.frame_index(data,age)]
		for i in row.size():
			var rec: Dictionary=row[i];var p:=shadow_foot(i)
			if float(rec.alpha)>0:
				mist(p,age,float(rec.alpha)*.6,42,28,130+i*7)
				sprite(str(rec.frame),p,p.x<center().x,Color(.25,.29,.38,float(rec.alpha)))
	sprite(Motion.frame(kind,age),boss)
	if kind in ["buff","heal"]:
		var color:=Color("71da87") if kind=="heal" else Color("ef4847")
		var strength:=envelope(.7,2.2,3.9,4.8,age)
		mist(boss,age,strength*2,60,80,50,color.darkened(.68))
		for i in 28:
			var p:=fposmod(age*.6+q(i),1)
			draw_rect(Rect2((boss+Vector2((q(i,1)-.5)*55,-p*110)).round(),Vector2(2,3)),c(color,sin(p*PI)*strength))
	for event in data.shadows:
		var e: Dictionary=event;var p:=shadow_foot(int(e.shooter))
		var mouth:=p+Vector2(44 if p.x<center().x else -44,-72)
		var dest:=point(int(e.target))
		muzzle(mouth,dest-mouth,age-float(e.time));bullet(mouth,dest,age-float(e.time),.1,Color(.9,.83,.65))
		impact(dest,age-float(e.hit),accent,.56+.1*float(e.round),int(e.shooter)*40)
	for i in data.host.size():
		var e: Dictionary=data.host[i];var dt:=age-float(e.time)
		var mouth:=boss+Motion.muzzle(kind,clampf(age,float(e.time),float(e.time)+.14),str(e.hand))
		var dest:=point(0)
		if kind in ["all","awakened_all"]:dest=center()-Vector2(0,45 if i==0 else 20)
		if kind=="awakened_single":dest=boss+Vector2(80 if i==0 else -112,-155)
		muzzle(mouth,dest-mouth,dt);bullet(mouth,dest,dt,.2 if kind=="awakened_single" else .12,Color(.92,.8,.68) if i==0 else Color(.92,.39,.45))
		if kind=="awakened_single":
			mist(dest,age,envelope(float(e.time)-.12,float(e.time)+.1,float(e.time)+.35,float(e.time)+.65,age)*2,41,43,92+i*8)
			var exit:=point(0)+Vector2(-12,-90) if i==0 else point(0)+Vector2(-95,-20)
			rift(exit,age,envelope(float(e.reentry)-.36,float(e.reentry)-.08,float(e.hit)+.04,float(e.hit)+.25,age))
			bullet(exit,point(0),age-float(e.reentry),.12,Color(.95,.18,.3))
			impact(point(0),age-float(e.hit),accent,1.55 if i==0 else 2.85,100+i*30)
		elif kind=="single":
			impact(point(0),age-float(e.hit),accent,1.42,12)
			if age>float(e.hit)+.12:mist(point(0)-Vector2(15,0),age-float(e.hit),1-smoothstep(.5,1.5,age-float(e.hit)),45,33,77)
		elif kind=="awakened_all" and i==0:
			for j in points.size():impact(point(j),age-float(e.hit),accent,1.6,80+j*40)
	if kind in ["all","awakened_all"]:rupture(age-float(data.impact))
