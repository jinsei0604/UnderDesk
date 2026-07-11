extends Control
## Resident-strip main view (placeholder art, §13-5). Draws the cross-section,
## routes clicks to dig/build commands, and hosts the archive dialog.

enum Mode { DIG = 0, BUILD = 1 }

const CELL_PX: int = 16
const HUD_HEIGHT: int = 22
const HUD_FONT_SIZE: int = 12
const MINION_INSET: int = 3

const COLOR_BACKGROUND := Color(0.05, 0.045, 0.07)
const COLOR_HUD_TEXT := Color(0.85, 0.82, 0.75)
const COLOR_AIR := Color(0.10, 0.09, 0.13)
const COLOR_SOIL := Color(0.42, 0.29, 0.17)
const COLOR_ROCK := Color(0.34, 0.34, 0.40)
const COLOR_WETROCK := Color(0.22, 0.32, 0.45)
const COLOR_RUINSTONE := Color(0.52, 0.47, 0.36)
const COLOR_GRID_LINE := Color(0.0, 0.0, 0.0, 0.25)
const COLOR_JOB_MARK := Color(1.0, 0.85, 0.3, 0.55)
const COLOR_DEPOT := Color(0.85, 0.3, 0.25)
const COLOR_MINION := Color(0.95, 0.85, 0.4)
## Slight per-minion tint variation: a crowd, not clones (§6).
const MINION_COLORS: Array[Color] = [
	Color(0.95, 0.85, 0.40),
	Color(0.95, 0.65, 0.35),
	Color(0.70, 0.90, 0.45),
	Color(0.95, 0.60, 0.60),
	Color(0.60, 0.85, 0.90),
	Color(0.85, 0.70, 0.95),
]
## Deeper rows fade toward darkness (§6: lighting carries the mood).
const DEPTH_FADE_PER_ROW: float = 0.015
const DEPTH_FADE_FLOOR: float = 0.4
const COLOR_CARRY := Color(0.6, 0.42, 0.25)
const COLOR_ROOM := Color(0.25, 0.55, 0.55, 0.85)

var sim: UDSim
var settings: UDSettings
var locale: UDLocale
var doc_db: UDDocumentDB
var room_db: UDRoomDB
var item_db: UDItemDB
var shop_db: UDShopDB
var prestige_db: UDShopDB
var strata_db: UDStrataDB
var art: UDArtLibrary
var anomalies: Array = []
var _anomaly_by_id: Dictionary = {}
var companion_defs: Array = []
var _companion_by_id: Dictionary = {}
var mode: Mode = Mode.DIG
var _build_room_id: String = ""
var scroll_y: int = 0
var scroll_x: int = 0
var _anim_frame: int = 0
var _tally_text: String = ""
var _tally_until_tick: int = 0

const TALLY_SHOW_TICKS: int = 5

## Expanded-mode control panel: big, thumb-friendly buttons on the
## right; the dig view does not need the full width.
const PANEL_WIDTH: int = 260
const BUTTON_FONT_SIZE: int = 16
const BUTTON_MIN_SIZE := Vector2(118, 44)
const ACTIVE_BUTTON_TINT := Color(1.0, 0.85, 0.3)

## Expanded view zoom: near-native sprite resolution, tunnel close-up
## framing (about 7x5 cells in view).
const EXPANDED_CELL_PX: int = 128
## UI-side sprite animation cadence (does not touch the simulation).
const ANIM_FRAME_SECONDS: float = 0.4
var unread_docs: Array[String] = []
var offline_ticks_applied: int = 0

var _button_bar: Control
var _archive_button: Button
var _dig_button: Button
var _room_buttons: Dictionary = {}  # room id -> Button
var _policy_button: Button
var _height_button: Button
var _collapse_button: Button
var _locale_button: Button
var _quit_button: Button
var _archive_dialog: AcceptDialog
var _archive_list: ItemList
var _archive_body: RichTextLabel
var _archive_doc_ids: Array[String] = []
var _treasure_button: Button
var _treasure_dialog: AcceptDialog
var _treasure_list: ItemList
var _shop_button: Button
var _shop_dialog: AcceptDialog
var _shop_list: ItemList
var _shop_buy_button: Button
var _shop_good_ids: Array[String] = []
var _prestige_button: Button
var _prestige_dialog: AcceptDialog
var _prestige_info: Label
var _prestige_list: ItemList
var _perma_buy_button: Button
var _bury_button: Button
var _bury_confirm: ConfirmationDialog
var _prestige_good_ids: Array[String] = []
var _card_button: Button
var _card_dialog: AcceptDialog

@onready var tick_timer: Timer = $TickTimer
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	settings = UDSettings.load_settings()
	locale = UDLocale.load_locale(settings.locale_code)
	doc_db = UDDocumentDB.load_from_dir("res://data/documents")
	room_db = UDRoomDB.load_from_dir("res://data/rooms")
	item_db = UDItemDB.load_from_dir("res://data/items")
	shop_db = UDShopDB.load_from_dir("res://data/shop")
	prestige_db = UDShopDB.load_from_dir("res://data/prestige")
	art = UDArtLibrary.load_default(room_db.all_ids())
	anomalies = UDDataLoader.load_json_dir("res://data/anomalies")
	for anomaly: Variant in anomalies:
		_anomaly_by_id[(anomaly as Dictionary)["id"]] = anomaly
	companion_defs = UDDataLoader.load_json_dir("res://data/companions")
	for companion: Variant in companion_defs:
		_companion_by_id[(companion as Dictionary)["id"]] = companion
	strata_db = UDStrataDB.load_from_dir("res://data/strata")

	var payload := UDSaveManager.load_game()
	if payload.is_empty():
		sim = UDSim.new_game(
			strata_db, int(Time.get_unix_time_from_system()),
			item_db.all_ids(), companion_defs
		)
	else:
		sim = UDSim.from_dict(
			payload["sim"], strata_db, item_db.all_ids(), companion_defs
		)
	_connect_sim_signals()
	if not payload.is_empty():
		offline_ticks_applied = UDOffline.elapsed_ticks(
			int(payload["saved_unix_time"]),
			int(Time.get_unix_time_from_system())
		)
		sim.advance(offline_ticks_applied)
	_sync_daily()

	tick_timer.wait_time = UD.TICK_SECONDS
	tick_timer.timeout.connect(_on_tick)
	tick_timer.start()
	var anim_timer := Timer.new()
	anim_timer.wait_time = ANIM_FRAME_SECONDS
	anim_timer.autostart = true
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	autosave_timer.wait_time = UD.AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.timeout.connect(func() -> void: UDSaveManager.save_game(sim))
	autosave_timer.start()

	_build_hud()
	_build_archive_dialog()
	_build_treasure_dialog()
	_build_shop_dialog()
	_build_prestige_dialog()
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


## Rolls the shared daily anomaly when the calendar day changes (§5.4).
func _sync_daily() -> void:
	var key := UDDaily.date_key(Time.get_date_dict_from_system())
	if sim.daily_date_key == key:
		return
	var anomaly := UDDaily.anomaly_for_date_key(anomalies, key)
	if not anomaly.is_empty():
		sim.apply_daily(key, anomaly)


## Advances UI-side sprite animation only; the simulation is untouched.
func _on_anim_tick() -> void:
	_anim_frame += 1
	queue_redraw()


func _on_tick() -> void:
	_sync_daily()
	sim.tick()
	if not settings.resident_mode:
		# While the big window is open, loot converts as it is dug.
		sim.collect_loot()
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.items.size()]
	UDResidentWindow.sync_render_loop(get_window())
	_follow_camera()
	queue_redraw()


## The camera anchors on the protagonist (minion 0): wherever they walk
## or dig, the view follows.
func _followed_minion() -> UDMinion:
	if sim.minions.is_empty():
		return null
	return sim.minions[0]


func _follow_camera() -> void:
	var star := _followed_minion()
	if star == null:
		return
	var max_scroll: int = maxi(0, sim.grid.height - _visible_rows())
	scroll_y = clampi(star.pos.y - _visible_rows() / 2, 0, max_scroll)
	if not settings.resident_mode:
		var max_scroll_x: int = maxi(0, sim.grid.width - _visible_cols())
		scroll_x = clampi(star.pos.x - _visible_cols() / 2, 0, max_scroll_x)


func _connect_sim_signals() -> void:
	sim.document_discovered.connect(_on_document_discovered)
	sim.companion_joined.connect(_on_companion_joined)


func _on_document_discovered(doc_id: String) -> void:
	unread_docs.append(doc_id)
	_refresh_archive_button()


func _on_companion_joined(companion_id: String) -> void:
	var name := companion_id
	if _companion_by_id.has(companion_id):
		name = locale.text(_companion_by_id[companion_id]["name_key"])
	_tally_text = locale.text("UI_COMPANION_JOINED") % name
	_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if settings.resident_mode:
		# The strip is ambient: any click opens the management window.
		if event is InputEventMouseButton and event.pressed:
			_expand()
		return
	if event is InputEventMouseButton and event.pressed:
		var mouse := event as InputEventMouseButton
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_click(mouse.position)
			MOUSE_BUTTON_RIGHT:
				_cancel_designation(mouse.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mouse.shift_pressed:
					_scroll_x_by(2)
				else:
					_scroll_by(1)
			MOUSE_BUTTON_WHEEL_UP:
				if mouse.shift_pressed:
					_scroll_x_by(-2)
				else:
					_scroll_by(-1)
	elif event is InputEventMouseMotion and mode == Mode.DIG:
		# Drag-paint dig designations instead of clicking cells one by one.
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_handle_click(motion.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE \
			and not settings.resident_mode:
		_collapse()


func _handle_click(click_pos: Vector2) -> void:
	var cell := _cell_at(click_pos)
	if cell == UDMinion.NO_TARGET:
		return
	match mode:
		Mode.DIG:
			if sim.add_dig_job(cell):
				queue_redraw()
		Mode.BUILD:
			if sim.build_room(room_db.get_room(_build_room_id), cell):
				mode = Mode.DIG
				_refresh_mode_buttons()
				queue_redraw()


func _cancel_designation(click_pos: Vector2) -> void:
	var cell := _cell_at(click_pos)
	if cell != UDMinion.NO_TARGET and sim.remove_dig_job(cell):
		queue_redraw()


func _scroll_by(rows: int) -> void:
	var max_scroll: int = maxi(0, sim.grid.height - _visible_rows())
	scroll_y = clampi(scroll_y + rows, 0, max_scroll)
	queue_redraw()


func _visible_cols() -> int:
	return maxi(1, int((size.x - PANEL_WIDTH) / _cell_px()))


func _scroll_x_by(cols: int) -> void:
	var max_scroll: int = maxi(0, sim.grid.width - _visible_cols())
	scroll_x = clampi(scroll_x + cols, 0, max_scroll)
	queue_redraw()


## The strip has no HUD bar: cells use the full height.
func _hud_offset() -> int:
	return 0 if settings.resident_mode else HUD_HEIGHT


## Strip mode zooms in Taskbar-Heroes style: one big row where the
## minions' motion is actually watchable. Expanded runs at 2x zoom.
func _cell_px() -> int:
	if settings.resident_mode:
		return clampi(int(size.y), CELL_PX, 64)
	return EXPANDED_CELL_PX


func _visible_rows() -> int:
	return maxi(1, int((size.y - _hud_offset()) / _cell_px()))


func _grid_origin() -> Vector2:
	var cell_px := _cell_px()
	var grid_px_width := float(sim.grid.width * cell_px)
	if settings.resident_mode:
		# The mini strip is narrower than the grid: center the followed worker.
		var star := _followed_minion()
		var star_x := float(star.pos.x) if star != null else float(UD.DEPOT_POS.x)
		var desired := size.x / 2.0 - (star_x + 0.5) * cell_px
		return Vector2(clampf(desired, minf(size.x - grid_px_width, 0.0), 0.0), 0.0)
	# Expanded: the dig view keeps clear of the right-hand button panel
	# and pans horizontally (zoomed cells no longer fit the width).
	var view_width := size.x - PANEL_WIDTH
	if grid_px_width <= view_width:
		return Vector2((view_width - grid_px_width) / 2.0, _hud_offset())
	return Vector2(-float(scroll_x * cell_px), _hud_offset())


func _cell_at(point: Vector2) -> Vector2i:
	var origin := _grid_origin()
	var local := point - origin
	if local.x < 0.0 or local.y < 0.0:
		return UDMinion.NO_TARGET
	var cell_px := _cell_px()
	var cell := Vector2i(int(local.x / cell_px), int(local.y / cell_px) + scroll_y)
	if not sim.grid.is_inside(cell):
		return UDMinion.NO_TARGET
	return cell


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if sim == null:
		return
	_draw_hud()
	_draw_grid()


const STRIP_FONT_SIZE: int = 11
const STRIP_BADGE := Color(1.0, 0.85, 0.3)
const STRIP_TEXT_BG := Color(0.0, 0.0, 0.0, 0.45)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	if settings.resident_mode:
		_draw_strip_overlay(font)
		return
	var parts: Array[String] = [
		locale.text("APP_TITLE"),
		"%s %d" % [locale.text("RES_GOLD"), int(sim.inventory[UD.RES_GOLD])],
		"%s %d/%d" % [locale.text("UI_TREASURES"), sim.items.size(), item_db.all_ids().size()],
		"⛏ %d" % sim.minions.size(),
		"▼ %d" % sim.deepest_air_row(),
		"tick %d" % sim.tick_count,
	]
	if sim.crystals > 0 or sim.resets > 0:
		parts.insert(2, "%s %d" % [locale.text("UI_CRYSTALS"), sim.crystals])
	if sim.daily_anomaly_id != "" and _anomaly_by_id.has(sim.daily_anomaly_id):
		var anomaly: Dictionary = _anomaly_by_id[sim.daily_anomaly_id]
		parts.append("%s: %s" % [
			locale.text("UI_DAILY"), locale.text(anomaly["name_key"]),
		])
	if offline_ticks_applied > 0:
		parts.append(locale.text("UI_OFFLINE_REPORT") % offline_ticks_applied)
	draw_string(
		font, Vector2(8, HUD_HEIGHT - 6), "  |  ".join(parts),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, HUD_FONT_SIZE, COLOR_HUD_TEXT
	)
	if _tally_text != "" and sim.tick_count <= _tally_until_tick:
		draw_string(
			font, Vector2(8, HUD_HEIGHT + 20), _tally_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, STRIP_BADGE
		)


## Translucent readout drawn over the cells; the strip has no HUD bar.
## Unread documents blink at the right edge (§5.1: icon blink only).
func _draw_strip_overlay(font: Font) -> void:
	var coin_part := "$%d" % int(sim.inventory[UD.RES_GOLD])
	var pending := sim.pending_loot_total()
	if pending > 0:
		coin_part += "(+%d)" % pending
	var text := "%s ▼%d ⛏%d" % [coin_part, sim.deepest_air_row(), sim.minions.size()]
	var text_width := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE
	).x
	draw_rect(Rect2(Vector2.ZERO, Vector2(text_width + 12, 16)), STRIP_TEXT_BG)
	draw_string(
		font, Vector2(6, 12), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE, COLOR_HUD_TEXT
	)
	if not unread_docs.is_empty() and sim.tick_count % 2 == 0:
		draw_rect(Rect2(Vector2(size.x - 20, 4), Vector2(12, 12)), STRIP_BADGE)


func _draw_grid() -> void:
	var origin := _grid_origin()
	var last_row: int = mini(sim.grid.height, scroll_y + _visible_rows())
	for y in range(scroll_y, last_row):
		for x in sim.grid.width:
			var cell := Vector2i(x, y)
			var rect := _cell_rect(origin, cell)
			var terrain := sim.grid.terrain_at(cell)
			var art_key := art.terrain_key(terrain)
			if art.has_art(art_key):
				var fade := maxf(DEPTH_FADE_FLOOR, 1.0 - y * DEPTH_FADE_PER_ROW)
				draw_texture_rect(
					art.texture(art_key), rect, false, Color(fade, fade, fade)
				)
			else:
				draw_rect(rect, _cell_color(terrain, y))
				draw_rect(rect, COLOR_GRID_LINE, false, 1.0)
	_draw_rooms(origin)
	_draw_jobs(origin)
	_draw_depot(origin)
	_draw_minions(origin)


func _cell_color(terrain: UD.Terrain, depth: int) -> Color:
	var base: Color
	match terrain:
		UD.Terrain.SOIL:
			base = COLOR_SOIL
		UD.Terrain.ROCK:
			base = COLOR_ROCK
		UD.Terrain.WETROCK:
			base = COLOR_WETROCK
		UD.Terrain.RUINSTONE:
			base = COLOR_RUINSTONE
		_:
			base = COLOR_AIR
	var fade: float = maxf(DEPTH_FADE_FLOOR, 1.0 - depth * DEPTH_FADE_PER_ROW)
	return base.darkened(1.0 - fade)


func _cell_rect(origin: Vector2, cell: Vector2i) -> Rect2:
	var cell_px := _cell_px()
	return Rect2(
		origin + Vector2(cell.x * cell_px, (cell.y - scroll_y) * cell_px),
		Vector2(cell_px, cell_px)
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
	var cell_px := float(_cell_px())
	var rect := _cell_rect(origin, UD.DEPOT_POS)
	if art.has_art("depot"):
		draw_texture_rect(art.texture("depot"), rect, false)
		return
	var flag_base := rect.position + Vector2(cell_px / 2.0, cell_px)
	draw_line(flag_base, flag_base + Vector2(0, -cell_px * 0.8), COLOR_DEPOT, 2.0)
	draw_rect(
		Rect2(flag_base + Vector2(0, -cell_px * 0.8), Vector2(cell_px * 0.4, cell_px * 0.3)),
		COLOR_DEPOT
	)


func _draw_rooms(origin: Vector2) -> void:
	var font := ThemeDB.fallback_font
	for i in sim.rooms.size():
		var footprint := sim.room_footprint(i, room_db)
		if not _cell_visible(footprint.position):
			continue
		var cell_px := _cell_px()
		var rect := Rect2(
			_cell_rect(origin, footprint.position).position,
			Vector2(footprint.size * cell_px)
		)
		var room_id: String = sim.rooms[i]["id"]
		var art_key := "room_%s" % room_id
		if art.has_art(art_key):
			draw_texture_rect(art.texture(art_key), rect, false)
			continue
		draw_rect(rect, COLOR_ROOM)
		var label := locale.text(room_db.get_room(room_id)["name_key"]).left(1)
		draw_string(
			font, rect.position + Vector2(4, cell_px - 4), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, HUD_FONT_SIZE, COLOR_HUD_TEXT
		)


func _draw_minions(origin: Vector2) -> void:
	var cell_px := _cell_px()
	var inset := maxi(MINION_INSET, cell_px / 6)
	for minion in sim.minions:
		if not _cell_visible(minion.pos):
			continue
		var rect := _cell_rect(origin, minion.pos)
		# Work bob, phase-shifted per minion and scaled with zoom.
		var bob := 0.0
		if minion.state != UDMinion.State.IDLE:
			bob = float(((sim.tick_count + minion.id) % 2) * maxi(1, cell_px / 12))
		var art_key := art.minion_key(minion.id)
		if art.has_art(art_key):
			# Illustrated sprites carry their own margins: use the full cell.
			var sprite_rect := Rect2(
				rect.position + Vector2(0, bob), Vector2(cell_px, cell_px - bob)
			)
			var tex: Texture2D
			if minion.state == UDMinion.State.IDLE or art.frame_count(art_key) <= 1:
				tex = art.texture(art_key)
			else:
				tex = art.frame(art_key, _anim_frame + minion.id)
			draw_texture_rect(tex, sprite_rect, false)
			continue
		var body := Rect2(
			rect.position + Vector2(inset, inset + bob),
			Vector2(cell_px - inset * 2, cell_px - inset * 2 - bob)
		)
		draw_rect(body, MINION_COLORS[minion.id % MINION_COLORS.size()])
		# Two dark eyes: placeholder charm until real sprites land (§6).
		var eye := maxf(1.0, cell_px / 12.0)
		var eye_y := body.position.y + body.size.y * 0.3
		draw_rect(Rect2(Vector2(body.position.x + body.size.x * 0.25, eye_y),
			Vector2(eye, eye)), COLOR_BACKGROUND)
		draw_rect(Rect2(Vector2(body.position.x + body.size.x * 0.65, eye_y),
			Vector2(eye, eye)), COLOR_BACKGROUND)


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	panel.offset_right = -4
	panel.offset_top = HUD_HEIGHT + 4
	panel.offset_bottom = -4
	add_child(panel)
	_button_bar = panel

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)

	_dig_button = _make_button("", func() -> void: _set_mode(Mode.DIG))
	grid.add_child(_dig_button)
	_policy_button = _make_button("", _cycle_dig_policy)
	grid.add_child(_policy_button)
	for room_id in room_db.all_ids():
		var button := _make_button("", _select_build_room.bind(room_id))
		_room_buttons[room_id] = button
		grid.add_child(button)
	_archive_button = _make_button("", _open_archive)
	grid.add_child(_archive_button)
	_treasure_button = _make_button("", _open_treasures)
	grid.add_child(_treasure_button)
	_shop_button = _make_button("", _open_shop)
	grid.add_child(_shop_button)
	_prestige_button = _make_button("", _open_prestige)
	grid.add_child(_prestige_button)
	_card_button = _make_button("", _generate_survey_card)
	grid.add_child(_card_button)
	_height_button = _make_button("", _cycle_height)
	grid.add_child(_height_button)
	_locale_button = _make_button("", _toggle_locale)
	grid.add_child(_locale_button)
	_collapse_button = _make_button("", _collapse)
	grid.add_child(_collapse_button)
	_quit_button = _make_button("", _quit)
	grid.add_child(_quit_button)
	_refresh_mode_buttons()


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.pressed.connect(callback)
	return button


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_refresh_mode_buttons()


func _select_build_room(room_id: String) -> void:
	_build_room_id = room_id
	_set_mode(Mode.BUILD)


func _refresh_mode_buttons() -> void:
	# The active mode button is tinted gold so the selection is obvious.
	var dig_active := mode == Mode.DIG
	_dig_button.disabled = dig_active
	_dig_button.modulate = ACTIVE_BUTTON_TINT if dig_active else Color.WHITE
	for room_id: String in _room_buttons:
		var button: Button = _room_buttons[room_id]
		var active := mode == Mode.BUILD and _build_room_id == room_id
		button.disabled = active
		button.modulate = ACTIVE_BUTTON_TINT if active else Color.WHITE


func _refresh_archive_button() -> void:
	if _archive_button == null:
		return
	var label := locale.text("UI_ARCHIVE")
	if not unread_docs.is_empty():
		label += " (%d)" % unread_docs.size()
	_archive_button.text = label


func _refresh_button_texts() -> void:
	_dig_button.text = locale.text("UI_DIG")
	for room_id: String in _room_buttons:
		var button: Button = _room_buttons[room_id]
		button.text = locale.text(room_db.get_room(room_id)["name_key"])
	_policy_button.text = locale.text(_policy_label_key())
	_height_button.text = "%dpx" % UD.WINDOW_HEIGHTS[settings.height_index]
	_collapse_button.text = locale.text("UI_COLLAPSE")
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.items.size()]
	_shop_button.text = locale.text("UI_SHOP")
	_shop_buy_button.text = locale.text("UI_BUY")
	_prestige_button.text = locale.text("UI_PRESTIGE")
	_perma_buy_button.text = locale.text("UI_BUY")
	_bury_button.text = locale.text("UI_PRESTIGE_DO")
	_card_button.text = locale.text("UI_CARD")
	_locale_button.text = _next_locale_code().to_upper()
	_quit_button.text = locale.text("UI_QUIT")
	_refresh_archive_button()


## The button is a plain on/off toggle; WIDEN stays core-only.
func _cycle_dig_policy() -> void:
	if sim.dig_policy == UD.DigPolicy.NONE:
		sim.dig_policy = UD.DigPolicy.DOWN
	else:
		sim.dig_policy = UD.DigPolicy.NONE
	_refresh_button_texts()
	queue_redraw()


func _policy_label_key() -> String:
	if sim.dig_policy == UD.DigPolicy.NONE:
		return "UI_AUTO_NONE"
	return "UI_AUTO_DOWN"


func _next_locale_code() -> String:
	var index := UD.SUPPORTED_LOCALES.find(settings.locale_code)
	return UD.SUPPORTED_LOCALES[(index + 1) % UD.SUPPORTED_LOCALES.size()]


## Strip = taskbar-look ambient view. Expanded = centered window for
## reading documents and giving orders. Clicking the strip expands.
func _apply_window_mode() -> void:
	_button_bar.visible = not settings.resident_mode
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
		_follow_camera()
	else:
		UDResidentWindow.setup_expanded(get_window())
	queue_redraw()


func _expand() -> void:
	# Checking in harvests everything the crew bagged while you were away.
	var tally := sim.collect_loot()
	if int(tally["coins"]) > 0:
		_tally_text = _format_tally(tally)
		_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS
	settings.resident_mode = false
	settings.save()
	_apply_window_mode()
	_follow_camera()
	_refresh_button_texts()


func _format_tally(tally: Dictionary) -> String:
	var text := locale.text("UI_COLLECTED") % int(tally["coins"])
	var breakdown: Array[String] = []
	var counts: Dictionary = tally["counts"]
	for res: Variant in counts.keys():
		breakdown.append("%s×%d" % [
			locale.text("RES_" + str(res).to_upper()), int(counts[res]),
		])
	if not breakdown.is_empty():
		text += "（%s）" % "  ".join(breakdown)
	return text


func _collapse() -> void:
	settings.resident_mode = true
	settings.save()
	_apply_window_mode()


func _cycle_height() -> void:
	settings.height_index = (settings.height_index + 1) % UD.WINDOW_HEIGHTS.size()
	settings.save()
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
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
	_archive_dialog.min_size = Vector2i(860, 500)
	var split := HSplitContainer.new()
	split.custom_minimum_size = Vector2(820, 440)
	_archive_list = ItemList.new()
	_archive_list.custom_minimum_size = Vector2(240, 0)
	_archive_list.add_theme_font_size_override("font_size", 15)
	_archive_list.item_selected.connect(_on_archive_item_selected)
	split.add_child(_archive_list)
	_archive_body = RichTextLabel.new()
	_archive_body.bbcode_enabled = true
	_archive_body.fit_content = false
	_archive_body.add_theme_font_size_override("normal_font_size", 17)
	_archive_body.add_theme_font_size_override("bold_font_size", 19)
	_archive_body.add_theme_constant_override("line_separation", 6)
	_archive_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_archive_body)
	_archive_dialog.add_child(split)
	add_child(_archive_dialog)


func _build_treasure_dialog() -> void:
	_treasure_dialog = AcceptDialog.new()
	_treasure_dialog.title = locale.text("UI_TREASURES")
	_treasure_dialog.min_size = Vector2i(560, 360)
	_treasure_list = ItemList.new()
	_treasure_list.custom_minimum_size = Vector2(520, 300)
	_treasure_list.add_theme_font_size_override("font_size", 15)
	_treasure_dialog.add_child(_treasure_list)
	add_child(_treasure_dialog)


func _open_treasures() -> void:
	if settings.resident_mode:
		_expand()
	_treasure_list.clear()
	for item_id in sim.items:
		if not item_db.has_item(item_id):
			continue
		var item := item_db.get_item(item_id)
		_treasure_list.add_item("%s — %s" % [
			locale.text(item["name_key"]), locale.text(item["desc_key"]),
		])
	if sim.items.is_empty():
		_treasure_list.add_item("---")
	_treasure_dialog.title = locale.text("UI_TREASURES")
	_treasure_dialog.popup_centered()


func _build_shop_dialog() -> void:
	_shop_dialog = AcceptDialog.new()
	_shop_dialog.title = locale.text("UI_SHOP")
	_shop_dialog.min_size = Vector2i(640, 400)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 330)
	_shop_list = ItemList.new()
	_shop_list.custom_minimum_size = Vector2(0, 280)
	_shop_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_font_size_override("font_size", 15)
	box.add_child(_shop_list)
	_shop_buy_button = Button.new()
	_shop_buy_button.pressed.connect(_on_shop_buy)
	box.add_child(_shop_buy_button)
	_shop_dialog.add_child(box)
	add_child(_shop_dialog)


func _open_shop() -> void:
	if settings.resident_mode:
		_expand()
	_populate_shop()
	_shop_dialog.title = locale.text("UI_SHOP")
	_shop_dialog.popup_centered()


func _populate_shop() -> void:
	var selected := _shop_list.get_selected_items()
	_shop_list.clear()
	_shop_good_ids.clear()
	for good_id in shop_db.all_ids():
		var good := shop_db.get_good(good_id)
		var level := sim.upgrade_level(good_id)
		var max_level := int(good["max_level"])
		var line := "%s Lv.%d/%d — %s" % [
			locale.text(good["name_key"]), level, max_level,
			locale.text(good["desc_key"]),
		]
		if level >= max_level:
			line += "  [MAX]"
		else:
			line += "  [$%d]" % UDSim.upgrade_cost(good, level)
		_shop_good_ids.append(good_id)
		_shop_list.add_item(line)
	if not selected.is_empty() and selected[0] < _shop_list.item_count:
		_shop_list.select(selected[0])


func _on_shop_buy() -> void:
	var selected := _shop_list.get_selected_items()
	if selected.is_empty():
		return
	var good := shop_db.get_good(_shop_good_ids[selected[0]])
	if sim.buy_upgrade(good):
		_populate_shop()
		queue_redraw()


func _build_prestige_dialog() -> void:
	_prestige_dialog = AcceptDialog.new()
	_prestige_dialog.min_size = Vector2i(640, 440)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 370)
	_prestige_info = Label.new()
	box.add_child(_prestige_info)
	_prestige_list = ItemList.new()
	_prestige_list.custom_minimum_size = Vector2(0, 240)
	_prestige_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prestige_list.add_theme_font_size_override("font_size", 15)
	box.add_child(_prestige_list)
	var row := HBoxContainer.new()
	_perma_buy_button = Button.new()
	_perma_buy_button.pressed.connect(_on_perma_buy)
	row.add_child(_perma_buy_button)
	_bury_button = Button.new()
	_bury_button.pressed.connect(func() -> void: _bury_confirm.popup_centered())
	row.add_child(_bury_button)
	box.add_child(row)
	_prestige_dialog.add_child(box)
	add_child(_prestige_dialog)
	_bury_confirm = ConfirmationDialog.new()
	_bury_confirm.confirmed.connect(_on_bury_confirmed)
	add_child(_bury_confirm)


func _open_prestige() -> void:
	if settings.resident_mode:
		_expand()
	_populate_prestige()
	_prestige_dialog.popup_centered()


func _populate_prestige() -> void:
	_prestige_dialog.title = locale.text("UI_PRESTIGE")
	_prestige_info.text = locale.text("UI_PRESTIGE_INFO") % [
		sim.deepest_air_row(), sim.prestige_gain(), sim.crystals,
	]
	_bury_confirm.dialog_text = locale.text("UI_PRESTIGE_CONFIRM")
	_bury_button.disabled = not sim.can_prestige()
	var selected := _prestige_list.get_selected_items()
	_prestige_list.clear()
	_prestige_good_ids.clear()
	for good_id in prestige_db.all_ids():
		var good := prestige_db.get_good(good_id)
		var level := sim.perma_level(good_id)
		var max_level := int(good["max_level"])
		var line := "%s Lv.%d/%d — %s" % [
			locale.text(good["name_key"]), level, max_level,
			locale.text(good["desc_key"]),
		]
		if level >= max_level:
			line += "  [MAX]"
		else:
			line += "  [%s %d]" % [locale.text("UI_CRYSTALS"), UDSim.upgrade_cost(good, level)]
		_prestige_good_ids.append(good_id)
		_prestige_list.add_item(line)
	if not selected.is_empty() and selected[0] < _prestige_list.item_count:
		_prestige_list.select(selected[0])


func _on_perma_buy() -> void:
	var selected := _prestige_list.get_selected_items()
	if selected.is_empty():
		return
	var good := prestige_db.get_good(_prestige_good_ids[selected[0]])
	if sim.buy_perma(good):
		_populate_prestige()
		queue_redraw()


func _on_bury_confirmed() -> void:
	if not sim.can_prestige():
		return
	sim = UDSim.prestige_reset(sim, strata_db, item_db.all_ids())
	_connect_sim_signals()
	scroll_y = 0
	scroll_x = 0
	_tally_text = ""
	unread_docs.clear()
	UDSaveManager.save_game(sim)
	_populate_prestige()
	_refresh_button_texts()
	queue_redraw()


## Renders today's survey card offscreen and saves it as a PNG (§5.4).
func _generate_survey_card() -> void:
	if settings.resident_mode:
		_expand()
	var anomaly_name := "-"
	if sim.daily_anomaly_id != "" and _anomaly_by_id.has(sim.daily_anomaly_id):
		var anomaly: Dictionary = _anomaly_by_id[sim.daily_anomaly_id]
		anomaly_name = locale.text(anomaly["name_key"])
	var data := {
		"date_key": sim.daily_date_key,
		"anomaly_name": anomaly_name,
		"depth": sim.deepest_air_row(),
		"coins": int(sim.inventory[UD.RES_GOLD]),
		"minions": sim.minions.size(),
		"docs": sim.discovered_documents.size(),
		"docs_total": doc_db.count(),
	}
	var viewport := SubViewport.new()
	viewport.size = UDSurveyCard.CARD_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.add_child(UDSurveyCard.build_card(data, locale))
	add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	DirAccess.make_dir_recursive_absolute(UDSurveyCard.CARDS_DIR)
	var path := UDSurveyCard.save_path_for(sim.daily_date_key)
	image.save_png(path)
	if _card_dialog == null:
		_card_dialog = AcceptDialog.new()
		_card_dialog.add_button(locale.text("UI_OPEN_FOLDER"), false, "open_folder")
		_card_dialog.custom_action.connect(
			func(_action: StringName) -> void:
				OS.shell_open(ProjectSettings.globalize_path(UDSurveyCard.CARDS_DIR))
		)
		add_child(_card_dialog)
	_card_dialog.title = locale.text("UI_CARD")
	_card_dialog.dialog_text = "%s\n%s" % [
		locale.text("UI_CARD_SAVED"), ProjectSettings.globalize_path(path),
	]
	_card_dialog.popup_centered()


func _open_archive() -> void:
	if settings.resident_mode:
		# Documents are unreadable in a 48px strip: expand first.
		_expand()
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
