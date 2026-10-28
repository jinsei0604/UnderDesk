extends "res://src/bossmaker/visuals/plush/rbm_plush_render.gd"
## Review-only V7: native contour frames, material deformation and physical hands.
const NewArt=preload("res://src/bossmaker/visuals/plush/rbm_plush_v7_data.gd")
const NEW_ROOT="res://assets_bossmaker/battle/plush/v7/"
const KEYS=["normal_single","normal_all","awakening","awakened_single","awakened_all"]
var sheets: Array[Texture2D]=[]
var veil: Node2D
var dark_front: Node2D
var originals: Dictionary={}
var is_new:=false

class Veil extends Node2D:
	var painter
	var foreground:=false
	func _draw() -> void:
		if is_instance_valid(painter):painter.draw_darkness(self,foreground)

static func clip_duration(key: String) -> float:
	if key in KEYS:return float(NewArt.ART.animations[key].duration)
	return float(Data.ANIMATION.animations[key.replace("_heal","_support").replace("_buff","_support")].duration)
static func clip_impact(key: String) -> float:
	return float(NewArt.ART.impact[key]) if key in KEYS else float(IMPACT[key])
static func new_paths() -> Array[String]:
	var paths: Array[String]=[]
	for i in range(int(NewArt.ART.pages)):paths.append(NEW_ROOT+"native-"+str(i)+".png")
	return paths
func _ready() -> void:
	super._ready()
	for path in new_paths():sheets.append(load(path))
	veil=Veil.new();veil.painter=self;veil.z_as_relative=false;veil.z_index=90
	veil.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(veil)
	dark_front=Veil.new();dark_front.painter=self;dark_front.foreground=true
	dark_front.z_as_relative=false;dark_front.z_index=92
	dark_front.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(dark_front)
func new_frame(key: String,t: float) -> Dictionary:
	var clip: Dictionary=NewArt.ART.animations[key]
	return clip.frames[clampi(int(t*float(clip.fps)+.0001),0,clip.frames.size()-1)]
func stamp(ci: CanvasItem,key: String,t: float,pos: Vector2,tint: Color=Color.WHITE,flip: bool=false) -> void:
	var f:=new_frame(key,t);var m: Dictionary=NewArt.ART.frames[int(f.id)]
	var r:=Rect2(m.rect[0],m.rect[1],m.rect[2],m.rect[3]);var offset:=Vector2(m.offset[0],m.offset[1])
	if flip:
		ci.draw_set_transform(pos.round(),0,Vector2(-1,1))
		ci.draw_texture_rect_region(sheets[int(m.page)],Rect2(offset,r.size),r,tint)
		ci.draw_set_transform(Vector2.ZERO)
	else:ci.draw_texture_rect_region(sheets[int(m.page)],Rect2((pos+offset).round(),r.size),r,tint)

func show_action(key: String,t: float) -> void:
	is_new=key in KEYS
	if not is_new:
		veil.visible=false
		dark_front.visible=false
		super.show_action(key,t)
		return
	kind=key;age=t;at=t;boss=home;anim=key
	screen_fx.visible=false;space.visible=false;support_display.visible=false
	support_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	veil.visible=true
	dark_front.visible=true
	frame_record=new_frame(key,t)
	aura=.60 if key.begins_with("awakened") else 0.0
	if key=="normal_single":
		var f:=new_frame(key,1.2)
		var contact:=target_foot()+Vector2(0,-43)-Vector2(f.far_hand[0],f.far_hand[1])
		var dash:=pow(smoothstep(.90,1.20,t),1.6)
		boss=home.lerp(contact,dash*(1-smoothstep(1.65,2.4,t)))
		boss.y-=sin(dash*PI)*14
		if t>=.35:sound("boss_move_heavy",1.18,"stuffing")
		if t>=.96:sound("neutral_blunt_swing",.72,"throw")
	elif key=="normal_all":
		if t>=.5:sound("boss_move_heavy",.85,"inhale")
		if t>=1.30:sound("wind_burst",.8,"release")
	elif key=="awakening":
		aura=smoothstep(1.35,3.7,t)*(.86-.28*smoothstep(5.7,6.7,t))
		if t>.55 and t<4.55:camera.cut(2,home+Vector2(0,-86))
		elif t>5.25 and t<5.75:camera.cut(2,home+Vector2(0,-150))
		else:camera.cut(1,Vector2(640,360))
		if t>=1.2:sound("neutral_blunt_swing",.52,"seam0")
		if t>=1.9:sound("neutral_impact_light",.53,"seam1")
		if t>=2.6:sound("boss_move_heavy",.60,"change")
		if t>=3.4:sound("wind_cast",.65,"rising")
		if t>=4.85:sound("neutral_blunt_swing",.62,"arms")
	elif key=="awakened_single":
		if t>=.72:sound("boss_move_heavy",.58,"open")
		if t>=1.1:sound("neutral_blunt_swing",.57,"reach")
		if t>=1.45:sound("neutral_impact_light",.61,"grip")
		if t>=1.98:sound("wind_burst",.63,"slam")
		if t>=2.85:sound("boss_move_heavy",.72,"withdraw")
	elif key=="awakened_all":
		aura=.6*(1-smoothstep(.05,.35,t))+smoothstep(5.0,5.6,t)*.6
		if t>=.85:sound("boss_move_heavy",.47,"door")
		var i:=0
		for id in HOMES:
			var when:=1.85+i*.36
			if t>=when:sound("neutral_blunt_swing",.78-i*.08,"claw"+id)
			if t>=when+.14:sound("neutral_impact_heavy",.9-i*.08,"strike"+id)
			i+=1
		if t>=3.91:sound("wind_burst",.53,"giant")
	camera.advance(maxf(0,t-old_age));old_age=t
	queue_redraw();front.queue_redraw();veil.queue_redraw();dark_front.queue_redraw()

func on_impact(key: String) -> void:
	if not key in KEYS:super.on_impact(key);return
	var power:=4.0 if key=="normal_single" else (5.0 if key=="normal_all" else 8.0)
	camera.shake(power,.18 if key=="normal_single" else .36)
	sound("neutral_impact_heavy" if key.begins_with("normal") else "boss_impact_mass",.75 if key.begins_with("normal") else .6,"main_impact")

func _draw() -> void:
	if not is_new:super._draw();return
	if kind=="awakened_all" and age>.95 and age<4.95:return
	if aura>0:stamp(self,"aura",fmod(age,2.0),boss,Color(1,1,1,aura))
	stamp(self,kind,age,boss)
	if kind=="awakening" and age>=4.25 and age<4.8:
		stamp(self,"impact",age-4.25,boss+Vector2(0,-5),Color(1,1,1,.8))

func draw_foreground(ci: CanvasItem) -> void:
	if not is_new:super.draw_foreground(ci);return
	if kind=="normal_single":
		var dt:=age-1.2
		if dt>=0 and dt<.6:
			stamp(ci,"fluff_scatter",dt,target_foot()+Vector2(0,-43),Color(1,1,1,1-smoothstep(.25,.6,dt)))
	elif kind=="normal_all":
		var i:=0
		for id in HOMES:
			var dst: Vector2=HOMES[id]+Vector2(0,-40)
			var start:=1.30+i*.025
			if age>=start and age<1.65:
				var k:=clampf((age-start)/(1.65-start),0,1)
				var p:=boss+Vector2(-5,-85)
				p=p.lerp(dst,k);p.y-=sin(k*PI)*(35+i*9)
				stamp(ci,"cotton",fmod(age+i*.2,1.0),p)
			elif age>=1.65 and age<2.25:stamp(ci,"cotton_burst",age-1.65,dst,Color(1,1,1,1-smoothstep(2.0,2.25,age)))
			i+=1
	elif kind=="awakened_single":draw_nightmare_arm(ci)

func polygon(ci: CanvasItem,points: Array,col: Color) -> void:
	var p:=PackedVector2Array()
	for v in points:
		var pixel:=Vector2(v).round()
		if p.is_empty() or p[p.size()-1]!=pixel:p.append(pixel)
	if p.size()>2 and p[0]==p[p.size()-1]:p.remove_at(p.size()-1)
	if p.size()>2:ci.draw_colored_polygon(p,col)
func sleeve(ci: CanvasItem,a: Vector2,b: Vector2,width: float,opacity: float=1.0) -> void:
	var axis: Vector2=(b-a).normalized();var n:=Vector2(-axis.y,axis.x)
	var length:=a.distance_to(b)
	if length<8:return
	var dark:=Color("2e2530");dark.a=opacity
	var cloth:=Color("6c4c40");cloth.a=opacity
	var light:=Color("9c7250");light.a=opacity
	var edge_a: Array=[];var edge_b: Array=[];var inner_a: Array=[];var inner_b: Array=[];var shine_a: Array=[];var shine_b: Array=[]
	var steps:=mini(16,int(length/3))
	for step in range(steps+1):
		var t:=float(step)/steps
		var center:=a.lerp(b,t)+n*sin(t*PI)*width*.20
		var r:=width*(.50+.45*sin(t*PI*.82))
		r+=sin(t*PI*7.0)*width*.07
		edge_a.append(center-n*r);edge_b.push_front(center+n*r)
		inner_a.append(center-n*(r-2));inner_b.push_front(center+n*(r-2))
		shine_a.append(center-n*r*.65);shine_b.push_front(center-n*r*.17)
	polygon(ci,edge_a+edge_b,dark)
	polygon(ci,inner_a+inner_b,cloth)
	polygon(ci,shine_a+shine_b,light)
	# Sewn fabric panels widen at the elbow; every edge is snapped to native pixels.
	for j in range(1,4):
		var center:=a.lerp(b,j/4.0);var w:=lerpf(width*.5,width,j/4.0)
		var patch:=Color("b8a27a") if j%2 else Color("4d6663");patch.a=opacity
		polygon(ci,[center-axis*10-n*w*.65,center+axis*7-n*w*.69,center+axis*13-n*w*.36,center+axis*10+n*w*.36,center+axis*3+n*w*.62,center-axis*9+n*w*.55,center-axis*13],patch)
		var fold:=Color("4b3633");fold.a=opacity
		polygon(ci,[center+axis*17-n*w*.8,center+axis*21-n*w*.5,center+axis*19+n*w*.28,center+axis*25+n*w*.6,center+axis*21+n*w*.72,center+axis*15+n*w*.35],fold)
		for h in [-.45,0.0,.45]:
			var p: Vector2=center+n*w*h
			polygon(ci,[p-axis*10-n,p-axis*5-n,p-axis*5+n,p-axis*10+n],dark)

func grab_lift(t: float) -> Vector2:
	var up:=smoothstep(1.52,1.91,t)
	var drop:=pow(smoothstep(1.98,2.20,t),2)
	return Vector2(16*up*(1-drop),-66*up*(1-drop))
func draw_nightmare_arm(ci: CanvasItem) -> void:
	if age<.95 or age>3.35:return
	var origin:=boss+Vector2(1,-86)
	var dst:=target_foot()+Vector2(0,-37)
	var reach:=pow(smoothstep(.95,1.42,age),2)
	var retract:=smoothstep(2.65,3.35,age)
	var hand:=origin.lerp(dst,reach*(1-retract))+grab_lift(age)*(1-retract)
	var elbow:=origin.lerp(hand,.48)+Vector2(0,-60*reach*(1-retract))
	var opacity:=smoothstep(.95,1.08,age)*(1-smoothstep(3.15,3.35,age))
	sleeve(ci,origin,elbow,25,opacity);sleeve(ci,elbow,hand+Vector2(0,37),32,opacity)
	var curl:=smoothstep(1.40,1.55,age)*(1-smoothstep(2.55,2.83,age))
	stamp(ci,"hand",curl,hand,Color(1,1,1,opacity))
	if age>=2.2 and age<2.8:stamp(ci,"impact",age-2.2,target_foot(),Color(1,1,1,1-smoothstep(2.55,2.8,age)))

func draw_darkness(ci: CanvasItem,foreground: bool=false) -> void:
	if kind!="awakened_all" or not is_new:return
	var black:=smoothstep(.72,1.08,age)*(1-smoothstep(4.75,5.30,age))
	if black<=0:return
	if not foreground:ci.draw_rect(Rect2(Vector2.ZERO,size),Color(0.008,.004,.014,black))
	if not foreground and age>=1.12 and age<3.7:
		var presence:=smoothstep(1.12,1.6,age)*(1-smoothstep(3.25,3.7,age))
		stamp(ci,"shade_left",0,Vector2(596,425),Color(1,1,1,presence*.66))
		stamp(ci,"shade_right",0,Vector2(808,446),Color(1,1,1,presence*.5))
		# Their still eyes establish a source for the approaching physical claws.
		for eye in [Vector2(562,265),Vector2(591,263),Vector2(765,293),Vector2(800,295)]:
			polygon(ci,[eye+Vector2(-4,0),eye+Vector2(0,-3),eye+Vector2(5,0),eye+Vector2(0,3)],Color(.66,.36,.73,presence))
	if not foreground:
		if age>=3.48 and age<4.65:
			var menace:=smoothstep(3.48,3.78,age)*(1-smoothstep(4.3,4.65,age))
			stamp(ci,"dread",0,Vector2(750,530),Color(1,1,1,menace*.85))
		return
	var i:=0
	for id in HOMES:
		var q:=age-(1.85+i*.36)
		var target: Vector2=HOMES[id]+Vector2(0,-35)
		if q>=-.16 and q<.43:
			var incoming:=smoothstep(-.16,.14,q)
			var end:=target+Vector2(16,20)
			var hand:=target+Vector2(135,-105)
			hand=hand.lerp(end,incoming)
			var opacity:=smoothstep(-.16,-.06,q)*(1-smoothstep(.25,.43,q))
			sleeve(ci,hand+Vector2(190,-80),hand+Vector2(0,34),25,opacity)
			stamp(ci,"claw",smoothstep(-.05,.20,q)*.4,hand,Color(1,1,1,opacity))
			if q>=.14:stamp(ci,"impact",q-.14,target,Color(1,1,1,opacity))
		i+=1
	if age>=3.92 and age<4.53:
		var sweep:=pow(smoothstep(3.92,4.18,age),.70)
		var p:=Vector2(1090,300).lerp(Vector2(150,465),sweep)
		var opacity:=smoothstep(3.92,3.98,age)*(1-smoothstep(4.28,4.53,age))
		sleeve(ci,p+Vector2(750,-140),p+Vector2(0,40),58,opacity)
		stamp(ci,"giant_claw",.12,p,Color(1,1,1,opacity))
	if age>=4.15 and age<4.75:
		for foot in HOMES.values():stamp(ci,"impact",age-4.15,foot+Vector2(0,-18),Color(1,1,1,1-smoothstep(4.5,4.75,age)))

func update_actors() -> void:
	if not is_new or not is_instance_valid(production_stage):return
	for id in HOMES:
		var actor: Control=production_stage._visuals[id]
		if not originals.has(id):originals[id]={"modulate":actor.modulate,"z":actor.z_index,"relative":actor.z_as_relative}
		if kind=="awakened_all":
			var darkness:=smoothstep(.72,1.08,age)*(1-smoothstep(4.75,5.30,age))
			actor.z_as_relative=false;actor.z_index=91 if darkness>.15 else int(originals[id].z)
			actor.modulate=Color.WHITE.lerp(Color(.34,.23,.43,1),darkness)
			var i:=HOMES.keys().find(id);var q:=age-(1.99+i*.36)
			if q>=0 and q<.22:
				production_stage._pose(id,11)
				actor.modulate=Color(.85,.65,.91,1)
				actor.position=production_stage._homes[id]+Vector2(-sin(q/.22*PI)*12,0).round()
		elif kind=="awakened_single" and age>=1.42 and age<2.65:
			production_stage._pose(id,11)
			actor.position=production_stage._homes[id]+Vector2(production_stage._guard_offsets.get(id,Vector2.ZERO))+grab_lift(age).round()
func cleanup_visuals() -> void:
	if not is_instance_valid(production_stage):return
	for id in originals:
		if not production_stage._visuals.has(id):continue
		var actor=production_stage._visuals[id];var saved: Dictionary=originals[id]
		actor.modulate=saved.modulate;actor.z_index=saved.z;actor.z_as_relative=saved.relative
		actor.position=production_stage._homes[id]
	originals.clear()
