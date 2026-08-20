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
