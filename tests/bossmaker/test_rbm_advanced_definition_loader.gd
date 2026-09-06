extends GutTest

## RPG BOSS MAKER — HARDCORE Creator「攻撃（action_sequence）」の
## RBMDefinitionLoader検証・解決テスト（2026-09-05全面再設計、旧「行動
## パターン」仕様のテストを全面置換）。RBMCreatorDraftを介さず、
## RBMDefinitionLoader.resolve()がボス作成者から見て安全な範囲を強制する
## ことを直接確認する（test_rbm_definition_loader.gdと同じ、ad-hocな
## Definition Dictionaryを手書きするパターン）。
##
## 旧仕様にあった瞬間条件（_instantサフィックス）・発動確率
## （trigger_probability）・Cooldown（cooldown_turns）・post_instant_behavior
## は新仕様に一切存在しない（RBMActionPatternRules冒頭コメント参照）——
## これらを指定しても「未知の条件タイプ」または「未知のフィールドとして
## 単純に無視される」ことを確認するテストへ置き換えた。

func _base_boss() -> Dictionary:
	return {
		"boss_id": "adhoc_boss",
		"boss_name": "Adhoc Boss",
		"hp": 1000,
		"atk": 100,
		"spd": 50,
		"skills": [
			{"skill_id": "adhoc_claw", "name": "Claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"skill_id": "adhoc_bite", "name": "Bite", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.5},
		],
	}

func _base_party(count: int = 1) -> Array:
	var ids := ["hero", "butler", "healer", "samurai", "tank"]
	var out: Array = []
	for i in range(count):
		out.append({"character_id": ids[i]})
	return out

func _bare_slot(skill_id: String = "adhoc_claw") -> Dictionary:
	return {
		"slot_id": "slot_1",
		"kind": "skill",
		"skill_id": skill_id,
		"conditions": [],
		"condition_logic": "AND",
		"max_uses": -1,
	}

func _resolve_with_slot(slot: Dictionary) -> Dictionary:
	var boss := _base_boss()
	boss["action_sequence"] = [slot]
	return RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})

# ---------------------------------------------------------------------------
# 空/未指定
# ---------------------------------------------------------------------------

func test_no_action_sequence_key_resolves_ok_with_empty_action_sequence() -> void:
	var result := RBMDefinitionLoader.resolve({"boss": _base_boss(), "party": _base_party(1)})
	assert_true(bool(result.get("ok", false)))
	assert_true((result["boss_def"]["action_sequence"] as Array).is_empty())

# ---------------------------------------------------------------------------
# slot_id
# ---------------------------------------------------------------------------

func test_duplicate_slot_id_is_rejected() -> void:
	var boss := _base_boss()
	boss["action_sequence"] = [_bare_slot(), _bare_slot()]
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(result.get("ok", false)))

func test_unsafe_slot_id_is_rejected() -> void:
	var slot := _bare_slot()
	slot["slot_id"] = "../etc/passwd"
	var result := _resolve_with_slot(slot)
	assert_false(bool(result.get("ok", false)))

# ---------------------------------------------------------------------------
# スロット総数の上限（旧MAX_ACTIONS_PER_PATTERNから、action_sequence全体の
# 上限へ引き継がれた——§9の判断根拠、RBMActionPatternRules冒頭コメント参照）
# ---------------------------------------------------------------------------

func test_action_sequence_exceeding_max_slots_is_rejected() -> void:
	var boss := _base_boss()
	var slots: Array = []
	for i in range(RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS + 1):
		var slot := _bare_slot()
		slot["slot_id"] = "slot_%d" % i
		slots.append(slot)
	boss["action_sequence"] = slots
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_false(bool(result.get("ok", false)))

func test_action_sequence_with_exactly_max_slots_is_accepted() -> void:
	var boss := _base_boss()
	var slots: Array = []
	for i in range(RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS):
		var slot := _bare_slot()
		slot["slot_id"] = "slot_%d" % i
		slots.append(slot)
	boss["action_sequence"] = slots
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(result.get("ok", false)))

# ---------------------------------------------------------------------------
# kind / skill_id / candidates
# ---------------------------------------------------------------------------

func test_slot_referencing_unknown_boss_skill_is_rejected() -> void:
	var result := _resolve_with_slot(_bare_slot("does_not_exist"))
	assert_false(bool(result.get("ok", false)))

func test_unknown_slot_kind_is_rejected() -> void:
	var slot := _bare_slot()
	slot["kind"] = "melee_combo"
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_random_slot_with_empty_candidates_is_rejected() -> void:
	var slot := _bare_slot()
	slot["kind"] = "random"
	slot["candidates"] = []
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_random_slot_with_negative_weight_is_rejected() -> void:
	var slot := _bare_slot()
	slot["kind"] = "random"
	slot["candidates"] = [{"skill_id": "adhoc_claw", "weight": -1.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_random_slot_with_zero_total_weight_is_rejected() -> void:
	var slot := _bare_slot()
	slot["kind"] = "random"
	slot["candidates"] = [{"skill_id": "adhoc_claw", "weight": 0.0}, {"skill_id": "adhoc_bite", "weight": 0.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_random_slot_referencing_unknown_boss_skill_is_rejected() -> void:
	var slot := _bare_slot()
	slot["kind"] = "random"
	slot["candidates"] = [{"skill_id": "does_not_exist", "weight": 1.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_random_slot_with_valid_candidates_resolves_ok() -> void:
	var slot := _bare_slot()
	slot["kind"] = "random"
	slot["candidates"] = [{"skill_id": "adhoc_claw", "weight": 70.0}, {"skill_id": "adhoc_bite", "weight": 30.0}]
	var result := _resolve_with_slot(slot)
	assert_true(bool(result.get("ok", false)))
	var resolved_slot: Dictionary = (result["boss_def"]["action_sequence"] as Array)[0]
	assert_eq((resolved_slot["candidates"] as Array).size(), 2)

# ---------------------------------------------------------------------------
# 通常条件の型・範囲検証
# ---------------------------------------------------------------------------

func test_hp_at_most_percent_out_of_range_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "hp_at_most", "percent": 150.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_hp_between_with_min_greater_than_max_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "hp_between", "percent_min": 80.0, "percent_max": 20.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_turn_at_with_turn_zero_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "turn_at", "turn": 0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

## 2026-09-05全面再設計: 瞬間条件（_instantサフィックス）は新仕様の
## NORMAL_CONDITION_TYPESに一切存在しない——未知の条件タイプとして拒否
## される。旧・是認テスト（瞬間条件は正しく解決される）から、削除された
## ことを直接確認するテストへ転換した。
func test_instant_condition_type_suffix_is_rejected_as_unknown() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "hp_at_most_instant", "percent": 50.0}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_allies_instant_condition_type_suffix_is_rejected_as_unknown() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "allies_at_most_instant", "count": 1}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_weak_hit_instant_condition_type_is_rejected_as_unknown() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "weak_hit_instant"}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_allies_at_least_with_negative_count_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "allies_at_least", "count": -1}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_character_condition_with_unknown_character_id_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "character_alive", "character_id": "not_a_real_character"}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_character_condition_accepts_any_known_ally_regardless_of_current_party() -> void:
	# STEP3（攻撃編集）はSTEP4（パーティ選択）より前に来るため、パーティに
	# まだ加入していないキャラクターも条件として選べる必要がある。
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "character_alive", "character_id": "samurai"}]
	var result := _resolve_with_slot(slot)  # パーティは"hero"のみ (_base_party(1))
	assert_true(bool(result.get("ok", false)))

func test_last_boss_skill_condition_with_unknown_skill_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "last_boss_skill", "skill_id": "not_a_boss_skill"}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_last_boss_skill_condition_with_known_boss_skill_resolves_ok() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "last_boss_skill", "skill_id": "adhoc_bite"}]
	assert_true(bool(_resolve_with_slot(slot).get("ok", false)))

## 味方の固定5キャラクター全員分のマスタースキル一覧から選べる（現在の
## "party"に含まれるかは無関係——tankは_base_party(1)に含まれない）。
func test_last_received_skill_condition_accepts_any_known_ally_skill() -> void:
	var master := RBMDataLoader.load_dict("res://data_bossmaker/allies/tank.json")
	var any_skill_id := str((master.get("skills", []) as Array)[0].get("id", ""))
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "last_received_skill", "skill_id": any_skill_id}]
	var result := _resolve_with_slot(slot)
	assert_true(bool(result.get("ok", false)))

func test_last_received_skill_condition_with_unknown_skill_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "last_received_skill", "skill_id": "not_a_real_ally_skill"}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_last_received_attribute_with_unknown_attribute_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "last_received_attribute", "attribute": "PSYCHIC"}]
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_weak_hit_condition_needs_no_fields_and_resolves_ok() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "weak_hit"}]
	var result := _resolve_with_slot(slot)
	assert_true(bool(result.get("ok", false)))

# ---------------------------------------------------------------------------
# condition_logic / max_uses
# ---------------------------------------------------------------------------

func test_multi_condition_slot_with_unknown_logic_is_rejected() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "turn_at_least", "turn": 1}, {"type": "hp_at_most", "percent": 50.0}]
	slot["condition_logic"] = "XOR"
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

func test_max_uses_below_negative_one_is_rejected() -> void:
	var slot := _bare_slot()
	slot["max_uses"] = -2
	assert_false(bool(_resolve_with_slot(slot).get("ok", false)))

## 2026-09-05全面再設計§9: 発動確率(trigger_probability)・Cooldown
## (cooldown_turns)・post_instant_behaviorは新schemaに一切存在しない——
## 値を渡してもDefinitionLoaderは単に無視し（resolved_slotへ書き写さない）、
## エラーにもならない（キー自体がもう検証対象ではないことの直接確認）。
func test_legacy_probability_cooldown_post_instant_fields_are_ignored() -> void:
	var slot := _bare_slot()
	slot["trigger_probability"] = 40.0
	slot["cooldown_turns"] = 3
	slot["post_instant_behavior"] = "next_turn"
	var result := _resolve_with_slot(slot)
	assert_true(bool(result.get("ok", false)))
	var resolved_slot: Dictionary = (result["boss_def"]["action_sequence"] as Array)[0]
	assert_false(resolved_slot.has("trigger_probability"))
	assert_false(resolved_slot.has("cooldown_turns"))
	assert_false(resolved_slot.has("post_instant_behavior"))

func test_valid_slot_round_trips_all_fields_into_boss_def() -> void:
	var slot := _bare_slot()
	slot["conditions"] = [{"type": "turn_at_least", "turn": 5}]
	slot["max_uses"] = 2
	var result := _resolve_with_slot(slot)
	assert_true(bool(result.get("ok", false)))
	var resolved_slot: Dictionary = (result["boss_def"]["action_sequence"] as Array)[0]
	assert_eq(str(resolved_slot["slot_id"]), "slot_1")
	assert_eq(int(resolved_slot["max_uses"]), 2)
	assert_eq(str(resolved_slot["skill_id"]), "adhoc_claw")

## §15/§18: 上から順に走査するラウンドロビン評価器の前提として、配列
## 順序がDefinition解決後も保持されること。
func test_slot_order_is_preserved_through_resolution() -> void:
	var boss := _base_boss()
	var slot_a := _bare_slot()
	slot_a["slot_id"] = "slot_a"
	var slot_b := _bare_slot()
	slot_b["slot_id"] = "slot_b"
	boss["action_sequence"] = [slot_a, slot_b]
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _base_party(1)})
	assert_true(bool(result.get("ok", false)))
	var resolved: Array = result["boss_def"]["action_sequence"]
	assert_eq(str(resolved[0]["slot_id"]), "slot_a")
	assert_eq(str(resolved[1]["slot_id"]), "slot_b")
