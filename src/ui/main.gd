extends Control
## Resident-strip main view (placeholder art, §13-5). Draws the cross-section,
## routes clicks to dig/build commands, and hosts the archive dialog.

enum Mode { DIG = 0, BUILD_DORM = 1 }

const CELL_PX: int = 16
const HUD_HEIGHT: int = 22
const HUD_FONT_SIZE: int = 12
const MINION_INSET: int = 3

const COLOR_BACKGROUND := Color(0.05, 0.045, 0.07)
const COLOR_HUD_TEXT := Color(0.85, 0.82, 0.75)
const COLOR_AIR := Color(0.10, 0.09, 0.13)
const COLOR_SOIL := Color(0.42, 0.29, 0.17)
const COLOR_ROCK := Color(0.34, 0.34, 0.40)
const COLOR_GRID_LINE := Color(0.0, 0.0, 0.0, 0.25)
const COLOR_JOB_MARK := Color(1.0, 0.85, 0.3, 0.55)
const COLOR_DEPOT := Color(0.85, 0.3, 0.25)
const COLOR_MINION := Color(0.95, 0.85, 0.4)
const COLOR_CARRY := Color(0.6, 0.42, 0.25)
const COLOR_ROOM := Color(0.25, 0.55, 0.55, 0.85)

var sim: UDSim
var settings: UDSettings
var locale: UDLocale
var doc_db: UDDocumentDB
var room_db: UDRoomDB
var mode: Mode = Mode.DIG
var scroll_y: int = 0
var unread_docs: Array[String] = []
var offline_ticks_applied: int = 0

var _archive_button: Button
var _dig_button: Button
var _dorm_button: Button
var _height_button: Button
var _mode_button: Button
var _locale_button: Button
var _quit_button: Button
var _archive_dialog: AcceptDialog
var _archive_list: ItemList
var _archive_body: RichTextLabel
var _archive_doc_ids: Array[String] = []

@onready var tick_timer: Timer = $TickTimer
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	settings = UDSettings.load_settings()
	locale = UDLocale.load_locale(settings.locale_code)
	doc_db = UDDocumentDB.load_from_dir("res://data/documents")
	room_db = UDRoomDB.load_from_dir("res://data/rooms")
	var strata := UDStrataDB.load_from_dir("res://data/strata")

	var payload := UDSaveManager.load_game()
	if payload.is_empty():
		sim = UDSim.new_game(strata, int(Time.get_unix_time_from_system()))
	else:
		sim = UDSim.from_dict(payload["sim"], strata)
	sim.document_discovered.connect(_on_document_discovered)
	if not payload.is_empty():
		offline_ticks_applied = UDOffline.elapsed_ticks(
			int(payload["saved_unix_time"]),
			int(Time.get_unix_time_from_system())
		)
		sim.advance(offline_ticks_applied)

	tick_timer.wait_time = UD.TICK_SECONDS
	tick_timer.timeout.connect(_on_tick)
	tick_timer.start()
	autosave_timer.wait_time = UD.AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.timeout.connect(func() -> void: UDSaveManager.save_game(sim))
	autosave_timer.start()

	_build_hud()
	_build_archive_dialog()
	_refresh_button_texts()
	_apply_window_mode()
	queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if sim != null:
				UDSaveManager.save_game(sim)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			UDResidentWindow.apply_focus_fps(true)
			RenderingServer.render_loop_enabled = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			UDResidentWindow.apply_focus_fps(false)


func _on_tick() -> void:
	sim.tick()
	UDResidentWindow.sync_render_loop(get_window())
	queue_redraw()


func _on_document_discovered(doc_id: String) -> void:
	unread_docs.append(doc_id)
	_refresh_archive_button()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_click(mouse.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(1)
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-1)


func _handle_click(click_pos: Vector2) -> void:
	var cell := _cell_at(click_pos)
	if cell == UDMinion.NO_TARGET:
		return
	match mode:
		Mode.DIG:
			if sim.add_dig_job(cell):
				queue_redraw()
		Mode.BUILD_DORM:
			if sim.build_room(room_db.get_room("dorm"), cell):
				mode = Mode.DIG
				_refresh_mode_buttons()
				queue_redraw()


func _scroll_by(rows: int) -> void:
	var max_scroll: int = maxi(0, sim.grid.height - _visible_rows())
	scroll_y = clampi(scroll_y + rows, 0, max_scroll)
	queue_redraw()


func _visible_rows() -> int:
	return maxi(1, int((size.y - HUD_HEIGHT) / CELL_PX))


func _grid_origin() -> Vector2:
	var grid_px_width := float(sim.grid.width * CELL_PX)
	return Vector2(maxf(0.0, (size.x - grid_px_width) / 2.0), HUD_HEIGHT)


func _cell_at(point: Vector2) -> Vector2i:
	var origin := _grid_origin()
	var local := point - origin
	if local.x < 0.0 or local.y < 0.0:
		return UDMinion.NO_TARGET
	var cell := Vector2i(int(local.x / CELL_PX), int(local.y / CELL_PX) + scroll_y)
	if not sim.grid.is_inside(cell):
		return UDMinion.NO_TARGET
	return cell


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if sim == null:
		return
	_draw_hud()
	_draw_grid()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var parts: Array[String] = [
		locale.text("APP_TITLE"),
		"%s %d" % [locale.text("RES_SOIL"), int(sim.inventory[UD.RES_SOIL])],
		"%s %d" % [locale.text("RES_STONE"), int(sim.inventory[UD.RES_STONE])],
		"⛏ %d" % sim.minions.size(),
		"tick %d" % sim.tick_count,
	]
	if offline_ticks_applied > 0:
		parts.append(locale.text("UI_OFFLINE_REPORT") % offline_ticks_applied)
	draw_string(
		font, Vector2(8, HUD_HEIGHT - 6), "  |  ".join(parts),
		HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD_TEXT
	)


func _draw_grid() -> void:
	var origin := _grid_origin()
	var last_row: int = mini(sim.grid.height, scroll_y + _visible_rows())
	for y in range(scroll_y, last_row):
		for x in sim.grid.width:
			var cell := Vector2i(x, y)
			var rect := Rect2(
				origin + Vector2(x * CELL_PX, (y - scroll_y) * CELL_PX),
				Vector2(CELL_PX, CELL_PX)
			)
			draw_rect(rect, _terrain_color(sim.grid.terrain_at(cell)))
			draw_rect(rect, COLOR_GRID_LINE, false, 1.0)
	_draw_rooms(origin)
	_draw_jobs(origin)
	_draw_depot(origin)
	_draw_minions(origin)


func _terrain_color(terrain: UD.Terrain) -> Color:
	match terrain:
		UD.Terrain.SOIL:
			return COLOR_SOIL
		UD.Terrain.ROCK:
			return COLOR_ROCK
		_:
			return COLOR_AIR


func _cell_rect(origin: Vector2, cell: Vector2i) -> Rect2:
	return Rect2(
		origin + Vector2(cell.x * CELL_PX, (cell.y - scroll_y) * CELL_PX),
		Vector2(CELL_PX, CELL_PX)
	)


func _cell_visible(cell: Vector2i) -> bool:
	return cell.y >= scroll_y and cell.y < scroll_y + _visible_rows()


func _draw_jobs(origin: Vector2) -> void:
	for job in sim.jobs:
		if _cell_visible(job.target):
			draw_rect(_cell_rect(origin, job.target), COLOR_JOB_MARK, false, 2.0)


func _draw_depot(origin: Vector2) -> void:
	if not _cell_visible(UD.DEPOT_POS):
		return
	var rect := _cell_rect(origin, UD.DEPOT_POS)
	var flag_base := rect.position + Vector2(CELL_PX / 2.0, CELL_PX)
	draw_line(flag_base, flag_base + Vector2(0, -CELL_PX * 0.8), COLOR_DEPOT, 2.0)
	draw_rect(
		Rect2(flag_base + Vector2(0, -CELL_PX * 0.8), Vector2(CELL_PX * 0.4, CELL_PX * 0.3)),
		COLOR_DEPOT
	)


func _draw_rooms(origin: Vector2) -> void:
	var font := ThemeDB.fallback_font
	for i in sim.rooms.size():
		var footprint := sim.room_footprint(i, room_db)
		if not _cell_visible(footprint.position):
			continue
		var rect := Rect2(
			_cell_rect(origin, footprint.position).position,
			Vector2(footprint.size * CELL_PX)
		)
		draw_rect(rect, COLOR_ROOM)
		var room_id: String = sim.rooms[i]["id"]
		var label := locale.text(room_db.get_room(room_id)["name_key"]).left(1)
		draw_string(
			font, rect.position + Vector2(4, CELL_PX - 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD_TEXT
		)


func _draw_minions(origin: Vector2) -> void:
	for minion in sim.minions:
		if not _cell_visible(minion.pos):
			continue
		var rect := _cell_rect(origin, minion.pos)
		var body := Rect2(
			rect.position + Vector2(MINION_INSET, MINION_INSET),
			Vector2(CELL_PX - MINION_INSET * 2, CELL_PX - MINION_INSET * 2)
		)
		draw_rect(body, COLOR_MINION)
		if minion.carrying != "":
			draw_rect(
				Rect2(rect.position + Vector2(MINION_INSET, 0), Vector2(6, 4)),
				COLOR_CARRY
			)


func _build_hud() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.position.y = 2
	add_child(bar)

	_dig_button = _make_button("", func() -> void: _set_mode(Mode.DIG))
	bar.add_child(_dig_button)
	_dorm_button = _make_button("", func() -> void: _set_mode(Mode.BUILD_DORM))
	bar.add_child(_dorm_button)
	_archive_button = _make_button("", _open_archive)
	bar.add_child(_archive_button)
	_height_button = _make_button("", _cycle_height)
	bar.add_child(_height_button)
	_mode_button = _make_button("", _toggle_window_mode)
	bar.add_child(_mode_button)
	_locale_button = _make_button("", _toggle_locale)
	bar.add_child(_locale_button)
	_quit_button = _make_button("", _quit)
	bar.add_child(_quit_button)
	_refresh_mode_buttons()


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	button.pressed.connect(callback)
	return button


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_refresh_mode_buttons()


func _refresh_mode_buttons() -> void:
	_dig_button.disabled = mode == Mode.DIG
	_dorm_button.disabled = mode == Mode.BUILD_DORM


func _refresh_archive_button() -> void:
	if _archive_button == null:
		return
	var label := locale.text("UI_ARCHIVE")
	if not unread_docs.is_empty():
		label += " (%d)" % unread_docs.size()
	_archive_button.text = label


func _refresh_button_texts() -> void:
	_dig_button.text = locale.text("UI_DIG")
	_dorm_button.text = locale.text("UI_BUILD_DORM")
	_height_button.text = "%dpx" % UD.WINDOW_HEIGHTS[settings.height_index]
	_mode_button.text = locale.text("UI_MODE_NORMAL") if settings.resident_mode \
		else locale.text("UI_MODE_RESIDENT")
	_locale_button.text = _next_locale_code().to_upper()
	_quit_button.text = locale.text("UI_QUIT")
	_refresh_archive_button()


func _next_locale_code() -> String:
	var index := UD.SUPPORTED_LOCALES.find(settings.locale_code)
	return UD.SUPPORTED_LOCALES[(index + 1) % UD.SUPPORTED_LOCALES.size()]


func _apply_window_mode() -> void:
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
	else:
		UDResidentWindow.setup_normal(get_window())


func _cycle_height() -> void:
	settings.height_index = (settings.height_index + 1) % UD.WINDOW_HEIGHTS.size()
	settings.save()
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
	_refresh_button_texts()


func _toggle_window_mode() -> void:
	settings.resident_mode = not settings.resident_mode
	settings.save()
	_apply_window_mode()
	_refresh_button_texts()


func _toggle_locale() -> void:
	settings.locale_code = _next_locale_code()
	settings.save()
	locale = UDLocale.load_locale(settings.locale_code)
	_archive_dialog.title = locale.text("UI_ARCHIVE")
	_refresh_button_texts()
	queue_redraw()


func _build_archive_dialog() -> void:
	_archive_dialog = AcceptDialog.new()
	_archive_dialog.title = locale.text("UI_ARCHIVE")
	_archive_dialog.min_size = Vector2i(640, 320)
	var split := HSplitContainer.new()
	split.custom_minimum_size = Vector2(600, 260)
	_archive_list = ItemList.new()
	_archive_list.custom_minimum_size = Vector2(200, 0)
	_archive_list.item_selected.connect(_on_archive_item_selected)
	split.add_child(_archive_list)
	_archive_body = RichTextLabel.new()
	_archive_body.bbcode_enabled = true
	_archive_body.fit_content = false
	_archive_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_archive_body)
	_archive_dialog.add_child(split)
	add_child(_archive_dialog)


func _open_archive() -> void:
	_archive_list.clear()
	_archive_doc_ids.clear()
	_archive_body.text = ""
	for doc_id in sim.discovered_documents:
		if not doc_db.has_doc(doc_id):
			continue
		var doc := doc_db.get_doc(doc_id)
		_archive_doc_ids.append(doc_id)
		_archive_list.add_item(locale.text(doc["title_key"]))
	unread_docs.clear()
	_refresh_archive_button()
	_archive_dialog.popup_centered()
	if _archive_list.item_count > 0:
		_archive_list.select(0)
		_on_archive_item_selected(0)


func _on_archive_item_selected(index: int) -> void:
	var doc := doc_db.get_doc(_archive_doc_ids[index])
	_archive_body.text = "[b]%s[/b]\n\n%s" % [
		locale.text(doc["title_key"]),
		locale.text(doc["body_key"]),
	]


func _quit() -> void:
	UDSaveManager.save_game(sim)
	get_tree().quit()
