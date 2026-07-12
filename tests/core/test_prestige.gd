extends GutTest
## §5.5: burying the shaft grants crystals, keeps the archive and the
## collection, and resets the run.


func _sim_at_depth(depth: int) -> UDSim:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 9)
	sim.dig_policy = UD.DigPolicy.NONE
	for y in range(1, depth + 1):
		sim._ensure_rows(y + 2)
		sim.grid.set_terrain(Vector2i(UD.DEPOT_POS.x, y), UD.Terrain.AIR)
	return sim


func _perma_pickaxe() -> Dictionary:
	return {
		"id": "perma_pickaxe",
		"name_key": "X",
		"desc_key": "X",
		"base_cost": 3,
		"cost_mult": 2.0,
		"effect": "dig_power_add",
		"max_level": 5,
	}


func _perma_start() -> Dictionary:
	return {
		"id": "perma_start",
		"name_key": "X",
		"desc_key": "X",
		"base_cost": 2,
		"cost_mult": 1.5,
		"effect": "start_coins",
		"max_level": 10,
	}


func test_gain_requires_depth() -> void:
	var shallow := UDSim.new_game(UDTestFixtures.strata(), 9)
	assert_eq(shallow.prestige_gain(), 0)
	assert_false(shallow.can_prestige())
	var deep := _sim_at_depth(UD.PRESTIGE_MIN_DEPTH)
	assert_eq(deep.prestige_gain(), 1, "one crystal at the threshold")
	assert_eq(_sim_at_depth(UD.PRESTIGE_MIN_DEPTH + 3).prestige_gain(), 4)


func test_reset_carries_the_permanent_and_drops_the_run() -> void:
	var old := _sim_at_depth(UD.PRESTIGE_MIN_DEPTH + 3)
	old.crystals = 2
	old.discovered_documents.append("doc_001")
	old.items["item_a"] = 1
	old.inventory[UD.RES_GOLD] = 500
	old.upgrades["pickaxe"] = {"level": 2, "effect": "dig_power_add"}
	old.rooms.append({"id": "dorm", "pos": Vector2i(5, 1), "effect": "minion_add"})

	var fresh := UDSim.prestige_reset(old, UDTestFixtures.strata(), ["item_a", "item_b"])

	assert_eq(fresh.crystals, 2 + 4, "old crystals plus the new gain")
	assert_eq(fresh.resets, 1)
	assert_eq(fresh.discovered_documents, ["doc_001"], "archive persists (§5.5)")
	assert_eq(fresh.items.size(), 1, "collection persists")
	assert_eq(fresh.grid.height, UD.GRID_INITIAL_HEIGHT, "fresh shaft")
	assert_eq(int(fresh.inventory[UD.RES_GOLD]), 0, "coins reset")
	assert_eq(fresh.upgrades.size(), 0, "shop upgrades are run-scoped")
	assert_eq(fresh.rooms.size(), 0, "rooms are run-scoped")
	assert_eq(fresh.dig_policy, old.dig_policy, "policy preference kept")


func test_reset_is_deterministic() -> void:
	var a := _sim_at_depth(15)
	var b := _sim_at_depth(15)
	var fresh_a := UDSim.prestige_reset(a, UDTestFixtures.strata())
	var fresh_b := UDSim.prestige_reset(b, UDTestFixtures.strata())
	fresh_a.advance(100)
	fresh_b.advance(100)
	assert_eq(JSON.stringify(fresh_a.to_dict()), JSON.stringify(fresh_b.to_dict()))


func test_buy_perma_and_effects() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 9)
	sim.crystals = 1
	assert_false(sim.buy_perma(_perma_pickaxe()), "cannot afford")
	sim.crystals = 3
	assert_true(sim.buy_perma(_perma_pickaxe()))
	assert_eq(sim.crystals, 0)
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER + 1)


func test_start_coins_perma_applies_on_reset() -> void:
	var old := _sim_at_depth(UD.PRESTIGE_MIN_DEPTH)
	old.crystals = 5
	assert_true(old.buy_perma(_perma_start()))
	var fresh := UDSim.prestige_reset(old, UDTestFixtures.strata())
	assert_eq(int(fresh.inventory[UD.RES_GOLD]), UD.PRESTIGE_START_COINS_PER_LEVEL)


func test_prestige_state_survives_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 9)
	sim.crystals = 7
	sim.resets = 2
	sim.perma["perma_pickaxe"] = {"level": 3, "effect": "dig_power_add"}
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.crystals, 7)
	assert_eq(restored.resets, 2)
	assert_eq(restored.perma_level("perma_pickaxe"), 3)
	assert_eq(restored.dig_power(), UD.MINION_DIG_POWER + 3)


func test_prestige_data_files_load() -> void:
	var db := UDShopDB.load_from_dir("res://data/prestige")
	assert_eq(db.all_ids().size(), 3)
	var ja := UDLocale.load_locale("ja")
	for id in db.all_ids():
		var good := db.get_good(id)
		assert_ne(ja.text(good["name_key"]), good["name_key"], "%s translated" % id)
