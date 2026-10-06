extends Node2D
## Transparent nearest-neighbor raster layer; allocated only for this boss.
const Vfx = preload("res://src/bossmaker/visuals/rbm_astronaut_vfx.gd")
const Cosmos = preload("res://src/bossmaker/visuals/rbm_astronaut_cosmos.gdshader")
var viewport: SubViewport
var picture: TextureRect
var effects: Node2D
var cosmos: ColorRect
var unit := 116.0/66.0

func configure(canvas_size: Vector2) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(ceil(canvas_size.x/unit),ceil(canvas_size.y/unit))
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_disable_input = true
	add_child(viewport)
	cosmos = ColorRect.new()
	cosmos.size = Vector2(viewport.size)
	cosmos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nebula := ShaderMaterial.new()
	nebula.shader = Cosmos
	nebula.set_shader_parameter("canvas_size",Vector2(viewport.size))
	cosmos.material = nebula
	cosmos.visible = false
	viewport.add_child(cosmos)
	effects = Vfx.new()
	effects.canvas_size = Vector2(viewport.size)
	viewport.add_child(effects)
	picture = TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.size = Vector2(viewport.size)*unit
	add_child(picture)

func advance(t: float) -> void:
	cosmos.material.set_shader_parameter("age",t)
	effects.age = t
	effects.queue_redraw()
