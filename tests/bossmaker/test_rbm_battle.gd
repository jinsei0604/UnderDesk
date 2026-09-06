extends GutTest

## RPG BOSS MAKER Phase 1 — battle core tests (Step 2).
## Exercises RBMBattle/RBMUnit/RBMConstants/RBMDataLoader entirely headless,
## against the real data_bossmaker/ JSON so the loader path is covered too.

const ALLY_DIR := "res://data_bossmaker/allies/"
const BOSS_PATH := "res://data_bossmaker/enemies/test_boss.json"

var hero_def: Dictionary
var butler_def: Dictionary
var healer_def: Dictionary
var samurai_def: Dictionary
var tank_def: Dictionary
var boss_def: Dictionary

func before_each() -> void:
	hero_def = RBMDataLoader.load_dict(ALLY_DIR + "hero.json")
	butler_def = RBMDataLoader.load_dict(ALLY_DIR + "butler.json")
	healer_def = RBMDataLoader.load_dict(ALLY_DIR + "healer.json")
	samurai_def = RBMDataLoader.load_dict(ALLY_DIR + "samurai.json")
	tank_def = RBMDataLoader.load_dict(ALLY_DIR + "tank.json")
	boss_def = RBMDataLoader.load_dict(BOSS_PATH)

func _full_party() -> Array[Dictionary]:
	var party: Array[Dictionary] = [hero_def, butler_def, healer_def, samurai_def, tank_def]
	return party

func _one(def: Dictionary) -> Array[Dictionary]:
	var party: Array[Dictionary] = [def]
	return party

func _two(a: Dictionary, b: Dictionary) -> Array[Dictionary]:
	var party: Array[Dictionary] = [a, b]
	return party

func _find_log_entry(log: Array, actor) -> Dictionary:
	# Log entries mix int (ally id) and String ("boss") actor keys; GDScript's ==
	# raises a runtime error when comparing those types directly, so compare as
	# strings instead of risking a type mismatch.
	var actor_str := str(actor)
	for entry in log:
		if str(entry.get("actor", "")) == actor_str:
			return entry
	return {}

func _neutral_boss(hp: int = 100000, atk: int = 1, spd: int = 1) -> Dictionary:
	return {
		"id": "neutral_boss", "display_name": "無属性ボス", "hp": hp, "atk": atk, "spd": spd,
		"skills": [], "normal_action_candidates": [],
	}

func _attacking_boss(atk: int, spd: int = 999, weak: Variant = null, resist: Variant = null) -> Dictionary:
	var def := {
		"id": "atk_boss", "display_name": "攻撃ボス", "hp": 100000, "atk": atk, "spd": spd,
		"skills": [
			{"id": "boss_hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [{"skill_id": "boss_hit", "weight": 1}],
	}
	if weak != null:
		def["weak_attribute"] = weak
	if resist != null:
		def["resist_attribute"] = resist
	return def

# ---------------------------------------------------------------------------
# 1. Fixed character data (v0.1-A / v0.1-B §2, §7)
# ---------------------------------------------------------------------------

func test_all_five_stats_match_spec() -> void:
	var battle := RBMBattle.new(_full_party(), boss_def, 1)
	var expected := [
		{"hp": 650, "atk": 240, "spd": 100, "sp": 100},
		{"hp": 450, "atk": 220, "spd": 120, "sp": 150},
		{"hp": 800, "atk": 140, "spd": 110, "sp": 120},
		{"hp": 700, "atk": 280, "spd": 70, "sp": 130},
		{"hp": 950, "atk": 200, "spd": 140, "sp": 100},
	]
	for i in range(5):
		var unit := battle.party[i]
		assert_eq(unit.max_hp, int(expected[i]["hp"]), "unit %d max_hp" % i)
		assert_eq(unit.atk, int(expected[i]["atk"]), "unit %d atk" % i)
		assert_eq(unit.spd, int(expected[i]["spd"]), "unit %d spd" % i)
		assert_eq(unit.max_sp, int(expected[i]["sp"]), "unit %d max_sp" % i)
		assert_eq(unit.skills.size(), 4, "unit %d skill count" % i)

func test_battle_start_sp_is_full_for_sp_bearing_units() -> void:
	var battle := RBMBattle.new(_full_party(), boss_def, 1)
	assert_eq(battle.party[0].sp, 100, "hero starts at max SP")
	assert_eq(battle.party[1].sp, 150, "butler starts at max SP")
	assert_eq(battle.party[2].sp, 120, "healer starts at max SP")
	assert_eq(battle.party[3].sp, 130, "samurai starts at max SP")

func test_tank_uses_the_standard_sp_resource_with_max_100() -> void:
	var battle := RBMBattle.new(_full_party(), boss_def, 1)
	var tank := battle.party[4]
	assert_true(tank.has_sp_resource())
	assert_eq(tank.max_sp, 100)
	assert_eq(tank.sp, 100)

# ---------------------------------------------------------------------------
# 2. Normal attack (v0.1-B §7)
# ---------------------------------------------------------------------------

func test_normal_attack_deals_atk_times_one() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	var result := battle.resolve_turn({"0": {"type": "attack"}})
	var entry := _find_log_entry(result["log"], 0)
	assert_eq(int(entry["amount"]), 240, "hero ATK 240 x1.0, no attribute bonus, boss has no reduction")

func test_normal_attack_restores_ten_sp_capped_at_max() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.party[0].sp = 95
	battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.party[0].sp, 100, "SP+10 clamped at max_sp (100)")

	var battle2 := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle2.party[0].sp = 20
	battle2.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle2.party[0].sp, 30, "SP+10 with headroom")

func test_normal_attack_restores_sp_for_the_tank_via_the_standard_path() -> void:
	var battle := RBMBattle.new(_one(tank_def), _neutral_boss(), 1)
	battle.party[0].sp = 50
	battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.party[0].sp, 60, "tank now follows the same normal-attack SP recovery path")
	assert_true(battle.party[0].has_sp_resource())

# ---------------------------------------------------------------------------
# 3. Attribute correction (v0.1-B §5, §8)
# ---------------------------------------------------------------------------

func test_weak_attribute_multiplies_damage_by_1_2() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(1, 999, "FIRE"), 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	var entry := _find_log_entry(result["log"], 0)
	# 240 * 1.5 (skill) * 1.2 (weak) = 432.0
	assert_eq(int(entry["amount"]), 432)

func test_resist_attribute_multiplies_damage_by_0_8() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(1, 999, null, "FIRE"), 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	var entry := _find_log_entry(result["log"], 0)
	# 240 * 1.5 * 0.8 = 288.0
	assert_eq(int(entry["amount"]), 288)

func test_neutral_attribute_relationship_is_1_0() -> void:
	# butler is ICE; a boss with no ICE weakness/resistance takes plain damage.
	var battle := RBMBattle.new(_one(butler_def), _attacking_boss(1, 999, "FIRE", "WIND"), 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "butler_ice_bolt"}})
	var entry := _find_log_entry(result["log"], 0)
	# 220 * 2.5 * 1.0 = 550.0
	assert_eq(int(entry["amount"]), 550)

func test_ally_own_weakness_resistance_derives_from_their_attack_attribute() -> void:
	# v0.1-B §8: hero is FIRE -> weak to ICE, resists FIRE.
	var battle := RBMBattle.new(_one(hero_def), boss_def, 1)
	var hero := battle.party[0]
	assert_eq(hero.weak_attribute, RBMConstants.Attribute.ICE)
	assert_eq(hero.resist_attribute, RBMConstants.Attribute.FIRE)
	# tank is NEUTRAL -> no weakness, no resistance.
	var battle2 := RBMBattle.new(_one(tank_def), boss_def, 1)
	var tank := battle2.party[0]
	assert_eq(tank.weak_attribute, null)
	assert_eq(tank.resist_attribute, null)

# ---------------------------------------------------------------------------
# 4. Damage rounding (v0.1-B §6, §7)
# ---------------------------------------------------------------------------

func test_final_damage_rounds_to_nearest_integer() -> void:
	# 151 * 0.5 (defend) = 75.5 -> rounds to 76, not truncated to 75.
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(151), 1)
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(entry["amount"]), 76)

func test_zero_damage_is_allowed_not_floored_to_one() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(1), 1)
	battle.party_timed_effects["iron_wall"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.10}
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	# 1 * 0.5 * 0.9 = 0.45 -> rounds to 0. UnderDesk's old max(1, ...) floor must NOT apply here.
	assert_eq(int(entry["amount"]), 0)

# ---------------------------------------------------------------------------
# 5. Defense / reduction stacking (v0.1-B §7, §16)
# ---------------------------------------------------------------------------

func test_basic_defend_halves_damage() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(200), 1)
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(entry["amount"]), 100)

func test_guard_boost_changes_defend_rate_to_sixty_percent() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(200), 1)
	battle.party_timed_effects["guard_boost"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.6}
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(entry["amount"]), 80)

func test_iron_wall_reduces_damage_by_ten_percent_even_without_defending() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(200), 1)
	battle.party_timed_effects["iron_wall"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.10}
	var result := battle.resolve_turn({"0": {"type": "attack"}})  # not defending
	var entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(entry["amount"]), 180)

func test_defend_plus_iron_wall_stack_multiplicatively_to_55_percent() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(1000), 1)
	battle.party_timed_effects["iron_wall"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.10}
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	# 1000 -> 500 (defend 50%) -> 450 (iron wall 10%) = 55% total reduction.
	assert_eq(int(entry["amount"]), 450)

func test_guard_boost_plus_iron_wall_stack_multiplicatively_to_64_percent() -> void:
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(1000), 1)
	battle.party_timed_effects["guard_boost"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.6}
	battle.party_timed_effects["iron_wall"] = {"applied_at_turn": 1, "duration_turns": 1, "value": 0.10}
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	# 1000 -> 400 (defend 60%) -> 360 (iron wall 10%) = 64% total reduction.
	assert_eq(int(entry["amount"]), 360)

# ---------------------------------------------------------------------------
# 6. Turn order (v0.1-B §10, confirmed)
# ---------------------------------------------------------------------------

func test_turn_order_is_spd_descending() -> void:
	var battle := RBMBattle.new(_full_party(), _neutral_boss(100000, 1, 90), 1)
	# tank(140) > butler(120) > healer(110) > boss(90) > hero(100)... wait compute properly below.
	var spds := {"ally:0": 100, "ally:1": 120, "ally:2": 110, "ally:3": 70, "ally:4": 140, "boss": 90}
	var last_spd := 99999
	for token in battle.turn_order:
		var spd: int = spds[token]
		assert_true(spd <= last_spd, "turn order must be SPD-descending at token %s" % token)
		last_spd = spd

func test_ally_acts_before_boss_on_equal_spd() -> void:
	# hero SPD 100 vs boss SPD 100 -> ally must come first, no coin flip.
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(100000, 1, 100), 1)
	assert_eq(battle.turn_order, ["ally:0", "boss"])

func test_spd_tiebreak_is_deterministic_across_repeated_construction() -> void:
	for i in range(5):
		var battle := RBMBattle.new(_one(hero_def), _neutral_boss(100000, 1, 100), i)
		assert_eq(battle.turn_order, ["ally:0", "boss"], "tie-break must never be randomized")

# ---------------------------------------------------------------------------
# 7. Heal / downed units (v0.1-B §9, §11)
# ---------------------------------------------------------------------------

func test_heal_does_not_exceed_max_hp() -> void:
	var battle := RBMBattle.new(_two(hero_def, healer_def), _neutral_boss(), 1)
	battle.party[0].hp = battle.party[0].max_hp - 50
	var result := battle.resolve_turn({"1": {"type": "skill", "skill_id": "healer_heal_single", "target_id": 0}})
	assert_eq(battle.party[0].hp, battle.party[0].max_hp)
	var entry := _find_log_entry(result["log"], 1)
	assert_eq(int(entry["amount"]), 50, "healed amount is clamped, not the full 400")

func test_downed_unit_cannot_be_healed() -> void:
	var battle := RBMBattle.new(_two(hero_def, healer_def), _neutral_boss(), 1)
	battle.party[0].hp = 0
	var result := battle.resolve_turn({"1": {"type": "skill", "skill_id": "healer_heal_single", "target_id": 0}})
	var entry := _find_log_entry(result["log"], 1)
	assert_true(bool(entry.get("failed", false)))
	assert_eq(battle.party[0].hp, 0)

func test_downed_unit_cannot_act() -> void:
	var battle := RBMBattle.new(_two(hero_def, healer_def), _neutral_boss(), 1)
	battle.party[0].hp = 0
	var result := battle.resolve_turn({"0": {"type": "attack"}, "1": {"type": "attack"}})
	var entry := _find_log_entry(result["log"], 0)
	assert_true(entry.is_empty(), "downed unit must not appear in the resolution log at all")

func test_action_targeting_an_ally_that_died_earlier_this_turn_fails_silently() -> void:
	# An "ally_all" boss hit (deterministic, unlike a random single-target pick)
	# calibrated to exceed hero's 650 HP but not healer's 800 HP, so hero is
	# downed and healer survives, both from the SAME boss action earlier in the
	# turn (boss SPD 999 acts before either ally).
	var aoe_boss := {
		"id": "aoe_boss", "display_name": "全体攻撃ボス", "hp": 100000, "atk": 700, "spd": 999,
		"skills": [{"id": "boss_aoe", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
		"normal_action_candidates": [{"skill_id": "boss_aoe", "weight": 1}],
	}
	var battle := RBMBattle.new(_two(hero_def, healer_def), aoe_boss, 1)
	var result := battle.resolve_turn({
		"1": {"type": "skill", "skill_id": "healer_heal_single", "target_id": 0},
	})
	assert_eq(battle.party[0].hp, 0, "hero (650 HP) was downed by the boss's 700-damage AoE this turn")
	assert_true(battle.party[1].hp > 0, "healer (800 HP) survived the same hit and could still act")
	var heal_entry := _find_log_entry(result["log"], 1)
	assert_true(bool(heal_entry.get("failed", false)), "heal on a since-downed target must not auto-redirect")

# ---------------------------------------------------------------------------
# 8. Effect durations (v0.1-B §9)
# ---------------------------------------------------------------------------

func test_atk_buff_expires_after_its_duration() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})  # turn 1, 3-turn buff
	assert_true(RBMConstants.timed_effect_active(battle.party[0].timed_effects, "atk_buff", 1))
	assert_true(RBMConstants.timed_effect_active(battle.party[0].timed_effects, "atk_buff", 2))
	assert_true(RBMConstants.timed_effect_active(battle.party[0].timed_effects, "atk_buff", 3))
	assert_false(RBMConstants.timed_effect_active(battle.party[0].timed_effects, "atk_buff", 4))

func test_atk_buff_actually_multiplies_subsequent_damage() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})
	var result := battle.resolve_turn({"0": {"type": "attack"}})
	var entry := _find_log_entry(result["log"], 0)
	# 240 * 1.75 (flame wrap) * 1.0 (normal attack multiplier) = 420.0
	assert_eq(int(entry["amount"]), 420)

func test_reusing_an_effect_refreshes_duration_without_stacking_the_multiplier() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})  # applied at turn 1
	battle.resolve_turn({"0": {"type": "attack"}})  # turn 2
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})  # re-applied at turn 3
	var effect: Dictionary = battle.party[0].timed_effects["atk_buff"]
	assert_eq(int(effect["applied_at_turn"]), 3, "duration window restarts from the re-use turn")
	assert_almost_eq(float(effect["value"]), 1.75, 0.0001, "multiplier does not stack (still x1.75, not x3.0625)")

func test_one_turn_effect_is_active_only_through_the_turn_it_was_used() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})
	# swap in a 1-turn effect manually to check the boundary precisely
	RBMConstants.set_timed_effect(battle.party_timed_effects, "iron_wall", battle.current_turn, 1, 0.10)
	var applied_turn := battle.current_turn
	assert_true(RBMConstants.timed_effect_active(battle.party_timed_effects, "iron_wall", applied_turn))
	assert_false(RBMConstants.timed_effect_active(battle.party_timed_effects, "iron_wall", applied_turn + 1))

# ---------------------------------------------------------------------------
# 9. 居合の構え (iai) and カウンター (counter) — v0.1-B §10
# ---------------------------------------------------------------------------

func test_iai_does_not_apply_to_normal_attack() -> void:
	var battle := RBMBattle.new(_one(samurai_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var result := battle.resolve_turn({"0": {"type": "attack"}})
	var entry := _find_log_entry(result["log"], 0)
	# samurai ATK 280 x1.0, NOT x2.5 -- iai must remain pending afterwards.
	assert_eq(int(entry["amount"]), 280)
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.5, 0.0001, "iai is still pending; normal attack did not consume it")

func test_iai_multiplies_damage_of_the_next_attack_skill_by_2_5_only_once() -> void:
	var battle := RBMBattle.new(_one(samurai_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})
	var entry := _find_log_entry(result["log"], 0)
	# 280 * 2.0 (skill) * 2.5 (iai) = 1400.0
	assert_eq(int(entry["amount"]), 1400)
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 1.0, 0.0001, "iai consumed after one attack-skill use")

	# a further attack skill must NOT be doubled again.
	var result2 := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})
	var entry2 := _find_log_entry(result2["log"], 0)
	assert_eq(int(entry2["amount"]), 560, "560 = 280 x2.0, no lingering bonus")

func test_iai_plus_counter_succeeds_when_counter_actually_triggers() -> void:
	# samurai SPD 70 > boss SPD 10 here, so the samurai's counter (activated on
	# their own turn) is still in place when the boss attacks later that turn.
	var boss := _attacking_boss(100, 10)
	var battle := RBMBattle.new(_one(samurai_def), boss, 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_counter"}})
	var boss_entry := _find_log_entry(result["log"], "boss")
	assert_true(bool(boss_entry.get("blocked", false)), "the boss's attack was intercepted")
	assert_true(bool(boss_entry.get("counter", false)))
	# reflected: samurai ATK 280 x3.0 (counter) x2.5 (iai, consumed here) = 2100.0
	assert_eq(int(boss_entry["reflected"]), 2100)
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 1.0, 0.0001, "iai was consumed by the counter-reflect")

func test_iai_is_preserved_when_the_counter_does_not_trigger() -> void:
	# boss SPD 999 > samurai SPD 70, so the boss has already acted before the
	# samurai's counter is even activated this turn -- the counter is wasted.
	var boss := _attacking_boss(100, 999)
	var battle := RBMBattle.new(_one(samurai_def), boss, 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_counter"}})
	var boss_entry := _find_log_entry(result["log"], "boss")
	assert_false(bool(boss_entry.get("blocked", false)), "counter had nothing left to intercept this turn")
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.5, 0.0001, "iai must remain pending -- the counter never triggered")
	assert_false(battle.party[0].counter_pending_this_turn, "counter stance clears at turn end regardless of trigger")

func test_iai_clears_when_the_samurai_is_downed() -> void:
	# SPD 1 keeps the samurai (SPD 70) acting before the boss on every turn, so
	# the boss's (initially harmless) counter-hit can never pre-empt the iai cast.
	var boss := _attacking_boss(1, 1)
	var battle := RBMBattle.new(_one(samurai_def), boss, 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.5, 0.0001, "iai armed")
	battle.boss.atk = 100000  # now lethal, even through a 50% defend
	battle.resolve_turn({"0": {"type": "defend"}})
	assert_true(battle.party[0].is_downed())
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 1.0, 0.0001, "iai clears the instant the samurai is downed")

# ---------------------------------------------------------------------------
# 10. Full mock battle, headless, start to finish
# ---------------------------------------------------------------------------

func test_full_mock_battle_runs_to_completion_without_a_ui() -> void:
	var battle := RBMBattle.new(_full_party(), boss_def, 42)
	var turns := 0
	while not battle.battle_over and turns < 200:
		var actions := {
			"0": {"type": "skill", "skill_id": "hero_slash"},
			"1": {"type": "skill", "skill_id": "butler_ice_bolt"},
			"2": {"type": "skill", "skill_id": "healer_shock"},
			"3": {"type": "skill", "skill_id": "samurai_slash"},
			"4": {"type": "attack"},
		}
		var result := battle.resolve_turn(actions)
		turns += 1
		# Fix #5: "turn" reports the turn that was JUST resolved (this loop's own
		# 1-indexed counter), not the internal next-turn cursor.
		assert_eq(int(result["turn"]), turns)
	assert_true(battle.battle_over, "the mock battle must actually conclude, not loop forever")
	assert_eq(battle.winner, "ally", "the fixed party should be able to defeat the fixed test boss")
	assert_true(turns > 1, "the battle should take more than a single turn (sanity check)")
	assert_true(turns < 200, "did not hit the safety cap")

# ---------------------------------------------------------------------------
# 11. Step 2 code-review fixes — かばう timing/scope, no attack fallback,
#     unfulfilled-action SP, counter one-shot logging, real-skill wiring.
# ---------------------------------------------------------------------------

func _aoe_boss(atk: int, spd: int = 1) -> Dictionary:
	return {
		"id": "aoe_boss", "display_name": "全体攻撃ボス", "hp": 100000, "atk": atk, "spd": spd,
		"skills": [{"id": "aoe_hit", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
		"normal_action_candidates": [{"skill_id": "aoe_hit", "weight": 1}],
	}

## Finds a seed for which the boss's single-target pick lands on `desired_target_id`
## (both allies alive, plain attacks, no かばう involved) — used only to make an
## otherwise-random single-target hit deterministic for a specific test.
func _find_seed_targeting(ally_defs: Array[Dictionary], boss_def_: Dictionary, desired_target_id: int, max_seed: int = 100) -> int:
	for seed in range(max_seed):
		var probe := RBMBattle.new(ally_defs.duplicate(), boss_def_, seed)
		var actions := {}
		for unit in probe.party:
			actions[str(unit.id)] = {"type": "attack"}
		var probe_result := probe.resolve_turn(actions)
		var boss_entry := _find_log_entry(probe_result["log"], "boss")
		if int(boss_entry.get("target", -1)) == desired_target_id:
			return seed
	return -1

func test_kabau_protects_only_against_single_target_attacks() -> void:
	# required fix #1
	var seed := _find_seed_targeting(_two(tank_def, hero_def), _attacking_boss(50, 1), 1)
	assert_true(seed >= 0, "must find a seed where the boss targets the hero (id 1) with a plain attack")

	var battle := RBMBattle.new(_two(tank_def, hero_def), _attacking_boss(50, 1), seed)
	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1},
		"1": {"type": "attack"},
	})
	var boss_entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(boss_entry["target"]), 0, "the tank (0) intercepted the single-target hit meant for the hero (1)")

func test_kabau_does_not_activate_on_an_all_target_attack() -> void:
	# required fix #1. Guards against the specific old bug where an "ally_all"
	# hit still redirected the protected ally's share onto the tank ON TOP OF
	# the tank's own share -- i.e. the tank silently absorbed two hits' worth
	# of damage while the protected ally took none.
	var battle := RBMBattle.new(_two(tank_def, hero_def), _aoe_boss(100), 1)
	var tank_hp_before := battle.party[0].hp
	var hero_hp_before := battle.party[1].hp

	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1},
		"1": {"type": "attack"},
	})
	var boss_entry := _find_log_entry(result["log"], "boss")
	var hits: Dictionary = boss_entry["hits"]
	var tank_hit: Dictionary = hits[0]
	var hero_hit: Dictionary = hits[1]

	# hero was actually hit himself, not redirected away.
	assert_eq(int(hero_hit["target"]), 1, "hero's own hit entry records hero, not the tank, as the target")
	assert_eq(int(hero_hit["amount"]), 100)
	assert_eq(battle.party[1].hp, hero_hp_before - 100, "hero's HP actually dropped by his own AoE share")

	# the tank was charged for exactly one hit -- its own -- never a second,
	# redirected one on top of it (the old bug would leave the tank at
	# tank_hp_before - 200 here).
	assert_eq(int(tank_hit["target"]), 0)
	assert_eq(int(tank_hit["amount"]), 100)
	assert_eq(battle.party[0].hp, tank_hp_before - 100, "tank absorbed only its own AoE share, not hero's too")

func test_kabau_does_not_exist_before_the_tank_acts_when_the_boss_is_faster() -> void:
	# additional confirmation #1 / required fix #2
	var seed := _find_seed_targeting(_two(tank_def, hero_def), _attacking_boss(50, 999), 1)
	assert_true(seed >= 0)

	var battle := RBMBattle.new(_two(tank_def, hero_def), _attacking_boss(50, 999), seed)
	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1},
		"1": {"type": "attack"},
	})
	var boss_entry := _find_log_entry(result["log"], "boss")
	# boss (SPD 999) resolved before the tank (SPD 140) could ever set protecting_ally_id
	# this turn -- the hit on the hero must land unredirected.
	assert_eq(int(boss_entry["target"]), 1, "かばう did not exist yet when the faster boss acted")

func test_kabau_is_active_once_the_tank_has_acted() -> void:
	# required fix #2. Distinct from test_kabau_clears_at_turn_end (which only
	# checks the AFTER-the-turn rest state) and from
	# test_kabau_protects_only_against_single_target_attacks (which only checks
	# who the boss's log entry names as the target). This test instead follows
	# the full timing chain in one place: unarmed before the tank acts -> the
	# tank uses かばう -> the SAME turn's single-target hit on the protected
	# ally is actually redirected -> the protected ally takes zero damage and
	# the tank absorbs the real damage.
	var seed := _find_seed_targeting(_two(tank_def, hero_def), _attacking_boss(80, 1), 1)
	assert_true(seed >= 0, "must find a seed where the boss's single-target pick lands on hero (1)")

	var battle := RBMBattle.new(_two(tank_def, hero_def), _attacking_boss(80, 1), seed)
	var tank_hp_before := battle.party[0].hp
	var hero_hp_before := battle.party[1].hp
	assert_eq(battle.party[0].protecting_ally_id, -1, "かばう is not active before the tank has acted")

	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1},
		"1": {"type": "attack"},
	})

	var boss_entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(boss_entry["target"]), 0, "the boss's single-target hit was redirected onto the tank")
	assert_true(int(boss_entry["amount"]) > 0, "sanity check: a real, non-zero hit was actually redirected")
	assert_eq(battle.party[1].hp, hero_hp_before, "hero (the protected ally) took zero damage")
	assert_eq(battle.party[0].hp, tank_hp_before - int(boss_entry["amount"]), "the tank actually absorbed that same amount")

func test_kabau_clears_at_turn_end() -> void:
	# required fix #4
	var battle := RBMBattle.new(_two(tank_def, hero_def), _neutral_boss(100000, 1, 1), 1)
	battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1},
		"1": {"type": "attack"},
	})
	assert_eq(battle.party[0].protecting_ally_id, -1, "かばう does not persist into the next turn")

func test_defend_is_active_from_turn_start_even_if_the_boss_is_faster() -> void:
	# additional confirmation #1
	var battle := RBMBattle.new(_one(hero_def), _attacking_boss(200, 999), 1)
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var entry := _find_log_entry(result["log"], "boss")
	assert_eq(int(entry["amount"]), 100, "50% defend already reduced the boss's earlier hit; hero had not acted yet")

func test_unspecified_action_does_not_fall_back_to_attack() -> void:
	# required fix #3
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	var before_hp := battle.boss.hp
	var result := battle.resolve_turn({})
	var entry := _find_log_entry(result["log"], 0)
	assert_true(bool(entry.get("failed", false)), "an unspecified action must not silently become an attack")
	assert_eq(battle.boss.hp, before_hp, "no damage was dealt")

func test_unrecognized_action_type_does_not_fall_back_to_attack() -> void:
	# required fix #3
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	var before_hp := battle.boss.hp
	var result := battle.resolve_turn({"0": {"type": "dance"}})
	var entry := _find_log_entry(result["log"], 0)
	assert_true(bool(entry.get("failed", false)), "an unrecognized action type must not silently become an attack")
	assert_eq(battle.boss.hp, before_hp)

func test_sp_is_not_spent_when_the_action_fails_due_to_a_downed_target() -> void:
	# required fix #7
	var battle := RBMBattle.new(_two(hero_def, healer_def), _neutral_boss(), 1)
	battle.party[0].hp = 0
	var sp_before := battle.party[1].sp
	var result := battle.resolve_turn({"1": {"type": "skill", "skill_id": "healer_heal_single", "target_id": 0}})
	var entry := _find_log_entry(result["log"], 1)
	assert_true(bool(entry.get("failed", false)))
	assert_eq(battle.party[1].sp, sp_before, "SP must not be spent on a failed (target-downed) skill use")

func test_counter_triggers_at_most_once_per_turn() -> void:
	# required test list item. The engine only resolves one boss action per
	# resolve_turn() call today, so there is no way to make TWO real boss hits
	# land within a single call through the public API alone -- and adding
	# that capability would be a new feature, which this pass is not allowed
	# to introduce. Instead this drives the same private resolution steps
	# resolve_turn() itself calls, directly, in sequence, WITHOUT ever going
	# through resolve_turn()'s own TURN END -- so a second hit can be applied
	# strictly "before TURN END" and the result cannot be confused with
	# counter_pending_this_turn being reset by TURN END rather than by firing.
	var battle := RBMBattle.new(_one(samurai_def), _attacking_boss(500, 10), 1)
	var samurai := battle.party[0]

	battle._resolve_ally_skill(samurai, "samurai_counter", -1)
	assert_true(samurai.counter_pending_this_turn, "step 1: the samurai is now in counter stance")

	var hp_before_first := samurai.hp
	var first_hit: Dictionary = battle._apply_boss_hit_to_ally(samurai, 1.0, RBMConstants.Attribute.NEUTRAL, false)
	assert_true(bool(first_hit.get("blocked", false)), "step 2/3: the first hit this turn is intercepted")
	assert_eq(int(first_hit["amount"]), 0)
	assert_true(int(first_hit["reflected"]) > 0)
	assert_eq(samurai.hp, hp_before_first, "the samurai took no damage from the blocked first hit")
	assert_false(samurai.counter_pending_this_turn, "counter is consumed the instant it fires -- not by TURN END")

	var hp_before_second := samurai.hp
	var second_hit: Dictionary = battle._apply_boss_hit_to_ally(samurai, 1.0, RBMConstants.Attribute.NEUTRAL, false)
	assert_false(bool(second_hit.get("blocked", false)), "step 4/5: a second same-turn hit is NOT intercepted")
	assert_true(int(second_hit["amount"]) > 0, "step 6: the samurai takes real, non-zero damage from this second hit")
	assert_eq(samurai.hp, hp_before_second - int(second_hit["amount"]), "and that damage was actually applied")

func test_counter_success_log_shows_explicit_zero_amount() -> void:
	# required fix #6
	var battle := RBMBattle.new(_one(samurai_def), _attacking_boss(500, 10), 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_counter"}})
	var boss_entry := _find_log_entry(result["log"], "boss")
	assert_true(bool(boss_entry.get("blocked", false)))
	assert_true(boss_entry.has("amount"), "amount must be explicitly present, not just implied by 'blocked'")
	assert_eq(int(boss_entry["amount"]), 0)
	assert_true(int(boss_entry["reflected"]) > 0, "reflected damage is a separate, real number")

func test_guard_boost_activates_via_the_real_skill() -> void:
	var battle := RBMBattle.new(_two(tank_def, hero_def), _aoe_boss(1000), 1)
	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_guard_boost"},
		"1": {"type": "defend"},
	})
	assert_true(RBMConstants.timed_effect_active(battle.party_timed_effects, "guard_boost", 1))
	var boss_entry := _find_log_entry(result["log"], "boss")
	var hits: Dictionary = boss_entry["hits"]
	var hero_hit: Dictionary = hits[1]
	assert_eq(int(hero_hit["amount"]), 400, "hero (defending) took 1000 x (1 - 0.6) via the tank's real guard_boost skill")

func test_iron_wall_activates_via_the_real_skill() -> void:
	var battle := RBMBattle.new(_two(tank_def, hero_def), _aoe_boss(1000), 1)
	var result := battle.resolve_turn({
		"0": {"type": "skill", "skill_id": "tank_iron_wall"},
		"1": {"type": "attack"},
	})
	assert_true(RBMConstants.timed_effect_active(battle.party_timed_effects, "iron_wall", 1))
	var boss_entry := _find_log_entry(result["log"], "boss")
	var hits: Dictionary = boss_entry["hits"]
	var hero_hit: Dictionary = hits[1]
	assert_eq(int(hero_hit["amount"]), 900, "hero (not defending) still took 1000 x (1 - 0.10) via the tank's real iron_wall skill")

func test_butler_sp_gift_restores_forty_cannot_target_self_and_caps_at_max() -> void:
	var battle := RBMBattle.new(_two(butler_def, hero_def), _neutral_boss(), 1)
	battle.party[1].sp = 50
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "butler_sp_gift", "target_id": 1}})
	var entry := _find_log_entry(result["log"], 0)
	assert_eq(int(entry["amount"]), 40)
	assert_eq(battle.party[1].sp, 90)

	var self_battle := RBMBattle.new(_one(butler_def), _neutral_boss(), 1)
	var self_result := self_battle.resolve_turn({"0": {"type": "skill", "skill_id": "butler_sp_gift", "target_id": 0}})
	var self_entry := _find_log_entry(self_result["log"], 0)
	assert_true(bool(self_entry.get("failed", false)), "cannot target self")

	var cap_battle := RBMBattle.new(_two(butler_def, hero_def), _neutral_boss(), 1)
	cap_battle.party[1].sp = 95
	var cap_result := cap_battle.resolve_turn({"0": {"type": "skill", "skill_id": "butler_sp_gift", "target_id": 1}})
	var cap_entry := _find_log_entry(cap_result["log"], 0)
	assert_eq(int(cap_entry["amount"]), 5, "only the 5 remaining headroom is actually granted")
	assert_eq(cap_battle.party[1].sp, 100)

func test_healer_heal_all_heals_every_living_ally() -> void:
	var battle := RBMBattle.new(_full_party(), _neutral_boss(), 1)
	for unit in battle.party:
		unit.hp = 1
	battle.party[4].hp = 0
	var result := battle.resolve_turn({"2": {"type": "skill", "skill_id": "healer_heal_all"}})
	var entry := _find_log_entry(result["log"], 2)
	var healed: Dictionary = entry["healed"]
	assert_eq(healed.size(), 4, "all four living allies were healed; the downed tank was skipped")
	for id in healed.keys():
		if int(id) != 2:
			assert_eq(int(healed[id]), 200)
	assert_eq(battle.party[4].hp, 0, "the downed tank remains at 0, untouched")

func test_healer_sp_all_excludes_self_and_downed_units() -> void:
	var battle := RBMBattle.new(_full_party(), _neutral_boss(), 1)
	for unit in battle.party:
		if unit.has_sp_resource():
			unit.sp = 10
	battle.party[2].sp = 100  # the healer needs enough SP (cost 60) to actually cast this
	battle.party[3].hp = 0
	var result := battle.resolve_turn({"2": {"type": "skill", "skill_id": "healer_sp_all"}})
	var entry := _find_log_entry(result["log"], 2)
	var recovered: Dictionary = entry["recovered"]
	assert_false(recovered.has(2), "the healer (caster) does not recover itself")
	assert_false(recovered.has(3), "the downed samurai is excluded")
	assert_true(recovered.has(0))
	assert_true(recovered.has(1))
	assert_true(recovered.has(4), "the tank now has the same standard SP resource as every other ally")
	assert_eq(int(recovered[0]), 40)
	assert_eq(int(recovered[1]), 40)
	assert_eq(int(recovered[4]), 40)

func test_all_twenty_ally_skills_match_the_confirmed_spec() -> void:
	# Values are floats throughout (not ints) to match how JSON.parse_string
	# represents every numeric field, avoiding a spurious float/int warning.
	#
	# Every entry includes "effect" (and "target" wherever the schema uses one)
	# so this test catches not just wrong numbers but wrong MEANING -- e.g. a
	# heal accidentally wired as "damage", butler's SP gift losing its
	# "_no_self" semantics, or the tank's guard/iron-wall/kabau skills pointing
	# at the wrong effect handler entirely.
	var expected := {
		"hero_slash": {"effect": "damage", "target": "boss", "attribute": "FIRE", "atk_multiplier": 1.5, "sp_cost": 15.0},
		"hero_blaze_all": {"effect": "damage", "target": "boss", "attribute": "FIRE", "atk_multiplier": 1.7, "sp_cost": 20.0},
		"hero_flame_wrap": {"effect": "buff_atk_self", "buff_multiplier": 1.75, "duration_turns": 3.0, "sp_cost": 30.0},
		"hero_burst_slash": {"effect": "damage", "target": "boss", "attribute": "FIRE", "atk_multiplier": 2.2, "sp_cost": 50.0},
		"butler_ice_bolt": {"effect": "damage", "target": "boss", "attribute": "ICE", "atk_multiplier": 2.5, "sp_cost": 15.0},
		"butler_ice_storm": {"effect": "damage", "target": "boss", "attribute": "ICE", "atk_multiplier": 2.8, "sp_cost": 20.0},
		# 老執事SP回復: 単体・自分自身対象不可 -- encoded by this exact effect id.
		"butler_sp_gift": {"effect": "sp_recover_single_no_self", "sp_amount": 40.0, "sp_cost": 30.0},
		"butler_grand_ice": {"effect": "damage", "target": "boss", "attribute": "ICE", "atk_multiplier": 4.0, "sp_cost": 60.0},
		"healer_shock": {"effect": "damage", "target": "boss", "attribute": "LIGHTNING", "atk_multiplier": 2.0, "sp_cost": 15.0},
		"healer_heal_single": {"effect": "heal", "target": "ally_chosen", "heal_amount": 400.0, "sp_cost": 20.0},
		"healer_heal_all": {"effect": "heal", "target": "ally_all", "heal_amount": 200.0, "sp_cost": 40.0},
		# 少女ヒーラー全体SP回復: 全体・自身除外 -- encoded by this exact effect id.
		"healer_sp_all": {"effect": "sp_recover_all_no_self", "sp_amount": 40.0, "sp_cost": 60.0},
		"samurai_slash": {"effect": "damage", "target": "boss", "attribute": "WIND", "atk_multiplier": 2.0, "sp_cost": 15.0},
		"samurai_slash_all": {"effect": "damage", "target": "boss", "attribute": "WIND", "atk_multiplier": 2.5, "sp_cost": 30.0},
		# 居合
		"samurai_iai": {"effect": "buff_next_attack", "buff_multiplier": 2.5, "sp_cost": 40.0},
		# カウンター
		"samurai_counter": {"effect": "counter_stance", "attribute": "WIND", "atk_multiplier": 3.0, "sp_cost": 50.0},
		"tank_smash": {"effect": "damage", "target": "boss", "attribute": "NEUTRAL", "atk_multiplier": 1.5, "sp_cost": 0.0},
		# かばう
		"tank_guard_swap": {"effect": "guard_redirect", "sp_cost": 0.0},
		# 防御強化
		"tank_guard_boost": {"effect": "guard_boost", "duration_turns": 1.0, "new_rate": 0.6, "sp_cost": 0.0},
		# 鉄壁
		"tank_iron_wall": {"effect": "party_damage_reduction", "duration_turns": 1.0, "reduction_rate": 0.1, "sp_cost": 0.0},
	}
	var all_defs := [hero_def, butler_def, healer_def, samurai_def, tank_def]
	var seen := {}
	for def in all_defs:
		var skills: Array = def["skills"]
		for skill in skills:
			var id := str(skill.get("id", ""))
			assert_true(expected.has(id), "unexpected skill id %s" % id)
			seen[id] = true
			var fields: Dictionary = expected[id]
			for key in fields.keys():
				assert_eq(skill.get(key, null), fields[key], "%s.%s" % [id, key])
	assert_eq(seen.size(), 20, "exactly 20 skills accounted for")
