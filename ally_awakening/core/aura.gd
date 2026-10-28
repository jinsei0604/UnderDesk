extends "res://ally_awakening/core/ink.gd"
## Attach at the character's foot, or supply a foot Callable. Owns no sprite.
const SHADER=preload("res://ally_awakening/core/aura.gdshader")
const IDS=["hero","butler","healer","samurai","tank"]
const COLORS=[Color("ef4847"),Color("509cf5"),Color("f2cd55"),Color("a4f255"),Color("b7bbc2")]
@export_enum("hero","butler","healer","samurai","tank") var character_id: String="hero"
@export_range(0,1) var intensity:=1.0
var foot_provider: Callable
var active:=false
var blend:=0.0
var mode:=0
var veil: ColorRect
var shader: ShaderMaterial
var foreground: Node2D
func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=2
	mode=maxi(0,IDS.find(character_id))
	color=COLORS[mode]
	shader=ShaderMaterial.new()
	shader.shader=SHADER
	shader.set_shader_parameter("mode",mode)
	shader.set_shader_parameter("hue",color)
	veil=ColorRect.new()
	veil.position=Vector2(-90,-150)
	veil.size=Vector2(180,180)
	veil.mouse_filter=Control.MOUSE_FILTER_IGNORE
	veil.material=shader
	add_child(veil)
	foreground=preload("res://ally_awakening/core/aura_foreground.gd").new()
	foreground.color=color
	foreground.z_index=2
	add_child(foreground)
	visible=false
func start(fade_in: bool=true) -> void:
	active=true
	visible=true
	if not fade_in:blend=1.0
func stop(immediate: bool=false) -> void:
	active=false
	if immediate:
		blend=0.0
		visible=false
func _process(dt: float) -> void:
	if not active and blend<=0:return
	if foot_provider.is_valid():position=Vector2(foot_provider.call()).round()
	age+=dt
	blend=move_toward(blend,1.0 if active else 0.0,dt*2.5)
	visible=blend>0
	shader.set_shader_parameter("age",age)
	shader.set_shader_parameter("intensity",blend*intensity)
	foreground.age=age
	foreground.strength=blend*intensity
	foreground.queue_redraw()
	queue_redraw()
func _draw() -> void:
	if blend<=0:return
	strength=blend*intensity
	ring(Vector2(0,-2),Vector2(34,9),tint(color,.32),2)
	for i in 12:
		var q:=fposmod(age*(.28 if mode==1 else .40)+i*.317,1.0)
		var x:=sin(i*5.71)*42+sin(age*1.8+i)*5
		if absf(x)<20:x+=24*signf(x+.01)
		var p:=Vector2(x,-q*128)
		var c:=tint(color,sin(q*PI)*.65)
		if mode==1:diamond(p,2,4,c)
		elif mode==2 and i%3==0:star(p,3,c)
		elif mode==3:line(PackedVector2Array([p,p+Vector2(8,-3)]),c)
		elif mode==4:draw_rect(Rect2(p.snapped(Vector2(2,2)),Vector2(3,3)),c)
		else:draw_rect(Rect2(p.snapped(Vector2(2,2)),Vector2(2,4)),c)
