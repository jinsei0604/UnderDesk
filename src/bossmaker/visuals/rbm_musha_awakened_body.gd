extends Node2D
## 覚醒後の朽ちた機械武者の本体描画(覚醒アトラス/振り下ろし4コマ)。承認済みの
## 倍率・足元アンカーのままNearestで描き、足元は動かさない。覚醒演出中は外套を
## 横帯に分割して変形させる(頭と足は固定)。眼は暗色で覆ってから細い赤線だけを描く。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const ROOT := "res://assets_bossmaker/battle/musha_awakened/"

var _atlas: Texture2D
var _swing: Texture2D
var _state: Dictionary = {}
var _foot := Vector2.ZERO
var age := 0.0

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func configure() -> void:
	_atlas = load(ROOT + "awakened.png") as Texture2D
	_swing = load(ROOT + "swing.png") as Texture2D

func advance(state: Dictionary, foot: Vector2, time: float) -> void:
	_state = state
	_foot = foot
	age = time
	queue_redraw()

func _draw() -> void:
	if _state.is_empty():
		return
	var index := int(_state.get("index", 3))
	if str(_state.get("source", "awakened")) == "swing":
		if _swing == null:
			return
		var region: Rect2 = Motion.SWING_RECTS[index]
		draw_set_transform(_foot.round(), 0.0, Vector2.ONE * Motion.SWING_SCALE)
		draw_texture_rect_region(_swing, Rect2(region.position - Motion.SWING_FEET[index], region.size), region)
		draw_set_transform(Vector2.ZERO)
		return
	if _atlas == null:
		return
	var r: Rect2 = Motion.ATLAS_RECTS[index]
	var atlas_foot: Vector2 = Motion.ATLAS_FEET[index]
	draw_set_transform(_foot.round(), 0.0, Vector2.ONE * Motion.ATLAS_SCALE)
	var bands := float(_state.get("bands", 0.0))
	if bands > 0.0:
		# 外套の横帯を伸縮させて変形させる。頭と足の位置は固定。
		var y := 0
		while y < int(r.size.y):
			var h := minf(12.0, r.size.y - y)
			var f := y / r.size.y
			var envelope := smoothstep(.30, .55, f) * (1.0 - smoothstep(.82, .95, f))
			var stretch := 1.0 + envelope * bands * (.09 + .045 * sin(age * 16.0 + f * 13.0))
			var dst := Rect2(r.position - atlas_foot + Vector2(0, y), Vector2(r.size.x, h))
			dst.position.x -= dst.size.x * (stretch - 1.0) * .5
			dst.size.x *= stretch
			draw_texture_rect_region(_atlas, dst, Rect2(r.position + Vector2(0, y), Vector2(r.size.x, h)))
			y += 12
	else:
		draw_texture_rect_region(_atlas, Rect2(r.position - atlas_foot, r.size), r)
	# 原画の眼を暗色で覆い、点灯時だけ細い横線の赤眼を描く(消灯時は赤を一切描かない)。
	var e: Vector2 = Vector2(Motion.ATLAS_EYES[index]) - atlas_foot
	draw_rect(Rect2(e - Vector2(7, 10), Vector2(15, 21)), Color(.035, .027, .032))
	if bool(_state.get("eye", true)):
		draw_rect(Rect2(e - Vector2(10, 2), Vector2(20, 4)), Color(1, .04, .05))
		draw_rect(Rect2(e - Vector2(4, 1), Vector2(8, 2)), Color(1, .6, .52))
	draw_set_transform(Vector2.ZERO)
