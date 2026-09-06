extends GutTest

## RPG BOSS MAKER Phase 1 Step 4 — RBMCreatorDraft (SIMPLE Creator's
## in-progress data model) tests. Pure data/logic, no UI involved.
##
## Codex最終レビュー指摘対応で追加された1件のテストのみ、実際に
## RBMLocalStageRepositoryへ保存する（作者備考の実UI値が保存JSONまで到達
## することを確認するため）。他の全既存テストはRepositoryへ一切触れない
## ため、このbefore_each/after_eachは無害——実プレイヤーのuser://保存
## ライブラリを汚さないよう、念のためテスト専用ディレクトリへ差し替える。

const _UI_TEST_DIR := "user://bossmaker_test_draft_ui/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(_UI_TEST_DIR)

func after_each() -> void:
	var dir := DirAccess.open(_UI_TEST_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				DirAccess.remove_absolute(_UI_TEST_DIR + "/" + entry)
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(_UI_TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _valid_attack_skill(name: String = "Attack", target: String = "single", attribute: String = "NEUTRAL", atk_multiplier: float = 1.0) -> Dictionary:
	return {"name": name, "type": "attack", "target": target, "attribute": attribute, "atk_multiplier": atk_multiplier}

func _valid_self_heal_fixed(name: String = "Heal", amount: int = 100) -> Dictionary:
	return {"name": name, "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": amount, "heal_percent": 0.0}

func _valid_self_heal_percent(name: String = "Heal", percent: float = 10.0) -> Dictionary:
	return {"name": name, "type": "self_heal", "heal_mode": "percent", "heal_fixed_amount": 0, "heal_percent": percent}

func _valid_atk_self_buff(name: String = "Buff", multiplier: float = 1.5, duration: int = 3) -> Dictionary:
	return {"name": name, "type": "atk_self_buff", "buff_multiplier": multiplier, "duration_turns": duration}

func _basic_draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	return draft

# ---------------------------------------------------------------------------
# STEP 1
# ---------------------------------------------------------------------------

func test_empty_name_is_invalid() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = ""
	assert_false(draft.step1_is_valid())

func test_one_char_name_is_valid() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "A"
	assert_true(draft.step1_is_valid())

func test_twenty_char_name_is_valid() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "A".repeat(20)
	assert_eq(draft.boss_name.length(), 20)
	assert_true(draft.step1_is_valid())

func test_twenty_one_char_name_is_invalid() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "A".repeat(21)
	assert_false(draft.step1_is_valid())

func test_appearance_id_is_retained_on_the_draft() -> void:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "slime_a"
	assert_eq(draft.appearance_id, "slime_a")

# ---------------------------------------------------------------------------
# STEP 2
# ---------------------------------------------------------------------------

func test_hp_atk_spd_boundaries_match_definition_loader_exactly() -> void:
	# §2-4: the Draft must never redefine these ranges -- it reads them
	# straight off RBMDefinitionLoader's own constants.
	var draft := _basic_draft()
	draft.hp = RBMDefinitionLoader.BOSS_HP_MIN
	draft.atk = RBMDefinitionLoader.BOSS_ATK_MIN
	draft.spd = RBMDefinitionLoader.BOSS_SPD_MIN
	assert_true(draft.step2_is_valid())
	draft.hp = RBMDefinitionLoader.BOSS_HP_MAX
	draft.atk = RBMDefinitionLoader.BOSS_ATK_MAX
	draft.spd = RBMDefinitionLoader.BOSS_SPD_MAX
	assert_true(draft.step2_is_valid())
	draft.hp = RBMDefinitionLoader.BOSS_HP_MAX + 1
	assert_false(draft.step2_is_valid())

func test_multiple_weak_attributes_can_be_selected() -> void:
	var draft := _basic_draft()
	draft.toggle_weak_attribute("FIRE")
	draft.toggle_weak_attribute("WIND")
	assert_eq(draft.weak_attributes, ["FIRE", "WIND"])

func test_multiple_resist_attributes_can_be_selected() -> void:
	var draft := _basic_draft()
	draft.toggle_resist_attribute("ICE")
	draft.toggle_resist_attribute("LIGHTNING")
	assert_eq(draft.resist_attributes, ["ICE", "LIGHTNING"])

func test_selecting_the_same_attribute_on_the_opposite_side_moves_it() -> void:
	var draft := _basic_draft()
	draft.toggle_weak_attribute("FIRE")
	assert_true(draft.weak_attributes.has("FIRE"))
	draft.toggle_resist_attribute("FIRE")
	assert_false(draft.weak_attributes.has("FIRE"), "FIRE must be removed from weak once selected as resist")
	assert_true(draft.resist_attributes.has("FIRE"))

	draft.toggle_weak_attribute("FIRE")
	assert_false(draft.resist_attributes.has("FIRE"), "and the reverse direction also moves it")
	assert_true(draft.weak_attributes.has("FIRE"))

func test_neutral_can_be_selected_as_a_normal_attribute() -> void:
	var draft := _basic_draft()
	draft.toggle_weak_attribute("NEUTRAL")
	assert_true(draft.weak_attributes.has("NEUTRAL"))

func test_zero_weak_and_resist_selections_is_valid() -> void:
	var draft := _basic_draft()
	assert_true(draft.weak_attributes.is_empty())
	assert_true(draft.resist_attributes.is_empty())
	draft.add_skill(_valid_attack_skill())
	draft.party_character_ids = ["hero"]
	var resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(resolved.get("ok", false)), "no weak/resist attribute at all must still resolve to a valid Definition")

# ---------------------------------------------------------------------------
# STEP 3
# ---------------------------------------------------------------------------

## Creator UI再設計 §1: MAX_SKILLSは8→64へ引き上げ済み（旧「8体まで」の
## 上限を前提にしたテストだったため、新しい上限へ合わせて書き直した）。
func test_up_to_max_skills_can_be_added() -> void:
	var draft := _basic_draft()
	for i in range(RBMCreatorDraft.MAX_SKILLS):
		var id := draft.add_skill(_valid_attack_skill("S%d" % i))
		assert_ne(id, "", "skill %d should be addable" % i)
	assert_eq(draft.skills.size(), RBMCreatorDraft.MAX_SKILLS)

func test_one_skill_past_the_max_is_rejected() -> void:
	var draft := _basic_draft()
	for i in range(RBMCreatorDraft.MAX_SKILLS):
		draft.add_skill(_valid_attack_skill("S%d" % i))
	assert_false(draft.can_add_skill())
	var id := draft.add_skill(_valid_attack_skill("OneTooMany"))
	assert_eq(id, "")
	assert_eq(draft.skills.size(), RBMCreatorDraft.MAX_SKILLS)

func test_attack_skill_definition_shape() -> void:
	var draft := _basic_draft()
	var id := draft.add_skill(_valid_attack_skill("炎獄斬", "all", "FIRE", 2.5))
	var skill := draft.find_skill(id)
	assert_eq(str(skill["type"]), "attack")
	assert_eq(str(skill["target"]), "all")
	assert_eq(str(skill["attribute"]), "FIRE")
	assert_eq(float(skill["atk_multiplier"]), 2.5)

func test_self_heal_fixed_amount_percent_readout() -> void:
	var draft := _basic_draft()
	draft.hp = 5000
	var id := draft.add_skill(_valid_self_heal_fixed("Heal", 1000))
	var skill := draft.find_skill(id)
	assert_almost_eq(draft.heal_percent_of_current_max_hp(skill), 20.0, 0.001)
	assert_eq(draft.resolved_heal_amount(skill), 1000, "fixed mode: heal_amount is the raw fixed value")

func test_self_heal_percent_mode_amount_readout() -> void:
	var draft := _basic_draft()
	draft.hp = 5000
	var id := draft.add_skill(_valid_self_heal_percent("Heal", 20.0))
	var skill := draft.find_skill(id)
	assert_eq(draft.resolved_heal_amount(skill), 1000, "percent mode: 20% of 5000 max HP = 1000")

func test_self_heal_fixed_mode_percent_readout_recalculates_when_hp_changes() -> void:
	var draft := _basic_draft()
	draft.hp = 5000
	var id := draft.add_skill(_valid_self_heal_fixed("Heal", 1000))
	var skill := draft.find_skill(id)
	assert_almost_eq(draft.heal_percent_of_current_max_hp(skill), 20.0, 0.001)
	draft.hp = 10000
	assert_almost_eq(draft.heal_percent_of_current_max_hp(skill), 10.0, 0.001, "the fixed amount itself never changes, only its % readout")
	assert_eq(draft.resolved_heal_amount(skill), 1000, "fixed mode's actual heal_amount is unaffected by HP changes")

func test_self_heal_percent_mode_amount_recalculates_when_hp_changes() -> void:
	var draft := _basic_draft()
	draft.hp = 5000
	var id := draft.add_skill(_valid_self_heal_percent("Heal", 20.0))
	var skill := draft.find_skill(id)
	assert_eq(draft.resolved_heal_amount(skill), 1000)
	draft.hp = 10000
	assert_eq(draft.resolved_heal_amount(skill), 2000, "percent mode's actual amount re-derives from the new max HP")

func test_atk_self_buff_preview() -> void:
	var draft := _basic_draft()
	draft.atk = 200
	var id := draft.add_skill(_valid_atk_self_buff("Rage", 1.5, 3))
	var skill := draft.find_skill(id)
	assert_eq(draft.buffed_atk_preview(skill), 300)

func test_baseline_attack_damage_uses_shared_formula_and_no_attribute_multiplier() -> void:
	var draft := _basic_draft()
	draft.atk = 100
	var id := draft.add_skill(_valid_attack_skill("Hit", "single", "FIRE", 2.0))
	var skill := draft.find_skill(id)
	# 100 x 2.0 x 1.0(no target yet) x 1.0 x 1.0 = 200, matching
	# RBMBattle.compute_damage_amount directly (not a re-derived formula).
	assert_eq(draft.baseline_attack_damage(skill), 200)
	assert_eq(draft.baseline_attack_damage(skill), RBMBattle.compute_damage_amount(100.0, 2.0, 1.0, 1.0, 1.0))

func test_baseline_damage_recalculates_when_boss_atk_or_multiplier_changes() -> void:
	var draft := _basic_draft()
	draft.atk = 100
	var id := draft.add_skill(_valid_attack_skill("Hit", "single", "NEUTRAL", 1.0))
	var skill := draft.find_skill(id)
	assert_eq(draft.baseline_attack_damage(skill), 100)
	draft.atk = 300
	assert_eq(draft.baseline_attack_damage(skill), 300)
	skill["atk_multiplier"] = 2.0
	draft.update_skill(id, skill)
	assert_eq(draft.baseline_attack_damage(draft.find_skill(id)), 600)

# ---------------------------------------------------------------------------
# STEP 4
# ---------------------------------------------------------------------------

func test_normal_actions_disabled_by_default() -> void:
	var draft := _basic_draft()
	assert_false(draft.normal_actions_enabled)
	assert_true(draft.step4_is_valid(), "disabled normal actions never block progress regardless of percentages")

func test_percentage_sum_of_100_is_valid() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	var b := draft.add_skill(_valid_attack_skill("B"))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[a] = 40.0
	draft.normal_action_percentages[b] = 60.0
	assert_true(draft.step4_is_valid())

func test_percentage_sum_under_100_is_invalid() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[a] = 80.0
	assert_false(draft.step4_is_valid())

func test_percentage_sum_over_100_is_invalid() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	var b := draft.add_skill(_valid_attack_skill("B"))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[a] = 70.0
	draft.normal_action_percentages[b] = 70.0
	assert_false(draft.step4_is_valid())

func test_zero_percent_skill_is_excluded_from_generated_normal_actions() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	var b := draft.add_skill(_valid_attack_skill("B"))
	draft.party_character_ids = ["hero"]
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[a] = 100.0
	draft.normal_action_percentages[b] = 0.0
	var boss: Dictionary = draft.to_definition()["boss"]
	var ids: Array = []
	for candidate in boss["normal_actions"]:
		ids.append(str(candidate["skill_id"]))
	assert_eq(ids, [a], "a 0% skill must not appear as a normal-action candidate at all")

func test_equalize_distributes_evenly_with_no_rounding_drift_for_4_skills() -> void:
	var draft := _basic_draft()
	var ids: Array = []
	for i in range(4):
		ids.append(draft.add_skill(_valid_attack_skill("S%d" % i)))
	draft.equalize_normal_action_percentages()
	var total := 0.0
	for id in ids:
		assert_almost_eq(float(draft.normal_action_percentages[id]), 25.0, 0.001)
		total += float(draft.normal_action_percentages[id])
	assert_almost_eq(total, 100.0, 0.0001)

func test_equalize_distributes_evenly_with_no_rounding_drift_for_8_skills() -> void:
	var draft := _basic_draft()
	var ids: Array = []
	for i in range(8):
		ids.append(draft.add_skill(_valid_attack_skill("S%d" % i)))
	draft.equalize_normal_action_percentages()
	var total := 0.0
	for id in ids:
		assert_almost_eq(float(draft.normal_action_percentages[id]), 12.5, 0.001)
		total += float(draft.normal_action_percentages[id])
	assert_almost_eq(total, 100.0, 0.0001)

func test_equalize_with_3_skills_sums_to_exactly_100_despite_repeating_decimals() -> void:
	var draft := _basic_draft()
	var ids: Array = []
	for i in range(3):
		ids.append(draft.add_skill(_valid_attack_skill("S%d" % i)))
	draft.equalize_normal_action_percentages()
	var total := 0.0
	for id in ids:
		total += float(draft.normal_action_percentages[id])
	assert_almost_eq(total, 100.0, 0.0001, "33.3/33.3/33.4 must sum to exactly 100.0, not 99.9")

func test_scripted_actions_three_timings() -> void:
	var draft := _basic_draft()
	var s := draft.add_skill(_valid_attack_skill("S"))
	draft.add_scripted_action(3, s, "replace")
	draft.add_scripted_action(1, s, "turn_start_interrupt")
	draft.add_scripted_action(5, s, "turn_end_interrupt")
	assert_eq(draft.scripted_actions.size(), 3)
	var timings: Array = []
	for entry in draft.scripted_actions:
		timings.append(str(entry["timing"]))
	assert_true(timings.has("replace"))
	assert_true(timings.has("turn_start_interrupt"))
	assert_true(timings.has("turn_end_interrupt"))

func test_reordering_generates_order_1_2_3_from_ui_array_position() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_self_heal_fixed("A", 10))
	var b := draft.add_skill(_valid_atk_self_buff("B", 1.5, 1))
	draft.add_scripted_action(3, a, "turn_start_interrupt")  # declared first
	draft.add_scripted_action(3, b, "turn_start_interrupt")  # declared second
	# now move b above a using only up/down -- never a raw order number.
	assert_true(draft.move_scripted_action(1, -1))
	draft.party_character_ids = ["hero"]
	var boss: Dictionary = draft.to_definition()["boss"]
	var scripted: Array = boss["scripted_actions"]
	assert_eq(scripted.size(), 2)
	assert_eq(str(scripted[0]["skill_id"]), b, "after moving up, b's order must now be 1")
	assert_eq(int(scripted[0]["order"]), 1)
	assert_eq(str(scripted[1]["skill_id"]), a)
	assert_eq(int(scripted[1]["order"]), 2)

func test_move_scripted_action_cannot_cross_a_different_group() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	var b := draft.add_skill(_valid_attack_skill("B"))
	draft.add_scripted_action(1, a, "replace")
	draft.add_scripted_action(2, b, "replace")  # different turn = different group
	assert_false(draft.move_scripted_action(1, -1), "must not merge across a (turn,timing) group boundary")

func test_deleting_a_skill_removes_scripted_actions_that_reference_it() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	var b := draft.add_skill(_valid_attack_skill("B"))
	draft.add_scripted_action(1, a, "replace")
	draft.add_scripted_action(1, b, "replace")
	draft.remove_skill(a)
	assert_eq(draft.scripted_actions.size(), 1)
	assert_eq(str(draft.scripted_actions[0]["skill_id"]), b)

func test_normal_actions_off_and_zero_scripted_actions_is_still_valid() -> void:
	var draft := _basic_draft()
	draft.add_skill(_valid_attack_skill("A"))
	assert_false(draft.normal_actions_enabled)
	assert_true(draft.scripted_actions.is_empty())
	assert_true(draft.step4_is_valid())
	draft.party_character_ids = ["hero"]
	var resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(resolved.get("ok", false)), "a boss with no normal actions and no scripted actions is a valid (if inert) Definition")

# ---------------------------------------------------------------------------
# STEP 5
# ---------------------------------------------------------------------------

func test_one_party_member_is_valid() -> void:
	var draft := _basic_draft()
	assert_true(draft.add_party_character("hero"))
	assert_true(draft.step5_is_valid())

func test_four_party_members_is_valid() -> void:
	var draft := _basic_draft()
	for id in ["hero", "butler", "healer", "samurai"]:
		assert_true(draft.add_party_character(id))
	assert_eq(draft.party_character_ids.size(), 4)
	assert_true(draft.step5_is_valid())

func test_zero_party_members_is_invalid() -> void:
	var draft := _basic_draft()
	assert_true(draft.party_character_ids.is_empty())
	assert_false(draft.step5_is_valid())

func test_a_fifth_party_member_is_rejected() -> void:
	var draft := _basic_draft()
	for id in ["hero", "butler", "healer", "samurai"]:
		draft.add_party_character(id)
	assert_false(draft.add_party_character("tank"))
	assert_eq(draft.party_character_ids.size(), 4)

func test_duplicate_party_member_is_rejected() -> void:
	var draft := _basic_draft()
	assert_true(draft.add_party_character("hero"))
	assert_false(draft.add_party_character("hero"))
	assert_eq(draft.party_character_ids.size(), 1)

func test_adding_a_character_defaults_all_their_skills_on() -> void:
	var draft := _basic_draft()
	draft.add_party_character("hero")
	var expected := draft.all_master_skill_ids("hero")
	assert_eq(draft.ally_allowed_skill_ids["hero"], expected)
	assert_true(expected.size() > 0)

# ---------------------------------------------------------------------------
# STEP 6
# ---------------------------------------------------------------------------

func test_zero_allowed_skills_for_a_character_is_valid() -> void:
	var draft := _basic_draft()
	draft.add_party_character("hero")
	draft.set_all_ally_skills_allowed("hero", false)
	assert_eq(draft.ally_allowed_skill_ids["hero"], [])
	assert_true(draft.step6_is_valid())

func test_set_all_on_and_off_for_one_character() -> void:
	var draft := _basic_draft()
	draft.add_party_character("hero")
	draft.set_all_ally_skills_allowed("hero", false)
	assert_true(draft.ally_allowed_skill_ids["hero"].is_empty())
	draft.set_all_ally_skills_allowed("hero", true)
	assert_eq(draft.ally_allowed_skill_ids["hero"], draft.all_master_skill_ids("hero"))

func test_set_all_party_skills_allowed_off_then_on() -> void:
	var draft := _basic_draft()
	draft.add_party_character("hero")
	draft.add_party_character("tank")
	draft.set_all_party_skills_allowed(false)
	assert_true(draft.ally_allowed_skill_ids["hero"].is_empty())
	assert_true(draft.ally_allowed_skill_ids["tank"].is_empty())
	draft.set_all_party_skills_allowed(true)
	assert_eq(draft.ally_allowed_skill_ids["hero"], draft.all_master_skill_ids("hero"))
	assert_eq(draft.ally_allowed_skill_ids["tank"], draft.all_master_skill_ids("tank"))

func test_toggling_a_single_skill() -> void:
	var draft := _basic_draft()
	draft.add_party_character("hero")
	var skill_id: String = draft.all_master_skill_ids("hero")[0]
	assert_true(draft.is_ally_skill_allowed("hero", skill_id))
	draft.set_ally_skill_allowed("hero", skill_id, false)
	assert_false(draft.is_ally_skill_allowed("hero", skill_id))
	draft.set_ally_skill_allowed("hero", skill_id, true)
	assert_true(draft.is_ally_skill_allowed("hero", skill_id))

func test_removed_character_settings_are_not_included_in_the_generated_definition() -> void:
	var draft := _basic_draft()
	draft.add_skill(_valid_attack_skill("A"))
	draft.add_party_character("hero")
	draft.add_party_character("tank")
	draft.remove_party_character("tank")  # §10: dropped from the party
	var boss_ids: Array = []
	for entry in draft.to_definition()["party"]:
		boss_ids.append(str(entry["character_id"]))
	assert_eq(boss_ids, ["hero"], "a removed party member's skill settings must never appear in the generated Definition")

# ---------------------------------------------------------------------------
# STEP 7 — per-character real damage preview
# ---------------------------------------------------------------------------

func test_party_damage_preview_uses_real_attribute_multiplier_for_each_character() -> void:
	var draft := _basic_draft()
	draft.atk = 100
	# hero.json's own attribute is FIRE -> weak=ICE, resist=FIRE (derived).
	var id := draft.add_skill(_valid_attack_skill("Ice Hit", "single", "ICE", 1.0))
	draft.add_party_character("hero")
	var preview := draft.party_damage_preview(draft.find_skill(id))
	# ICE attack vs hero's ICE weakness -> 1.2x -> round(100*1.0*1.2)=120
	assert_eq(int(preview["hero"]), 120)

func test_party_damage_preview_with_atk_self_buff_multiplier() -> void:
	var draft := _basic_draft()
	draft.atk = 100
	var id := draft.add_skill(_valid_attack_skill("Fire Hit", "single", "FIRE", 1.0))
	draft.add_party_character("hero")
	var normal := draft.party_damage_preview(draft.find_skill(id), 1.0)
	# FIRE attack vs hero's FIRE resistance -> 0.8x -> round(100*1.0*0.8)=80
	assert_eq(int(normal["hero"]), 80)
	var buffed := draft.party_damage_preview(draft.find_skill(id), 2.0)
	assert_eq(int(buffed["hero"]), 160)

func test_party_damage_preview_matches_a_real_boss_hit_for_an_undefended_target() -> void:
	# §7-4: same result as the real RBMBattle for the well-defined case this
	# preview covers (undefended target, no active buffs/kabau/counter).
	var draft := _basic_draft()
	draft.atk = 137
	var id := draft.add_skill(_valid_attack_skill("Wind Hit", "single", "WIND", 1.7))
	draft.add_party_character("samurai")  # samurai's own attribute is WIND -> resist=WIND
	var preview := draft.party_damage_preview(draft.find_skill(id))

	var definition := draft.to_definition()
	definition["boss"]["normal_actions"] = [{"skill_id": id, "weight": 1}]
	var start := RBMDefinitionLoader.start_battle(definition, 1)
	var battle: RBMBattle = start["battle"]
	var samurai := battle.party[0]
	var hp_before := samurai.hp
	# "attack" (not "defend"): the preview assumes an undefended target.
	battle.resolve_turn({"0": {"type": "attack"}})
	var actual_damage := hp_before - samurai.hp
	assert_eq(actual_damage, int(preview["samurai"]), "the preview must equal the real battle's damage for an undefended target")

# ---------------------------------------------------------------------------
# Definition generation round-trips through RBMDefinitionLoader
# ---------------------------------------------------------------------------

func test_full_draft_generates_a_definition_that_resolves_and_produces_a_working_battle() -> void:
	var draft := _basic_draft()
	var atk_id := draft.add_skill(_valid_attack_skill("Slash", "single", "NEUTRAL", 1.0))
	draft.add_skill(_valid_self_heal_percent("Regen", 10.0))
	draft.add_skill(_valid_atk_self_buff("Rage", 1.5, 2))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[atk_id] = 100.0
	draft.add_party_character("hero")
	draft.add_party_character("tank")

	var definition := draft.to_definition()
	var resolved := RBMDefinitionLoader.resolve(definition)
	assert_true(bool(resolved.get("ok", false)), "errors: %s" % str(resolved.get("errors", [])))

	var start := RBMDefinitionLoader.start_battle(definition, 1)
	assert_true(bool(start.get("ok", false)))
	var battle: RBMBattle = start["battle"]
	assert_eq(battle.party.size(), 2)
	assert_eq(battle.boss.max_hp, draft.hp)
	assert_eq(battle.boss.display_name, draft.boss_name)

# ---------------------------------------------------------------------------
# v0.1-C 多属性対応 §7「Creator接続」— STEP 2の複数選択が to_definition() ->
# RBMDefinitionLoader -> 実際のTEST BATTLEダメージ計算まで、2件目以降の属性も
# 失わず届くこと。
# ---------------------------------------------------------------------------

func _find_log_entry_for_actor(log: Array, actor) -> Dictionary:
	var actor_str := str(actor)
	for entry in log:
		if str(entry.get("actor", "")) == actor_str:
			return entry
	return {}

func test_multi_attribute_selection_reaches_real_damage_through_definition_and_loader() -> void:
	var draft := _basic_draft()
	# hero is FIRE, healer is LIGHTNING (both actual master ally attributes) --
	# selecting BOTH as weak on the boss exercises the second entry too, not
	# just the first (what the removed stopgap would have silently dropped).
	draft.toggle_weak_attribute("FIRE")
	draft.toggle_weak_attribute("LIGHTNING")
	draft.add_party_character("hero")
	draft.add_party_character("healer")

	var definition := draft.to_definition()
	assert_eq(definition["boss"]["weak_attributes"], ["FIRE", "LIGHTNING"], "both selected attributes are written into the generated Definition")

	var start := RBMDefinitionLoader.start_battle(definition, 1)
	assert_true(bool(start.get("ok", false)), "errors: %s" % str(start.get("errors", [])))
	var battle: RBMBattle = start["battle"]

	var fire_result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	var fire_entry := _find_log_entry_for_actor(fire_result["log"], 0)
	assert_eq(int(fire_entry["amount"]), 432, "hero's FIRE attack (weak_attributes[0]) lands as a weak hit: 240 * 1.5 * 1.2")

	var thunder_result := battle.resolve_turn({"1": {"type": "skill", "skill_id": "healer_shock"}})
	var thunder_entry := _find_log_entry_for_actor(thunder_result["log"], 1)
	assert_eq(int(thunder_entry["amount"]), 336, "healer's LIGHTNING attack (weak_attributes[1], the SECOND entry) ALSO lands as a weak hit: 140 * 2.0 * 1.2")

func test_multi_attribute_selection_with_both_weak_and_resist_reaches_real_battle() -> void:
	var draft := _basic_draft()
	draft.toggle_weak_attribute("FIRE")
	draft.toggle_resist_attribute("WIND")
	draft.add_party_character("hero")
	draft.add_party_character("samurai")

	var definition := draft.to_definition()
	assert_eq(definition["boss"]["weak_attributes"], ["FIRE"])
	assert_eq(definition["boss"]["resist_attributes"], ["WIND"])

	var start := RBMDefinitionLoader.start_battle(definition, 1)
	assert_true(bool(start.get("ok", false)), "errors: %s" % str(start.get("errors", [])))
	var battle: RBMBattle = start["battle"]

	var weak_result := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})
	assert_eq(int(_find_log_entry_for_actor(weak_result["log"], 0)["amount"]), 432, "FIRE is weak: 240 * 1.5 * 1.2")

	var resist_result := battle.resolve_turn({"1": {"type": "skill", "skill_id": "samurai_slash"}})
	assert_eq(int(_find_log_entry_for_actor(resist_result["log"], 1)["amount"]), 448, "WIND is resisted: 280 * 2.0 * 0.8")

# ---------------------------------------------------------------------------
# Phase 1 Step 6 — ローカル保存・再編集: Draft側のシリアライズ/復元 (§48/§49/§50)
# ---------------------------------------------------------------------------

## §48/§49: 全フィールドを埋めたDraftを作り、to_saved_dict()/
## restore_from_saved_dict()の組で往復させても完全に元へ戻ることを確認する
## （JSONを一切経由しない、純粋なDraft <-> Dictionaryの往復）。
func _fully_populated_draft() -> RBMCreatorDraft:
	var draft := _basic_draft()
	draft.appearance_id = "appearance_dragon"
	draft.toggle_weak_attribute("FIRE")
	draft.toggle_weak_attribute("WIND")
	draft.toggle_resist_attribute("ICE")
	var attack_id := draft.add_skill(_valid_attack_skill("斬撃", "all", "FIRE", 2.5))
	var heal_id := draft.add_skill(_valid_self_heal_percent("回復", 15.0))
	var buff_id := draft.add_skill(_valid_atk_self_buff("強化", 1.75, 4))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[attack_id] = 60.0
	draft.normal_action_percentages[heal_id] = 40.0
	draft.add_scripted_action(3, buff_id, "turn_start_interrupt")
	draft.add_scripted_action(3, attack_id, "turn_start_interrupt")
	draft.add_party_character("hero")
	draft.add_party_character("tank")
	draft.set_ally_skill_allowed("tank", draft.all_master_skill_ids("tank")[0], false)
	return draft

func test_to_saved_dict_and_restore_from_saved_dict_round_trips_every_field() -> void:
	var original := _fully_populated_draft()
	var saved := original.to_saved_dict()

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)

	assert_eq(restored.boss_name, original.boss_name)
	assert_eq(restored.appearance_id, original.appearance_id)
	assert_eq(restored.hp, original.hp)
	assert_eq(restored.atk, original.atk)
	assert_eq(restored.spd, original.spd)
	assert_eq(restored.weak_attributes, original.weak_attributes)
	assert_eq(restored.resist_attributes, original.resist_attributes)
	assert_eq(restored.skills, original.skills, "raw authoring skill fields (heal_mode/heal_fixed_amount/heal_percent etc.) must survive verbatim")
	assert_eq(restored.normal_actions_enabled, original.normal_actions_enabled)
	assert_eq(restored.normal_action_percentages, original.normal_action_percentages)
	assert_eq(restored.scripted_actions, original.scripted_actions, "array ORDER within a (turn,timing) group must be preserved")
	assert_eq(restored.party_character_ids, original.party_character_ids)
	assert_eq(restored.ally_allowed_skill_ids, original.ally_allowed_skill_ids)

## §9/§20: `_next_skill_ordinal`を明示的に確認する専用テスト——最大既存
## skill_idから再計算する設計だとskill_id削除→再作成が別スキル扱いという
## Step 5確定仕様を壊しうるため、この値だけを狙って往復確認する。
func test_next_skill_ordinal_round_trips_and_is_not_recomputed_from_existing_skills() -> void:
	var draft := _basic_draft()
	var a := draft.add_skill(_valid_attack_skill("A"))
	draft.remove_skill(a)  # boss_skill_1は削除済み、_next_skill_ordinalは2のまま
	var saved := draft.to_saved_dict()
	assert_eq(int(saved["next_skill_ordinal"]), 2)

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	var new_id := restored.add_skill(_valid_attack_skill("B"))
	assert_eq(new_id, "boss_skill_2", "must continue from the saved counter, not re-derive boss_skill_1 from an (now-empty) skills array")
	assert_ne(new_id, a, "must never reissue a deleted skill's old id")

## §7: DefinitionではなくDraftの生フィールドを保存の正とする——skillsの
## 著作フィールド（heal_mode等）はDefinitionへ変換すると失われるため、
## restore_from_saved_dict()後もSTEP3編集用の生フィールドがそのまま残って
## いることを直接確認する。
func test_self_heal_authoring_fields_survive_round_trip_even_though_definition_loses_them() -> void:
	var draft := _basic_draft()
	var heal_id := draft.add_skill(_valid_self_heal_percent("回復", 33.0))
	var saved := draft.to_saved_dict()
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	var restored_skill := restored.find_skill(heal_id)
	assert_eq(str(restored_skill["heal_mode"]), "percent")
	assert_almost_eq(float(restored_skill["heal_percent"]), 33.0, 0.001)
	# resolved_heal_amount()（Definition向け解決済み値）は生フィールドから
	# 都度再計算できることも合わせて確認。
	restored.hp = 10000
	assert_eq(restored.resolved_heal_amount(restored_skill), 3300)

## §15/§16/§18/§19: full_authoring_snapshot()自体の内容確認——stage_idは
## 対象外(§18)、Clear Check成功snapshotは対象(§16)。
func test_full_authoring_snapshot_includes_clear_check_and_excludes_nothing_stage_id_related() -> void:
	var draft := _basic_draft()
	draft.add_skill(_valid_attack_skill("A"))
	draft.add_party_character("hero")
	var before := draft.full_authoring_snapshot()
	assert_true(before.has("boss_name"))
	assert_true(before.has("clear_check_success_snapshot"))
	assert_eq(before["clear_check_success_snapshot"], {}, "not yet cleared")
	assert_false(before.has("stage_id"), "stage_id is not authoring content (§18)")

	draft.normal_action_percentages[str(draft.skills[0]["skill_id"])] = 100.0
	draft.normal_actions_enabled = true
	var definition := draft.to_definition()
	var start := RBMDefinitionLoader.start_battle(definition, 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	if battle.winner == "ally":
		draft.record_clear_check_success()
	assert_true(draft.has_ever_cleared(), "sanity: this fixture actually wins")
	var after := draft.full_authoring_snapshot()
	assert_ne(after["clear_check_success_snapshot"], {}, "§16: a genuine Clear Check success must be visible on the authoring snapshot")
	assert_ne(after, before, "§16: Clear Check success alone changes full_authoring_snapshot() even with zero content edits")

## §17: is_playable()はRBMDefinitionLoader.resolve()の合否をそのまま反映する
## ライブ判定（キャッシュしない、§22）。
func test_is_playable_reflects_definition_validity_live() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = ""  # STEP1未完成 = party/skillsも空 = validation失敗
	assert_false(draft.is_playable())
	draft.boss_name = "テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill(_valid_attack_skill("A"))
	draft.add_party_character("hero")
	assert_true(draft.is_playable())
	draft.remove_party_character("hero")
	assert_false(draft.is_playable(), "live re-derivation: removing the only party member makes it unplayable again immediately")

## §10/§11: clear_check_snapshot_for_save()/restore_clear_check_snapshot()の
## 往復——空Dictionaryなら未クリアのまま、非空ならis_clear_check_currently_valid()
## がロード後も一致判定できることを確認する。
func test_clear_check_snapshot_round_trips_and_restores_valid_state() -> void:
	var draft := _basic_draft()
	var attack_id := draft.add_skill(_valid_attack_skill("A"))
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[attack_id] = 100.0
	draft.add_party_character("hero")
	var definition := draft.to_definition()
	var start := RBMDefinitionLoader.start_battle(definition, 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity")
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())

	var saved := draft.clear_check_snapshot_for_save()
	assert_ne(saved, {})

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(draft.to_saved_dict())
	restored.restore_clear_check_snapshot(saved)
	assert_true(restored.has_ever_cleared())
	assert_true(restored.is_clear_check_currently_valid(), "restored snapshot must equal a freshly-computed battle_content_snapshot() from the restored draft")

	restored.atk = 999
	assert_false(restored.is_clear_check_currently_valid(), "editing after restore still invalidates normally")
	restored.atk = draft.atk
	assert_true(restored.is_clear_check_currently_valid(), "and reverting still restores it (A->B->A survives a save/load round trip)")

func test_restore_clear_check_snapshot_with_empty_dict_means_never_cleared() -> void:
	var draft := _basic_draft()
	draft.restore_clear_check_snapshot({})
	assert_false(draft.has_ever_cleared())
	assert_false(draft.is_clear_check_currently_valid())

# ---------------------------------------------------------------------------
# Phase 1 Step 6 §12/§13/§50 — JSON数値型正規化: 実際にJSON.stringify()/
# JSON.parse_string()を経由させ、Godot 4.7の「JSONの数値は常にfloatで返る」
## という実機確認済みの挙動に対しrestore側が正しくintへ戻すことを確認する。
# ---------------------------------------------------------------------------

func test_json_round_trip_restores_int_fields_correctly() -> void:
	var draft := _fully_populated_draft()
	var saved := draft.to_saved_dict()
	var json_text := JSON.stringify(saved)
	var parsed: Variant = JSON.parse_string(json_text)
	assert_true(parsed is Dictionary)

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(parsed)

	assert_eq(typeof(restored.hp), TYPE_INT)
	assert_eq(typeof(restored.atk), TYPE_INT)
	assert_eq(typeof(restored.spd), TYPE_INT)
	assert_eq(restored.hp, draft.hp)
	assert_eq(restored.atk, draft.atk)
	assert_eq(restored.spd, draft.spd)

	for skill in restored.skills:
		match str(skill.get("type", "")):
			"self_heal":
				assert_eq(typeof(skill["heal_fixed_amount"]), TYPE_INT, "heal_fixed_amount must come back as int, not float, after a real JSON round trip")
			"atk_self_buff":
				assert_eq(typeof(skill["duration_turns"]), TYPE_INT, "duration_turns must come back as int")

	for entry in restored.scripted_actions:
		assert_eq(typeof(entry["turn"]), TYPE_INT, "scripted_actions turn must come back as int")

	# the whole point: with proper normalization, the restored Draft's own
	# to_saved_dict() must be byte-identical to a fresh in-memory one (Godot's
	# Dictionary == fails across an int/float type mismatch, per the Step 6
	# investigation's own empirical finding).
	assert_eq(restored.to_saved_dict(), draft.to_saved_dict())

func test_json_round_trip_keeps_float_fields_as_float_with_correct_values() -> void:
	var draft := _fully_populated_draft()
	var saved := draft.to_saved_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(parsed)

	for skill in restored.skills:
		match str(skill.get("type", "")):
			"attack":
				assert_eq(typeof(skill["atk_multiplier"]), TYPE_FLOAT)
				assert_almost_eq(float(skill["atk_multiplier"]), 2.5, 0.0001)
			"self_heal":
				assert_eq(typeof(skill["heal_percent"]), TYPE_FLOAT)
				assert_almost_eq(float(skill["heal_percent"]), 15.0, 0.0001)
			"atk_self_buff":
				assert_eq(typeof(skill["buff_multiplier"]), TYPE_FLOAT)
				assert_almost_eq(float(skill["buff_multiplier"]), 1.75, 0.0001)

	for skill_id in restored.normal_action_percentages.keys():
		assert_eq(typeof(restored.normal_action_percentages[skill_id]), TYPE_FLOAT)

## §12/§50: Clear Check snapshot側の数値も同様にJSON往復後intへ戻ること
## （hp/atk/spd/heal_amount/duration_turns/scripted turn・order）。
func test_json_round_trip_restores_clear_check_snapshot_int_fields_and_stays_valid() -> void:
	var draft := _basic_draft()
	var heal_id := draft.add_skill(_valid_self_heal_fixed("回復", 50))
	var buff_id := draft.add_skill(_valid_atk_self_buff("強化", 1.5, 2))
	draft.add_scripted_action(1, heal_id, "turn_start_interrupt")
	draft.add_scripted_action(1, buff_id, "turn_start_interrupt")
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid(), "sanity")

	var saved := draft.clear_check_snapshot_for_save()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(draft.to_saved_dict())
	restored.restore_clear_check_snapshot(parsed)

	# is_clear_check_currently_valid() compares battle_content_snapshot()
	# (freshly computed, always int/float per its own construction) against
	# the restored _clear_check_success_snapshot via Dictionary == -- if ANY
	# numeric field (hp/atk/spd/heal_amount/duration_turns/scripted turn or
	# order) had failed to normalize back to int, this comparison would fail
	# exactly as the Step 6 investigation's own empirical finding predicts.
	assert_true(restored.is_clear_check_currently_valid(), "after a real JSON round trip, the restored Clear Check snapshot must still equal a freshly-computed battle_content_snapshot()")

# ---------------------------------------------------------------------------
# Phase 1 Step 7 — 作者備考・情報公開設定 (§11〜§20/§43〜§46/§57)
# ---------------------------------------------------------------------------

func test_new_draft_has_empty_author_notes_and_all_visible_by_default() -> void:
	var draft := RBMCreatorDraft.new()
	assert_eq(draft.author_notes, "")
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(draft.is_challenge_info_visible(key), "key %s must default to public" % key)

## §11/§13: 200文字を超える入力はAPI自体が受け付けない（STEP 1のboss_name
## と同じ「切り詰めて保存する」設計）。
func test_set_author_notes_clamps_to_the_200_character_cap() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_author_notes("A".repeat(250))
	assert_eq(draft.author_notes.length(), RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH)

func test_set_author_notes_under_the_cap_is_kept_verbatim() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_author_notes("このボスは氷属性が弱点です")
	assert_eq(draft.author_notes, "このボスは氷属性が弱点です")

## §14: 個別トグル。
func test_set_challenge_info_visible_toggles_a_single_key_only() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_challenge_info_visible("hp", false)
	assert_false(draft.is_challenge_info_visible("hp"))
	assert_true(draft.is_challenge_info_visible("atk"), "toggling one key must not affect any other key")

func test_set_challenge_info_visible_ignores_an_unknown_key() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_challenge_info_visible("not_a_real_key", false)
	assert_false(draft.challenge_info_visibility.has("not_a_real_key"), "an unknown key must never be written into the Dictionary")

## §15: 一括切り替え。
func test_set_all_challenge_info_visible_toggles_every_key_at_once() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_all_challenge_info_visible(false)
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_false(draft.is_challenge_info_visible(key), "key %s must be false after すべて非公開" % key)
	draft.set_all_challenge_info_visible(true)
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(draft.is_challenge_info_visible(key), "key %s must be true after すべて公開" % key)

## §19: to_saved_dict()/restore_from_saved_dict()の往復で両フィールドとも
## 完全に一致すること。
func test_author_notes_and_visibility_round_trip_through_saved_dict() -> void:
	var draft := _basic_draft()
	draft.set_author_notes("挑戦前に必ずお読みください")
	draft.set_challenge_info_visible("hp", false)
	draft.set_challenge_info_visible("boss_skills", false)
	var saved := draft.to_saved_dict()

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_eq(restored.author_notes, "挑戦前に必ずお読みください")
	assert_false(restored.is_challenge_info_visible("hp"))
	assert_false(restored.is_challenge_info_visible("boss_skills"))
	assert_true(restored.is_challenge_info_visible("atk"))

## §19/§42: フィールド自体が存在しない旧stage（Step 7以前に保存されたもの）
## を復元しても、author_notes=""・すべて公開のデフォルトへ安全に
## フォールバックすること——クラッシュせず、下書きの未完成を壊さない。
func test_restoring_a_pre_step7_save_without_the_new_fields_defaults_to_empty_notes_and_all_visible() -> void:
	var draft := _basic_draft()
	var saved := draft.to_saved_dict()
	saved.erase("author_notes")
	saved.erase("challenge_info_visibility")

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_eq(restored.author_notes, "")
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(restored.is_challenge_info_visible(key))

## §19: JSON往復後もauthor_notesはString、challenge_info_visibilityの各値は
## Boolのまま——JSON.parse_string()がすべての数値をfloatへ変換する既知の
## 挙動とは無関係な文字列/真偽値フィールドだが、念のため実際のJSON経路で
## 確認する。
func test_author_notes_and_visibility_survive_a_real_json_round_trip() -> void:
	var draft := _basic_draft()
	draft.set_author_notes("備考テキスト")
	draft.set_challenge_info_visible("weak_attributes", false)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(draft.to_saved_dict()))

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(parsed)
	assert_eq(restored.author_notes, "備考テキスト")
	assert_false(restored.is_challenge_info_visible("weak_attributes"))
	assert_true(restored.is_challenge_info_visible("hp"))

## §43: 未保存変更判定の対象に含まれる——author_notes/visibilityの変更だけで
## has_unsaved_changesが検知できること（full_authoring_snapshot()自体は
## to_saved_dict()をそのまま含むため、この2フィールド専用の追加コードは
## 無いが、それを直接確認する）。
func test_full_authoring_snapshot_changes_when_author_notes_or_visibility_change() -> void:
	var draft := _basic_draft()
	var baseline := draft.full_authoring_snapshot()

	draft.set_author_notes("追記")
	assert_ne(draft.full_authoring_snapshot(), baseline, "editing author_notes alone must change the authoring snapshot")

	var draft2 := _basic_draft()
	var baseline2 := draft2.full_authoring_snapshot()
	draft2.set_challenge_info_visible("hp", false)
	assert_ne(draft2.full_authoring_snapshot(), baseline2, "editing visibility alone must change the authoring snapshot")

## §44: battle_content_snapshot()（Clear Check比較専用）には一切含まれない
## ——author_notes/visibilityをどう変更してもClear Check成功の有効性へ
## 影響しないこと。
func test_battle_content_snapshot_is_unaffected_by_author_notes_or_visibility() -> void:
	var draft := _basic_draft()
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid(), "sanity")

	draft.set_author_notes("この備考を変更してもClear Checkは無効化されない")
	assert_true(draft.is_clear_check_currently_valid(), "editing author_notes must never invalidate an existing Clear Check success")

	draft.set_all_challenge_info_visible(false)
	assert_true(draft.is_clear_check_currently_valid(), "editing visibility settings must never invalidate an existing Clear Check success")

# ---------------------------------------------------------------------------
# 公開設定の最終修正（7→6項目、「攻略側パーティ詳細」キー廃止）
# §8の10項目チェックリストに対応するテスト群
#
# 実機プレイ改善③ item1: "win_condition"/"special_condition"の追加により
# 6→8項目へ。以下のテストは全て、この意図的な項目数変更に合わせて期待値
# 6→8へ更新した（検証ロジック自体——「配列サイズとDictionaryサイズが一致
# すること」「hide/show allが全項目に効くこと」「保存/読込を往復しても
# 項目数が保たれること」「未知キーは無視されること」——は無改修のまま）。
# ---------------------------------------------------------------------------

## §8-1/実機プレイ改善③item1: 新規Draftの公開設定キーが8項目のみ。
func test_challenge_info_visibility_keys_has_exactly_eight_entries() -> void:
	assert_eq(RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS.size(), 8)
	var draft := RBMCreatorDraft.new()
	assert_eq(draft.challenge_info_visibility.size(), 8, "a fresh Draft's visibility Dictionary itself must also have exactly 8 entries")

## §8-2: 「攻略側パーティ詳細」キーが存在しない。
func test_challenge_info_visibility_keys_does_not_include_party_details() -> void:
	assert_false(RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS.has("party_details"))
	var draft := RBMCreatorDraft.new()
	assert_false(draft.challenge_info_visibility.has("party_details"))
	# §5: このキーはトグル対象からも完全に外れている——渡しても何も起きない
	# （既存のCHALLENGE_INFO_VISIBILITY_KEYS.has()ガードにより静かに無視される）。
	draft.set_challenge_info_visible("party_details", false)
	assert_false(draft.challenge_info_visibility.has("party_details"), "an unknown/removed key must never be written back in, even via an explicit call")

## §8-3/実機プレイ改善③item1・2: すべて公開で8項目true
## （win_condition/special_conditionもこの一括操作に含まれることを確認）。
func test_show_all_sets_all_eight_keys_true() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_all_challenge_info_visible(false)
	draft.set_all_challenge_info_visible(true)
	assert_eq(draft.challenge_info_visibility.size(), 8)
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(draft.is_challenge_info_visible(key), "key %s must be true after すべて公開" % key)

## §8-4/実機プレイ改善③item1・2: すべて非公開で8項目false。
func test_hide_all_sets_all_eight_keys_false() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_all_challenge_info_visible(false)
	assert_eq(draft.challenge_info_visibility.size(), 8)
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_false(draft.is_challenge_info_visible(key), "key %s must be false after すべて非公開" % key)

## §8-6: 保存→ロード後も8項目を維持。
func test_visibility_keeps_exactly_eight_entries_after_save_and_load_round_trip() -> void:
	var draft := _basic_draft()
	draft.set_challenge_info_visible("hp", false)
	var saved := draft.to_saved_dict()

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_eq(restored.challenge_info_visibility.size(), 8)
	assert_false(restored.challenge_info_visibility.has("party_details"))
	assert_false(restored.is_challenge_info_visible("hp"))
	assert_true(restored.is_challenge_info_visible("atk"))

## §8-7: 旧stage（公開設定フィールド自体が存在しない、または最終修正前の
## 「攻略側パーティ詳細」を含む旧7項目形式、または実機プレイ改善③以前の
## 6項目形式）は現行の8項目すべて公開へフォールバック——
## _restore_challenge_info_visibility()が既知キーだけを走査しCHALLENGE_INFO_
## VISIBILITY_KEYS.get(key, true)でデフォルト補完する既存の設計（新キー追加
## 時にも安全に効くとコメントされていた設計）が、今回のキー追加でも変更
## なしにそのまま機能することを確認する。
func test_pre_final_fix_seven_key_save_falls_back_to_eight_keys_all_visible() -> void:
	var draft := _basic_draft()
	var saved := draft.to_saved_dict()
	# 最終修正前（Step 7開発中）に生成されたデータを模す——手作業で
	# party_detailsキーを追加した7項目形式のDictionaryをJSON経由で復元する。
	var legacy_visibility: Dictionary = (saved["challenge_info_visibility"] as Dictionary).duplicate()
	legacy_visibility["party_details"] = false
	saved["challenge_info_visibility"] = legacy_visibility
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(parsed)
	assert_eq(restored.challenge_info_visibility.size(), 8, "the legacy party_details entry must be silently dropped, never counted")
	assert_false(restored.challenge_info_visibility.has("party_details"))
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(restored.is_challenge_info_visible(key), "key %s must default to public when restoring a legacy save" % key)

## 実機プレイ改善③ item1: 実機プレイ改善③より前（win_condition/special_
## conditionキー自体が存在しない）6項目形式の旧セーブも、新2項目が
## デフォルト公開へ正しく補完されることを確認する——これが今回の変更が
## 実際に後方互換であることの直接証拠。
func test_pre_item1_six_key_save_gets_new_two_keys_defaulted_to_visible() -> void:
	var draft := _basic_draft()
	var saved := draft.to_saved_dict()
	var legacy_visibility: Dictionary = (saved["challenge_info_visibility"] as Dictionary).duplicate()
	legacy_visibility.erase("win_condition")
	legacy_visibility.erase("special_condition")
	assert_eq(legacy_visibility.size(), 6, "sanity: this simulates a pre-item1 save with exactly the old 6 keys")
	saved["challenge_info_visibility"] = legacy_visibility
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))

	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(parsed)
	assert_eq(restored.challenge_info_visibility.size(), 8, "the 2 new keys must be added, defaulted to visible")
	assert_true(restored.is_challenge_info_visible("win_condition"))
	assert_true(restored.is_challenge_info_visible("special_condition"))

## §8-8/§8-9: 公開設定変更で未保存変更あり、元に戻す(A→B→A)と未保存変更なし
## ——full_authoring_snapshot()同士の比較でこの往復を直接確認する
## （has_unsaved_changes()自体はRBMCreatorMain側の責務だが、その判定ロジックは
## この同じsnapshot比較そのものなので、Draft単体でも直接検証できる）。
func test_toggling_visibility_then_reverting_restores_the_original_authoring_snapshot() -> void:
	var draft := _basic_draft()
	var baseline := draft.full_authoring_snapshot()

	draft.set_challenge_info_visible("hp", false)
	assert_ne(draft.full_authoring_snapshot(), baseline, "changing visibility must register as an unsaved change")

	draft.set_challenge_info_visible("hp", true)
	assert_eq(draft.full_authoring_snapshot(), baseline, "reverting visibility back to its original value must restore no-unsaved-changes")

# ---------------------------------------------------------------------------
# Codex最終レビュー指摘対応 — 作者備考TextEdit・公開設定CheckBoxの実UIテスト
# ---------------------------------------------------------------------------
##
## 実機検証（scratch probe）で確認した事実: TextEdit.text_changedシグナルは
## ①ノードがSceneTreeへ実際に加わっており、②少なくとも1フレーム
## （内部のTextServer/フォント遅延初期化のため）経過した後でなければ、
## insert_text_at_caret()を呼んでも発火しない。`.text = "..."`という直接代入
## はSceneTree加入・フレーム経過の有無に関わらず一度もtext_changedを
## 発火しないことも確認済み——そのため以下のテストはinsert_text_at_caret()
## （実際のキーストローク処理が内部で呼ぶのと同じAPI）だけを使い、必ず
## add_child_autofree()でツリーへ加えたうえで最低2フレームawaitしてから
## 操作する。CheckBox.button_pressedへの直接代入・Button.pressed.emit()は
## いずれもフレーム待機なしで即座に実signalを発火することも同じprobeで
## 確認済み（Godot BaseButtonの標準実装がtoggle_mode時に自動発火する）。

func _new_creator_for_ui_test() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.go_to_step(5)
	return creator

func _step7_view(creator: RBMCreatorMain) -> RBMCreatorStep7Summary:
	return creator._step_views[4]

## §2: 実際のSTEP7 TextEditへ、実際の入力経路(insert_text_at_caret())で
## 201文字を「入力」し、text_changedシグナル→ハンドラ→Draftという実経路を
## 通す。draft.set_author_notes()を直接呼ぶだけでは検証しない。
func test_author_notes_real_typing_via_text_edit_clamps_to_200_and_reaches_draft() -> void:
	var creator := _new_creator_for_ui_test()
	await get_tree().process_frame
	await get_tree().process_frame
	var step7 := _step7_view(creator)
	var edit: TextEdit = step7._author_notes_edit
	edit.insert_text_at_caret("あ".repeat(201))
	await get_tree().process_frame

	assert_eq(edit.text.length(), 200, "the TextEdit widget itself must never display more than 200 characters after real typing")
	assert_eq(creator.draft.author_notes.length(), 200, "the real text_changed signal path must reach draft.author_notes")
	assert_eq(creator.draft.author_notes, edit.text, "the TextEdit and the Draft must show the exact same (clamped) content")
	assert_eq(step7._author_notes_count_label.text, "200 / %d 文字" % RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH)

## §3: 実UI由来の200文字が保存JSONへ到達すること（最低限必須）。より強い
## 確認として、別のCreatorへロードし直しDraft値・STEP7 TextEdit表示の両方に
## 200文字が復元されることも確認する。
func test_author_notes_real_typing_value_reaches_the_saved_json_and_survives_reload() -> void:
	var creator := _new_creator_for_ui_test()
	await get_tree().process_frame
	await get_tree().process_frame
	var step7 := _step7_view(creator)
	creator.draft.boss_name = "備考UI保存テスト"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")
	var edit: TextEdit = step7._author_notes_edit
	edit.insert_text_at_caret("い".repeat(201))
	await get_tree().process_frame
	assert_eq(creator.draft.author_notes.length(), 200, "sanity")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)), "sanity")
	var stage_id := str(result.get("stage_id", ""))

	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	var loaded_draft := RBMCreatorDraft.new()
	loaded_draft.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(loaded_draft.author_notes.length(), 200, "the real-UI-origin 200-char notes must reach the saved JSON")
	assert_eq(loaded_draft.author_notes, edit.text)

	var creator2 := RBMCreatorMain.new()
	add_child_autofree(creator2)
	var load_result := creator2.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	creator2.go_to_step(6)
	await get_tree().process_frame
	assert_eq(creator2.draft.author_notes.length(), 200)
	var step7_reloaded := _step7_view(creator2)
	assert_eq(step7_reloaded._author_notes_edit.text.length(), 200, "reloading must restore the 200-char notes into the STEP7 TextEdit display too")

## §4/実機プレイ改善③item1: 実際の8つのCheckBox（win_condition/
## special_condition追加後）を、Godotのtoggle_mode Buttonが実際に発火する
## button_pressedプロパティ経由の実signalで操作する。
func test_all_eight_visibility_checkboxes_are_wired_to_the_draft_via_real_toggled_signal() -> void:
	var creator := _new_creator_for_ui_test()
	var step7 := _step7_view(creator)
	assert_eq(step7._visibility_checkboxes.size(), 8, "sanity: exactly 8 checkboxes must be constructed")
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(step7._visibility_checkboxes.has(key), "a checkbox for key %s must exist" % key)
		var checkbox: CheckBox = step7._visibility_checkboxes[key]
		assert_true(checkbox.button_pressed, "sanity: starts public")
		checkbox.button_pressed = false
		assert_false(creator.draft.is_challenge_info_visible(key), "toggling the real CheckBox for %s must reach the Draft via its own toggled signal" % key)

## §4: 代表2件について、button_pressedへの代入が実際にGodotの本物のSignal
## ディスパッチ機構を経由していることを、get_connections()で実際の接続一覧
## を確認する形でさらに強く検証する。
func test_hp_and_boss_skills_checkboxes_have_a_real_toggled_connection() -> void:
	var creator := _new_creator_for_ui_test()
	var step7 := _step7_view(creator)
	for key in ["hp", "boss_skills"]:
		var checkbox: CheckBox = step7._visibility_checkboxes[key]
		var connections := checkbox.toggled.get_connections()
		assert_gt(connections.size(), 0, "checkbox for %s must have at least one real toggled connection" % key)

## §5: 実際の「すべて非公開」ボタンをButton.pressedシグナル経由で操作する。
func test_hide_all_button_real_press_turns_off_all_six_checkboxes_and_draft_keys() -> void:
	var creator := _new_creator_for_ui_test()
	var step7 := _step7_view(creator)
	var hide_all_button: Button = step7.find_child("HideAllVisibilityButton", true, false)
	assert_not_null(hide_all_button, "sanity")
	hide_all_button.pressed.emit()

	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_false(creator.draft.is_challenge_info_visible(key), "Draft key %s must be false after a real すべて非公開 press" % key)
		var checkbox: CheckBox = step7._visibility_checkboxes[key]
		assert_false(checkbox.button_pressed, "CheckBox UI for %s must stay in sync (unchecked) after a real すべて非公開 press" % key)

## §6: 実際の「すべて公開」ボタン。一括ボタン押下後、CheckBox UI自体が
## draftへ同期していることも確認する。
func test_show_all_button_real_press_after_hide_all_turns_on_all_six_checkboxes_and_draft_keys() -> void:
	var creator := _new_creator_for_ui_test()
	var step7 := _step7_view(creator)
	var hide_all_button: Button = step7.find_child("HideAllVisibilityButton", true, false)
	var show_all_button: Button = step7.find_child("ShowAllVisibilityButton", true, false)
	hide_all_button.pressed.emit()
	show_all_button.pressed.emit()

	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		assert_true(creator.draft.is_challenge_info_visible(key), "Draft key %s must be true after real すべて非公開→すべて公開" % key)
		var checkbox: CheckBox = step7._visibility_checkboxes[key]
		assert_true(checkbox.button_pressed, "CheckBox UI for %s must stay in sync (checked)" % key)
