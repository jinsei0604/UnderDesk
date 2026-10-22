extends RefCounted
## Fixed half-resolution material field; owned by the victory layer, including cancellation.
const NOISE = preload("res://assets_bossmaker/effects/awakened_defeat/density.png")
const MATERIALS := {
	"musha":preload("res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_ink.gdshader"),
	"astronaut":preload("res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_nebula.gdshader"),
	"gentleman":preload("res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_powder.gdshader")
}
var viewport: SubViewport
var material: ShaderMaterial
var display: Sprite2D

func attach(parent: Node, subject: String, origin: Vector2) -> void:
	viewport = SubViewport.new()
	viewport.name = "VictoryDefeatVolume"
	viewport.size = Vector2i(640,360)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	material = ShaderMaterial.new()
	material.shader = MATERIALS[subject]
	material.set_shader_parameter("density_tex",NOISE)
	material.set_shader_parameter("origin",origin)
	material.set_shader_parameter("age",-10.0)
	var rect := ColorRect.new()
	rect.size = Vector2(640,360)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	viewport.add_child(rect)
	display = Sprite2D.new()
	display.name = "VictoryDefeatVolumeDisplay"
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var composite := CanvasItemMaterial.new()
	composite.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	display.material = composite
	display.centered = false
	display.scale = Vector2(2,2)
	display.z_index = -1
	parent.add_child(display)

func advance(t: float) -> void:
	material.set_shader_parameter("age",t)
	if t > 2.5:
		display.hide()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

