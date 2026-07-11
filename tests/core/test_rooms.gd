extends GutTest


func _sim_with_open_area() -> UDSim:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	for x in range(5, 9):
		sim.grid.set_terrain(Vector2i(x, 1), UD.Terrain.AIR)
	return sim


func test_build_dorm_spawns_minion() -> void:
	var sim := _sim_with_open_area()
	sim.inventory[UD.RES_SOIL] = 10
	var before := sim.minions.size()
	assert_true(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(5, 1)))
	assert_eq(sim.minions.size(), before + 1)
	assert_eq(int(sim.inventory[UD.RES_SOIL]), 0, "cost deducted")
	assert_eq(sim.rooms.size(), 1)


func test_build_rejects_insufficient_resources() -> void:
	var sim := _sim_with_open_area()
	sim.inventory[UD.RES_SOIL] = 9
	assert_false(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(5, 1)))
	assert_eq(sim.rooms.size(), 0)


func test_build_rejects_undug_cells() -> void:
	var sim := _sim_with_open_area()
	sim.inventory[UD.RES_SOIL] = 10
	assert_false(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(20, 1)),
		"cannot build inside solid ground")


func test_tavern_adds_dig_power() -> void:
	var sim := _sim_with_open_area()
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER)
	sim.inventory[UD.RES_STONE] = 8
	var tavern := {
		"id": "tavern",
		"name_key": "ROOM_TAVERN",
		"width": 2,
		"height": 1,
		"cost": {"stone": 8},
		"effect": "dig_power_add",
	}
	assert_true(sim.build_room(tavern, Vector2i(5, 1)))
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER + 1)
	# The bonus must survive a save/load cycle.
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.dig_power(), UD.MINION_DIG_POWER + 1)


func test_altar_raises_document_chance() -> void:
	var sim := _sim_with_open_area()
	assert_eq(sim.document_chance_bonus(), 0.0)
	sim.inventory[UD.RES_MAGIC_STONE] = 5
	var altar := {
		"id": "altar",
		"name_key": "ROOM_ALTAR",
		"width": 2,
		"height": 1,
		"cost": {"magic_stone": 5},
		"effect": "doc_chance_add",
	}
	assert_true(sim.build_room(altar, Vector2i(5, 1)))
	assert_eq(sim.document_chance_bonus(), UD.DOC_CHANCE_PER_ALTAR)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.document_chance_bonus(), UD.DOC_CHANCE_PER_ALTAR)


func test_build_rejects_overlap() -> void:
	var sim := _sim_with_open_area()
	sim.inventory[UD.RES_SOIL] = 20
	assert_true(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(5, 1)))
	assert_false(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(6, 1)),
		"footprints may not overlap")
