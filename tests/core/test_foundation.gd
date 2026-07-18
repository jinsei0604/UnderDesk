extends GutTest
## Foundation pieces: art naming convention and dialog icon fallback.


func test_art_library_loads_shipped_art_and_falls_back() -> void:
	var lib := UDArtLibrary.load_default(["dorm", "tavern", "altar"])
	# Shipped: rooms, depot, the protagonist's dorm portrait (redesign
	# pending, so no minion_0 pixel sprite right now - see CLAUDE.md).
	for key: String in [
		"depot", "room_dorm", "room_tavern", "room_altar", "portrait_minion_0",
	]:
		assert_true(lib.has_art(key), "%s loads" % key)
	# The pixel sprite itself, and companions in general, fall back to
	# placeholder rectangles until their art ships.
	assert_false(lib.has_art("minion_0"))
	assert_null(lib.texture("minion_0"))
	assert_false(lib.has_art("minion_1"))
	assert_null(lib.texture("minion_1"))


func test_art_frame_animation() -> void:
	var lib := UDArtLibrary.load_default([])
	assert_eq(lib.frame_count("depot"), 1, "static art stays single-frame")
	assert_eq(lib.frame_count("minion_0"), 0, "protagonist sprite not shipped yet (redesign pending)")
	assert_eq(lib.frame_count("minion_1"), 0, "missing art has no frames")


func test_art_keys() -> void:
	var lib := UDArtLibrary.load_default([])
	assert_eq(lib.minion_key(0), "minion_0")
	assert_eq(lib.minion_key(7), "minion_1", "variants wrap at %d" % UDArtLibrary.MINION_VARIANTS)


func test_placeholder_icons_fall_back_when_no_real_art() -> void:
	var lib := UDArtLibrary.load_default([])
	# No item/shop/doc art is shipped yet: every dialog icon
	# should still resolve to a generated placeholder, not null.
	assert_null(lib.texture("item_old_lantern"), "no real art shipped for this key")
	var icon := lib.icon_or_placeholder("item_old_lantern", "old_lantern", "gem")
	assert_not_null(icon)
	assert_eq(icon.get_width(), UDArtLibrary.PLACEHOLDER_ICON_SIZE)


func test_placeholder_icons_are_cached_and_deterministic() -> void:
	var lib := UDArtLibrary.load_default([])
	var a := lib.placeholder_icon("pickaxe", "rune")
	var b := lib.placeholder_icon("pickaxe", "rune")
	assert_eq(a, b, "same seed+shape reuses the cached texture")
	var c := lib.placeholder_icon("survey", "rune")
	assert_ne(a, c, "different seeds are distinct objects")


func test_placeholder_icon_shapes_differ() -> void:
	var lib := UDArtLibrary.load_default([])
	var gem := lib.placeholder_icon("x", "gem").get_image()
	var book := lib.placeholder_icon("x", "book").get_image()
	assert_ne(gem.get_data(), book.get_data(), "gem and book render different pixels")


func test_load_default_finds_real_art_for_extra_categories() -> void:
	# room_dorm.png ships for real; the extra id params (items, etc.) get
	# probed too and fall back cleanly when no art exists yet.
	var lib := UDArtLibrary.load_default(["dorm"], ["old_lantern"])
	assert_false(lib.has_art("item_old_lantern"), "no item art shipped yet")
