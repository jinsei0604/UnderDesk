extends GutTest


func test_new_game_grid_layout() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	assert_eq(sim.grid.width, UD.GRID_WIDTH)
	assert_eq(sim.grid.height, UD.GRID_INITIAL_HEIGHT)
	assert_eq(sim.grid.terrain_at(Vector2i(0, 0)), UD.Terrain.AIR, "surface row is air")
	assert_eq(sim.grid.terrain_at(Vector2i(0, 1)), UD.Terrain.SOIL)
	assert_eq(sim.grid.terrain_at(Vector2i(0, 5)), UD.Terrain.ROCK)


func test_grid_expands_below_deepest_stratum() -> void:
	var strata := UDTestFixtures.strata()
	var grid := UDGrid.new(4)
	for y in 12:
		grid.append_row(strata.terrain_for_depth(y))
	assert_eq(grid.height, 12)
	# Depth 10-11 is beyond the deepest defined stratum: reuses it.
	assert_eq(grid.terrain_at(Vector2i(0, 11)), UD.Terrain.ROCK)


func test_walkability() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	assert_true(sim.grid.is_walkable(Vector2i(10, 0)))
	assert_false(sim.grid.is_walkable(Vector2i(10, 1)))
	assert_false(sim.grid.is_walkable(Vector2i(-1, 0)), "out of bounds")


func test_pathfinder_straight_tunnel() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	# Carve a vertical tunnel at x=5, depth 1..3.
	for y in range(1, 4):
		sim.grid.set_terrain(Vector2i(5, y), UD.Terrain.AIR)
	var path := UDPathfinder.find_path(sim.grid, Vector2i(5, 0), Vector2i(5, 3))
	assert_eq(path.size(), 4, "start plus 3 steps down")
	assert_eq(path[0], Vector2i(5, 0))
	assert_eq(path[3], Vector2i(5, 3))


func test_pathfinder_unreachable() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	var path := UDPathfinder.find_path(sim.grid, Vector2i(5, 0), Vector2i(5, 3))
	assert_eq(path.size(), 0, "buried cell is unreachable")
