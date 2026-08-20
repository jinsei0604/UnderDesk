extends GutTest
## Idle auto-battle: trash mobs are cleared unattended, tick by tick,
## risk-free (no party HP loss), and the boss gate halts stage advance
## without stopping the reward flow.


func test_new_game_starts_at_stage_one() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	assert_eq(sim.stage_index, 1, "idle from minute one")


func test_auto_battle_pays_exp_and_coins_unattended() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	sim.advance(300)
	assert_gt(sim.exp_pool, 0, "exp flows without clicks")
	assert_gt(int(sim.inventory[UD.RES_GOLD]), 0, "coins flow without clicks")


func test_trash_combat_never_costs_party_hp() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	sim.advance(300)
	for unit in sim.minions:
		assert_eq(unit.hp, sim.unit_max_hp(unit), "idle trash combat is risk-free")


func test_stage_advances_past_a_non_gate_band() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	# Trash dies the tick after it spawns (tick 1 spawns, tick 2 kills and
	# clears a stage). 2 ticks lands mid-band, well short of the gate at
	# stage 5.
	sim.advance(2)
	assert_gt(sim.stage_index, 1, "stage advanced past the opening band")
	assert_lt(sim.stage_index, 5, "halted at the gate, not past it")


## RPG_SYSTEM_DESIGN_v5 §5.1: idle trash dies to one hit no matter its
## stats (real HP/DEF only matter in manual battles). A wall of HP/DEF
## far beyond the level-1 party must still fall one tick after spawning.
func test_idle_trash_dies_in_one_hit_regardless_of_stats() -> void:
	var enemies := UDEnemyDB.from_dicts([
		{"id": "test_trash", "name_key": "X", "hp": 1000, "atk": 1, "def": 999,
			"exp": 3, "coins": 2, "is_boss": false},
		{"id": "test_boss", "name_key": "X", "hp": 20, "atk": 3, "def": 1,
			"exp": 15, "coins": 10, "is_boss": true},
	])
	var sim := UDSim.new_game(enemies, UDTestFixtures.stages(), 11)
	sim.advance(2)
	assert_gt(sim.total_kills, 0, "hp 1000 def 999 trash still dies in one idle hit")


func test_boss_gate_halts_advance_but_keeps_farming() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	sim.advance(2000)
	assert_eq(sim.stage_index, 5, "auto-battle cannot clear the gate")
	var exp_at_gate := sim.exp_pool
	var gold_at_gate := int(sim.inventory[UD.RES_GOLD])
	sim.advance(200)
	assert_eq(sim.stage_index, 5, "still gated")
	assert_gt(sim.exp_pool, exp_at_gate, "trash keeps paying exp while gated")
	assert_gt(int(sim.inventory[UD.RES_GOLD]), gold_at_gate, "trash keeps paying coins while gated")


func test_total_kills_counts_every_trash_kill() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	assert_eq(sim.total_kills, 0, "no kills before the first tick")
	sim.advance(300)
	assert_gt(sim.total_kills, 0, "trash kills accumulate unattended")


func test_total_kills_survives_save_roundtrip() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	sim.advance(300)
	var restored := UDSim.from_dict(
		sim.to_dict(), UDTestFixtures.enemies(), UDTestFixtures.stages()
	)
	assert_eq(restored.total_kills, sim.total_kills, "kill count is not dig-era state")


func test_auto_battle_is_deterministic() -> void:
	var a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(0.5), 99)
	var b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(0.5), 99)
	a.advance(300)
	b.advance(300)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_document_discovery_is_deterministic() -> void:
	var sim_a := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7)
	var sim_b := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(1.0), 7)
	for sim: UDSim in [sim_a, sim_b]:
		sim.advance(30)
	assert_gt(sim_a.discovered_documents.size(), 0, "chance 1.0 always drops")
	assert_eq(sim_a.discovered_documents, sim_b.discovered_documents,
		"same seed picks the same document")
