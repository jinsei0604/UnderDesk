extends "res://src/bossmaker/visuals/rbm_slime_vfx.gd"
const SkinShader=preload("res://src/bossmaker/visuals/rbm_slime_punch.gdshader")
const PunchTiming=preload("res://src/bossmaker/visuals/rbm_slime_punch_timing.gd")
var surface: Sprite2D
var skin_material: ShaderMaterial
var white: ImageTexture
var extension:=0.0
var formation:=0.0
var shadow: Polygon2D
var shadow_points:=PackedVector2Array()

func _ready() -> void:
	shadow=Polygon2D.new()
	shadow.color=Color(.07,.03,.06,.3)
	shadow.show_behind_parent=true
	shadow_points.resize(12)
	add_child(shadow)
	skin_material=ShaderMaterial.new()
	skin_material.shader=SkinShader
	skin_material.set_shader_parameter("skin",slime)
	var img:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	white=ImageTexture.create_from_image(img)
	surface=Sprite2D.new()
	surface.texture=white
	surface.centered=false
	surface.material=skin_material
	surface.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(surface)
	# impact remains in _draw via draw order; surface is behind parent commands.
	surface.show_behind_parent=true

func advance(t: float) -> void:
	super.advance(t)
	# Retiming body and arm together keeps their junction fixed on the flank.
	state=motion.sample(kind,PunchTiming.pose_time(t))
	if not is_instance_valid(surface): return
	extension=float(state.arm)
	formation=smoothstep(.36,.67,t)*(1.0-smoothstep(1.63,1.94,t))
	var sc: Vector2=state.scale
	for i in range(12):
		var a:=i*TAU/12.0
		shadow_points[i]=snap(motion.home+Vector2(0,1)+Vector2(cos(a)*101*sc.x,sin(a)*12))
	shadow.polygon=shadow_points
	var root:=Vector2(-48*sc.x,-52*sc.y)
	var seed:=root+Vector2(-18.0*formation,0)
	var target: Vector2=motion.contact-motion.home
	var end:=seed.lerp(target,extension)
	var origin:=Vector2(minf(end.x-42,-130),minf(end.y-48,-180)).floor()
	var bounds:=Vector2(260-origin.x,32-origin.y).ceil()
	surface.position=(motion.home+origin).round()
	surface.scale=bounds
	skin_material.set_shader_parameter("quad_origin",origin)
	skin_material.set_shader_parameter("quad_size",bounds)
	skin_material.set_shader_parameter("body_scale",sc)
	skin_material.set_shader_parameter("pixel_scale",pixel_scale)
	skin_material.set_shader_parameter("root_pos",root)
	skin_material.set_shader_parameter("tip",end)
	skin_material.set_shader_parameter("bud",formation)
	skin_material.set_shader_parameter("crush",float(state.crush))
	skin_material.set_shader_parameter("ripple",float(state.ripple))
	skin_material.set_shader_parameter("age",t)

func _draw() -> void:
	if state.is_empty() or age<0: return
	impact(motion.contact,age-.91,.36,Palette.color_for(attack_attribute),1.0)
