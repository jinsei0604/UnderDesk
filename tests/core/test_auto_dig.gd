extends GutTest
## §4: direction-level dig policies keep progress flowing without
## per-cell orders.


func test_policy_none_generates_no_jobs() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.advance(50)
	assert_eq(sim.jobs.size(), 0)
	assert_eq(int(sim.inventory[UD.RES_SOIL]), 0)


func test_policy_down_digs_unattended() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.dig_policy = UD.DigPolicy.DOWN
	var initial_height := sim.grid.height
	sim.advance(300)
	assert_gt(int(sim.inventory[UD.RES_SOIL]), 5, "resources flow without clicks")
	assert_gt(sim.grid.height, initial_height, "shaft keeps deepening")
	assert_false(sim.grid.is_walkable(Vector2i(0, 1)),
		"digging stays focused near the depot, not across the whole map")


func test_policy_widen_expands_deepest_gallery() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	# Hand-carve a 2-deep shaft below the depot first.
	sim.grid.set_terrain(Vector2i(UD.DEPOT_POS.x, 1), UD.Terrain.AIR)
	sim.grid.set_terrain(Vector2i(UD.DEPOT_POS.x, 2), UD.Terrain.AIR)
	sim.dig_policy = UD.DigPolicy.WIDEN
	sim.advance(200)
	var widened := (
		sim.grid.is_walkable(Vector2i(UD.DEPOT_POS.x - 1, 2))
		or sim.grid.is_walkable(Vector2i(UD.DEPOT_POS.x + 1, 2))
	)
	assert_true(widened, "deepest row grew sideways")
	assert_true(sim.grid.is_walkable(Vector2i(UD.DEPOT_POS.x, 1)),
		"widen policy does not dig downward")


func test_policy_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.strata(0.5), 99)
	var b := UDSim.new_game(UDTestFixtures.strata(0.5), 99)
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.DOWN
	a.advance(300)
	b.advance(300)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_stale_unreachable_jobs_do_not_starve_policy() -> void:
	# Regression: leftover designations on buried cells filled every job
	# slot, so DOWN policy never generated work and minions sat idle.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	for x in range(0, 9):
		assert_true(sim.add_dig_job(Vector2i(x, 3)), "buried cell designated")
	sim.dig_policy = UD.DigPolicy.DOWN
	sim.advance(100)
	assert_gt(int(sim.inventory[UD.RES_SOIL]), 0, "policy digs despite stale jobs")


func test_remove_dig_job() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.add_dig_job(Vector2i(5, 3))
	assert_true(sim.remove_dig_job(Vector2i(5, 3)))
	assert_eq(sim.jobs.size(), 0)
	assert_false(sim.remove_dig_job(Vector2i(5, 3)), "already removed")


func test_remove_dig_job_keeps_claimed_jobs() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	var target := Vector2i(UD.DEPOT_POS.x, 1)
	sim.add_dig_job(target)
	sim.advance(2)  # a minion claims and heads out
	assert_false(sim.remove_dig_job(target), "claimed job is not cancellable")


func test_policy_survives_save_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 5)
	sim.dig_policy = UD.DigPolicy.WIDEN
	sim.advance(20)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.dig_policy, UD.DigPolicy.WIDEN)


func test_pre_policy_save_defaults_to_none() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 5)
	var d := sim.to_dict()
	d.erase("dig_policy")
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata()
	)
	assert_eq(restored.dig_policy, UD.DigPolicy.NONE)
