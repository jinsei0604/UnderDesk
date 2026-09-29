extends Node2D
## 朽ちた機械武者の本体描画。poses.png(ポーズ矩形)とdesign.png(静止姿)を、
## 承認済みの倍率・足元アンカーのままNearestで描く。位置は演出側が渡す
## 足元(ステージ座標)で決まり、固定座標は持たない。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
const ROOT := "res://assets_bossmaker/battle/musha/"
const AWAKENED_ROOT := "res://assets_bossmaker/battle/musha_awakened/"
## 覚醒後の静止姿(design.png)の足元と表示倍率(rbm_musha_awakened_motion.gd と同じ確定値)。
const AWAKENED_FOOT := Vector2(299, 575)
const AWAKENED_SCALE := 0.335

## 覚醒後(musha_awakened)の自己強化/回復では、静止姿として覚醒後の抜刀待機を描く
## (通常版の納刀・俯く姿勢は覚醒後の外見には無い)。
var awakened := false
var _poses: Texture2D
var _idle: Texture2D
var _state: Dictionary = {}

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func configure() -> void:
	_poses = load(ROOT + "poses.png") as Texture2D
	_idle = load(AWAKENED_ROOT + "design.png" if awakened else ROOT + "design.png") as Texture2D

func advance(state: Dictionary) -> void:
	_state = state
	queue_redraw()

func _draw() -> void:
	if _state.is_empty() or not bool(_state.get("visible", true)):
		return
	var pose := int(_state.get("pose", Motion.IDLE))
	var image: Texture2D
	var region: Rect2
	var anchor: Vector2
	var factor := Motion.POSE_SCALE
	if pose < 0:
		image = _idle
		if image == null:
			return
		region = Rect2(Vector2.ZERO, image.get_size())
		factor = Motion.IDLE_DISPLAY_HEIGHT / region.size.y
		anchor = Vector2(region.size.x / 2.0, region.size.y)
		if awakened:
			factor = AWAKENED_SCALE
			anchor = AWAKENED_FOOT
	else:
		image = _poses
		if image == null:
			return
		region = Motion.POSE_RECTS[pose]
		anchor = Motion.POSE_ANCHORS[pose] - region.position
	var flip := bool(_state.get("flip", false))
	draw_set_transform(Vector2(_state.get("foot", Vector2.ZERO)).round(), 0.0, Vector2(-1.0 if flip else 1.0, float(_state.get("scale_y", 1.0))))
	draw_texture_rect_region(image, Rect2(-anchor * factor, region.size * factor), region, Color(1, 1, 1, float(_state.get("alpha", 1.0))))
	draw_set_transform(Vector2.ZERO)
