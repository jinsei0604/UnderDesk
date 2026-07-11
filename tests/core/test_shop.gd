extends GutTest
## Shop upgrades: escalating coin costs, effects, and persistence.


func _pickaxe() -> Dictionary:
	return {
		"id": "pickaxe",
		"name_key": "SHOP_PICKAXE",
		"desc_key": "SHOP_PICKAXE_DESC",
		"base_cost": 100,
		"cost_mult": 2.0,
		"effect": "dig_power_add",
		"max_level": 2,
	}


func _hire() -> Dictionary:
	return {
		"id": "hire_minion",
		"name_key": "SHOP_HIRE",
		"desc_key": "SHOP_HIRE_DESC",
		"base_cost": 50,
		"cost_mult": 1.5,
		"effect": "minion_add",
		"max_level": 17,
	}


func test_cost_scales_per_level() -> void:
	assert_eq(UDSim.upgrade_cost(_hire(), 0), 50)
	assert_eq(UDSim.upgrade_cost(_hire(), 1), 75)
	assert_eq(UDSim.upgrade_cost(_pickaxe(), 2), 400)


func test_buy_rejects_insufficient_coins() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 99
	assert_false(sim.buy_upgrade(_pickaxe()))
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 99, "nothing charged")


func test_buy_deducts_and_applies_effect() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 300
	assert_true(sim.buy_upgrade(_pickaxe()))
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 200)
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER + 1)
	assert_true(sim.buy_upgrade(_pickaxe()))
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 0, "level 1 costs double")
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER + 2)


func test_max_level_enforced() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 10000
	assert_true(sim.buy_upgrade(_pickaxe()))
	assert_true(sim.buy_upgrade(_pickaxe()))
	assert_false(sim.buy_upgrade(_pickaxe()), "max level 2 reached")


func test_hire_spawns_minion() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 50
	var before := sim.minions.size()
	assert_true(sim.buy_upgrade(_hire()))
	assert_eq(sim.minions.size(), before + 1)


func test_upgrades_survive_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 1)
	sim.inventory[UD.RES_GOLD] = 300
	sim.buy_upgrade(_pickaxe())
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.upgrade_level("pickaxe"), 1)
	assert_eq(restored.dig_power(), UD.MINION_DIG_POWER + 1)


func test_shop_files_load_and_translate() -> void:
	var db := UDShopDB.load_from_dir("res://data/shop")
	assert_eq(db.all_ids().size(), 2, "hiring left the shop with the plan change")
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for id in db.all_ids():
		var good := db.get_good(id)
		assert_gt(int(good["base_cost"]), 0)
		assert_gt(float(good["cost_mult"]), 1.0)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(good["name_key"]), good["name_key"])
			assert_ne(locale.text(good["desc_key"]), good["desc_key"])
