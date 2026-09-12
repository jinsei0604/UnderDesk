extends RefCounted
## Shared adopted UI frames and menu layout. Display only.

const INK := Color("111925")
const PANEL := Color("16202c")
const EDGE := Color("64583f")
const GOLD := Color("b99b60")
const IVORY := Color("e9dfca")
const MUTED := Color("aaa495")
const DIM := Color("626760")
const DANGER := Color("a96658")
var style_cache: Dictionary = {}
var theme_cache: Dictionary = {}

func recolor(c: Color) -> Color:
	var colors := {
		"14171d": "101720", "1d2129": "16202c", "383e49": "514a3d",
		"e7e9ed": "e9dfca", "989faa": "aaa495", "60656f": "626760",
		"ba652f": "b99b60", "cd763e": "d1b780", "984f23": "8b754d",
		"252932": "1b2835", "2e3340": "273849", "1b1e25": "101923",
		"191c22": "151c23", "2f343e": "17212b", "3e444f": "273849",
		"252931": "111925", "14161b": "0b121a", "161c27": "16202c",
		"3a4351": "514a3d", "0b0e14": "0b121a", "e9edf3": "e9dfca",
		"93a0b1": "aaa495", "5a6270": "626760", "8b98aa": "a88c59",
		"bac6d6": "d1b780", "454e5c": "64583f", "1b2230": "1b2835",
		"232c3d": "273849", "12161f": "101923", "12151b": "151c23",
		"1d2532": "273849", "0e131a": "101720", "202b3d": "253348",
		"293650": "30435a", "151c29": "111925", "0f263e": "111925"
	}
	var result := Color(str(colors.get(c.to_html(false), c.to_html(false))))
	result.a = c.a
	return result

func frame(fill: Color, edge: Color, padding: Vector4 = Vector4(16, 8, 16, 8), thin := false) -> StyleBoxTexture:
	var key := str([fill, edge, padding, thin])
	if style_cache.has(key): return style_cache[key]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var depth := Color("090e14")
	if thin:
		img.fill(edge)
		img.fill_rect(Rect2i(1, 1, 14, 14), fill)
	else:
		img.fill_rect(Rect2i(2, 0, 12, 16), depth)
		img.fill_rect(Rect2i(0, 2, 16, 12), depth)
		img.fill_rect(Rect2i(2, 1, 12, 13), edge)
		img.fill_rect(Rect2i(1, 2, 14, 12), edge)
		img.fill_rect(Rect2i(2, 3, 12, 11), fill)
		img.fill_rect(Rect2i(3, 2, 10, 12), fill)
		img.fill_rect(Rect2i(3, 3, 10, 1), Color(fill).lightened(0.05))
		img.fill_rect(Rect2i(3, 13, 10, 1), depth)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	for side in range(4):
		s.set_texture_margin(side, 1 if thin else 4)
		s.set_content_margin(side, padding[side])
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style_cache[key] = s
	return s

func convert_style(original: StyleBox) -> StyleBox:
	if not original is StyleBoxFlat: return original
	var old: StyleBoxFlat = original
	if old.bg_color.a == 0.0 and old.border_color.a == 0.0: return old
	if old.bg_color.a == 0.0 and old.get_border_width(SIDE_LEFT) == 0: return old
	var pad := Vector4(old.get_content_margin(SIDE_LEFT), old.get_content_margin(SIDE_TOP), old.get_content_margin(SIDE_RIGHT), old.get_content_margin(SIDE_BOTTOM))
	var fill := recolor(old.bg_color)
	var edge := recolor(old.border_color)
	if old.get_border_width(SIDE_LEFT) == 0: edge = fill.darkened(0.22)
	var thin := pad.y < 4 or not old.draw_center
	var result := frame(fill, edge, pad, thin).duplicate() as StyleBoxTexture
	result.draw_center = old.draw_center
	return result

func menu_frame(fill: Color, edge := GOLD, padding := Vector4(24,16,24,16)) -> StyleBoxTexture:
	# 32-pixel nine-slice with two-pixel steps; only large menu choices use this rim.
	var img := Image.create(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in range(32):
		for x in range(32):
			var d := mini(mini(x,31-x),mini(y,31-y))
			var corner := mini(x,31-x) + mini(y,31-y)
			if corner < 6: continue
			var c := fill
			if d < 2 or corner < 8: c = Color("090e14")
			elif d < 4 or corner < 10: c = edge.darkened(0.3)
			elif d == 5: c = Color("3b4040")
			img.set_pixel(x,y,c)
	for xy in [Vector2i(4,4),Vector2i(26,4),Vector2i(4,26),Vector2i(26,26)]:
		img.fill_rect(Rect2i(xy,Vector2i(2,2)),edge)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	for side in range(4):
		s.set_texture_margin(side,10)
		s.set_content_margin(side,padding[side])
	return s

func menu_button(b: Button, primary := false) -> void:
	button_style(b,primary)
	for state in ["normal","hover","pressed","hover_pressed"]:
		b.add_theme_stylebox_override(state,menu_frame(Color("253348") if state in ["hover","pressed","hover_pressed"] else INK, IVORY if state == "hover" else GOLD))

func convert_theme(original: Theme) -> Theme:
	var key := original.get_instance_id()
	if theme_cache.has(key): return theme_cache[key]
	var result := original.duplicate() as Theme
	for type in result.get_type_list():
		for item in result.get_stylebox_list(type):
			result.set_stylebox(item, type, convert_style(result.get_stylebox(item, type)))
		for item in result.get_color_list(type):
			result.set_color(item, type, recolor(result.get_color(item, type)))
	for type in ["CheckBox", "CheckButton"]:
		for state in ["checked", "checked_disabled", "on", "on_disabled"]: result.set_icon(state, type, icon("check", GOLD))
		for state in ["unchecked", "unchecked_disabled", "off", "off_disabled"]: result.set_icon(state, type, icon("empty", DIM))
	result.set_icon("arrow", "OptionButton", icon("down", MUTED))
	for type in ["HScrollBar", "VScrollBar"]:
		result.set_stylebox("scroll", type, frame(Color("0b121a"), Color("28313a"), Vector4.ZERO, true))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, frame(EDGE, GOLD if state != "grabber" else EDGE, Vector4(3, 3, 3, 3), true))
	result.set_icon("grabber", "HSlider", icon("slider", GOLD))
	result.set_icon("grabber_highlight", "HSlider", icon("slider", IVORY))
	theme_cache[key] = result
	return result

func icon(kind: String, color := GOLD) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var pixels: Array = []
	match kind:
		"right": pixels = [[4,2],[4,3],[5,3],[4,4],[5,4],[6,4],[4,5],[5,5],[4,6]]
		"left": pixels = [[4,2],[4,3],[3,3],[4,4],[3,4],[2,4],[4,5],[3,5],[4,6]]
		"down": pixels = [[1,2],[2,2],[3,2],[4,2],[5,2],[2,3],[3,3],[4,3],[3,4]]
		"check": pixels = [[1,3],[2,4],[3,3],[4,2],[5,1]]
		"slider": pixels = [[2,0],[3,0],[4,0],[2,1],[4,1],[2,2],[4,2],[2,3],[4,3],[2,4],[4,4],[2,5],[4,5],[2,6],[3,6],[4,6]]
		"empty": pixels = [[1,1],[2,1],[3,1],[4,1],[5,1],[1,2],[5,2],[1,3],[5,3],[1,4],[5,4],[1,5],[2,5],[3,5],[4,5],[5,5]]
	for p in pixels: img.fill_rect(Rect2i(p[0]*2, p[1]*2, 2, 2), color)
	return ImageTexture.create_from_image(img)

func button_style(b: Button, primary := false, destructive := false) -> void:
	var rim := DANGER if destructive else (GOLD if primary else EDGE)
	b.add_theme_stylebox_override("normal", frame(Color("253348") if primary else PANEL, rim))
	b.add_theme_stylebox_override("hover", frame(Color("273849"), DANGER if destructive else GOLD))
	b.add_theme_stylebox_override("pressed", frame(INK, GOLD))
	b.add_theme_stylebox_override("hover_pressed", frame(INK, GOLD))
	b.add_theme_stylebox_override("disabled", frame(Color("151c23"), Color("383c3c")))
	var focus := frame(Color.TRANSPARENT, GOLD, Vector4(16,8,16,8), true).duplicate() as StyleBoxTexture
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, Color("deb2a4") if destructive else IVORY)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func walk(node: Node) -> void:
	if node is Control:
		var c: Control = node
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if c.theme != null and not c.has_meta("world_theme"):
			c.theme = convert_theme(c.theme)
			c.set_meta("world_theme", true)
		if not c.has_meta("world_styles"):
			for prop in c.get_property_list():
				var path := str(prop.name)
				if path.begins_with("theme_override_styles/") and c.get(path) is StyleBox:
					c.set(path, convert_style(c.get(path)))
				if path.begins_with("theme_override_colors/") and c.get(path) is Color:
					c.set(path, recolor(c.get(path)))
			c.set_meta("world_styles", true)
		if c is ColorRect:
			c.color = Color("101720") if str(c.name) == "RootBackground" else recolor(c.color)
		if c is Label and c.text == "▶" and not c.has_meta("world_cursor"):
			c.text = " "
			c.custom_minimum_size.x = 14
			var arrow := TextureRect.new()
			arrow.texture = icon("right")
			arrow.position = Vector2(0,2)
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(arrow)
			c.set_meta("world_cursor",true)
		if c is Button and not c.has_meta("world_semantic"):
			var b: Button = c
			var key := str(b.name)
			if key in ["SkillListBackButton","TargetPickerBackButton"]:
				b.text = tr("戻る")
				b.icon = icon("left")
				b.custom_minimum_size = Vector2(150,44)
				b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				b.add_theme_font_size_override("font_size",16)
				button_style(b)
				b.get_parent().move_child(b,b.get_parent().get_child_count()-1)
			if key.begins_with("Remove") or key.begins_with("Delete") or "Discard" in key:
				button_style(b, false, true)
			elif key.begins_with("Confirm") or key.begins_with("Save"):
				button_style(b, true)
			if b.toggle_mode and b.button_pressed:
				b.add_theme_stylebox_override("pressed", frame(Color("253348"), GOLD))
			c.set_meta("world_semantic", true)
		if c is HBoxContainer: order_confirmation(c)
	for child in node.get_children(): walk(child)

func order_confirmation(row: HBoxContainer) -> void:
	if row.has_meta("world_ordered"): return
	var yes: Button = null
	var cancel: Button = null
	for child in row.get_children():
		if child is Button:
			if str(child.name).begins_with("Confirm") or str(child.name) == "ExitConfirmSaveButton": yes = child
			if "Cancel" in str(child.name): cancel = child
	if yes != null and cancel != null:
		row.move_child(cancel, row.get_child_count()-1)
		row.move_child(yes, row.get_child_count()-1)
		row.alignment = BoxContainer.ALIGNMENT_END
		row.set_meta("world_ordered", true)

func label(parent: Control, text: String, rect: Rect2, size := 16, color := IVORY, centered := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if centered: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func panel(parent: Control, rect: Rect2, menu := false) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", menu_frame(INK) if menu else frame(INK, EDGE, Vector4.ZERO))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

func nav(parent: Control, text: String, rect: Rect2, callback: Callable, name: String, forward := false) -> Button:
	var b := Button.new()
	b.name = name
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.custom_minimum_size = rect.size
	b.add_theme_font_size_override("font_size", 16)
	button_style(b, forward)
	b.icon = icon("right" if forward else "left")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT if forward else HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func entry_layout(entry: RBMCreatorEntry) -> void:
	if entry._top_panel.has_meta("world_layout"): return
	entry._top_panel.set_meta("world_layout", true)
	for key in ["NewBossButton", "EditSavedBossButton"]:
		var b: Button = entry._top_panel.find_child(key, true, false)
		if b:
			for child in b.get_children():
				if child is Control: child.hide()
			menu_button(b, key == "NewBossButton")
			b.text = tr("新しいボス戦を作る") if key == "NewBossButton" else tr("保存したボス戦を編集")
			b.add_theme_font_size_override("font_size", 24)
			b.icon = icon("right")
			b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# ボタンのtext内容ではなく、安定したノード名(BackToRootButton)で検索
	# する——言語切替でtextが変わっても(戻る/Back)見失わないようにする。
	var back: Button = entry._top_panel.find_child("BackToRootButton", true, false) as Button
	if back:
		for child in back.get_children():
			if child is Control: child.hide()
		button_style(back)
		back.text = tr("戻る")
		back.icon = icon("left")
		back.reparent(entry._top_panel)
		back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		back.position = Vector2(56, 636)
		back.size = Vector2(150, 44)
		back.custom_minimum_size = Vector2(150, 44)

func method_layout(entry: RBMCreatorEntry) -> void:
	var base: Control = entry._mode_choice_panel
	if base.has_meta("world_layout"): return
	base.set_meta("world_layout", true)
	var hint := tr("作成開始後はモードを変更できません")
	# Preserve background and referenced asset files. Remove only this screen's character node.
	for child in base.get_children():
		if str(child.name) != "Background":
			base.remove_child(child)
			child.queue_free()
	entry._guide_character = null
	panel(base, Rect2(240, 64, 800, 128), true).name = "MethodHeadingPanel"
	label(base, tr("ボスを作る方法を選択"), Rect2(260, 80, 760, 48), 32, IVORY, true)
	label(base, hint, Rect2(260, 139, 760, 26), 15, MUTED, true).name = "ModeChoiceHintLabel"
	for i in range(2):
		var b := Button.new()
		b.name = "ChooseSimpleModeButton" if i == 0 else "ChooseAdvancedModeButton"
		b.position = Vector2(176 + i * 480, 248)
		b.size = Vector2(448, 244)
		menu_button(b)
		base.add_child(b)
		b.pressed.connect(entry._on_choose_simple_mode_pressed if i == 0 else entry._on_choose_advanced_mode_pressed)
		label(b, "SIMPLE" if i == 0 else "HARDCORE", Rect2(32, 24, 384, 46), 32, IVORY).name = "CategoryLabel"
		label(b, tr("シンプルで作る") if i == 0 else tr("ハードコアで作る"), Rect2(32, 72, 384, 30), 19, GOLD).name = "TitleLabel"
		label(b, tr("基本的な設定だけで\nすぐにボス戦を作成できます。") if i == 0 else tr("行動条件などを細かく設定して\nボス戦を作り込めます。"), Rect2(32, 119, 384, 61), 17, IVORY).name = "DescriptionLabel"
		label(b, tr("この方法で作成を始める"), Rect2(32, 199, 350, 24), 15, MUTED)
		var arrow := TextureRect.new()
		arrow.texture = icon("right")
		arrow.position = Vector2(394, 205)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(arrow)
	nav(base, tr("戻る"), Rect2(56,636,150,44), entry._on_mode_choice_back_pressed, "ModeChoiceBackButton")

func creator_layout(main: RBMCreatorMain) -> void:
	if not main.has_meta("world_layout"):
		main.set_meta("world_layout", true)
		var column: VBoxContainer = main._header.get_parent()
		column.offset_left = 24
		column.offset_right = -24
		column.offset_top = 18
		column.offset_bottom = -24
		main._header.custom_minimum_size.y = 52
		var progress := ProgressStrip.new()
		progress.name = "WorldProgressStrip"
		progress.creator = main
		main._header.add_child(progress)
		progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var exit: Button = main.find_child("ExitCreatorButton", true, false)
		var exit_row := exit.get_parent() as Control
		exit.reparent(main._nav_row)
		exit_row.hide()
		exit.text = tr("作成を終了")
		button_style(exit)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main._nav_row.add_child(spacer)
		main._nav_row.move_child(main._back_button, 0)
		main._nav_row.move_child(exit, 1)
		main._nav_row.move_child(spacer, 2)
		main._nav_row.move_child(main._next_button, main._nav_row.get_child_count()-1)
		main._nav_row.add_theme_constant_override("separation", 12)
		main._back_button.text = tr("戻る")
		main._back_button.icon = icon("left")
		main._back_button.custom_minimum_size = Vector2(150, 44)
		main._next_button.text = tr("次へ")
		main._next_button.icon = icon("right")
		main._next_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		main._next_button.custom_minimum_size = Vector2(150, 44)
		button_style(main._back_button)
		button_style(main._next_button, true)
		# The existing top STEP label remains the sole progress count.
		# Keep left step navigation and right live profile, as in the adopted layout.
		center_exit_dialog(main)
		var summary: Control = main._step_views[4]
		var summary_back: Button = summary.find_child("BackButton",true,false)
		summary_back.text = tr("戻る")
		summary_back.icon = icon("left")
		summary_back.custom_minimum_size = Vector2(150,44)
		summary_back.add_theme_font_size_override("font_size",16)
		button_style(summary_back)
		var summary_back_to_list: Button = summary.find_child("BackToCreatorListButton",true,false)
		summary_back_to_list.icon = icon("left")
		summary_back_to_list.custom_minimum_size = Vector2(150,44)
		summary_back_to_list.add_theme_font_size_override("font_size",16)
		button_style(summary_back_to_list)
		for key in ["SaveButton","PublishOnlineButton"]:
			var b: Button = summary.find_child(key,true,false)
			b.custom_minimum_size = Vector2(120,44)
			button_style(b,true)
		# Reserve a visible gap above the global footer while retaining the existing scroll.
		main._nav_row.add_theme_constant_override("separation",12)
		var party_column: VBoxContainer = main._step_views[3].get_child(0)
		party_column.offset_top = 16
		party_column.add_theme_constant_override("separation",8)
	# Refresh rebuilds some controls. Common conversion is applied after each refresh.
	main._header.get_node("WorldProgressStrip").queue_redraw()
	if main.current_step == 5: summary_layout(main._step_views[4])

func summary_layout(summary: RBMCreatorStep7Summary) -> void:
	var content: VBoxContainer = summary._content
	if content.find_child("WorldSummaryColumns",true,false) != null: return
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parts := {}
	for c in content.get_children():
		if c is HSeparator:
			content.remove_child(c)
			c.queue_free()
		else: parts[str(c.name)] = c
	var columns := HBoxContainer.new()
	columns.name = "WorldSummaryColumns"
	columns.add_theme_constant_override("separation",24)
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360
	left.add_theme_constant_override("separation",22)
	columns.add_child(left)
	for key in ["CreationContentSection","TestBattleSection","ClearCheckSection"]:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel",frame(PANEL,EDGE,Vector4(16,16,16,16)))
		left.add_child(box)
		parts[key].reparent(box)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel",frame(PANEL,EDGE,Vector4(20,16,20,16)))
	columns.add_child(right)
	var settings: Control = parts["ChallengeSettingsSection"]
	settings.reparent(right)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",6)
	settings.add_child(grid)
	for c in settings.get_children():
		if c is CheckBox:
			c.reparent(grid)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL

class ProgressStrip:
	extends Control
	var creator: RBMCreatorMain
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(0,size.y-2,size.x,2),Color("514a3d"))
		for i in range(creator.STEP_COUNT):
			var at := Vector2(size.x-260+i*20,12)
			draw_rect(Rect2(at,Vector2(12,12)),Color("b99b60") if i+1 == creator.current_step else Color("64583f"))
			if i+1 != creator.current_step: draw_rect(Rect2(at+Vector2(2,2),Vector2(8,8)),Color("101720"))

func creator_selection(main: RBMCreatorMain) -> void:
	for i in range(main._step_nav_column._rows.size()):
		var item: Dictionary = main._step_nav_column._rows[i]
		var b: Button = item.button
		var current := i+1 == main.current_step
		b.icon = icon("right") if current else null
		b.add_theme_color_override("font_color",IVORY if current else MUTED)
		(item.accent as ColorRect).color = GOLD if current else Color.TRANSPARENT

func center_exit_dialog(main: RBMCreatorMain) -> void:
	var p: PanelContainer = main._exit_confirm_panel
	var overlay := Control.new()
	overlay.name = "WorldExitDialogOverlay"
	main.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.03,0.05,0.78)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.reparent(overlay)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -300
	p.offset_top = -122
	p.offset_right = 300
	p.offset_bottom = 122
	p.add_theme_stylebox_override("panel", menu_frame(INK, GOLD, Vector4(28,24,28,24)))
	var col: VBoxContainer = p.find_child("ExitConfirmColumn", true, false)
	col.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = tr("変更内容を保存しますか？")
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	col.move_child(title, 0)
	var row := (p.find_child("ExitConfirmSaveButton", true, false) as Button).get_parent() as HBoxContainer
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_END
	for b in row.get_children():
		if b is Button: b.size_flags_vertical = Control.SIZE_SHRINK_END
	overlay.visible = p.visible
	p.visibility_changed.connect(func(): overlay.visible = p.visible)

func challenge_layout(hub: RBMChallengeHubView) -> void:
	if hub.has_meta("world_layout"): return
	hub.set_meta("world_layout", true)
	# Reuse a currently adopted room, no new world or environment art.
	var bg := TextureRect.new()
	bg.texture = load("res://assets_bossmaker/art/creator_top_background.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	hub.add_child(bg)
	hub.move_child(bg, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var old: Control = hub.find_child("HubColumn", true, false)
	old.hide()
	panel(hub, Rect2(144, 64, 992, 504),true)
	label(hub, tr("挑戦"), Rect2(184, 84, 920, 54), 36)
	label(hub, tr("遊びたいボスを選んでください"), Rect2(184, 143, 920, 28), 16, MUTED)
	label(hub, tr("モードから探す"), Rect2(184, 197, 400, 22), 15, GOLD)
	var names := ["SimpleCategoryButton", "HardcoreCategoryButton", "FeaturedCategoryButton", "NewCategoryButton", "UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton", "RandomChallengeButton", "SearchBossButton"]
	var positions := [Rect2(184,232,440,76), Rect2(648,232,440,76), Rect2(184,374,164,58), Rect2(369,374,164,58), Rect2(554,374,164,58), Rect2(739,374,164,58), Rect2(924,374,164,58), Rect2(648,478,208,48), Rect2(880,478,208,48)]
	label(hub, tr("ボスを見つける"), Rect2(184,334,400,22), 15, GOLD)
	for i in range(names.size()):
		var b: Button = old.find_child(names[i], true, false)
		b.reparent(hub)
		b.position = positions[i].position
		b.size = positions[i].size
		button_style(b, i == 8)
		if i < 2:
			menu_button(b)
			b.add_theme_font_size_override("font_size", 24)
	var back: Button = old.find_child("BackToRootButton", true, false)
	back.reparent(hub)
	back.text = tr("戻る")
	back.icon = icon("left")
	back.position = Vector2(56,636)
	back.size = Vector2(150,44)
	button_style(back)

