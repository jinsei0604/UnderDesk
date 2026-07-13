extends GutTest
## Facilities (altar/tavern/dorm) are one-time unlocks bought via the
## shared "upgrades" ledger (§ plan change 2026-07-13: no map placement
## — they used to be placeable rooms, see test_v5_room_migrates_to_upgrade
## for the save-compat story).


func _dorm_def() -> Dictionary:
	return {
		"id": "dorm", "name_key": "ROOM_DORM", "desc_key": "FACILITY_DORM_DESC",
		"base_cost": 25, "cost_mult": 1.0, "effect": "", "max_level": 1,
	}


func _tavern_def() -> Dictionary:
	return {
		"id": "tavern", "name_key": "ROOM_TAVERN", "desc_key": "FACILITY_GUILD_DESC",
		"base_cost": 40, "cost_mult": 1.0, "effect": "dig_power_add", "max_level": 1,
	}


func _altar_def() -> Dictionary:
	return {
		"id": "altar", "name_key": "ROOM_ALTAR", "desc_key": "FACILITY_ALTAR_DESC",
		"base_cost": 80, "cost_mult": 1.0, "effect": "doc_chance_add", "max_level": 1,
	}


func test_dorm_unlock_costs_coins_and_spawns_no_worker() -> void:
	# Plan change: companions join through the story, so the dorm is
	# flavor only and must not spawn workers.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	sim.inventory[UD.RES_GOLD] = 25
	var before := sim.minions.size()
	assert_true(sim.buy_upgrade(_dorm_def()))
	assert_eq(sim.minions.size(), before, "no worker spawned")
	assert_eq(int(sim.inventory[UD.RES_GOLD]), 0, "cost deducted")
	assert_true(sim.dorm_built())


func test_unlock_rejects_insufficient_coins() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	sim.inventory[UD.RES_GOLD] = 24
	assert_false(sim.buy_upgrade(_dorm_def()))
	assert_false(sim.dorm_built())


func test_unlock_is_one_time_only() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	sim.inventory[UD.RES_GOLD] = 1000
	assert_true(sim.buy_upgrade(_altar_def()))
	assert_false(sim.buy_upgrade(_altar_def()), "max_level 1: no second purchase")


func test_guild_unlock_adds_dig_power() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER)
	assert_false(sim.guild_built())
	sim.inventory[UD.RES_GOLD] = 40
	assert_true(sim.buy_upgrade(_tavern_def()))
	assert_true(sim.guild_built())
	assert_eq(sim.dig_power(), UD.MINION_DIG_POWER + 1)
	# The bonus must survive a save/load cycle.
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.dig_power(), UD.MINION_DIG_POWER + 1)
	assert_true(restored.guild_built())


func test_altar_unlock_raises_document_chance() -> void:
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	assert_eq(sim.document_chance_bonus(), 0.0)
	assert_false(sim.altar_built())
	sim.inventory[UD.RES_GOLD] = 80
	assert_true(sim.buy_upgrade(_altar_def()))
	assert_true(sim.altar_built())
	assert_eq(sim.document_chance_bonus(), UD.UPGRADE_DOC_CHANCE)
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())), UDTestFixtures.strata()
	)
	assert_eq(restored.document_chance_bonus(), UD.UPGRADE_DOC_CHANCE)
	assert_true(restored.altar_built())


func test_v5_room_migrates_to_upgrade() -> void:
	# Pre-2026-07-13 saves recorded altar/tavern/dorm as placed rooms
	# (an array of {id, pos, effect}). Loading one must carry the
	# unlock over as a level-1 upgrade instead of losing it silently.
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	var d := sim.to_dict()
	d["version"] = 5
	d["rooms"] = [
		{"id": "altar", "pos": [5, 1], "effect": "doc_chance_add"},
		{"id": "tavern", "pos": [7, 1], "effect": "dig_power_add"},
	]
	var restored := UDSim.from_dict(JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata())
	assert_true(restored.altar_built())
	assert_true(restored.guild_built())
	assert_false(restored.dorm_built(), "dorm was never in this old save")
	assert_eq(restored.document_chance_bonus(), UD.UPGRADE_DOC_CHANCE)
	assert_eq(restored.dig_power(), UD.MINION_DIG_POWER + 1)


func test_v5_room_migration_does_not_override_existing_upgrade() -> void:
	# Defensive: if a future re-save already has the upgrade recorded,
	# the legacy rooms array must not clobber it (e.g. reset a level).
	var sim := UDSim.new_game(UDTestFixtures.strata(), 3)
	var d := sim.to_dict()
	d["version"] = 5
	d["upgrades"] = {"altar": {"level": 1, "effect": "doc_chance_add"}}
	d["rooms"] = [{"id": "altar", "pos": [5, 1], "effect": "doc_chance_add"}]
	var restored := UDSim.from_dict(JSON.parse_string(JSON.stringify(d)), UDTestFixtures.strata())
	assert_eq(restored.upgrade_level("altar"), 1, "no double-application")
