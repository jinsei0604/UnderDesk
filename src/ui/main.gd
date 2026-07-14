extends Control
## Resident-strip main view (placeholder art, §13-5). Draws the cross-section,
## routes clicks to dig commands, and hosts the archive dialog.

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

var sim: UDSim
var settings: UDSettings
var locale: UDLocale
var doc_db: UDDocumentDB
var facility_db: UDShopDB
var item_db: UDItemDB
var shop_db: UDShopDB
var strata_db: UDStrataDB
var art: UDArtLibrary
var achievements: UDAchievements
var anomalies: Array = []
var _anomaly_by_id: Dictionary = {}
## Document series defs (data/series/): filename order is display order.
var doc_series: Array = []
## "" = the series-selection shelf; otherwise the open series id.
var _archive_series: String = ""
## "" = the rank-selection shelf; otherwise the open rank (Z/S/A/B/C/D).
var _treasure_rank: String = ""
var companion_defs: Array = []
var _companion_by_id: Dictionary = {}
var _anim_frame: int = 0
## Per-minion dig-swing phase (UI-only, not simulation state): every
## swing starts at the wind-up frame instead of wherever the global
## animation counter happens to be, or a new dig could open mid-strike.
var _prev_minion_state: Dictionary = {}  # minion id -> UDMinion.State
var _dig_anim_start: Dictionary = {}  # minion id -> _anim_frame at swing start
var _facing: Dictionary = {}  # minion id -> -1 (left) / 1 (right)

## Which way each character's source art faces (mirrored for the other
## direction at draw time). Default is right (1).
const MINION_NATIVE_FACING: Dictionary = {0: 1, 2: -1}

## Normalized offsets for terrain-colored dig chips at the target cell.
const DEBRIS_OFFSETS: Array[Vector2] = [
	Vector2(0.15, 0.30), Vector2(0.55, 0.12), Vector2(0.75, 0.45),
	Vector2(0.35, 0.60), Vector2(0.62, 0.78), Vector2(0.10, 0.72),
]
var _tally_text: String = ""
var _tally_until_tick: int = 0

const TALLY_SHOW_TICKS: int = 5

## Expanded-mode control panel: big, thumb-friendly buttons on the
## right; the dig view does not need the full width.
const PANEL_WIDTH: int = 260
const BUTTON_FONT_SIZE: int = 16
const BUTTON_MIN_SIZE := Vector2(118, 44)

## Expanded view zoom: near-native sprite resolution, tunnel close-up
## framing (about 7x5 cells in view).
const EXPANDED_CELL_PX: int = 128
## UI-side sprite animation cadence (does not touch the simulation).
const ANIM_FRAME_SECONDS: float = 0.4
var unread_docs: Array[String] = []
var offline_ticks_applied: int = 0

var _button_bar: Control
var _archive_button: Button
var _facility_buttons: Dictionary = {}  # facility id -> Button
var _policy_button: Button
var _height_button: Button
var _collapse_button: Button
var _locale_button: Button
var _quit_button: Button
var _archive_dialog: UDCardDialog
var _treasure_button: Button
var _treasure_dialog: UDCardDialog
var _shop_button: Button
var _shop_dialog: UDCardDialog
var _altar_dialog: UDCardDialog
var _guild_dialog: UDCardDialog
var _dorm_dialog: UDCardDialog
## Auto-picked consumption plan for the selected guild exchange target.
var _guild_plan: Dictionary = {}

@onready var tick_timer: Timer = $TickTimer
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	settings = UDSettings.load_settings()
	locale = UDLocale.load_locale(settings.locale_code)
	doc_db = UDDocumentDB.load_from_dir("res://data/documents")
	facility_db = UDShopDB.load_from_dir("res://data/facilities")
	item_db = UDItemDB.load_from_dir("res://data/items")
	shop_db = UDShopDB.load_from_dir("res://data/shop")
	doc_series = UDDataLoader.load_json_dir("res://data/series")
	var series_ids: Array[String] = []
	for def: Variant in doc_series:
		series_ids.append(str((def as Dictionary)["id"]))
	art = UDArtLibrary.load_default(
		facility_db.all_ids(), item_db.all_ids(), shop_db.all_ids(), doc_db.all_ids(), series_ids
	)
	achievements = UDAchievements.load_default(UDPlatform.create())
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
			item_db.all_ids(), companion_defs, doc_db.conditions_by_id(),
			item_db.ranks_by_id()
		)
	else:
		sim = UDSim.from_dict(
			payload["sim"], strata_db, item_db.all_ids(), companion_defs,
			doc_db.conditions_by_id(), item_db.ranks_by_id()
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
	_build_altar_dialog()
	_build_guild_dialog()
	_build_dorm_dialog()
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
	_track_dig_swing_starts()
	if not settings.tutorial_seen and sim.tick_count >= UD.TUTORIAL_TICKS:
		settings.tutorial_seen = true
		settings.save()
	var fresh_achievements := achievements.evaluate(sim)
	if not fresh_achievements.is_empty():
		achievements.save()
	for ach_id in fresh_achievements:
		var ach_name := ach_id
		for def: Variant in achievements.defs:
			if str((def as Dictionary)["id"]) == ach_id:
				ach_name = locale.text((def as Dictionary)["name_key"])
				break
		_tally_text = locale.text("UI_ACHIEVEMENT") % ach_name
		_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	if not settings.resident_mode:
		# While the big window is open, loot converts as it is dug.
		sim.collect_loot()
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	UDResidentWindow.sync_render_loop(get_window())
	_follow_camera()
	queue_redraw()


## Stamps the animation-time origin of every swing the instant a minion
## enters DIGGING, so _draw_minions always starts the loop at the
## wind-up frame instead of sampling into it mid-strike.
func _track_dig_swing_starts() -> void:
	for minion in sim.minions:
		var prev_state: int = int(_prev_minion_state.get(minion.id, -1))
		if minion.state == UDMinion.State.DIGGING \
				and prev_state != UDMinion.State.DIGGING:
			_dig_anim_start[minion.id] = _anim_frame
		_prev_minion_state[minion.id] = minion.state


## The camera anchors on the protagonist (minion 0): wherever they walk
## or dig, the view follows.
func _followed_minion() -> UDMinion:
	if sim.minions.is_empty():
		return null
	return sim.minions[0]


## The camera is computed live from the followed miner in _grid_origin(),
## so following just needs a redraw as the miner advances rightward.
func _follow_camera() -> void:
	queue_redraw()


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
		# No manual scrolling: the camera auto-follows the tunnel front.
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				_handle_click(mouse.position)
			MOUSE_BUTTON_RIGHT:
				_cancel_designation(mouse.position)
	elif event is InputEventMouseMotion:
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
	if sim.add_dig_job(cell):
		queue_redraw()


func _cancel_designation(click_pos: Vector2) -> void:
	var cell := _cell_at(click_pos)
	if cell != UDMinion.NO_TARGET and sim.remove_dig_job(cell):
		queue_redraw()


## The strip has no HUD bar: cells use the full height.
func _hud_offset() -> int:
	return 0 if settings.resident_mode else HUD_HEIGHT


## The tunnel is a thin fixed-height corridor: size the cell so all
## CORRIDOR_HEIGHT rows fit without any vertical scroll. The strip squeezes
## them into the taskbar band; expanded fills the window height.
func _cell_px() -> int:
	if settings.resident_mode:
		return clampi(int(size.y) / UD.CORRIDOR_HEIGHT, 8, 64)
	var avail_h := size.y - _hud_offset()
	return mini(EXPANDED_CELL_PX, int(avail_h / UD.CORRIDOR_HEIGHT))


func _visible_rows() -> int:
	return maxi(1, int((size.y - _hud_offset()) / _cell_px()))


## Camera: the corridor is centered vertically and follows the miner
## horizontally (no scrolling — the view auto-pans as the tunnel advances).
func _grid_origin() -> Vector2:
	var cell_px := _cell_px()
	var star := _followed_minion()
	var star_x := float(star.pos.x) if star != null else float(UD.DEPOT_POS.x)
	var view_width := size.x if settings.resident_mode else size.x - PANEL_WIDTH
	# Keep the miner centered, but never scroll left past the entrance.
	var origin_x := minf(view_width / 2.0 - (star_x + 0.5) * cell_px, 0.0)
	var avail_h := size.y - _hud_offset()
	var origin_y := _hud_offset() + (avail_h - sim.grid.height * cell_px) / 2.0
	return Vector2(origin_x, origin_y)


func _cell_at(point: Vector2) -> Vector2i:
	var origin := _grid_origin()
	var local := point - origin
	if local.x < 0.0 or local.y < 0.0:
		return UDMinion.NO_TARGET
	var cell_px := _cell_px()
	var cell := Vector2i(int(local.x / cell_px), int(local.y / cell_px))
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
		"%s %d/%d" % [locale.text("UI_TREASURES"), sim.distinct_items(), item_db.all_ids().size()],
		"⛏ %d" % sim.minions.size(),
		"▼ %d" % sim.frontier_distance(),
		"tick %d" % sim.tick_count,
	]
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
	if _tutorial_active():
		draw_string(
			font, Vector2(8, size.y - 10), _tutorial_hint(),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 16, STRIP_BADGE
		)


## First-run only (§10): the pitch is that leaving the game alone is
## correct play, so the hints rotate quietly instead of interrupting.
func _tutorial_active() -> bool:
	return not settings.tutorial_seen and sim.tick_count < UD.TUTORIAL_TICKS


func _tutorial_hint() -> String:
	var index := int(sim.tick_count / UD.TUTORIAL_HINT_CYCLE_TICKS) \
		% UD.TUTORIAL_HINT_KEYS.size()
	return locale.text(UD.TUTORIAL_HINT_KEYS[index])


## Translucent readout drawn over the cells; the strip has no HUD bar.
## Unread documents blink at the right edge (§5.1: icon blink only).
## Walking or digging direction; the last horizontal direction sticks.
func _minion_facing(minion: UDMinion) -> int:
	var dir := 0
	if minion.state == UDMinion.State.DIGGING \
			and minion.job_target != UDMinion.NO_TARGET:
		dir = signi(minion.job_target.x - minion.pos.x)
	elif not minion.path.is_empty():
		dir = signi(minion.path[0].x - minion.pos.x)
	if dir != 0:
		_facing[minion.id] = dir
	return int(_facing.get(minion.id, 1))


## Dig chips colored like the block actually being chewed (§ user
## feedback: brown dust on gray rock reads wrong).
func _draw_debris(origin: Vector2) -> void:
	var chip := maxf(2.0, _cell_px() / 12.0)
	for minion in sim.minions:
		if minion.state != UDMinion.State.DIGGING:
			continue
		if minion.job_target == UDMinion.NO_TARGET \
				or not sim.grid.is_inside(minion.job_target):
			continue
		var terrain := sim.grid.terrain_at(minion.job_target)
		if terrain == UD.Terrain.AIR or not _cell_visible(minion.job_target):
			continue
		var rect := _cell_rect(origin, minion.job_target)
		var base := _cell_color(terrain, minion.job_target.y)
		for i in 3:
			var off: Vector2 = DEBRIS_OFFSETS[(_anim_frame + i * 2) % DEBRIS_OFFSETS.size()]
			draw_rect(
				Rect2(rect.position + off * rect.size * 0.85, Vector2(chip, chip)),
				base.lightened(0.12 + 0.1 * float(i))
			)


func _draw_strip_overlay(font: Font) -> void:
	var coin_part := "$%d" % int(sim.inventory[UD.RES_GOLD])
	var pending := sim.pending_loot_total()
	if pending > 0:
		coin_part += "(+%d)" % pending
	var text := "%s ▼%d ⛏%d" % [coin_part, sim.frontier_distance(), sim.minions.size()]
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
	if _tutorial_active():
		var hint := _tutorial_hint()
		var hint_width := font.get_string_size(
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE
		).x
		var hint_y := size.y - 14
		draw_rect(Rect2(Vector2(0, hint_y), Vector2(hint_width + 12, 14)), STRIP_TEXT_BG)
		draw_string(
			font, Vector2(6, hint_y + 11), hint,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, STRIP_FONT_SIZE, STRIP_BADGE
		)


func _draw_grid() -> void:
	var origin := _grid_origin()
	var cell_px := _cell_px()
	# Cull to the visible column window — the tunnel can be thousands of
	# cells long, so never iterate the whole grid (§7.1 CPU budget).
	var first_col: int = maxi(0, int(-origin.x / cell_px))
	var last_col: int = mini(sim.grid.width, first_col + int(size.x / cell_px) + 2)
	for y in sim.grid.height:
		for x in range(first_col, last_col):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(origin, cell)
			var terrain := sim.grid.terrain_at(cell)
			if terrain == UD.Terrain.AIR:
				# Open, dug-out tunnel: just the dark background.
				continue
			var art_key := art.terrain_key(terrain)
			if art.has_art(art_key):
				draw_texture_rect(art.variant_texture(art_key, hash(cell)), rect, false)
			else:
				draw_rect(rect, _cell_color(terrain, y))
				draw_rect(rect, COLOR_GRID_LINE, false, 1.0)
	_draw_jobs(origin)
	_draw_depot(origin)
	_draw_minions(origin)
	_draw_debris(origin)


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
		origin + Vector2(cell.x * cell_px, cell.y * cell_px),
		Vector2(cell_px, cell_px)
	)


func _cell_visible(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= sim.grid.height:
		return false
	var rect := _cell_rect(_grid_origin(), cell)
	return rect.position.x + rect.size.x > 0.0 and rect.position.x < size.x


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


## Party slot -> art variant. Slot 0 is always the protagonist; slot N
## (N>=1) corresponds to sim.companions[N-1] in join order, so the art
## key is looked up by companion identity rather than the slot index
## (fixes companions rendering as an unnamed placeholder block).
func _minion_art_variant(slot_index: int) -> int:
	if slot_index == 0:
		return 0
	var companion_index := slot_index - 1
	if companion_index < sim.companions.size():
		return UDMinion.art_variant_for_companion(sim.companions[companion_index])
	return slot_index


func _draw_minions(origin: Vector2) -> void:
	var cell_px := _cell_px()
	var inset := maxi(MINION_INSET, cell_px / 6)
	for slot_index in sim.minions.size():
		var minion: UDMinion = sim.minions[slot_index]
		if not _cell_visible(minion.pos):
			continue
		var rect := _cell_rect(origin, minion.pos)
		# Work bob, phase-shifted per minion and scaled with zoom.
		var bob := 0.0
		if minion.state != UDMinion.State.IDLE:
			bob = float(((sim.tick_count + minion.id) % 2) * maxi(1, cell_px / 12))
		var art_variant := _minion_art_variant(slot_index)
		var art_key := art.minion_key(art_variant)
		if art.has_art(art_key):
			# Illustrated sprites carry their own margins: use the full cell.
			var sprite_rect := Rect2(
				rect.position + Vector2(0, bob), Vector2(cell_px, cell_px - bob)
			)
			var tex: Texture2D
			# The frame set is a dig loop (§6: wind-up -> strike -> dust
			# -> recover), not a walk cycle: only animate while actually
			# digging, or the sprite reads as jittering while moving
			# between jobs. The swing always starts at the wind-up frame
			# (index 1: index 0 is the idle/base pose) relative to when
			# THIS dig began, not the global animation clock, or a swing
			# could open already mid-strike.
			if minion.state == UDMinion.State.DIGGING and art.frame_count(art_key) > 1:
				var swing_start := int(_dig_anim_start.get(minion.id, _anim_frame))
				tex = art.frame(art_key, 1 + _anim_frame - swing_start)
			else:
				tex = art.texture(art_key)
			var native := int(MINION_NATIVE_FACING.get(art_variant, 1))
			if _minion_facing(minion) != native:
				# Mirror around the sprite's vertical center line.
				draw_set_transform(
					Vector2(sprite_rect.get_center().x * 2.0, 0.0), 0.0, Vector2(-1, 1)
				)
				draw_texture_rect(tex, sprite_rect, false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
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

	_policy_button = _make_button("", _cycle_dig_policy)
	grid.add_child(_policy_button)
	for facility_id in facility_db.all_ids():
		var button := _make_button("", _on_facility_button.bind(facility_id))
		_facility_buttons[facility_id] = button
		grid.add_child(button)
	_archive_button = _make_button("", _open_archive)
	grid.add_child(_archive_button)
	_treasure_button = _make_button("", _open_treasures)
	grid.add_child(_treasure_button)
	_shop_button = _make_button("", _open_shop)
	grid.add_child(_shop_button)
	_height_button = _make_button("", _cycle_height)
	grid.add_child(_height_button)
	_locale_button = _make_button("", _toggle_locale)
	grid.add_child(_locale_button)
	_collapse_button = _make_button("", _collapse)
	grid.add_child(_collapse_button)
	_quit_button = _make_button("", _quit)
	grid.add_child(_quit_button)


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.pressed.connect(callback)
	return button


## Facility buttons (user request 2026-07-13: no map placement at all —
## pressing the button unlocks the facility outright, same one-time
## cost as before, then opens its screen. Reuses the shop's buy_upgrade
## command with max_level 1, so altar/guild/dorm live in the same
## "upgrades" ledger as pickaxe/survey and need no bespoke sim state.
func _on_facility_button(facility_id: String) -> void:
	if sim.upgrade_level(facility_id) <= 0 and not _auto_build(facility_id):
		return
	match facility_id:
		"altar":
			_open_altar()
		"tavern":
			_open_guild()
		"dorm":
			_open_dorm()


func _auto_build(facility_id: String) -> bool:
	var def := facility_db.get_good(facility_id)
	if sim.buy_upgrade(def):
		return true
	_tally_text = locale.text("UI_BUILD_CANNOT_AFFORD") % locale.text(def["name_key"])
	_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	return false


func _refresh_archive_button() -> void:
	if _archive_button == null:
		return
	var label := locale.text("UI_ARCHIVE")
	if not unread_docs.is_empty():
		label += " (%d)" % unread_docs.size()
	_archive_button.text = label


func _refresh_button_texts() -> void:
	for facility_id: String in _facility_buttons:
		var button: Button = _facility_buttons[facility_id]
		button.text = locale.text(facility_db.get_good(facility_id)["name_key"])
	_policy_button.text = locale.text(_policy_label_key())
	_height_button.text = "%dpx" % UD.WINDOW_HEIGHTS[settings.height_index]
	_collapse_button.text = locale.text("UI_COLLAPSE")
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	_shop_button.text = locale.text("UI_SHOP")
	_locale_button.text = _next_locale_code().to_upper()
	_quit_button.text = locale.text("UI_QUIT")
	_refresh_archive_button()


## The button is a plain on/off toggle; WIDEN stays core-only.
func _cycle_dig_policy() -> void:
	if sim.dig_policy == UD.DigPolicy.NONE:
		sim.dig_policy = UD.DigPolicy.RIGHT
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
	_archive_dialog = UDCardDialog.create(locale.text("UI_ARCHIVE"), false)
	_archive_dialog.card_selected.connect(_on_archive_card_selected)
	_archive_dialog.back_pressed.connect(_show_archive_series_shelf)
	_archive_dialog.set_background(art.texture("dialog_bg_archive"))
	add_child(_archive_dialog)


func _build_treasure_dialog() -> void:
	_treasure_dialog = UDCardDialog.create(locale.text("UI_TREASURES"), false)
	_treasure_dialog.card_selected.connect(_on_treasure_card_selected)
	_treasure_dialog.back_pressed.connect(_show_treasure_rank_shelf)
	_treasure_dialog.set_background(art.texture("dialog_bg_treasure"))
	add_child(_treasure_dialog)


## Two-level treasure shelf (same UX as the archive, 2026-07-14 user
## request — one less layout for the player to learn): the shelf shows
## one card per rank (Z/S/A/B/C/D), opening a rank lists its items as
## owned cards or locked ????? slots.
func _open_treasures() -> void:
	if settings.resident_mode:
		_expand()
	_show_treasure_rank_shelf()
	_treasure_dialog.popup_centered()


func _rank_item_ids(rank: String) -> Array[String]:
	var ids: Array[String] = []
	for item_id in item_db.all_ids():
		if item_db.rank(item_id) == rank:
			ids.append(item_id)
	return ids


func _show_treasure_rank_shelf() -> void:
	_treasure_rank = ""
	_treasure_dialog.clear_cards()
	for rank in UD.ITEM_RANKS:
		var item_ids := _rank_item_ids(rank)
		if item_ids.is_empty():
			continue
		var owned := 0
		for item_id in item_ids:
			if sim.item_count(item_id) > 0:
				owned += 1
		_treasure_dialog.add_card(
			rank, locale.text("UI_RANK_LABEL") % rank, "%d / %d" % [owned, item_ids.size()],
			art.icon_or_placeholder("item_rank_%s" % rank, rank, "gem"), false
		)
	_treasure_dialog.set_back(locale.text("UI_BACK"), false)
	_treasure_dialog.set_progress(
		locale.text("UI_PROGRESS_ITEMS") % [sim.distinct_items(), item_db.all_ids().size()]
	)
	_treasure_dialog.show_detail("", locale.text("UI_SELECT_RANK_HINT"), null)


func _show_treasure_rank(rank: String) -> void:
	_treasure_rank = rank
	_treasure_dialog.clear_cards()
	var item_ids := _rank_item_ids(rank)
	var owned := 0
	for item_id in item_ids:
		var is_owned := sim.item_count(item_id) > 0
		if is_owned:
			owned += 1
		var icon := art.icon_or_placeholder("item_%s" % item_id, item_id, "gem")
		var title_text := locale.text(item_db.get_item(item_id)["name_key"]) \
			if is_owned else ""
		var subtitle := "×%d" % sim.item_count(item_id) if is_owned else ""
		_treasure_dialog.add_card(item_id, title_text, subtitle, icon, not is_owned)
	_treasure_dialog.set_back(locale.text("UI_BACK"), true)
	_treasure_dialog.set_progress(
		"%s   %d / %d" % [locale.text("UI_RANK_LABEL") % rank, owned, item_ids.size()]
	)
	_treasure_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var first := _treasure_dialog.first_unlocked_id()
	if first != "":
		_treasure_dialog.select_card(first)


func _on_treasure_card_selected(card_id: String) -> void:
	if _treasure_rank == "":
		_show_treasure_rank(card_id)
		return
	var item := item_db.get_item(card_id)
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s: %s[/b]   ×%d / %d" % [
		locale.text("UI_RANK"), item_db.rank(card_id),
		sim.item_count(card_id), sim.item_cap(card_id),
	]
	_treasure_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % card_id, card_id, "gem")
	)


func _build_shop_dialog() -> void:
	_shop_dialog = UDCardDialog.create(locale.text("UI_SHOP"), true)
	_shop_dialog.card_selected.connect(_on_shop_card_selected)
	_shop_dialog.action_pressed.connect(_on_shop_buy)
	add_child(_shop_dialog)


func _open_shop() -> void:
	if settings.resident_mode:
		_expand()
	_populate_shop("")
	_shop_dialog.title = locale.text("UI_SHOP")
	_shop_dialog.popup_centered()


## Goods hang like framed wares (reference shot): the card carries name,
## level and price; the detail panel sells it and holds the buy button.
func _populate_shop(keep_selection: String) -> void:
	_shop_dialog.clear_cards()
	for good_id in shop_db.all_ids():
		var good := shop_db.get_good(good_id)
		var level := sim.upgrade_level(good_id)
		var max_level := int(good["max_level"])
		var subtitle := "Lv.%d/%d" % [level, max_level]
		if level >= max_level:
			subtitle += "  MAX"
		else:
			subtitle += "  $%d" % UDSim.upgrade_cost(good, level)
		var icon := art.icon_or_placeholder("shop_%s" % good_id, good_id, "rune")
		_shop_dialog.add_card(
			good_id, locale.text(good["name_key"]), subtitle, icon, false
		)
	_shop_dialog.set_progress(
		"%s %d" % [locale.text("RES_GOLD"), int(sim.inventory[UD.RES_GOLD])]
	)
	_shop_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	_shop_dialog.set_action(locale.text("UI_BUY"), true)
	var select_id := keep_selection
	if select_id == "":
		select_id = _shop_dialog.first_unlocked_id()
	if select_id != "":
		_shop_dialog.select_card(select_id)


func _on_shop_card_selected(good_id: String) -> void:
	var good := shop_db.get_good(good_id)
	var level := sim.upgrade_level(good_id)
	var max_level := int(good["max_level"])
	var body := locale.text(good["desc_key"])
	var maxed := level >= max_level
	var cost := 0
	if maxed:
		body += "\n\n[b]Lv.%d/%d  MAX[/b]" % [level, max_level]
	else:
		cost = UDSim.upgrade_cost(good, level)
		body += "\n\n[b]Lv.%d/%d[/b]   $%d" % [level, max_level, cost]
	_shop_dialog.show_detail(
		locale.text(good["name_key"]), body,
		art.icon_or_placeholder("shop_%s" % good_id, good_id, "rune")
	)
	var affordable := not maxed and int(sim.inventory[UD.RES_GOLD]) >= cost
	_shop_dialog.set_action(locale.text("UI_BUY"), not affordable)


func _on_shop_buy(good_id: String) -> void:
	var good := shop_db.get_good(good_id)
	if sim.buy_upgrade(good):
		_populate_shop(good_id)
		queue_redraw()


## --- Dorm ---------------------------------------------------------
## Pure flavor (no gameplay effect): a roster card per party member.

func _build_dorm_dialog() -> void:
	_dorm_dialog = UDCardDialog.create(locale.text("ROOM_DORM"), false)
	_dorm_dialog.card_selected.connect(_on_dorm_card_selected)
	_dorm_dialog.set_background(art.texture("dialog_bg_dorm"))
	add_child(_dorm_dialog)


func _open_dorm() -> void:
	if settings.resident_mode:
		_expand()
	_dorm_dialog.clear_cards()
	for slot_index in sim.minions.size():
		var art_variant := _minion_art_variant(slot_index)
		var minion_id := "minion_%d" % slot_index
		var display_name := locale.text("APP_TITLE") if slot_index == 0 else ""
		if slot_index > 0 and slot_index - 1 < sim.companions.size():
			var companion_id: String = sim.companions[slot_index - 1]
			if _companion_by_id.has(companion_id):
				display_name = locale.text(_companion_by_id[companion_id]["name_key"])
		_dorm_dialog.add_card(
			minion_id, display_name, "",
			art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune"), false
		)
	_dorm_dialog.set_progress("%s %d/%d" % [
		locale.text("UI_PARTY"), sim.minions.size(), UD.MINION_MAX,
	])
	_dorm_dialog.title = locale.text("ROOM_DORM")
	_dorm_dialog.show_detail("", locale.text("FACILITY_DORM_DESC"), null)
	if sim.minions.size() > 0:
		_dorm_dialog.select_card("minion_0")
	_dorm_dialog.popup_centered()


func _on_dorm_card_selected(minion_id: String) -> void:
	var slot_index := int(minion_id.trim_prefix("minion_"))
	var art_variant := _minion_art_variant(slot_index)
	var display_name := locale.text("APP_TITLE")
	if slot_index > 0 and slot_index - 1 < sim.companions.size():
		var companion_id: String = sim.companions[slot_index - 1]
		if _companion_by_id.has(companion_id):
			display_name = locale.text(_companion_by_id[companion_id]["name_key"])
	_dorm_dialog.show_detail(
		display_name, locale.text("FACILITY_DORM_DESC"),
		art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune")
	)


## --- Altar offerings -------------------------------------------------
## Coins (and at higher levels a treasure of the demanded rank) buy
## permanent-for-this-run dig power (user spec 2026-07-12).

func _build_altar_dialog() -> void:
	_altar_dialog = UDCardDialog.create(locale.text("UI_ALTAR"), true)
	_altar_dialog.card_selected.connect(_on_altar_card_selected)
	_altar_dialog.action_pressed.connect(_on_altar_offer)
	_altar_dialog.set_background(art.texture("dialog_bg_altar"))
	# Whichever party member is being enhanced stands on the altar table;
	# hardcoded to the hero (minion 0) until per-companion altar upgrades
	# and their effects are designed.
	_altar_dialog.set_character(art.texture(art.minion_key(0)), 0.68)
	add_child(_altar_dialog)


func _open_altar() -> void:
	if settings.resident_mode:
		_expand()
	_populate_altar()
	_altar_dialog.title = locale.text("UI_ALTAR")
	_altar_dialog.popup_centered()


func _populate_altar() -> void:
	_altar_dialog.clear_cards()
	_altar_dialog.set_back("", false)
	_altar_dialog.set_progress("%s   %s %d" % [
		locale.text("UI_ALTAR_LEVEL") % sim.altar_level,
		locale.text("RES_GOLD"), int(sim.inventory[UD.RES_GOLD]),
	])
	_altar_dialog.set_action(locale.text("UI_ALTAR_OFFER"), true)
	if not sim.altar_built():
		_altar_dialog.show_detail("", locale.text("UI_ALTAR_NEEDS_ROOM"), null)
		return
	var required_rank := sim.altar_required_item_rank()
	if required_rank == "":
		_altar_dialog.add_card(
			"__coins__", locale.text("UI_ALTAR_COINS"),
			"$%d" % sim.altar_offer_cost(),
			art.icon_or_placeholder("room_altar", "altar_offer", "rune"), false
		)
	else:
		for item_id in item_db.ids_of_rank(required_rank):
			if sim.item_count(item_id) <= 0:
				continue
			_altar_dialog.add_card(
				item_id, locale.text(item_db.get_item(item_id)["name_key"]),
				"%s  ×%d" % [required_rank, sim.item_count(item_id)],
				art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"),
				false
			)
		if not _altar_dialog.has_cards():
			_altar_dialog.show_detail("", "%s\n%s" % [
				locale.text("UI_ALTAR_NEED_RANK") % required_rank,
				locale.text("UI_ALTAR_NO_ITEM") % required_rank,
			], null)
			return
	var first := _altar_dialog.first_unlocked_id()
	if first != "":
		_altar_dialog.select_card(first)


func _on_altar_card_selected(card_id: String) -> void:
	var cost := sim.altar_offer_cost()
	var body := "%s\n\n[b]$%d[/b]" % [locale.text("UI_ALTAR_EFFECT"), cost]
	var required_rank := sim.altar_required_item_rank()
	var title := locale.text("UI_ALTAR_COINS")
	var icon := art.icon_or_placeholder("room_altar", "altar_offer", "rune")
	if required_rank != "" and card_id != "__coins__":
		body += "\n%s" % (locale.text("UI_ALTAR_NEED_RANK") % required_rank)
		title = locale.text(item_db.get_item(card_id)["name_key"])
		icon = art.icon_or_placeholder("item_%s" % card_id, card_id, "gem")
	_altar_dialog.show_detail(title, body, icon)
	var affordable := int(sim.inventory[UD.RES_GOLD]) >= cost
	_altar_dialog.set_action(locale.text("UI_ALTAR_OFFER"), not affordable)


func _on_altar_offer(card_id: String) -> void:
	var item_id := "" if card_id == "__coins__" else card_id
	if sim.offer_at_altar(item_id):
		_populate_altar()
		queue_redraw()


## --- Guild exchange ---------------------------------------------------
## Rank-up exchange runs locally today; person-to-person trading rides
## on Steam later through the same sim command (UDPlatform).

func _build_guild_dialog() -> void:
	_guild_dialog = UDCardDialog.create(locale.text("UI_GUILD"), true)
	_guild_dialog.card_selected.connect(_on_guild_card_selected)
	_guild_dialog.action_pressed.connect(_on_guild_exchange)
	add_child(_guild_dialog)




func _open_guild() -> void:
	if settings.resident_mode:
		_expand()
	_populate_guild("")
	_guild_dialog.title = locale.text("UI_GUILD")
	_guild_dialog.popup_centered()


func _populate_guild(keep_selection: String) -> void:
	_guild_dialog.clear_cards()
	_guild_dialog.set_back("", false)
	_guild_dialog.set_progress(locale.text("UI_GUILD_NOTE"))
	_guild_dialog.set_action(locale.text("UI_EXCHANGE"), true)
	if not sim.guild_built():
		_guild_dialog.show_detail("", locale.text("UI_GUILD_NEEDS_ROOM"), null)
		return
	for item_id in item_db.all_ids():
		var rank := item_db.rank(item_id)
		if not UD.ITEM_EXCHANGE_COSTS.has(rank):
			continue
		var fodder_rank := sim.rank_below(rank)
		_guild_dialog.add_card(
			item_id, locale.text(item_db.get_item(item_id)["name_key"]),
			"%s ← %s×%d" % [rank, fodder_rank, int(UD.ITEM_EXCHANGE_COSTS[rank])],
			art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"),
			false
		)
	_guild_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var select_id := keep_selection
	if select_id == "":
		select_id = _guild_dialog.first_unlocked_id()
	if select_id != "":
		_guild_dialog.select_card(select_id)


## Greedy auto-pick: spend the most plentiful fodder first so rare
## spares survive. Returns {} when the player cannot cover the cost.
func _guild_exchange_plan(target_id: String) -> Dictionary:
	var rank := item_db.rank(target_id)
	if not UD.ITEM_EXCHANGE_COSTS.has(rank):
		return {}
	var needed := int(UD.ITEM_EXCHANGE_COSTS[rank])
	var fodder_rank := sim.rank_below(rank)
	var owned: Array[String] = []
	for item_id in item_db.ids_of_rank(fodder_rank):
		if item_id != target_id and sim.item_count(item_id) > 0:
			owned.append(item_id)
	owned.sort_custom(
		func(a: String, b: String) -> bool:
			return sim.item_count(a) > sim.item_count(b)
	)
	var plan: Dictionary = {}
	for item_id in owned:
		if needed <= 0:
			break
		var take := mini(needed, sim.item_count(item_id))
		plan[item_id] = take
		needed -= take
	if needed > 0:
		return {}
	return plan


func _on_guild_card_selected(target_id: String) -> void:
	var item := item_db.get_item(target_id)
	var rank := item_db.rank(target_id)
	var fodder_rank := sim.rank_below(rank)
	var needed := int(UD.ITEM_EXCHANGE_COSTS[rank])
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s[/b]" % (locale.text("UI_GUILD_COST") % [fodder_rank, needed])
	body += "\n%s ×%d / %d" % [
		locale.text("UI_RANK") + " " + rank,
		sim.item_count(target_id), sim.item_cap(target_id),
	]
	_guild_plan = _guild_exchange_plan(target_id)
	var at_cap := sim.item_count(target_id) >= sim.item_cap(target_id)
	if _guild_plan.is_empty():
		body += "\n\n%s" % (locale.text("UI_GUILD_SHORT") % [fodder_rank, needed])
	else:
		body += "\n\n%s" % locale.text("UI_GUILD_CONSUMES")
		for consume_id: Variant in _guild_plan.keys():
			body += "\n  %s ×%d" % [
				locale.text(item_db.get_item(str(consume_id))["name_key"]),
				int(_guild_plan[consume_id]),
			]
	_guild_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % target_id, target_id, "gem")
	)
	_guild_dialog.set_action(
		locale.text("UI_EXCHANGE"), _guild_plan.is_empty() or at_cap
	)


func _on_guild_exchange(target_id: String) -> void:
	if sim.exchange_item(target_id, _guild_plan):
		_populate_guild(target_id)
		queue_redraw()


## Two-level archive (user request 2026-07-12): the shelf shows one card
## per series (メインストーリー / 外伝 …, data/series/); opening a series
## lists its documents in number order, unfound ones blacked out as ?????.
func _open_archive() -> void:
	if settings.resident_mode:
		# Documents are unreadable in a 48px strip: expand first.
		_expand()
	_show_archive_series_shelf()
	_archive_dialog.popup_centered()


func _series_doc_ids(series_id: String) -> Array[String]:
	var ids: Array[String] = []
	for doc_id in doc_db.all_ids():
		if str(doc_db.get_doc(doc_id).get("series", "other")) == series_id:
			ids.append(doc_id)
	return ids


func _show_archive_series_shelf() -> void:
	_archive_series = ""
	_archive_dialog.clear_cards()
	for def: Variant in doc_series:
		var series := def as Dictionary
		var series_id := str(series["id"])
		var doc_ids := _series_doc_ids(series_id)
		if doc_ids.is_empty():
			continue
		var found := 0
		var has_unread := false
		for doc_id in doc_ids:
			if sim.discovered_documents.has(doc_id):
				found += 1
			if unread_docs.has(doc_id):
				has_unread = true
		var subtitle := "%d / %d" % [found, doc_ids.size()]
		if has_unread:
			subtitle += " ✦"
		_archive_dialog.add_card(
			series_id, locale.text(series["name_key"]), subtitle,
			art.icon_or_placeholder("series_%s" % series_id, series_id, "book"),
			false
		)
	_archive_dialog.set_back(locale.text("UI_BACK"), false)
	_archive_dialog.set_progress(locale.text("UI_PROGRESS_DOCS") % [
		sim.discovered_documents.size(), doc_db.count(),
	])
	_archive_dialog.show_detail("", locale.text("UI_SELECT_SERIES_HINT"), null)


func _show_archive_series(series_id: String) -> void:
	_archive_series = series_id
	var fresh := unread_docs.duplicate()
	_archive_dialog.clear_cards()
	var found := 0
	var doc_ids := _series_doc_ids(series_id)
	for doc_id in doc_ids:
		var is_found := sim.discovered_documents.has(doc_id)
		if is_found:
			found += 1
		var doc := doc_db.get_doc(doc_id)
		var subtitle := _doc_number_label(doc_id)
		if fresh.has(doc_id):
			subtitle += " ✦"
		_archive_dialog.add_card(
			doc_id, locale.text(doc["title_key"]) if is_found else "",
			subtitle, art.icon_or_placeholder(doc_id, doc_id, "book"),
			not is_found
		)
		# Entering the shelf marks this series' pages as read.
		unread_docs.erase(doc_id)
	_refresh_archive_button()
	var series_name := series_id
	for def: Variant in doc_series:
		if str((def as Dictionary)["id"]) == series_id:
			series_name = locale.text((def as Dictionary)["name_key"])
			break
	_archive_dialog.set_back(locale.text("UI_BACK"), true)
	_archive_dialog.set_progress("%s   %d / %d" % [series_name, found, doc_ids.size()])
	_archive_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	# Open on the newest unread page in this series, else the first found.
	var select_id := ""
	for doc_id in doc_ids:
		if fresh.has(doc_id):
			select_id = doc_id
			break
	if select_id == "":
		select_id = _archive_dialog.first_unlocked_id()
	if select_id != "":
		_archive_dialog.select_card(select_id)


## doc_007 -> "No.7" (matches the reference catalogue numbering).
func _doc_number_label(doc_id: String) -> String:
	var digits := ""
	for i in range(doc_id.length() - 1, -1, -1):
		if not doc_id[i].is_valid_int():
			break
		digits = doc_id[i] + digits
	return ("No.%d" % int(digits)) if digits != "" else doc_id


func _on_archive_card_selected(card_id: String) -> void:
	if _archive_series == "":
		_show_archive_series(card_id)
		return
	var doc := doc_db.get_doc(card_id)
	_archive_dialog.show_detail(
		locale.text(doc["title_key"]),
		locale.text(doc["body_key"]),
		art.icon_or_placeholder(card_id, card_id, "book")
	)


func _quit() -> void:
	UDSaveManager.save_game(sim)
	get_tree().quit()
