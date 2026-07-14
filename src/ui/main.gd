extends Control
## Resident-strip main view (2026-07-15 redesign: dig -> cave exploration +
## turn-based combat). Draws the idle battle view, hosts the boss-fight
## turn menu, and hosts every card dialog (shop/treasure/archive/altar/
## guild/dorm).

const HUD_HEIGHT: int = 22
const HUD_FONT_SIZE: int = 12

const COLOR_BACKGROUND := Color(0.05, 0.045, 0.07)
const COLOR_HUD_TEXT := Color(0.85, 0.82, 0.75)
const COLOR_HP_BAR_BG := Color(0.15, 0.05, 0.05)
const COLOR_HP_BAR := Color(0.75, 0.2, 0.2)
const COLOR_MP_BAR_BG := Color(0.05, 0.08, 0.15)
const COLOR_MP_BAR := Color(0.25, 0.45, 0.85)
const COLOR_ENEMY_HP_BAR := Color(0.8, 0.3, 0.15)
const COLOR_GATE_BADGE := Color(1.0, 0.5, 0.2)
const COLOR_DIG_ROCKMASS := Color(0.1, 0.09, 0.12)

var sim: UDSim
var settings: UDSettings
var locale: UDLocale
var doc_db: UDDocumentDB
var facility_db: UDShopDB
var item_db: UDItemDB
var shop_db: UDShopDB
var enemy_db: UDEnemyDB
var stage_db: UDStageDB
var skill_db: UDSkillDB
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

var _tally_text: String = ""
var _tally_until_tick: int = 0

const TALLY_SHOW_TICKS: int = 5

## Expanded-mode control panel: big, thumb-friendly buttons on the
## right; the battle view does not need the full width.
const PANEL_WIDTH: int = 260
const BUTTON_FONT_SIZE: int = 16
const BUTTON_MIN_SIZE := Vector2(118, 44)

## UI-side sprite animation cadence (does not touch the simulation).
const ANIM_FRAME_SECONDS: float = 0.4
var unread_docs: Array[String] = []
var offline_ticks_applied: int = 0
## Snapshot taken right before offline catch-up, so the welcome-back
## summary can report what was earned while away (UI-only bookkeeping;
## the sim itself has no "pending" concept to collect).
var _offline_gold_before: int = 0
var _offline_exp_before: int = 0

var _button_bar: Control
var _archive_button: Button
var _facility_buttons: Dictionary = {}  # facility id -> Button
var _fight_button: Button
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

## Boss encounter panel (expanded-mode only): a turn menu per living
## unit (attack / one of their known skills), plus resolve/flee buttons.
var _boss_panel: Control
var _boss_enemy_label: Label
var _boss_hp_bar: ProgressBar
var _boss_unit_rows: Dictionary = {}  # unit id -> {option: OptionButton, hp_label: Label}
var _boss_log: Label

@onready var tick_timer: Timer = $TickTimer
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	settings = UDSettings.load_settings()
	locale = UDLocale.load_locale(settings.locale_code)
	doc_db = UDDocumentDB.load_from_dir("res://data/documents")
	facility_db = UDShopDB.load_from_dir("res://data/facilities")
	item_db = UDItemDB.load_from_dir("res://data/items")
	shop_db = UDShopDB.load_from_dir("res://data/shop")
	enemy_db = UDEnemyDB.load_from_dir("res://data/enemies")
	stage_db = UDStageDB.load_from_dir("res://data/stages")
	skill_db = UDSkillDB.load_from_dir("res://data/skills")
	doc_series = UDDataLoader.load_json_dir("res://data/series")
	var series_ids: Array[String] = []
	for def: Variant in doc_series:
		series_ids.append(str((def as Dictionary)["id"]))
	art = UDArtLibrary.load_default(
		facility_db.all_ids(), item_db.all_ids(), shop_db.all_ids(), doc_db.all_ids(),
		series_ids, enemy_db.all_ids()
	)
	achievements = UDAchievements.load_default(UDPlatform.create())
	anomalies = UDDataLoader.load_json_dir("res://data/anomalies")
	for anomaly: Variant in anomalies:
		_anomaly_by_id[(anomaly as Dictionary)["id"]] = anomaly
	companion_defs = UDDataLoader.load_json_dir("res://data/companions")
	for companion: Variant in companion_defs:
		_companion_by_id[(companion as Dictionary)["id"]] = companion

	var payload := UDSaveManager.load_game()
	if payload.is_empty():
		sim = UDSim.new_game(
			enemy_db, stage_db, int(Time.get_unix_time_from_system()),
			item_db.all_ids(), companion_defs, doc_db.conditions_by_id(),
			item_db.ranks_by_id(), skill_db
		)
	else:
		sim = UDSim.from_dict(
			payload["sim"], enemy_db, stage_db, item_db.all_ids(), companion_defs,
			doc_db.conditions_by_id(), item_db.ranks_by_id(), skill_db
		)
	_connect_sim_signals()
	if not payload.is_empty():
		_offline_gold_before = int(sim.inventory.get(UD.RES_GOLD, 0))
		_offline_exp_before = sim.exp_pool
		offline_ticks_applied = UDOffline.elapsed_ticks(
			int(payload["saved_unix_time"]),
			int(Time.get_unix_time_from_system())
		)
		sim.advance(offline_ticks_applied)
		if offline_ticks_applied > 0:
			_tally_text = _format_offline_summary()
			_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 4
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
	_build_boss_panel()
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
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	_refresh_fight_button()
	UDResidentWindow.sync_render_loop(get_window())
	queue_redraw()


func _connect_sim_signals() -> void:
	sim.document_discovered.connect(_on_document_discovered)
	sim.companion_joined.connect(_on_companion_joined)


func _on_document_discovered(doc_id: String) -> void:
	unread_docs.append(doc_id)
	_refresh_archive_button()


func _on_companion_joined(companion_id: String) -> void:
	var display_name := companion_id
	if _companion_by_id.has(companion_id):
		display_name = locale.text(_companion_by_id[companion_id]["name_key"])
	_tally_text = locale.text("UI_COMPANION_JOINED") % display_name
	_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if settings.resident_mode:
		# The strip is ambient: any click opens the management window.
		if event is InputEventMouseButton and event.pressed:
			_expand()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE \
			and not settings.resident_mode:
		_collapse()


## The strip has no HUD bar: the battle view uses the full height.
func _hud_offset() -> int:
	return 0 if settings.resident_mode else HUD_HEIGHT


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if sim == null:
		return
	_draw_hud()
	if not sim.boss_active:
		_draw_battle()


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
		"%s %d" % [locale.text("UI_STAGE"), sim.stage_index],
		"EXP %d" % sim.exp_pool,
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
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 16, STRIP_BADGE
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


func _draw_strip_overlay(font: Font) -> void:
	var gate := " ⚠" if stage_db.is_boss_stage(sim.stage_index) else ""
	var text := "$%d  ステージ%d%s  ⛏%d" % [
		int(sim.inventory[UD.RES_GOLD]), sim.stage_index, gate, sim.minions.size(),
	]
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


## --- Idle battle view (no boss fight active) -------------------------
## A simple readout of the auto-battle loop: the current trash mob (icon
## + HP bar) and the party roster (portrait + HP/MP bar + level). Not
## interactive — the only input here is "click the strip to expand".

const ENEMY_ICON_PX: int = 96
const PARTY_ICON_PX: int = 64
const BAR_HEIGHT: int = 6
## Where dig_background.png's floor plane sits, as a fraction of the view
## height (measured from the shipped art: the lit floor band runs roughly
## 0.70-0.82 down the image). Enemy/party icons plant their feet here
## instead of floating over the cave ceiling.
const GROUND_FRAC: float = 0.78
const SIDE_MARGIN_FRAC: float = 0.14


func _view_rect() -> Rect2 :
	var view_right := size.x if settings.resident_mode else size.x - float(PANEL_WIDTH)
	var view_top := float(_hud_offset())
	return Rect2(Vector2(0, view_top), Vector2(view_right, size.y - view_top))


func _draw_battle() -> void:
	var view := _view_rect()
	_draw_backdrop(view)
	_draw_enemy(view)
	_draw_party_row(view)


const SCROLL_PX_PER_KILL: float = 18.0


## Cave backdrop behind the battle view. Digging no longer scrolls a grid,
## so instead the tiled dig_background.png creeps right by a fixed step
## every time sim.total_kills ticks up (i.e. every kill, trash or boss) —
## a visible sense of walking forward each time an enemy falls.
func _draw_backdrop(view: Rect2) -> void:
	if not art.has_art("dig_background"):
		draw_rect(view, COLOR_DIG_ROCKMASS)
		return
	var tex := art.texture("dig_background")
	var scale := view.size.y / float(tex.get_height())
	var tile_w := tex.get_width() * scale
	var offset := fmod(float(sim.total_kills) * SCROLL_PX_PER_KILL, tile_w)
	var tx := view.position.x - offset
	while tx < view.position.x + view.size.x:
		draw_texture_rect(tex, Rect2(Vector2(tx, view.position.y), Vector2(tile_w, view.size.y)), false)
		tx += tile_w


func _ground_y(view: Rect2) -> float:
	return view.position.y + view.size.y * GROUND_FRAC


## Enemy stands on the right, facing the party across the cave floor.
func _draw_enemy(view: Rect2) -> void:
	if sim.enemy_id == "" or not enemy_db.has_enemy(sim.enemy_id):
		return
	var def := enemy_db.get_enemy(sim.enemy_id)
	var icon_px := ENEMY_ICON_PX if not settings.resident_mode else mini(int(view.size.y) - 4, 32)
	var center_x := view.position.x + view.size.x * (1.0 - SIDE_MARGIN_FRAC)
	var ground_y := _ground_y(view)
	var top := maxf(view.position.y, ground_y - icon_px)
	var icon := art.icon_or_placeholder("enemy_%s" % sim.enemy_id, sim.enemy_id, "gem")
	var rect := Rect2(Vector2(center_x - icon_px / 2.0, top), Vector2(icon_px, icon_px))
	draw_texture_rect(icon, rect, false)
	var max_hp := int(def["hp"])
	var bar_y := top - BAR_HEIGHT - 4
	var bar_rect := Rect2(Vector2(center_x - icon_px / 2.0, bar_y), Vector2(icon_px, BAR_HEIGHT))
	draw_rect(bar_rect, COLOR_HP_BAR_BG)
	var frac := clampf(float(sim.enemy_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * frac, BAR_HEIGHT)), COLOR_ENEMY_HP_BAR)
	if not settings.resident_mode:
		var font := ThemeDB.fallback_font
		var name_text := locale.text(str(def["name_key"]))
		draw_string(
			font, Vector2(center_x, bar_y - 6), name_text,
			HORIZONTAL_ALIGNMENT_CENTER, icon_px * 2, 14, COLOR_HUD_TEXT
		)


## Party stands on the left, clustered near the protagonist rather than
## spread across the view, facing the enemy on the right across the floor.
func _draw_party_row(view: Rect2) -> void:
	if settings.resident_mode or sim.minions.is_empty():
		return
	var count := sim.minions.size()
	var spacing := minf(PARTY_ICON_PX * 0.6, view.size.x / float(count + 1))
	var start_x := view.position.x + view.size.x * SIDE_MARGIN_FRAC
	var ground_y := _ground_y(view)
	var top := maxf(view.position.y, ground_y - PARTY_ICON_PX)
	var font := ThemeDB.fallback_font
	for slot_index in count:
		var unit: UDMinion = sim.minions[slot_index]
		var x := start_x + spacing * slot_index
		var art_variant := _minion_art_variant(slot_index)
		var art_key := art.minion_key(art_variant)
		var icon := art.icon_or_placeholder(art_key, "minion_%d" % slot_index, "rune")
		var rect := Rect2(Vector2(x - PARTY_ICON_PX / 2.0, top), Vector2(PARTY_ICON_PX, PARTY_ICON_PX))
		draw_texture_rect(icon, rect, false)
		var bar_w := PARTY_ICON_PX
		var hp_y := top - BAR_HEIGHT - 4
		draw_rect(Rect2(Vector2(x - bar_w / 2.0, hp_y), Vector2(bar_w, BAR_HEIGHT)), COLOR_HP_BAR_BG)
		var hp_frac := clampf(float(unit.hp) / float(maxi(1, sim.unit_max_hp(unit))), 0.0, 1.0)
		draw_rect(Rect2(Vector2(x - bar_w / 2.0, hp_y), Vector2(bar_w * hp_frac, BAR_HEIGHT)), COLOR_HP_BAR)
		draw_string(
			font, Vector2(x, hp_y - 6), "Lv.%d" % unit.level,
			HORIZONTAL_ALIGNMENT_CENTER, bar_w * 2, 13, COLOR_HUD_TEXT
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

	_fight_button = _make_button("", _on_fight_button)
	grid.add_child(_fight_button)
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


## Facility buttons: pressing the button unlocks the facility outright
## (one-time cost via buy_upgrade, max_level 1), then opens its screen.
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


func _refresh_fight_button() -> void:
	if _fight_button == null:
		return
	var at_gate := stage_db.is_boss_stage(sim.stage_index)
	_fight_button.disabled = not at_gate
	_fight_button.text = locale.text("UI_FIGHT_GATE") if at_gate else locale.text("UI_FIGHT_NONE")


func _refresh_button_texts() -> void:
	for facility_id: String in _facility_buttons:
		var button: Button = _facility_buttons[facility_id]
		button.text = locale.text(facility_db.get_good(facility_id)["name_key"])
	_refresh_fight_button()
	_height_button.text = "%dpx" % UD.WINDOW_HEIGHTS[settings.height_index]
	_collapse_button.text = locale.text("UI_COLLAPSE")
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	_shop_button.text = locale.text("UI_SHOP")
	_locale_button.text = _next_locale_code().to_upper()
	_quit_button.text = locale.text("UI_QUIT")
	_refresh_archive_button()


func _next_locale_code() -> String:
	var index := UD.SUPPORTED_LOCALES.find(settings.locale_code)
	return UD.SUPPORTED_LOCALES[(index + 1) % UD.SUPPORTED_LOCALES.size()]


## Strip = taskbar-look ambient view. Expanded = centered window for
## reading documents and giving orders. Clicking the strip expands.
func _apply_window_mode() -> void:
	_button_bar.visible = not settings.resident_mode
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
	else:
		UDResidentWindow.setup_expanded(get_window())
	queue_redraw()


func _expand() -> void:
	settings.resident_mode = false
	settings.save()
	_apply_window_mode()
	_refresh_button_texts()
	if sim.boss_active:
		_refresh_boss_panel()


func _format_offline_summary() -> String:
	var gold_gained := int(sim.inventory.get(UD.RES_GOLD, 0)) - _offline_gold_before
	var exp_gained := sim.exp_pool - _offline_exp_before
	return locale.text("UI_OFFLINE_EARNED") % [maxi(0, exp_gained), maxi(0, gold_gained)]


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


## --- Boss encounter (turn-based, manual only) -------------------------

func _on_fight_button() -> void:
	if sim.boss_active:
		_show_boss_panel()
		return
	if sim.start_boss_fight():
		_show_boss_panel()


func _build_boss_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -220
	panel.offset_bottom = 220
	panel.visible = false
	add_child(panel)
	_boss_panel = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	_boss_enemy_label = Label.new()
	_boss_enemy_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_boss_enemy_label)

	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.show_percentage = false
	_boss_hp_bar.custom_minimum_size = Vector2(0, 18)
	column.add_child(_boss_hp_bar)

	column.add_child(HSeparator.new())

	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	column.add_child(rows_box)
	rows_box.name = "rows"

	_boss_log = Label.new()
	_boss_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_boss_log)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	var resolve_button := Button.new()
	resolve_button.text = locale.text("UI_BOSS_RESOLVE") if locale != null else "Resolve"
	resolve_button.name = "resolve"
	resolve_button.pressed.connect(_on_boss_resolve_round)
	buttons.add_child(resolve_button)
	var flee_button := Button.new()
	flee_button.text = locale.text("UI_BOSS_FLEE") if locale != null else "Flee"
	flee_button.name = "flee"
	flee_button.pressed.connect(_on_boss_flee)
	buttons.add_child(flee_button)


func _show_boss_panel() -> void:
	if settings.resident_mode:
		_expand()
	_refresh_boss_panel()
	_boss_panel.visible = true
	queue_redraw()


func _hide_boss_panel() -> void:
	_boss_panel.visible = false
	queue_redraw()


func _refresh_boss_panel() -> void:
	if not sim.boss_active:
		return
	var stage := stage_db.stage_for_index(sim.stage_index)
	var boss := enemy_db.get_enemy(str(stage["boss_id"]))
	_boss_enemy_label.text = locale.text(str(boss["name_key"]))
	_boss_hp_bar.max_value = int(boss["hp"])
	_boss_hp_bar.value = sim.boss_hp

	var rows_box: VBoxContainer = _boss_panel.find_child("rows", true, false)
	for child in rows_box.get_children():
		child.queue_free()
	_boss_unit_rows.clear()
	for unit in sim.minions:
		if unit.hp <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rows_box.add_child(row)
		var name_label := Label.new()
		name_label.text = _unit_display_name(unit)
		name_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(name_label)
		var hp_label := Label.new()
		hp_label.text = "HP %d/%d  MP %d/%d" % [
			unit.hp, sim.unit_max_hp(unit), unit.mp, sim.unit_max_mp(unit),
		]
		hp_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(hp_label)
		var option := OptionButton.new()
		option.add_item(locale.text("UI_BOSS_ATTACK"), 0)
		option.set_item_metadata(0, "attack")
		var item_index := 1
		for skill_id in sim.unit_skills(unit):
			if not skill_db.has_skill(skill_id):
				continue
			var skill := skill_db.get_skill(skill_id)
			var enabled := unit.mp >= int(skill.get("mp_cost", 0))
			option.add_item(locale.text(str(skill["name_key"])), item_index)
			option.set_item_metadata(item_index, skill_id)
			option.set_item_disabled(item_index, not enabled)
			item_index += 1
		row.add_child(option)
		_boss_unit_rows[unit.id] = {"option": option, "hp_label": hp_label}


func _unit_display_name(unit: UDMinion) -> String:
	if unit.id == 0:
		return locale.text("APP_TITLE")
	var companion_index := unit.id - 1
	if companion_index >= 0 and companion_index < sim.companions.size():
		var companion_id: String = sim.companions[companion_index]
		if _companion_by_id.has(companion_id):
			return locale.text(_companion_by_id[companion_id]["name_key"])
	return "?"


func _on_boss_resolve_round() -> void:
	var actions: Array = []
	for unit_id: Variant in _boss_unit_rows.keys():
		var row: Dictionary = _boss_unit_rows[unit_id]
		var option: OptionButton = row["option"]
		var selected: Variant = option.get_selected_metadata()
		if selected == null:
			continue
		if str(selected) == "attack":
			actions.append({"unit_id": unit_id, "action": "attack"})
		else:
			actions.append({"unit_id": unit_id, "action": "skill", "skill_id": str(selected)})
	var result := sim.resolve_boss_round(actions)
	if result.get("won", false):
		_boss_log.text = locale.text("UI_BOSS_WON")
		_hide_boss_panel()
		_refresh_fight_button()
		queue_redraw()
		return
	if result.get("lost", false):
		_boss_log.text = locale.text("UI_BOSS_LOST")
		_hide_boss_panel()
		queue_redraw()
		return
	_boss_log.text = ""
	_refresh_boss_panel()


func _on_boss_flee() -> void:
	sim.flee_boss_fight()
	_hide_boss_panel()


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


## Two-level treasure shelf (same UX as the archive): the shelf shows
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
## Party roster: Lv/HP/MP per member, with a level-up button that
## spends the shared exp_pool banked from idle combat.

func _build_dorm_dialog() -> void:
	_dorm_dialog = UDCardDialog.create(locale.text("ROOM_DORM"), true)
	_dorm_dialog.card_selected.connect(_on_dorm_card_selected)
	_dorm_dialog.action_pressed.connect(_on_dorm_level_up)
	_dorm_dialog.set_background(art.texture("dialog_bg_dorm"))
	add_child(_dorm_dialog)


func _open_dorm() -> void:
	if settings.resident_mode:
		_expand()
	_populate_dorm("")
	_dorm_dialog.title = locale.text("ROOM_DORM")
	_dorm_dialog.popup_centered()


func _populate_dorm(keep_selection: String) -> void:
	_dorm_dialog.clear_cards()
	for slot_index in sim.minions.size():
		var unit: UDMinion = sim.minions[slot_index]
		var art_variant := _minion_art_variant(slot_index)
		var minion_id := "minion_%d" % slot_index
		var display_name := _unit_display_name(unit)
		_dorm_dialog.add_card(
			minion_id, display_name, "Lv.%d" % unit.level,
			art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune"), false
		)
	_dorm_dialog.set_progress("%s %d/%d   EXP %d" % [
		locale.text("UI_PARTY"), sim.minions.size(), UD.MINION_MAX, sim.exp_pool,
	])
	_dorm_dialog.set_action(locale.text("UI_LEVEL_UP"), true)
	var select_id := keep_selection
	if select_id == "" and sim.minions.size() > 0:
		select_id = "minion_0"
	if select_id != "":
		_dorm_dialog.select_card(select_id)
	else:
		_dorm_dialog.show_detail("", locale.text("FACILITY_DORM_DESC"), null)


func _on_dorm_card_selected(minion_id: String) -> void:
	var slot_index := int(minion_id.trim_prefix("minion_"))
	var unit: UDMinion = sim.minions[slot_index]
	var art_variant := _minion_art_variant(slot_index)
	var display_name := _unit_display_name(unit)
	var cost := UDSim.exp_cost_for_level(unit.level)
	var body := "%s\n\nLv.%d   HP %d/%d   MP %d/%d\n\n%s: %d / %d" % [
		locale.text("FACILITY_DORM_DESC"), unit.level, unit.hp, sim.unit_max_hp(unit),
		unit.mp, sim.unit_max_mp(unit), locale.text("UI_LEVEL_UP_COST"), sim.exp_pool, cost,
	]
	_dorm_dialog.show_detail(
		display_name, body,
		art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune")
	)
	_dorm_dialog.set_action(locale.text("UI_LEVEL_UP"), sim.exp_pool < cost)


func _on_dorm_level_up(minion_id: String) -> void:
	var slot_index := int(minion_id.trim_prefix("minion_"))
	var unit: UDMinion = sim.minions[slot_index]
	if sim.level_up_companion(unit.id):
		_populate_dorm(minion_id)
		_on_dorm_card_selected(minion_id)
		queue_redraw()


## --- Altar offerings -------------------------------------------------
## Coins (and at higher levels a treasure of the demanded rank) buy
## permanent-for-this-save attack (party_atk_bonus()).

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


## Two-level archive: the shelf shows one card per series (data/series/);
## opening a series lists its documents in number order, unfound ones
## blacked out as ?????.
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
