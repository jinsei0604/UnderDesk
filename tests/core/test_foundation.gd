extends GutTest
## Foundation pieces: art naming convention and survey card assembly.


func test_art_library_loads_shipped_art_and_falls_back() -> void:
	var lib := UDArtLibrary.load_default(["dorm", "tavern", "altar"])
	# Shipped: terrain set, rooms, depot, protagonist, Riko.
	for key: String in [
		"terrain_soil", "terrain_rock", "terrain_wetrock", "terrain_ruinstone",
		"terrain_air", "depot", "room_dorm", "room_tavern", "room_altar",
		"minion_0", "minion_2",
	]:
		assert_true(lib.has_art(key), "%s loads" % key)
	# Companions without art yet fall back to placeholder rectangles.
	assert_false(lib.has_art("minion_1"))
	assert_null(lib.texture("minion_1"))


func test_art_frame_animation() -> void:
	var lib := UDArtLibrary.load_default([])
	assert_eq(lib.frame_count("minion_0"), 3, "protagonist has a 3-frame dig loop")
	assert_eq(lib.frame_count("minion_2"), 2, "Riko has a blink frame")
	assert_eq(lib.frame_count("terrain_soil"), 1, "static tiles stay single-frame")
	assert_eq(lib.frame_count("minion_1"), 0, "missing art has no frames")
	assert_not_null(lib.frame("minion_0", 0))
	assert_not_null(lib.frame("minion_0", 7), "frame index wraps")
	assert_ne(lib.frame("minion_0", 0), lib.frame("minion_0", 1))


func test_art_keys() -> void:
	var lib := UDArtLibrary.load_default([])
	assert_eq(lib.terrain_key(UD.Terrain.SOIL), "terrain_soil")
	assert_eq(lib.terrain_key(UD.Terrain.RUINSTONE), "terrain_ruinstone")
	assert_eq(lib.terrain_key(UD.Terrain.AIR), "terrain_air")
	assert_eq(lib.minion_key(0), "minion_0")
	assert_eq(lib.minion_key(7), "minion_1", "variants wrap at %d" % UDArtLibrary.MINION_VARIANTS)


func test_survey_card_paths_and_build() -> void:
	assert_eq(UDSurveyCard.save_path_for("2026-07-11"), "user://cards/card_2026-07-11.png")
	var locale := UDLocale.load_locale("ja")
	var card := UDSurveyCard.build_card({
		"date_key": "2026-07-11",
		"anomaly_name": "テスト異変",
		"depth": 14,
		"coins": 320,
		"minions": 4,
		"docs": 6,
		"docs_total": 13,
	}, locale)
	assert_not_null(card)
	assert_eq(card.size, Vector2(UDSurveyCard.CARD_SIZE))
	assert_gt(card.get_child_count(), 0)
	card.free()


func test_survey_card_paper_tint() -> void:
	assert_eq(UDSurveyCard.paper_color(""), UDSurveyCard.COLOR_PAPER,
		"no anomaly color keeps plain paper")
	var tinted := UDSurveyCard.paper_color("#16301c")
	assert_ne(tinted, UDSurveyCard.COLOR_PAPER, "anomaly color stains the paper")
	assert_eq(UDSurveyCard.paper_color("not-a-color"), UDSurveyCard.COLOR_PAPER,
		"garbage color falls back to plain paper")


func test_survey_card_stamp_translates() -> void:
	for code: String in UD.SUPPORTED_LOCALES:
		var locale := UDLocale.load_locale(code)
		assert_ne(locale.text("CARD_STAMP"), "CARD_STAMP")
		assert_ne(locale.text("UI_CARD_COPIED"), "UI_CARD_COPIED")


func test_placeholder_icons_fall_back_when_no_real_art() -> void:
	var lib := UDArtLibrary.load_default([])
	# No item/shop/prestige/doc art is shipped yet: every dialog icon
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
	# minion_2.png ships for real (Riko); reuse it as a stand-in room id
	# to prove the new item/shop/prestige/doc id params get probed.
	var lib := UDArtLibrary.load_default(["dorm"], ["old_lantern"])
	assert_false(lib.has_art("item_old_lantern"), "no item art shipped yet")


func test_anomaly_card_colors_are_valid() -> void:
	for def: Variant in UDDataLoader.load_json_dir("res://data/anomalies"):
		var anomaly := def as Dictionary
		var color := str(anomaly.get("card_color", ""))
		if color == "":
			continue
		assert_true(Color.html_is_valid(color),
			"%s card_color %s parses" % [anomaly["id"], color])
