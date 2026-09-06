extends GutTest

## RPG BOSS MAKER Phase 1 Step 4 — snapshot()/restore() (Turn REWIND primitive)
## tests. Exercises RBMBattle.snapshot()/restore() directly, against real
## resolve_turn() calls -- not just data-shape checks. Does not touch
## rbm_unit.gd/rbm_constants.gd/rbm_data_loader.gd/rbm_definition_loader.gd,
## and rbm_battle.gd's own existing 51 tests (tests/bossmaker/test_rbm_battle.gd)
## remain untouched.

func _boss_with_random_candidates() -> Dictionary:
	# 2 weighted candidates so _pick_boss_normal_action() actually rolls RNG,
	# plus a 3rd skill only reachable via a scripted action (for the
	# re-trigger test), and generous HP on both sides so several turns can be
	# resolved without anyone dying mid-test.
	return {
		"id": "snapshot_test_boss", "display_name": "Snapshot Boss",
		"hp": 5000, "atk": 100, "spd": 50,
		"skills": [
			{"id": "hit_a", "display_name": "A", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "hit_b", "display_name": "B", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "scripted_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 100},
		],
		"normal_action_candidates": [
			{"skill_id": "hit_a", "weight": 50},
			{"skill_id": "hit_b", "weight": 50},
		],
	}

func _party_defs(count: int = 2) -> Array[Dictionary]:
	var ids := ["hero", "butler", "healer", "samurai", "tank"]
	var out: Array[Dictionary] = []
	for i in range(count):
		out.append(RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % ids[i]))
	return out

func _battle(boss_def: Dictionary = {}, seed: int = 1, party_count: int = 2) -> RBMBattle:
	var def := boss_def if not boss_def.is_empty() else _boss_with_random_candidates()
	return RBMBattle.new(_party_defs(party_count), def, seed)

func _defend_all(battle: RBMBattle) -> Dictionary:
	var actions := {}
	for unit in battle.party:
		actions[str(unit.id)] = {"type": "defend"}
	return actions

# ---------------------------------------------------------------------------
# snapshot round-trip
# ---------------------------------------------------------------------------

func test_snapshot_then_restore_then_snapshot_again_is_identical() -> void:
	var battle := _battle()
	var s1 := battle.snapshot()
	battle.resolve_turn(_defend_all(battle))
	battle.restore(s1)
	var s2 := battle.snapshot()
	assert_eq(s1, s2, "restoring a snapshot and taking another must produce a deep-equal Dictionary")

func test_snapshot_taken_before_progressing_is_unaffected_by_later_battle_changes() -> void:
	# §9-8: advancing the battle after taking a snapshot must never
	# retroactively mutate that already-taken snapshot (no aliasing).
	var battle := _battle()
	var s1 := battle.snapshot()
	var s1_copy: Dictionary = s1.duplicate(true)
	battle.resolve_turn(_defend_all(battle))
	battle.resolve_turn(_defend_all(battle))
	assert_eq(s1, s1_copy, "a previously taken snapshot must stay byte-for-byte the same no matter what happens to the live battle afterward")

# ---------------------------------------------------------------------------
# HP / SP restoration
# ---------------------------------------------------------------------------

func test_hp_is_fully_restored_for_boss_and_all_allies() -> void:
	var battle := _battle()
	var snap := battle.snapshot()
	var hp_before := {"boss": battle.boss.hp}
	for unit in battle.party:
		hp_before[unit.id] = unit.hp

	battle.resolve_turn({"0": {"type": "attack"}, "1": {"type": "attack"}})
	battle.resolve_turn({"0": {"type": "attack"}, "1": {"type": "attack"}})
	# something must actually have changed, or this test would prove nothing.
	assert_true(battle.boss.hp != hp_before["boss"] or battle.party[0].hp != hp_before[0], "sanity: HP actually changed before restoring")

	battle.restore(snap)
	assert_eq(battle.boss.hp, hp_before["boss"])
	for unit in battle.party:
		assert_eq(unit.hp, hp_before[unit.id])

func test_sp_is_fully_restored() -> void:
	# SP starts full (unit_from_ally_def), so a plain "attack" (which only
	# GRANTS SP, capped at max) can never visibly change it from this state --
	# spend SP first via a real skill, snapshot, then verify restore brings
	# the pre-spend SP back.
	var samurai := RBMDataLoader.load_dict("res://data_bossmaker/allies/samurai.json")
	var battle := RBMBattle.new([samurai], _boss_with_random_candidates(), 1)
	var sp_before := battle.party[0].sp
	var snap := battle.snapshot()

	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})  # costs SP
	assert_ne(battle.party[0].sp, sp_before, "sanity: SP actually changed after spending it on a skill")

	battle.restore(snap)
	assert_eq(battle.party[0].sp, sp_before)

# ---------------------------------------------------------------------------
# timed effects (buffs) -- applied_at_turn / duration_turns / value
# ---------------------------------------------------------------------------

func test_ally_timed_effect_fully_restored() -> void:
	var battle := _battle()
	# hero (party[0]) casts hero_flame_wrap, a buff_atk_self skill.
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}, "1": {"type": "defend"}})
	var snap := battle.snapshot()
	var effect_before: Dictionary = (battle.party[0].timed_effects["atk_buff"] as Dictionary).duplicate(true)

	battle.resolve_turn(_defend_all(battle))
	battle.resolve_turn(_defend_all(battle))

	battle.restore(snap)
	var effect_after: Dictionary = battle.party[0].timed_effects["atk_buff"]
	assert_eq(effect_after, effect_before)
	assert_eq(int(effect_after["applied_at_turn"]), int(effect_before["applied_at_turn"]))
	assert_eq(int(effect_after["duration_turns"]), int(effect_before["duration_turns"]))
	assert_eq(float(effect_after["value"]), float(effect_before["value"]))

func test_party_timed_effect_fully_restored() -> void:
	var tank := RBMDataLoader.load_dict("res://data_bossmaker/allies/tank.json")
	var battle := RBMBattle.new([tank], _boss_with_random_candidates(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "tank_guard_boost"}})
	var snap := battle.snapshot()
	var effect_before: Dictionary = (battle.party_timed_effects["guard_boost"] as Dictionary).duplicate(true)

	battle.resolve_turn({"0": {"type": "defend"}})
	battle.resolve_turn({"0": {"type": "defend"}})

	battle.restore(snap)
	assert_eq(battle.party_timed_effects["guard_boost"], effect_before)

# ---------------------------------------------------------------------------
# transient per-turn combat state: defend / counter / iai / kabau
# ---------------------------------------------------------------------------

func test_temporary_combat_state_is_captured_and_restored() -> void:
	var samurai := RBMDataLoader.load_dict("res://data_bossmaker/allies/samurai.json")
	var battle := RBMBattle.new([samurai], _boss_with_random_candidates(), 1)
	# samurai_iai sets next_attack_bonus_multiplier; samurai_counter arms
	# counter_pending_this_turn + active_counter_skill. Both are single-target
	# self-affecting skills that don't need a target_id.
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var snap_after_iai := battle.snapshot()
	assert_true(float(snap_after_iai["units"]["0"]["next_attack_bonus_multiplier"]) != 1.0, "sanity: iai actually armed a bonus")

	# v0.1-B §10: a plain "type":"attack" is NOT an "攻撃スキル" and does not
	# consume iai -- an actual attack-effect SKILL (samurai_slash) is needed.
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})
	assert_eq(battle.party[0].next_attack_bonus_multiplier, 1.0, "sanity: the bonus was consumed by the attack skill")

	battle.restore(snap_after_iai)
	assert_true(battle.party[0].next_attack_bonus_multiplier != 1.0, "restoring must bring the still-pending iai bonus back")

func test_kabau_and_other_turn_end_cleared_fields_round_trip_through_the_snapshot_mechanism() -> void:
	# is_defending / protecting_ally_id / counter_pending_this_turn /
	# active_counter_skill are ALL unconditionally reset by TURN END at the
	# end of every single resolve_turn() call (Step 2 fix #2/#4) -- so at any
	# externally-observable "turn start" point (the only point REWIND ever
	# actually snapshots from, per §9-6), these fields are always already at
	# their default (false/-1/empty). There is no way to observe them
	# non-default from outside resolve_turn() through real gameplay. This test
	# instead directly exercises the snapshot/restore PLUMBING itself (the
	# same kind of white-box access Step 2's own tests use to isolate
	# mid-turn-only state, e.g. test_counter_triggers_at_most_once_per_turn) so
	# the mechanism is still verified correct and stays correct even if a
	# future engine change ever makes one of these fields externally
	# observable as non-default.
	var tank := RBMDataLoader.load_dict("res://data_bossmaker/allies/tank.json")
	var battle := RBMBattle.new([tank], _boss_with_random_candidates(), 1)
	var unit := battle.party[0]

	unit.is_defending = true
	unit.protecting_ally_id = 5
	unit.counter_pending_this_turn = true
	unit.active_counter_skill = battle._find_skill(unit, "tank_smash")
	var snap := battle.snapshot()

	unit.is_defending = false
	unit.protecting_ally_id = -1
	unit.counter_pending_this_turn = false
	unit.active_counter_skill = {}

	battle.restore(snap)
	assert_true(unit.is_defending)
	assert_eq(unit.protecting_ally_id, 5)
	assert_true(unit.counter_pending_this_turn)
	assert_eq(str(unit.active_counter_skill.get("id", "")), "tank_smash")

# ---------------------------------------------------------------------------
# turn / battle result
# ---------------------------------------------------------------------------

func test_current_turn_is_restored() -> void:
	var battle := _battle()
	battle.resolve_turn(_defend_all(battle))
	battle.resolve_turn(_defend_all(battle))
	var snap := battle.snapshot()  # this is "Turn 3's start" snapshot
	battle.resolve_turn(_defend_all(battle))
	battle.resolve_turn(_defend_all(battle))
	assert_eq(battle.current_turn, 5)

	battle.restore(snap)
	assert_eq(battle.current_turn, 3)

func test_battle_over_and_winner_are_restored() -> void:
	var boss := _boss_with_random_candidates()
	boss["hp"] = 1
	var battle := _battle(boss)
	var snap := battle.snapshot()
	battle.resolve_turn({"0": {"type": "attack"}, "1": {"type": "attack"}})  # kills the 1-HP boss
	assert_true(battle.battle_over)
	assert_eq(battle.winner, "ally")

	battle.restore(snap)
	assert_false(battle.battle_over)
	assert_eq(battle.winner, "")

# ---------------------------------------------------------------------------
# RNG: same snapshot + same inputs -> byte-identical results
# ---------------------------------------------------------------------------

func test_rng_state_restore_reproduces_the_same_boss_skill_picks_and_damage() -> void:
	var battle := _battle(_boss_with_random_candidates(), 1)
	var snap := battle.snapshot()

	var first_run: Array = []
	for i in range(6):
		var result := battle.resolve_turn(_defend_all(battle))
		for entry in result["log"]:
			if str(entry.get("actor", "")) == "boss":
				first_run.append(entry.duplicate(true))

	battle.restore(snap)

	var second_run: Array = []
	for i in range(6):
		var result := battle.resolve_turn(_defend_all(battle))
		for entry in result["log"]:
			if str(entry.get("actor", "")) == "boss":
				second_run.append(entry.duplicate(true))

	assert_eq(first_run.size(), second_run.size())
	# sanity: this boss has 2 weighted candidates, so across 6 turns the picks
	# should not ALL be identical to each other within a single run (otherwise
	# this test wouldn't actually be exercising real randomness).
	var picks: Array = []
	for entry in first_run:
		picks.append(str(entry.get("skill_id", "")))
	var all_same := true
	for pick in picks:
		if pick != picks[0]:
			all_same = false
			break
	assert_false(all_same, "sanity: the 2-candidate boss must pick differently at least once across 6 turns for this to be a meaningful RNG test")
	for i in range(first_run.size()):
		assert_eq(first_run[i], second_run[i], "boss log entry %d must match exactly after restoring RNG state and replaying the same inputs" % i)

func test_random_single_target_selection_matches_after_restore() -> void:
	# party of 3 so the boss's single-target ally_random_single pick has real
	# choices to make, not just a forced single survivor.
	var battle := _battle(_boss_with_random_candidates(), 7, 3)
	var snap := battle.snapshot()

	var actions := _defend_all(battle)
	var first_targets: Array = []
	for i in range(5):
		var result := battle.resolve_turn(actions)
		for entry in result["log"]:
			if str(entry.get("actor", "")) == "boss" and entry.has("target"):
				first_targets.append(entry["target"])

	battle.restore(snap)
	var second_targets: Array = []
	for i in range(5):
		var result := battle.resolve_turn(actions)
		for entry in result["log"]:
			if str(entry.get("actor", "")) == "boss" and entry.has("target"):
				second_targets.append(entry["target"])

	assert_eq(first_targets, second_targets, "the boss's random single-target choice must reproduce identically after restore")

# ---------------------------------------------------------------------------
# 指定行動 re-trigger
# ---------------------------------------------------------------------------

func test_scripted_action_fires_again_after_restoring_a_pre_turn_snapshot() -> void:
	var boss := _boss_with_random_candidates()
	boss["hp"] = 500
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_start_interrupt", "order": 0}]
	var battle := _battle(boss)
	battle.boss.hp = 200
	var snap := battle.snapshot()

	var first := battle.resolve_turn(_defend_all(battle))
	var first_boss_entries: Array = []
	for entry in first["log"]:
		if str(entry.get("actor", "")) == "boss":
			first_boss_entries.append(entry)
	assert_true(first_boss_entries.size() >= 1)
	assert_eq(str(first_boss_entries[0]["skill_id"]), "scripted_heal", "sanity: the scripted turn_start_interrupt fired on the first run")

	battle.restore(snap)
	var second := battle.resolve_turn(_defend_all(battle))
	var second_boss_entries: Array = []
	for entry in second["log"]:
		if str(entry.get("actor", "")) == "boss":
			second_boss_entries.append(entry)
	assert_true(second_boss_entries.size() >= 1)
	assert_eq(str(second_boss_entries[0]["skill_id"]), "scripted_heal", "the same scripted action must fire again, not be treated as already-consumed")

# ---------------------------------------------------------------------------
# §3修正: REWIND再発火の全3タイミング (turn_start_interrupt above was the only
# one already covered through a real resolve_turn() before this round --
# replace/turn_end_interrupt, plus all 3 together, add the missing coverage).
# ---------------------------------------------------------------------------

func _boss_log_entries(log: Array) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(entry)
	return out

func test_replace_scripted_action_fires_again_and_suppresses_the_normal_action_after_a_rewind() -> void:
	var boss := _boss_with_random_candidates()
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "replace", "order": 0}]
	var battle := _battle(boss)
	battle.boss.hp = 200
	var snap := battle.snapshot()

	var first := battle.resolve_turn(_defend_all(battle))
	var first_boss_entries := _boss_log_entries(first["log"])
	assert_eq(first_boss_entries.size(), 1, "'replace' takes the single normal-action slot -- exactly one boss entry, not the scripted skill plus hit_a/hit_b")
	assert_eq(str(first_boss_entries[0]["skill_id"]), "scripted_heal", "sanity: replace fired instead of a random normal-action pick on the first run")

	battle.restore(snap)
	var second := battle.resolve_turn(_defend_all(battle))
	var second_boss_entries := _boss_log_entries(second["log"])
	assert_eq(second_boss_entries.size(), 1, "still exactly one boss entry after REWIND -- the normal action is suppressed again, not restored alongside the scripted one")
	assert_eq(str(second_boss_entries[0]["skill_id"]), "scripted_heal", "'replace' fires again, not treated as already-consumed")
	assert_eq(first["log"], second["log"], "the two runs' logs must match exactly")
	assert_eq(battle.boss.hp, 300, "HP after REWIND+replay must match the first run's result (200 + 100 heal, both times)")

func test_turn_end_interrupt_scripted_action_fires_again_after_a_rewind() -> void:
	var boss := _boss_with_random_candidates()
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_end_interrupt", "order": 0}]
	var battle := _battle(boss)
	battle.boss.hp = 200
	var snap := battle.snapshot()

	var first := battle.resolve_turn(_defend_all(battle))
	var first_boss_entries := _boss_log_entries(first["log"])
	assert_eq(first_boss_entries.size(), 2, "turn_end_interrupt is an EXTRA action after the normal one -- 2 boss entries")
	assert_eq(str(first_boss_entries[1]["skill_id"]), "scripted_heal", "sanity: the scripted turn_end_interrupt fired after the normal action on the first run")
	var hp_after_first := battle.boss.hp

	battle.restore(snap)
	var second := battle.resolve_turn(_defend_all(battle))
	var second_boss_entries := _boss_log_entries(second["log"])
	assert_eq(second_boss_entries.size(), 2, "still 2 boss entries after REWIND -- the normal action still fires, then turn_end_interrupt fires again after it")
	assert_eq(str(second_boss_entries[1]["skill_id"]), "scripted_heal", "turn_end_interrupt fires again, not treated as already-consumed")
	assert_eq(first["log"], second["log"], "the two runs' logs must match exactly")
	assert_eq(battle.boss.hp, hp_after_first, "resulting HP after the second run must match the first")

func test_all_three_scripted_timings_together_reproduce_identically_after_a_rewind() -> void:
	var boss := _boss_with_random_candidates()
	boss["scripted_actions"] = [
		{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_start_interrupt", "order": 0},
		{"turn": 1, "skill_id": "scripted_heal", "timing": "replace", "order": 0},
		{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_end_interrupt", "order": 0},
	]
	var battle := _battle(boss)
	battle.boss.hp = 200
	var snap := battle.snapshot()

	var first := battle.resolve_turn(_defend_all(battle))
	var first_boss_entries := _boss_log_entries(first["log"])
	# turn_start_interrupt, then "replace" (taking the normal-action slot
	# instead of a random hit_a/hit_b pick), then turn_end_interrupt -- 3 boss
	# entries total, all the scripted skill, no normal action anywhere in between.
	assert_eq(first_boss_entries.size(), 3, "turn_start + replace (no separate normal action) + turn_end = 3 boss entries")
	for entry in first_boss_entries:
		assert_eq(str(entry["skill_id"]), "scripted_heal")
	var hp_after_first := battle.boss.hp
	var party_hp_after_first: Array = []
	for unit in battle.party:
		party_hp_after_first.append(unit.hp)

	battle.restore(snap)
	var second := battle.resolve_turn(_defend_all(battle))
	var second_boss_entries := _boss_log_entries(second["log"])
	assert_eq(second_boss_entries.size(), 3, "all 3 scripted timings fire again after REWIND, and 'replace' still suppresses the normal action")
	for entry in second_boss_entries:
		assert_eq(str(entry["skill_id"]), "scripted_heal")
	assert_eq(first["log"], second["log"], "the full log -- order, all 3 scripted actions, suppressed normal action -- must match exactly")
	assert_eq(battle.boss.hp, hp_after_first, "final boss HP must match")
	for i in range(battle.party.size()):
		assert_eq(battle.party[i].hp, party_hp_after_first[i], "final party HP must match for unit %d" % i)

# ---------------------------------------------------------------------------
# repeated REWIND stress
# ---------------------------------------------------------------------------

func test_many_repeated_snapshot_restore_cycles_do_not_corrupt_state() -> void:
	var battle := _battle()
	var turn_1_snap := battle.snapshot()

	for cycle in range(25):
		battle.resolve_turn(_defend_all(battle))
		battle.resolve_turn(_defend_all(battle))
		var mid_snap := battle.snapshot()
		battle.resolve_turn(_defend_all(battle))
		battle.restore(mid_snap)
		battle.restore(turn_1_snap)
		assert_eq(battle.current_turn, 1, "cycle %d: restoring the turn-1 snapshot must always land exactly back on turn 1" % cycle)

	# after 25 cycles, restoring turn_1_snap one final time must still
	# reproduce the ORIGINAL turn-1 state exactly (no accumulated drift/aliasing).
	var final_snap := battle.snapshot()
	assert_eq(final_snap, turn_1_snap, "no state drift after many repeated snapshot/restore cycles")
