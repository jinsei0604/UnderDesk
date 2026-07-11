extends GutTest
## Intruder raids (§5.2): resolved deterministically inside the tick,
## decided by traps built in advance, reported through the event log.
## The player is never asked to respond in realtime.


func _sim(rng_seed: int = 3) -> UDSim:
	return UDSim.new_game(UDTestFixtures.strata(), rng_seed)


func _trap_def() -> Dictionary:
	return {
		"id": "trap",
		"name_key": "ROOM_TRAP",
		"width": 2,
		"height": 1,
		"cost": {"gold": 60},
		"effect": "defense_add",
	}


func _build_trap(sim: UDSim, x: int) -> void:
	sim.inventory[UD.RES_GOLD] = int(sim.inventory.get(UD.RES_GOLD, 0)) + 60
	for dx in 2:
		sim.grid.set_terrain(Vector2i(x + dx, 1), UD.Terrain.AIR)
	assert_true(sim.build_room(_trap_def(), Vector2i(x, 1)), "trap built")


func test_no_raid_before_the_interval() -> void:
	var sim := _sim()
	sim.dig_policy = UD.DigPolicy.NONE
	sim.advance(100)
	assert_eq(sim.event_log.size(), 0)


func test_raid_fires_on_the_interval_and_is_logged() -> void:
	var sim := _sim()
	sim.dig_policy = UD.DigPolicy.NONE
	sim.tick_count = UD.INTRUDER_INTERVAL_TICKS - 1
	sim.advance(1)
	assert_eq(sim.event_log.size(), 1)
	var entry: Dictionary = sim.event_log[0]
	assert_eq(str(entry["kind"]), "intruder")
	assert_eq(int(entry["tick"]), UD.INTRUDER_INTERVAL_TICKS)
	assert_between(int(entry["strength"]),
		UD.INTRUDER_STRENGTH_MIN, UD.INTRUDER_STRENGTH_MAX)


func test_traps_raise_defense() -> void:
	var sim := _sim()
	assert_eq(sim.defense(), 0)
	_build_trap(sim, 2)
	_build_trap(sim, 6)
	assert_eq(sim.defense(), 2)


func test_full_defense_always_repels_and_pays_loot() -> void:
	var sim := _sim()
	sim.dig_policy = UD.DigPolicy.NONE
	for i in UD.INTRUDER_STRENGTH_MAX:
		_build_trap(sim, 2 + i * 3)
	var coins_before := int(sim.inventory[UD.RES_GOLD])
	sim.tick_count = UD.INTRUDER_INTERVAL_TICKS - 1
	sim.advance(1)
	var entry: Dictionary = sim.event_log[0]
	assert_true(bool(entry["repelled"]))
	assert_gt(int(entry["coins"]), 0)
	assert_eq(int(sim.inventory[UD.RES_GOLD]), coins_before + int(entry["coins"]))


func test_breach_never_steals_below_zero() -> void:
	var sim := _sim()
	sim.dig_policy = UD.DigPolicy.NONE
	sim.inventory[UD.RES_GOLD] = 5
	sim.tick_count = UD.INTRUDER_INTERVAL_TICKS - 1
	sim.advance(1)
	var entry: Dictionary = sim.event_log[0]
	assert_false(bool(entry["repelled"]), "no traps: strength >= 1 wins")
	assert_gte(int(sim.inventory[UD.RES_GOLD]), 0)
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 5 + int(entry["coins"]))


func test_log_is_capped() -> void:
	var sim := _sim()
	for i in UD.EVENT_LOG_MAX + 5:
		sim.tick_count = UD.INTRUDER_INTERVAL_TICKS * (i + 1)
		sim._check_intruder()
	assert_eq(sim.event_log.size(), UD.EVENT_LOG_MAX)
	assert_eq(
		int(sim.event_log[-1]["tick"]),
		UD.INTRUDER_INTERVAL_TICKS * (UD.EVENT_LOG_MAX + 5),
		"newest entry kept"
	)


func test_raids_are_deterministic() -> void:
	var a := _sim(17)
	var b := _sim(17)
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.DOWN
		sim.tick_count = UD.INTRUDER_INTERVAL_TICKS - 5
		sim.advance(10)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_event_log_survives_roundtrip() -> void:
	var sim := _sim()
	sim.tick_count = UD.INTRUDER_INTERVAL_TICKS
	sim._check_intruder()
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.event_log.size(), 1)
	assert_eq(restored.event_log[0], sim.event_log[0], "ints stay ints")


func test_old_saves_without_event_log_load_clean() -> void:
	var sim := _sim()
	var d := sim.to_dict()
	d.erase("event_log")
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata()
	)
	assert_eq(restored.event_log.size(), 0)


func test_trap_room_file_loads_and_translates() -> void:
	var rooms := UDRoomDB.load_from_dir("res://data/rooms")
	assert_true(rooms.has_room("trap"))
	var def := rooms.get_room("trap")
	assert_eq(str(def["effect"]), "defense_add")
	for code: String in UD.SUPPORTED_LOCALES:
		var locale := UDLocale.load_locale(code)
		assert_ne(locale.text(def["name_key"]), def["name_key"],
			"%s trap name translated" % code)
