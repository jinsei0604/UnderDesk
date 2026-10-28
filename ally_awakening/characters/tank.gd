extends "res://ally_awakening/core/sequence.gd"
const DUST_PATH="res://ally_awakening/textures/dust_atlas.png"
var dust: TextureRect
var dust_frames: Array[AtlasTexture]=[]
func _ready() -> void:
	super._ready()
	dust=TextureRect.new()
	dust.position=Vector2(-250,-130)
	dust.size=Vector2(500,180)
	dust.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	dust.mouse_filter=Control.MOUSE_FILTER_IGNORE
	dust.z_index=-1
	add_child(dust)
func warm_paths() -> Array[String]:
	var paths:=super.warm_paths()
	paths.append(DUST_PATH)
	return paths
func prepare() -> bool:
	if not super.prepare():return false
	var atlas=load(DUST_PATH) as Texture2D
	if atlas==null:return false
	dust_frames.clear()
	for i in 60:
		var frame:=AtlasTexture.new()
		frame.atlas=atlas
		frame.region=Rect2(i%10*250,i/10*90,250,90)
		dust_frames.append(frame)
	dust.texture=dust_frames[0]
	dust.modulate.a=0
	return true
func advance(t: float) -> void:
	super.advance(t)
	if dust_frames.is_empty():return
	dust.texture=dust_frames[clampi(int((age-release_time)*30),0,59)]
	dust.modulate.a=tail(2.0)*vfx_strength if age>=release_time else 0.0
func _init() -> void:
	character_id="tank"
	color=Color("b7bbc2")
	duration=5.85
	release_time=3.15
	quiet_time=2.98
func shake_amplitude() -> float:return 8.0
func pose_at(t: float) -> String:
	if t<2.98:return "b:0"
	if t<3.15:return "b:6"
	if t<4.45:return "s:19"
	if t<4.65:return "b:6"
	return "b:0"
func _rock(p: Vector2,size: float,a: float) -> void:
	poly(PackedVector2Array([p+Vector2(-size,-size*.4),p+Vector2(-size*.4,-size),p+Vector2(size*.8,-size*.7),p+Vector2(size,size*.6),p+Vector2(-size*.7,size)]),tint(Color("777479"),a))
	line(PackedVector2Array([p+Vector2(-size,-size*.4),p+Vector2(-size*.4,-size),p+Vector2(size*.8,-size*.7)]),tint(color,a),2)
func _draw() -> void:
	if not active:return
	var white:=Color("f2eee5")
	var b:=smoothstep(.25,2.8,age)
	if age<release_time:
		# Pressure pushes a broad polygonal seal into the floor; stones rise slowly.
		for i in 8:
			var a:=i*TAU/8
			var p:=Vector2(cos(a)*110,sin(a)*25)
			line(PackedVector2Array([Vector2.ZERO,p*.5+Vector2(5,-4),p*b]),tint(color,b*.65),3)
		for i in 12:
			var x:=sin(i*5.9)*120
			var y:=cos(i*4.1)*18-pow(b,2)*(25+i%4*12)
			_rock(Vector2(x,y),4+i%4,b)
		for i in 3:
			var q:=fposmod(age*.32+i*.33,1)
			ring(Vector2(0,-q*120),Vector2(76,18)*(1-q*.25),tint(color,b*sin(q*PI)*.7),4)
		if age>=quiet_time:
			ring(Vector2.ZERO,Vector2(92,22),tint(white,1),4)
			star(Vector2(0,-24),18,tint(white,1))
	else:
		var t:=age-release_time
		var k:=tail(1.9)
		# Heavy vertical compression becomes a ground-hugging expanding shock front.
		for i in 3:
			var q:=maxf(0,t-i*.14)
			var rad:=45+pow(q,.5)*290
			ring(Vector2(0,5),Vector2(rad,rad*.24),tint(white,maxf(0,1-q/1.1)*.8),maxf(2,12-q*10))
		for i in 12:
			var a:=i*TAU/12
			var d:=Vector2(cos(a),sin(a)*.3)
			var end:=d*(100+minf(1,t*4)*140)
			line(PackedVector2Array([d*30,d*60+Vector2(7,-4),d*85-Vector2(4,1),d*120+Vector2(3,4),end]),tint(color,k*.7),3)
			line(PackedVector2Array([d*85-Vector2(4,1),d*120+Vector2(20,-12)]),tint(color,k*.5),2)
		for i in 28:
			var a:=i*2.399
			var v:=Vector2(cos(a)*155,-70-absf(sin(a))*125)
			var p:=Vector2(sin(i*4.1)*60,0)+v*t+Vector2(0,t*t*155)
			_rock(p,(4+i%5)*k,k)
		for i in 7:
			var p:=Vector2((i-3)*(30+t*28),10)
			flame(p,24*k,(45+i%3*15)*k,0,tint(Color("a19b94"),k*.25))
		if t<.23:
			for i in 9:
				var a:=-PI+i*PI/8
				ray(Vector2(0,-5),Vector2(cos(a),sin(a)),190,12,tint(white,(1-t/.23)*.8))
