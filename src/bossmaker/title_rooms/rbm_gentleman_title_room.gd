extends Node2D
const ROOM = preload("res://assets_bossmaker/title_rooms/gentleman/room.png")
const CHAIR = preload("res://assets_bossmaker/title_rooms/gentleman/chair.png")
const HAT = preload("res://assets_bossmaker/title_rooms/gentleman/existing_hat.png")
var room_texture: Texture2D
var t: float = 0.0
var sip: float = 0.0
var aim: float = 0.0
var pose: int = 4
var shots: Array[float] = [20.1,22.1]
var target_point: Vector2 = Vector2(618,105)
var rocking_pivot: Vector2 = Vector2(334,316)
var actor_origin: Vector2 = Vector2(190,123)
var rig_view: SubViewport
var rig_holder: Node2D
var presentation: Node2D
var rocking_angle: float=0.0
var rocking_offset: Vector2=Vector2.ZERO
var root: Node2D
var person: Node2D
var upper: Node2D
var lower: Node2D
var hand: Node2D
var cup: Cup
var head: Head
var body: FixedBody
var gun: Piece
var vfx: Node2D
var visitor: ShadowVisitor
var look: float=0.0
var gun_textures: Array[Texture2D] = []
var runner: PackedVector2Array
const SHOULDER = Vector2(60,45)
const ELBOW = Vector2(53,55)
const PALM = Vector2(63,64)
const MUZZLES = [Vector2(116,47),Vector2(121,41),Vector2(115,38),Vector2(111,30),Vector2(116,47),Vector2(117,48),Vector2(119,48),Vector2(117,47)]
const UPPER_MASK = [Vector2(60,40),Vector2(67,43),Vector2(60,53),Vector2(58,58),Vector2(53,60),Vector2(50,57),Vector2(50,52),Vector2(54,45)]
const LOWER_MASK = [Vector2(50,55),Vector2(56,53),Vector2(60,57),Vector2(67,61),Vector2(69,66),Vector2(65,70),Vector2(59,69),Vector2(54,64),Vector2(53,60)]

class Piece:
	extends Node2D
	var tex: Texture2D
	var area: Rect2
	func _draw() -> void:
		if tex:draw_texture_rect(tex,area,false)

class FixedBody:
	extends Node2D
	var torso: Texture2D
	var thigh_near: Texture2D
	var thigh_far: Texture2D
	var shin_near: Texture2D
	var shin_far: Texture2D
	var boot: Texture2D
	func patch(tex: Texture2D,source_pivot: Vector2,destination_pivot: Vector2,angle: float=0.0) -> void:
		draw_set_transform(destination_pivot*2,angle)
		draw_texture_rect(tex,Rect2(-source_pivot*2,Vector2(288,248)),false)
	func _draw() -> void:
		# Original pixels moved as rigid pieces. No mesh, blended vertices or stretching.
		patch(thigh_far,Vector2(81,69),Vector2(80,70),-PI/2)
		patch(shin_far,Vector2(84,88),Vector2(99,70))
		patch(boot,Vector2(86,105),Vector2(99,87))
		patch(thigh_near,Vector2(70,69),Vector2(72,74),-PI/2)
		patch(shin_near,Vector2(68,88),Vector2(91,74))
		patch(boot,Vector2(86,105),Vector2(91,91))
		draw_set_transform(Vector2.ZERO)
		draw_texture_rect(torso,Rect2(0,0,288,248),false)

class Head:
	extends Piece
	func _draw() -> void:
		var eye: Vector2=Vector2(77,33)-Vector2(76,40)
		var points: PackedVector2Array=[]
		for p in [Vector2(-6,1),Vector2(-7,-3),Vector2(-5,-8),Vector2(-2,-10),Vector2(3,-9),Vector2(6,-6),Vector2(6,1)]:points.append((eye+p)*2)
		draw_colored_polygon(points,Color("080a10"))
		draw_line((eye+Vector2(-5,-8))*2,(eye+Vector2(-2,-10))*2,Color("171d2a"),2,false)
		super._draw()

class Cup:
	extends Node2D
	var time: float=0.0
	var depth_tilt: float=0.0
	func line(a: Vector2,b: Vector2,col: Color,width: float=1) -> void:
		draw_line(a.round(),b.round(),col,width,false)
	func _draw() -> void:
		draw_set_transform(Vector2(10,-4))
		# Dedicated depth poses: rim recedes into the mouth; underside faces the viewer.
		# No clockwise/counterclockwise rotation on the screen.
		var depth: float=roundf(depth_tilt*4.0)/4.0
		var rim_y: float=-4.0-depth*2.0
		var base_y: float=6.0-depth*6.0
		draw_colored_polygon(PackedVector2Array([Vector2(-7,rim_y),Vector2(7,rim_y),Vector2(5,base_y),Vector2(-4,base_y)]),Color("cabb9f"))
		if depth<.75:
			draw_rect(Rect2(-5,rim_y+1,10,maxf(1.0,3.0-depth*4.0)),Color("493225"))
		line(Vector2(-6,rim_y),Vector2(7,rim_y),Color("ecdbc1"),2)
		if depth>0.0:
			var oval: float=depth*3.0
			draw_colored_polygon(PackedVector2Array([Vector2(-4,base_y-oval*.4),Vector2(3,base_y-oval*.4),Vector2(5,base_y+oval*.45),Vector2(3,base_y+oval),Vector2(-3,base_y+oval),Vector2(-5,base_y+oval*.45)]),Color("e2d5b9"))
			line(Vector2(-2,base_y+oval*.45),Vector2(2,base_y+oval*.45),Color("b2a58d"),1)
		# Handle faces the actual glove/hand grip on the left of the cup.
		line(Vector2(-7,-1),Vector2(-11,-1),Color("cabb9f"),2)
		line(Vector2(-11,-1),Vector2(-11,4),Color("cabb9f"),2)
		line(Vector2(-11,4),Vector2(-5,4),Color("cabb9f"),2)
		# Visible cuff, palm, knuckles and thumb around the existing handle.
		draw_rect(Rect2(-18,0,4,6),Color("c6c4b7"))
		draw_colored_polygon(PackedVector2Array([Vector2(-15,-1),Vector2(-11,-3),Vector2(-8,-2),Vector2(-7,0),Vector2(-5,1),Vector2(-5,4),Vector2(-8,7),Vector2(-13,7),Vector2(-16,4)]),Color("10151e"))
		draw_colored_polygon(PackedVector2Array([Vector2(-14,0),Vector2(-11,-1),Vector2(-8,0),Vector2(-7,4),Vector2(-10,6),Vector2(-13,5)]),Color("35404e"))
		line(Vector2(-12,0),Vector2(-9,0),Color("596371"),2)
		line(Vector2(-12,3),Vector2(-9,3),Color("202836"),1)
		draw_rect(Rect2(-8,1,3,3),Color("596371"))
		for k in range(2):
			var f: float=fposmod(time*.22+k*.5,1)
			var x: float=sin(f*6+k)*2
			line(Vector2(x,-6-f*13),Vector2(x+2,-10-f*13),Color(.76,.71,.66,sin(f*PI)*.22),1)

class ShadowVisitor:
	extends "res://src/bossmaker/visuals/rbm_gentleman_vfx.gd"
	var opacity: float=0.0
	func _ready() -> void:
		kind="preview_shadow"
		super._ready()
		data=Motion.clip("all")
	func set_time(q: float) -> void:
		age=maxf(0.0,q-34.3)
		# Reuse the first combat shadow's exact appearance/disappearance envelope.
		var source_time: float=0.0
		if q>=34.3 and q<36.65:source_time=minf(age,1.0)
		elif q>=36.65 and q<37.35:source_time=5.30+(q-36.65)
		var rec: Dictionary=data.shadow_frames[Motion.frame_index(data,source_time)][0]
		opacity=float(rec.alpha)
		queue_redraw()
	func _draw() -> void:
		if opacity<=0.0:return
		mist(Vector2.ZERO,age,opacity*.6,42,28,130)
		# The skill's standing, hat-on clone, facing the seated boss. No firing frames.
		sprite("normal_draw_fire_00",Vector2.ZERO,false,Color(.25,.29,.38,opacity))

class PracticeEffects:
	extends "res://src/bossmaker/visuals/rbm_gentleman_vfx.gd"
	var tip: Vector2
	var mark: Vector2
	var since: float=-1.0
	func _ready() -> void: pass
	func _draw() -> void:
		if since<0 or since>.8:return
		muzzle(tip,(mark-tip).normalized(),since)
		bullet(tip,mark,since,.10,Color("e5bb70"))
		if since>=.10:
			impact(mark,since-.10,Color("efca86"),.52,18)

## Which pixels of a 144x124 battle frame belong to each part, decided once per room with the
## same pixel-center tests as before. Cutting a part is then one native masked blit instead of a
## GDScript pass over every pixel for each of the 25 parts.
func part_masks() -> Dictionary:
	var masks: Dictionary={}
	for part in ["body","thigh_near","thigh_far","shin_near","shin_far","boot","upper","lower","head","gun"]:
		masks[part]=Image.create_empty(144,124,false,Image.FORMAT_LA8)
	var upper_poly: PackedVector2Array=PackedVector2Array(UPPER_MASK)
	var lower_poly: PackedVector2Array=PackedVector2Array(LOWER_MASK)
	var thigh_near_poly: PackedVector2Array=PackedVector2Array([Vector2(66,66),Vector2(77,67),Vector2(73,89),Vector2(62,89)])
	var thigh_far_poly: PackedVector2Array=PackedVector2Array([Vector2(77,67),Vector2(85,68),Vector2(88,89),Vector2(79,89)])
	for y in range(124):
		for x in range(144):
			var p: Vector2=Vector2(x+.5,y+.5)
			var in_upper: bool=Geometry2D.is_point_in_polygon(p,upper_poly)
			var in_lower: bool=Geometry2D.is_point_in_polygon(p,lower_poly)
			var in_head: bool=y<40
			var in_gun: bool=x>=84 and y<70
			if not (in_upper or in_lower or in_head or in_gun) and y<69:masks.body.set_pixel(x,y,Color.WHITE)
			if Geometry2D.is_point_in_polygon(p,thigh_near_poly):masks.thigh_near.set_pixel(x,y,Color.WHITE)
			if Geometry2D.is_point_in_polygon(p,thigh_far_poly):masks.thigh_far.set_pixel(x,y,Color.WHITE)
			if y>=88 and y<105 and x>=62 and x<75:masks.shin_near.set_pixel(x,y,Color.WHITE)
			if y>=88 and y<105 and x>=79 and x<89:masks.shin_far.set_pixel(x,y,Color.WHITE)
			if y>=104 and x>=78 and x<100:masks.boot.set_pixel(x,y,Color.WHITE)
			if in_upper:masks.upper.set_pixel(x,y,Color.WHITE)
			if in_lower:masks.lower.set_pixel(x,y,Color.WHITE)
			if in_head:masks.head.set_pixel(x,y,Color.WHITE)
			if in_gun:masks.gun.set_pixel(x,y,Color.WHITE)
	return masks

func texture_part(source: Image,mask: Image) -> Texture2D:
	# Pixels outside the part stay Color.TRANSPARENT, which is (1,1,1,0) in Godot 4, as before.
	var out: Image=Image.create_empty(144,124,false,Image.FORMAT_RGBA8)
	out.fill(Color.TRANSPARENT)
	out.blit_rect_mask(source,mask,Rect2i(0,0,144,124),Vector2i.ZERO)
	return ImageTexture.create_from_image(out)

func native_viewport_size() -> Vector2i:
	return Vector2i(320,180)

func take_presentation_layer() -> Node2D:
	# Keep the completed chair/person pixel surface on the final canvas, as approved.
	remove_child(presentation)
	return presentation

func set_presentation_active(active: bool) -> void:
	rig_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func _ready() -> void:
	room_texture=ROOM
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var metadata: Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets_bossmaker/title_rooms/gentleman/heads.json"))
	var source: Image
	var masks: Dictionary=part_masks()
	for i in range(16):
		var im: Image=load("res://assets_bossmaker/battle/gentleman/motion_frames/normal_draw_fire_%02d.png"%i).get_image()
		im.convert(Image.FORMAT_RGBA8)
		im.flip_x()
		im.fill_rect(Rect2i(int(metadata[i].eye[0])-16,0,32,int(metadata[i].eye[1])),Color.TRANSPARENT)
		gun_textures.append(texture_part(im,masks.gun))
		if i==4:source=im
	# Compose the complete chair and sitter on a fixed native-pixel canvas.
	# Only this finished texture rotates on the final-resolution canvas.
	rig_view=SubViewport.new();rig_view.size=Vector2i(320,180)
	rig_view.transparent_bg=true;rig_view.disable_3d=true
	rig_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	rig_view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(rig_view)
	rig_holder=Node2D.new();rig_holder.name="FixedSeatedComposition";rig_holder.scale=Vector2(.5,.5);rig_view.add_child(rig_holder)
	presentation=Node2D.new();presentation.name="GentlemanRockRoot";root=presentation
	add_child(presentation)
	var display: Sprite2D=Sprite2D.new();display.name="ChairAndSitterUnifiedSprite"
	display.texture=rig_view.get_texture();display.centered=false
	display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	display.scale=Vector2(4,4);display.position=-rocking_pivot*2;presentation.add_child(display)
	var chair: Piece=Piece.new();chair.name="RockingChair";chair.tex=CHAIR
	chair.area=Rect2(276,184,105,132);rig_holder.add_child(chair)
	var chair_im: Image=CHAIR.get_image()
	for x in range(chair_im.get_width()):
		for y in range(chair_im.get_height()-1,65,-1):
			if chair_im.get_pixel(x,y).a>.5:
				runner.append(Vector2(276+(x+.5)*105.0/chair_im.get_width(),184+(y+1)*132.0/chair_im.get_height())-rocking_pivot)
				break
	person=Node2D.new();person.name="Gentleman";person.position=actor_origin;rig_holder.add_child(person)
	body=FixedBody.new();body.name="RigidSeatedBody";person.add_child(body)
	body.torso=texture_part(source,masks.body)
	body.thigh_near=texture_part(source,masks.thigh_near);body.thigh_far=texture_part(source,masks.thigh_far)
	body.shin_near=texture_part(source,masks.shin_near);body.shin_far=texture_part(source,masks.shin_far)
	body.boot=texture_part(source,masks.boot)
	head=Head.new();head.name="Head";head.position=Vector2(76,40)*2;head.tex=texture_part(source,masks.head)
	head.area=Rect2(-Vector2(76,40)*2,Vector2(288,248));person.add_child(head)
	gun=Piece.new();gun.name="ExistingGunArmFrames";gun.position=Vector2(84,48)*2
	gun.area=Rect2(-Vector2(84,48)*2,Vector2(288,248));person.add_child(gun)
	upper=Piece.new();upper.name="UpperArm";upper.position=SHOULDER*2
	upper.tex=texture_part(source,masks.upper);upper.area=Rect2(-SHOULDER*2,Vector2(288,248));person.add_child(upper)
	lower=Piece.new();lower.name="Forearm";lower.position=(ELBOW-SHOULDER)*2
	lower.tex=texture_part(source,masks.lower);lower.area=Rect2(-ELBOW*2,Vector2(288,248));upper.add_child(lower)
	hand=Node2D.new();hand.name="HandGrip";hand.position=(PALM-ELBOW)*2;lower.add_child(hand)
	cup=Cup.new();cup.name="CoffeeCup";cup.position=Vector2.ZERO;hand.add_child(cup)
	vfx=PracticeEffects.new();add_child(vfx)
	visitor=ShadowVisitor.new();visitor.name="ExistingSkillShadow"
	visitor.position=Vector2(444,316);visitor.scale=Vector2(2,2);add_child(visitor)
	advance(0.0)

func gate(a: float,b: float,c: float,d: float,x: float) -> float:
	return smoothstep(a,b,x)*(1.0-smoothstep(c,d,x))

func arm_angles(goal: Vector2) -> Vector2:
	var delta: Vector2=goal-SHOULDER
	var a: float=(ELBOW-SHOULDER).length()
	var b: float=(PALM-ELBOW).length()
	var r: float=delta.length()
	var theta: float=delta.angle()+acos(clampf((r*r+a*a-b*b)/(2*r*a),-1,1))
	var elbow: Vector2=SHOULDER+Vector2.from_angle(theta)*a
	return Vector2(theta-(ELBOW-SHOULDER).angle(),(goal-elbow).angle()-(PALM-ELBOW).angle())

func advance(seconds: float) -> void:
	t=seconds
	var q: float=fposmod(t,40.0)
	# Eleven deliberate arm key poses, 0.9 s sip hold; no elastic skin deformation.
	sip=roundf(maxf(gate(8.0,10.3,11.2,13.6,q),gate(28.0,30.3,31.2,33.6,q))*10)/10.0
	aim=gate(17.4,18.5,23.4,24.4,q)
	var angle: float=sin(t*TAU/5.6)*deg_to_rad(1.6)
	var floor_y: float=-INF
	for p in runner:floor_y=maxf(floor_y,p.rotated(angle).y)
	rocking_angle=angle
	rocking_offset=Vector2(-angle*45,-floor_y)
	root.rotation=angle
	root.position=rocking_pivot*2+rocking_offset*2
	var rest: Vector2=arm_angles(Vector2(74,60))
	var drink: Vector2=arm_angles(Vector2(73,42))
	var angles: Vector2=rest.lerp(drink,sip)
	upper.rotation=angles.x
	lower.rotation=angles.y-angles.x
	# Cup is an actual child of the hand. Counter-rotate its wrist gently to stay upright.
	cup.rotation=-angles.y
	cup.depth_tilt=smoothstep(.55,1.0,sip)
	# A small rigid head lift acknowledges the visitor; torso/legs stay fixed.
	look=roundf(gate(35.65,36.45,37.45,38.25,q)*6.0)/6.0
	head.rotation=.035*sip-deg_to_rad(12.0)*look
	head.position=Vector2(76,40)*2+Vector2(roundf(look*2.0),-roundf(look*2.0))
	visitor.set_time(q)
	cup.time=t;cup.queue_redraw()
	pose=4+roundi(4*aim)
	var shot_age: float=-1.0
	for st in shots:
		if q>=st and q<st+.8:
			shot_age=q-st
			# Exactly one shot and one recoil per trigger; no forward/reverse firing-frame playback.
			pose=8
	var recoil: float=0.0
	if shot_age>=0 and shot_age<.34:recoil=sin(PI*clampf(shot_age/.34,0,1))*.075
	gun.rotation=-.34*aim-recoil
	gun.tex=gun_textures[pose];gun.queue_redraw()
	var warm: float=.018*sin(t*5.1)+.01*sin(t*8.3)
	person.modulate=Color(.91+warm,.86+warm,.82+warm,1)
	var muzzle_local: Vector2=actor_origin+gun.position+((MUZZLES[clampi(pose-8,0,7)]-Vector2(84,48))*2).rotated(gun.rotation)
	vfx.tip=rocking_pivot+(muzzle_local-rocking_pivot).rotated(angle)+rocking_offset
	vfx.mark=target_center(q);vfx.since=shot_age;vfx.queue_redraw()
	# Structural invariants: rigid body and constant bone lengths throughout the loop.
	assert(root.scale==Vector2.ONE and is_zero_approx(root.skew))
	assert(body.transform==Transform2D.IDENTITY)
	assert(is_equal_approx(root.position.y/2+floor_y,rocking_pivot.y))
	for rigid in [person,upper,lower,head,gun,hand,cup]:
		assert(rigid.scale==Vector2.ONE and is_zero_approx(rigid.skew))
	assert(cup.get_parent()==hand and cup.position==Vector2.ZERO)
	assert(person.scale==Vector2.ONE and person.position==actor_origin)
	assert(is_equal_approx(lower.position.length(),(ELBOW-SHOULDER).length()*2))
	assert(is_equal_approx(hand.position.length(),(PALM-ELBOW).length()*2))
	queue_redraw()

func line(a: Vector2,b: Vector2,col: Color,width: float=1) -> void:
	draw_line(a.round(),b.round(),col,width,false)

func _draw() -> void:
	draw_texture_rect(room_texture,Rect2(0,0,640,360),false)
	draw_fire()
	draw_target()
	draw_texture_rect(HAT,Rect2(164,197,30,19),false,Color(.84,.76,.71,1))
	draw_rain()
	draw_set_transform(Vector2(335,314),0,Vector2(1,.18))
	draw_circle(Vector2.ZERO,62,Color(.012,.008,.009,.3))
	draw_set_transform(Vector2.ZERO)

func draw_fire() -> void:
	var time: float=floorf(t*12)/12.0
	# 12 images per original 0.4-second interval, on the same native pixel grid.
	# Sharp polygon contours are rasterized with solid palette colors: no blur/fade.
	var frame: int=int(floorf(t*30.0+.00001))%96
	var layers: Array=preload("res://src/bossmaker/title_rooms/rbm_gentleman_title_fire_frames.gd").POSES[frame]
	var colors: Array[Color]=[Color("e58250"),Color("ffae5b"),Color("ffe18b")]
	for layer in range(3):
		var points: PackedVector2Array=[]
		for p in layers[layer]:points.append(Vector2(482+float(p[0])*2,172+float(p[1])*2))
		draw_colored_polygon(points,colors[layer])
	# Inbetween the detached tip too, keeping the same take-off and disappearance.
	var phase: float=float(frame)/12.0
	if phase>=1.0 and phase<5.0:
		var travel: float=clampf(phase-2.0,0.0,3.0)
		var size_y: float=lerpf(0.0,4.0,phase-1.0) if phase<2.0 else (lerpf(4.0,2.0,phase-2.0) if phase<3.0 else (2.0 if phase<4.0 else lerpf(2.0,0.0,phase-4.0)))
		var spark: Vector2=Vector2(506+travel*2.0,174-travel*4.0)
		if size_y>=1.0:draw_rect(Rect2(spark,Vector2(2,size_y)),Color("efa16a"))

	# A handful of glowing embers; no attack-style explosions.
	for k in range(4):
		var f: float=fposmod(time*.24+k*.27,1.0)
		draw_rect(Rect2(Vector2(482+k*13+sin(f*9)*3,229-f*52).round(),Vector2(2,2)),Color(1,.53,.18,sin(f*PI)*.7))
	var flicker: float=.03+.02*sin(time*6.1)
	draw_colored_polygon(PackedVector2Array([Vector2(449,270),Vector2(553,271),Vector2(594,304),Vector2(411,301)]),Color(1,.49,.13,flicker))

func target_motion(q: float) -> Vector3:
	var swing: float=0.0
	var offset: Vector2=Vector2.ZERO
	for st in shots:
		var since: float=q-st-.10
		if since>=0 and since<2.8:
			swing-=sin(since*9.0)*exp(-since*1.55)*.60
			offset.x+=sin(since*12.0)*exp(-since*2.0)*2.5
			offset.y-=sin(since*9.0)*exp(-since*2.0)*1.0
	return Vector3(offset.x,offset.y,swing)

func target_center(q: float) -> Vector2:
	var motion: Vector3=target_motion(q)
	return Vector2(618,91)+Vector2(motion.x,motion.y)+Vector2(0,14).rotated(motion.z)

func draw_target() -> void:
	var q: float=fposmod(t,40.0)
	var motion: Vector3=target_motion(q)
	var flash: float=0.0
	for st in shots:
		var since: float=q-st-.10
		if since>=0 and since<.22:flash=maxf(flash,1.0-since/.22)
	draw_set_transform(Vector2(618,91)+Vector2(motion.x,motion.y),motion.z)
	line(Vector2.ZERO,Vector2(0,6),Color("735536"),2)
	draw_circle(Vector2(0,14),10,Color("26212a"))
	draw_circle(Vector2(0,14),8,Color("b7996f").lerp(Color("ffe4a9"),flash*.85))
	draw_circle(Vector2(0,14),5,Color("41332c").lerp(Color("efc381"),flash*.8))
	draw_circle(Vector2(0,14),3,Color("c7aa78"))
	draw_rect(Rect2(-1,13,2,2),Color("672d29"))
	for i in range(shots.size()):
		if q>=shots[i]+.10:
			var mark: Vector2=Vector2(-3,15) if i==0 else Vector2(3,12)
			line(mark+Vector2(-2,-1),mark+Vector2(2,2),Color("e8c38b"),2)
			draw_circle(mark,2,Color("151216"))
	draw_set_transform(Vector2.ZERO)

func draw_rain() -> void:
	for k in range(9):
		var f: float=fposmod(t*.17+k*.117,1)
		var x: float=44+fposmod(k*17.3,61)
		var y: float=12+f*166
		if y>64 and y<74 or y>128 and y<137:continue
		line(Vector2(x,y),Vector2(x-1,y+7),Color(.35,.55,.81,.24),1)
