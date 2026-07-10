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


func test_build_rejects_overlap() -> void:
	var sim := _sim_with_open_area()
	sim.inventory[UD.RES_SOIL] = 20
	assert_true(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(5, 1)))
	assert_false(sim.build_room(UDTestFixtures.dorm_def(), Vector2i(6, 1)),
		"footprints may not overlap")
