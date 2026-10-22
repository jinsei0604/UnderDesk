extends Node2D
const Aura = preload("res://src/bossmaker/title_rooms/rbm_astronaut_hand_aura.gd")
const ROOM = preload("res://assets_bossmaker/title_rooms/astronaut/room.png")
const SEATED = preload("res://assets_bossmaker/title_rooms/astronaut/seated.png")
const ASTRO = preload("res://assets_bossmaker/battle/astronaut/frames/00.png")
const ASTRO_WORK = preload("res://assets_bossmaker/battle/astronaut/frames/01.png")
var t: float = 0.0
var clock_base: float = 0.0
var rig: Dictionary = {"origin":[280,139],"palm":[133,94]}
var aura: Node2D
var hand: Vector2
var arm_angle: float = 0.0
var head_angle: float = 0.0
var working: bool = true
var mouse_work: float = 0.0
var aura_strength: float = 0.0
var lift_amount: float = 0.0
var rest_amount: float = 0.0
var upper_angle: float = 0.0
var character_mesh: ArrayMesh
var mesh_rest: PackedVector2Array
var mesh_uv: PackedVector2Array
var mesh_indices: PackedInt32Array
var pointer: Vector2 = Vector2(82,26)
var mouse_motion: Vector2 = Vector2.ZERO

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var now: Dictionary = Time.get_datetime_dict_from_system(false)
	clock_base=now.hour*3600+now.minute*60+now.second
	aura=Aura.new()
	add_child(aura)
	build_character_mesh()
	advance(0)

func build_character_mesh() -> void:
	# One intact full-character texture: every adjacent triangle shares vertices.
	# The sleeve, elbow and torso can never move as disconnected cutout layers.
	var cols: int=72
	var rows: int=92
	for y in range(rows):
		for x in range(cols):
			var p: Vector2=Vector2(x*2,y*2)
			mesh_rest.append(p)
			mesh_uv.append(p/Vector2(142,182))
	for y in range(rows-1):
		for x in range(cols-1):
			var i: int=y*cols+x
			mesh_indices.append_array(PackedInt32Array([i,i+1,i+cols,i+1,i+cols+1,i+cols]))
	character_mesh=ArrayMesh.new()

func deform_character(p: Vector2) -> Vector2:
	var shoulder: Vector2=Vector2(82,66)
	var elbow: Vector2=Vector2(99,94)
	var posed_elbow: Vector2=shoulder+(elbow-shoulder).rotated(upper_angle)
	var upper: Vector2=shoulder+(p-shoulder).rotated(upper_angle)
	var lower: Vector2=posed_elbow+(p-elbow).rotated(upper_angle+arm_angle)
	var forearm_weight: float=smoothstep(86.0,107.0,p.x)
	var arm_mask: float=smoothstep(73.0,83.0,p.x)*smoothstep(54.0,66.0,p.y)*(1.0-smoothstep(104.0,113.0,p.y))
	var result: Vector2=p.lerp(upper.lerp(lower,forearm_weight),arm_mask)
	# Subtle torso/head follow-through fades into the waist and fixed chair.
	var body_weight: float=smoothstep(46.0,66.0,p.x)*(1.0-smoothstep(101.0,119.0,p.y))
	result+=Vector2(mouse_work*1.2-rest_amount*1.5,-lift_amount*.65)*body_weight
	var head_weight: float=(1.0-smoothstep(37.0,61.0,p.y))*smoothstep(20.0,39.0,p.x)
	var neck: Vector2=Vector2(70,51)
	result+=(neck+(p-neck).rotated(head_angle)-p)*head_weight
	return result

func update_character_mesh() -> void:
	var verts: PackedVector3Array=PackedVector3Array()
	for p in mesh_rest:
		var v: Vector2=deform_character(p)
		verts.append(Vector3(v.x,v.y,0))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts
	arrays[Mesh.ARRAY_TEX_UV]=mesh_uv
	arrays[Mesh.ARRAY_INDEX]=mesh_indices
	character_mesh.clear_surfaces()
	character_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func sync_clock() -> void:
	var now: Dictionary=Time.get_datetime_dict_from_system(false)
	clock_base=now.hour*3600+now.minute*60+now.second-t

func smooth_gate(a: float,b: float,c: float,d: float,x: float) -> float:
	return smoothstep(a,b,x)*(1.0-smoothstep(c,d,x))

func advance(seconds: float) -> void:
	t=seconds
	var q: float=fposmod(t,36.0)
	mouse_work=maxf(smooth_gate(5.4,6.1,8.1,8.8,q),smooth_gate(29.0,29.7,31.0,31.7,q))
	var rest: float=smooth_gate(13.0,13.6,14.7,15.4,q)
	var lift: float=smooth_gate(20.3,21.0,22.8,23.5,q)
	lift_amount=lift
	rest_amount=rest
	aura_strength=smooth_gate(21.0,21.3,22.3,22.7,q)
	working=mouse_work<.2 and rest<.2 and q<20.2 or q>23.6 and mouse_work<.2
	var tap: float=0.0
	if working and sin(q*2.7)+sin(q*1.13) > -1.0:
		tap=roundf(sin(q*15.5)*.75+sin(q*23.7)*.60)
	mouse_motion=Vector2(sin((q-6.1)*2.1),sin((q-6.1)*1.4)) * mouse_work
	# Typing rotates around an attached elbow; it never translates the forearm.
	upper_angle=-.055*lift-.018*mouse_work
	arm_angle=-.78*lift+.17*mouse_work+tap*.018+mouse_motion.y*.018
	head_angle=-.04*rest-.035*lift
	var origin: Vector2=Vector2(rig.origin[0],rig.origin[1])
	var palm: Vector2=Vector2(rig.palm[0],rig.palm[1])
	hand=origin+deform_character(palm)
	aura.position=(hand+Vector2(12,-8)).round()
	# The in-world PC cursor moves only while the glove operates the mouse.
	if mouse_work>.01:
		var u: float=clampf((q-6.1)/2.0,0.0,1.0) if q<20.0 else clampf((q-29.7)/1.3,0.0,1.0)
		pointer=Vector2(82,26).lerp(Vector2(125,38),smoothstep(0.0,1.0,u)) if q<20.0 else Vector2(125,38).lerp(Vector2(82,26),smoothstep(0.0,1.0,u))
		pointer+=Vector2(sin(u*PI*2)*3,sin(u*PI)*8)
	update_character_mesh()
	aura.age=t
	aura.intensity=aura_strength
	aura.queue_redraw()
	queue_redraw()

func stroke(a: Vector2,b: Vector2,c: Color,width: float=1.0) -> void:
	draw_line(a.round(),b.round(),c,width,false)

func _draw() -> void:
	if rig.is_empty():return
	draw_texture(ROOM,Vector2.ZERO)
	# Recompose the original mouse as a separate prop within seated arm reach.
	# These source desk strips preserve the existing room's pixel texture.
	draw_rect(Rect2(447,229,39,5),Color("1b2947"))
	draw_texture_rect_region(ROOM,Rect2(447,234,39,12),Rect2(486,241,26,7))
	stroke(Vector2(464,228),Vector2(468,236),Color("10182b"),2)
	draw_texture_rect_region(ROOM,Rect2(Vector2(413,234)+mouse_motion.round(),Vector2(27,12)),Rect2(447,229,38,17))
	# Warm practical lights stay secondary to the monitor.
	for lamp in [Vector2(96,187),Vector2(403,64),Vector2(580,185)]:
		for j in range(4,0,-1):
			draw_circle(lamp,float(j)*9,Color(.015,.025,.06,.11),true,-1,false)
	draw_clock()
	draw_monitor()
	# Floor contact, drawn on the same discrete pixel grid.
	draw_set_transform(Vector2(338,322),0,Vector2(1,.18))
	draw_circle(Vector2.ZERO,53,Color(.005,.01,.025,.32),true,-1,false)
	draw_set_transform(Vector2.ZERO)
	var origin: Vector2=Vector2(rig.origin[0],rig.origin[1])
	var light: float=.018*sin(t*.71)+.008*sin(t*1.21)
	var shade: Color=Color(.68+light,.76+light,.91+light,1)
	draw_set_transform(origin)
	draw_mesh(character_mesh,SEATED,Transform2D.IDENTITY,shade)
	draw_set_transform(Vector2.ZERO)
	draw_steam()
	# A couple of distant windows vary slowly; the room stays still.
	var window_alpha: float=.10+.12*(.5+.5*sin(t*.35))
	draw_rect(Rect2(27,139,2,3),Color(.9,.61,.25,window_alpha))
	draw_rect(Rect2(18,157,2,2),Color(.66,.73,.90,window_alpha*.6))

func draw_clock() -> void:
	var secs: float=clock_base+t
	var c: Vector2=Vector2(560,56)
	var minute: float=fposmod(secs/60.0,60.0)
	var hour: float=fposmod(secs/3600.0,12.0)
	var second: float=fposmod(floorf(secs),60.0)
	stroke(c,c+Vector2(sin(hour*TAU/12),-cos(hour*TAU/12))*18,Color("141927"),2)
	stroke(c,c+Vector2(sin(minute*TAU/60),-cos(minute*TAU/60))*26,Color("141927"),2)
	stroke(c-Vector2(sin(second*TAU/60),-cos(second*TAU/60))*4,c+Vector2(sin(second*TAU/60),-cos(second*TAU/60))*27,Color("555063"),1)
	draw_circle(c,2,Color("171c29"),true,-1,false)

func screen_point(p: Vector2) -> Vector2:
	var top: Vector2=Vector2(356,129).lerp(Vector2(501,119),p.x/144)
	var bottom: Vector2=Vector2(356,203).lerp(Vector2(501,207),p.x/144)
	return top.lerp(bottom,p.y/84).round()

func screen_rect(r: Rect2,c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([screen_point(r.position),screen_point(r.position+Vector2(r.size.x,0)),screen_point(r.end),screen_point(r.position+Vector2(0,r.size.y))]),c)

func draw_monitor() -> void:
	var glow: float=.95+.02*sin(t*.71)
	screen_rect(Rect2(0,0,144,84),Color(.10,.16,.27,1)*Color(glow,glow,glow,1))
	screen_rect(Rect2(0,0,144,5),Color("597eaa"))
	screen_rect(Rect2(0,76,144,8),Color("263c5b"))
	screen_rect(Rect2(3,8,20,65),Color("293d59"))
	screen_rect(Rect2(112,8,29,65),Color("263852"))
	for x in range(28,109,10):stroke(screen_point(Vector2(x,10)),screen_point(Vector2(x,72)),Color(.31,.47,.61,.25))
	for y in range(12,72,10):stroke(screen_point(Vector2(27,y)),screen_point(Vector2(107,y)),Color(.31,.47,.61,.25))
	# Shipped, unmodified astronaut sprite and existing work pose on the PC.
	var frame: Texture2D=ASTRO_WORK if mouse_work>.5 else ASTRO
	draw_texture_rect_region(frame,Rect2(415,139,22,46),Rect2(33,20,32,67),Color(.75,.82,.95,1))
	draw_texture_rect_region(ASTRO,Rect2(360,140,11,23),Rect2(33,20,32,67),Color(.60,.72,.84,1))
	draw_texture_rect_region(ASTRO_WORK,Rect2(360,170,11,23),Rect2(33,20,32,67),Color(.60,.72,.84,1))
	for i in range(5):
		var yy: float=14+i*11
		screen_rect(Rect2(117,yy,18,2),Color("5d738c"))
		screen_rect(Rect2(117,yy+4,8+(i*5)%12,2),Color("3e5977"))
	for i in range(4):screen_rect(Rect2(117+i*5,68,4,4),[Color("9dadae"),Color("465576"),Color("6092a4"),Color("af8359")][i])
	var step: int=int(t/3.0)%4
	screen_rect(Rect2(31+step*15,79,10,2),Color("7698b4"))
	# Small selection handles change with the work, not a desktop cursor.
	var col: Color=Color(.56,.74,.86,.40+.12*sin(t))
	for p in [Vector2(407,136),Vector2(442,136),Vector2(407,188),Vector2(442,188)]:draw_rect(Rect2(p,Vector2(2,2)),col)
	# This cursor belongs only to the monitor's editor, never the captured desktop.
	var cursor_shape: Array=[Vector2(0,0),Vector2(0,9),Vector2(2,7),Vector2(4,11),Vector2(6,10),Vector2(4,6),Vector2(8,6)]
	var cursor_poly: PackedVector2Array=PackedVector2Array()
	for p in cursor_shape:cursor_poly.append(screen_point(pointer+p))
	draw_colored_polygon(cursor_poly,Color("bfdaeb"))
	var border: PackedVector2Array=cursor_poly.duplicate()
	border.append(border[0])
	draw_polyline(border,Color("15243b"),1,false)
	if mouse_work>.8 and (fposmod(t,1.15)<.13):
		screen_rect(Rect2(117,36,18,2),Color("8baec4"))

func draw_steam() -> void:
	for k in range(3):
		var phase: float=fposmod(t*.19+k*.33,1.0)
		var yy: float=220-phase*17
		var xx: float=531+sin(phase*6+k)*2
		var alpha: float=sin(phase*PI)*.19
		stroke(Vector2(xx,yy),Vector2(xx+1,yy-3),Color(.66,.73,.82,alpha))
		stroke(Vector2(xx+1,yy-3),Vector2(xx,yy-5),Color(.66,.73,.82,alpha*.65))
