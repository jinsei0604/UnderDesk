extends GutTest
## Coin economy: hauled resources convert on deposit, old saves migrate,
## special finds (chests, nuggets) stay deterministic.


func test_deposit_converts_soil_to_coins() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 42)
	sim.dig_policy = UD.DigPolicy.NONE
	sim.add_dig_job(Vector2i(UD.DEPOT_POS.x, 1))
	sim.advance(30)
	assert_eq(int(sim.inventory[UD.RES_SOIL]), 0, "raw soil is not stockpiled")
	assert_true(int(sim.inventory[UD.RES_GOLD]) >= 1, "deposit paid in coins")


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
	sim.items.append("item_a")
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata(), pool
	)
	assert_eq(restored.items.size(), 1)
	assert_eq(restored.items[0], "item_a")


func test_special_finds_are_deterministic() -> void:
	var pool: Array[String] = ["item_a", "item_b", "item_c"]
	var a := UDSim.new_game(UDTestFixtures.strata(), 777, pool)
	var b := UDSim.new_game(UDTestFixtures.strata(), 777, pool)
	for sim: UDSim in [a, b]:
		sim.dig_policy = UD.DigPolicy.DOWN
		sim.advance(600)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))
	for item_id in a.items:
		assert_true(pool.has(item_id), "found items come from the pool")


func test_chest_with_empty_pool_pays_coins_without_crashing() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 777)
	sim.dig_policy = UD.DigPolicy.DOWN
	sim.advance(600)
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
