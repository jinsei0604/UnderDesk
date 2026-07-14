extends GutTest
## Coin economy: kills pay coins immediately, special finds (chests,
## nuggets) stay deterministic.


func test_kill_pays_coins_immediately() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 42)
	var before := int(sim.inventory[UD.RES_GOLD])
	sim.advance(2)  # tick 1 spawns the trash, tick 2 kills it
	assert_gt(int(sim.inventory[UD.RES_GOLD]), before, "coins paid on kill, no collect step")


func test_v2_save_does_not_remigrate() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	sim.inventory[UD.RES_GOLD] = 7
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.enemies(), UDTestFixtures.stages()
	)
	assert_eq(int(restored.inventory[UD.RES_GOLD]), 7)


func test_items_survive_roundtrip() -> void:
	var pool: Array[String] = ["item_a", "item_b"]
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, pool)
	sim.items["item_a"] = 1
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.enemies(), UDTestFixtures.stages(), pool
	)
	assert_eq(restored.items.size(), 1)
	assert_eq(int(restored.items["item_a"]), 1)


func test_special_finds_are_deterministic() -> void:
	var pool: Array[String] = ["item_a", "item_b", "item_c"]
	var a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 777, pool)
	var b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 777, pool)
	for sim: UDSim in [a, b]:
		sim.advance(600)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))
	for item_id: Variant in a.items.keys():
		assert_true(pool.has(item_id), "found items come from the pool")


func test_chest_with_empty_pool_pays_coins_without_crashing() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 777)
	sim.advance(600)
	assert_eq(sim.items.size(), 0, "no pool, no items")
	assert_true(int(sim.inventory[UD.RES_GOLD]) > 0)


func test_real_item_files_load_and_translate() -> void:
	var db := UDItemDB.load_from_dir("res://data/items")
	assert_eq(db.all_ids().size(), 100)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for id in db.all_ids():
		var item := db.get_item(id)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(item["name_key"]), item["name_key"])
			assert_ne(locale.text(item["desc_key"]), item["desc_key"])
