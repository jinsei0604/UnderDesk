extends GutTest
## UDCardDialog chrome: regression guard for the 2026-07-15 bug where the
## header close button was created hidden by add_header_close_button() and
## nothing ever turned it back on for the five enable_art_chrome() dialogs
## (archive/treasure/altar/guild/dorm) — closable only by the OS titlebar
## that enable_art_chrome() also removes, i.e. not closable at all.


func test_enable_art_chrome_shows_the_close_button() -> void:
	var dialog := UDCardDialog.create("X", false)
	dialog.enable_art_chrome("X", "close")
	assert_true(dialog.header_close_visible())
	dialog.free()


func test_add_header_close_button_alone_starts_hidden() -> void:
	# The shop's own usage pattern: create it hidden, then explicitly show
	# it per-page. If this ever stops being hidden by default, the shop's
	# front-page (where the art's own painted plaque is the only close
	# affordance) would show a redundant header button too.
	var dialog := UDCardDialog.create("X", false)
	dialog.add_header_close_button("close")
	assert_false(dialog.header_close_visible())
	dialog.set_header_close_visible(true)
	assert_true(dialog.header_close_visible())
	dialog.free()


func test_solid_hotspot_fires_its_callback_and_clears() -> void:
	var dialog := UDCardDialog.create("X", false)
	var fired := [false]
	var button := dialog.add_solid_hotspot(
		Rect2(0, 0, 1, 1), "close", func() -> void: fired[0] = true
	)
	button.pressed.emit()
	assert_true(fired[0])
	dialog.clear_hotspots()
	assert_true(not is_instance_valid(button) or button.is_queued_for_deletion())
	dialog.free()
