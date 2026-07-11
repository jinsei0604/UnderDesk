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
