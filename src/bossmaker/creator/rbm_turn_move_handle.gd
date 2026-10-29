class_name RBMTurnMoveHandle
extends Button

## HARDCORE の通常行動（ターンのカード）の並べ替えのつまみ（2026-10-29 ユーザー指示）。
## カードの右に置く「Move（四方向矢印）」のボタン。長押ししてから動かすとドラッグになり、
## 呼び出し側（RBMCreatorStep4ActionPatterns）が挿入型で並べ替える（2つを入れ替える方式ではない）。
## 押してすぐ離した時は何もしない。押した後はマウスがボタンの外へ出ても、離すまでこのボタンが入力を受ける
## （Godot のマウスフォーカス）ので、カードの上を通ってもカードは開かない。

signal drag_started()
signal drag_moved(global_position: Vector2)
signal drag_ended(global_position: Vector2)

const World := preload("res://src/bossmaker/rbm_world_ui.gd")
## 長押しと見なすまでの時間（秒）。
const LONG_PRESS_SEC := 0.3
## 四方向矢印のドット絵（7×7、1マス＝2px。RBMWorldUi.icon() と同じ作り方・大きさ）。
const MOVE_ICON_PIXELS := [
	[3, 0],
	[2, 1], [3, 1], [4, 1],
	[1, 2], [3, 2], [5, 2],
	[0, 3], [1, 3], [2, 3], [3, 3], [4, 3], [5, 3], [6, 3],
	[1, 4], [3, 4], [5, 4],
	[2, 5], [3, 5], [4, 5],
	[3, 6],
]

var _holding := false
var _dragging := false
var _press_serial := 0

static func move_icon(color: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for p in MOVE_ICON_PIXELS:
		img.fill_rect(Rect2i(p[0] * 2, p[1] * 2, 2, 2), color)
	return ImageTexture.create_from_image(img)

func _init() -> void:
	text = ""
	icon = move_icon(World.CREATOR_MUTED)
	expand_icon = false
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(44.0, 44.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tooltip_text = TranslationServer.translate("長押ししてから動かすと、ターンの順番を変えられます")
	theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON

func is_dragging() -> bool:
	return _dragging

func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if mouse.pressed:
			_holding = true
			_press_serial += 1
			var serial := _press_serial
			get_tree().create_timer(LONG_PRESS_SEC).timeout.connect(func(): _on_long_press(serial))
		else:
			_holding = false
			if _dragging:
				_dragging = false
				icon = move_icon(World.CREATOR_MUTED)
				drag_ended.emit(mouse.global_position)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		accept_event()
		drag_moved.emit(motion.global_position)

func _on_long_press(serial: int) -> void:
	if not is_instance_valid(self) or not _holding or serial != _press_serial or _dragging:
		return
	_dragging = true
	icon = move_icon(World.CREATOR_ACCENT)
	drag_started.emit()

func _notification(what: int) -> void:
	## 途中で画面が閉じた・隠れた時は、ドラッグを終わらせずに捨てる（呼び出し側が並べ替えを取り消す）。
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_holding = false
		_dragging = false
