extends GutTest

## RPG BOSS MAKER Phase 1 Step 3 修正版 — BossBattleDefinition resolution tests.
## Exercises RBMDefinitionLoader against the real data_bossmaker/definitions/
## JSON, plus ad-hoc Dictionaries for validation/edge-case coverage.
##
## Step 3 修正指示 correction: a boss now has NO master data of its own (see
## src/bossmaker/README.md) -- everything about it comes from the Definition's
## own "boss" object, author-created. Only the ally side is still
## master-referenced. rbm_unit.gd/rbm_constants.gd/rbm_data_loader.gd remain
## untouched; rbm_battle.gd gained a small, additive 指定行動 mechanism this
## round (see its own doc comment) that this file also exercises through real
## resolve_turn() calls, not just data-shape checks.

const DEFINITION_DIR := "res://data_bossmaker/definitions/"

func _load_definition(id: String) -> Dictionary:
	return RBMDataLoader.load_dict(DEFINITION_DIR + id + ".json")

func _find_entry(log: Array, actor) -> Dictionary:
	var actor_str := str(actor)
	for entry in log:
		if str(entry.get("actor", "")) == actor_str:
			return entry
	return {}

func _find_all_entries(log: Array, actor) -> Array[Dictionary]:
	var actor_str := str(actor)
	var out: Array[Dictionary] = []
	for entry in log:
		if str(entry.get("actor", "")) == actor_str:
			out.append(entry)
	return out

## A minimal valid boss block, reused by the ad-hoc Dictionaries below so each
## test only has to vary the one field it actually cares about.
func _base_boss() -> Dictionary:
	return {
		"boss_id": "adhoc_boss",
		"boss_name": "Adhoc Boss",
		"hp": 1000,
		"atk": 100,
		"spd": 50,
		"skills": [
			{"skill_id": "adhoc_claw", "name": "Claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_actions": [
			{"skill_id": "adhoc_claw", "weight": 1},
		],
	}

func _base_party(count: int = 1) -> Array:
	var ids := ["hero", "butler", "healer", "samurai", "tank"]
	var out: Array = []
	for i in range(count):
		out.append({"character_id": ids[i]})
	return out

# ---------------------------------------------------------------------------
# Test 1: Definition A読み込み（インライン作成ボス・4人パーティ）
# ---------------------------------------------------------------------------

func test_definition_a_resolves_the_specified_boss_party_and_skills() -> void:
	var definition := _load_definition("test_definition_a")
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_true(bool(resolved.get("ok", false)), "definition A must resolve cleanly")

	var ally_defs: Array = resolved["ally_defs"]
	assert_eq(ally_defs.size(), 4, "definition A's party has 4 members (within the 1-4 range)")
	var ids: Array = []
	for ally_def in ally_defs:
		ids.append(str(ally_def["id"]))
	assert_eq(ids, ["hero", "butler", "healer", "tank"], "party order/composition matches the definition")

	var boss_def: Dictionary = resolved["boss_def"]
	assert_eq(str(boss_def["id"]), "cave_troll_a", "the boss_id is just an author label now, not a master reference")
	assert_eq(int(boss_def["hp"]), 3000, "boss stats come straight from the definition -- there is no master to override")
	assert_eq(str(boss_def["display_name"]), "テスト用ボス")

	var boss_skill_ids: Array = []
	for skill in boss_def["skills"]:
		boss_skill_ids.append(str(skill["id"]))
	assert_eq(boss_skill_ids, ["boss_claw"], "the boss's author-created skill list resolved")
	assert_eq(str(boss_def["skills"][0]["effect"]), "damage", "attack-type author skills translate to the existing internal 'damage' effect")

	var hero_skill_ids: Array = []
	for skill in ally_defs[0]["skills"]:
		hero_skill_ids.append(str(skill["id"]))
	assert_eq(hero_skill_ids, ["hero_slash", "hero_blaze_all", "hero_flame_wrap", "hero_burst_slash"], "hero's allowed skills match the definition exactly")

func test_definition_a_produces_a_working_battle() -> void:
	var definition := _load_definition("test_definition_a")
	var start := RBMDefinitionLoader.start_battle(definition, 1)
	assert_true(bool(start.get("ok", false)))
	var battle: RBMBattle = start["battle"]
	assert_eq(battle.party.size(), 4)
	assert_eq(battle.boss.max_hp, 3000)
	assert_eq(battle.boss.display_name, "テスト用ボス")

# ---------------------------------------------------------------------------
# Test 2: Definition差し替え（同一RBMBattleクラス、コード変更なしで別の戦闘に）
# ---------------------------------------------------------------------------

func test_switching_definition_a_to_b_changes_the_battle_with_no_code_changes() -> void:
	var def_a := _load_definition("test_definition_a")
	var def_b := _load_definition("test_definition_b")

	var start_a := RBMDefinitionLoader.start_battle(def_a, 1)
	assert_true(bool(start_a.get("ok", false)))
	var battle_a: RBMBattle = start_a["battle"]

	var start_b := RBMDefinitionLoader.start_battle(def_b, 1)
	assert_true(bool(start_b.get("ok", false)))
	var battle_b: RBMBattle = start_b["battle"]

	assert_eq(battle_a.party.size(), 4)
	assert_eq(battle_b.party.size(), 2, "definition B uses a smaller party")

	assert_eq(battle_a.boss.display_name, "テスト用ボス")
	assert_eq(battle_b.boss.display_name, "氷の番人", "definition B author-creates an entirely different boss")

	assert_eq(battle_a.boss.max_hp, 3000)
	assert_eq(battle_b.boss.max_hp, 4000)

	var tank_a := battle_a.party[3]
	var tank_a_skills: Array = []
	for skill in tank_a.skills:
		tank_a_skills.append(str(skill["id"]))
	assert_eq(tank_a_skills.size(), 4, "definition A allows the tank's full 4-skill kit")

	var tank_b := battle_b.party[0]
	var tank_b_skills: Array = []
	for skill in tank_b.skills:
		tank_b_skills.append(str(skill["id"]))
	assert_eq(tank_b_skills, ["tank_smash", "tank_iron_wall"], "definition B restricts the same tank to a 2-skill subset")

# ---------------------------------------------------------------------------
# Test 3: パーティ人数（1〜4人のみ有効）
# ---------------------------------------------------------------------------

func test_party_size_one_is_accepted() -> void:
	var definition := {"boss": _base_boss(), "party": _base_party(1)}
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_true(bool(resolved.get("ok", false)))

func test_party_size_four_is_accepted() -> void:
	var definition := {"boss": _base_boss(), "party": _base_party(4)}
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_true(bool(resolved.get("ok", false)))

func test_party_size_zero_is_rejected() -> void:
	var definition := {"boss": _base_boss(), "party": []}
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_false(bool(resolved.get("ok", true)))

func test_party_size_five_is_rejected() -> void:
	var definition := {"boss": _base_boss(), "party": _base_party(5)}
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_false(bool(resolved.get("ok", true)), "the confirmed spec caps the party at 4")

func test_duplicate_character_id_in_party_is_rejected() -> void:
	var definition := {
		"boss": _base_boss(),
		"party": [{"character_id": "hero"}, {"character_id": "hero"}],
	}
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_false(bool(resolved.get("ok", true)), "the same character_id may not appear twice in one party")

# ---------------------------------------------------------------------------
# Test 4: ボス数値の範囲検証（HP/ATK/SPD、下限・上限・範囲外・未知属性）
# ---------------------------------------------------------------------------

func test_boss_hp_at_the_lower_bound_is_accepted() -> void:
	var boss := _base_boss()
	boss["hp"] = 1
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))

func test_boss_hp_at_the_upper_bound_is_accepted() -> void:
	var boss := _base_boss()
	boss["hp"] = 1000000
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))

func test_boss_hp_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["hp"] = 0
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_hp_over_one_million_is_rejected() -> void:
	var boss := _base_boss()
	boss["hp"] = 1000001
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_atk_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["atk"] = 0
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_atk_over_9999_is_rejected() -> void:
	var boss := _base_boss()
	boss["atk"] = 10000
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_spd_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["spd"] = 0
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_spd_over_500_is_rejected() -> void:
	var boss := _base_boss()
	boss["spd"] = 501
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_missing_a_required_stat_is_rejected() -> void:
	var boss := _base_boss()
	boss.erase("spd")
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "there is no fallback/default -- a required boss stat must be present")

func test_boss_valid_weak_attribute_is_accepted() -> void:
	var boss := _base_boss()
	boss["weak_attribute"] = "FIRE"
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))
	assert_eq(str(resolved["boss_def"]["weak_attribute"]), "FIRE")

func test_boss_unknown_weak_attribute_is_rejected() -> void:
	var boss := _base_boss()
	boss["weak_attribute"] = "EARTH"
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "EARTH is not one of the 5 confirmed attributes")

func test_boss_omitted_weak_attribute_is_accepted_as_no_weakness() -> void:
	var boss := _base_boss()
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)), "a boss may legitimately have no weakness at all")
	assert_null(resolved["boss_def"]["weak_attribute"])

# ---------------------------------------------------------------------------
# Test 5: 作者作成ボススキル（攻撃/自己回復/ATK自己強化）の解決と実戦闘での使用
# ---------------------------------------------------------------------------

func test_attack_type_boss_skill_resolves_to_the_existing_damage_effect() -> void:
	var boss := _base_boss()
	boss["skills"] = [
		{"skill_id": "s1", "name": "S1", "type": "attack", "target": "all", "attribute": "WIND", "atk_multiplier": 0.5},
	]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))
	var skill: Dictionary = resolved["boss_def"]["skills"][0]
	assert_eq(str(skill["effect"]), "damage")
	assert_eq(str(skill["target"]), "ally_all")
	assert_eq(str(skill["attribute"]), "WIND")
	assert_eq(float(skill["atk_multiplier"]), 0.5)

func test_author_created_attack_skill_actually_reduces_target_hp_by_the_expected_amount() -> void:
	# Step 3 最終修正指示 §6: don't stop at the log/data-shape -- assert real
	# before/after HP and the exact expected damage value.
	var boss := _base_boss()
	boss["atk"] = 100
	boss["skills"] = [
		{"skill_id": "s_atk", "name": "Atk", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.5},
	]
	boss["normal_actions"] = [{"skill_id": "s_atk", "weight": 1}]
	var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, 1)
	var battle: RBMBattle = start["battle"]
	var hero := battle.party[0]
	var hp_before := hero.hp

	# "attack" (not "defend"), sole normal_actions candidate, single living
	# ally target, NEUTRAL attack attribute (matches neither hero's ICE
	# weakness nor FIRE resistance) -- every factor besides ATK x
	# atk_multiplier is 1.0, so the expected damage is exactly reproducible.
	battle.resolve_turn({"0": {"type": "attack"}})
	var hp_after := hero.hp

	assert_true(hp_after < hp_before, "the author-created attack actually reduced the target's HP")
	var expected_damage := int(round(100.0 * 1.5))
	assert_eq(hp_before - hp_after, expected_damage, "the reduction matches atk x atk_multiplier exactly")

func test_self_heal_type_boss_skill_resolves_and_actually_heals_in_battle() -> void:
	var boss := _base_boss()
	boss["hp"] = 500
	boss["skills"] = [
		{"skill_id": "s_heal", "name": "Heal", "type": "self_heal", "heal_amount": 200},
	]
	boss["normal_actions"] = [{"skill_id": "s_heal", "weight": 1}]
	var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, 1)
	var battle: RBMBattle = start["battle"]
	battle.boss.hp = 100
	# hero defends (not attacks) so hero's own action never independently
	# defeats the boss before the boss's own self_heal turn resolves.
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var boss_entry := _find_entry(result["log"], "boss")
	assert_eq(str(boss_entry["skill_id"]), "s_heal")
	assert_eq(int(boss_entry["amount"]), 200, "self_heal actually restored the configured amount")
	assert_eq(battle.boss.hp, 300)

func test_atk_self_buff_type_boss_skill_resolves_and_actually_buffs_damage_in_battle() -> void:
	var boss := _base_boss()
	boss["skills"] = [
		{"skill_id": "s_buff", "name": "Buff", "type": "atk_self_buff", "buff_multiplier": 2.0, "duration_turns": 2},
		{"skill_id": "s_atk", "name": "Atk", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
	]
	boss["normal_actions"] = [{"skill_id": "s_atk", "weight": 1}]
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "s_buff", "timing": "replace", "order": 0}]
	var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, 1)
	var battle: RBMBattle = start["battle"]

	var boss_atk := battle.boss.atk  # captured before any buff applies

	battle.resolve_turn({"0": {"type": "attack"}})  # turn 1: forced onto the buff via "replace" (no defend, to avoid a confounding reduction on turn 2)
	var hero := battle.party[0]
	var hp_before_buffed_hit := hero.hp
	battle.resolve_turn({"0": {"type": "attack"}})  # turn 2: normal random pick (the sole candidate: s_atk), now buffed 2x
	var actual_damage := hp_before_buffed_hit - hero.hp

	# Step 3 最終修正指示 §7: instead of only "buffed > unbuffed", compute the
	# exact expected damage from the existing formula
	# (ATK x atk_buff x skill_multiplier x attribute x bonus x reduction) with
	# the configured buff_multiplier plugged in, and assert equality. Turn 2's
	# ally action is "attack" (not "defend"), s_atk's attribute is NEUTRAL
	# (matches neither hero's ICE weakness nor FIRE resistance -> 1.0x), and
	# there is no counter/iai in play, so every factor besides atk_buff is 1.0.
	var expected_buffed_damage := int(round(float(boss_atk) * 2.0 * 1.0 * 1.0 * 1.0 * 1.0))
	assert_eq(actual_damage, expected_buffed_damage, "the configured buff_multiplier (2.0) is reflected exactly in the resulting damage")

func test_boss_skill_missing_type_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1"}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_boss_skill_unknown_type_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "summon_minion"}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "only attack/self_heal/atk_self_buff are confirmed boss skill types")

func test_attack_boss_skill_missing_atk_multiplier_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "attack", "target": "single", "attribute": "FIRE"}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_attack_boss_skill_invalid_target_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "attack", "target": "everyone", "attribute": "FIRE", "atk_multiplier": 1.0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "target must be exactly 'single' or 'all'")

func test_self_heal_boss_skill_missing_heal_amount_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "self_heal"}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_atk_self_buff_boss_skill_missing_duration_turns_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "atk_self_buff", "buff_multiplier": 1.5}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_duplicate_boss_skill_id_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [
		{"skill_id": "dup", "name": "A", "type": "self_heal", "heal_amount": 10},
		{"skill_id": "dup", "name": "B", "type": "self_heal", "heal_amount": 20},
	]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

# ---------------------------------------------------------------------------
# Test 5b: 最低限の意味検証（Step 3 最終修正指示 §3/§4/§5）— 独自の上限は設けない。
# 戦闘状態を破壊しうる値（負数、duration<=0、weight合計<=0、turn<1）のみ拒否し、
# それ以外の境界（倍率0・回復量0・weight0・turn1）は明示的に有効のまま許可する。
# ---------------------------------------------------------------------------

func test_negative_attack_atk_multiplier_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": -0.1}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_attack_atk_multiplier_of_zero_is_accepted() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.0}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)), "0x is a deliberately harmless attack, not an invalid one -- individual 0-value bans are deferred to Creator")

func test_negative_self_heal_amount_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "self_heal", "heal_amount": -1}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_self_heal_amount_of_zero_is_accepted() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "self_heal", "heal_amount": 0}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))

func test_negative_atk_self_buff_multiplier_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "atk_self_buff", "buff_multiplier": -0.5, "duration_turns": 1}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_atk_self_buff_multiplier_of_zero_is_accepted() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "atk_self_buff", "buff_multiplier": 0.0, "duration_turns": 1}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))

func test_atk_self_buff_duration_turns_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 0}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "unlike a 0x multiplier, a 0-turn duration is meaningless (a buff active for zero turns), so 0 itself is rejected here")

func test_atk_self_buff_negative_duration_turns_is_rejected() -> void:
	var boss := _base_boss()
	boss["skills"] = [{"skill_id": "s1", "name": "S1", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": -1}]
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_negative_normal_action_weight_is_rejected() -> void:
	var boss := _base_boss()
	boss["normal_actions"] = [{"skill_id": "adhoc_claw", "weight": -5}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_normal_action_weight_of_zero_with_another_candidate_positive_is_accepted() -> void:
	var boss := _base_boss()
	boss["skills"] = [
		{"skill_id": "adhoc_claw", "name": "Claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"skill_id": "other", "name": "Other", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
	]
	boss["normal_actions"] = [{"skill_id": "adhoc_claw", "weight": 0}, {"skill_id": "other", "weight": 5}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)), "an individual candidate at weight 0 is fine as long as the total is positive")

func test_normal_actions_total_weight_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["normal_actions"] = [{"skill_id": "adhoc_claw", "weight": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)), "a normal_actions list with a total weight of 0 leaves the boss unable to pick any normal action")

func test_empty_normal_actions_is_still_accepted() -> void:
	# a boss that only ever acts via 指定行動 is a legitimate design -- this
	# must not be confused with "at least one candidate but total weight 0".
	var boss := _base_boss()
	boss["normal_actions"] = []
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)))

func test_scripted_action_turn_of_zero_is_rejected() -> void:
	var boss := _base_boss()
	boss["scripted_actions"] = [{"turn": 0, "skill_id": "adhoc_claw", "timing": "replace", "order": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_scripted_action_negative_turn_is_rejected() -> void:
	var boss := _base_boss()
	boss["scripted_actions"] = [{"turn": -3, "skill_id": "adhoc_claw", "timing": "replace", "order": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_scripted_action_turn_of_one_is_accepted() -> void:
	var boss := _base_boss()
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "adhoc_claw", "timing": "replace", "order": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(resolved.get("ok", false)), "turn 1 is the first real turn (RBMBattle.current_turn starts at 1), so it must be reachable")

# ---------------------------------------------------------------------------
# Test 6: 使用可能スキル vs 通常行動候補は別概念（definition Bで実戦闘検証）
# ---------------------------------------------------------------------------

func test_definition_b_boss_has_four_usable_skills_but_only_one_normal_candidate() -> void:
	var def_b := _load_definition("test_definition_b")
	var resolved := RBMDefinitionLoader.resolve(def_b)
	var boss_def: Dictionary = resolved["boss_def"]
	var usable_ids: Array = []
	for skill in boss_def["skills"]:
		usable_ids.append(str(skill["id"]))
	assert_eq(usable_ids, ["sentinel_frost_bite", "sentinel_regen", "sentinel_focus", "sentinel_frost_nova"], "all 4 author-created skills are usable")
	var candidate_ids: Array = []
	for candidate in boss_def["normal_action_candidates"]:
		candidate_ids.append(str(candidate["skill_id"]))
	assert_eq(candidate_ids, ["sentinel_frost_bite"], "only 1 of the 4 usable skills is a normal-turn candidate")

func test_a_usable_but_non_candidate_boss_skill_is_never_auto_picked_on_a_normal_turn() -> void:
	# turn 1 has no scripted action at all in definition B -- the boss's only
	# possible normal pick is sentinel_frost_bite (the sole normal_actions
	# entry). sentinel_regen/sentinel_focus/sentinel_frost_nova must never
	# appear here even though they are all "usable" (present in boss.skills).
	var def_b := _load_definition("test_definition_b")
	for seed in range(1, 11):
		var start := RBMDefinitionLoader.start_battle(def_b, seed)
		var battle: RBMBattle = start["battle"]
		var result := battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})
		var boss_entry := _find_entry(result["log"], "boss")
		assert_eq(str(boss_entry["skill_id"]), "sentinel_frost_bite", "seed %d: only the configured normal candidate was ever picked" % seed)

func test_normal_action_weight_actually_shapes_the_random_distribution() -> void:
	var boss := _base_boss()
	boss["skills"] = [
		{"skill_id": "heavy", "name": "Heavy", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"skill_id": "light", "name": "Light", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5},
	]
	boss["normal_actions"] = [{"skill_id": "heavy", "weight": 90}, {"skill_id": "light", "weight": 10}]
	var counts := {"heavy": 0, "light": 0}
	for seed in range(1, 61):
		var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, seed)
		var battle: RBMBattle = start["battle"]
		var result := battle.resolve_turn({"0": {"type": "defend"}})
		var boss_entry := _find_entry(result["log"], "boss")
		var picked := str(boss_entry["skill_id"])
		counts[picked] = int(counts[picked]) + 1
	assert_true(int(counts["heavy"]) > int(counts["light"]), "the 90/10 weight split favors 'heavy' across many seeds")
	assert_true(int(counts["light"]) > 0, "both configured candidates are at least reachable")

# ---------------------------------------------------------------------------
# Test 7: 指定行動（置換型／割り込み型・ターン開始時／割り込み型・ターン終了時）
# ---------------------------------------------------------------------------

func test_turn_start_interrupt_scripted_action_fires_in_addition_to_the_normal_action() -> void:
	# definition B, turn 2: sentinel_focus (turn_start_interrupt) + the boss's
	# normal pick (sentinel_frost_bite) both fire -- 2 real boss log entries.
	var def_b := _load_definition("test_definition_b")
	var start := RBMDefinitionLoader.start_battle(def_b, 1)
	var battle: RBMBattle = start["battle"]
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 1
	var result := battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 2
	assert_eq(int(result["turn"]), 2)
	var boss_entries := _find_all_entries(result["log"], "boss")
	assert_eq(boss_entries.size(), 2, "the scripted interrupt is an EXTRA action, not a replacement")
	assert_eq(str(boss_entries[0]["skill_id"]), "sentinel_focus", "the turn_start_interrupt resolves before the normal action")
	assert_eq(str(boss_entries[1]["skill_id"]), "sentinel_frost_bite", "the normal action still happens afterward")

func test_replace_scripted_action_substitutes_the_normal_action_not_add_to_it() -> void:
	# definition B, turn 3: sentinel_frost_nova (replace) takes the place of
	# the would-be normal pick (sentinel_frost_bite) -- exactly 1 boss entry.
	var def_b := _load_definition("test_definition_b")
	var start := RBMDefinitionLoader.start_battle(def_b, 1)
	var battle: RBMBattle = start["battle"]
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 1
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 2
	var result := battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 3
	assert_eq(int(result["turn"]), 3)
	var boss_entries := _find_all_entries(result["log"], "boss")
	assert_eq(boss_entries.size(), 1, "'replace' takes the single normal-action slot, it does not add a second action")
	assert_eq(str(boss_entries[0]["skill_id"]), "sentinel_frost_nova")
	assert_true(boss_entries[0].has("hits"), "sentinel_frost_nova is an ally_all attack -- it really executed, not just got logged")

func test_multiple_replace_scripted_actions_on_the_same_turn_all_fire_in_order_with_no_normal_action() -> void:
	# Step 3 最終修正指示 §1/§2: two "replace"-timing scripted actions on the
	# same turn -- declared in the JSON with order:20 then order:10, mirroring
	# the instruction's own example -- must BOTH fire, in ascending order
	# (skill_b first, then skill_a), and the boss's ordinary normal action
	# (a third, distinct skill only reachable via normal_actions) must not
	# fire at all that turn. This exercises real resolve_turn() output, not
	# just the resolved Definition's data shape.
	var boss := _base_boss()
	boss["hp"] = 1000
	boss["skills"] = [
		{"skill_id": "skill_a", "name": "A", "type": "self_heal", "heal_amount": 150},
		{"skill_id": "skill_b", "name": "B", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"skill_id": "s_normal", "name": "Normal", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
	]
	boss["normal_actions"] = [{"skill_id": "s_normal", "weight": 1}]
	boss["scripted_actions"] = [
		{"turn": 1, "skill_id": "skill_a", "timing": "replace", "order": 20},
		{"turn": 1, "skill_id": "skill_b", "timing": "replace", "order": 10},
	]
	var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, 1)
	var battle: RBMBattle = start["battle"]
	battle.boss.hp = 400  # damaged first, so skill_a's heal has visible room
	var hero := battle.party[0]
	var boss_hp_before := battle.boss.hp
	var hero_hp_before := hero.hp

	# Deliberately no ally action at all this turn: hero neither attacks the
	# boss (which would otherwise confound the expected +150 net HP change
	# from skill_a's heal) nor defends (which would otherwise halve skill_b's
	# damage to hero).
	var result := battle.resolve_turn({})

	var boss_entries := _find_all_entries(result["log"], "boss")
	assert_eq(boss_entries.size(), 2, "both replace-timing scripted actions fired, not just the lowest-order one")
	assert_eq(str(boss_entries[0]["skill_id"]), "skill_b", "order:10 executes before order:20 regardless of JSON declaration order")
	assert_eq(str(boss_entries[1]["skill_id"]), "skill_a")
	for entry in boss_entries:
		assert_ne(str(entry["skill_id"]), "s_normal", "the ordinary normal action never fires this turn when replace-type scripted actions are configured for it")

	# real HP/state changes, not just log shape.
	assert_eq(int(boss_entries[0]["amount"]), 100, "skill_b dealt exactly ATK(100) x 1.0 to the sole living ally")
	assert_eq(int(boss_entries[0]["target"]), hero.id)
	assert_true(hero.hp < hero_hp_before, "skill_b's attack actually reduced hero's HP")
	assert_eq(hero_hp_before - hero.hp, 100)

	assert_eq(int(boss_entries[1]["amount"]), 150, "skill_a healed exactly the configured heal_amount")
	assert_true(battle.boss.hp > boss_hp_before, "skill_a's self_heal actually raised the boss's HP")
	assert_eq(battle.boss.hp - boss_hp_before, 150)

func test_turn_end_interrupt_scripted_action_fires_after_the_normal_action() -> void:
	# definition B, turn 4: the normal action (sentinel_frost_bite) fires
	# first, then sentinel_regen (turn_end_interrupt) fires afterward.
	var def_b := _load_definition("test_definition_b")
	var start := RBMDefinitionLoader.start_battle(def_b, 1)
	var battle: RBMBattle = start["battle"]
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 1
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 2
	battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 3
	# nothing has attacked the boss through turns 1-3 (both allies defended
	# every turn), so it is still sitting at full HP -- damage it manually so
	# sentinel_regen's heal this turn actually has visible room to apply.
	battle.boss.hp = battle.boss.max_hp - 1000
	var boss_hp_before_turn_4 := battle.boss.hp
	var result := battle.resolve_turn({"0": {"type": "defend"}, "1": {"type": "defend"}})  # turn 4
	assert_eq(int(result["turn"]), 4)
	var boss_entries := _find_all_entries(result["log"], "boss")
	assert_eq(boss_entries.size(), 2)
	assert_eq(str(boss_entries[0]["skill_id"]), "sentinel_frost_bite", "the normal action resolves first")
	assert_eq(str(boss_entries[1]["skill_id"]), "sentinel_regen", "the turn_end_interrupt resolves after it")
	assert_true(battle.boss.hp > boss_hp_before_turn_4, "sentinel_regen actually healed the boss this turn")

func test_scripted_action_referencing_an_unknown_boss_skill_is_rejected() -> void:
	var boss := _base_boss()
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "no_such_skill", "timing": "replace", "order": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_scripted_action_with_an_unknown_timing_is_rejected() -> void:
	var boss := _base_boss()
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "adhoc_claw", "timing": "mid_turn", "order": 0}]
	var resolved := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(resolved.get("ok", true)))

func test_same_timing_scripted_actions_resolve_in_the_definition_specified_order() -> void:
	# an ad-hoc boss with two turn_start_interrupt actions on the same turn --
	# a heal (order 1) and a self-buff (order 0) -- to prove ordering is driven
	# by the Definition's own "order" field, not JSON declaration order (heal
	# is declared FIRST in the JSON below but must resolve SECOND).
	var boss := _base_boss()
	boss["hp"] = 500
	boss["skills"] = [
		{"skill_id": "s_heal", "name": "Heal", "type": "self_heal", "heal_amount": 50},
		{"skill_id": "s_buff", "name": "Buff", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 1},
		{"skill_id": "adhoc_claw", "name": "Claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
	]
	boss["scripted_actions"] = [
		{"turn": 1, "skill_id": "s_heal", "timing": "turn_start_interrupt", "order": 1},
		{"turn": 1, "skill_id": "s_buff", "timing": "turn_start_interrupt", "order": 0},
	]
	var start := RBMDefinitionLoader.start_battle({"boss": boss, "party": _base_party(1)}, 1)
	var battle: RBMBattle = start["battle"]
	battle.boss.hp = 300
	var result := battle.resolve_turn({"0": {"type": "defend"}})
	var boss_entries := _find_all_entries(result["log"], "boss")
	# 2 scripted entries + 1 normal-action entry (adhoc_claw, the only normal
	# candidate) = 3 total, in the order: buff (order 0) -> heal (order 1) ->
	# normal action.
	assert_eq(boss_entries.size(), 3)
	assert_eq(str(boss_entries[0]["skill_id"]), "s_buff", "order:0 resolves before order:1 regardless of JSON declaration order")
	assert_eq(str(boss_entries[1]["skill_id"]), "s_heal")
	assert_eq(str(boss_entries[2]["skill_id"]), "adhoc_claw")

# ---------------------------------------------------------------------------
# Test 8: スキル許可（既存の味方側テスト＋ボス側の実戦闘検証）
# ---------------------------------------------------------------------------

func test_a_skill_the_character_owns_but_the_definition_forbids_is_unusable() -> void:
	var def_b := _load_definition("test_definition_b")
	var start := RBMDefinitionLoader.start_battle(def_b, 1)
	var battle: RBMBattle = start["battle"]
	var tank := battle.party[0]

	var owned_ids: Array = []
	for skill in tank.skills:
		owned_ids.append(str(skill["id"]))
	assert_false(owned_ids.has("tank_guard_swap"), "a forbidden skill is not even present on the unit -- not just hidden from a future UI")
	assert_false(owned_ids.has("tank_guard_boost"))

	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "tank_guard_swap", "target_id": 1}})
	var entry := _find_entry(result["log"], 0)
	assert_true(bool(entry.get("failed", false)), "the forbidden skill request is refused")
	assert_eq(str(entry.get("reason", "")), "unknown_skill")

func test_a_skill_the_definition_allows_can_actually_be_used() -> void:
	var def_b := _load_definition("test_definition_b")
	var start := RBMDefinitionLoader.start_battle(def_b, 1)
	var battle: RBMBattle = start["battle"]
	var boss_hp_before := battle.boss.hp

	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "tank_smash", "target_id": -1}})
	var entry := _find_entry(result["log"], 0)
	assert_false(bool(entry.get("failed", false)), "an allowed skill must actually resolve, not fail")
	assert_true(battle.boss.hp < boss_hp_before, "real damage was dealt")

func test_every_skill_a_definition_allows_for_each_character_is_individually_usable() -> void:
	# unlike a mere skill-count check, this actually invokes EVERY allowed
	# skill of every character in definition A and confirms each one resolves
	# without "unknown_skill" -- catching a typo'd allowed_skill_ids entry
	# that happens to still have the right length/shape. party entry order
	# maps 1:1 onto battle.party[i].id (RBMBattle assigns sequential ids in
	# ally_defs order, and RBMDefinitionLoader preserves party order).
	var definition := _load_definition("test_definition_a")
	var raw_party: Array = definition["party"]
	for i in range(raw_party.size()):
		var entry: Dictionary = raw_party[i]
		var character_id := str(entry["character_id"])
		var allowed: Array = entry["allowed_skill_ids"]
		for skill_id_variant in allowed:
			var skill_id := str(skill_id_variant)
			var start := RBMDefinitionLoader.start_battle(definition, 1)
			var battle: RBMBattle = start["battle"]
			var result := battle.resolve_turn({str(i): {"type": "skill", "skill_id": skill_id, "target_id": i}})
			var log_entry := _find_entry(result["log"], i)
			assert_false(str(log_entry.get("reason", "")) == "unknown_skill", "%s (character %s) is individually usable, not just present in the skill list" % [skill_id, character_id])

# ---------------------------------------------------------------------------
# Test 9: 不正ID・不正フォーマット（IDは既知マスターへの安全な解決のみ許可）
# ---------------------------------------------------------------------------

func test_unknown_character_id_is_rejected_not_silently_fixed_up() -> void:
	var bad := {"boss": _base_boss(), "party": [{"character_id": "does_not_exist"}]}
	var resolved := RBMDefinitionLoader.resolve(bad)
	assert_false(bool(resolved.get("ok", true)))
	assert_true((resolved["errors"] as Array).size() > 0)
	assert_false(resolved.has("ally_defs"), "no partial battle-ready data is exposed on failure")

func test_character_id_containing_a_path_separator_is_rejected() -> void:
	var bad := {"boss": _base_boss(), "party": [{"character_id": "../hero"}]}
	var resolved := RBMDefinitionLoader.resolve(bad)
	assert_false(bool(resolved.get("ok", true)), "a path-traversal-shaped id must never be accepted")

func test_character_id_containing_a_backslash_is_rejected() -> void:
	var bad := {"boss": _base_boss(), "party": [{"character_id": "hero\\..\\allies"}]}
	var resolved := RBMDefinitionLoader.resolve(bad)
	assert_false(bool(resolved.get("ok", true)))

func test_unknown_skill_id_is_rejected() -> void:
	var bad := {"boss": _base_boss(), "party": [{"character_id": "hero", "allowed_skill_ids": ["hero_slash", "no_such_skill"]}]}
	var resolved := RBMDefinitionLoader.resolve(bad)
	assert_false(bool(resolved.get("ok", true)))

func test_skill_that_exists_but_is_not_owned_by_that_character_is_rejected() -> void:
	var bad := {"boss": _base_boss(), "party": [{"character_id": "hero", "allowed_skill_ids": ["tank_smash"]}]}
	var resolved := RBMDefinitionLoader.resolve(bad)
	assert_false(bool(resolved.get("ok", true)))

func test_a_bad_definition_never_reaches_start_battle_with_usable_data() -> void:
	var bad := {"boss": _base_boss(), "party": []}
	var start := RBMDefinitionLoader.start_battle(bad, 1)
	assert_false(bool(start.get("ok", true)))
	assert_false(start.has("battle"), "no RBMBattle instance is ever constructed from an invalid definition")
