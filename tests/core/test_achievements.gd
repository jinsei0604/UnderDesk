extends GutTest
## Achievement tracker: data-driven triggers, once-only unlocks, and a
## platform hook that will later forward to Steam.


class RecordingPlatform:
	extends UDPlatform
	var calls: Array[String] = []

	func notify_unlock(achievement_id: String) -> void:
		calls.append(achievement_id)


func _defs() -> Array:
	return [
		{"id": "a_docs", "name_key": "X", "desc_key": "X",
			"trigger": {"type": "docs", "count": 2}},
		{"id": "a_depth", "name_key": "X", "desc_key": "X",
			"trigger": {"type": "depth", "count": 3}},
	]


func test_nothing_unlocks_at_start() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	var tracker := UDAchievements.from_defs(_defs(), UDPlatform.new())
	assert_eq(tracker.evaluate(sim).size(), 0)
	assert_eq(tracker.unlocked.size(), 0)


func test_unlocks_once_and_notifies_platform() -> void:
	var platform := RecordingPlatform.new()
	var tracker := UDAchievements.from_defs(_defs(), platform)
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.discovered_documents.append("d1")
	sim.discovered_documents.append("d2")
	var fresh := tracker.evaluate(sim)
	assert_eq(fresh, ["a_docs"] as Array[String])
	assert_eq(platform.calls, ["a_docs"] as Array[String])
	assert_eq(tracker.evaluate(sim).size(), 0, "already unlocked: no repeat")
	assert_eq(platform.calls.size(), 1, "platform notified exactly once")


func test_depth_trigger() -> void:
	var tracker := UDAchievements.from_defs(_defs(), UDPlatform.new())
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	for x in range(1, 4):
		sim._ensure_cols(x + 2)
		sim.grid.set_terrain(Vector2i(x, 1), UD.Terrain.AIR)
	var fresh := tracker.evaluate(sim)
	assert_true(fresh.has("a_depth"))


func test_unlocks_survive_dict_roundtrip() -> void:
	var tracker := UDAchievements.from_defs(_defs(), UDPlatform.new())
	tracker.unlocked.append("a_docs")
	var restored := UDAchievements.from_defs(_defs(), UDPlatform.new())
	restored.apply_dict(JSON.parse_string(JSON.stringify(tracker.to_dict())))
	assert_eq(restored.unlocked, ["a_docs"] as Array[String])
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.discovered_documents.append("d1")
	sim.discovered_documents.append("d2")
	assert_eq(restored.evaluate(sim).size(), 0, "restored unlock not re-earned")


func test_achievement_files_load_and_translate() -> void:
	var defs := UDDataLoader.load_json_dir("res://data/achievements")
	assert_gt(defs.size(), 0)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for def: Variant in defs:
		var ach := def as Dictionary
		var trigger := ach["trigger"] as Dictionary
		assert_true(str(trigger["type"]) in UDAchievements.TRIGGER_TYPES,
			"%s trigger type known" % ach["id"])
		assert_gt(int(trigger["count"]), 0)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(ach["name_key"]), ach["name_key"])
			assert_ne(locale.text(ach["desc_key"]), ach["desc_key"])
