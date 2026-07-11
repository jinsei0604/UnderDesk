extends GutTest
## Validates the shipped data files (§7.3) load and cross-reference correctly.


func test_strata_files_load() -> void:
	var strata := UDStrataDB.load_from_dir("res://data/strata")
	assert_eq(strata.terrain_for_depth(0), UD.Terrain.AIR)
	assert_eq(strata.terrain_for_depth(1), UD.Terrain.SOIL)
	assert_eq(strata.terrain_for_depth(6), UD.Terrain.ROCK)
	assert_eq(strata.terrain_for_depth(16), UD.Terrain.WETROCK)
	assert_eq(strata.terrain_for_depth(100), UD.Terrain.WETROCK, "deepest stratum repeats")


func test_room_files_load() -> void:
	var rooms := UDRoomDB.load_from_dir("res://data/rooms")
	assert_true(rooms.has_room("dorm"))
	assert_true(rooms.has_room("tavern"))
	assert_eq(int(rooms.get_room("dorm")["width"]), 2)


func test_documents_and_locales_cross_reference() -> void:
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	assert_eq(docs.count(), 8)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	var doc_ids: Array[String] = []
	for n in range(1, 9):
		doc_ids.append("doc_%03d" % n)
	for doc_id in doc_ids:
		assert_true(docs.has_doc(doc_id))
		var doc := docs.get_doc(doc_id)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(doc["title_key"]), doc["title_key"],
				"%s title translated" % doc_id)
			assert_ne(locale.text(doc["body_key"]), doc["body_key"],
				"%s body translated" % doc_id)


func test_strata_document_ids_exist() -> void:
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	var strata_defs := UDDataLoader.load_json_dir("res://data/strata")
	for def: Variant in strata_defs:
		for doc_id: Variant in (def as Dictionary).get("documents", []) as Array:
			assert_true(docs.has_doc(doc_id), "%s referenced by strata exists" % doc_id)
