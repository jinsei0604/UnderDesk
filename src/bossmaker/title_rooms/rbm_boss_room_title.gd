extends Control
## Shared title shell. Boss rooms own only their 640x360 artwork and animation;
## the official logo, START, input and short handoff stay common to every boss.
signal boot_completed

const Catalog = preload("res://src/bossmaker/title_rooms/rbm_title_room_catalog.gd")
const OfficialTitle = preload("res://src/bossmaker/title_boot_preview/rbm_title_boot_preview.gd")
const Audio = preload("res://src/bossmaker/rbm_audio.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const START_FADE_SECONDS := 0.18
const FRAME_SECONDS := 1.0 / 30.0

var selected_room_id: String
var _room: Node2D
var _viewport: SubViewport
var _canvas: Control
var _start_button: Button
var _start_label: Label
var _elapsed: float = 0.0
var _frame_accumulator: float = 0.0
var _revealed: bool = false
var _starting: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	var backdrop := ColorRect.new()
	backdrop.color = Color("050a14")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_viewport = SubViewport.new()
	_viewport.name = "RoomViewport"
	_viewport.size = Vector2i(640, 360)
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	selected_room_id = Catalog.session_room_id()
	_room = Catalog.create_session_room()
	if _room.has_method("native_viewport_size"):
		_viewport.size = _room.native_viewport_size()
		_room.scale = Vector2(_viewport.size) / Vector2(640, 360)
	_viewport.add_child(_room)
	_canvas = Control.new()
	_canvas.name = "SharedTitleCanvas"
	_canvas.size = DESIGN_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var art := TextureRect.new()
	art.texture = _viewport.get_texture()
	art.size = DESIGN_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(art)
	if _room.has_method("take_presentation_layer"):
		_canvas.add_child(_room.take_presentation_layer())
	_build_shared_ui()
	resized.connect(_layout)
	visibility_changed.connect(_sync_visibility)
	_layout()
	_finish_initial_layout.call_deferred()

func _build_shared_ui() -> void:
	# Reuse the exact approved wordmark node; never run the old boot animation.
	var source := OfficialTitle.new()
	source._load_preview_fonts()
	var layer: Control = source._build_title_layer()
	var logo: Label = layer.get_node("TitleText")
	layer.remove_child(logo)
	logo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	logo.position = Vector2(70, 141)
	logo.size = Vector2(610, 56)
	_canvas.add_child(logo)
	layer.free()
	source.free()
	_start_label = Label.new()
	_start_label.name = "StartLabel"
	_start_label.text = "START"
	_start_label.add_theme_font_override("font", preload("res://assets_bossmaker/fonts/Rajdhani-Medium.ttf"))
	_start_label.add_theme_font_size_override("font_size", 26)
	_start_label.add_theme_color_override("font_color", Color("eef5f6"))
	_start_label.add_theme_color_override("font_shadow_color", Color("090f1a"))
	_start_label.add_theme_constant_override("shadow_offset_y", 2)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.position = Vector2(560, 653)
	_start_label.size = Vector2(160, 40)
	_start_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_start_label)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	# Full-window activation, including letterboxed areas after a resize.
	_start_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_start_button.focus_mode = Control.FOCUS_ALL
	# Play only the explicit START cue; suppress automatic hover/focus/button audio.
	_start_button.set_meta("rbm_audio_bound", true)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_start_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_start_button.pressed.connect(_on_start_pressed)
	add_child(_start_button)

func _finish_initial_layout() -> void:
	# A locale button is added after this launcher by the home screen. Scene order,
	# not z_index, determines GUI picking, so keep the modal layer last as well.
	get_parent().move_child(self, -1)
	_start_button.grab_focus()
	_sync_visibility()

func _layout() -> void:
	if not is_instance_valid(_canvas): return
	var factor: float = minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - DESIGN_SIZE * factor) * 0.5

func _sync_visibility() -> void:
	var active: bool = is_visible_in_tree() and not _revealed
	set_process(active)
	set_process_input(active)
	if _room.has_method("set_presentation_active"): _room.set_presentation_active(active)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func _process(delta: float) -> void:
	_elapsed += delta
	_frame_accumulator += delta
	if _frame_accumulator < FRAME_SECONDS: return
	_frame_accumulator = fmod(_frame_accumulator, FRAME_SECONDS)
	_room.advance(_elapsed)
	if _room.has_method("sync_clock"): _room.sync_clock()
	_start_label.modulate.a = 0.87 + 0.09 * sin(_elapsed * 0.75)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _revealed: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed: _on_start_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed: _on_start_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_on_start_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Prevent keyboard focus/activation leaking into the obscured home menu.
		get_viewport().set_input_as_handled()

func _on_start_pressed() -> void:
	if _starting or _revealed or not is_visible_in_tree(): return
	_starting = true
	Audio.cue(self, "ui_confirm")
	_start_button.disabled = true
	_start_label.modulate.a = 1.0
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, START_FADE_SECONDS)
	fade.tween_callback(_finish_start)

func _finish_start() -> void:
	if _revealed: return
	_revealed = true
	_start_button.release_focus()
	hide()
	_sync_visibility()
	boot_completed.emit()
