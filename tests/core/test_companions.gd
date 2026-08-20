extends GutTest
## 新企画v1 §1 (2026-08-18): the staged join-by-document-count system is
## gone — new_game() seats every companion_defs entry immediately, so the
## party is protagonist + N companions from turn one. This file used to
## cover the retired staged-join mechanic; it now covers full-roster
## startup and the save migrations that normalize an older save to it.


func _defs() -> Array:
	return [
		{"id": "c1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 20, "hp_per_level": 4, "base_sp": 5, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1},
		{"id": "c2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 18, "hp_per_level": 4, "base_sp": 6, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1},
	]


func test_new_game_seats_the_full_roster_immediately() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	assert_eq(sim.companions, ["c1", "c2"], "every companion def present from turn one")
	assert_eq(sim.minions.size(), 3, "protagonist + 2 companions")
	assert_eq(sim.minions[0].id, 0)
	assert_eq(sim.minions[1].id, 1)
	assert_eq(sim.minions[2].id, 2)


func test_new_game_with_no_companion_defs_is_solo() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	assert_eq(sim.companions.size(), 0)
	assert_eq(sim.minions.size(), 1, "just the protagonist when no companion data is injected")


func test_full_roster_start_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], _defs())
	var b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7, [], _defs())
	for sim: UDSim in [a, b]:
		sim.advance(200)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_full_roster_survives_save_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions, ["c1", "c2"])
	assert_eq(restored.minions.size(), 3)


func test_pre_v4_party_migrates_to_the_modern_full_roster() -> void:
	# An ancient save (pre-companion-system) runs the whole migration
	# chain on load: v3 -> v4 first rebuilds it down to the solo
	# protagonist, then v8 -> v9 (新企画v1 §1) seats the full modern
	# roster on top of that — both migrations key off the same original
	# saved version number and apply in sequence.
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	var d := sim.to_dict()
	d["version"] = 3
	var minions: Array = d["minions"]
	for extra_id in [1, 2]:
		var clone: Dictionary = (minions[0] as Dictionary).duplicate(true)
		clone["id"] = extra_id
		minions.append(clone)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions, ["c1", "c2"], "full modern roster, not the old crew")
	assert_eq(restored.minions.size(), 3)


func test_v8_save_normalizes_a_partial_roster_to_full() -> void:
	# 新企画v1 §1 v8 -> v9: an old save mid-way through the retired staged
	# join (only c1 had joined) gains the rest of the roster on load.
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	sim.companions.append("c1")
	sim.minions.append(sim._new_unit_at_level(1, 1))
	var d := sim.to_dict()
	d["version"] = 8
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions, ["c1", "c2"], "the missing companion is added")
	assert_eq(restored.minions.size(), 3)


func test_v9_save_with_the_current_full_roster_is_left_alone() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	sim.minions[1].level = 3
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.minions[1].level, 3, "an already-current save is not rebuilt from scratch")


func test_removed_companion_def_prunes_saved_party() -> void:
	# A companion definition that no longer exists (e.g. deleted from data
	# files) is shed from a save that still lists it — independent of the
	# v8 -> v9 roster normalization above (this save is already v9-shaped).
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	var d := sim.to_dict()
	(d["companions"] as Array).append("ghost")
	var minions: Array = d["minions"]
	var ghost_unit: Dictionary = (minions[0] as Dictionary).duplicate(true)
	ghost_unit["id"] = minions.size()
	minions.append(ghost_unit)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _defs()
	)
	assert_eq(restored.companions, ["c1", "c2"], "unknown companion removed, known ones kept")
	assert_eq(restored.minions.size(), 3)


func test_all_companion_defs_removed_falls_back_to_solo() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], _defs())
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], []
	)
	assert_eq(restored.companions.size(), 0, "no known companion defs left")
	assert_eq(restored.minions.size(), 1, "party is the solo protagonist")
