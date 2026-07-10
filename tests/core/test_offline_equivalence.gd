extends GutTest
## §12-2 most critical: offline batch calculation == realtime progression.
## Any divergence here is a progression-destroying bug.

const TOTAL_TICKS: int = 400
const SPLIT_TICK: int = 137


func _new_sim_with_work(rng_seed: int) -> UDSim:
	var sim := UDSim.new_game(UDTestFixtures.strata(0.5), rng_seed)
	# A column straight down plus side branches: enough work to keep
	# all three minions busy and consume RNG via document rolls.
	for y in range(1, 7):
		sim.add_dig_job(Vector2i(UD.DEPOT_POS.x, y))
	sim.add_dig_job(Vector2i(UD.DEPOT_POS.x - 1, 1))
	sim.add_dig_job(Vector2i(UD.DEPOT_POS.x + 1, 1))
	sim.add_dig_job(Vector2i(UD.DEPOT_POS.x + 1, 2))
	return sim


func _snapshot(sim: UDSim) -> String:
	return JSON.stringify(sim.to_dict())


func test_batch_advance_equals_tick_by_tick() -> void:
	var realtime := _new_sim_with_work(1234)
	var batch := _new_sim_with_work(1234)
	for i in TOTAL_TICKS:
		realtime.tick()
	batch.advance(TOTAL_TICKS)
	assert_eq(_snapshot(realtime), _snapshot(batch))


func test_save_load_midway_does_not_diverge() -> void:
	var continuous := _new_sim_with_work(9876)
	var interrupted := _new_sim_with_work(9876)

	continuous.advance(TOTAL_TICKS)

	interrupted.advance(SPLIT_TICK)
	# Simulate app kill + restart: serialize through actual JSON text.
	var json_text := JSON.stringify(interrupted.to_dict())
	var restored := UDSim.from_dict(JSON.parse_string(json_text), UDTestFixtures.strata(0.5))
	restored.advance(TOTAL_TICKS - SPLIT_TICK)

	assert_eq(_snapshot(continuous), _snapshot(restored))


func test_different_seeds_diverge() -> void:
	# Sanity check that the test itself has teeth: document rolls must
	# actually consume RNG, so different seeds should differ.
	var a := _new_sim_with_work(1)
	var b := _new_sim_with_work(2)
	a.advance(TOTAL_TICKS)
	b.advance(TOTAL_TICKS)
	assert_ne(_snapshot(a), _snapshot(b))
