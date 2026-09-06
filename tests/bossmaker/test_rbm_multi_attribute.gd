extends GutTest

## RPG BOSS MAKER — Phase 1 Step 4 未解決事項修正 (v0.1-C 多属性対応).
##
## STEP 2's confirmed spec always allowed selecting MULTIPLE weak/resist
## attributes (0 or more each), but the battle engine only ever supported a
## single value per side until now. This file exercises the resulting
## multi-attribute support end-to-end at the battle-core level:
## RBMUnit/RBMConstants (pure list-membership lookup), RBMDataLoader (raw
## Dictionary -> RBMUnit, both legacy singular-key and new plural-key shapes),
## RBMDefinitionLoader (Definition validation/translation, both shapes), and
## real RBMBattle.resolve_turn() damage results.
##
## See test_rbm_creator_draft.gd's own new test for the remaining leg of §7
## ("Creator接続": STEP2 selection -> to_definition() -> Loader -> a real
## TEST BATTLE actually applying the SECOND+ selected attribute, not just the
## first) -- that one needs RBMCreatorDraft and belongs alongside the rest of
## that class's own tests instead of being duplicated here.

const ALLY_DIR := "res://data_bossmaker/allies/"

var hero_def: Dictionary    # FIRE, atk 240, hero_slash x1.5
var butler_def: Dictionary  # ICE, atk 220, butler_ice_bolt x2.5
var healer_def: Dictionary  # LIGHTNING, atk 140, healer_shock x2.0
var samurai_def: Dictionary # WIND, atk 280, samurai_slash x2.0

func before_each() -> void:
	hero_def = RBMDataLoader.load_dict(ALLY_DIR + "hero.json")
	butler_def = RBMDataLoader.load_dict(ALLY_DIR + "butler.json")
	healer_def = RBMDataLoader.load_dict(ALLY_DIR + "healer.json")
	samurai_def = RBMDataLoader.load_dict(ALLY_DIR + "samurai.json")

func _one(def: Dictionary) -> Array[Dictionary]:
	var party: Array[Dictionary] = [def]
	return party

## Actor keys in the log mix int (ally id) and String ("boss") -- compare as
## strings, same pattern test_rbm_battle.gd/test_rbm_definition_loader.gd use.
func _find_log_entry(log: Array, actor) -> Dictionary:
	var actor_str := str(actor)
	for entry in log:
		if str(entry.get("actor", "")) == actor_str:
			return entry
	return {}

## A boss that just stands still and takes hits -- no boss skills need to
## fire for any of these tests, only the ally's own attack skill's attribute
## against whatever weak/resist this boss was given.
func _boss(extra: Dictionary = {}) -> Dictionary:
	var def := {
		"id": "multi_attr_boss", "display_name": "多属性テストボス", "hp": 1000000, "atk": 1, "spd": 1,
		"skills": [], "normal_action_candidates": [],
	}
	for key in extra:
		def[key] = extra[key]
	return def

## Allies (of the 5 fixed characters) only ever have FIRE/ICE/LIGHTNING/WIND
## attack skills -- none is NEUTRAL. §5 requires NEUTRAL to be selectable as a
## weak/resist attribute too, so this ad-hoc attacker (constructed the same
## way test_rbm_battle.gd's own _neutral_boss()/_attacking_boss() fixtures
## are, straight into RBMBattle.new(), not through the Loader) fills that gap.
func _neutral_attacker(atk: int = 100) -> Dictionary:
	return {
		"id": "neutral_attacker", "display_name": "無属性アタッカー", "attribute": "NEUTRAL",
		"hp": 999, "atk": atk, "spd": 999, "max_sp": 100,
		"skills": [
			{"id": "neutral_hit", "display_name": "無属性攻撃", "effect": "damage", "target": "boss", "attribute": "NEUTRAL", "atk_multiplier": 1.0, "sp_cost": 0},
		],
	}

# ---------------------------------------------------------------------------
# RBMConstants.attribute_multiplier_for_lists — pure function
# ---------------------------------------------------------------------------

func test_attribute_multiplier_for_lists_weak_membership() -> void:
	var weak: Array = [RBMConstants.Attribute.FIRE, RBMConstants.Attribute.WIND]
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.FIRE, weak, []), RBMConstants.ATTRIBUTE_MULTIPLIER_WEAK)
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.WIND, weak, []), RBMConstants.ATTRIBUTE_MULTIPLIER_WEAK)
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.ICE, weak, []), RBMConstants.ATTRIBUTE_MULTIPLIER_NORMAL)

func test_attribute_multiplier_for_lists_resist_membership() -> void:
	var resist: Array = [RBMConstants.Attribute.ICE, RBMConstants.Attribute.WIND]
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.ICE, [], resist), RBMConstants.ATTRIBUTE_MULTIPLIER_RESIST)
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.WIND, [], resist), RBMConstants.ATTRIBUTE_MULTIPLIER_RESIST)
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.FIRE, [], resist), RBMConstants.ATTRIBUTE_MULTIPLIER_NORMAL)

func test_attribute_multiplier_for_lists_empty_lists_is_always_normal() -> void:
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.NEUTRAL, [], []), RBMConstants.ATTRIBUTE_MULTIPLIER_NORMAL)
	assert_eq(RBMConstants.attribute_multiplier_for_lists(RBMConstants.Attribute.FIRE, [], []), RBMConstants.ATTRIBUTE_MULTIPLIER_NORMAL)

# ---------------------------------------------------------------------------
# 旧形式互換 — 単一weak_attribute/resist_attributeの旧Definitionが従来どおり動く
# ---------------------------------------------------------------------------

func test_legacy_singular_weak_attribute_still_produces_the_original_scalar_and_the_new_list() -> void:
	var battle := RBMBattle.new(_one(hero_def), _boss({"weak_attribute": "ICE"}), 1)
	var boss := battle.boss
	assert_eq(boss.weak_attribute, RBMConstants.Attribute.ICE, "the old singular field reads exactly as it always did")
	assert_eq(boss.weak_attributes, [RBMConstants.Attribute.ICE], "and is also visible as a one-element list")
	# hero attacks with FIRE -- boss is weak to ICE, not FIRE, so this must
	# still be a normal (not weak) hit, exactly as before this change.
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	assert_eq(int(_find_log_entry(result["log"], 0)["amount"]), 360, "240 * 1.5 * 1.0")

func test_legacy_singular_resist_attribute_still_produces_the_original_scalar_and_the_new_list() -> void:
	var battle := RBMBattle.new(_one(hero_def), _boss({"resist_attribute": "FIRE"}), 1)
	var boss := battle.boss
	assert_eq(boss.resist_attribute, RBMConstants.Attribute.FIRE)
	assert_eq(boss.resist_attributes, [RBMConstants.Attribute.FIRE])
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	# 240 * 1.5 * 0.8 (FIRE resisted) = 288
	assert_eq(int(_find_log_entry(result["log"], 0)["amount"]), 288)

func test_definition_loader_still_resolves_a_legacy_singular_attribute_definition() -> void:
	var boss := {
		"boss_id": "legacy_boss", "boss_name": "旧式ボス", "hp": 1000, "atk": 10, "spd": 5,
		"weak_attribute": "FIRE",
		"skills": [{"skill_id": "claw", "name": "claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
		"normal_actions": [{"skill_id": "claw", "weight": 1}],
	}
	var resolved := RBMDefinitionLoader.resolve({"party": [{"character_id": "hero"}], "boss": boss})
	assert_true(bool(resolved.get("ok", false)), "errors: %s" % str(resolved.get("errors", [])))
	var boss_def: Dictionary = resolved["boss_def"]
	assert_eq(str(boss_def["weak_attribute"]), "FIRE", "the singular key is preserved unchanged")
	assert_eq(boss_def["weak_attributes"], ["FIRE"], "and also exposed as a one-element list")
	assert_null(boss_def["resist_attribute"])
	assert_true((boss_def["resist_attributes"] as Array).is_empty())

# ---------------------------------------------------------------------------
# 複数弱点
# ---------------------------------------------------------------------------

func test_multiple_weak_attributes_each_independently_apply_the_weak_multiplier() -> void:
	var boss_def := _boss({"weak_attributes": ["FIRE", "LIGHTNING"]})
	var b_fire := RBMBattle.new(_one(hero_def), boss_def, 1)
	var r_fire := b_fire.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	assert_eq(int(_find_log_entry(r_fire["log"], 0)["amount"]), 432, "FIRE: 240 * 1.5 * 1.2 (weak)")

	var b_thunder := RBMBattle.new(_one(healer_def), boss_def, 1)
	var r_thunder := b_thunder.resolve_turn({"0": {"type": "skill", "skill_id": "healer_shock"}})
	assert_eq(int(_find_log_entry(r_thunder["log"], 0)["amount"]), 336, "LIGHTNING (thunder): 140 * 2.0 * 1.2 (weak)")

	var b_ice := RBMBattle.new(_one(butler_def), boss_def, 1)
	var r_ice := b_ice.resolve_turn({"0": {"type": "skill", "skill_id": "butler_ice_bolt"}})
	assert_eq(int(_find_log_entry(r_ice["log"], 0)["amount"]), 550, "ICE (not a registered weakness): 220 * 2.5 * 1.0")

# ---------------------------------------------------------------------------
# 複数耐性
# ---------------------------------------------------------------------------

func test_multiple_resist_attributes_each_independently_apply_the_resist_multiplier() -> void:
	var boss_def := _boss({"resist_attributes": ["ICE", "WIND"]})
	var b_ice := RBMBattle.new(_one(butler_def), boss_def, 1)
	var r_ice := b_ice.resolve_turn({"0": {"type": "skill", "skill_id": "butler_ice_bolt"}})
	assert_eq(int(_find_log_entry(r_ice["log"], 0)["amount"]), 440, "ICE: 220 * 2.5 * 0.8 (resist)")

	var b_wind := RBMBattle.new(_one(samurai_def), boss_def, 1)
	var r_wind := b_wind.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})
	assert_eq(int(_find_log_entry(r_wind["log"], 0)["amount"]), 448, "WIND: 280 * 2.0 * 0.8 (resist)")

	var b_fire := RBMBattle.new(_one(hero_def), boss_def, 1)
	var r_fire := b_fire.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	assert_eq(int(_find_log_entry(r_fire["log"], 0)["amount"]), 360, "FIRE (not a registered resistance): 240 * 1.5 * 1.0")

# ---------------------------------------------------------------------------
# 弱点＋耐性 同時
# ---------------------------------------------------------------------------

func test_weak_and_resist_attribute_lists_can_both_be_populated_at_once_with_correct_multipliers() -> void:
	var boss_def := _boss({
		"weak_attributes": ["FIRE", "LIGHTNING"],
		"resist_attributes": ["ICE", "WIND"],
	})
	var b_fire := RBMBattle.new(_one(hero_def), boss_def, 1)
	assert_eq(int(_find_log_entry(b_fire.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})["log"], 0)["amount"]), 432, "FIRE is weak")

	var b_thunder := RBMBattle.new(_one(healer_def), boss_def, 1)
	assert_eq(int(_find_log_entry(b_thunder.resolve_turn({"0": {"type": "skill", "skill_id": "healer_shock"}})["log"], 0)["amount"]), 336, "LIGHTNING is weak")

	var b_ice := RBMBattle.new(_one(butler_def), boss_def, 1)
	assert_eq(int(_find_log_entry(b_ice.resolve_turn({"0": {"type": "skill", "skill_id": "butler_ice_bolt"}})["log"], 0)["amount"]), 440, "ICE is resisted")

	var b_wind := RBMBattle.new(_one(samurai_def), boss_def, 1)
	assert_eq(int(_find_log_entry(b_wind.resolve_turn({"0": {"type": "skill", "skill_id": "samurai_slash"}})["log"], 0)["amount"]), 448, "WIND is resisted")

# ---------------------------------------------------------------------------
# 無属性 (NEUTRAL) — a real attribute, not "no attribute"
# ---------------------------------------------------------------------------

func test_neutral_can_be_registered_as_a_weakness_and_is_not_treated_as_no_weakness() -> void:
	var boss_def := _boss({"weak_attributes": ["NEUTRAL"]})
	var battle := RBMBattle.new(_one(_neutral_attacker(100)), boss_def, 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "neutral_hit"}})
	assert_eq(int(_find_log_entry(result["log"], 0)["amount"]), 120, "100 * 1.0 * 1.2 -- NEUTRAL is a registered weakness here")

func test_neutral_can_be_registered_as_a_resistance() -> void:
	var boss_def := _boss({"resist_attributes": ["NEUTRAL"]})
	var battle := RBMBattle.new(_one(_neutral_attacker(100)), boss_def, 1)
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "neutral_hit"}})
	assert_eq(int(_find_log_entry(result["log"], 0)["amount"]), 80, "100 * 1.0 * 0.8 -- NEUTRAL is a registered resistance here")

# ---------------------------------------------------------------------------
# RBMDefinitionLoader — plural-key validation and full loader->battle wiring
# ---------------------------------------------------------------------------

func _base_boss_for_loader() -> Dictionary:
	return {
		"boss_id": "multi_attr_loader_boss", "boss_name": "多属性ボス", "hp": 1000, "atk": 100, "spd": 50,
		"skills": [{"skill_id": "claw", "name": "claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
		"normal_actions": [{"skill_id": "claw", "weight": 1}],
	}

func test_loader_resolves_the_new_plural_weak_and_resist_attribute_keys() -> void:
	var boss := _base_boss_for_loader()
	boss["weak_attributes"] = ["FIRE", "LIGHTNING"]
	boss["resist_attributes"] = ["ICE", "WIND"]
	var resolved := RBMDefinitionLoader.resolve({"party": [{"character_id": "hero"}], "boss": boss})
	assert_true(bool(resolved.get("ok", false)), "errors: %s" % str(resolved.get("errors", [])))
	var boss_def: Dictionary = resolved["boss_def"]
	assert_eq(boss_def["weak_attributes"], ["FIRE", "LIGHTNING"], "nothing beyond the first entry is dropped")
	assert_eq(boss_def["resist_attributes"], ["ICE", "WIND"])
	assert_eq(str(boss_def["weak_attribute"]), "FIRE", "singular key still exposed = first entry, for backward compatibility")
	assert_eq(str(boss_def["resist_attribute"]), "ICE")

func test_loader_rejects_an_unknown_attribute_inside_the_plural_weak_attributes_list() -> void:
	var boss := _base_boss_for_loader()
	boss["weak_attributes"] = ["FIRE", "EARTH"]
	var resolved := RBMDefinitionLoader.resolve({"party": [{"character_id": "hero"}], "boss": boss})
	assert_false(bool(resolved.get("ok", false)), "an unknown attribute anywhere in the list must still be rejected")

func test_loader_with_neither_key_resolves_to_empty_lists_and_null_singulars() -> void:
	var resolved := RBMDefinitionLoader.resolve({"party": [{"character_id": "hero"}], "boss": _base_boss_for_loader()})
	assert_true(bool(resolved.get("ok", false)))
	var boss_def: Dictionary = resolved["boss_def"]
	assert_true((boss_def["weak_attributes"] as Array).is_empty())
	assert_true((boss_def["resist_attributes"] as Array).is_empty())
	assert_null(boss_def["weak_attribute"])
	assert_null(boss_def["resist_attribute"])

func test_loader_to_real_battle_a_second_and_third_weak_attribute_actually_apply_not_just_the_first() -> void:
	var boss := _base_boss_for_loader()
	boss["weak_attributes"] = ["ICE", "LIGHTNING", "WIND"]
	var start := RBMDefinitionLoader.start_battle({"party": [{"character_id": "healer"}], "boss": boss}, 1)
	assert_true(bool(start.get("ok", false)), "errors: %s" % str(start.get("errors", [])))
	var battle: RBMBattle = start["battle"]
	# healer's own attribute is LIGHTNING -- the SECOND entry of weak_attributes,
	# not the first (ICE) -- exercising exactly the case the old "only
	# weak_attributes[0] survives to_definition()" stopgap would have missed.
	var result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "healer_shock"}})
	assert_eq(int(_find_log_entry(result["log"], 0)["amount"]), 336, "140 * 2.0 * 1.2 -- LIGHTNING, the 2nd entry, reached real battle damage")
