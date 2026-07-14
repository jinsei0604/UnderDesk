extends GutTest
## Plan change: the protagonist excavates alone; story companions join
## as documents are discovered (max party of 5).


func _defs() -> Array:
	return [
		{"id": "c1", "name_key": "X", "join_at_docs": 1},
		{"id": "c2", "name_key": "X", "join_at_docs": 2},
	]


func test_protagonist_starts_alone() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, [], _defs())
	assert_eq(sim.minions.size(), 1, "solo at the start")
	assert_eq(sim.companions.size(), 0)


func test_companion_joins_on_story_progress() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(1.0), 7, [], _defs())
	sim.dig_policy = UD.DigPolicy.NONE
	sim.add_dig_job(Vector2i(1, UD.DEPOT_POS.y))
	sim.advance(30)
	assert_eq(sim.discovered_documents.size(), 1)
	assert_eq(sim.companions.size(), 1, "first companion joined at 1 document")
	assert_eq(sim.companions[0], "c1")
	assert_eq(sim.minions.size(), 2)


func test_join_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.strata(1.0), 7, [], _defs())
	var b := UDSim.new_game(UDTestFixtures.strata(1.0), 7, [], _defs())
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.RIGHT
		sim.advance(200)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_companions_survive_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, [], _defs())
	sim.companions.append("c1")
	sim.minions.append(UDMinion.create(1, UD.DEPOT_POS))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.strata(), [], _defs()
	)
	assert_eq(restored.companions.size(), 1)
	assert_eq(restored.minions.size(), 2)


func test_pre_v4_party_migrates_to_solo() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, [], _defs())
	var d := sim.to_dict()
	d["version"] = 3
	# Fake an old three-minion crew with a claimed job.
	var minions: Array = d["minions"]
	for extra_id in [1, 2]:
		var clone: Dictionary = (minions[0] as Dictionary).duplicate(true)
		clone["id"] = extra_id
		minions.append(clone)
	d["jobs"] = [{"target": [5, 1], "progress": 1, "claimed_by": 2}]
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata(), [], _defs()
	)
	assert_eq(restored.minions.size(), 1, "party rebuilt as the solo protagonist")
	# The v6 -> v7 tunnel redesign resets the dig entirely, so any stale
	# jobs (claimed or not) are cleared rather than merely released.
	assert_eq(restored.jobs.size(), 0, "pre-v7 tunnel reset clears jobs")


func test_removed_companion_defs_prune_saved_party() -> void:
	# Placeholder companions were deleted from data; saves that had them
	# joined must shed them on load and rebuild the crew.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, [], _defs())
	sim.companions.append("c1")
	sim.companions.append("ghost")
	sim.minions.append(UDMinion.create(1, UD.DEPOT_POS))
	sim.minions.append(UDMinion.create(2, UD.DEPOT_POS))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.strata(), [], _defs()
	)
	assert_eq(restored.companions.size(), 1, "unknown companion removed")
	assert_eq(restored.companions[0], "c1")
	assert_eq(restored.minions.size(), 2, "party rebuilt to protagonist + c1")


func test_all_companions_removed_prunes_party_to_solo() -> void:
	# Every companion definition was deleted (empty defs): a save still
	# holding one must shed it and fall back to the solo protagonist.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, [], _defs())
	sim.companions.append("c1")
	sim.minions.append(UDMinion.create(1, UD.DEPOT_POS))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.strata(), [], []
	)
	assert_eq(restored.companions.size(), 0, "companion shed with no definitions")
	assert_eq(restored.minions.size(), 1, "party is the solo protagonist")


