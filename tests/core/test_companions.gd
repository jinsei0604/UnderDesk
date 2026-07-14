extends GutTest
## Plan change: the protagonist excavates alone; story companions join
## as documents are discovered (max party of 5).


func _defs() -> Array:
	return [
		{"id": "c1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 20, "hp_per_level": 4, "base_mp": 5, "mp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1},
		{"id": "c2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 18, "hp_per_level": 4, "base_mp": 6, "mp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1},
	]


func test_protagonist_starts_alone() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	assert_eq(sim.minions.size(), 1, "solo at the start")
	assert_eq(sim.companions.size(), 0)


func test_companion_joins_on_story_progress() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], _defs())
	# The fixture trash dies the tick after it spawns (tick 1 spawns, tick 2
	# kills), and document_chance 1.0 always drops one, so 2 ticks already
	# yield exactly 1 document (and thus only the join_at_docs=1 companion).
	sim.advance(2)
	assert_gt(sim.discovered_documents.size(), 0)
	assert_eq(sim.companions.size(), 1, "first companion joined at 1 document")
	assert_eq(sim.companions[0], "c1")
	assert_eq(sim.minions.size(), 2)


func test_join_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], _defs())
	var b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], _defs())
	for sim: UDSim in [a, b]:
		sim.advance(200)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_companions_survive_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	sim.companions.append("c1")
	sim.minions.append(sim._new_unit_at_level(1, 1))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions.size(), 1)
	assert_eq(restored.minions.size(), 2)


func test_pre_v4_party_migrates_to_solo() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	var d := sim.to_dict()
	d["version"] = 3
	# Fake an old three-minion crew.
	var minions: Array = d["minions"]
	for extra_id in [1, 2]:
		var clone: Dictionary = (minions[0] as Dictionary).duplicate(true)
		clone["id"] = extra_id
		minions.append(clone)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.minions.size(), 1, "party rebuilt as the solo protagonist")


func test_removed_companion_defs_prune_saved_party() -> void:
	# Placeholder companions were deleted from data; saves that had them
	# joined must shed them on load and rebuild the crew.
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	sim.companions.append("c1")
	sim.companions.append("ghost")
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.minions.append(sim._new_unit_at_level(2, 1))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions.size(), 1, "unknown companion removed")
	assert_eq(restored.companions[0], "c1")
	assert_eq(restored.minions.size(), 2, "party rebuilt to protagonist + c1")


func test_all_companions_removed_prunes_party_to_solo() -> void:
	# Every companion definition was deleted (empty defs): a save still
	# holding one must shed it and fall back to the solo protagonist.
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	sim.companions.append("c1")
	sim.minions.append(sim._new_unit_at_level(1, 1))
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], []
	)
	assert_eq(restored.companions.size(), 0, "companion shed with no definitions")
	assert_eq(restored.minions.size(), 1, "party is the solo protagonist")


