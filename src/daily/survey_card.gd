class_name UDSurveyCard
extends RefCounted
## §5.4 share card: renders a retro survey-report styled Control that
## the UI captures into a PNG under user://cards/ and copies to the
## clipboard. The paper is tinted per anomaly (data/anomalies card_color)
## so regulars can tell at a glance which day a screenshot came from.

const CARD_SIZE := Vector2i(640, 360)
const CARDS_DIR: String = "user://cards"

const COLOR_PAPER := Color(0.13, 0.11, 0.09)
const COLOR_BORDER := Color(0.72, 0.6, 0.35)
const COLOR_TITLE := Color(0.9, 0.78, 0.5)
const COLOR_TEXT := Color(0.85, 0.8, 0.7)
const COLOR_FOOTER := Color(0.55, 0.5, 0.4)
const COLOR_STAMP := Color(0.75, 0.3, 0.25, 0.85)
## How strongly the anomaly color soaks into the paper.
const TINT_BLEND: float = 0.35
const STAMP_ROTATION: float = -0.12


static func save_path_for(date_key: String) -> String:
	return "%s/card_%s.png" % [CARDS_DIR, date_key]


## Paper color for the day: the base parchment lightly stained with the
## anomaly's card_color (empty string keeps the plain paper).
static func paper_color(card_color: String) -> Color:
	if card_color == "":
		return COLOR_PAPER
	return COLOR_PAPER.lerp(Color.from_string(card_color, COLOR_PAPER), TINT_BLEND)


## data keys: date_key, anomaly_name, depth, coins, minions, docs,
## docs_total, card_color, crystals, items, items_total, resets
static func build_card(data: Dictionary, locale: UDLocale) -> Control:
	var root := Panel.new()
	root.custom_minimum_size = Vector2(CARD_SIZE)
	root.size = Vector2(CARD_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = paper_color(str(data.get("card_color", "")))
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
	var stats := "▼ %d    $ %d    ⛏ %d" % [
		int(data.get("depth", 0)), int(data.get("coins", 0)),
		int(data.get("minions", 0)),
	]
	if int(data.get("crystals", 0)) > 0 or int(data.get("resets", 0)) > 0:
		stats += "    ◆ %d" % int(data.get("crystals", 0))
	box.add_child(_label(stats, 22, COLOR_TEXT))
	var progress := "%s %d/%d" % [
		locale.text("UI_ARCHIVE"),
		int(data.get("docs", 0)), int(data.get("docs_total", 0)),
	]
	if int(data.get("items_total", 0)) > 0:
		progress += "    %s %d/%d" % [
			locale.text("UI_TREASURES"),
			int(data.get("items", 0)), int(data.get("items_total", 0)),
		]
	box.add_child(_label(progress, 18, COLOR_TEXT))
	var footer := _label("UNDERDESK", 12, COLOR_FOOTER)
	footer.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	box.add_child(footer)

	root.add_child(_stamp(locale.text("CARD_STAMP")))
	return root


## A slightly crooked inspection stamp in the top-right corner: the small
## imperfection that sells the retro paperwork look.
static func _stamp(text: String) -> Control:
	var stamp := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = COLOR_STAMP
	style.set_border_width_all(2)
	style.set_content_margin_all(6)
	stamp.add_theme_stylebox_override("panel", style)
	stamp.position = Vector2(CARD_SIZE.x - 150, 26)
	stamp.rotation = STAMP_ROTATION
	stamp.add_child(_label(text, 18, COLOR_STAMP))
	return stamp


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
