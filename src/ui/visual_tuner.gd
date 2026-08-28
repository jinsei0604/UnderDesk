extends Control

## UNDERDESK visual motion tuner v1.
##
## This is deliberately an external-data overlay. It never writes GDScript,
## combat state, SP, damage, or save-game data. Debug builds may edit and save
## a user:// JSON override; release builds only read the checked-in res://
## default and never expose the panel.

signal adjustments_changed

const DEFAULT_DATA_PATH := "res://skill_motion_data/sotiris/eos_burst.json"
const USER_DATA_PATH := "user://skill_motion_data/sotiris/eos_burst.json"
const PANEL_WIDTH := 370.0
const SWORD_MASK_RADIUS := 8.0
const SWORD_PIVOT_MASK_RADIUS := 10.0

const SKILL_IDS: Array[String] = [
	"rapid_slash", "healing", "soul_break", "eos_burst",
]
const SKILL_NAMES: Array[String] = [
	"Rapid Slash", "Healing", "Soul Break", "Eos Burst",
]
const PLAYBACK_SPEEDS: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0]

var _debug_ui_enabled := OS.is_debug_build()
var _sheet_path := ""
var _cell_size := Vector2i(222, 222)
var _frame_count := 0
var _sword_bases: Array[Vector2] = []
var _sword_tips: Array[Vector2] = []
var _frame_durations: Array[float] = []
var _source_images: Array[Image] = []
var _source_textures: Array[Texture2D] = []
var _adjusted_texture_cache: Dictionary = {}
var _frames: Array[Dictionary] = []

var _current_frame := 0
var _selected_skill := "eos_burst"
var _playing := false
var _loop_enabled := true
var _playback_speed := 1.0
var _playback_accumulator := 0.0
var _show_original := false
var _syncing_ui := false

var _panel: PanelContainer
var _skill_select: OptionButton
var _frame_label: Label
var _loop_check: CheckBox
var _before_check: CheckBox
var _speed_select: OptionButton
var _status_label: Label
var _rows: Dictionary = {}
var _edit_controls: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	visible = false
	set_process(false)
	if _debug_ui_enabled:
		_build_panel()
	resized.connect(_on_resized)


func configure_eos(
		sheet_path: String,
		cell_size: Vector2i,
		frame_count: int,
		sword_bases: Array[Vector2],
		sword_tips: Array[Vector2],
		frame_durations: Array[float]
) -> void:
	_sheet_path = sheet_path
	_cell_size = cell_size
	_frame_count = frame_count
	_sword_bases = sword_bases.duplicate()
	_sword_tips = sword_tips.duplicate()
	_frame_durations = frame_durations.duplicate()
	_reset_all_frames_to_defaults()
	_load_source_sheet()
	_load_motion_data()
	_current_frame = clampi(_current_frame, 0, maxi(0, _frame_count - 1))
	_refresh_ui()
	queue_redraw()


func toggle_panel() -> void:
	if not _debug_ui_enabled:
		return
	visible = not visible
	set_process(visible)
	if visible:
		move_to_front()
		_refresh_ui()
	queue_redraw()


func is_panel_open() -> bool:
	return visible


func eos_adjusted_frame(
		frame_index: int, fallback: Texture2D, preview: bool = false
) -> Texture2D:
	if not _valid_frame(frame_index):
		return fallback
	if preview and _show_original:
		return fallback
	var sword := _sword_data(frame_index)
	var offset := Vector2(float(sword["x"]), float(sword["y"]))
	var rotation_degrees := float(sword["rotation"])
	if offset.is_zero_approx() and is_zero_approx(rotation_degrees):
		return fallback
	var cache_key := "%d|%.3f|%.3f|%.3f" % [
		frame_index, offset.x, offset.y, rotation_degrees,
	]
	if _adjusted_texture_cache.has(cache_key):
		return _adjusted_texture_cache[cache_key]
	var source := _source_image(frame_index, fallback)
	if source == null:
		return fallback
	var adjusted := _compose_sword_adjustment(
		source, _sword_bases[frame_index], _sword_tips[frame_index],
		offset, deg_to_rad(rotation_degrees))
	var texture := ImageTexture.create_from_image(adjusted)
	_adjusted_texture_cache[cache_key] = texture
	return texture


func eos_character_offset(frame_index: int, preview: bool = false) -> Vector2:
	if not _valid_frame(frame_index) or (preview and _show_original):
		return Vector2.ZERO
	var character := _character_data(frame_index)
	return Vector2(float(character["x"]), float(character["y"]))


func eos_pair_character_offset(
		frame_a: int, frame_b: int, mix_b: float
) -> Vector2:
	var effective_b := frame_b if _valid_frame(frame_b) else frame_a
	return eos_character_offset(frame_a).lerp(
		eos_character_offset(effective_b), clampf(mix_b, 0.0, 1.0))


func eos_transform_sword_point(
		frame_index: int, local_point: Vector2, preview: bool = false
) -> Vector2:
	if not _valid_frame(frame_index) or (preview and _show_original):
		return local_point
	var sword := _sword_data(frame_index)
	var pivot := _sword_bases[frame_index]
	var offset := Vector2(float(sword["x"]), float(sword["y"]))
	return (local_point - pivot).rotated(deg_to_rad(float(sword["rotation"]))) \
		+ pivot + offset


func eos_frame_has_adjustment(frame_index: int) -> bool:
	if not _valid_frame(frame_index):
		return false
	var character := _character_data(frame_index)
	var sword := _sword_data(frame_index)
	return not is_zero_approx(float(character["x"])) \
		or not is_zero_approx(float(character["y"])) \
		or not is_zero_approx(float(sword["x"])) \
		or not is_zero_approx(float(sword["y"])) \
		or not is_zero_approx(float(sword["rotation"]))


func eos_pair_has_adjustment(frame_a: int, frame_b: int) -> bool:
	return eos_frame_has_adjustment(frame_a) \
		or (_valid_frame(frame_b) and eos_frame_has_adjustment(frame_b))


func save_motion_data() -> Error:
	return save_motion_data_to(USER_DATA_PATH)


func save_motion_data_to(path: String) -> Error:
	var global_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_error := DirAccess.make_dir_recursive_absolute(global_dir)
	if dir_error != OK:
		_set_status("Save failed: %s" % error_string(dir_error), true)
		return dir_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		_set_status("Save failed: %s" % error_string(open_error), true)
		return open_error
	file.store_string(JSON.stringify(_motion_payload(), "\t"))
	file.close()
	_set_status("Saved: %s" % ProjectSettings.globalize_path(path))
	return OK


func load_motion_data_from(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	_apply_payload(parsed as Dictionary)
	_invalidate_adjustments()
	_refresh_ui()
	return OK


func _process(delta: float) -> void:
	if not visible or not _playing or _selected_skill != "eos_burst" or _frame_count <= 0:
		return
	_playback_accumulator += delta * _playback_speed
	var guard := 0
	while _playback_accumulator >= _duration_for_frame(_current_frame) and guard < _frame_count + 1:
		_playback_accumulator -= _duration_for_frame(_current_frame)
		guard += 1
		if _current_frame >= _frame_count - 1:
			if not _loop_enabled:
				_playing = false
				_playback_accumulator = 0.0
				break
			_current_frame = 0
		else:
			_current_frame += 1
		_refresh_ui()
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var preview_width := maxf(160.0, size.x - PANEL_WIDTH - 28.0)
	var preview_rect := Rect2(8.0, 8.0, preview_width, maxf(120.0, size.y - 16.0))
	draw_rect(preview_rect, Color(0.015, 0.018, 0.03, 0.88), true)
	draw_rect(preview_rect, Color(0.78, 0.66, 0.25, 0.72), false, 2.0)
	if _selected_skill != "eos_burst" or not _valid_frame(_current_frame):
		draw_string(
			ThemeDB.fallback_font, preview_rect.get_center() - Vector2(120.0, 0.0),
			"v1 preview: Eos Burst only", HORIZONTAL_ALIGNMENT_CENTER, 240.0, 16,
			Color(0.92, 0.86, 0.68))
		return
	var source_texture := _source_textures[_current_frame]
	var texture := eos_adjusted_frame(_current_frame, source_texture, true)
	if texture == null:
		return
	var max_side := minf(preview_rect.size.x - 48.0, preview_rect.size.y - 72.0)
	var scale_factor := maxf(0.25, minf(2.0, max_side / float(_cell_size.y)))
	var draw_size := Vector2(_cell_size) * scale_factor
	var character_offset := eos_character_offset(_current_frame, true) * scale_factor
	var draw_pos := Vector2(
		preview_rect.get_center().x - draw_size.x * 0.5,
		preview_rect.end.y - draw_size.y - 24.0) + character_offset
	var old_filter := texture_filter
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
	texture_filter = old_filter
	var base := eos_transform_sword_point(
		_current_frame, _sword_bases[_current_frame], true) * scale_factor + draw_pos
	var tip := eos_transform_sword_point(
		_current_frame, _sword_tips[_current_frame], true) * scale_factor + draw_pos
	draw_line(base, tip, Color(1.0, 0.84, 0.22, 0.74), 1.0)
	draw_circle(base, 4.0, Color(0.2, 1.0, 0.55, 0.9), false, 1.5)
	draw_string(
		ThemeDB.fallback_font, preview_rect.position + Vector2(14.0, 24.0),
		"EOS BURST  |  frame %d / %d%s" % [
			_current_frame, _frame_count - 1, "  |  BEFORE" if _show_original else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.94, 0.9, 0.72))


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "UNDERDESKVisualTunerPanel"
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -PANEL_WIDTH - 8.0
	_panel.offset_top = 8.0
	_panel.offset_right = -8.0
	_panel.offset_bottom = -8.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.06, 0.09, 0.98)
	panel_style.border_color = Color(0.72, 0.59, 0.2, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(PANEL_WIDTH - 48.0, 0.0)
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)

	var title := Label.new()
	title.text = "UNDERDESK Visual Tuner  v1"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34))
	content.add_child(title)
	var hint := Label.new()
	hint.text = "F10: close  |  Shift+F10: REWIND II debug"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.68, 0.7, 0.78))
	content.add_child(hint)

	_add_section_title(content, "Skill")
	_skill_select = OptionButton.new()
	for i in SKILL_IDS.size():
		_skill_select.add_item(SKILL_NAMES[i])
		_skill_select.set_item_metadata(i, SKILL_IDS[i])
	_skill_select.select(SKILL_IDS.find(_selected_skill))
	_skill_select.item_selected.connect(_on_skill_selected)
	content.add_child(_skill_select)

	_add_section_title(content, "Playback")
	_frame_label = Label.new()
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_frame_label)
	var frame_buttons := HBoxContainer.new()
	frame_buttons.add_child(_make_button("< Prev", _on_previous_frame))
	frame_buttons.add_child(_make_button("Next >", _on_next_frame))
	content.add_child(frame_buttons)
	var play_buttons := HBoxContainer.new()
	play_buttons.add_child(_make_button("Play", _on_play))
	play_buttons.add_child(_make_button("Pause", _on_pause))
	play_buttons.add_child(_make_button("Stop", _on_stop))
	play_buttons.add_child(_make_button("Restart", _on_restart))
	content.add_child(play_buttons)
	var playback_options := HBoxContainer.new()
	_loop_check = CheckBox.new()
	_loop_check.text = "Loop"
	_loop_check.button_pressed = true
	_loop_check.toggled.connect(_on_loop_toggled)
	playback_options.add_child(_loop_check)
	_speed_select = OptionButton.new()
	for speed in PLAYBACK_SPEEDS:
		_speed_select.add_item("%.2fx" % speed)
		_speed_select.set_item_metadata(_speed_select.item_count - 1, speed)
	_speed_select.select(3)
	_speed_select.item_selected.connect(_on_speed_selected)
	playback_options.add_child(_speed_select)
	_before_check = CheckBox.new()
	_before_check.text = "Before"
	_before_check.toggled.connect(_on_before_toggled)
	playback_options.add_child(_before_check)
	content.add_child(playback_options)

	_add_section_title(content, "Character (per frame)")
	_rows["character_x"] = _add_value_row(content, "X", -128.0, 128.0, 0.5, "character", "x")
	_rows["character_y"] = _add_value_row(content, "Y", -128.0, 128.0, 0.5, "character", "y")

	_add_section_title(content, "Sword (per frame)")
	_rows["sword_x"] = _add_value_row(content, "X", -128.0, 128.0, 0.5, "sword", "x")
	_rows["sword_y"] = _add_value_row(content, "Y", -128.0, 128.0, 0.5, "sword", "y")
	_rows["sword_rotation"] = _add_value_row(
		content, "Rotation (deg)", -180.0, 180.0, 0.1, "sword", "rotation")

	_add_section_title(content, "Save")
	var save_buttons := HBoxContainer.new()
	save_buttons.add_child(_make_button("Reset Frame", _on_reset_frame))
	save_buttons.add_child(_make_button("Save JSON", _on_save))
	content.add_child(save_buttons)
	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84))
	content.add_child(_status_label)


func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var label := Label.new()
	label.text = "[ %s ]" % text
	label.add_theme_color_override("font_color", Color(0.9, 0.79, 0.42))
	parent.add_child(label)


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button


func _add_value_row(
		parent: VBoxContainer, label_text: String,
		minimum: float, maximum: float, step: float,
		section: String, key: String
) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.x = 105.0
	spin.value_changed.connect(_on_numeric_value_changed.bind(section, key))
	header.add_child(spin)
	box.add_child(header)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value_changed.connect(_on_numeric_value_changed.bind(section, key))
	box.add_child(slider)
	parent.add_child(box)
	_edit_controls.append(spin)
	_edit_controls.append(slider)
	return {"spin": spin, "slider": slider}


func _on_skill_selected(index: int) -> void:
	_selected_skill = str(_skill_select.get_item_metadata(index))
	_playing = false
	_playback_accumulator = 0.0
	if _selected_skill == "eos_burst":
		_set_status("Eos Burst is editable in v1")
	else:
		_set_status("Selectable for expansion; v1 editing target is Eos Burst")
	_refresh_ui()
	queue_redraw()


func _on_previous_frame() -> void:
	if _frame_count <= 0:
		return
	_playing = false
	_current_frame = posmod(_current_frame - 1, _frame_count)
	_playback_accumulator = 0.0
	_refresh_ui()
	queue_redraw()


func _on_next_frame() -> void:
	if _frame_count <= 0:
		return
	_playing = false
	_current_frame = posmod(_current_frame + 1, _frame_count)
	_playback_accumulator = 0.0
	_refresh_ui()
	queue_redraw()


func _on_play() -> void:
	if _selected_skill == "eos_burst" and _frame_count > 0:
		_playing = true
		set_process(true)


func _on_pause() -> void:
	_playing = false


func _on_stop() -> void:
	_playing = false
	_current_frame = 0
	_playback_accumulator = 0.0
	_refresh_ui()
	queue_redraw()


func _on_restart() -> void:
	_current_frame = 0
	_playback_accumulator = 0.0
	_playing = _selected_skill == "eos_burst"
	_refresh_ui()
	queue_redraw()


func _on_loop_toggled(enabled: bool) -> void:
	_loop_enabled = enabled


func _on_speed_selected(index: int) -> void:
	_playback_speed = float(_speed_select.get_item_metadata(index))


func _on_before_toggled(enabled: bool) -> void:
	_show_original = enabled
	queue_redraw()


func _on_numeric_value_changed(value: float, section: String, key: String) -> void:
	if _syncing_ui or _selected_skill != "eos_burst" or not _valid_frame(_current_frame):
		return
	var frame := _frames[_current_frame]
	var section_data: Dictionary = frame[section]
	section_data[key] = value
	frame[section] = section_data
	_frames[_current_frame] = frame
	_invalidate_adjustments()
	_refresh_ui()
	_set_status("Frame %d modified (unsaved)" % _current_frame)


func _on_reset_frame() -> void:
	if not _valid_frame(_current_frame):
		return
	_frames[_current_frame] = _default_frame(_current_frame)
	_invalidate_adjustments()
	_refresh_ui()
	_set_status("Frame %d reset (unsaved)" % _current_frame)


func _on_save() -> void:
	save_motion_data()


func _on_resized() -> void:
	queue_redraw()


func _refresh_ui() -> void:
	if not _debug_ui_enabled or _panel == null:
		return
	_syncing_ui = true
	if _frame_label != null:
		_frame_label.text = "Frame: %d / %d%s" % [
			_current_frame, maxi(0, _frame_count - 1), "  PLAY" if _playing else "  PAUSE"]
	var editable := _selected_skill == "eos_burst" and _valid_frame(_current_frame)
	for control in _edit_controls:
		if control is Range:
			(control as Range).editable = editable
	if editable:
		_set_row_value("character_x", float(_character_data(_current_frame)["x"]))
		_set_row_value("character_y", float(_character_data(_current_frame)["y"]))
		_set_row_value("sword_x", float(_sword_data(_current_frame)["x"]))
		_set_row_value("sword_y", float(_sword_data(_current_frame)["y"]))
		_set_row_value("sword_rotation", float(_sword_data(_current_frame)["rotation"]))
	_syncing_ui = false


func _set_row_value(row_key: String, value: float) -> void:
	if not _rows.has(row_key):
		return
	var row: Dictionary = _rows[row_key]
	(row["spin"] as SpinBox).value = value
	(row["slider"] as HSlider).value = value


func _set_status(text: String, is_error: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color", Color(1.0, 0.45, 0.42) if is_error else Color(0.72, 0.82, 0.9))


func _load_source_sheet() -> void:
	_source_images.clear()
	_source_textures.clear()
	if _sheet_path.is_empty() or _frame_count <= 0:
		return
	var bytes := FileAccess.get_file_as_bytes(_sheet_path)
	if bytes.is_empty():
		push_error("Visual tuner source sheet missing: %s" % _sheet_path)
		return
	var sheet := Image.new()
	var load_error := sheet.load_png_from_buffer(bytes)
	if load_error != OK:
		push_error("Visual tuner source sheet decode failed: %s" % error_string(load_error))
		return
	for frame_index in _frame_count:
		var region := Rect2i(Vector2i(frame_index * _cell_size.x, 0), _cell_size)
		var image := sheet.get_region(region)
		image.convert(Image.FORMAT_RGBA8)
		_source_images.append(image)
		_source_textures.append(ImageTexture.create_from_image(image))


func _load_motion_data() -> void:
	var path := DEFAULT_DATA_PATH
	if _debug_ui_enabled and FileAccess.file_exists(USER_DATA_PATH):
		path = USER_DATA_PATH
	var load_error := load_motion_data_from(path)
	if load_error == ERR_FILE_NOT_FOUND:
		_set_status("No motion JSON found; using zero adjustments")
	elif load_error != OK:
		_set_status("Motion JSON load failed: %s" % error_string(load_error), true)
	else:
		_set_status("Loaded: %s" % ProjectSettings.globalize_path(path))


func _apply_payload(payload: Dictionary) -> void:
	var incoming: Variant = payload.get("frames", [])
	if not incoming is Array:
		return
	for raw: Variant in incoming as Array:
		if not raw is Dictionary:
			continue
		var raw_frame := raw as Dictionary
		var frame_index := int(raw_frame.get("frame", -1))
		if not _valid_frame(frame_index):
			continue
		var frame := _default_frame(frame_index)
		var character_raw: Variant = raw_frame.get("character", {})
		if character_raw is Dictionary:
			var character := frame["character"] as Dictionary
			character["x"] = float((character_raw as Dictionary).get("x", 0.0))
			character["y"] = float((character_raw as Dictionary).get("y", 0.0))
			frame["character"] = character
		var sword_raw: Variant = raw_frame.get("sword", {})
		if sword_raw is Dictionary:
			var sword := frame["sword"] as Dictionary
			sword["x"] = float((sword_raw as Dictionary).get("x", 0.0))
			sword["y"] = float((sword_raw as Dictionary).get("y", 0.0))
			sword["rotation"] = float((sword_raw as Dictionary).get("rotation", 0.0))
			frame["sword"] = sword
		_frames[frame_index] = frame


func _motion_payload() -> Dictionary:
	return {
		"version": 1,
		"character": "sotiris",
		"skill": "eos_burst",
		"frame_count": _frame_count,
		"frames": _frames.duplicate(true),
	}


func _reset_all_frames_to_defaults() -> void:
	_frames.clear()
	for frame_index in _frame_count:
		_frames.append(_default_frame(frame_index))
	_adjusted_texture_cache.clear()


func _default_frame(frame_index: int) -> Dictionary:
	return {
		"frame": frame_index,
		"character": {"x": 0.0, "y": 0.0},
		"sword": {"x": 0.0, "y": 0.0, "rotation": 0.0},
	}


func _character_data(frame_index: int) -> Dictionary:
	return _frames[frame_index]["character"] as Dictionary


func _sword_data(frame_index: int) -> Dictionary:
	return _frames[frame_index]["sword"] as Dictionary


func _valid_frame(frame_index: int) -> bool:
	return frame_index >= 0 and frame_index < _frames.size() \
		and frame_index < _sword_bases.size() and frame_index < _sword_tips.size()


func _duration_for_frame(frame_index: int) -> float:
	if frame_index >= 0 and frame_index < _frame_durations.size():
		return maxf(0.01, _frame_durations[frame_index])
	return 0.1


func _source_image(frame_index: int, fallback: Texture2D) -> Image:
	if frame_index >= 0 and frame_index < _source_images.size():
		return _source_images[frame_index]
	if fallback == null:
		return null
	var image := fallback.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _invalidate_adjustments() -> void:
	_adjusted_texture_cache.clear()
	adjustments_changed.emit()
	queue_redraw()


func _compose_sword_adjustment(
		source: Image, base: Vector2, tip: Vector2,
		offset: Vector2, rotation_radians: float
) -> Image:
	var output := source.duplicate()
	output.convert(Image.FORMAT_RGBA8)
	var width: int = output.get_width()
	var height: int = output.get_height()
	# Remove only the narrow blade/hilt corridor from the original flattened
	# sprite. The body and planted feet remain untouched.
	for y in height:
		for x in width:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			if _inside_sword_mask(point, base, tip):
				var color: Color = output.get_pixel(x, y)
				if color.a > 0.0:
					output.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
	# Inverse-map every destination pixel into the original sword corridor.
	# This avoids forward-rotation holes and preserves the source pixel art.
	for y in height:
		for x in width:
			var destination := Vector2(float(x) + 0.5, float(y) + 0.5)
			var original := (destination - offset - base).rotated(-rotation_radians) + base
			if not _inside_sword_mask(original, base, tip):
				continue
			var source_x := int(floor(original.x))
			var source_y := int(floor(original.y))
			if source_x < 0 or source_x >= width or source_y < 0 or source_y >= height:
				continue
			var sword_color := source.get_pixel(source_x, source_y)
			if sword_color.a > 0.0:
				output.set_pixel(x, y, sword_color)
	return output


func _inside_sword_mask(point: Vector2, base: Vector2, tip: Vector2) -> bool:
	var segment := tip - base
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(base) <= SWORD_PIVOT_MASK_RADIUS
	var raw_t := (point - base).dot(segment) / length_squared
	if raw_t < -0.18 or raw_t > 1.12:
		return false
	var closest := base + segment * clampf(raw_t, 0.0, 1.0)
	var radius := SWORD_PIVOT_MASK_RADIUS if raw_t < 0.16 else SWORD_MASK_RADIUS
	return point.distance_to(closest) <= radius
