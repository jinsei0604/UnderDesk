extends "res://tools/verify_real_skills_gpu.gd"

var ui_checks: Array = []
var long_message_captured := false

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	for mode in ["test", "clear_check", "challenge"]:
		await _open_view(mode, _definition_for("hero"), "appearance_knight")
		await _settle()
		await _capture(mode + "_normal.png")
		await _click(view.find_child("OpenSkillListButton", true, false))
		await _check_skills(mode)
		var snapshot: Dictionary = view.session.battle.snapshot().duplicate(true)
		var state: Dictionary = view.session.battle.presentation_state().duplicate(true)
		var selected: bool = view._skill_list_panel.visible
		await _click(view.find_child("LogButton", true, false))
		_ui_check(mode + " log opens", view._log_window_overlay["overlay"].visible)
		await _capture(mode + "_log_open.png")
		var close: Button = view._log_window_overlay["close_button"]
		_ui_check(mode + " close visible in viewport", _inside(close))
		await _click(close)
		_ui_check(mode + " log closes", not view._log_window_overlay["overlay"].visible)
		_ui_check(mode + " log preserves snapshot", snapshot == view.session.battle.snapshot())
		_ui_check(mode + " log preserves presentation", state == view.session.battle.presentation_state())
		_ui_check(mode + " log preserves selection", selected == view._skill_list_panel.visible)
		await _click(view._skill_list_panel.get_child(0))
		await _click(view.find_child("AttackButton", true, false))
		await _settle()
		_ui_check(mode + " attack continues after log", not view._battle_log_history.is_empty() and snapshot != view.session.battle.snapshot())
		_layout_checks(mode)
		await _capture(mode + "_message.png")
		await _close_view()
	# Every ally's four real master skills, including longest labels/descriptions.
	for id in Assets.ALLY_IDS:
		await _open_view("test", _definition_for(id), "appearance_knight")
		var turns := 0
		while view.session.pending_ally_id() != _actor_id(id) and turns < 16:
			view.act_defend(view.session.pending_ally_id())
			await _settle()
			turns += 1
		await _click(view.find_child("OpenSkillListButton", true, false))
		await _check_skills(id)
		if id == "hero":
			view._presenter.entry_impact.connect(_long_message)
			await _click(view._skill_list_panel.find_child("SkillButton_hero_burst_slash", true, false))
			await _settle()
			_ui_check("long actual skill captured at impact", long_message_captured)
			_layout_checks("long skill")
			await _click(view.find_child("LogButton", true, false))
			_ui_check("populated log retains skill history", view._log_window_body_label.text.contains("炎属性高威力単体攻撃"))
			await _capture("populated_log.png")
			await _click(view._log_window_overlay["close_button"])
			_ui_check("populated log closes", not view._log_window_overlay["overlay"].visible)
		await _close_view()
	for boss in Assets.BOSS_IDS:
		await _open_view("test", _definition_for("samurai"), "appearance_" + boss)
		await _capture("boss_" + boss + ".png")
		await _close_view()
	await _open_view("test", _definition_for("samurai"), "appearance_knight")
	# Contact sheet inside the actual battlefield. Five visuals only; party stays four.
	for actor in stage._visuals.values(): actor.hide()
	for i in range(Assets.ALLY_IDS.size()):
		var id: String = Assets.ALLY_IDS[i]
		var actor := RBMCharacterVisual.new()
		stage.add_child(actor)
		actor.setup(id, Assets.display_height(id))
		actor.position = Vector2(stage.size.x * (i + 0.5) / 5.0, stage.size.y - 35) - actor.foot_position()
		var label := Label.new()
		label.text = id
		label.position = Vector2(stage.size.x * (i + 0.5) / 5.0 - 22, stage.size.y - 25)
		stage.add_child(label)
	await _settle()
	await _capture("all_five_healer_standard.png")
	_ui_check("gallery does not change party limit", view.session.battle.party.size() == 4)
	await _close_view()
	var result := {"passed": report["errors"].is_empty(), "errors": report["errors"], "checks": ui_checks, "viewport": [1280,720], "adapter": RenderingServer.get_video_adapter_name(), "five_visuals_only": true}
	FileAccess.open(output_dir.path_join("ui-gpu-report.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("UI_GPU_DONE passed=%s checks=%d" % [result["passed"], ui_checks.size()])
	quit(0 if result["passed"] else 1)

func _settle() -> void:
	for i in range(8): await process_frame
	var ticks := 0
	while is_instance_valid(view) and view._presenter.is_playing() and ticks < 1200:
		await process_frame
		ticks += 1
	for i in range(8): await process_frame

func _long_message(entry: Dictionary) -> void:
	if str(entry.get("skill_id", "")) != "hero_burst_slash": return
	await process_frame
	await _capture("hero_long_skill_message.png")
	_ui_check("actual long skill headline displayed", view._log_label.text.contains("炎属性高威力単体攻撃"))
	_ui_check("multiline message fits without clipping", view._log_label.get_minimum_size().y <= view._log_label.get_parent().size.y)
	long_message_captured = true

func _click(button: Control) -> void:
	if button == null:
		_ui_check("button exists", false)
		return
	var point := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	Input.parse_input_event(move)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _settle()

func _inside(control: Control) -> bool:
	return control.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(1280,720)).encloses(control.get_global_rect())

func _ui_check(label: String, passed: bool) -> void:
	ui_checks.append({"name":label,"passed":passed})
	if not passed: _fail(label)

func _check_skills(label: String) -> void:
	_ui_check(label + " skill panel opens", view._skill_list_panel.visible)
	var count := 0
	for child in view._skill_list_panel.get_children():
		if child is Button:
			count += 1
			_ui_check(label + " visible " + child.name, _inside(child))
	_ui_check(label + " back plus four skills", count == 5)
	_ui_check(label + " no skill scroll required", not view._skill_list_panel.get_parent() is ScrollContainer)
	_layout_checks(label)
	await _capture(label + "_skills.png")

func _layout_checks(label: String) -> void:
	var message: Control = view.find_child("LatestInfoPanel",true,false)
	_ui_check(label + " message between battlefield and HP", message.get_global_rect().position.y >= view._battlefield.get_global_rect().end.y and message.get_global_rect().end.y <= view._party_rows.get_global_rect().position.y)
	_ui_check(label + " message wide", message.size.x >= 600)
	_ui_check(label + " battlefield height", view._battlefield.size.y >= 260)
	_ui_check(label + " HP panels inside", _inside(view._party_rows))
	_ui_check(label + " LOG inside", _inside(view.find_child("LogButton",true,false)))
	_ui_check(label + " commands below turn order", view._command_area.get_global_rect().position.y >= view._turn_order_panel.get_global_rect().end.y)
	_ui_check(label + " quit inside", _inside(view._quit_button))

