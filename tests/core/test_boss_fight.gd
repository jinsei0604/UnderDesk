extends GutTest
## Manual boss fights: a turn-based, player-initiated encounter at a gate
## stage. Idle auto-battle never resolves these (see test_auto_battle.gd);
## only start_boss_fight()/resolve_boss_round()/flee_boss_fight() do.


func _sim_at_gate(rng_seed: int = 11) -> UDSim:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), rng_seed)
	sim.stage_index = 5  # the fixture's gate stage
	return sim


func test_cannot_start_boss_fight_off_a_gate() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	assert_eq(sim.stage_index, 1, "not a gate stage")
	assert_false(sim.start_boss_fight())


func test_start_boss_fight_sets_boss_hp() -> void:
	var sim := _sim_at_gate()
	assert_true(sim.start_boss_fight())
	assert_true(sim.boss_active)
	assert_eq(sim.boss_hp, int(UDTestFixtures.enemies().get_enemy("test_boss")["hp"]))
	assert_false(sim.start_boss_fight(), "cannot start twice")


func test_auto_battle_does_not_run_during_a_boss_fight() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var exp_before := sim.exp_pool
	sim.advance(50)
	assert_eq(sim.exp_pool, exp_before, "idle loop is suspended mid-fight")
	assert_eq(sim.stage_index, 5, "stage does not advance mid-fight")


func test_flee_boss_fight_returns_to_farming() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	assert_true(sim.flee_boss_fight())
	assert_false(sim.boss_active)
	assert_false(sim.flee_boss_fight(), "nothing to flee")
	sim.advance(50)
	assert_gt(sim.exp_pool, 0, "back to idle-farming the gate")


func test_resolve_boss_round_attack_damages_boss() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var before := sim.boss_hp
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_lt(sim.boss_hp, before, "attack action reduces boss hp")


func test_winning_clears_the_gate_and_pays_rewards() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var exp_before := sim.exp_pool
	var result := {}
	for i in 20:
		if not sim.boss_active:
			break
		result = sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_true(result.get("won", false), "boss defeated within a reasonable number of rounds")
	assert_false(sim.boss_active)
	assert_eq(sim.stage_index, 6, "gate cleared, stage advances")
	assert_gt(sim.exp_pool, exp_before, "boss kill pays exp")


func test_boss_counterattacks_and_can_wipe_the_party_without_penalty() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	# Do nothing but survive rounds (no attack action submitted) until the
	# boss's counterattacks would wipe a fragile level-1 unit; the loss must
	# not soft-lock anything (retreat-and-heal).
	var result := {}
	for i in 30:
		result = sim.resolve_boss_round([])
		if result.get("lost", false):
			break
	assert_true(result.get("lost", false), "the boss can in fact wipe the party")
	assert_false(sim.boss_active, "retreat, not a stuck state")
	for unit in sim.minions:
		assert_eq(unit.hp, sim.unit_max_hp(unit), "party fully healed on retreat")
	assert_eq(sim.stage_index, 5, "still gated: the boss was not defeated")


func test_skill_action_costs_mp_and_damages_boss() -> void:
	var sim := _sim_at_gate()
	sim.companion_defs = [{
		"id": "c1", "name_key": "X", "join_at_docs": 0,
		"base_hp": 20, "hp_per_level": 4, "base_mp": 10, "mp_per_level": 2,
		"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
		"skills": ["test_skill"],
	}]
	sim.companions = ["c1"]
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.skills = UDTestFixtures.skills()
	sim.start_boss_fight()
	var mp_before := sim.minions[1].mp
	var boss_hp_before := sim.boss_hp
	sim.resolve_boss_round([{"unit_id": 1, "action": "skill", "skill_id": "test_skill"}])
	assert_lt(sim.minions[1].mp, mp_before, "skill consumed mp")
	assert_lt(sim.boss_hp, boss_hp_before, "skill damaged the boss")


func test_boss_round_is_deterministic() -> void:
	var a := _sim_at_gate(3)
	var b := _sim_at_gate(3)
	for sim: UDSim in [a, b]:
		sim.start_boss_fight()
		sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_boss_fight_survives_save_roundtrip() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		UDTestFixtures.enemies(), UDTestFixtures.stages()
	)
	assert_eq(restored.boss_active, sim.boss_active)
	assert_eq(restored.boss_hp, sim.boss_hp)
	assert_eq(restored.stage_index, sim.stage_index)


func test_level_up_companion_spends_exp_pool() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	var cost := UDSim.exp_cost_for_level(1)
	sim.exp_pool = cost - 1
	assert_false(sim.level_up_companion(0), "not enough banked exp")
	sim.exp_pool = cost
	assert_true(sim.level_up_companion(0))
	assert_eq(sim.minions[0].level, 2)
	assert_eq(sim.exp_pool, 0)
	assert_eq(sim.minions[0].hp, sim.unit_max_hp(sim.minions[0]), "healed on level up")


func test_level_up_companion_unknown_unit_fails() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	sim.exp_pool = 10000
	assert_false(sim.level_up_companion(99))
