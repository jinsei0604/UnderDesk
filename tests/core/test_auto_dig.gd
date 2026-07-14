extends GutTest
## §4: direction-level dig policies keep progress flowing without
## per-cell orders.


func test_new_game_defaults_to_right_policy() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	assert_eq(sim.dig_policy, UD.DigPolicy.RIGHT, "idle from minute one")


func test_policy_none_generates_no_jobs() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.dig_policy = UD.DigPolicy.NONE
	sim.advance(50)
	assert_eq(sim.jobs.size(), 0)
	assert_eq(int(sim.inventory[UD.RES_SOIL]), 0)


func test_policy_right_digs_unattended() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.dig_policy = UD.DigPolicy.RIGHT
	sim.advance(300)
	sim.collect_loot()
	assert_gt(int(sim.inventory[UD.RES_GOLD]), 5, "coins flow without clicks")


func test_policy_digs_rightward_as_a_corridor() -> void:
	# Per the reference image: one horizontal tunnel heading right. Every
	# row shares the same dug prefix — a full-height corridor, no pillars.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.dig_policy = UD.DigPolicy.RIGHT
	sim.advance(400)
	var dug_xs: Array[int] = []
	for x in sim.grid.width:
		if sim.grid.is_walkable(Vector2i(x, 1)):
			dug_xs.append(x)
	assert_gt(dug_xs.size(), 2, "corridor is being carved rightward")
	assert_eq(dug_xs[0], 0, "tunnel starts at the entrance")
	assert_eq(dug_xs[dug_xs.size() - 1], dug_xs.size() - 1,
		"corridor is contiguous from the entrance")


func test_policy_clears_columns_full_height() -> void:
	# The face column must be cleared top-to-bottom before advancing, so no
	# solid cell is ever left standing behind the tunnel front.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.dig_policy = UD.DigPolicy.RIGHT
	sim.advance(400)
	var frontier := sim.frontier_distance()
	# Every column left of the frontier is fully open (all rows dug).
	for x in frontier:
		for y in sim.grid.height:
			assert_true(sim.grid.is_walkable(Vector2i(x, y)),
				"no standing cell behind the tunnel face")


func test_policy_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.strata(0.5), 99)
	var b := UDSim.new_game(UDTestFixtures.strata(0.5), 99)
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.RIGHT
	a.advance(300)
	b.advance(300)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_stale_unreachable_jobs_do_not_starve_policy() -> void:
	# Regression: leftover designations on buried cells filled every job
	# slot, so the policy never generated work and minions sat idle.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	for y in sim.grid.height:
		assert_true(sim.add_dig_job(Vector2i(6, y)), "buried cell designated")
	sim.dig_policy = UD.DigPolicy.RIGHT
	sim.advance(100)
	sim.collect_loot()
	assert_gt(int(sim.inventory[UD.RES_GOLD]), 0, "policy digs despite stale jobs")


func test_remove_dig_job() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	sim.add_dig_job(Vector2i(5, 1))
	assert_true(sim.remove_dig_job(Vector2i(5, 1)))
	assert_eq(sim.jobs.size(), 0)
	assert_false(sim.remove_dig_job(Vector2i(5, 1)), "already removed")


func test_remove_dig_job_keeps_claimed_jobs() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 11)
	# The first solid cell at the tunnel mouth: reachable from the depot.
	var target := Vector2i(1, UD.DEPOT_POS.y)
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
