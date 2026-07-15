extends GutTest
## Weapon shop: a single equipped slot (buying replaces, not stacks),
## leveled up with coins, contributing straight to party attack.


func test_starts_unarmed() -> void:
	var sim := UDSim.new_game(
		UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], [], {}, {},
		UDTestFixtures.skills(), UDTestFixtures.weapons()
	)
	assert_eq(sim.equipped_weapon_id, "")
	assert_eq(sim.weapon_level, 0)
	assert_eq(sim.weapon_atk_bonus(), 0)


func _sim_with_weapons() -> UDSim:
	return UDSim.new_game(
		UDTestFixtures.enemies(), UDTestFixtures.stages(), 1, [], [], {}, {},
		UDTestFixtures.skills(), UDTestFixtures.weapons()
	)


func test_buy_weapon_deducts_coins_and_equips_at_level_one() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 100
	assert_true(sim.buy_weapon("test_dagger"))
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 0)
	assert_eq(sim.equipped_weapon_id, "test_dagger")
	assert_eq(sim.weapon_level, 1)
	assert_eq(sim.weapon_atk_bonus(), 5)


func test_buy_weapon_rejects_insufficient_coins() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 50
	assert_false(sim.buy_weapon("test_dagger"))
	assert_eq(sim.equipped_weapon_id, "")


func test_buying_a_new_weapon_replaces_the_old_one() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 600
	sim.buy_weapon("test_dagger")
	assert_true(sim.buy_weapon("test_axe"))
	assert_eq(sim.equipped_weapon_id, "test_axe")
	assert_eq(sim.weapon_level, 1, "the new weapon starts fresh, not carrying the old level")


func test_rebuying_the_equipped_weapon_is_rejected() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 300
	sim.buy_weapon("test_dagger")
	assert_false(sim.buy_weapon("test_dagger"), "already equipped")


func test_upgrade_weapon_deducts_coins_and_raises_atk() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 200
	sim.buy_weapon("test_dagger")
	var atk_before := sim.weapon_atk_bonus()
	assert_true(sim.upgrade_weapon())
	assert_eq(sim.weapon_level, 2)
	assert_eq(sim.weapon_atk_bonus(), atk_before + 2, "atk_per_level applied")


func test_upgrade_weapon_fails_with_nothing_equipped() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 10000
	assert_false(sim.upgrade_weapon())


func test_upgrade_weapon_respects_max_level() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 10000
	sim.buy_weapon("test_dagger")
	sim.upgrade_weapon()
	sim.upgrade_weapon()
	assert_eq(sim.weapon_level, 3, "max_level 3")
	assert_false(sim.upgrade_weapon(), "already maxed")


func test_weapon_atk_feeds_party_atk_bonus() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 100
	var bonus_before := sim.party_atk_bonus()
	sim.buy_weapon("test_dagger")
	assert_eq(sim.party_atk_bonus(), bonus_before + 5)


func test_weapon_state_survives_save_roundtrip() -> void:
	var sim := _sim_with_weapons()
	sim.inventory[UD.RES_GOLD] = 200
	sim.buy_weapon("test_dagger")
	sim.upgrade_weapon()
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages(), [], [], {}, {},
		UDTestFixtures.skills(), UDTestFixtures.weapons()
	)
	assert_eq(restored.equipped_weapon_id, "test_dagger")
	assert_eq(restored.weapon_level, 2)


func test_pre_weapon_save_loads_unarmed() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 1)
	var d := sim.to_dict()
	(d as Dictionary).erase("equipped_weapon_id")
	(d as Dictionary).erase("weapon_level")
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(d)), UDTestFixtures.enemies(), UDTestFixtures.stages()
	)
	assert_eq(restored.equipped_weapon_id, "")
	assert_eq(restored.weapon_level, 0)


func test_weapon_files_load_and_translate() -> void:
	var db := UDShopDB.load_from_dir("res://data/weapons")
	assert_eq(db.all_ids().size(), 3)
	var ja := UDLocale.load_locale("ja")
	var en := UDLocale.load_locale("en")
	for id in db.all_ids():
		var weapon := db.get_good(id)
		assert_gt(int(weapon["buy_cost"]), 0)
		assert_gt(int(weapon["base_atk"]), 0)
		assert_gt(float(weapon["upgrade_cost_mult"]), 1.0)
		assert_gt(int(weapon["max_level"]), 0)
		for locale: UDLocale in [ja, en]:
			assert_ne(locale.text(weapon["name_key"]), weapon["name_key"])
			assert_ne(locale.text(weapon["desc_key"]), weapon["desc_key"])
