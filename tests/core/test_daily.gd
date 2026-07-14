extends GutTest
## §5.4 / §12-5: the daily anomaly seed must be identical for every
## player and stable across engine versions.


func test_seed_is_stable_and_date_dependent() -> void:
	var a := UDDaily.seed_for_date_key("2026-07-11")
	var b := UDDaily.seed_for_date_key("2026-07-11")
	var c := UDDaily.seed_for_date_key("2026-07-12")
	assert_eq(a, b, "same date, same seed")
	assert_ne(a, c, "different date, different seed")
	assert_gt(a, 0)


func test_date_key_format() -> void:
	assert_eq(UDDaily.date_key({"year": 2026, "month": 7, "day": 5}), "2026-07-05")


func test_anomaly_pick_is_deterministic() -> void:
	var anomalies := UDDataLoader.load_json_dir("res://data/anomalies")
	assert_gt(anomalies.size(), 0)
	var first := UDDaily.anomaly_for_date_key(anomalies, "2026-07-11")
	var second := UDDaily.anomaly_for_date_key(anomalies, "2026-07-11")
	assert_eq(first["id"], second["id"])


func test_apply_daily_once_per_day() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	var anomaly := {"id": "gold_dust", "name_key": "X", "effect": "gold_per_kill"}
	assert_true(sim.apply_daily("2026-07-11", anomaly))
	assert_false(sim.apply_daily("2026-07-11", anomaly), "same day is a no-op")
	assert_true(sim.apply_daily("2026-07-12", anomaly), "next day applies")


func test_gold_per_kill_effect() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 42)
	sim.apply_daily("2026-07-11", {"id": "gold_dust", "name_key": "X", "effect": "gold_per_kill"})
	sim.advance(30)
	# Each kill: the enemy's own coin reward, +1 daily bonus.
	assert_true(int(sim.inventory[UD.RES_GOLD]) >= 2, "daily bonus paid on kill")


func test_atk_and_doc_chance_effects() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	sim.apply_daily("2026-07-11", {"id": "soft_earth", "name_key": "X", "effect": "atk_add"})
	assert_eq(sim.party_atk_bonus(), 1)
	sim.apply_daily("2026-07-12", {"id": "lush_vein", "name_key": "X", "effect": "doc_chance_add"})
	assert_eq(sim.party_atk_bonus(), 0, "yesterday's effect gone")
	assert_eq(sim.document_chance_bonus(), UD.DAILY_DOC_CHANCE_BONUS)


func test_daily_state_survives_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	sim.apply_daily("2026-07-11", {"id": "lush_vein", "name_key": "X", "effect": "doc_chance_add"})
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.enemies(), UDTestFixtures.stages()
	)
	assert_eq(restored.daily_date_key, "2026-07-11")
	assert_eq(restored.daily_anomaly_id, "lush_vein")
	assert_eq(restored.document_chance_bonus(), UD.DAILY_DOC_CHANCE_BONUS)
