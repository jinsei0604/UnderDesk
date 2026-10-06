extends Node2D
## Quiet awakened-dragon atmosphere only. The dragon itself keeps its static idle.
var age := 0.0
var _stage: Control
var _foot := Vector2.ZERO
var _tail := Vector2.ZERO
var _height := 180.0
var _pixel := 3.0

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 6

func configure(stage: Control) -> void:
	_stage = stage
	refresh()

func refresh() -> void:
	_update_anchors()
	queue_redraw()

func _process(delta: float) -> void:
	age += delta
	_update_anchors()
	if visible:
		queue_redraw()

func _update_anchors() -> void:
	visible = false
	if not is_instance_valid(_stage) or str(_stage._asset_ids.get("boss", "")) != "dragon_awakened":
		return
	var boss: Control = _stage._visuals.get("boss")
	if not is_instance_valid(boss):
		return
	visible = true
	_height = _stage.Assets.display_height("dragon")
	_foot = boss.position + boss.foot_position()
	var tail_pixel := Vector2(513, 341)
	var pose_records: Array = boss._pose_rects
	var pose_index := int(boss.pose)
	if pose_index >= 0 and pose_index < pose_records.size():
		var landmarks: Dictionary = pose_records[pose_index].get("landmarks", {})
		var tail_values: Array = landmarks.get("tail", [513, 341])
		tail_pixel = Vector2(float(tail_values[0]), float(tail_values[1]))
	_tail = boss.position + tail_pixel * float(boss._pixel_scale)
	# Dedicated dragon actions draw an animated body while the normal actor is hidden.
	var presentation: Node2D = _stage._skill_presentation
	if not boss.visible and is_instance_valid(presentation):
		var body: Node2D = presentation.get("_body")
		if is_instance_valid(body):
			if body.has_method("foot_point"):
				_foot = Vector2(body.call("foot_point")) + presentation.position
			if body.has_method("tail_point"):
				_tail = Vector2(body.call("tail_point")) + presentation.position

func _draw() -> void:
	if not visible:
		return
	# Five faint drifting smoke fragments and seven embers remain deliberately sparse.
	for i in range(5):
		var q := fposmod(age * 0.22 + float(i) * 0.219, 1.0)
		var side := sin(float(i) * 7.13)
		var point := _foot + Vector2(side * _height * 0.69 + sin(age + float(i)) * 5.0, -q * _height * 1.08)
		var radius := 6.0 + q * 7.0
		var alpha := sin(q * PI) * 0.28
		_cloud(point, radius, Color(0.022, 0.019, 0.031, alpha))
	for i in range(7):
		var q := fposmod(age * 0.27 + float(i) * 0.157, 1.0)
		var point := _foot + Vector2(sin(float(i) * 5.9) * _height * 0.64 + sin(age * 1.8 + float(i)) * 7.0, -q * _height * 1.05)
		draw_rect(Rect2(point.snapped(Vector2.ONE * _pixel), Vector2(_pixel, _pixel)), Color(0.91, 0.045, 0.075, sin(q * PI) * 0.60))
	# Continuous black flame at the original tail tip, with crisp deep-red edging.
	for i in range(3):
		var origin := _tail + Vector2(float(i - 1) * 5.0, 5.0)
		var h := 23.0 + sin(age * 7.0 + float(i) * 2.0) * 5.0
		_flame(origin, 8.0, h, Color(0.26, 0.013, 0.036, 0.88))
		_flame(origin, 5.0, h * 0.86, Color(0.016, 0.015, 0.021, 0.97))

func _cloud(center: Vector2, radius: float, color: Color) -> void:
	var point := center.snapped(Vector2.ONE * _pixel)
	var size := ceilf(radius / _pixel) * _pixel
	draw_rect(Rect2(point - Vector2(size, size * 0.5), Vector2(size * 2.0, size)), color)
	draw_rect(Rect2(point - Vector2(size * 0.5, size), Vector2(size, size * 2.0)), color)

func _flame(origin: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		origin + Vector2(-width, 0), origin + Vector2(-width, -height * 0.35),
		origin + Vector2(-width * 0.3, -height * 0.27), origin + Vector2(-width * 0.6, -height * 0.66),
		origin + Vector2(0, -height), origin + Vector2(width * 0.55, -height * 0.64),
		origin + Vector2(width * 0.22, -height * 0.41), origin + Vector2(width * 0.85, -height * 0.51),
		origin + Vector2(width, 0),
	])
	for i in range(points.size()):
		points[i] = points[i].snapped(Vector2.ONE * _pixel)
	if not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, color)
