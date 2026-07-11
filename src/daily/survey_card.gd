class_name UDSurveyCard
extends RefCounted
## §5.4 share card: renders a retro survey-report styled Control that
## the UI captures into a PNG under user://cards/.

const CARD_SIZE := Vector2i(640, 360)
const CARDS_DIR: String = "user://cards"

const COLOR_PAPER := Color(0.13, 0.11, 0.09)
const COLOR_BORDER := Color(0.72, 0.6, 0.35)
const COLOR_TITLE := Color(0.9, 0.78, 0.5)
const COLOR_TEXT := Color(0.85, 0.8, 0.7)
const COLOR_FOOTER := Color(0.55, 0.5, 0.4)


static func save_path_for(date_key: String) -> String:
	return "%s/card_%s.png" % [CARDS_DIR, date_key]


## data keys: date_key, anomaly_name, depth, coins, minions, docs, docs_total
static func build_card(data: Dictionary, locale: UDLocale) -> Control:
	var root := Panel.new()
	root.custom_minimum_size = Vector2(CARD_SIZE)
	root.size = Vector2(CARD_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PAPER
	style.border_color = COLOR_BORDER
	style.set_border_width_all(3)
	style.set_content_margin_all(24)
	root.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 24
	box.offset_top = 18
	box.offset_right = -24
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)

	box.add_child(_label(locale.text("CARD_TITLE"), 28, COLOR_TITLE))
	box.add_child(_label(str(data.get("date_key", "")), 14, COLOR_FOOTER))
	box.add_child(HSeparator.new())
	box.add_child(_label(
		"%s: %s" % [locale.text("UI_DAILY"), str(data.get("anomaly_name", "-"))],
		18, COLOR_TEXT
	))
	box.add_child(_label(
		"▼ %d    $ %d    ⛏ %d" % [
			int(data.get("depth", 0)), int(data.get("coins", 0)),
			int(data.get("minions", 0)),
		],
		22, COLOR_TEXT
	))
	box.add_child(_label(
		"%s %d/%d" % [
			locale.text("UI_ARCHIVE"),
			int(data.get("docs", 0)), int(data.get("docs_total", 0)),
		],
		18, COLOR_TEXT
	))
	var footer := _label("UNDERDESK", 12, COLOR_FOOTER)
	footer.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	box.add_child(footer)
	return root


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
