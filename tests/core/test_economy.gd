extends GutTest
## Coin economy: hauled resources convert on deposit, old saves migrate,
## special finds (chests, nuggets) stay deterministic.


func test_dig_bags_loot_and_collect_converts() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	sim.dig_policy = UD.DigPolicy.NONE
	sim.add_dig_job(Vector2i(UD.DEPOT_POS.x, 1))
	sim.advance(30)
	assert_eq(int(sim.pending_loot.get(UD.RES_SOIL, 0)), 1, "loot bagged on the spot")
	var before := int(sim.inventory[UD.RES_GOLD])
	var tally := sim.collect_loot()
	assert_eq(int(tally["coins"]), int(UD.COIN_VALUES[UD.RES_SOIL]))
	assert_eq(int(sim.inventory[UD.RES_GOLD]), before + 1)
	assert_eq(sim.pending_loot_total(), 0, "bag emptied by the tally")
	assert_eq(int(sim.collect_loot()["coins"]), 0, "second tally pays nothing")


func test_pre_v3_hauling_minion_is_normalized() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	var d := sim.to_dict()
	var minion_dict: Dictionary = (d["minions"] as Array)[0]
	minion_dict["state"] = 3  # HAULING
	minion_dict["carrying"] = UD.RES_STONE
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata()
	)
	assert_eq(restored.minions[0].state, UDMinion.State.IDLE)
	assert_eq(restored.minions[0].carrying, "")
	assert_eq(int(restored.pending_loot.get(UD.RES_STONE, 0)), 1,
		"the hauled load went into the bag")


func test_v1_save_migrates_stockpiles_to_coins() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	var d := sim.to_dict()
	d["version"] = 1
	d["inventory"][UD.RES_SOIL] = 12
	d["inventory"][UD.RES_STONE] = 3
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata()
	)
	assert_eq(int(restored.inventory[UD.RES_SOIL]), 0)
	assert_eq(int(restored.inventory[UD.RES_STONE]), 0)
	assert_eq(int(restored.inventory[UD.RES_GOLD]),
		12 * int(UD.COIN_VALUES[UD.RES_SOIL]) + 3 * int(UD.COIN_VALUES[UD.RES_STONE]))


func test_v2_save_does_not_remigrate() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 7
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(int(restored.inventory[UD.RES_GOLD]), 7)


func test_items_survive_roundtrip() -> void:
	var pool: Array[String] = ["item_a", "item_b"]
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1, pool)
	sim.items["item_a"] = 1
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata(), pool
	)
	assert_eq(restored.items.size(), 1)
	assert_eq(int(restored.items["item_a"]), 1)


func test_special_finds_are_deterministic() -> void:
	var pool: Array[String] = ["item_a", "item_b", "item_c"]
	var a := UDSim.new_game(UDTestFixtures.strata(), 777, pool)
	var b := UDSim.new_game(UDTestFixtures.strata(), 777, pool)
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.DOWN
		sim.advance(600)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))
	for item_id: Variant in a.items.keys():
		assert_true(pool.has(item_id), "found items come from the pool")


func test_chest_with_empty_pool_pays_coins_without_crashing() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 777)
	sim.dig_policy = UD.DigPolicy.DOWN
	sim.advance(600)
	sim.collect_loot()
	assert_eq(sim.items.size(), 0, "no pool, no items")
	assert_true(int(sim.inventory[UD.RES_GOLD]) > 0)


func test_real_item_files_load_and_translate() -> void:
	var db := UDItemDB.load_from_dir("res://data/items")
	assert_eq(db.all_ids().size(), 5)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for id in db.all_ids():
		var item := db.get_item(id)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(item["name_key"]), item["name_key"])
			assert_ne(locale.text(item["desc_key"]), item["desc_key"])
