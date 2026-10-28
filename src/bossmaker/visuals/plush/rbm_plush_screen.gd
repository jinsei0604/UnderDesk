extends Node2D
var stage: Control
func _draw() -> void:
	if not is_instance_valid(stage):return
	if stage.kind=="awakened_all":stage.Revision.screen(self,stage.age,stage)
