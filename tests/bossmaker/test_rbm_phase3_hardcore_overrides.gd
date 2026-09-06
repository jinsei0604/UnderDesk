extends GutTest

## Phase 3 Step 1-3: player-facing HARDCORE naming, sparse per-stage ally
## overrides, unified SP, save v2, Clear Check and real-battle integration.

const TEST_DIR := "user://bossmaker_test_phase3_hardcore/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _draft(mode: String = RBMCreatorDraft.CREATOR_MODE_ADVANCED) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "Phase3検証ボス"
	draft.hp = 1000000
	draft.atk = 1
	draft.spd = 1
	draft.add_skill({"name": "待機攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.0})
	draft.add_party_character("hero")
	draft.set_creator_mode(mode)
	return draft

func _skill(definition: Dictionary, skill_id: String) -> Dictionary:
	for skill_variant in definition.get("skills", []):
		if skill_variant is Dictionary and str((skill_variant as Dictionary).get("id", "")) == skill_id:
			return skill_variant
	return {}

func _party_entry(definition: Dictionary, character_id: String) -> Dictionary:
	for entry_variant in definition.get("party", []):
		if entry_variant is Dictionary and str((entry_variant as Dictionary).get("character_id", "")) == character_id:
			return entry_variant
	return {}

func _find_log(log: Array, actor_id: int, skill_id: String) -> Dictionary:
	for entry_variant in log:
		if entry_variant is Dictionary:
			var entry: Dictionary = entry_variant
			if int(entry.get("actor", -999)) == actor_id and str(entry.get("skill_id", "")) == skill_id:
				return entry
	return {}

func _write_payload(stage_id: String, payload: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEST_DIR, stage_id], FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

func _valid_value_for(field: String) -> Variant:
	match field:
		"atk_multiplier": return 9.25
		"buff_multiplier": return 3.50
		"new_rate", "reduction_rate": return 0.77
		"duration_turns": return 9
		"heal_amount": return 456
		"sp_amount": return 77
		"sp_cost": return 123
	return 0

func test_player_facing_name_is_hardcore_while_internal_identifier_stays_advanced() -> void:
	var entry := RBMCreatorEntry.new()
	add_child_autofree(entry)
	await get_tree().process_frame
	# Phase 3.5 UI統一 正式アート実装: 「作成方法を選択」画面の重い構築
	# （背景画像＋案内役キャラクター）は、実際にこの画面へ到達するまで遅延
	# する（RBMCreatorEntry._ensure_mode_choice_content_built()参照、§24と
	# 同じ精神——bossmakerテストスイート全体でこの画面を一度も開かない
	# テストにまで一律コストを乗せないための判断）。このテスト自身は実際の
	# プレイヤー導線と同じく「新しいボス戦を作る」を押してから確認する。
	entry.find_child("NewBossButton", true, false).pressed.emit()
	await get_tree().process_frame
	var choose := entry.find_child("ChooseAdvancedModeButton", true, false) as Button
	assert_not_null(choose)
	# Creator本体UI刷新に先立つ「作成方法選択」画面の正式アート実装
	# （RBMCreatorEntry._configure_method_card()）で、SIMPLE/HARDCOREの
	# カードは唐草装飾つきの独自描画Surface（ModeChoicePanelSurface）へ
	# 移行し、button.text自体は意図的に空文字へ（Buttonの既定描画に頼らず
	# カード内の子Labelへ描画を委譲するため）。実際にプレイヤーへ表示される
	# タイトルは子Label"TitleLabel"が持つ（button.tooltip_textも同じ値へ
	# 揃えてあるが、常時可視の本体はこちらのLabel）——この経路を直接確認する。
	var choose_title_label := choose.find_child("TitleLabel", true, false) as Label
	assert_not_null(choose_title_label, "ChooseAdvancedModeButtonは子LabelでタイトルをレンダリングするButton.textは意図的に空にしてある")
	assert_eq(choose_title_label.text, "ハードコアで作る")
	assert_eq(RBMCreatorDraft.CREATOR_MODE_ADVANCED, "advanced")

	var summary := RBMCreatorStep7Summary.new()
	add_child_autofree(summary)
	var draft := _draft()
	summary.setup(draft, null)
	summary.refresh()
	## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§23-A: 作成モード
	## （SIMPLE/HARDCORE）切替UIは最終確認画面から削除された——切替ロジック
	## 自体（RBMCreatorDraft.set_creator_mode()等）はDraft側に無改修のまま
	## 残置、この画面からのUI導線だけが無くなったことを確認する。
	assert_null(summary.find_child("SwitchToSimpleModeButton", true, false), "作成モード切替UIは最終確認画面から削除されていること")
	assert_null(summary.find_child("SwitchToAdvancedModeButton", true, false))
	assert_null(summary.find_child("CreatorModeLabel", true, false))
	# 「HARDCORE」は作成方法選択画面のカード意匠（SIMPLE/HARDCOREの英語
	# カテゴリラベル、_configure_method_card()の"category"引数、node名
	# "CategoryLabel"）として意図的に表示される正式な仕様——ここだけを
	# スキャンから除外する（_all_control_texts()の`exclude_names`）。それ
	# 以外の場所（STEP7の作成モード表示等）に"HARDCORE"が漏れていないかは
	# 引き続きこのテストで検出する——「テストを緩くする」のではなく、
	# 既知の1箇所だけを正確に除外する形にした。禁止すべき内部識別子の生
	# 表記（"ADVANCED"の英語表記・「アドバンスド」のカタカナ表記）は
	# どの画面にも実際に登場しない（実装側もgrep済み）。
	var player_text := " ".join(
		_all_control_texts(entry, ["CategoryLabel"]) + _all_control_texts(summary, ["CategoryLabel"])
	)
	for forbidden in ["HARDCORE", "ADVANCED", "アドバンスド"]:
		assert_false(player_text.contains(forbidden), "プレイヤー向け表記に%sを残さない" % forbidden)

func _all_label_texts(node: Node, exclude_names: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	for label_variant in node.find_children("*", "Label", true, false):
		var label := label_variant as Label
		if exclude_names.has(label.name):
			continue
		out.append(label.text)
	return out

func _all_control_texts(node: Node, exclude_names: Array[String] = []) -> Array[String]:
	var out := _all_label_texts(node, exclude_names)
	for button_variant in node.find_children("*", "Button", true, false):
		var button := button_variant as Button
		if exclude_names.has(button.name):
			continue
		out.append(button.text)
	return out

func test_sparse_overrides_store_only_differences_and_master_equal_values_prune() -> void:
	var draft := _draft()
	assert_true(draft.set_ally_stat_override("hero", "hp", 777))
	assert_true(draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0))
	assert_eq(draft.ally_overrides["hero"]["stats"], {"hp": 777})
	assert_eq(draft.ally_overrides["hero"]["skills"]["hero_slash"], {"atk_multiplier": 5.0})

	var master := draft.master_character_def("hero")
	assert_true(draft.set_ally_stat_override("hero", "hp", master["hp"]))
	assert_true(draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", _skill(master, "hero_slash")["atk_multiplier"]))
	assert_false(draft.ally_overrides.has("hero"), "master-equal values must not be serialized as redundant overrides")

func test_all_master_skill_effects_accept_only_their_existing_whitelisted_numeric_fields() -> void:
	var draft := _draft()
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		if not draft.party_character_ids.has(character_id):
			draft.add_party_character(character_id)
		var master := draft.master_character_def(character_id)
		for skill_variant in master.get("skills", []):
			var master_skill: Dictionary = skill_variant
			var skill_id := str(master_skill["id"])
			var fields := RBMDefinitionLoader.ally_skill_override_fields(master_skill)
			assert_gt(fields.size(), 0, "%s must expose its real numeric fields" % skill_id)
			for field in fields:
				assert_true(draft.set_ally_skill_override(character_id, skill_id, field, _valid_value_for(field)), "%s.%s" % [skill_id, field])
		assert_false(draft.set_ally_skill_override(character_id, str((master["skills"][0] as Dictionary)["id"]), "invented_field", 1))

	var resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(resolved.get("ok", false)), str(resolved.get("errors", [])))
	for ally_variant in resolved.get("ally_defs", []):
		var ally: Dictionary = ally_variant
		var character_id := str(ally["id"])
		for skill_variant in ally.get("skills", []):
			var skill: Dictionary = skill_variant
			for field in RBMDefinitionLoader.ally_skill_override_fields(skill):
				assert_eq(skill[field], _valid_value_for(field), "%s.%s must reach DefinitionLoader" % [str(skill["id"]), field])

func test_override_ranges_reject_nan_inf_fractional_integers_and_out_of_range_values() -> void:
	var draft := _draft()
	assert_false(draft.set_ally_stat_override("hero", "hp", 0))
	assert_false(draft.set_ally_stat_override("hero", "hp", 1.5))
	assert_false(draft.set_ally_stat_override("hero", "hp", RBMDefinitionLoader.ALLY_OVERRIDE_INT_MAX + 1))
	assert_false(draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", NAN))
	assert_false(draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", INF))
	assert_false(draft.set_ally_skill_override("hero", "hero_slash", "sp_cost", 1.5))
	assert_false(draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 1000.01))
	assert_false(draft.set_ally_skill_override("tank", "tank_guard_boost", "new_rate", 1.01))
	assert_true(draft.ally_overrides.is_empty())

func test_every_override_range_accepts_its_exact_lower_and_upper_bound() -> void:
	for field in RBMDefinitionLoader.ALLY_STAT_OVERRIDE_FIELDS:
		assert_true(RBMDefinitionLoader.validate_ally_stat_override_value(field, 1), "%s lower" % field)
		assert_true(RBMDefinitionLoader.validate_ally_stat_override_value(field, 1000000000), "%s upper" % field)
		assert_false(RBMDefinitionLoader.validate_ally_stat_override_value(field, 0), "%s below" % field)
		assert_false(RBMDefinitionLoader.validate_ally_stat_override_value(field, 1000000001), "%s above" % field)
	for field in ["heal_amount", "sp_amount", "sp_cost"]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 0), "%s lower" % field)
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1000000000), "%s upper" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, -1), "%s below" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1000000001), "%s above" % field)
	assert_true(RBMDefinitionLoader.validate_ally_skill_override_value("duration_turns", 1))
	assert_true(RBMDefinitionLoader.validate_ally_skill_override_value("duration_turns", 1000000000))
	assert_false(RBMDefinitionLoader.validate_ally_skill_override_value("duration_turns", 0))
	assert_false(RBMDefinitionLoader.validate_ally_skill_override_value("duration_turns", 1000000001))
	for field in ["atk_multiplier", "buff_multiplier"]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 0.0), "%s lower" % field)
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1000.0), "%s upper" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, -0.01), "%s below" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1000.01), "%s above" % field)
	for field in ["new_rate", "reduction_rate"]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 0.0), "%s lower" % field)
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1.0), "%s upper" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, -0.01), "%s below" % field)
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value(field, 1.01), "%s above" % field)

func test_definition_loader_rejects_malformed_or_unknown_override_content() -> void:
	var draft := _draft()
	var definition := draft.to_definition()
	var party: Dictionary = definition["party"][0]
	party["stat_overrides"] = {"hp": 1.5}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)))
	party["stat_overrides"] = {"hp": 100, "unknown": 2}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)))
	party.erase("stat_overrides")
	party["skill_overrides"] = {"unknown_skill": {"sp_cost": 1}}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)))
	party["skill_overrides"] = {"hero_slash": {"heal_amount": 1}}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)))
	for forbidden_field in ["effect", "attribute", "target", "id"]:
		var forbidden_values := {}
		forbidden_values[forbidden_field] = 1
		party["skill_overrides"] = {"hero_slash": forbidden_values}
		assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)), "%s cannot be overridden" % forbidden_field)
	var errors: Array[String] = []
	assert_false(RBMDefinitionLoader.validate_ally_overrides({"unknown_character": {"stats": {"hp": 10}}}, errors))

func test_simple_ignores_retained_overrides_and_hardcore_reapplies_them() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "atk", 100)
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0)
	var hardcore_entry := _party_entry(draft.to_definition(), "hero")
	assert_eq(hardcore_entry["stat_overrides"], {"atk": 100})
	assert_eq(hardcore_entry["skill_overrides"]["hero_slash"], {"atk_multiplier": 5.0})

	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	var simple_entry := _party_entry(draft.to_definition(), "hero")
	assert_false(simple_entry.has("stat_overrides"))
	assert_false(simple_entry.has("skill_overrides"))
	assert_true(draft.ally_overrides.has("hero"), "SIMPLE retains authoring data")
	var simple_resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_eq(int((simple_resolved["ally_defs"][0] as Dictionary)["atk"]), 240, "retained values must not leak into SIMPLE battle")

	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var hardcore_resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_eq(int((hardcore_resolved["ally_defs"][0] as Dictionary)["atk"]), 100)
	assert_eq(float(_skill(hardcore_resolved["ally_defs"][0], "hero_slash")["atk_multiplier"]), 5.0)

func test_step6_adjusted_master_values_feed_simple_and_hardcore_defaults_while_explicit_overrides_win() -> void:
	var draft := _draft()
	draft.add_party_character("butler")
	draft.add_party_character("samurai")

	var hardcore_default := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(hardcore_default.get("ok", false)), str(hardcore_default.get("errors", [])))
	assert_eq(float(_skill(hardcore_default["ally_defs"][0], "hero_flame_wrap")["buff_multiplier"]), 1.75)
	assert_eq(float(_skill(hardcore_default["ally_defs"][1], "butler_ice_storm")["atk_multiplier"]), 2.8)
	assert_eq(float(_skill(hardcore_default["ally_defs"][2], "samurai_iai")["buff_multiplier"]), 2.5)

	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	var simple := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(simple.get("ok", false)), str(simple.get("errors", [])))
	assert_eq(float(_skill(simple["ally_defs"][0], "hero_flame_wrap")["buff_multiplier"]), 1.75)
	assert_eq(float(_skill(simple["ally_defs"][1], "butler_ice_storm")["atk_multiplier"]), 2.8)
	assert_eq(float(_skill(simple["ally_defs"][2], "samurai_iai")["buff_multiplier"]), 2.5)

	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_true(draft.set_ally_skill_override("hero", "hero_flame_wrap", "buff_multiplier", 1.25))
	assert_true(draft.set_ally_skill_override("butler", "butler_ice_storm", "atk_multiplier", 3.25))
	assert_true(draft.set_ally_skill_override("samurai", "samurai_iai", "buff_multiplier", 3.5))
	var overridden := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(overridden.get("ok", false)), str(overridden.get("errors", [])))
	assert_eq(float(_skill(overridden["ally_defs"][0], "hero_flame_wrap")["buff_multiplier"]), 1.25)
	assert_eq(float(_skill(overridden["ally_defs"][1], "butler_ice_storm")["atk_multiplier"]), 3.25)
	assert_eq(float(_skill(overridden["ally_defs"][2], "samurai_iai")["buff_multiplier"]), 3.5)

func test_step6_clear_check_snapshot_tracks_effective_master_values_and_explicit_old_value_overrides() -> void:
	var draft := _draft()
	draft.add_party_character("butler")
	draft.add_party_character("samurai")
	var current_snapshot := draft.battle_content_snapshot()
	assert_eq(float(_party_entry(current_snapshot, "hero")["skill_values"]["hero_flame_wrap"]["buff_multiplier"]), 1.75)
	assert_eq(float(_party_entry(current_snapshot, "butler")["skill_values"]["butler_ice_storm"]["atk_multiplier"]), 2.8)
	assert_eq(float(_party_entry(current_snapshot, "samurai")["skill_values"]["samurai_iai"]["buff_multiplier"]), 2.5)
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())

	var pre_adjustment_snapshot := current_snapshot.duplicate(true)
	_party_entry(pre_adjustment_snapshot, "hero")["skill_values"]["hero_flame_wrap"]["buff_multiplier"] = 1.5
	_party_entry(pre_adjustment_snapshot, "butler")["skill_values"]["butler_ice_storm"]["atk_multiplier"] = 2.0
	_party_entry(pre_adjustment_snapshot, "samurai")["skill_values"]["samurai_iai"]["buff_multiplier"] = 2.0
	draft.restore_clear_check_snapshot(pre_adjustment_snapshot)
	assert_false(draft.is_clear_check_currently_valid(), "an old Clear Check must not certify the newly adjusted effective master values")

	assert_true(draft.set_ally_skill_override("hero", "hero_flame_wrap", "buff_multiplier", 1.5))
	assert_true(draft.set_ally_skill_override("butler", "butler_ice_storm", "atk_multiplier", 2.0))
	assert_true(draft.set_ally_skill_override("samurai", "samurai_iai", "buff_multiplier", 2.0))
	assert_true(draft.is_clear_check_currently_valid(), "explicit HARDCORE overrides that preserve all old effective values must preserve the matching old Clear Check")
	draft.reset_all_ally_overrides()
	assert_false(draft.is_clear_check_currently_valid(), "removing those overrides returns to the adjusted masters and invalidates the old snapshot")

func test_removing_character_or_disabling_skill_retains_override_authoring_data() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "hp", 777)
	draft.set_ally_skill_override("hero", "hero_slash", "sp_cost", 99)
	draft.set_ally_skill_allowed("hero", "hero_slash", false)
	assert_eq(int(draft.ally_overrides["hero"]["skills"]["hero_slash"]["sp_cost"]), 99)
	draft.remove_party_character("hero")
	assert_eq(int(draft.ally_overrides["hero"]["stats"]["hp"]), 777)
	draft.add_party_character("hero")
	assert_false(draft.is_ally_skill_allowed("hero", "hero_slash"), "re-adding must preserve the prior enabled/disabled selection")
	assert_eq(int(draft.ally_overrides["hero"]["skills"]["hero_slash"]["sp_cost"]), 99)

func test_three_reset_scopes_remove_only_the_requested_sparse_data() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "hp", 777)
	draft.set_ally_skill_override("hero", "hero_slash", "sp_cost", 99)
	draft.set_ally_skill_override("hero", "hero_burst_slash", "atk_multiplier", 8.0)
	draft.reset_ally_character_stats("hero")
	assert_false((draft.ally_overrides["hero"] as Dictionary).has("stats"))
	assert_true((draft.ally_overrides["hero"] as Dictionary).has("skills"))
	draft.reset_ally_skill("hero", "hero_slash")
	assert_false((draft.ally_overrides["hero"]["skills"] as Dictionary).has("hero_slash"))
	assert_true((draft.ally_overrides["hero"]["skills"] as Dictionary).has("hero_burst_slash"))
	draft.reset_all_ally_overrides()
	assert_true(draft.ally_overrides.is_empty())

func test_loader_applies_to_a_deep_copy_without_mutating_master_data() -> void:
	var draft := _draft()
	var before := draft.master_character_def("hero")
	draft.set_ally_stat_override("hero", "atk", 999)
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 7.0)
	var resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	assert_true(bool(resolved.get("ok", false)))
	assert_eq(int((resolved["ally_defs"][0] as Dictionary)["atk"]), 999)
	var after := draft.master_character_def("hero")
	assert_eq(after, before, "per-stage resolution must never mutate the fixed master Dictionary")
	assert_eq(int(after["atk"]), 240)
	assert_eq(float(_skill(after, "hero_slash")["atk_multiplier"]), 1.5)

func test_real_battle_uses_custom_atk_multiplier_and_tank_custom_sp_cost() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "atk", 100)
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0)
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	assert_true(bool(start.get("ok", false)))
	var battle: RBMBattle = start["battle"]
	var log := battle.resolve_turn({"0": {"type": "skill", "skill_id": "hero_slash"}})["log"] as Array
	assert_eq(int(_find_log(log, 0, "hero_slash")["amount"]), 500, "100 × 5.0 × neutral factors must be used by real battle")

	var tank_draft := _draft()
	tank_draft.remove_party_character("hero")
	tank_draft.add_party_character("tank")
	tank_draft.set_ally_skill_override("tank", "tank_smash", "sp_cost", 30)
	var tank_start := RBMDefinitionLoader.start_battle(tank_draft.to_definition(), 1)
	var tank_battle: RBMBattle = tank_start["battle"]
	assert_eq(tank_battle.party[0].max_sp, 100)
	tank_battle.resolve_turn({"0": {"type": "skill", "skill_id": "tank_smash"}})
	assert_eq(tank_battle.party[0].sp, 70, "tank uses the normal SP-cost path after max_sp unification")

func test_equal_ally_spd_uses_party_order_and_clear_check_tracks_that_order() -> void:
	var draft := _draft()
	draft.add_party_character("tank")
	draft.set_ally_stat_override("hero", "spd", 500)
	draft.set_ally_stat_override("tank", "spd", 500)
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	assert_eq((start["battle"] as RBMBattle).turn_order.slice(0, 2), ["ally:0", "ally:1"])
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	draft.party_character_ids = ["tank", "hero"]
	assert_false(draft.is_clear_check_currently_valid(), "party order changes the equal-SPD tie-break and must invalidate")
	var reordered := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	assert_eq(str((reordered["battle"] as RBMBattle).party[0].display_name), "無属性・巨大な筋肉のハンマー使い")

func test_clear_check_snapshot_contains_order_stats_allowed_skills_and_effective_values() -> void:
	var draft := _draft()
	draft.add_party_character("tank")
	draft.set_ally_stat_override("hero", "hp", 777)
	draft.set_ally_stat_override("hero", "max_sp", 333)
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0)
	draft.set_ally_skill_allowed("hero", "hero_burst_slash", false)
	var snapshot := draft.battle_content_snapshot()
	assert_true(snapshot["party"] is Array)
	assert_eq(str(snapshot["party"][0]["character_id"]), "hero")
	assert_eq(str(snapshot["party"][1]["character_id"]), "tank")
	assert_eq(int(snapshot["party"][0]["hp"]), 777)
	assert_eq(int(snapshot["party"][0]["max_sp"]), 333)
	assert_eq(float(snapshot["party"][0]["skill_values"]["hero_slash"]["atk_multiplier"]), 5.0)
	assert_false((snapshot["party"][0]["allowed_skill_ids"] as Array).has("hero_burst_slash"))
	assert_false((snapshot["party"][0]["skill_values"] as Dictionary).has("hero_burst_slash"))
	draft.record_clear_check_success()
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.5)
	assert_false(draft.is_clear_check_currently_valid())
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0)
	assert_true(draft.is_clear_check_currently_valid())

func test_save_v2_round_trip_preserves_sparse_overrides_and_v1_loads_without_them() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "atk", 999)
	draft.set_ally_skill_override("hero", "hero_slash", "sp_cost", 88)
	draft.record_clear_check_success()
	var saved := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(saved.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(saved["stage_id"]))
	assert_eq(int(loaded["save_format_version"]), 2)
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded["draft_data"])
	restored.restore_clear_check_snapshot(loaded["clear_check_data"])
	assert_eq(restored.ally_overrides, draft.ally_overrides)
	assert_true(restored.is_clear_check_currently_valid())

	var legacy_draft := draft.to_saved_dict()
	legacy_draft.erase("ally_overrides")
	var legacy_id := "3111111111"
	_write_payload(legacy_id, {
		"save_format_version": 1, "stage_id": legacy_id,
		"created_unix_time": 1, "updated_unix_time": 1,
		"draft": legacy_draft, "clear_check_success_snapshot": {},
	})
	var legacy := RBMLocalStageRepository.load_stage(legacy_id)
	assert_true(bool(legacy.get("ok", false)), "v1 files remain readable")
	var migrated := RBMCreatorDraft.new()
	migrated.restore_from_saved_dict(legacy["draft_data"])
	assert_true(migrated.ally_overrides.is_empty(), "v1 has no override data")

func test_v1_cannot_smuggle_ally_overrides_and_always_uses_master_values() -> void:
	var draft := _draft()
	var legacy_data := draft.to_saved_dict()
	legacy_data["ally_overrides"] = {"hero": {"stats": {"atk": 999}}}
	var stage_id := "3444444444"
	_write_payload(stage_id, {
		"save_format_version": 1, "stage_id": stage_id,
		"created_unix_time": 1, "updated_unix_time": 1,
		"draft": legacy_data, "clear_check_success_snapshot": {},
	})
	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(loaded.get("ok", false)))
	assert_false((loaded["draft_data"] as Dictionary).has("ally_overrides"))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded["draft_data"])
	var resolved := RBMDefinitionLoader.resolve(restored.to_definition())
	assert_eq(int((resolved["ally_defs"][0] as Dictionary)["atk"]), 240)

func test_full_save_load_test_clear_and_challenge_pipeline_keeps_all_effective_ally_data() -> void:
	var draft := _draft()
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		if not draft.party_character_ids.has(character_id) and draft.party_character_ids.size() < RBMDefinitionLoader.MAX_PARTY_SIZE:
			draft.add_party_character(character_id)
	for index in range(draft.party_character_ids.size()):
		var character_id: String = draft.party_character_ids[index]
		draft.set_ally_stat_override(character_id, "hp", 700 + index)
		draft.set_ally_stat_override(character_id, "atk", 300 + index)
		draft.set_ally_stat_override(character_id, "spd", 200 + index)
		draft.set_ally_stat_override(character_id, "max_sp", 400 + index)
		var master := draft.master_character_def(character_id)
		for skill_variant in master.get("skills", []):
			var master_skill: Dictionary = skill_variant
			for field in RBMDefinitionLoader.ally_skill_override_fields(master_skill):
				draft.set_ally_skill_override(character_id, str(master_skill["id"]), field, _valid_value_for(field))
	# Keep one concrete allowed-skill difference in the same end-to-end payload.
	draft.set_ally_skill_allowed("hero", "hero_burst_slash", false)
	draft.record_clear_check_success()
	var original_definition := draft.to_definition()
	var save := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(save.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(save["stage_id"]))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded["draft_data"])
	restored.restore_clear_check_snapshot(loaded["clear_check_data"])
	assert_true(restored.is_clear_check_currently_valid())
	assert_eq(restored.to_definition(), original_definition, "Creator → Clear Check → Save → Load must preserve every effective value and party order")

	var test_session := RBMCreatorTestSession.new(restored.to_definition(), 123)
	var clear_check_session := RBMCreatorTestSession.new(restored.to_definition(), 123)
	var challenge_session := RBMChallengeSession.new(restored.to_definition(), 123)
	assert_true(test_session.start_ok())
	assert_true(clear_check_session.start_ok())
	assert_true(challenge_session.start_ok())
	assert_eq(test_session.battle.snapshot()["units"], clear_check_session.battle.snapshot()["units"])
	assert_eq(test_session.battle.snapshot()["units"], challenge_session.battle.snapshot()["units"])
	for index in range(test_session.battle.party.size()):
		var test_unit: RBMUnit = test_session.battle.party[index]
		var challenge_unit: RBMUnit = challenge_session.battle.party[index]
		assert_eq(test_unit.max_hp, challenge_unit.max_hp)
		assert_eq(test_unit.atk, challenge_unit.atk)
		assert_eq(test_unit.spd, challenge_unit.spd)
		assert_eq(test_unit.max_sp, challenge_unit.max_sp)
		assert_eq(test_unit.sp, challenge_unit.sp)
		assert_eq(test_unit.skills, challenge_unit.skills)

func test_v2_strict_load_rejects_missing_unknown_and_invalid_override_fields() -> void:
	var draft := _draft()
	var stage_id := "3222222222"
	var payload := {
		"save_format_version": 2, "stage_id": stage_id,
		"created_unix_time": 1, "updated_unix_time": 1,
		"draft": draft.to_saved_dict(), "clear_check_success_snapshot": {},
	}
	payload["draft"].erase("ally_overrides")
	_write_payload(stage_id, payload)
	assert_false(bool(RBMLocalStageRepository.load_stage(stage_id).get("ok", true)))

	payload["draft"]["ally_overrides"] = {"hero": {"stats": {"hp": 1.5}}}
	_write_payload(stage_id, payload)
	assert_false(bool(RBMLocalStageRepository.load_stage(stage_id).get("ok", true)))
	payload["draft"]["ally_overrides"] = {"hero": {"unknown": {}}}
	_write_payload(stage_id, payload)
	assert_false(bool(RBMLocalStageRepository.load_stage(stage_id).get("ok", true)))

func test_test_battle_restart_rewind_and_challenge_restart_keep_effective_values() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "hp", 777)
	draft.set_ally_stat_override("hero", "atk", 333)
	var definition := draft.to_definition()
	var test_session := RBMCreatorTestSession.new(definition, 1)
	assert_true(test_session.start_ok())
	assert_eq(test_session.battle.party[0].max_hp, 777)
	assert_eq(test_session.battle.party[0].atk, 333)
	assert_true(test_session.rewind_to(1))
	assert_eq(test_session.battle.party[0].max_hp, 777)
	test_session.restart()
	assert_eq(test_session.battle.party[0].atk, 333)

	var challenge := RBMChallengeSession.new(definition, 1)
	assert_true(challenge.start_ok())
	assert_eq(challenge.battle.party[0].max_hp, 777)
	challenge.restart()
	assert_eq(challenge.battle.party[0].atk, 333)

func test_normal_battle_has_no_100_turn_cap() -> void:
	var draft := _draft()
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	for _turn in range(101):
		battle.resolve_turn({"0": {"type": "defend"}})
	assert_false(battle.battle_over, "ordinary battle must not auto-end at turn 100")
	assert_gt(battle.current_turn, 100)

## Creator UI改修（STEP4統合、2026-09-05）: 旧「性能を見る」ボタン
## （ViewPerformanceButton_%s）→カード選択(SelectCharacterButton_%s)＋
## [性能調整]タブ(PerformanceTabButton)、旧「閉じる」（CloseCharacterInfoButton）
## →他カードを選ぶかタブを切り替えるだけ（専用の「閉じる」概念自体が無い）
## という新しい操作導線へ置き換えた。ADVANCED編集ロジック自体・ノード名
## （AllyStatOverrideSpin_%s_%s等）は無改修。
func test_hardcore_party_ui_edits_and_resets_via_real_controls_without_draft_side_effects_on_open() -> void:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.draft.add_party_character("hero")
	main.go_to_step(4)
	var step := main._step_views[3] as RBMCreatorStep5Party
	step.refresh()
	await get_tree().process_frame
	var before := main.draft.full_authoring_snapshot()
	(step.find_child("SelectCharacterButton_hero", true, false) as Button).pressed.emit()
	(step.find_child("PerformanceTabButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.full_authoring_snapshot(), before, "opening the editor is read-only")
	assert_null(step.find_child("CharacterInfoStatsLabel", true, false), "ADVANCEDでは編集欄（SpinBox）自体が唯一の値表示であり、重複する読み取り専用ラベルは存在しないこと")
	assert_eq((step.find_child("AllyStatOverrideLabel_hero_hp", true, false) as Label).text, "HP")
	var hp_spin := step.find_child("AllyStatOverrideSpin_hero_hp", true, false) as SpinBox
	assert_not_null(hp_spin)
	assert_eq(int(hp_spin.value), 650, "SpinBox自身が現在値を表示する")
	hp_spin.value = 777
	assert_eq(int(main.draft.ally_overrides["hero"]["stats"]["hp"]), 777)
	assert_eq((step.find_child("AllyStatOverrideLabel_hero_hp", true, false) as Label).text, "HP", "編集後も標準値→設定値表示へ戻らない")
	var slash_spin := step.find_child("AllySkillOverrideSpin_hero_hero_slash_atk_multiplier", true, false) as SpinBox
	assert_not_null(slash_spin)
	assert_eq((step.find_child("AllySkillOverrideLabel_hero_hero_slash_atk_multiplier", true, false) as Label).text, "倍率")
	assert_eq(float(slash_spin.value), 1.5)
	slash_spin.value = 5.0
	assert_eq(float(main.draft.ally_overrides["hero"]["skills"]["hero_slash"]["atk_multiplier"]), 5.0)
	(step.find_child("ResetAllySkillButton_hero_hero_slash", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_false((main.draft.ally_overrides["hero"] as Dictionary).has("skills"))
	(step.find_child("ResetAllyStatsButton_hero", true, false) as Button).pressed.emit()
	assert_true(main.draft.ally_overrides.is_empty())
	hp_spin = step.find_child("AllyStatOverrideSpin_hero_hp", true, false) as SpinBox
	hp_spin.value = 888
	(step.find_child("AllySkillOverrideSpin_hero_hero_slash_sp_cost", true, false) as SpinBox).value = 44
	assert_false(main.draft.ally_overrides.is_empty())
	(step.find_child("ResetAllAllyOverridesButton", true, false) as Button).pressed.emit()
	assert_true(main.draft.ally_overrides.is_empty(), "全体リセットの実UI導線も維持する")

func test_every_hardcore_override_row_shows_only_its_caption_and_editable_current_value() -> void:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.go_to_step(4)
	var step := main._step_views[3] as RBMCreatorStep5Party
	var stat_labels := {"hp": "HP", "atk": "ATK", "spd": "SPD", "max_sp": "Max SP"}
	var skill_labels := {
		"atk_multiplier": "倍率", "heal_amount": "回復量", "sp_amount": "SP回復量",
		"sp_cost": "SP消費", "buff_multiplier": "強化倍率", "duration_turns": "効果時間",
		"new_rate": "防御軽減率", "reduction_rate": "被ダメージ軽減率",
	}
	for character_id_variant in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		var character_id := str(character_id_variant)
		## Creator UI改修（2026-09-05）: 「選択キャラクター設定」は攻略パーティ
		## の一員に対してのみ機能する新モデルのため、対象キャラだけの単独
		## パーティへ都度入れ替えてから選択する。
		main.draft.party_character_ids.clear()
		main.draft.add_party_character(character_id)
		step.refresh()
		step.select_character(character_id)
		(step.find_child("PerformanceTabButton", true, false) as Button).pressed.emit()
		await get_tree().process_frame
		var master := main.draft.master_character_def(character_id)
		assert_null(step.find_child("CharacterInfoStatsLabel", true, false), "ADVANCEDでは編集欄（SpinBox）自体が唯一の値表示であること")
		for field in RBMDefinitionLoader.ALLY_STAT_OVERRIDE_FIELDS:
			var stat_label := step.find_child("AllyStatOverrideLabel_%s_%s" % [character_id, field], true, false) as Label
			var stat_spin := step.find_child("AllyStatOverrideSpin_%s_%s" % [character_id, field], true, false) as SpinBox
			assert_eq(stat_label.text, str(stat_labels[field]), "%s.%sは項目名だけを表示" % [character_id, field])
			assert_eq(int(stat_spin.value), int(master[field]), "%s.%sの現在値は編集欄に表示" % [character_id, field])
		for skill_variant in master.get("skills", []):
			var skill: Dictionary = skill_variant
			var skill_id := str(skill.get("id", ""))
			for field in RBMDefinitionLoader.ally_skill_override_fields(skill):
				var skill_label := step.find_child("AllySkillOverrideLabel_%s_%s_%s" % [character_id, skill_id, field], true, false) as Label
				var skill_spin := step.find_child("AllySkillOverrideSpin_%s_%s_%s" % [character_id, skill_id, field], true, false) as SpinBox
				assert_eq(skill_label.text, str(skill_labels[field]), "%s.%s.%sは項目名だけを表示" % [character_id, skill_id, field])
				assert_eq(float(skill_spin.value), float(skill[field]), "%s.%s.%sの現在値は編集欄に表示" % [character_id, skill_id, field])

func test_challenge_confirm_shows_effective_values_only_for_hardcore_and_does_not_mutate_draft() -> void:
	var draft := _draft()
	draft.set_ally_stat_override("hero", "atk", 999)
	draft.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 5.0)
	var before := draft.full_authoring_snapshot()
	var view := RBMChallengeConfirmView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	view.open("3333333333", draft)
	var stats := view.find_child("PartyPerformanceStats_hero", true, false) as Label
	assert_not_null(stats)
	assert_true(stats.text.contains("ATK 999"))
	assert_false(stats.text.contains("240"))
	assert_false(stats.text.contains("→"))
	var skill_line := view.find_child("PartyPerformanceSkill_hero_hero_slash", true, false) as Label
	assert_true(skill_line.text.contains("倍率 5.00"))
	assert_false(skill_line.text.contains("1.50"))
	assert_false(skill_line.text.contains("→"))
	assert_eq(draft.full_authoring_snapshot(), before, "challenge display must not modify the saved Draft")

	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	view.open("3333333333", draft)
	await get_tree().process_frame
	var simple_has_performance := false
	for node in view.find_children("*", "Label", true, false):
		if (node as Label).name.begins_with("PartyPerformance"):
			simple_has_performance = true
	assert_false(simple_has_performance, "SIMPLE keeps its established master-only presentation")
