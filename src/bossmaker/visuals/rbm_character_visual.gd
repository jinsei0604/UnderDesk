class_name RBMCharacterVisual
extends Control

## Each pose uses the same native pixel grid, scale and grounded pivot.
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
var asset_id := ""
var pose := 0
var _pixel_scale := 1.0
var _texture: Texture2D
var _flash := 0.0
var _blink_clock := 0.0
var _pose_rects: Array = []
var _canvas_size := Assets.POSE_CANVAS
var _foot := Assets.POSE_FOOT

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(id: String, height: float) -> void:
	asset_id = id
	var metadata_path := Assets.ROOT + id + "/frames.json"
	var body_height := 400.0
	if FileAccess.file_exists(metadata_path):
		var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if metadata is Dictionary:
			body_height = maxf(1.0, float(metadata.get("body_height", 400)))
			_pose_rects = metadata.get("poses", [])
			var canvas: Array = metadata.get("canvas", [512, 512])
			var foot: Array = metadata.get("foot", [256, 460])
			_canvas_size = Vector2(canvas[0], canvas[1])
			_foot = Vector2(foot[0], foot[1])
	_pixel_scale = height / body_height
	size = _canvas_size * _pixel_scale
	set_pose(0)

func set_pose(index: int) -> void:
	pose = clampi(index, 0, Assets.POSE_COUNT - 1)
	_texture = Assets.texture(asset_id, pose)
	queue_redraw()

func reset_pose() -> void:
	set_pose(0)

func foot_position() -> Vector2:
	return _foot * _pixel_scale

func visible_rect() -> Rect2:
	if pose < _pose_rects.size():
		var bounds: Array = _pose_rects[pose]["bbox"]
		return Rect2(Vector2(bounds[0], bounds[1]) * _pixel_scale, Vector2(bounds[2], bounds[3]) * _pixel_scale)
	return Rect2()

func all_pose_bounds() -> Rect2:
	var bounds := Rect2()
	for record in _pose_rects:
		var box: Array = record["bbox"]
		var rect := Rect2(Vector2(box[0], box[1]) * _pixel_scale, Vector2(box[2], box[3]) * _pixel_scale)
		bounds = bounds.merge(rect) if bounds.has_area() else rect
	return bounds

func _has_point(point: Vector2) -> bool:
	return visible_rect().has_point(point)

func impact_flash() -> void:
	_flash = 0.10
	queue_redraw()

func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		queue_redraw()

func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false, Color(1.5, 1.25, 1.15) if _flash > 0.0 else Color.WHITE)
