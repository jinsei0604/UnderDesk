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


## 新企画v1 §10 (2026-08-18): a party wipe no longer ends the encounter —
## the sim rewinds itself back to the fight's own checkpoint (captured by
## start_boss_fight()) and the same attempt simply restarts. This replaces
## the pre-REWIND "retreat and heal" behavior this test used to check.
func test_boss_counterattacks_and_wipe_triggers_automatic_rewind() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var boss_hp_at_start := sim.boss_hp
	# Do nothing but survive rounds (no attack action submitted) until the
	# boss's counterattacks would wipe a fragile level-1 unit. Bound
	# comfortably covers even a 1-damage-per-round floor (maxi(1, atk-def))
	# against the post-2026-07-19 Lv1 HP baseline (protagonist 50, see
	# constants.gd).
	var result := {}
	for i in 60:
		result = sim.resolve_boss_round([])
		if result.get("lost", false):
			break
	assert_true(result.get("lost", false), "the boss can in fact wipe the party")
	assert_true(result.get("rewound", false), "a wipe is reported as a rewind, not a retreat")
	assert_true(sim.boss_active, "REWIND restarts the same fight, it does not leave it")
	for unit in sim.minions:
		assert_eq(unit.hp, sim.unit_max_hp(unit), "party restored to checkpoint (full) hp")
	assert_eq(sim.boss_hp, boss_hp_at_start, "boss hp restored to checkpoint too")
	assert_eq(sim.stage_index, 5, "still gated: the boss was not defeated")


func test_skill_action_costs_sp_and_damages_boss() -> void:
	var sim := _sim_at_gate()
	sim.companion_defs = [{
		"id": "c1", "name_key": "X", "join_at_docs": 0,
		"base_hp": 20, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 2,
		"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
		"skills": ["test_skill"],
	}]
	sim.companions = ["c1"]
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.skills = UDTestFixtures.skills()
	sim.start_boss_fight()
	var sp_before := sim.minions[1].sp
	var boss_hp_before := sim.boss_hp
	sim.resolve_boss_round([{"unit_id": 1, "action": "skill", "skill_id": "test_skill"}])
	assert_lt(sim.minions[1].sp, sp_before, "skill consumed sp")
	assert_lt(sim.boss_hp, boss_hp_before, "skill damaged the boss")


## An ally-target heal skill must heal whichever ally was chosen, not
## default to healing the caster (2026-07-19: ally target selection).
func test_ally_target_heal_skill_heals_chosen_ally_not_the_caster() -> void:
	var sim := _sim_at_gate()
	sim.companion_defs = [{
		"id": "c1", "name_key": "X", "join_at_docs": 0,
		"base_hp": 20, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 2,
		"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
		"skills": ["test_heal_skill"],
	}]
	sim.companions = ["c1"]
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.skills = UDTestFixtures.skills()
	sim.start_boss_fight()
	# Damaged AFTER start_boss_fight() (新企画v1 §10, 2026-08-18): it now
	# heals the party to full as part of capturing the REWIND checkpoint,
	# so setting this before the call would just get healed away again.
	sim.minions[0].hp = 1  # protagonist badly hurt; caster (unit 1) is full
	var protagonist_hp_before := sim.minions[0].hp
	var caster_hp_before := sim.minions[1].hp
	sim.resolve_boss_round(
		[{"unit_id": 1, "action": "skill", "skill_id": "test_heal_skill", "target_id": 0}])
	assert_gt(sim.minions[0].hp, protagonist_hp_before, "chosen ally target was healed")
	assert_eq(sim.minions[1].hp, caster_hp_before, "caster itself was not healed instead")


## The battle motion sequencer (main.gd, 2026-07-19) reads resolve_boss_round's
## "log" to know what each character's animation should show — a real
## per-action amount, not just "the round happened".
func test_resolve_boss_round_log_reports_attack_amount() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var boss_hp_before := sim.boss_hp
	var result := sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	var log: Array = result["log"]
	assert_eq(log.size(), 1)
	var entry: Dictionary = log[0]
	assert_eq(int(entry["unit_id"]), 0)
	assert_eq(str(entry["action"]), "attack")
	assert_eq(str(entry["effect"]), "damage")
	assert_eq(str(entry["target_type"]), "enemy")
	assert_eq(int(entry["amount"]), boss_hp_before - sim.boss_hp)


func test_resolve_boss_round_log_reports_skill_amount_and_target() -> void:
	var sim := _sim_at_gate()
	sim.companion_defs = [{
		"id": "c1", "name_key": "X", "join_at_docs": 0,
		"base_hp": 20, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 2,
		"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
		"skills": ["test_skill"],
	}]
	sim.companions = ["c1"]
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.skills = UDTestFixtures.skills()
	sim.start_boss_fight()
	var boss_hp_before := sim.boss_hp
	var result := sim.resolve_boss_round(
		[{"unit_id": 1, "action": "skill", "skill_id": "test_skill"}])
	var log: Array = result["log"]
	assert_eq(log.size(), 1)
	var entry: Dictionary = log[0]
	assert_eq(int(entry["unit_id"]), 1)
	assert_eq(str(entry["skill_id"]), "test_skill")
	assert_eq(str(entry["effect"]), "damage")
	assert_eq(str(entry["target_type"]), "enemy")
	assert_eq(int(entry["amount"]), boss_hp_before - sim.boss_hp)


## A heal skill with no "power" set (RPG_SYSTEM_DESIGN_v5 numbers pending,
## see CLAUDE.md) must still visibly heal something instead of silently
## doing nothing — same floor idea as the pre-existing damage-vs-defense
## floor, applied to the heal side (2026-07-19). Checked against the log's
## amount rather than the healed unit's final hp: that unit is also hurt
## (hp 1) and therefore the boss's own counter-attack target this same
## round (see _boss_target — lowest hp), so its post-round hp reflects the
## heal AND the counter, not the heal alone. That interaction is correct
## behavior, not something this test should be confounded by.
func test_heal_skill_without_power_still_heals_a_floor_amount() -> void:
	var sim := _sim_at_gate()
	sim.companion_defs = [{
		"id": "c1", "name_key": "X", "join_at_docs": 0,
		"base_hp": 20, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 2,
		"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
		"skills": ["test_heal_skill_no_power"],
	}]
	sim.companions = ["c1"]
	sim.minions.append(sim._new_unit_at_level(1, 1))
	sim.skills = UDTestFixtures.skills()
	sim.start_boss_fight()
	# Damaged AFTER start_boss_fight() (新企画v1 §10, 2026-08-18): it now
	# heals the party to full as part of capturing the REWIND checkpoint,
	# so setting this before the call would just get healed away again.
	sim.minions[0].hp = 1
	var result := sim.resolve_boss_round(
		[{"unit_id": 1, "action": "skill", "skill_id": "test_heal_skill_no_power", "target_id": 0}])
	var entry: Dictionary = result["log"][0]
	assert_eq(str(entry["effect"]), "heal")
	assert_gte(int(entry["amount"]), 1, "unset power still heals at least 1 hp")


func test_boss_round_log_is_deterministic() -> void:
	var a := _sim_at_gate(3)
	var b := _sim_at_gate(3)
	var results: Array = []
	for sim: UDSim in [a, b]:
		sim.start_boss_fight()
		results.append(sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}]))
	assert_eq(JSON.stringify(results[0]["log"]), JSON.stringify(results[1]["log"]))


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
	assert_eq(restored.boss_enemy_id, sim.boss_enemy_id)
	assert_eq(restored.stage_index, sim.stage_index)


func _win_fight(sim: UDSim) -> Dictionary:
	var result := {}
	for i in 20:
		if not sim.boss_active:
			break
		result = sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	return result


func test_cleared_gate_boss_can_be_rematched() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	_win_fight(sim)
	assert_eq(sim.stage_index, 6, "gate cleared")
	assert_true(sim.start_boss_fight(), "rematch opens past the gate")
	assert_eq(sim.boss_enemy_id, "test_boss", "rematch targets the cleared gate's boss")
	assert_eq(sim.boss_hp, int(UDTestFixtures.enemies().get_enemy("test_boss")["hp"]),
		"boss hp resets for the rematch")


func test_rematch_win_pays_rewards_but_does_not_advance() -> void:
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	_win_fight(sim)
	var exp_before := sim.exp_pool
	sim.start_boss_fight()
	var result := _win_fight(sim)
	assert_true(result.get("won", false))
	assert_eq(sim.stage_index, 6, "rematch never advances the stage")
	assert_gt(sim.exp_pool, exp_before, "rematch still pays rewards")
	assert_true(sim.start_boss_fight(), "and can be fought again indefinitely")


func test_no_rematch_before_reaching_any_gate() -> void:
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11)
	assert_eq(sim.stage_index, 1)
	assert_false(sim.start_boss_fight(), "no gate at or below stage 1")


func test_rematch_is_deterministic() -> void:
	var a := _sim_at_gate(3)
	var b := _sim_at_gate(3)
	for sim: UDSim in [a, b]:
		sim.start_boss_fight()
		_win_fight(sim)
		sim.start_boss_fight()
		sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_pre_rematch_save_mid_fight_derives_boss_id() -> void:
	# A save written before boss_enemy_id existed can be mid-fight at a
	# gate; loading it must recover which boss is being fought.
	var sim := _sim_at_gate()
	sim.start_boss_fight()
	var d: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	d.erase("boss_enemy_id")
	var restored := UDSim.from_dict(d, UDTestFixtures.enemies(), UDTestFixtures.stages())
	assert_true(restored.boss_active)
	assert_eq(restored.boss_enemy_id, "test_boss", "derived from the gate band")


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


## --- REWIND + body-part destruction (新企画v1 §8/§10, 2026-08-18) -------
## A local enemy/stage db (rather than UDTestFixtures.enemies()) so these
## tests don't disturb the "test_boss" shape every test above depends on.

func _enemies_with_parted_boss() -> UDEnemyDB:
	return UDEnemyDB.from_dicts([
		{"id": "test_trash", "name_key": "X", "hp": 4, "atk": 1, "def": 0,
			"exp": 3, "coins": 2, "is_boss": false},
		{"id": "test_parted_boss", "name_key": "X", "hp": 40, "atk": 3, "def": 0,
			"exp": 15, "coins": 10, "is_boss": true,
			"parts": [{"id": "tail", "hp": 6}],
			"actions": [{"id": "sweep", "power": 20, "requires_part_intact": "tail"}],
		},
	])


func _stages_with_parted_boss() -> UDStageDB:
	return UDStageDB.from_dicts([
		{"id": "test_band", "name_key": "X", "stage_from": 1, "stage_to": 4,
			"trash_pool": ["test_trash"], "boss_id": "", "documents": [], "document_chance": 0.0},
		{"id": "test_gate", "name_key": "X", "stage_from": 5, "stage_to": 5,
			"trash_pool": ["test_trash"], "boss_id": "test_parted_boss",
			"documents": [], "document_chance": 0.0},
	])


func _sim_with_parted_boss(rng_seed: int = 11) -> UDSim:
	var sim := UDSim.new_game(_enemies_with_parted_boss(), _stages_with_parted_boss(), rng_seed)
	sim.stage_index = 5
	return sim


func test_start_boss_fight_initializes_part_hp_and_a_checkpoint() -> void:
	var sim := _sim_with_parted_boss()
	assert_true(sim.start_boss_fight())
	assert_eq(sim.boss_part_hp, {"tail": 6})
	assert_true(sim.boss_parts_destroyed.is_empty())
	assert_false(sim.boss_checkpoint.is_empty())


func test_part_targeted_attack_reduces_the_parts_own_pool_not_boss_hp() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	var boss_hp_before := sim.boss_hp
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	assert_eq(sim.boss_hp, boss_hp_before, "part damage does not touch the main hp pool")
	assert_lt(int(sim.boss_part_hp["tail"]), 6, "the part itself took the damage")


## protagonist atk 5 - part def 0 floors at 5/round; tail hp 6, so 2
## rounds destroy it. Destroying it removes "sweep" (requires_part_
## intact: "tail") from the boss's own candidate list THIS SAME round,
## so round 2's own counter-attack already falls back to flat "attack".
func test_destroying_a_part_removes_its_gated_action_and_records_intel() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	var mid_counter: Dictionary = sim.resolve_boss_round(
		[{"unit_id": 0, "action": "attack", "target_part": "tail"}])["boss_counter"]
	assert_true(sim.boss_parts_destroyed.has("tail"))
	assert_eq(int(sim.boss_part_hp["tail"]), 0)
	assert_eq(str(mid_counter["action_id"]), "attack", "gated action dropped the moment the part died")
	var intel: Dictionary = sim.boss_intel.get("test_parted_boss", {})
	assert_true((intel.get("parts_destroyed_seen", []) as Array).has("tail"))
	# And stays gone every subsequent round, not just the one it broke in.
	var result := sim.resolve_boss_round([])
	assert_eq(str(result["boss_counter"]["action_id"]), "attack")


func test_manual_rewind_restores_checkpoint_state_mid_fight() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	var hp_at_start := sim.minions[0].hp
	var boss_hp_at_start := sim.boss_hp
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])  # destroys it
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])  # dents boss_hp too
	assert_lt(sim.minions[0].hp, hp_at_start)
	assert_lt(sim.boss_hp, boss_hp_at_start)
	assert_true(sim.boss_parts_destroyed.has("tail"))
	assert_true(sim.rewind_boss_fight())
	assert_eq(sim.minions[0].hp, hp_at_start, "hp restored to the checkpoint")
	assert_eq(sim.boss_hp, boss_hp_at_start, "boss hp restored to the checkpoint")
	assert_eq(int(sim.boss_part_hp["tail"]), 6, "part hp restored to the checkpoint")
	assert_true(sim.boss_parts_destroyed.is_empty(), "the part itself comes back on rewind")
	assert_true(sim.boss_active, "REWIND restarts the fight, it does not exit the encounter")


## 新企画v1仕様書 v2 §11/§29-12 (2026-08-20): REWIND is scoped to the fight
## itself — every permanent-progress field a real playthrough would care
## about (level, exp bank, coins, discovered documents) must come through
## a manual REWIND completely untouched, not just "close enough".
func test_manual_rewind_does_not_touch_permanent_progress() -> void:
	var sim := _sim_at_gate()
	sim.exp_pool = 500
	sim.inventory["gold"] = 120
	sim.discovered_documents.append("doc_test")
	sim.start_boss_fight()
	assert_true(sim.level_up_companion(0), "spend some of the exp bank mid-fight")
	var level_after_levelup := sim.minions[0].level
	var exp_after_levelup := sim.exp_pool
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_true(sim.rewind_boss_fight())
	assert_eq(sim.minions[0].level, level_after_levelup, "level-ups are permanent, not fight state")
	assert_eq(sim.exp_pool, exp_after_levelup, "the exp bank does not roll back with the fight")
	assert_eq(int(sim.inventory["gold"]), 120, "coins are untouched by REWIND")
	assert_eq(sim.discovered_documents.size(), 1, "docs are untouched by REWIND")
	assert_true(sim.discovered_documents.has("doc_test"))


## The one thing REWIND does NOT undo (新企画v1 §12): what the player has
## learned about this boss survives even though the part itself came back.
func test_boss_intel_is_not_reset_by_rewind() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	assert_true(sim.boss_parts_destroyed.has("tail"))
	sim.rewind_boss_fight()
	assert_true(sim.boss_parts_destroyed.is_empty(), "the part itself comes back on rewind")
	var intel: Dictionary = sim.boss_intel.get("test_parted_boss", {})
	assert_true((intel.get("parts_destroyed_seen", []) as Array).has("tail"),
		"but the knowledge that it CAN be destroyed persists")


func test_party_wipe_preserves_boss_intel_across_the_automatic_rewind() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	assert_true(sim.boss_parts_destroyed.has("tail"))
	# Force a wipe deterministically (the fallback counter alone won't
	# reliably do it) rather than grinding rounds out.
	sim.minions[0].hp = 1
	var result := sim.resolve_boss_round([])
	assert_true(result.get("lost", false))
	assert_true(result.get("rewound", false))
	var intel: Dictionary = sim.boss_intel.get("test_parted_boss", {})
	assert_true((intel.get("parts_destroyed_seen", []) as Array).has("tail"),
		"knowledge survives the automatic rewind on wipe too")


func test_boss_action_choice_is_deterministic() -> void:
	var a := _sim_with_parted_boss(3)
	var b := _sim_with_parted_boss(3)
	for sim: UDSim in [a, b]:
		sim.start_boss_fight()
		sim.resolve_boss_round([])
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_boss_fight_with_parts_survives_save_roundtrip() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		_enemies_with_parted_boss(), _stages_with_parted_boss()
	)
	assert_eq(restored.boss_part_hp, sim.boss_part_hp)
	assert_eq(restored.boss_parts_destroyed, sim.boss_parts_destroyed)
	# Not a JSON.stringify comparison here: the checkpoint's own nested
	# numbers go through a real JSON round-trip (this call) and come back
	# as floats where they started as ints (the usual Godot JSON quirk —
	# rewind_boss_fight() below already re-casts everything with int()/str()
	# when it actually reads the checkpoint back out, so this only needs
	# to confirm the blob itself survived, not its raw numeric formatting;
	# see test_rewind_after_save_roundtrip_still_restores_the_checkpoint
	# for proof it still functions correctly after this same round-trip).
	assert_false(restored.boss_checkpoint.is_empty())
	assert_eq(JSON.stringify(restored.boss_intel), JSON.stringify(sim.boss_intel))


func test_rewind_after_save_roundtrip_still_restores_the_checkpoint() -> void:
	var sim := _sim_with_parted_boss()
	sim.start_boss_fight()
	var hp_at_start := sim.minions[0].hp
	sim.resolve_boss_round([{"unit_id": 0, "action": "attack", "target_part": "tail"}])
	var restored := UDSim.from_dict(
		JSON.parse_string(JSON.stringify(sim.to_dict())),
		_enemies_with_parted_boss(), _stages_with_parted_boss()
	)
	assert_lt(restored.minions[0].hp, hp_at_start)
	assert_true(restored.rewind_boss_fight())
	assert_eq(restored.minions[0].hp, hp_at_start, "checkpoint still works after a save roundtrip")


## 新企画v1仕様書 v2 §17 (2026-08-21 playtest-fix round): the tests above all
## use a synthetic "test_parted_boss" fixture — this one instead loads the
## REAL data/enemies + data/stages off disk, the exact content the actual
## cave_troll playtest exercises, to catch data-entry mistakes (wrong part
## id, requires_part_intact pointing at a part that doesn't exist, etc.)
## the synthetic fixture can't. Doesn't try to grind the arm's 180 HP down
## via real combat math (that depends on live party stats this test
## shouldn't need to hardcode/re-derive, and risks an unrelated party
## wipe/auto-REWIND mid-grind) — one real hit proves damage routing and
## gating work, then the "already destroyed" state is set directly to
## exercise the rest of the mechanic against real data quickly.
func test_cave_troll_real_data_body_part_and_gated_action_end_to_end() -> void:
	var enemies := UDEnemyDB.load_from_dir("res://data/enemies")
	var stages := UDStageDB.load_from_dir("res://data/stages")
	var sim := UDSim.new_game(enemies, stages, 11)
	sim.stage_index = 10  # gate_10 (data/stages/020_gate10.json), cave_troll's gate
	assert_true(sim.start_boss_fight())
	assert_eq(sim.boss_enemy_id, "cave_troll")
	assert_eq(sim.boss_hp, 600)
	assert_eq(int(sim.boss_part_hp["arm"]), 180)
	assert_eq(int(sim.boss_part_hp["leg"]), 220)
	assert_false(sim.boss_parts_destroyed.has("arm"))

	# §8/§12: attacking the arm damages ONLY the arm's own pool.
	var boss_hp_before := sim.boss_hp
	var result := sim.resolve_boss_round(
		[{"unit_id": 0, "action": "attack", "target_part": "arm"}])
	assert_lt(int(sim.boss_part_hp["arm"]), 180, "the arm actually took damage")
	assert_eq(sim.boss_hp, boss_hp_before, "part damage never touches boss_hp")
	# §11: while the arm is intact, club_smash (its only requires_part_
	# intact: "arm" gated action) is the sole real candidate every round —
	# deterministically always chosen ("強力な棍棒攻撃を使用可能").
	assert_eq(str(result["boss_counter"]["action_id"]), "club_smash")

	# Skip straight to "the arm was already destroyed this attempt" — see
	# this function's doc comment for why the grind itself is out of scope
	# here.
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")

	# §11: with the arm gone, club_smash drops out of the boss's real
	# candidate list — falls back to its flat atk, deterministically.
	result = sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_eq(str(result["boss_counter"]["action_id"]), "attack",
		"club_smash is unavailable now that its required part is destroyed")

	# §13: REWIND restores the real checkpoint captured at start_boss_
	# fight() — hp/arm/leg/available-action all the way back to fight
	# start, using data actually loaded off disk.
	assert_true(sim.rewind_boss_fight())
	assert_eq(sim.boss_hp, 600)
	assert_eq(int(sim.boss_part_hp["arm"]), 180)
	assert_eq(int(sim.boss_part_hp["leg"]), 220)
	assert_true(sim.boss_parts_destroyed.is_empty())
	result = sim.resolve_boss_round([{"unit_id": 0, "action": "attack"}])
	assert_eq(str(result["boss_counter"]["action_id"]), "club_smash",
		"club_smash is available again after REWIND restored the arm")


## --- SPD 順ターン進行システム v1 (2026-08-24) -----------------------------
## companion c1: base_spd 30 (level1 spd=30). c2: base_spd 5. Protagonist's
## base_spd is UD.PROTAGONIST_BASE_SPD=24 (constants.gd). test_boss's spd is
## 10 (fixtures.gd). Descending: c1(30) > protagonist(24) > boss(10) > c2(5)
## — a deliberately spread-out set of values (no accidental ties) so turn
## order tests read unambiguously; the *separate* tie-break test below picks
## its own values on purpose to force ties.
func _spd_defs() -> Array:
	return [
		{"id": "c1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 20, "hp_per_level": 4, "base_sp": 5, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 30, "spd_per_level": 1},
		{"id": "c2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 18, "hp_per_level": 4, "base_sp": 6, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 5, "spd_per_level": 1},
	]


func _sim_at_gate_with_party(rng_seed: int = 11) -> UDSim:
	var sim := UDSim.new_game(
		UDTestFixtures.enemies(), UDTestFixtures.stages(), rng_seed, [], _spd_defs())
	sim.stage_index = 5  # the fixture's gate stage
	return sim


func test_start_boss_fight_generates_a_deterministic_spd_descending_turn_order() -> void:
	var sim := _sim_at_gate_with_party()
	assert_true(sim.start_boss_fight())
	assert_eq(sim.turn_order, ["ally:1", "ally:0", "enemy:test_boss", "ally:2"],
		"c1(30) > protagonist(24) > boss(10) > c2(5), descending")
	assert_eq(sim.turn_cursor, 0)
	assert_eq(sim.current_actor_token(), "ally:1")


## §51: equal SPD favors allies over the enemy; equal SPD between two allies
## breaks by the existing fixed party seating order (ascending unit id).
## Deliberately distinct dict from _spd_defs() above — this one exists only
## to force two exact ties (24 vs protagonist, 10 vs the boss).
func test_equal_spd_ties_break_allies_before_enemy_then_by_seating_order() -> void:
	var defs := [
		{"id": "tc1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 20, "hp_per_level": 4, "base_sp": 5, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 24, "spd_per_level": 0},  # ties the protagonist (24)
		{"id": "tc2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 18, "hp_per_level": 4, "base_sp": 6, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 10, "spd_per_level": 0},  # ties test_boss's spd (10)
	]
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11, [], defs)
	sim.stage_index = 5
	assert_true(sim.start_boss_fight())
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:test_boss"],
		"protagonist(id0) before tc1(id1) at the 24-tie; tc2 before the boss at the 10-tie")


func test_resolve_player_action_resolves_only_the_current_actors_turn_and_advances_cursor() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.current_actor_token(), "ally:1")
	var boss_hp_before := sim.boss_hp
	var hp_before := {}
	for unit in sim.minions:
		hp_before[unit.id] = unit.hp

	var result := sim.resolve_player_action(1, "attack")

	assert_lt(sim.boss_hp, boss_hp_before, "the acting unit's attack landed")
	assert_false(result.has("boss_counter"),
		"a single ally action never triggers an enemy counter on its own")
	for unit in sim.minions:
		assert_eq(unit.hp, hp_before[unit.id], "no ally took damage from just one ally's turn")
	assert_eq(sim.turn_cursor, 1)
	assert_eq(sim.current_actor_token(), "ally:0", "cursor moved to the next entry in turn_order")


func test_resolve_player_action_rejects_a_call_for_a_unit_whose_turn_it_is_not() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.current_actor_token(), "ally:1")
	var boss_hp_before := sim.boss_hp

	var result := sim.resolve_player_action(0, "attack")  # it's ally:1's turn, not ally:0's

	assert_eq(result, {}, "out-of-turn calls are rejected outright")
	assert_eq(sim.boss_hp, boss_hp_before, "no damage was applied")
	assert_eq(sim.turn_cursor, 0, "cursor did not move")
	assert_eq(sim.current_actor_token(), "ally:1")


func test_resolve_enemy_action_only_fires_on_the_enemys_own_turn() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.current_actor_token(), "ally:1")
	var hp_before := {}
	for unit in sim.minions:
		hp_before[unit.id] = unit.hp

	var early := sim.resolve_enemy_action("test_boss")
	assert_eq(early, {}, "not the enemy's turn yet")
	for unit in sim.minions:
		assert_eq(unit.hp, hp_before[unit.id], "no ally took damage from a rejected enemy call")

	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(0, "attack")
	assert_eq(sim.current_actor_token(), "enemy:test_boss", "now legitimately the boss's turn")

	var result := sim.resolve_enemy_action("test_boss")
	assert_true(result.has("boss_counter"), "the boss's own turn resolves exactly one counter")
	var target_id := int(result["boss_counter"]["target_unit_id"])
	var damaged_count := 0
	for unit in sim.minions:
		if unit.hp < int(hp_before[unit.id]):
			damaged_count += 1
			assert_eq(unit.id, target_id, "only the chosen target lost hp")
	assert_eq(damaged_count, 1, "exactly one ally was hit by the single counter-attack")
	assert_eq(sim.current_actor_token(), "ally:2", "cursor advanced past the enemy's turn")


func test_dead_unit_is_skipped_in_the_turn_cycle_without_consuming_a_turn() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.turn_order, ["ally:1", "ally:0", "enemy:test_boss", "ally:2"])
	for unit in sim.minions:
		if unit.id == 2:
			unit.hp = 0  # c2 (ally:2), the last entry in turn_order, is already dead

	sim.resolve_player_action(1, "attack")
	assert_eq(sim.current_actor_token(), "ally:0")
	sim.resolve_player_action(0, "attack")
	assert_eq(sim.current_actor_token(), "enemy:test_boss")
	sim.resolve_enemy_action("test_boss")
	assert_eq(sim.current_actor_token(), "ally:1",
		"ally:2's dead turn slot was skipped entirely; the cycle wrapped straight back to ally:1")


func test_manual_rewind_resets_turn_order_and_cursor_to_fight_start() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	var order_at_start := sim.turn_order.duplicate()
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(0, "attack")
	assert_ne(sim.turn_cursor, 0, "sanity: the cursor actually progressed before rewinding")

	assert_true(sim.rewind_boss_fight())

	assert_eq(sim.turn_order, order_at_start, "§48: no stale NEXT order survives a rewind")
	assert_eq(sim.turn_cursor, 0)
	assert_eq(sim.current_actor_token(), order_at_start[0])


## §10/§42/§48: an auto-rewind triggered by a party wipe (via resolve_enemy_
## action, not the old batch resolve_boss_round path) resets HP *and* the
## new turn-progression state together, and boss_active stays true (REWIND
## returns to the same fight, it never ends it) — same contract the existing
## resolve_boss_round-driven wipe test already covers for HP; this test is
## specifically about the NEW turn_order/turn_cursor fields riding along.
func test_auto_rewind_on_party_wipe_resets_turn_order_and_cursor_too() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	var order_at_start := sim.turn_order.duplicate()
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(0, "attack")
	assert_eq(sim.current_actor_token(), "enemy:test_boss")

	# Stage a guaranteed one-hit party wipe: only the protagonist is left
	# alive, at 1 hp — _boss_target() deterministically targets the lowest-hp
	# living unit, and every damage formula in this file floors at 1, so the
	# counter is certain to kill this last survivor.
	for unit in sim.minions:
		unit.hp = 1 if unit.id == 0 else 0

	var result := sim.resolve_enemy_action("test_boss")

	assert_true(result.get("rewound", false))
	assert_true(sim.boss_active, "REWIND returns to the same fight, it does not end it")
	assert_eq(sim.turn_order, order_at_start)
	assert_eq(sim.turn_cursor, 0)
	assert_eq(sim.current_actor_token(), order_at_start[0])
	for unit in sim.minions:
		assert_eq(unit.hp, sim.unit_max_hp(unit), "REWIND restores hp to full, not just to 1")


func test_granular_turn_resolution_is_deterministic_for_a_fixed_seed() -> void:
	var sim_a := _sim_at_gate_with_party(11)
	var sim_b := _sim_at_gate_with_party(11)
	sim_a.start_boss_fight()
	sim_b.start_boss_fight()
	assert_eq(sim_a.turn_order, sim_b.turn_order)

	# Drive two full cycles identically on both sims: [ally:1, ally:0,
	# enemy:test_boss, ally:2] x2, asserting lockstep state after every step.
	for cycle in 2:
		sim_a.resolve_player_action(1, "attack")
		sim_b.resolve_player_action(1, "attack")
		assert_eq(sim_a.boss_hp, sim_b.boss_hp, "cycle %d step ally:1" % cycle)
		assert_eq(sim_a.current_actor_token(), sim_b.current_actor_token())

		sim_a.resolve_player_action(0, "attack")
		sim_b.resolve_player_action(0, "attack")
		assert_eq(sim_a.boss_hp, sim_b.boss_hp, "cycle %d step ally:0" % cycle)
		assert_eq(sim_a.current_actor_token(), sim_b.current_actor_token())

		if not sim_a.boss_active:
			break  # the boss may already be dead by cycle 2; both sims agree either way
		var res_a := sim_a.resolve_enemy_action("test_boss")
		var res_b := sim_b.resolve_enemy_action("test_boss")
		assert_eq(res_a.get("boss_counter", {}), res_b.get("boss_counter", {}),
			"cycle %d step enemy" % cycle)
		for unit_a in sim_a.minions:
			var unit_b: UDMinion = null
			for candidate in sim_b.minions:
				if candidate.id == unit_a.id:
					unit_b = candidate
			assert_eq(unit_a.hp, unit_b.hp, "cycle %d unit %d hp" % [cycle, unit_a.id])
		assert_eq(sim_a.current_actor_token(), sim_b.current_actor_token())

		sim_a.resolve_player_action(2, "attack")
		sim_b.resolve_player_action(2, "attack")
		assert_eq(sim_a.boss_hp, sim_b.boss_hp, "cycle %d step ally:2" % cycle)
		assert_eq(sim_a.current_actor_token(), sim_b.current_actor_token())


func test_save_roundtrip_preserves_turn_order_and_cursor_mid_fight() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	sim.resolve_player_action(1, "attack")
	assert_eq(sim.current_actor_token(), "ally:0")

	var d := sim.to_dict()
	var restored := UDSim.from_dict(
		d, UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _spd_defs())

	assert_eq(restored.turn_order, sim.turn_order)
	assert_eq(restored.turn_cursor, sim.turn_cursor)
	assert_eq(restored.current_actor_token(), "ally:0")


## §48's fallback path: a save written before this system existed (or one
## from which the fields were otherwise stripped) but mid an active fight
## gets a freshly generated turn order rather than an empty/broken one —
## same "an older save simply has none of the new keys" tolerance the rest
## of this codebase applies via d.get(key, default) (iron rule 3), here
## applied to code-schema evolution rather than save-schema evolution.
func test_save_missing_turn_order_regenerates_a_fresh_one_when_boss_is_active() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	var d := sim.to_dict()
	d.erase("turn_order")
	d.erase("turn_cursor")

	var restored := UDSim.from_dict(
		d, UDTestFixtures.enemies(), UDTestFixtures.stages(), [], _spd_defs())

	assert_true(restored.boss_active)
	assert_eq(restored.turn_order, sim.turn_order,
		"regenerated from the same living units/SPD, so it comes out identical")
	assert_eq(restored.turn_cursor, 0)


## Phase 5 (NEXT5、2026-08-25): peek_next_actors()自体の純粋性・正確性を
## sim層で直接検証する（UI側の網羅シナリオはtest_battle_next_queue.gd）。

func test_peek_next_actors_excludes_the_current_actor_and_returns_the_real_upcoming_order() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.turn_order, ["ally:1", "ally:0", "enemy:test_boss", "ally:2"])
	assert_eq(sim.current_actor_token(), "ally:1")

	assert_eq(sim.peek_next_actors(5), ["ally:0", "enemy:test_boss", "ally:2"],
		"current actor (ally:1) is not in its own NEXT list; wraps but stops before repeating itself")


func test_peek_next_actors_caps_at_the_requested_count() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()

	assert_eq(sim.peek_next_actors(2), ["ally:0", "enemy:test_boss"])


func test_peek_next_actors_advances_by_exactly_one_after_one_action_resolves() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.peek_next_actors(5), ["ally:0", "enemy:test_boss", "ally:2"])

	sim.resolve_player_action(1, "attack")  # ally:1's turn completes; cursor moves to ally:0

	assert_eq(sim.current_actor_token(), "ally:0")
	assert_eq(sim.peek_next_actors(5), ["enemy:test_boss", "ally:2", "ally:1"],
		"the list shifted by exactly one; ally:1 (who just acted) now re-appears at the tail")


func test_peek_next_actors_matches_the_real_tie_broken_turn_order() -> void:
	var defs := [
		{"id": "tc1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 20, "hp_per_level": 4, "base_sp": 5, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 24, "spd_per_level": 0},  # ties the protagonist (24)
		{"id": "tc2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 18, "hp_per_level": 4, "base_sp": 6, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 2, "def_per_level": 1,
			"base_spd": 10, "spd_per_level": 0},  # ties test_boss's spd (10)
	]
	var sim := UDSim.new_game(UDTestFixtures.enemies(), UDTestFixtures.stages(), 11, [], defs)
	sim.stage_index = 5
	sim.start_boss_fight()
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:test_boss"])

	assert_eq(sim.peek_next_actors(5), ["ally:1", "ally:2", "enemy:test_boss"],
		"NEXT reads the identical tie-broken order sim itself will actually walk; no separate UI-side SPD math")


func test_peek_next_actors_does_not_consume_rng_or_mutate_turn_state() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	var rng_state_before := sim._rng.state
	var rng_seed_before := sim._rng.seed
	var cursor_before := sim.turn_cursor
	var order_before := sim.turn_order.duplicate()

	sim.peek_next_actors(5)
	sim.peek_next_actors(5)
	sim.peek_next_actors(1)

	assert_eq(sim._rng.state, rng_state_before, "merely peeking ahead consumes no randomness")
	assert_eq(sim._rng.seed, rng_seed_before)
	assert_eq(sim.turn_cursor, cursor_before, "peeking never advances the real cursor")
	assert_eq(sim.turn_order, order_before, "peeking never rewrites turn_order")


func test_peek_next_actors_does_not_fabricate_entries_when_fewer_than_requested_remain() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	assert_eq(sim.turn_order.size(), 4)

	var upcoming := sim.peek_next_actors(5)

	assert_eq(upcoming.size(), 3,
		"only 3 real slots exist besides the current actor; NEXT does not pad with fake entries")


func test_peek_next_actors_reflects_the_fresh_order_after_manual_rewind() -> void:
	var sim := _sim_at_gate_with_party()
	sim.start_boss_fight()
	var fight_start_upcoming := sim.peek_next_actors(5)
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(0, "attack")
	assert_ne(sim.peek_next_actors(5), fight_start_upcoming,
		"sanity: NEXT actually changed while mid-fight, before we rewind")

	sim.rewind_boss_fight()

	assert_eq(sim.current_actor_token(), "ally:1")
	assert_eq(sim.peek_next_actors(5), fight_start_upcoming,
		"REWIND restores the exact fight-start turn order, so NEXT matches it again")


## Phase 6「防御」(2026-08-25): guarding_unitsの正確性・付与/解除タイミング
## ・敵ダメージ半減・REWIND連携をsim層で直接検証する。既存の
## _sim_at_gate_with_party()の敵(test_boss.atk=3)は小さすぎて「最低
## ダメージ1」フロアが半減の効果自体を覆い隠してしまう(3-def後の値が
## 元々1や2しかない)ため、半減が数値としてはっきり区別できる専用の
## 固定値フィクスチャ(boss atk=20, 味方def=0/3)をこのセクション専用に
## 用意する——実測: protagonist(def3)は非防御17/防御時8、companion
## (def0)は非防御20/防御時10（いずれも既存のmaxi(1,...)フロアと同じ
## ルールを半減後に再適用しただけ、新しい最低ダメージ仕様は発明して
## いない）。

func _guard_test_enemies() -> UDEnemyDB:
	return UDEnemyDB.from_dicts([
		{"id": "guard_test_boss", "name_key": "X", "hp": 999, "atk": 20, "def": 0, "spd": 1,
			"exp": 15, "coins": 10, "is_boss": true},
	])


func _guard_test_stages() -> UDStageDB:
	return UDStageDB.from_dicts([
		{"id": "guard_gate", "name_key": "X", "stage_from": 5, "stage_to": 5,
			"trash_pool": [], "boss_id": "guard_test_boss", "documents": [], "document_chance": 0.0},
	])


func _guard_test_defs() -> Array:
	return [
		{"id": "gc1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 50, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 0, "def_per_level": 0,
			"base_spd": 20, "spd_per_level": 0},
		{"id": "gc2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 50, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 0, "def_per_level": 0,
			"base_spd": 15, "spd_per_level": 0},
	]


## turn_order == ["ally:0"(protagonist,spd24,def3), "ally:1"(gc1,spd20,def0),
## "ally:2"(gc2,spd15,def0), "enemy:guard_test_boss"(spd1,atk20)] —
## deterministic every time (fixed SPD values, no ties).
## HP/SPポーション追加 (2026-08-25): p_battle_itemsは末尾の省略可能引数
## のため、既存の全呼び出し元(Phase 6の防御テスト群)は無改修のまま動く。
func _sim_with_guardable_party(rng_seed: int = 11, p_battle_items: UDBattleItemDB = null) -> UDSim:
	var sim := UDSim.new_game(
		_guard_test_enemies(), _guard_test_stages(), rng_seed, [], _guard_test_defs(),
		{}, {}, null, null, p_battle_items)
	sim.stage_index = 5
	return sim


## HP/SPポーション追加 (2026-08-25): テスト用の30%固定回復率フィクス
## チャー。実際のdata/battle_items/*.jsonと同じ形。
func _potion_test_items() -> UDBattleItemDB:
	return UDBattleItemDB.from_dicts([
		{"id": "hp_potion", "name_key": "X", "desc_key": "X",
			"heal_stat": "hp", "heal_percent": 0.3},
		{"id": "sp_potion", "name_key": "X", "desc_key": "X",
			"heal_stat": "sp", "heal_percent": 0.3},
	])


func test_only_the_current_actor_can_guard() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	assert_eq(sim.current_actor_token(), "ally:0")

	var result := sim.resolve_player_action(1, "guard")  # it's ally:0's turn, not ally:1's

	assert_eq(result, {}, "rejected exactly like any other unit's action out of turn")
	assert_false(sim.guarding_units.has(1), "the rejected call never touched guarding_units")
	assert_eq(sim.current_actor_token(), "ally:0", "cursor untouched by the rejected call")


func test_guard_consumes_exactly_one_action_and_advances_to_the_next_actor() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	assert_eq(sim.current_actor_token(), "ally:0")

	var result := sim.resolve_player_action(0, "guard")

	assert_eq((result.get("log", []) as Array).size(), 1, "one real action was consumed")
	assert_eq(sim.guarding_units, [0])
	assert_eq(sim.current_actor_token(), "ally:1",
		"turn advanced exactly once, same as attack/skill — SPD/turn order untouched (§25)")


func test_guarding_halves_the_next_boss_counter_and_reapplies_the_existing_minimum_floor() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	assert_eq(sim.current_actor_token(), "enemy:guard_test_boss")
	var hp_before := sim.minions[0].hp

	var result := sim.resolve_enemy_action(sim.boss_enemy_id)

	var counter: Dictionary = result["boss_counter"]
	assert_eq(counter["target_unit_id"], 0,
		"still the tie-break winner at full HP (lowest-hp target, ties favor unit 0)")
	assert_eq(counter["amount"], 8, "unguarded would be maxi(1,20-3)=17; guarded floor(17/2)=8")
	assert_eq(sim.minions[0].hp, hp_before - 8)


func test_a_non_guarding_unit_takes_full_unmitigated_damage() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.minions[2].hp -= 1  # gc2 becomes the strict lowest-HP target, no guard involved
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")  # gc2 acts too, but does not guard
	assert_eq(sim.current_actor_token(), "enemy:guard_test_boss")
	var hp_before := sim.minions[2].hp

	var result := sim.resolve_enemy_action(sim.boss_enemy_id)

	var counter: Dictionary = result["boss_counter"]
	assert_eq(counter["target_unit_id"], 2)
	assert_eq(counter["amount"], 20, "no guard active for unit 2 — full, unmitigated damage")
	assert_eq(sim.minions[2].hp, hp_before - 20)


func test_multiple_units_can_hold_independent_guard_states_at_once() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	sim.resolve_player_action(1, "guard")
	sim.resolve_player_action(2, "attack")  # gc2 deliberately does NOT guard

	assert_eq(sim.guarding_units, [0, 1],
		"guarding_units is a real per-unit array, not a single global bool (§16)")
	assert_false(sim.guarding_units.has(2))


## §4「次に自分の行動順を迎える"直前"まで維持する」——読み合わせの結果、
## 「自分の番が実際に来た時点で既に切れている」(彼女がまだ何も選んで
## いない、current_actorの黄色い強調と「防御中」表示が同時に出て紛らわ
## しくなる状態を作らない)を正とし、行動を実際に選ぶタイミングではなく
## カーソルが本人へ到達したタイミングそのものでクリアされることを検証
## する。
func test_guard_clears_the_instant_that_units_own_turn_arrives_again() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	assert_true(sim.guarding_units.has(0))
	sim.resolve_player_action(1, "attack")
	assert_true(sim.guarding_units.has(0), "guard survives another ally's turn (§8)")
	sim.resolve_player_action(2, "attack")
	assert_true(sim.guarding_units.has(0), "guard survives right up until the enemy's own turn (§9)")

	sim.resolve_enemy_action(sim.boss_enemy_id)  # this call's own cursor-advance lands on ally:0

	assert_eq(sim.current_actor_token(), "ally:0", "unit 0's own next turn has arrived")
	assert_false(sim.guarding_units.has(0),
		"cleared the instant her own turn arrives — before she has chosen anything new (§4)")


func test_other_units_actions_do_not_clear_someone_elses_guard() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")

	sim.resolve_player_action(1, "attack")
	assert_true(sim.guarding_units.has(0), "unit 1 acting does not touch unit 0's guard (§9)")
	sim.resolve_player_action(2, "attack")
	assert_true(sim.guarding_units.has(0))


func test_enemy_action_does_not_clear_guard_unless_it_kills_the_guarding_unit() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "guard")
	sim.resolve_player_action(2, "attack")
	assert_eq(sim.current_actor_token(), "enemy:guard_test_boss")

	sim.resolve_enemy_action(sim.boss_enemy_id)  # targets unit 0 (still the lowest-hp tie winner)

	assert_true(sim.guarding_units.has(1),
		"the boss's counter hit a DIFFERENT unit — unit 1's guard is untouched (§9)")


func test_ko_clears_guard_so_a_future_revive_never_finds_a_stale_guard_state() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.minions[0].hp = 5  # guaranteed lowest-hp target, and low enough that 8 dmg kills it
	sim.resolve_player_action(0, "guard")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	assert_true(sim.guarding_units.has(0))

	sim.resolve_enemy_action(sim.boss_enemy_id)  # 8 guarded damage vs 5 hp -> KO

	assert_eq(sim.minions[0].hp, 0)
	assert_false(sim.guarding_units.has(0), "KO clears guard immediately (§17)")


func test_manual_rewind_resets_every_guard_state_to_the_fight_start_none() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	sim.resolve_player_action(1, "guard")
	assert_eq(sim.guarding_units, [0, 1])

	sim.rewind_boss_fight()

	assert_eq(sim.guarding_units, [],
		"REWIND always returns to fight start, and nobody is guarding at fight start (§18)")


## Solo-protagonist fixture (no companions): a single boss counter is
## enough to wipe the party, since _party_wiped() requires EVERY living
## unit at 0 hp and only one unit is ever hit per counter — with 3 party
## members that requires killing 2 through some other path first, which
## would just be noise for this test's actual point (guard survives an
## auto-rewind). turn_order == ["ally:0", "enemy:guard_test_boss"].
func _solo_guard_sim(rng_seed: int = 11) -> UDSim:
	var sim := UDSim.new_game(_guard_test_enemies(), _guard_test_stages(), rng_seed)
	sim.stage_index = 5
	return sim


func test_auto_rewind_on_party_wipe_also_resets_guard_states() -> void:
	var sim := _solo_guard_sim()
	sim.start_boss_fight()
	assert_eq(sim.turn_order, ["ally:0", "enemy:guard_test_boss"])
	sim.minions[0].hp = 5  # guarded hit (8) still exceeds this -> KO -> the only unit -> wipe
	sim.resolve_player_action(0, "guard")
	assert_true(sim.guarding_units.has(0))

	var result := sim.resolve_enemy_action(sim.boss_enemy_id)

	assert_true(result.get("rewound", false), "sanity: this really did trigger the automatic rewind")
	assert_eq(sim.guarding_units, [], "guard states reset along with everything else (§18)")


func test_guard_does_not_disturb_turn_order_or_next5() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	var order_before := sim.turn_order.duplicate()

	sim.resolve_player_action(0, "guard")

	assert_eq(sim.turn_order, order_before, "guard never rewrites the underlying turn_order (§16/§25)")
	assert_eq(sim.current_actor_token(), "ally:1", "cursor advances exactly like any other action")
	# NEXT5 is relative to whoever is now current — this is the SAME thing
	# a fresh peek would show after any other action type (attack/skill)
	# advanced the cursor the same way; nothing guard-specific here.
	assert_eq(sim.peek_next_actors(5), ["ally:2", "enemy:guard_test_boss", "ally:0"],
		"NEXT5 correctly reflects the new current actor after guard, same as after any action")


func test_guard_action_consumes_no_extra_rng() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	var rng_state_before := sim._rng.state
	var rng_seed_before := sim._rng.seed

	sim.resolve_player_action(0, "guard")

	assert_eq(sim._rng.state, rng_state_before, "guard's own resolution touches no randomness (§17)")
	assert_eq(sim._rng.seed, rng_seed_before)


## §18/§19/§20 sanity: attack/skill/part-targeting still work exactly as
## before with guard's code paths present, even with an unrelated guard
## active elsewhere.
func test_normal_attack_still_works_normally_while_someone_else_guards() -> void:
	var sim := _sim_with_guardable_party()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	var boss_hp_before := sim.boss_hp

	sim.resolve_player_action(1, "attack")

	assert_lt(sim.boss_hp, boss_hp_before, "unit 1's attack landed normally")


func test_part_targeted_damage_still_routes_correctly_while_someone_else_guards() -> void:
	var enemies := UDEnemyDB.from_dicts([
		{"id": "guard_test_boss", "name_key": "X", "hp": 999, "atk": 20, "def": 0, "spd": 1,
			"exp": 15, "coins": 10, "is_boss": true,
			"parts": [{"id": "arm", "hp": 50, "name_key": "X"}]},
	])
	var sim := UDSim.new_game(enemies, _guard_test_stages(), 11, [], _guard_test_defs())
	sim.stage_index = 5
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	var boss_hp_before := sim.boss_hp

	sim.resolve_player_action(1, "attack", "", -1, "arm")

	assert_eq(sim.boss_hp, boss_hp_before, "part-targeted damage stays in the part's own pool (§20)")
	assert_lt(int(sim.boss_part_hp["arm"]), 50, "the part itself took the damage")


## ============================================================
## HP/SPポーション (2026-08-25、追加仕様§1-23) — Task D0.
## turn_order == ["ally:0"(protagonist,maxhp50,maxsp50), "ally:1"(gc1,
## maxhp50,maxsp10), "ally:2"(gc2,maxhp50,maxsp10), "enemy:guard_test_boss"]
## — same fixture as the Guard tests above, plus an injected item catalog.
## ============================================================

func _potion_sim(rng_seed: int = 11) -> UDSim:
	return _sim_with_guardable_party(rng_seed, _potion_test_items())


func test_battle_item_counts_start_at_three_each_on_boss_fight_start() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	assert_eq(int(sim.battle_item_counts.get("hp_potion", -1)), 3)
	assert_eq(int(sim.battle_item_counts.get("sp_potion", -1)), 3)


func test_hp_potion_heals_thirty_percent_of_max_hp() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10  # gc1, max_hp 50 -> 30% = 15

	var result := sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(sim.minions[1].hp, 25, "10 + floor(50*0.3)=15 -> 25")
	assert_eq(int((result["log"][0] as Dictionary)["amount"]), 15, "log carries the actual healed amount")


func test_sp_potion_heals_thirty_percent_of_max_sp() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].sp = 2  # gc1, max_sp 10 -> 30% = 3

	var result := sim.resolve_player_action(0, "item", "sp_potion", 1)

	assert_eq(sim.minions[1].sp, 5)
	assert_eq(int((result["log"][0] as Dictionary)["amount"]), 3)


func test_hp_potion_never_exceeds_max_hp_and_the_message_shows_the_actual_amount() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 42  # 42 + 15 would be 57 -> clamp to 50

	var result := sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(sim.minions[1].hp, 50, "clamped to max, not 57")
	assert_eq(int((result["log"][0] as Dictionary)["amount"]), 8,
		"the ACTUAL clamped amount (50-42), not the nominal 15 (§6)")


func test_sp_potion_never_exceeds_max_sp_and_the_message_shows_the_actual_amount() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].sp = 9  # 9+3 would be 12 -> clamp to 10

	var result := sim.resolve_player_action(0, "item", "sp_potion", 1)

	assert_eq(sim.minions[1].sp, 10)
	assert_eq(int((result["log"][0] as Dictionary)["amount"]), 1, "actual clamped amount (10-9), not the nominal 3")


func test_using_an_item_decrements_only_that_items_count_by_one() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10

	sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2)
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3, "the other item's count is untouched")


func test_using_an_item_consumes_the_actors_whole_turn_and_next_progresses_normally() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	assert_eq(sim.current_actor_token(), "ally:0")

	sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(sim.current_actor_token(), "ally:1", "item use is a full turn, exactly like attack/skill/guard")
	assert_eq(sim.peek_next_actors(5), ["ally:2", "enemy:guard_test_boss", "ally:0"],
		"NEXT correctly reflects the real new cursor position -- no item-specific stall or skip")


func test_using_an_item_on_an_ally_does_not_change_who_the_actor_was() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10  # gc1

	var result := sim.resolve_player_action(0, "item", "hp_potion", 1)

	var entry := result["log"][0] as Dictionary
	assert_eq(int(entry["unit_id"]), 0, "the acting unit is still the current actor (protagonist)")
	assert_eq(int(entry["target_id"]), 1, "the healed target is the OTHER unit, distinct from the actor")


## 仕様変更 (2026-08-26、ユーザー指示「アイテムを必要としていなくても
## 使えるようにして。特殊条件でポーションを使うをしなければいけない
## ボスを作る予定」): 旧§12の「満タン相手には使用自体を拒否」は撤回——
## 満タンの相手にも使用自体は常に成立し(個数を消費し行動が終わる)、
## 実際に回復した量だけが0になる。
func test_hp_potion_on_an_already_full_hp_target_is_allowed_and_heals_for_zero() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	# gc1 is already at full HP right after start_boss_fight()'s own full heal.

	var result := sim.resolve_player_action(0, "item", "hp_potion", 1)

	var entry := result["log"][0] as Dictionary
	assert_eq(str(entry["effect"]), "heal")
	assert_eq(int(entry["amount"]), 0, "already full -- the clamp naturally yields zero healed")
	assert_eq(sim.minions[1].hp, sim.unit_max_hp(sim.minions[1]))
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2, "the use still consumes a count even at full HP")
	assert_eq(sim.current_actor_token(), "ally:1", "the turn still resolved and moved on")


func test_sp_potion_on_an_already_full_sp_target_is_allowed_and_heals_for_zero() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()

	var result := sim.resolve_player_action(0, "item", "sp_potion", 1)

	var entry := result["log"][0] as Dictionary
	assert_eq(str(entry["effect"]), "heal_sp")
	assert_eq(int(entry["amount"]), 0)
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 2, "the use still consumes a count even at full SP")


func test_hp_potion_cannot_revive_a_downed_unit() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[2].hp = 0  # gc2, KO'd

	var result := sim.resolve_player_action(0, "item", "hp_potion", 2)

	assert_true((result["log"] as Array).is_empty(), "cannot target a KO'd unit -- no revive (§11)")
	assert_eq(sim.minions[2].hp, 0)
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 3)


func test_sp_potion_cannot_be_used_on_a_downed_unit_either() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[2].hp = 0
	sim.minions[2].sp = 0

	var result := sim.resolve_player_action(0, "item", "sp_potion", 2)

	assert_true((result["log"] as Array).is_empty())
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3)


func test_rewind_restores_item_counts_to_the_fight_starting_values() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	sim.resolve_player_action(0, "item", "hp_potion", 1)
	sim.minions[2].sp = 2
	sim.resolve_player_action(1, "item", "sp_potion", 2)
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2)
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 2)

	sim.rewind_boss_fight()

	assert_eq(int(sim.battle_item_counts["hp_potion"]), 3, "REWIND restores counts to the checkpoint's full values")
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3)


func test_rewind_restores_hp_healed_by_an_item_back_to_the_checkpoint() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	sim.resolve_player_action(0, "item", "hp_potion", 1)
	assert_eq(sim.minions[1].hp, 25, "sanity: the heal really landed before rewinding")

	sim.rewind_boss_fight()

	assert_eq(sim.minions[1].hp, sim.unit_max_hp(sim.minions[1]),
		"rewind restores the checkpoint's HP (full, from start_boss_fight()'s own heal), not the mid-fight value")


func test_a_fresh_boss_fight_resets_item_counts_regardless_of_the_previous_fights_leftovers() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	sim.resolve_player_action(0, "item", "hp_potion", 1)  # unit 0 acted -> cursor moves to ally:1
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2)
	sim.boss_hp = 0  # force a win without scripting a full combat round
	sim.resolve_player_action(1, "attack")  # boss_hp already <=0 -> this call triggers _apply_boss_win()

	assert_false(sim.boss_active, "sanity: the fight actually ended")
	assert_true(sim.start_boss_fight(), "a brand new attempt begins")

	assert_eq(int(sim.battle_item_counts["hp_potion"]), 3, "fresh fight -- no carryover from the last one")
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3)


func test_item_use_does_not_disturb_an_unrelated_guard_state() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "guard")
	assert_true(sim.guarding_units.has(0))
	sim.minions[1].hp = 10

	sim.resolve_player_action(1, "item", "hp_potion", 1)

	assert_true(sim.guarding_units.has(0), "the earlier guard is untouched by an unrelated item use")
	assert_eq(sim.minions[1].hp, 25, "and the item itself worked normally")


func test_item_use_does_not_disturb_boss_part_hp() -> void:
	var enemies := UDEnemyDB.from_dicts([
		{"id": "guard_test_boss", "name_key": "X", "hp": 999, "atk": 20, "def": 0, "spd": 1,
			"exp": 15, "coins": 10, "is_boss": true,
			"parts": [{"id": "arm", "hp": 50, "name_key": "X"}]},
	])
	var sim := UDSim.new_game(
		enemies, _guard_test_stages(), 11, [], _guard_test_defs(),
		{}, {}, null, null, _potion_test_items())
	sim.stage_index = 5
	sim.start_boss_fight()
	sim.minions[1].hp = 10

	sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(int(sim.boss_part_hp["arm"]), 50, "an item turn never touches an untouched part's HP")

	sim.resolve_player_action(1, "attack", "", -1, "arm")

	assert_lt(int(sim.boss_part_hp["arm"]), 50, "part targeting still works normally later in the same fight")


func test_item_use_does_not_disturb_turn_order_itself() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	var order_before := sim.turn_order.duplicate()
	sim.minions[1].hp = 10

	sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(sim.turn_order, order_before, "item use never rewrites the underlying turn_order")


func test_item_use_consumes_no_rng() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	var rng_state_before := sim._rng.state
	var rng_seed_before := sim._rng.seed

	sim.resolve_player_action(0, "item", "hp_potion", 1)

	assert_eq(sim._rng.state, rng_state_before, "item resolution is fully deterministic (§20)")
	assert_eq(sim._rng.seed, rng_seed_before)


## バグ修正 (2026-08-26、実機報告「ポーションを1個も持っていない」):
## この機能より前に保存されたセーブなどで、あるアイテムIDが一度も
## battle_item_countsへ記録されていない状態を再現し、backfillだけが
## 効いて既に使用済みの他アイテムの残数には触れないことを確認する。
func test_ensure_battle_item_defaults_backfills_missing_items_without_touching_existing_counts() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 10
	sim.resolve_player_action(0, "item", "hp_potion", 1)
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2)
	sim.battle_item_counts.erase("sp_potion")  # simulate an old/incomplete save
	assert_false(sim.battle_item_counts.has("sp_potion"))

	sim.ensure_battle_item_defaults()

	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3, "the missing item was backfilled to the base count")
	assert_eq(int(sim.battle_item_counts["hp_potion"]), 2, "the already-used item's count is untouched")


## 実際のバグの再現経路: main._on_fight_button()は既にアクティブな戦闘
## へ戻るだけの場合sim.start_boss_fight()自体を呼ばない——が、呼ばれた
## としても(例: 他の経路から)、"既にアクティブだから何もしない"分岐が
## 補充だけは行うことを直接確認する。
func test_start_boss_fight_backfills_missing_items_when_the_fight_is_already_active() -> void:
	var sim := _potion_sim()
	sim.start_boss_fight()
	sim.battle_item_counts.erase("sp_potion")

	var result := sim.start_boss_fight()

	assert_false(result, "resuming an active fight never re-initializes it as a brand new one")
	assert_eq(int(sim.battle_item_counts["sp_potion"]), 3)


## ============================================================
## Boss Action Set (新企画v1 D2、2026-08-25、§7-40) — Task D2.
## 3人パーティ(protagonist+ac1+ac2)を使う——2人構成だと、割り込みの
## spliceされる位置がボス自身の元スロットへちょうど重なってしまう
## 特殊ケース(実際の5人パーティでは発生しない極端な端点)があり、
## それを避けて「割り込み後に正常なSPD順へ戻る」ことを曖昧さ無く
## 検証するため。
## ============================================================

## start_condition (2026-08-31、§1-§9): 実データ(cave_troll.json)と同じ
## 形("requires_part_intact"を持つ小さなDictionary)をaction_set自身に
## 追加。既存の全テストは腕を"予兆より前"には一切壊さないため(壊すのは
## 常に予兆解決"後"のgap中——step実行時判定のfizzleテスト)、この追加は
## 既存テスト群への副作用を持たない。"actions"配列(部位条件を持たない
## 代替行動)も新規追加——§6前半「代替行動があればそれを選ぶ」の検証に
## 使う。既存テストはこのボスが通常のランダム選択(_boss_choose_action)
## 経路へ落ちることが一度も無いため、これも無影響。
func _action_set_test_enemies() -> UDEnemyDB:
	return UDEnemyDB.from_dicts([
		{"id": "action_set_test_boss", "name_key": "X", "hp": 999, "atk": 5, "def": 0, "spd": 1,
			"exp": 10, "coins": 5, "is_boss": true,
			"parts": [{"id": "arm", "hp": 50, "name_key": "X"}],
			"actions": [{"id": "arm_broken_swipe", "power": 20}],
			"action_set": {"id": "test_set",
				"start_condition": {"requires_part_intact": "arm"},
				"steps": [
					{"gap": 0, "action": {"id": "telegraph", "deals_damage": false}},
					{"gap": 2, "action": {"id": "strong", "power": 50, "requires_part_intact": "arm"}},
				]}},
	])


func _action_set_test_stages() -> UDStageDB:
	return UDStageDB.from_dicts([
		{"id": "action_set_gate", "name_key": "X", "stage_from": 5, "stage_to": 5,
			"trash_pool": [], "boss_id": "action_set_test_boss", "documents": [], "document_chance": 0.0},
	])


func _action_set_test_defs() -> Array:
	return [
		{"id": "ac1", "name_key": "X", "join_at_docs": 1,
			"base_hp": 100, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 0, "def_per_level": 0,
			"base_spd": 15, "spd_per_level": 0},
		{"id": "ac2", "name_key": "X", "join_at_docs": 2,
			"base_hp": 100, "hp_per_level": 4, "base_sp": 10, "sp_per_level": 1,
			"base_atk": 4, "atk_per_level": 1, "base_def": 0, "def_per_level": 0,
			"base_spd": 10, "spd_per_level": 0},
	]


## turn_order == ["ally:0"(protagonist,spd24,def3), "ally:1"(ac1,spd15,def0),
## "ally:2"(ac2,spd10,def0), "enemy:action_set_test_boss"(spd1)] —
## deterministic every time (fixed SPD values, no ties).
func _action_set_sim(rng_seed: int = 11, p_battle_items: UDBattleItemDB = null) -> UDSim:
	var sim := UDSim.new_game(
		_action_set_test_enemies(), _action_set_test_stages(), rng_seed, [], _action_set_test_defs(),
		{}, {}, null, null, p_battle_items)
	sim.stage_index = 5
	return sim


## §7-9: このボスの通常のSPD順の番は、常に0ダメージの予兆から新しい
## action_setが始まる——即座に強攻撃(旧・単純ランダム選択)を放たない。
func test_boss_action_set_fires_step_0_as_a_zero_damage_telegraph_on_its_normal_spd_turn() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:action_set_test_boss"])
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")
	var hp_before := {0: sim.minions[0].hp, 1: sim.minions[1].hp, 2: sim.minions[2].hp}

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_true(result.has("boss_telegraph"))
	assert_false(result.has("boss_counter"))
	assert_eq(str(result["boss_telegraph"]["action_id"]), "telegraph")
	for id in hp_before:
		assert_eq(sim.minions[id].hp, hp_before[id], "telegraph deals no damage (§15)")


## §10-13: 固定間隔(gap)は"完了した味方行動"の数——1行動だけではまだ
## 割り込みは発生しない。
func test_boss_action_set_does_not_fire_the_interrupt_after_only_one_ally_action() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	assert_eq(sim.current_actor_token(), "ally:0")

	sim.resolve_player_action(0, "attack")  # 1st gap ally

	assert_eq(sim.current_actor_token(), "ally:1",
		"only 1 ally action passed -- the already-scheduled interrupt isn't reached yet")
	# §18-20: the interrupt was already spliced into turn_order the instant
	# the telegraph resolved (eager scheduling, not a lazy per-action
	# countdown) -- its mere presence in the array doesn't mean it has
	# fired; current_actor_token() above is what actually matters.
	assert_eq(sim.turn_order.size(), 5, "the interrupt is already scheduled, just not reached yet")


## §17: ちょうど2回の味方行動が完了した直後、割り込みが本来のSPD順を
## 追い越して次の行動として挿入され、実際にダメージを与える。
func test_boss_action_set_interrupt_fires_after_exactly_two_ally_actions_with_real_damage() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	sim.resolve_player_action(0, "attack")  # 1st gap ally

	sim.resolve_player_action(1, "attack")  # 2nd gap ally -- the interrupt lands right here

	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss",
		"interrupted ahead of normal order -- ac2's turn hasn't come up yet")
	var hp_before := sim.minions[0].hp  # neither ally hurt yet -> tie -> unit 0 wins _boss_target()

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_true(result.has("boss_counter"))
	assert_false(result.has("boss_telegraph"))
	assert_eq(int(result["boss_counter"]["amount"]), 47, "50 power - 3 def, arm intact")
	assert_eq(int(result["boss_counter"]["target_unit_id"]), 0)
	assert_eq(sim.minions[0].hp, hp_before - 47)


## §18-20/最重要: 予兆が解決した"その瞬間"から、NEXT5の裏付けである
## peek_next_actors()は既に正しい未来位置に割り込みを反映している——
## 2回の味方行動を待って初めて現れるのではない(UI側の別予測ではなく、
## turn_orderという同じ実データを読むだけで済むことの直接証明)。
func test_next5_reflects_the_scheduled_interrupt_the_instant_the_telegraph_resolves() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")

	sim.resolve_enemy_action("action_set_test_boss")  # telegraph

	# 予兆の直後、まだ1つも味方行動が起きていないのに、割り込みは既に
	# turn_orderへspliceされている——gap=2なので、次の2件の味方トークン
	# (ally:0, ally:1)の直後に挿入されているはず。現在行動者はally:0
	# (予兆自身の_advance_turn_cursor()による通常の1歩)。
	assert_eq(sim.current_actor_token(), "ally:0")
	assert_eq(sim.turn_order,
		["ally:0", "ally:1", "enemy:action_set_test_boss", "ally:2", "enemy:action_set_test_boss"],
		"the interrupt is already spliced in right after the 2nd upcoming ally slot")
	assert_eq(sim.peek_next_actors(5),
		["ally:1", "enemy:action_set_test_boss", "ally:2", "enemy:action_set_test_boss"],
		"NEXT already shows the interrupt in its correct future position, before any gap action happened")


## §26-27: 割り込みが解決すると、turn_orderは元の形（増えたぶんが除かれた
## 並び）へ確実に戻り、次の実際の行動者へ自然に継続する。
func test_boss_action_set_returns_to_normal_spd_order_after_the_interrupt_resolves() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")

	sim.resolve_enemy_action("action_set_test_boss")  # the interrupt itself

	assert_eq(sim.current_actor_token(), "ally:2", "the next real ally continues normally")
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:action_set_test_boss"],
		"turn_order fully restored to its original shape -- no leftover extra slot")
	assert_eq(sim.boss_action_set_step, 0, "ready for a fresh set next time")


## §26-27: 次にこのボスの本来のSPDターンが巡ってきたとき、また新しい
## セット(予兆から)が始まる——割り込みの続きにはならない。
func test_a_fresh_action_set_starts_from_step_0_the_next_time_the_boss_reaches_its_normal_turn() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # interrupt
	sim.resolve_player_action(2, "attack")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_true(result.has("boss_telegraph"), "a fresh set begins from step 0 again, not another interrupt")


## §23-24/最重要: 部位の状態は"予兆の瞬間"ではなく"割り込みが実際に発生
## する直前"の最新状態を見る——予兆の時点ではまだ腕は健在だったが、
## その後の2行動の間に破壊された場合、強攻撃は不発する。
func test_boss_action_set_interrupt_fizzles_when_the_required_part_was_destroyed_after_the_telegraph() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph -- arm is still intact here
	assert_false(sim.boss_parts_destroyed.has("arm"))
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")  # destroyed DURING the 2-action gap
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")  # splices/reaches the interrupt
	var hp_before := {0: sim.minions[0].hp, 1: sim.minions[1].hp, 2: sim.minions[2].hp}

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_true(result.has("boss_fizzle"))
	assert_false(result.has("boss_counter"))
	assert_eq(str(result["boss_fizzle"]["action_id"]), "strong")
	for id in hp_before:
		assert_eq(sim.minions[id].hp, hp_before[id], "a fizzle deals no damage")
	assert_eq(sim.boss_action_set_step, 0, "the set still ends normally even on a fizzle (§26/§27)")


## §12: 戦闘不能のスロットはターン循環そのものが自動でスキップする
## （既存のREWIND/防御テストでも使われている性質）ため、gapのカウントに
## 一切寄与しない——死んだユニットの番が"来ない"以上、それを行動として
## 消費したことにはならない。
## 注記: 割り込みの発生位置は予兆が解決した"その瞬間"にtelegraph時点の
## 生存状況を基準として確定的に決まる(§18-20、NEXT5が即座に正しい未来
## 位置を示すための設計)。そのため、このテストはunit 1を"telegraph発生
## 前から"死亡させておく——telegraphより後(gapを数えている最中)に新たに
## 死亡するケースは、既に確定済みの割り込み位置を過去に遡って動かす
## ことになり別の話（このボスの唯一のダメージ源は割り込み自身であり、
## それがまだ発火していない間は誰も死にようがないため、実際のゲーム
## プレイでは起こらない状況）。
func test_ko_units_are_skipped_by_the_turn_cycle_and_never_count_toward_the_action_set_gap() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.minions[1].hp = 0  # ac1 (unit 1) is KO'd from before the telegraph even fires
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(2, "attack")  # unit 1's slot is silently skipped in this initial lap too
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")

	sim.resolve_enemy_action("action_set_test_boss")  # telegraph, scheduled with unit 1 already excluded
	assert_eq(sim.current_actor_token(), "ally:0", "unit 1's dead slot contributes nothing to the schedule")

	sim.resolve_player_action(0, "attack")  # 1st of the 2 living allies' gap actions
	assert_eq(sim.current_actor_token(), "ally:2", "unit 1's dead slot is skipped, never counted")

	sim.resolve_player_action(2, "attack")  # 2nd gap action

	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss",
		"exactly 2 living ally actions triggered the interrupt, matching gap=2")


## §21: 防御もどうぐの使用も、攻撃と全く同じ「1つの完了した味方行動」
## として扱われる——action文字列を一切見ない設計であることの直接証明。
func test_guard_counts_as_one_action_toward_the_action_set_gap() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph

	sim.resolve_player_action(0, "guard")  # 1st gap action, via guard instead of attack
	sim.resolve_player_action(1, "guard")  # 2nd gap action

	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss", "guard counts exactly like attack")


## 新企画v1「Boss Action Setを実戦で成立させるフェーズ」§8/§21-7:
## スキルの使用も攻撃/防御/どうぐと同じ「1つの完了した味方行動」——
## turn_orderの各要素は行動の種類を一切記録しないため(_schedule_boss_
## action_set_interrupt()のdoc comment参照)構造的に保証されるが、
## §21が明示的に挙げるチェック項目のためスキルでも直接確認しておく。
func test_skill_use_counts_as_one_action_toward_the_action_set_gap() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph

	sim.resolve_player_action(0, "skill", "skill_rapid_slash")  # 1st gap action, via skill
	sim.resolve_player_action(1, "attack")  # 2nd gap action

	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss", "skill counts exactly like attack")


## §22: どうぐの使用も攻撃/防御と同じ「1つの完了した味方行動」。
func test_item_use_counts_as_one_action_toward_the_action_set_gap() -> void:
	var sim := _action_set_sim(11, _potion_test_items())
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	sim.minions[0].hp = 10  # so the potion actually has an effect (isn't rejected as full-HP)

	sim.resolve_player_action(0, "item", "hp_potion", 0)  # 1st gap action
	sim.resolve_player_action(1, "attack")  # 2nd gap action

	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss", "item use counts exactly like attack")


## §30-31: 予兆・割り込みとも一切RNGを消費しない(scripted, deterministic)。
func test_boss_action_set_telegraph_and_interrupt_consume_no_rng() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	var seed_before := sim._rng.seed
	var state_before := sim._rng.state

	sim.resolve_enemy_action("action_set_test_boss")  # telegraph

	assert_eq(sim._rng.seed, seed_before)
	assert_eq(sim._rng.state, state_before)

	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # interrupt

	assert_eq(sim._rng.seed, seed_before, "the whole action-set sequence never touches RNG")
	assert_eq(sim._rng.state, state_before)


## §32-33: 進行中のaction set(予兆済み・1/2行動だけ消化済み)は、REWINDで
## 完全に未着手(0)へ戻る——turn_orderの一時的なsplice痕跡も残らない。
func test_manual_rewind_resets_an_in_progress_action_set_back_to_not_yet_started() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	sim.resolve_player_action(0, "attack")  # 1 of 2 gap actions done
	assert_eq(sim.boss_action_set_step, 1)

	sim.rewind_boss_fight()

	assert_eq(sim.boss_action_set_step, 0, "back to fully unbegun")
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:action_set_test_boss"],
		"no leftover splice artifact either")
	assert_eq(sim.current_actor_token(), "ally:0")


## §31: REWIND後、同じ行動列を再現すれば、予兆・割り込みとも全く同じ
## 結果を再現する(決定性)。
func test_action_set_reproduces_identically_after_rewind_given_the_same_actions() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	var play := func() -> Array:
		sim.resolve_player_action(0, "attack")
		sim.resolve_player_action(1, "attack")
		sim.resolve_player_action(2, "attack")
		var telegraph_result: Dictionary = sim.resolve_enemy_action("action_set_test_boss")
		sim.resolve_player_action(0, "attack")
		sim.resolve_player_action(1, "attack")
		var interrupt_result: Dictionary = sim.resolve_enemy_action("action_set_test_boss")
		return [telegraph_result, interrupt_result]

	var first_run: Array = play.call()
	sim.rewind_boss_fight()
	var second_run: Array = play.call()

	assert_eq((first_run[0] as Dictionary)["boss_telegraph"], (second_run[0] as Dictionary)["boss_telegraph"])
	assert_eq((first_run[1] as Dictionary)["boss_counter"], (second_run[1] as Dictionary)["boss_counter"])


## §34: 既存の確立済みルール(全滅時、full animationは中断せず後から
## REWINDする——ここではsim層の契約そのもの: 割り込みの一撃で全滅した
## 場合もresolve_enemy_action()自身がwipe検出→自動REWINDまで完結する)
## が、割り込み経由の全滅でも変わらず成立し、進行中のaction set状態も
## 一緒に完全リセットされる。
func test_action_set_interrupt_can_wipe_the_party_and_triggers_automatic_rewind() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	sim.resolve_player_action(0, "attack")  # 1st gap action (ally0)
	sim.minions[0].hp = 0
	sim.minions[2].hp = 0
	sim.minions[1].hp = 1  # the sole survivor going into the interrupt
	sim.resolve_player_action(1, "attack")  # 2nd gap action (ally1) -- splices the interrupt

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_true(result.get("rewound", false), "the interrupt's strong attack wiped the lone survivor")
	assert_true(sim.boss_active, "REWIND restarts the same fight, does not end it")
	for m in sim.minions:
		assert_eq(m.hp, sim.unit_max_hp(m), "party fully healed by the rewind")
	assert_eq(sim.boss_action_set_step, 0, "the in-progress action set is also fully reset")
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:action_set_test_boss"])


## real cave_troll data (data/enemies/cave_troll.json) を実際に読み込み、
## 予兆→2回の味方行動→割り込みという流れが、実データ・実SPD順で
## end-to-endに動作することを確認する(既存のtest_cave_troll_real_data_
## body_part_and_gated_action_end_to_end()は旧resolve_boss_round()経路
## のため無改修——action_setはresolve_enemy_action()経由でのみ発火し、
## resolve_boss_roundは今まで通り_apply_enemy_counter()の従来ランダム
## 選択のまま)。
func test_cave_troll_real_data_action_set_telegraph_then_interrupt_end_to_end() -> void:
	var enemies := UDEnemyDB.load_from_dir("res://data/enemies")
	var stages := UDStageDB.load_from_dir("res://data/stages")
	# 新企画v1フェーズ0以降、全5人が最初から仲間——companion_defsを渡さない
	# と主人公1人だけのpartyになり(既存のtest_cave_troll_real_data_body_
	# part_and_gated_action_end_to_end()は旧resolve_boss_round経由でこれで
	# 足りるが)、複数の味方行動が必要なaction_setのgap検証には5人フル
	# パーティが要る——main.gd._ready()と同じ、実データを読み込む。
	var companion_defs := UDDataLoader.load_json_dir("res://data/companions")
	var sim := UDSim.new_game(enemies, stages, 11, [], companion_defs)
	sim.stage_index = 10  # gate_10 (data/stages/020_gate10.json), cave_troll's gate
	assert_true(sim.start_boss_fight())
	assert_eq(sim.boss_enemy_id, "cave_troll")
	var base_order: Array[String] = sim.turn_order.duplicate()

	# 円→protagonist→サユ(実データのSPD順で、troll(spd16)より速い3人)
	# まで消化——troll自身の本来の番へ到達する。
	var advanced := 0
	while sim.current_actor_token().begins_with("ally:"):
		var token: String = sim.current_actor_token()
		sim.resolve_player_action(int(token.substr(5)), "attack")
		advanced += 1
		assert_lt(advanced, 10, "should have reached cave_troll's own turn by now")
	assert_eq(sim.current_actor_token(), "enemy:cave_troll")

	var telegraph := sim.resolve_enemy_action("cave_troll")

	assert_true(telegraph.has("boss_telegraph"))
	assert_eq(str(telegraph["boss_telegraph"]["action_id"]), "club_windup_telegraph")
	assert_true(sim.current_actor_token().begins_with("ally:"), "advances to the next real ally")

	# gap=2ぶんの味方行動を消化——実データの生存者は5人なので、確実に
	# 2人ぶん(誰であれ)を消化すれば割り込みへ到達する。
	var gap_advanced := 0
	while sim.current_actor_token() != "enemy:cave_troll":
		var token: String = sim.current_actor_token()
		assert_true(token.begins_with("ally:"))
		sim.resolve_player_action(int(token.substr(5)), "attack")
		gap_advanced += 1
		assert_lt(gap_advanced, 3, "the interrupt must land after exactly 2 ally actions, not later")
	assert_eq(gap_advanced, 2, "exactly 2 ally actions were needed to reach the interrupt")

	var interrupt := sim.resolve_enemy_action("cave_troll")

	assert_true(interrupt.has("boss_counter"))
	assert_eq(str(interrupt["boss_counter"]["action_id"]), "club_smash_strong")
	assert_gt(int(interrupt["boss_counter"]["amount"]), 0, "the arm is intact -- real damage lands")
	assert_true(sim.current_actor_token().begins_with("ally:"), "returns to the normal SPD order")
	assert_eq(sim.turn_order, base_order, "turn_order fully restored to its original real-data shape")


## ============================================================
## Boss Action Set 開始条件 (実機報告 2026-08-31、§1-§10) — 右腕が既に
## 破壊済みの状態でボスの通常SPD順の番が来ても、棍棒action_setそのもの
## (予兆を含む)を一切始めない。既存の"予兆解決"後判定(§4/§5の実行時
## 判定、_resolve_action_set_stepのfizzle)とは別の、"開始時"判定
## (_action_set_start_condition_met、action_set.start_condition)。
## ============================================================

## §3/§4: 開始条件を満たさない(腕が既に破壊済み)場合、予兆(steps[0])は
## 一切発火せず、§6前半どおり代替行動(actionsのarm_broken_swipe、部位
## 条件を持たない)が選ばれる——ダメージも実際に発生する。
func test_boss_action_set_start_condition_uses_the_alternate_action_when_the_part_is_already_destroyed() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")  # already destroyed BEFORE the boss's first normal turn
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")
	var hp_before := sim.minions[0].hp

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_false(result.has("boss_telegraph"),
		"「洞窟トロルが棍棒を大きく振り上げた！！」は表示されない (§2 パターンA)")
	assert_true(result.has("boss_counter"))
	assert_eq(str(result["boss_counter"]["action_id"]), "arm_broken_swipe",
		"an available alternate action is used instead of the blocked action_set (§6 前半)")
	assert_lt(sim.minions[0].hp, hp_before, "the alternate action still deals real damage")
	assert_eq(sim.boss_action_set_step, 0, "no action set was ever begun")
	assert_eq(sim.turn_order, ["ally:0", "ally:1", "ally:2", "enemy:action_set_test_boss"],
		"turn_order is untouched -- no interrupt was ever scheduled (§8)")


## §6後半: 代替行動も存在しない場合は、既存の空candidates→flat attack
## フォールバックへ落ちる（新しい攻撃を勝手に発明しない）。この1件だけ
## ローカルなenemies dbを使う——共有フィクスチャの"actions"配列を空にする
## ためだけに別変数を増やすより、テスト自身に事情を局所化した方が明確。
func test_boss_action_set_start_condition_falls_back_to_flat_attack_when_no_alternate_action_exists() -> void:
	var enemies := UDEnemyDB.from_dicts([
		{"id": "action_set_test_boss", "name_key": "X", "hp": 999, "atk": 5, "def": 0, "spd": 1,
			"exp": 10, "coins": 5, "is_boss": true,
			"parts": [{"id": "arm", "hp": 50, "name_key": "X"}],
			# "actions" intentionally absent -- no alternate action data at all.
			"action_set": {"id": "test_set",
				"start_condition": {"requires_part_intact": "arm"},
				"steps": [
					{"gap": 0, "action": {"id": "telegraph", "deals_damage": false}},
					{"gap": 2, "action": {"id": "strong", "power": 50, "requires_part_intact": "arm"}},
				]}},
	])
	var sim := UDSim.new_game(
		enemies, _action_set_test_stages(), 11, [], _action_set_test_defs(), {}, {}, null, null, null)
	sim.stage_index = 5
	sim.start_boss_fight()
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")

	var result := sim.resolve_enemy_action("action_set_test_boss")

	assert_false(result.has("boss_telegraph"))
	assert_true(result.has("boss_counter"))
	assert_eq(str(result["boss_counter"]["action_id"]), "attack",
		"falls back to the generic flat-atk action, no new attack invented (§6後半)")


## §5/§6: 予兆が一度発生した"後"は、開始条件ではなく実行時条件
## (requires_part_intact on the strong step)がそのまま既存どおり働く
## ——開始時判定は新しいセットを"始める"かどうかにしか関わらないことの
## 直接対比。予兆自体はまだ腕が健在な状態で普通に発生させ、gap中に破壊
## した場合の挙動は既存のtest_boss_action_set_interrupt_fizzles_when_
## the_required_part_was_destroyed_after_the_telegraph()が変わらず検証
## し続ける（本テストでは新規に重複させない）。
func test_boss_action_set_start_condition_does_not_block_an_already_begun_set() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")

	var telegraph := sim.resolve_enemy_action("action_set_test_boss")  # arm intact -- telegraph fires

	assert_true(telegraph.has("boss_telegraph"))
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")  # destroyed mid-set, after the telegraph already fired
	assert_eq(sim.boss_action_set_step, 1, "the set stays in progress -- start_condition is not re-checked")


## §9: 通常REWINDは常に戦闘開始時点(腕は必ず健在)へ戻る——予兆解決後に
## 腕を破壊しても、REWINDで巻き戻ればまた予兆から始められる、という
## "開始条件がその都度、最新のboss_parts_destroyedを見て再判定される"
## ことの直接証明(固定されたフラグをキャッシュしていない)。
func test_manual_rewind_makes_the_action_set_startable_again_after_the_part_regenerates() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")  # destroyed during the gap

	sim.rewind_boss_fight()

	assert_false(sim.boss_parts_destroyed.has("arm"), "sanity: rewind restores the part")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	var result := sim.resolve_enemy_action("action_set_test_boss")
	assert_true(result.has("boss_telegraph"), "a fresh telegraph fires -- start_condition re-evaluated live")


## §9/§10 の2パターン: REWINDⅡのmid_checkpointは戦闘開始時点ではなく
## プレイヤーが指定した任意の途中地点を保存するため、「腕が既に壊れて
## いる途中地点」をそのまま復元できる——通常REWINDでは再現できない
## ケース。
func test_rewind2_reevaluates_the_start_condition_from_whatever_part_state_it_captured() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()

	# パターン: mid_checkpoint地点では腕健在 -> 復元後もaction_set開始可能。
	assert_true(sim.set_mid_checkpoint(), "ally:0's turn -- a valid moment to set the checkpoint")
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")  # destroyed AFTER the checkpoint was captured
	assert_true(sim.use_rewind2())
	assert_false(sim.boss_parts_destroyed.has("arm"), "restored to the checkpoint's intact-arm state")
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	var result_intact := sim.resolve_enemy_action("action_set_test_boss")
	assert_true(result_intact.has("boss_telegraph"), "checkpoint had an intact arm -- the set can start")

	# パターン: 腕が既に壊れている途中地点をmid_checkpointへ保存 -> 復元後は
	# action_set不可のまま。次のセット(1回のみ設定可能なmid_checkpointの
	# 制約を避けるため)新しいsimを使う。
	var sim2 := _action_set_sim()
	sim2.set_rewind2_unlocked(true)
	sim2.start_boss_fight()
	sim2.boss_part_hp["arm"] = 0
	sim2.boss_parts_destroyed.append("arm")
	assert_true(sim2.set_mid_checkpoint(), "checkpoint captured WITH the arm already destroyed")
	sim2.resolve_player_action(0, "attack")  # move a bit further before rewinding back
	assert_true(sim2.use_rewind2())
	assert_true(sim2.boss_parts_destroyed.has("arm"), "restored to the checkpoint's destroyed-arm state")
	sim2.resolve_player_action(0, "attack")
	sim2.resolve_player_action(1, "attack")
	sim2.resolve_player_action(2, "attack")
	var result_broken := sim2.resolve_enemy_action("action_set_test_boss")
	assert_false(result_broken.has("boss_telegraph"), "checkpoint had a destroyed arm -- the set cannot start")
	assert_true(result_broken.has("boss_counter"))
	assert_eq(str(result_broken["boss_counter"]["action_id"]), "arm_broken_swipe")


## --- REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」、2026-08-28) ------------------
## プレイヤーが戦闘中に自分で1回だけ指定できる、上位の「途中地点」への
## REWIND。通常REWIND(常に戦闘開始時点)とは完全に独立したスナップショット
## スロット(mid_checkpoint)を持つ——恒久の解放フラグ(rewind2_unlocked)が
## trueの間だけ使え、1戦闘につき「設定は最大1回・使用は最大1回」。既存の
## _action_set_sim()（3人パーティ＋部位(arm)＋Action Set2段構成のボス、
## 上のBoss Action Setテスト群と共有）とp_battle_items（HP/SPポーション、
## _potion_test_items()）をそのまま使い回す。


func _rng_test_enemies() -> UDEnemyDB:
	return UDEnemyDB.from_dicts([
		{"id": "rng_test_boss", "name_key": "X", "hp": 999, "atk": 5, "def": 0, "spd": 1,
			"exp": 10, "coins": 5, "is_boss": true,
			"actions": [
				{"id": "swipe", "power": 4},
				{"id": "smash", "power": 40},
			]},
	])


func _rng_test_stages() -> UDStageDB:
	return UDStageDB.from_dicts([
		{"id": "rng_gate", "name_key": "X", "stage_from": 5, "stage_to": 5,
			"trash_pool": [], "boss_id": "rng_test_boss", "documents": [], "document_chance": 0.0},
	])


## action_setもpartsも持たないボス——_boss_choose_action()の旧ランダム
## AI経路(RNGを実際に消費する)だけを純粋に踏ませるための専用フィクス
## チャー。_action_set_test_defs()と同じ3人パーティを使い回す。
func _rng_test_sim(rng_seed: int = 11) -> UDSim:
	var sim := UDSim.new_game(
		_rng_test_enemies(), _rng_test_stages(), rng_seed, [], _action_set_test_defs())
	sim.stage_index = 5
	return sim


## §1: 未解放では、味方の入力待ち中であっても設定も使用もできない。
func test_rewind2_unavailable_before_being_unlocked() -> void:
	var sim := _action_set_sim()
	sim.start_boss_fight()
	assert_false(sim.rewind2_unlocked)
	assert_true(sim.current_actor_token().begins_with("ally:"))
	assert_false(sim.set_mid_checkpoint(), "§1: locked -- cannot even set a checkpoint")
	assert_false(sim.use_rewind2(), "§1: locked -- nothing to use either")


## §2: 解放後は設定できる。
func test_rewind2_available_once_unlocked() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	assert_true(sim.set_mid_checkpoint(), "§2: unlocked -- setting now succeeds")
	assert_true(sim.mid_checkpoint_set)


## §3/§28: 解放済みのまま一度使い切っても、新しい戦闘は必ず未設定・未
## 使用から始まる。
func test_new_fight_starts_with_mid_checkpoint_unset_and_unused() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	sim.use_rewind2()
	assert_true(sim.mid_checkpoint_used)
	sim.flee_boss_fight()

	sim.start_boss_fight()  # a brand new attempt

	assert_false(sim.mid_checkpoint_set, "§3/§28: fresh fight, unused checkpoint slot")
	assert_false(sim.mid_checkpoint_used)
	assert_true(sim.mid_checkpoint.is_empty())


## §4/§19/§20/§34: 味方の生存中current_actorのターンでなければ設定できない
## ——ここでは「敵の番」を実際に再現して確認する(main.gd側の"UI階層途中
## か"というより細かいガードは、sim層では表現できない一時UI状態のため
## main.gd自身の責務、§33参照)。
func test_rewind2_can_only_be_set_while_it_is_a_living_allys_turn() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")

	assert_false(sim.set_mid_checkpoint(), "§4/§19/§20: not an ally's turn, cannot set")

	sim.resolve_enemy_action("action_set_test_boss")  # telegraph -> wraps back to an ally
	assert_true(sim.current_actor_token().begins_with("ally:"))
	assert_true(sim.set_mid_checkpoint(), "an ally's own turn is the only safe moment")


## §9: 一度設定したら、以降どれだけ状態が変わっても別地点へ上書きできない
## ——最初に保存したスナップショットの中身も無傷のまま。
func test_setting_a_second_time_does_not_overwrite_the_first_point() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	var boss_hp_at_set := int(sim.mid_checkpoint["boss_hp"])

	sim.resolve_player_action(0, "attack")  # boss_hp now differs from the checkpoint
	assert_ne(sim.boss_hp, boss_hp_at_set)
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")

	assert_false(sim.set_mid_checkpoint(), "§9: already set once -- cannot move it to here instead")
	assert_eq(int(sim.mid_checkpoint["boss_hp"]), boss_hp_at_set,
		"the original snapshot is untouched by the rejected second attempt")


## §6: 設定地点へ、実際に1回戻れる。
func test_using_rewind2_restores_the_saved_point() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	var boss_hp_at_set := sim.boss_hp
	sim.set_mid_checkpoint()

	# 3 attacks damage boss_hp (not ally HP); the telegraph that follows
	# deals 0 damage by design (§15 of the Boss Action Set tests above) --
	# boss_hp is the dimension that genuinely moves in this sequence.
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")
	assert_lt(sim.boss_hp, boss_hp_at_set, "sanity: something actually changed since the checkpoint")

	assert_true(sim.use_rewind2(), "§6: returns to the saved point")
	assert_eq(sim.boss_hp, boss_hp_at_set)
	assert_true(sim.mid_checkpoint_used)
	assert_true(sim.boss_active, "REWINDⅡ restarts from the mid-point, it does not exit the encounter")


## §7: 一度使用したら、その戦闘中は二度と使用できない。
func test_rewind2_cannot_be_used_twice() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	sim.use_rewind2()

	assert_false(sim.use_rewind2(), "§7: already spent, this fight")


## §8: 使用後は、設定のやり直しもできない。
func test_rewind2_cannot_be_reset_after_use() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	sim.use_rewind2()

	assert_false(sim.set_mid_checkpoint(), "§8: used -- no re-setting either")


## §9/§12/§40: 通常REWINDを挟んでも、「設定済み」という事実そのものは
## 消えない——mid_checkpoint自体もboss_checkpointとは無関係に無傷。
func test_normal_rewind_does_not_revive_a_pending_mid_checkpoint() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()

	assert_true(sim.rewind_boss_fight())

	assert_true(sim.mid_checkpoint_set, "§9/§12/§40: normal REWIND does not clear the fact it was set")
	assert_false(sim.mid_checkpoint_used)
	assert_false(sim.mid_checkpoint.is_empty(), "the snapshot itself survives a normal REWIND too")


## §10/§11/§40: 通常REWINDを挟んでも、「使用済み」という事実は消えない
## ——REWINDⅡ権は復活しない。
func test_normal_rewind_does_not_revive_a_used_rewind2() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	sim.use_rewind2()

	assert_true(sim.rewind_boss_fight())

	assert_true(sim.mid_checkpoint_used, "§10/§11/§40: normal REWIND does not restore the REWINDⅡ right")
	assert_false(sim.use_rewind2(), "still spent")


## §14/§15/§36: 設定済み・使用済みの状態も、mid_checkpoint自体も、恒久の
## 解放フラグも、いずれもセーブ＆ロードで失われない——boss_checkpoint等の
## 既存フィールドと同じadditiveパターン。
func test_rewind2_set_and_used_state_survives_a_save_roundtrip() -> void:
	var sim := _action_set_sim(11, _potion_test_items())
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.set_mid_checkpoint()
	sim.use_rewind2()

	var loaded := UDSim.from_dict(
		sim.to_dict(), _action_set_test_enemies(), _action_set_test_stages(),
		[], _action_set_test_defs(), {}, {}, null, null, _potion_test_items())

	assert_true(loaded.rewind2_unlocked, "§14/§36: unlock state persists")
	assert_true(loaded.mid_checkpoint_set, "§14/§15: setting persists")
	assert_true(loaded.mid_checkpoint_used, "§14: use-count does not come back on load")
	assert_false(loaded.use_rewind2(), "cannot re-spend after a reload")
	assert_false(loaded.mid_checkpoint.is_empty(), "the checkpoint itself round-trips too, §15")


## §12/§13/§16/§17/§28/§29: 「セットした瞬間」のHP/SP・ポーション残数・
## 防御状態・部位HPが正確に復元され、それ以降の変化（追加のポーション
## 消費・防御の自然解除・部位破壊）は全て打ち消される。
func test_rewind2_restores_hp_sp_potions_guard_and_boss_part_state() -> void:
	var sim := _action_set_sim(11, _potion_test_items())
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()

	sim.resolve_player_action(0, "item", "hp_potion", 1)  # ac1(id1) drinks
	sim.resolve_player_action(1, "guard")  # id1 guards -- still in effect until id1's own next turn
	sim.resolve_player_action(2, "attack", "", -1, "arm")  # dents the arm without destroying it
	assert_eq(sim.current_actor_token(), "enemy:action_set_test_boss")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph, 0 damage -- wraps to ally:0
	assert_eq(sim.current_actor_token(), "ally:0")

	assert_true(sim.set_mid_checkpoint())
	var checkpoint_hp1 := sim.minions[1].hp
	var checkpoint_potions := int(sim.battle_item_counts["hp_potion"])
	var checkpoint_part_hp := int(sim.boss_part_hp["arm"])
	assert_eq(sim.guarding_units, [1], "id1 is still guarding at the exact checkpoint moment")

	sim.resolve_player_action(0, "attack", "", -1, "arm")
	assert_eq(sim.current_actor_token(), "ally:1")
	assert_true(sim.guarding_units.is_empty(), "sanity: id1's guard cleared on its own next turn")
	sim.resolve_player_action(1, "item", "hp_potion", 1)  # a further potion, since the checkpoint
	# Force the part to destruction directly rather than looping combat
	# rounds to grind it down — the same technique the existing fizzle
	# test above uses (avoids RNG-dependent flakiness / party-wipe risk
	# from a long, open-ended attack loop; only the post-checkpoint state
	# itself matters here, not exactly how it got there).
	sim.boss_part_hp["arm"] = 0
	sim.boss_parts_destroyed.append("arm")
	assert_true(sim.boss_parts_destroyed.has("arm"), "sanity: the arm is destroyed since the checkpoint")
	assert_lt(int(sim.battle_item_counts["hp_potion"]), checkpoint_potions,
		"sanity: potion count genuinely dropped further since the checkpoint")

	assert_true(sim.use_rewind2())

	assert_eq(sim.minions[1].hp, checkpoint_hp1, "§12: hp restored")
	assert_eq(int(sim.battle_item_counts["hp_potion"]), checkpoint_potions, "§13/§29: potion count restored")
	assert_eq(sim.guarding_units, [1], "§14/§28: id1's guard state at the checkpoint moment is restored")
	assert_eq(int(sim.boss_part_hp["arm"]), checkpoint_part_hp, "§16: part hp restored")
	assert_false(sim.boss_parts_destroyed.has("arm"), "§17: the destroyed part comes back")


## §18-22: Boss Action Setの進行度・turn_order・turn_cursor・current_
## actor・NEXT5が、セットした瞬間の値へ正確に戻る——予兆済み（進行中）
## の状態でチェックポイントを取り、その後に割り込みまで進めてから戻す。
func test_rewind2_restores_action_set_progress_turn_order_and_next5() -> void:
	var sim := _action_set_sim(11, _potion_test_items())
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph -- Action Set now mid-progress
	assert_eq(sim.current_actor_token(), "ally:0")
	assert_ne(sim.boss_action_set_step, 0, "sanity: the telegraph actually advanced the set")

	assert_true(sim.set_mid_checkpoint())
	var checkpoint_step := sim.boss_action_set_step
	var checkpoint_turn_order := sim.turn_order.duplicate()
	var checkpoint_turn_cursor := sim.turn_cursor
	var checkpoint_actor := sim.current_actor_token()
	var checkpoint_next5 := sim.peek_next_actors(5)

	# Keep playing well past the checkpoint -- the interrupt fires and the
	# set completes, moving everything beyond the checkpointed moment.
	var advance_guard := 0
	while sim.boss_action_set_step == checkpoint_step and advance_guard < 10:
		var actor: String = sim.current_actor_token()
		if actor.begins_with("ally:"):
			sim.resolve_player_action(int(actor.substr(5)), "attack")
		else:
			sim.resolve_enemy_action("action_set_test_boss")
		advance_guard += 1
	assert_ne(sim.boss_action_set_step, checkpoint_step, "sanity: the set genuinely moved on")
	assert_ne(sim.turn_cursor, checkpoint_turn_cursor)

	assert_true(sim.use_rewind2())

	assert_eq(sim.boss_action_set_step, checkpoint_step, "§18: Action Set progress restored")
	assert_eq(sim.turn_order, checkpoint_turn_order, "§19: turn order restored")
	assert_eq(sim.turn_cursor, checkpoint_turn_cursor, "§20: turn cursor restored")
	assert_eq(sim.current_actor_token(), checkpoint_actor, "§21: current actor matches")
	assert_eq(sim.peek_next_actors(5), checkpoint_next5, "§22: NEXT5 matches")


## §23: REWINDⅡ後も、通常REWINDと同じ決定論性を持つ——同じ操作列を
## 再現すると、RNGが絡む敵の行動選択（_boss_choose_actionの旧ランダム
## AI経路、power4/40の2択でどちらが選ばれるかがRNG状態次第）まで含めて
## 完全に同じ結果になる。既存のtest_action_set_reproduces_identically_
## after_rewind_given_the_same_actionsと同じclosureパターンをmid_
## checkpointへ適用する。
func test_rewind2_reproduces_identical_boss_choices_given_the_same_actions() -> void:
	var sim := _rng_test_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	assert_true(sim.current_actor_token().begins_with("ally:"))
	assert_true(sim.set_mid_checkpoint())
	var checkpoint_seed := sim._rng.seed
	var checkpoint_state := sim._rng.state

	var play := func() -> Dictionary:
		while sim.current_actor_token().begins_with("ally:"):
			var actor: String = sim.current_actor_token()
			sim.resolve_player_action(int(actor.substr(5)), "attack")
		return sim.resolve_enemy_action("rng_test_boss")

	var first_run: Dictionary = play.call()
	assert_true(sim.use_rewind2())
	assert_eq(sim._rng.seed, checkpoint_seed, "§23: RNG seed restored")
	assert_eq(sim._rng.state, checkpoint_state, "§23: RNG state restored")
	var second_run: Dictionary = play.call()

	assert_eq(first_run, second_run,
		"same actions from the same restored RNG state -> identical boss choice")


## §24/§35: boss_intelはREWINDⅡの対象外——通常REWINDと同じ方針を維持する。
func test_rewind2_does_not_reset_boss_intel() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph -- recorded into boss_intel
	assert_true(sim.set_mid_checkpoint())
	assert_true(sim.boss_intel.has("action_set_test_boss"), "sanity: something was already learned")
	var intel_before := sim.boss_intel.duplicate(true)

	assert_true(sim.use_rewind2())

	assert_eq(sim.boss_intel, intel_before, "§24/§35: boss_intel is never touched by REWINDⅡ either")


## §25/§26/§27/§40: 通常REWINDとREWINDⅡはそれぞれ独立した戻り先を持ち、
## 互いの戻り先スナップショットを破壊しない——通常REWINDは常に戦闘開始
## 時点、REWINDⅡは常にプレイヤーが指定した途中地点のまま。
func test_normal_rewind_and_rewind2_go_to_different_points_without_corrupting_each_other() -> void:
	var sim := _action_set_sim(11, _potion_test_items())
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	var hp_at_fight_start := sim.minions[0].hp

	sim.resolve_player_action(0, "attack")
	sim.resolve_player_action(1, "attack")
	sim.resolve_player_action(2, "attack")
	sim.resolve_enemy_action("action_set_test_boss")  # telegraph, 0 damage -- HP still untouched here
	# push on to the boss's next real (damaging) action before checkpointing,
	# so the mid-checkpoint's HP is genuinely below the fight-start HP.
	var guard := 0
	while sim.minions[0].hp == hp_at_fight_start and guard < 10:
		var actor: String = sim.current_actor_token()
		if actor.begins_with("ally:"):
			sim.resolve_player_action(int(actor.substr(5)), "attack")
		else:
			sim.resolve_enemy_action("action_set_test_boss")
		guard += 1
	assert_lt(sim.minions[0].hp, hp_at_fight_start, "sanity: id0 has taken damage by now")
	assert_true(sim.current_actor_token().begins_with("ally:"), "safe moment to checkpoint")
	assert_true(sim.set_mid_checkpoint())
	var hp_at_mid_checkpoint := sim.minions[0].hp

	# Keep playing further -- more damage since the checkpoint.
	sim.resolve_player_action(int(sim.current_actor_token().substr(5)), "attack")
	guard = 0
	while sim.minions[0].hp == hp_at_mid_checkpoint and guard < 10:
		var actor: String = sim.current_actor_token()
		if actor.begins_with("ally:"):
			sim.resolve_player_action(int(actor.substr(5)), "attack")
		else:
			sim.resolve_enemy_action("action_set_test_boss")
		guard += 1
	assert_lt(sim.minions[0].hp, hp_at_mid_checkpoint, "sanity: further damage since the mid checkpoint")

	assert_true(sim.use_rewind2())
	assert_eq(sim.minions[0].hp, hp_at_mid_checkpoint,
		"§26: REWINDⅡ returns to the mid-fight point, not fight start")

	# Play on a bit more from the restored mid-point, then use the normal
	# REWIND -- must land back at the very start of the fight, not the
	# (already-spent) mid-point.
	sim.resolve_player_action(int(sim.current_actor_token().substr(5)), "attack")
	assert_true(sim.rewind_boss_fight())
	assert_eq(sim.minions[0].hp, hp_at_fight_start,
		"§25/§40: normal REWIND still goes all the way to fight start")
	assert_true(sim.mid_checkpoint_used, "REWINDⅡ's spent state survives the normal REWIND too (§11)")


## §29/§36: 解放状態(rewind2_unlocked)自体は恒久データ——戦闘が終わって
## 次の戦闘が始まっても解放されたまま。§3/§28（設定済み/使用済みは毎回
## リセット）とは対照的な扱いであることを明示する。
func test_rewind2_unlock_itself_persists_across_fights_unlike_the_per_fight_state() -> void:
	var sim := _action_set_sim()
	sim.set_rewind2_unlocked(true)
	sim.start_boss_fight()
	sim.flee_boss_fight()

	sim.start_boss_fight()  # a brand new fight

	assert_true(sim.rewind2_unlocked, "§29/§36: the unlock itself is permanent")
	assert_false(sim.mid_checkpoint_set, "but the per-fight state resets, §3/§28")
