extends GutTest
const Launcher = preload("res://src/bossmaker/rbm_title_boot_launcher.gd")
const Catalog = preload("res://src/bossmaker/title_rooms/rbm_title_room_catalog.gd")

var _saved_room: String

func before_each() -> void:
	_saved_room = Catalog._session_room_id

func after_each() -> void:
	Catalog._session_room_id = _saved_room

func _make_title(room_id: String = "astronaut") -> Control:
	Catalog._session_room_id = room_id
	get_tree().root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var title := Launcher.new()
	host.add_child(title)
	await get_tree().process_frame
	return title

func test_approved_room_and_shared_wordmark() -> void:
	var title := await _make_title()
	assert_eq(title.selected_room_id, "astronaut")
	assert_eq(title._viewport.size, Vector2i(640, 360))
	assert_eq(title._room.get_script().resource_path, "res://src/bossmaker/title_rooms/rbm_astronaut_title_room.gd")
	var logo: Label = title.find_child("TitleText", true, false)
	assert_eq(logo.text, "MAKERS & CHALLENGERS")
	assert_eq(logo.get_theme_font_size("font_size"), 36)
	assert_eq(logo.get_theme_font("font").resource_path, "res://assets_bossmaker/fonts/Oxanium-SemiBold.ttf")
	assert_false(title._start_button.disabled)
	assert_true(title._start_button.get_meta("rbm_audio_bound"), "automatic UI audio must stay suppressed")
	assert_eq(title.find_children("*", "AudioStreamPlayer", true, false).size(), 0)

func test_selection_is_retained_when_launcher_is_recreated() -> void:
	var first := await _make_title()
	var second := await _make_title()
	assert_eq(first.selected_room_id, second.selected_room_id)
	assert_eq(first.selected_room_id, Catalog.session_room_id())
	assert_eq(Catalog.ROOMS.size(), 3, "all approved rooms participate in launch selection")

func test_start_during_typing_and_aura_finishes_once_without_long_movie() -> void:
	for time in [0.0, 21.8]:
		var title := await _make_title()
		title._room.advance(time)
		watch_signals(title)
		title._start_button.pressed.emit()
		title._on_start_pressed()
		await get_tree().create_timer(0.25).timeout
		assert_true(title._revealed)
		assert_false(title.visible)
		assert_eq(get_signal_emit_count(title, "boot_completed"), 1)
		assert_false(title.is_processing())
		assert_eq(title._viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)

func test_keyboard_start_and_resize() -> void:
	var title := await _make_title()
	title.get_parent().size = Vector2(1600, 900)
	await get_tree().process_frame
	assert_eq(title._canvas.scale, Vector2(1.25, 1.25))
	assert_eq(title._canvas.position, Vector2.ZERO)
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	title._input(accept)
	await get_tree().create_timer(0.25).timeout
	assert_true(title._revealed)

func test_live_clock_and_connected_character() -> void:
	var title := await _make_title()
	title._room.advance(21.8)
	title._room.sync_clock()
	var local := Time.get_datetime_dict_from_system(false)
	var seconds: float = local.hour * 3600 + local.minute * 60 + local.second
	assert_almost_eq(title._room.clock_base + title._room.t, seconds, 1.0)
	assert_gt(title._room.aura.intensity, 0.9)
	assert_not_null(title._room.character_mesh)
	assert_eq(title._room.character_mesh.get_surface_count(), 1, "one connected full-character surface")
	var before: Vector2 = title._room.pointer
	title._room.advance(6.2)
	var after: Vector2 = title._room.pointer
	title._room.advance(7.8)
	assert_ne(after, title._room.pointer, "PC cursor moves with mouse action")
	var stopped: Vector2 = title._room.pointer
	title._room.advance(11.0)
	assert_eq(stopped, title._room.pointer, "cursor stays still during typing")

func test_real_game_home_and_creator_return_do_not_replay_title() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	var title: Control = root._title_boot_launcher
	assert_eq(root._title_screen.get_child(-1), title, "title blocks even the later-created locale button")
	title._start_button.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	assert_false(title.visible)
	assert_true(root._title_screen.visible)
	assert_true(root._challenge_monitor.is_visible_in_tree())
	assert_true(root._creator_monitor.is_visible_in_tree())
	var room_id: String = title.selected_room_id
	root._on_create_pressed()
	assert_true(root.creator_entry.visible)
	root._on_creator_exit_requested()
	assert_true(root._title_screen.visible)
	assert_false(title.visible)
	assert_eq(title.selected_room_id, room_id)

func test_all_rooms_use_the_same_full_window_start_with_one_click_sound() -> void:
	for room_id in Catalog.ROOMS.keys():
		for point in [Vector2(12,12), Vector2(1268,12), Vector2(12,708), Vector2(1268,708), Vector2(640,360)]:
			var title := await _make_title(room_id)
			assert_eq(title._start_button.size, title.size)
			watch_signals(title)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.position = point
			click.pressed = true
			title.get_viewport().push_input(click, true)
			title.get_viewport().push_input(click, true)
			var audio: Node = title.get_node("RBMAudio")
			assert_eq(audio.history, ["ui_confirm"])
			await get_tree().create_timer(0.25).timeout
			assert_eq(get_signal_emit_count(title, "boot_completed"), 1)
			assert_false(title.visible)
			if room_id == "gentleman":
				assert_eq(title._room.rig_view.render_target_update_mode, SubViewport.UPDATE_DISABLED)
			elif room_id == "musha":
				assert_eq(title._room.decor_view.render_target_update_mode, SubViewport.UPDATE_DISABLED)

func test_touch_and_letterbox_click_activate_title() -> void:
	var title := await _make_title("gentleman")
	title.get_parent().size = Vector2(1600,720)
	await get_tree().process_frame
	assert_eq(title._canvas.position.x,160.0)
	assert_eq(title._start_button.size,Vector2(1600,720))
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(8,360)
	touch.pressed = true
	title.get_viewport().push_input(touch,true)
	await get_tree().create_timer(0.25).timeout
	assert_true(title._revealed)
	assert_eq(title.get_node("RBMAudio").history,["ui_confirm"])

func test_gentleman_preserves_approved_rig_fire_and_shadow() -> void:
	var title := await _make_title("gentleman")
	assert_eq(title._viewport.size,Vector2i(320,180))
	assert_eq(title._room.presentation.get_parent(),title._canvas)
	assert_eq(title._room.scale,Vector2(.5,.5))
	for time in [0.0,10.5,20.1,22.1,35.3,36.6,38.5,40.0]:
		title._room.advance(time)
		assert_eq(title._room.body.transform,Transform2D.IDENTITY)
		assert_eq(title._room.cup.get_parent(),title._room.hand)
	title._room.advance(35.3)
	assert_gt(title._room.visitor.opacity,0.8)
	title._room.advance(36.6)
	assert_eq(title._room.look,1.0)
	title._room.advance(38.5)
	assert_eq(title._room.visitor.opacity,0.0)
	assert_eq(title._room.look,0.0)

func test_catalog_selects_all_rooms_and_caches_each_launch() -> void:
	var seen: Dictionary = {}
	for launch in range(64):
		Catalog._session_room_id = ""
		var chosen: String = Catalog.session_room_id()
		assert_true(Catalog.ROOMS.has(chosen))
		assert_eq(Catalog.session_room_id(),chosen)
		seen[chosen] = true
	assert_eq(seen.size(),3)


func test_musha_keeps_complete_approved_cels_and_resumes_without_a_redraw() -> void:
	var title := await _make_title("musha")
	assert_eq(title._viewport.size, Vector2i(640, 360))
	assert_eq(title._room.actor.texture.resource_path, "res://assets_bossmaker/title_rooms/musha/seated_cleaning.png")
	assert_eq(title._room.actor.hframes * title._room.actor.vframes, 24)
	assert_eq(title._room.decor_view.size, Vector2i(320, 180))
	title.set_process(false)
	title._room.advance(0.0)
	var rest_frame: int = title._room.actor.frame
	title._room.advance(5.2)
	var wiping_frame: int = title._room.actor.frame
	assert_ne(wiping_frame, rest_frame)
	assert_eq(title._room.actor.scale, Vector2.ONE)
	assert_eq(title._room.actor.rotation, 0.0)
	title.hide()
	assert_eq(title._room.decor_view.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	title.show()
	assert_eq(title._room.actor.frame, wiping_frame)
	assert_eq(title._room.decor_view.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_eq(title.selected_room_id, "musha")
	title._room.advance(40.0)
	assert_eq(title._room.actor.frame, rest_frame)

func test_musha_start_during_wipe_stops_both_viewports_and_opens_home_once() -> void:
	var title := await _make_title("musha")
	title._room.advance(5.2)
	watch_signals(title)
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(8, 8)
	touch.pressed = true
	title.get_viewport().push_input(touch, true)
	title.get_viewport().push_input(touch, true)
	await get_tree().create_timer(0.25).timeout
	assert_eq(get_signal_emit_count(title, "boot_completed"), 1)
	assert_eq(title.get_node("RBMAudio").history, ["ui_confirm"])
	assert_false(title.visible)
	assert_false(title.is_processing())
	assert_eq(title._viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(title._room.decor_view.render_target_update_mode, SubViewport.UPDATE_DISABLED)
