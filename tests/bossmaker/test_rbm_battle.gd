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
		{"hp": 950, "atk": 200, "spd": 140, "sp": RBMConstants.NO_SP},
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

func test_tank_has_no_sp_resource_at_all() -> void:
	var battle := RBMBattle.new(_full_party(), boss_def, 1)
	var tank := battle.party[4]
	assert_false(tank.has_sp_resource())
	assert_eq(tank.max_sp, RBMConstants.NO_SP)
	assert_eq(tank.sp, 0)

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

func test_normal_attack_does_not_restore_sp_for_the_sp_less_tank() -> void:
	var battle := RBMBattle.new(_one(tank_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.party[0].sp, 0, "tank never accrues SP")
	assert_false(battle.party[0].has_sp_resource())

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
	# 240 * 1.5 (flame wrap) * 1.0 (normal attack multiplier) = 360.0
	assert_eq(int(entry["amount"]), 360)

func test_reusing_an_effect_refreshes_duration_without_stacking_the_multiplier() -> void:
	var battle := RBMBattle.new(_one(hero_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})  # applied at turn 1
	battle.resolve_turn({"0": {"type": "attack"}})  # turn 2
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_flame_wrap"}})  # re-applied at turn 3
	var effect: Dictionary = battle.party[0].timed_effects["atk_buff"]
	assert_eq(int(effect["applied_at_turn"]), 3, "duration window restarts from the re-use turn")
	assert_almost_eq(float(effect["value"]), 1.5, 0.0001, "multiplier does not stack (still x1.5, not x2.25)")

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
	# samurai ATK 280 x1.0, NOT x2.0 -- iai must remain pending afterwards.
	assert_eq(int(entry["amount"]), 280)
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.0, 0.0001, "iai is still pending; normal attack did not consume it")

func test_iai_doubles_damage_of_the_next_attack_skill_only_once() -> void:
	var battle := RBMBattle.new(_one(samurai_def), _neutral_boss(), 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})
	var entry := _find_log_entry(result["log"], 0)
	# 280 * 2.0 (skill) * 2.0 (iai) = 1120.0
	assert_eq(int(entry["amount"]), 1120)
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
	# reflected: samurai ATK 280 x3.0 (counter) x2.0 (iai, consumed here) = 1680.0
	assert_eq(int(boss_entry["reflected"]), 1680)
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
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.0, 0.0001, "iai must remain pending -- the counter never triggered")
	assert_false(battle.party[0].counter_pending_this_turn, "counter stance clears at turn end regardless of trigger")

func test_iai_clears_when_the_samurai_is_downed() -> void:
	# SPD 1 keeps the samurai (SPD 70) acting before the boss on every turn, so
	# the boss's (initially harmless) counter-hit can never pre-empt the iai cast.
	var boss := _attacking_boss(1, 1)
	var battle := RBMBattle.new(_one(samurai_def), boss, 1)
	battle.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_iai"}})
	assert_almost_eq(battle.party[0].next_attack_bonus_multiplier, 2.0, 0.0001, "iai armed")
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
		assert_eq(int(result["turn"]), battle.current_turn)
	assert_true(battle.battle_over, "the mock battle must actually conclude, not loop forever")
	assert_eq(battle.winner, "ally", "the fixed party should be able to defeat the fixed test boss")
	assert_true(turns > 1, "the battle should take more than a single turn (sanity check)")
	assert_true(turns < 200, "did not hit the safety cap")
