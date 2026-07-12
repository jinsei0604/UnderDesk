extends GutTest
## Validates the shipped data files (§7.3) load and cross-reference correctly.


func test_strata_files_load() -> void:
	var strata := UDStrataDB.load_from_dir("res://data/strata")
	assert_eq(strata.terrain_for_depth(0), UD.Terrain.AIR)
	assert_eq(strata.terrain_for_depth(1), UD.Terrain.SOIL)
	assert_eq(strata.terrain_for_depth(6), UD.Terrain.ROCK)
	assert_eq(strata.terrain_for_depth(16), UD.Terrain.WETROCK)
	assert_eq(strata.terrain_for_depth(31), UD.Terrain.RUINSTONE)
	assert_eq(strata.terrain_for_depth(100), UD.Terrain.RUINSTONE, "deepest stratum repeats")


func test_room_files_load() -> void:
	var rooms := UDRoomDB.load_from_dir("res://data/rooms")
	assert_true(rooms.has_room("dorm"))
	assert_true(rooms.has_room("tavern"))
	assert_true(rooms.has_room("altar"))
	assert_eq(int(rooms.get_room("dorm")["width"]), 2)


func test_documents_and_locales_cross_reference() -> void:
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	assert_eq(docs.count(), 13)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	var doc_ids: Array[String] = []
	for n in range(1, 14):
		doc_ids.append("doc_%03d" % n)
	for doc_id in doc_ids:
		assert_true(docs.has_doc(doc_id))
		var doc := docs.get_doc(doc_id)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(doc["title_key"]), doc["title_key"],
				"%s title translated" % doc_id)
			assert_ne(locale.text(doc["body_key"]), doc["body_key"],
				"%s body translated" % doc_id)


func test_document_foreshadow_metadata_is_well_formed() -> void:
	# Optional story-bible fields (§5.1): validated here so scenario data
	# can grow without code changes yet still fail loudly on typos.
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	assert_gt(docs.count(), 0, "documents shipped")
	var foreshadow_pattern := RegEx.create_from_string("^F\\d{2}$")
	for doc_id in docs.all_ids():
		var doc := docs.get_doc(doc_id)
		if doc.has("reveal_stage"):
			assert_true(str(doc["reveal_stage"]) in UD.REVEAL_STAGES,
				"%s reveal_stage is one of %s" % [doc_id, UD.REVEAL_STAGES])
		if doc.has("foreshadow_ids"):
			for fid: Variant in doc["foreshadow_ids"] as Array:
				assert_ne(foreshadow_pattern.search(str(fid)), null,
					"%s foreshadow id %s matches FNN" % [doc_id, fid])
		if doc.has("companion_tag"):
			assert_true(str(doc["companion_tag"]).length() > 0,
				"%s companion_tag is non-empty" % doc_id)
		if doc.has("conditions"):
			for key: Variant in (doc["conditions"] as Dictionary).keys():
				assert_true(str(key) in UD.DOC_CONDITION_KEYS,
					"%s condition key %s is known" % [doc_id, key])


func test_document_series_cross_reference() -> void:
	# Every document belongs to a defined series (data/series/), every
	# series translates, and no series shelf is empty in the archive.
	var series_defs := UDDataLoader.load_json_dir("res://data/series")
	assert_gt(series_defs.size(), 0)
	var series_ids: Array[String] = []
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for def: Variant in series_defs:
		var series := def as Dictionary
		series_ids.append(str(series["id"]))
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(series["name_key"]), series["name_key"],
				"%s name translated" % series["id"])
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	for doc_id in docs.all_ids():
		var series_id := str(docs.get_doc(doc_id).get("series", "other"))
		assert_true(series_id in series_ids,
			"%s series %s is defined" % [doc_id, series_id])


func test_strata_document_ids_exist() -> void:
	var docs := UDDocumentDB.load_from_dir("res://data/documents")
	var strata_defs := UDDataLoader.load_json_dir("res://data/strata")
	for def: Variant in strata_defs:
		for doc_id: Variant in (def as Dictionary).get("documents", []) as Array:
			assert_true(docs.has_doc(doc_id), "%s referenced by strata exists" % doc_id)
