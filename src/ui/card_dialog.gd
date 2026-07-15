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
var _detail_panel: Control
var _root_panel: PanelContainer
var _hotspot_layer: Control
var _header: HBoxContainer
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
	# Kill AcceptDialog's own gray theme panel: it shows through the content
	# margin around `root` as a gray border, which reads as "leftover UI
	# behind the art" on a fully illustrated dialog. A dark flat panel
	# blends into the art's dark edges instead.
	add_theme_stylebox_override("panel", _flat(COLOR_CABINET, COLOR_CABINET, 0, 0))

	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(920, 500)
	root.add_theme_stylebox_override("panel", _flat(COLOR_CABINET, COLOR_BORDER_DIM, 2, 10))
	add_child(root)
	_root_panel = root

	# Background art fills the WHOLE dialog (child 0 of root, behind the
	# column), not just the card body — otherwise the header strip and
	# margins above/around the cards show the panel behind the art. Framed
	# dialogs keep their cabinet border because root's content margin insets
	# this rect; frameless ones (set_frame_visible false) let it reach the
	# edges. Hotspots live in a matching full-rect layer on top (child 2) so
	# their texture-normalized rects map 1:1 onto this same rect.
	_background_rect = TextureRect.new()
	_background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_rect.clip_contents = true
	_background_rect.visible = false
	_background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_rect.resized.connect(_layout_hotspots)
	root.add_child(_background_rect)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_header = header

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
	_detail_panel = detail

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

	# Hotspot layer: a full-rect Control over everything (last child of
	# root, same rect as _background_rect), holding the invisible click
	# targets. It must be MOUSE_FILTER_IGNORE, not PASS: PASS forwards the
	# event to this layer's PARENT, never to the sibling column drawn
	# behind it, so a full-rect PASS layer on top silently swallows every
	# click meant for the cards / close button / action button in the
	# column. IGNORE makes the layer itself transparent to the mouse while
	# its own STOP button children (hotspots) still receive clicks — so
	# everything behind stays clickable. It shares _background_rect's rect
	# exactly, so texture-normalized hotspot rects map straight onto the
	# art wherever the cover-crop places it.
	_hotspot_layer = Control.new()
	_hotspot_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hotspot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hotspot_layer)


func set_progress(text: String) -> void:
	_progress_label.text = text


## Optional illustrated backdrop behind the card grid (e.g. the archive's
## library-desk scene). Pass null to fall back to the plain cabinet panel.
func set_background(tex: Texture2D) -> void:
	_background_rect.texture = tex
	_background_rect.visible = tex != null


## Hides the right-side detail panel so card_area (and its background
## art) gets the full dialog width — for a hotspot-only page like the
## shop's landing screen, where the panel would otherwise sit empty and
## the art gets cropped tighter than it needs to (STRETCH_KEEP_ASPECT_
## COVERED crops to whatever's left after the panel's width). HBoxContainer
## skips invisible children's space, so this alone widens card_area.
func set_detail_visible(visible_now: bool) -> void:
	_detail_panel.visible = visible_now


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


## Drops the dark-cabinet border/margin the root panel normally draws
## around every card dialog — for a dialog whose set_background() art
## already reads as a complete scene (the shop), that extra frame just
## shows up as an unrelated outer edge instead of matching the art.
func set_frame_visible(visible_now: bool) -> void:
	if visible_now:
		_root_panel.add_theme_stylebox_override("panel", _flat(COLOR_CABINET, COLOR_BORDER_DIM, 2, 10))
	else:
		_root_panel.add_theme_stylebox_override("panel", _flat(COLOR_CABINET, COLOR_CABINET, 0, 0))


## Full art-driven chrome for a dialog whose background fills the frame:
## drops the OS titlebar and cabinet frame, then puts a title and a close
## button into the header row over the art — the code equivalent of the
## shop art's baked-in title/閉じる plaque, for the other dialogs whose
## illustrations don't have them drawn in. Header-based (not free-floating)
## so the container guarantees they're laid out and on-screen: a
## hand-anchored top-right button kept collapsing to zero width.
func enable_art_chrome(title_text: String, close_label: String) -> void:
	hide_native_chrome()
	set_frame_visible(false)

	# A left spacer centers the title between the back button and the
	# progress/close cluster; the title itself is natural-width (an EXPAND
	# title was starving the close button of layout width, dropping it).
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	_header.move_child(spacer, 1)

	var title_lbl := Label.new()
	title_lbl.text = title_text
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	_header.add_child(title_lbl)
	_header.move_child(title_lbl, 2)  # back, spacer, title, [progress(EXPAND)], close

	var close_btn := Button.new()
	close_btn.text = "✕ " + close_label
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	close_btn.add_theme_stylebox_override("normal", _flat(COLOR_CABINET, COLOR_BORDER, 2, 8))
	close_btn.add_theme_stylebox_override("hover", _flat(COLOR_PAPER_HOVER, COLOR_BORDER, 2, 8))
	close_btn.add_theme_stylebox_override("pressed", _flat(COLOR_PAPER_SELECTED, COLOR_BORDER, 2, 8))
	close_btn.custom_minimum_size = Vector2(96, 34)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(hide)
	_header.add_child(close_btn)  # stays last: the header's right end


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
	_hotspot_layer.add_child(control)
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
