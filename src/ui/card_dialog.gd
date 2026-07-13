class_name UDCardDialog
extends AcceptDialog
## Shared card-catalogue dialog (§6, user reference shots 2026-07-12):
## a dark cabinet holding a grid of parchment cards on the left and a
## large detail panel on the right — the shop / treasure / archive
## screens all read as "a real collection", not a text list. Undiscovered
## entries stay as locked "?????" cards so the shelf shows its true size.

signal card_selected(id: String)
signal action_pressed(id: String)
signal back_pressed

## Palette shared with the survey card: aged paper in a dark cabinet.
const COLOR_CABINET := Color(0.075, 0.065, 0.055)
const COLOR_PAPER := Color(0.16, 0.135, 0.105)
const COLOR_PAPER_HOVER := Color(0.21, 0.18, 0.14)
const COLOR_PAPER_SELECTED := Color(0.24, 0.2, 0.14)
const COLOR_LOCKED := Color(0.095, 0.085, 0.075)
const COLOR_BORDER := Color(0.62, 0.5, 0.28)
const COLOR_BORDER_DIM := Color(0.28, 0.24, 0.18)
const COLOR_TITLE := Color(0.9, 0.78, 0.5)
const COLOR_TEXT := Color(0.85, 0.8, 0.7)
const COLOR_MUTED := Color(0.5, 0.45, 0.38)

const CARD_SIZE := Vector2(150, 128)
const CARD_ICON_PX: int = 44
const DETAIL_ICON_PX: int = 88
const GRID_COLUMNS: int = 4

var _progress_label: Label
var _back_button: Button
var _grid: GridContainer
var _background_rect: TextureRect
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_body: RichTextLabel
var _action_button: Button
var _cards: Dictionary = {}  # id -> Button
var _selected_id: String = ""


static func create(dialog_title: String, with_action: bool) -> UDCardDialog:
	var dialog := UDCardDialog.new()
	dialog.title = dialog_title
	dialog.min_size = Vector2i(960, 560)
	dialog._build(with_action)
	return dialog


func _build(with_action: bool) -> void:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(920, 500)
	root.add_theme_stylebox_override("panel", _flat(COLOR_CABINET, COLOR_BORDER_DIM, 2, 10))
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)

	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(90, 34)
	_back_button.add_theme_font_size_override("font_size", 14)
	_back_button.visible = false
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(_back_button)

	_progress_label = Label.new()
	_progress_label.add_theme_font_size_override("font_size", 15)
	_progress_label.add_theme_color_override("font_color", COLOR_TITLE)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_progress_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var card_area := Control.new()
	card_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(card_area)

	_background_rect = TextureRect.new()
	_background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_background_rect.visible = false
	card_area.add_child(_background_rect)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_area.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var detail := PanelContainer.new()
	detail.custom_minimum_size = Vector2(280, 0)
	detail.add_theme_stylebox_override("panel", _flat(COLOR_PAPER, COLOR_BORDER, 2, 14))
	body.add_child(detail)

	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 10)
	detail.add_child(detail_box)

	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(DETAIL_ICON_PX, DETAIL_ICON_PX)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail_box.add_child(_detail_icon)

	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.add_theme_color_override("font_color", COLOR_TITLE)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(_detail_title)

	detail_box.add_child(HSeparator.new())

	_detail_body = RichTextLabel.new()
	_detail_body.bbcode_enabled = true
	_detail_body.fit_content = false
	_detail_body.add_theme_font_size_override("normal_font_size", 16)
	_detail_body.add_theme_color_override("default_color", COLOR_TEXT)
	_detail_body.add_theme_constant_override("line_separation", 5)
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(_detail_body)

	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(0, 42)
	_action_button.add_theme_font_size_override("font_size", 16)
	_action_button.visible = with_action
	_action_button.pressed.connect(
		func() -> void:
			if _selected_id != "":
				action_pressed.emit(_selected_id)
	)
	detail_box.add_child(_action_button)


func set_progress(text: String) -> void:
	_progress_label.text = text


## Optional illustrated backdrop behind the card grid (e.g. the archive's
## library-desk scene). Pass null to fall back to the plain cabinet panel.
func set_background(tex: Texture2D) -> void:
	_background_rect.texture = tex
	_background_rect.visible = tex != null


## Shows the "back to series" button on nested pages (archive shelves).
func set_back(label: String, visible_now: bool) -> void:
	_back_button.text = "← " + label
	_back_button.visible = visible_now


func clear_cards() -> void:
	_selected_id = ""
	_cards.clear()
	for child in _grid.get_children():
		child.queue_free()


## A parchment card. Locked cards keep their slot on the shelf but show
## only "?????" and a lock, exactly like the reference catalogue.
func add_card(
	id: String, title_text: String, subtitle: String,
	icon: Texture2D, locked: bool
) -> void:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.disabled = locked
	var base := _flat(COLOR_LOCKED if locked else COLOR_PAPER,
		COLOR_BORDER_DIM, 2, 8)
	card.add_theme_stylebox_override("normal", base)
	card.add_theme_stylebox_override("disabled", base)
	card.add_theme_stylebox_override("hover", _flat(COLOR_PAPER_HOVER, COLOR_BORDER, 2, 8))
	card.add_theme_stylebox_override("pressed", _flat(COLOR_PAPER_SELECTED, COLOR_BORDER, 2, 8))
	card.add_theme_stylebox_override("focus", _flat(COLOR_PAPER_SELECTED, COLOR_TITLE, 2, 8))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(CARD_ICON_PX, CARD_ICON_PX)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	image.texture = icon
	# Locked entries read as blacked-out silhouettes on a dark slot.
	image.modulate = Color(0.16, 0.14, 0.13) if locked else Color.WHITE
	box.add_child(image)

	var name_label := Label.new()
	name_label.text = "?????" if locked else title_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override(
		"font_color", COLOR_MUTED if locked else COLOR_TEXT
	)
	box.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = "🔒" if locked else subtitle
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override(
		"font_color", COLOR_MUTED if locked else COLOR_TITLE
	)
	sub_label.visible = locked or subtitle != ""
	box.add_child(sub_label)

	if not locked:
		card.pressed.connect(
			func() -> void:
				_selected_id = id
				card_selected.emit(id)
		)
	_grid.add_child(card)
	_cards[id] = card


func select_card(id: String) -> void:
	if not _cards.has(id):
		return
	_selected_id = id
	(_cards[id] as Button).grab_focus()
	card_selected.emit(id)


func selected_id() -> String:
	return _selected_id


func show_detail(title_text: String, body_bbcode: String, icon: Texture2D) -> void:
	_detail_title.text = title_text
	_detail_body.text = body_bbcode
	_detail_icon.texture = icon
	_detail_icon.visible = icon != null


func set_action(label: String, disabled: bool) -> void:
	_action_button.text = label
	_action_button.disabled = disabled


func has_cards() -> bool:
	return not _cards.is_empty()


func first_unlocked_id() -> String:
	for id: Variant in _cards.keys():
		if not (_cards[id] as Button).disabled:
			return str(id)
	return ""


static func _flat(
	bg: Color, border: Color, border_px: int, margin_px: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_px)
	style.set_content_margin_all(margin_px)
	style.set_corner_radius_all(3)
	return style
