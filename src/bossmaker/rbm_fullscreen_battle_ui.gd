extends "res://src/bossmaker/rbm_world_ui.gd"
## Common display layout for TEST, Clear Check and CHALLENGE.
## Existing controls keep their signals and session ownership.
var view: Control
var canvas: Control
var stage: Control
var command_scroll: ScrollContainer
var command_backdrop: Panel
var background: TextureRect
var current_background := ""
var built := false

func setup(target: Control) -> void:
	view = target
	view.visibility_changed.connect(update.call_deferred)
	view._skill_list_panel.visibility_changed.connect(update.call_deferred)
	view._target_picker.visibility_changed.connect(update.call_deferred)
	if view is RBMCreatorClearCheckView:
		view._confirm_panel.visibility_changed.connect(update.call_deferred)
	update.call_deferred()

func place(c: Control, parent: Control, rect: Rect2) -> void:
	if c.get_parent() != parent: c.reparent(parent)
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.position = rect.position
	c.size = rect.size

func modal(content: Control, hud: Control, rect: Rect2, node_name: String) -> void:
	var overlay := Control.new()
	overlay.name = node_name
	hud.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 40
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.03,0.05,0.78)
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel(overlay,rect)
	place(content,overlay,Rect2(rect.position+Vector2(20,20),rect.size-Vector2(40,40)))
	content.add_theme_constant_override("separation",16)
	if content is HBoxContainer:
		for child in content.get_children():
			if child is Button:
				child.custom_minimum_size = Vector2(150,44)
				child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			elif child is Label:
				child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.visibility_changed.connect(func(): overlay.visible = content.visible)
	overlay.visible = content.visible

func build() -> void:
	built = true
	canvas = Control.new()
	canvas.name = "FullScreenBattleCanvas"
	view.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage = view._battlefield_ally_row.get_meta("visual_stage")
	place(stage,canvas,Rect2(0,0,1280,720))
	stage.set_meta("fullscreen_formation",true)
	stage._layout_actors()
	background = TextureRect.new()
	background.name = "FullScreenBattleBackground"
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	stage.move_child(background,0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var hud := Control.new()
	hud.name = "BattleHUD"
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.z_index = 20
	panel(hud,Rect2(24,20,590,54))
	place(view._boss_label,hud,Rect2(40,28,550,38))
	view._boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel(hud,Rect2(944,20,312,202))
	place(view._turn_order_panel,hud,Rect2(960,32,280,176))
	panel(hud,Rect2(24,558,900,134))
	place(view._party_rows,hud,Rect2(36,568,876,114))
	view._party_rows.add_theme_constant_override("separation",12)
	# The legacy Battlefield container is emptied above (its boss label and visual
	# stage are both already relocated onto the fullscreen canvas), so it no longer
	# has anything to draw. It stays hidden, but still needs a real rect describing
	# the on-screen area the stage/sprites actually occupy -- verify_battle_ui_gpu.gd
	# checks that the latest-info message sits below this area and above the HP row.
	place(view._battlefield,hud,Rect2(24,20,1232,430))
	view._battlefield.visible = false
	command_backdrop = panel(hud,Rect2(944,430,312,262))
	command_backdrop.name = "CommandBackdrop"
	command_scroll = ScrollContainer.new()
	command_scroll.name = "BattleCommandScroll"
	command_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud.add_child(command_scroll)
	place(view._command_area,command_scroll,Rect2(0,0,288,236))
	view._command_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Latest-info panel and its existing scroll move together. Positioned in the
	# gap between the battlefield area and the HP row (both placed above).
	place(view._log_label.get_parent().get_parent(),hud,Rect2(24,450,700,112))
	place(view.find_child("LogButton",true,false),hud,Rect2(944,240,90,44))
	place(view._quit_button,hud,Rect2(1050,240,206,44))
	if view is RBMCreatorTestBattleView or view is RBMCreatorClearCheckView:
		place(view._rewind_list.get_parent(),hud,Rect2(24,82,312,44))
	if view is RBMCreatorClearCheckView or view is RBMChallengeBattleView:
		place(view._restart_button,hud,Rect2(350,82,244,44))
		modal(view._restart_confirm,hud,Rect2(190,260,900,180),"RestartDialog")
	if view is RBMCreatorTestBattleView or view is RBMChallengeBattleView:
		modal(view._quit_confirm,hud,Rect2(190,260,900,180),"QuitDialog")
	modal(view._outcome_area,hud,Rect2(390,240,500,240),"OutcomeDialog")
	# Clear Check still owns its confirm/battle visibility state. Keep those nodes.
	if view is RBMCreatorClearCheckView:
		for child in view._battle_panel.get_children():
			if child is Control: child.hide()
	else:
		view.get_node("Column").hide()
	for detail in [view._ally_detail_overlay,view._boss_detail_overlay,view._log_window_overlay]:
		var detail_overlay: Control = detail["overlay"]
		detail_overlay.z_index = 60
		# These overlays are meant to behave like full-screen modal popups (see
		# build_detail_overlay's own doc comment), but they are plain children of
		# `view`, nested alongside the fullscreen HUD tree rather than as an actual
		# top-level popup. Without top_level, pointer clicks on their inner buttons
		# (e.g. the "close" button) were not reaching those buttons once the rest of
		# the screen was rebuilt into this absolute-positioned HUD -- only clicks
		# that fell through to the overlay's own catch-all "click anywhere closes"
		# handler worked. top_level=true fixes hit-testing without changing the
		# overlay's on-screen position (its anchors still resolve against `view`'s
		# own full-viewport rect).
		detail_overlay.top_level = true

func update() -> void:
	if not is_instance_valid(view) or not view.is_inside_tree(): return
	if not built: build()
	canvas.visible = not view._confirm_panel.visible if view is RBMCreatorClearCheckView else true
	var value: String = view.battle_background
	if view is RBMCreatorTestBattleView or view is RBMCreatorClearCheckView:
		if is_instance_valid(view.main) and view.main.get("draft") is RBMCreatorDraft:
			value = view.main.draft.battle_background
	if value != current_background:
		current_background = value
		background.texture = load("res://assets_bossmaker/art/battle_courtyard_%s.png" % ("day" if value == "day" else "night"))
	var selecting: bool = view._skill_list_panel.visible or view._target_picker.visible
	var top := 302.0 if selecting else 442.0
	command_backdrop.position.y = top-12
	command_backdrop.size.y = 692-(top-12)
	command_scroll.position = Vector2(956,top)
	command_scroll.size = Vector2(288,680-top)
	# Content has natural minimum height; the viewport, exit and return controls stay fixed.
	view._command_area.custom_minimum_size.y = 0
	walk(view)
