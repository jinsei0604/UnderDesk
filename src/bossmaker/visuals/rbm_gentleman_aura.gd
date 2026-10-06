extends Node2D
const Smoke = preload("res://src/bossmaker/visuals/rbm_gentleman_smoke.gdshader")
var _stage: Control
var _smoke: ColorRect
var age := 0.0
func configure(stage: Control) -> void:
	_stage=stage
	z_index=0
	refresh()
func refresh() -> void:
	if not is_instance_valid(_stage): return
	visible=str(_stage._asset_ids.get("boss",""))=="gentleman_awakened"
	if visible and not is_instance_valid(_smoke):
		_smoke=ColorRect.new()
		_smoke.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_smoke.material=ShaderMaterial.new()
		_smoke.material.shader=Smoke
		add_child(_smoke)
	if is_instance_valid(_smoke): _smoke.visible=visible
func _process(delta: float) -> void:
	if not is_instance_valid(_stage): return
	var enabled: bool=str(_stage._asset_ids.get("boss",""))=="gentleman_awakened"
	if enabled!=visible: refresh()
	if not visible or not is_instance_valid(_smoke): return
	age+=delta
	var driver: Node=_stage._skill_presentation
	_smoke.visible=not (is_instance_valid(driver) and driver.has_method("is_gentleman"))
	var unit: float=_stage.Assets.display_height("gentleman")/94.0
	_smoke.position=(_stage._foot("boss")-Vector2(70,151)*unit).round()
	_smoke.size=Vector2(140,180)*unit
	_smoke.material.set_shader_parameter("age",age)
