extends GutTest
## Foundation pieces: art naming convention and dialog icon fallback.


func test_art_library_loads_shipped_art_and_falls_back() -> void:
	var lib := UDArtLibrary.load_default(["dorm", "tavern", "altar"])
	# Shipped: rooms, depot, protagonist, and Madoka (companion_1).
	for key: String in [
		"depot", "room_dorm", "room_tavern", "room_altar", "minion_0", "minion_1",
	]:
		assert_true(lib.has_art(key), "%s loads" % key)
	# Companions without art yet fall back to placeholder rectangles.
	assert_false(lib.has_art("minion_2"))
	assert_null(lib.texture("minion_2"))


func test_art_frame_animation() -> void:
	var lib := UDArtLibrary.load_default([])
	assert_eq(lib.frame_count("minion_0"), 5, "protagonist has a 5-frame dig loop")
	assert_eq(lib.frame_count("depot"), 1, "static art stays single-frame")
	assert_eq(lib.frame_count("minion_1"), 8, "Madoka has an 8-frame idle loop")
	assert_eq(lib.frame_count("minion_2"), 0, "missing art has no frames")
	assert_not_null(lib.frame("minion_0", 0))
	assert_not_null(lib.frame("minion_0", 7), "frame index wraps")
	assert_ne(lib.frame("minion_0", 0), lib.frame("minion_0", 1))


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
