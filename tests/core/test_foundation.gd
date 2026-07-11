extends GutTest
## Foundation pieces: art naming convention and survey card assembly.


func test_art_library_falls_back_gracefully() -> void:
	var lib := UDArtLibrary.load_default(["dorm", "tavern", "altar"])
	# No PNGs shipped yet: everything falls back to placeholder drawing.
	assert_false(lib.has_art("terrain_soil"))
	assert_null(lib.texture("terrain_soil"))


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
