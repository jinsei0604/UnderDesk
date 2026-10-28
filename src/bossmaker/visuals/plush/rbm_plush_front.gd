extends Node2D
var stage: Control
func _draw() -> void:
	if is_instance_valid(stage):stage.draw_foreground(self)
