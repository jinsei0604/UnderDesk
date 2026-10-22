extends Node2D
## Compile the optional awakened defeat material during the encounter's existing intro wait.
## Transparent, temporary, and owned by the director; it never changes readiness or battle timing.
const Volume = preload("res://src/bossmaker/visuals/encounter/rbm_awakened_defeat_volume.gd")
var subject := ""
var field: RefCounted
var _frames := 0

static func supports(asset_id: String) -> bool:
	return Volume.MATERIALS.has(asset_id.trim_suffix("_awakened"))

func _ready() -> void:
	name = "AwakenedDefeatMaterialWarmup"
	field = Volume.new()
	field.attach(self,subject,Vector2(640,360))

func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= 4:
		field.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		queue_free()
