extends GutTest
## §13-3: one minion digs a designated cell and hauls the soil home.

const MAX_TICKS: int = 60


func test_full_dig_haul_cycle() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	var target := Vector2i(UD.DEPOT_POS.x, 1)
	assert_true(sim.add_dig_job(target))

	var done := false
	for i in MAX_TICKS:
		sim.tick()
		if int(sim.inventory[UD.RES_SOIL]) == 1:
			done = true
			break
	assert_true(done, "soil deposited within %d ticks" % MAX_TICKS)
	assert_eq(sim.grid.terrain_at(target), UD.Terrain.AIR, "cell was dug out")
	assert_eq(sim.jobs.size(), 0, "job consumed")


func test_dig_job_validation() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	assert_false(sim.add_dig_job(Vector2i(5, 0)), "air cell not diggable")
	assert_false(sim.add_dig_job(Vector2i(-1, 3)), "out of bounds")
	assert_true(sim.add_dig_job(Vector2i(5, 1)))
	assert_false(sim.add_dig_job(Vector2i(5, 1)), "duplicate designation")


func test_unreachable_job_stays_queued_without_breaking() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	assert_true(sim.add_dig_job(Vector2i(5, 3)), "buried cell can be designated")
	sim.advance(20)
	assert_eq(sim.jobs.size(), 1, "job waits until reachable (§5.1: no loss)")
	for minion in sim.minions:
		assert_eq(minion.state, UDMinion.State.IDLE)


func test_digging_down_expands_grid() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	var initial_height := sim.grid.height
	# Dig a column downward; each completed dig near the bottom appends rows.
	for y in range(1, initial_height):
		sim.add_dig_job(Vector2i(UD.DEPOT_POS.x, y))
	sim.advance(400)
	assert_gt(sim.grid.height, initial_height, "grid expanded downward")


func test_document_discovery_is_deterministic() -> void:
	var sim_a := UDSim.new_game(UDTestFixtures.strata(1.0), 7)
	var sim_b := UDSim.new_game(UDTestFixtures.strata(1.0), 7)
	for sim: UDSim in [sim_a, sim_b]:
		sim.add_dig_job(Vector2i(UD.DEPOT_POS.x, 1))
		sim.advance(30)
	assert_eq(sim_a.discovered_documents.size(), 1, "chance 1.0 always drops")
	assert_eq(sim_a.discovered_documents, sim_b.discovered_documents,
		"same seed picks the same document")
