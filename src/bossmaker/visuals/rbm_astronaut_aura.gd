extends Node2D
const PixelLayer = preload("res://src/bossmaker/visuals/rbm_astronaut_pixel_layer.gd")
var _stage: Control
var _layer: Node2D
var age := 0.0

func configure(stage: Control) -> void:
	_stage = stage
	z_index = 0
	refresh()

func refresh() -> void:
	if not is_instance_valid(_stage): return
	visible = str(_stage._asset_ids.get("boss","")) == "astronaut_awakened"
	if not visible:
		if is_instance_valid(_layer): _layer.queue_free(); _layer = null
		return
	if not is_instance_valid(_layer):
		_layer = PixelLayer.new()
		add_child(_layer)
		_layer.configure(_stage.size)
		_layer.effects.aura_only = true
		_layer.effects.power = .8
		_layer.cosmos.visible = true

func _process(delta: float) -> void:
	if not is_instance_valid(_stage): return
	var enabled: bool = str(_stage._asset_ids.get("boss","")) == "astronaut_awakened"
	if enabled != visible: refresh()
	if not visible or not is_instance_valid(_layer): return
	age += delta
	var driver = _stage._skill_presentation
	var transforming: bool = is_instance_valid(driver) and driver.get("action_kind") == "awakening"
	_layer.visible = not transforming
	_layer.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if transforming else SubViewport.UPDATE_ALWAYS
	_layer.effects.boss = _stage._foot("boss")/_layer.unit
	_layer.cosmos.material.set_shader_parameter("center",_layer.effects.boss-Vector2(0,45))
	_layer.advance(age)
