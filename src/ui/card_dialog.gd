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

const CARD_SIZE := Vector2(128, 108)
const CARD_ICON_PX: int = 36
const DETAIL_ICON_PX: int = 88
const GRID_COLUMNS: int = 4
const CHARACTER_SIZE: float = 120.0
const CHARACTER_BOTTOM_MARGIN: float = 18.0

var _progress_label: Label
var _back_button: Button
var _grid: GridContainer
var _background_rect: TextureRect
var _character_rect: TextureRect
var _detail_icon: TextureRect
var _detail_title: Label
var _detail_body: RichTextLabel
var _action_button: Button
var _cards: Dictionary = {}  # id -> Button
var _selected_id: String = ""
var _card_area: Control
var _action_requires_selection: bool = true
## Invisible click targets over a set_background() illustration (e.g. the
## guild's painted "アイテム交換" / "交換カウンター" signs), each a Rect2
## normalized to the background texture's own pixel size (0..1 on both
## axes) so they track STRETCH_KEEP_ASPECT_COVERED's crop-and-scale as
## the dialog resizes.
var _hotspots: Array[Dictionary] = []  # [{ "rect": Rect2, "button": Control }]


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
	_card_area = card_area

	_background_rect = TextureRect.new()
	_background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_rect.clip_contents = true
	_background_rect.visible = false
	_background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_rect.resized.connect(_layout_hotspots)
	card_area.add_child(_background_rect)

	_character_rect = TextureRect.new()
	_character_rect.anchor_left = 0.5
	_character_rect.anchor_right = 0.5
	_character_rect.offset_left = -CHARACTER_SIZE / 2.0
	_character_rect.offset_right = CHARACTER_SIZE / 2.0
	_character_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_rect.visible = false
	card_area.add_child(_character_rect)

	# Hotspots sit directly in card_area, siblings of (and added after, so
	# drawn/hit-tested above) this scroll container. When the grid it holds
	# is empty — the guild's landing page — an ordinary Control child added
	# before the scroll would still lose clicks to it: ScrollContainer's
	# default MOUSE_FILTER_STOP claims the whole card_area regardless of
	# whether the grid inside has any cards.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_area.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 22)
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
			if _selected_id != "" or not _action_requires_selection:
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


## Optional character portrait posed over the backdrop (e.g. the hero
## or a companion standing on the altar). `feet_y` is where the
## character's feet line up, as a fraction of the card area's height
## (0 = top, 1 = bottom); the sprite extends upward from that line.
## Whichever party member is being upgraded can be swapped in later by
## just calling this again with a different texture.
func set_character(tex: Texture2D, feet_y: float = 1.0) -> void:
	_character_rect.texture = tex
	_character_rect.visible = tex != null
	_character_rect.anchor_top = feet_y
	_character_rect.anchor_bottom = feet_y
	_character_rect.offset_top = -CHARACTER_SIZE - CHARACTER_BOTTOM_MARGIN
	_character_rect.offset_bottom = -CHARACTER_BOTTOM_MARGIN


## Drops the native OK button and window titlebar/close-X, for a dialog
## whose set_background() art bakes in its own title and close control
## (e.g. the shop's painted "閉じる" plaque) — two redundant, differently
## styled close affordances read as a mistake, not two options.
func hide_native_chrome() -> void:
	get_ok_button().visible = false
	borderless = true


## Shows the "back to series" button on nested pages (archive shelves).
func set_back(label: String, visible_now: bool) -> void:
	_back_button.text = "← " + label
	_back_button.visible = visible_now


func clear_cards() -> void:
	_selected_id = ""
	_cards.clear()
	for child in _grid.get_children():
		child.queue_free()


## Adds a fully transparent button over the background art at `rect_norm`
## (fractions of the texture's own size) so a spot painted into the scene
## — a sign, a counter — is clickable in place, instead of a parchment
## card floating over it. Cleared independently of clear_cards(); call
## clear_hotspots() before laying out a page that doesn't want any.
func add_hotspot(rect_norm: Rect2, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.self_modulate = Color(1, 1, 1, 0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(on_pressed)
	add_overlay(rect_norm, button)
	return button


## Positions any Control at `rect_norm` (fractions of the background
## texture's own pixel size) using the same cover-scale math as
## add_hotspot — e.g. a live Label masking a baked placeholder number in
## the art. Tracked and cleared the same way as button hotspots.
func add_overlay(rect_norm: Rect2, control: Control) -> void:
	_card_area.add_child(control)
	_hotspots.append({"rect": rect_norm, "button": control})
	_layout_hotspots()


func clear_hotspots() -> void:
	for h: Variant in _hotspots:
		((h as Dictionary)["button"] as Control).queue_free()
	_hotspots.clear()


## Re-derives each overlay's screen rect from the background's current
## cover-scale crop (same math STRETCH_KEEP_ASPECT_COVERED does
## internally, which TextureRect doesn't expose) whenever the dialog is
## resized, so they stay pinned to the art instead of drifting.
func _layout_hotspots() -> void:
	if _background_rect.texture == null or _hotspots.is_empty():
		return
	var tex_size := _background_rect.texture.get_size()
	var rect_size := _background_rect.size
	if rect_size.x <= 0.0 or rect_size.y <= 0.0 or tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale := maxf(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	var displayed := tex_size * scale
	var offset := (rect_size - displayed) / 2.0
	for h: Variant in _hotspots:
		var entry := h as Dictionary
		var r := entry["rect"] as Rect2
		var control := entry["button"] as Control
		control.position = offset + r.position * displayed
		control.size = r.size * displayed


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


## `requires_selection` false lets the action fire with no card selected —
## for pages with no grid at all (e.g. the shop's weapon-upgrade screen,
## which acts on "whatever's currently equipped" rather than a pick).
func set_action(label: String, disabled: bool, requires_selection: bool = true) -> void:
	_action_button.text = label
	_action_button.disabled = disabled
	_action_requires_selection = requires_selection


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
