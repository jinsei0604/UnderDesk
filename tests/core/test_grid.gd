extends GutTest


func test_new_game_grid_layout() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	assert_eq(sim.grid.width, UD.GRID_INITIAL_WIDTH)
	assert_eq(sim.grid.height, UD.CORRIDOR_HEIGHT)
	# Terrain now varies by x (distance dug), uniform down each column.
	assert_eq(sim.grid.terrain_at(Vector2i(0, 0)), UD.Terrain.AIR, "entrance column is air")
	assert_eq(sim.grid.terrain_at(Vector2i(1, 0)), UD.Terrain.SOIL)
	assert_eq(sim.grid.terrain_at(Vector2i(5, 0)), UD.Terrain.ROCK)


func test_grid_expands_past_deepest_stratum() -> void:
	var strata := UDTestFixtures.strata()
	var grid := UDGrid.new(3)
	for x in 12:
		grid.append_column(strata.terrain_for_distance(x))
	assert_eq(grid.width, 12)
	# Distance 10-11 is beyond the deepest defined stratum: reuses it.
	assert_eq(grid.terrain_at(Vector2i(11, 0)), UD.Terrain.ROCK)


func test_walkability() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	assert_true(sim.grid.is_walkable(Vector2i(0, 0)), "entrance column is open")
	assert_false(sim.grid.is_walkable(Vector2i(1, 0)), "first face is solid")
	assert_false(sim.grid.is_walkable(Vector2i(-1, 0)), "out of bounds")


func test_pathfinder_straight_tunnel() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	# Carve a horizontal tunnel along row 1, distance 1..3.
	for x in range(1, 4):
		sim.grid.set_terrain(Vector2i(x, 1), UD.Terrain.AIR)
	var path := UDPathfinder.find_path(sim.grid, Vector2i(0, 1), Vector2i(3, 1))
	assert_eq(path.size(), 4, "start plus 3 steps right")
	assert_eq(path[0], Vector2i(0, 1))
	assert_eq(path[3], Vector2i(3, 1))


func test_pathfinder_unreachable() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	var path := UDPathfinder.find_path(sim.grid, Vector2i(0, 1), Vector2i(3, 1))
	assert_eq(path.size(), 0, "buried cell is unreachable")
