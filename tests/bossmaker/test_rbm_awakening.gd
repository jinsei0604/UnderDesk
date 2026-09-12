extends GutTest

## RPG BOSS MAKER — 覚醒（Awakening）の回帰テスト。
## 通常のaction_sequence（1ターン1スロットのラウンドロビン）とは完全に
## 独立した、ボス専用の特別イベントであることを検証する。既存の
## test_rbm_advanced_battle.gdと同じ慣習で、RBMDefinitionLoaderを経由せず
## 「既に解決済みのboss_def」を直接手書きしてRBMBattleへ渡し、実際の製品
## コードが使う戦闘駆動API（advance_to_next_decision()/resolve_pending_
## ally_action()）をそのまま経由して検証する。

const ATTACK := {"type": "attack"}

func _ally_def(character_id: String, atk_override: int = -1, spd_override: int = -1) -> Dictionary:
	var def := RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % character_id)
	if atk_override >= 0:
		def["atk"] = atk_override
	if spd_override >= 0:
		def["spd"] = spd_override
	return def

func _boss_skills() -> Array:
	return [
		{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
	]

## awakeningが空Dictionaryなら「未設定」——旧ボスデータ/覚醒を設定していない
## ボスと同じ状態を作れる。
func _boss_def(awakening: Dictionary = {}, hp: int = 1000, spd: int = 10, action_sequence: Array = []) -> Dictionary:
	var def := {
		"id": "awakening_boss", "display_name": "AwakeningBoss", "hp": hp, "atk": 10, "spd": spd,
		"skills": _boss_skills(),
		"normal_action_candidates": [],
		"action_sequence": action_sequence,
	}
	if not awakening.is_empty():
		def["awakening"] = awakening
	return def

func _hp_awakening(percent: float = 50.0, buff: Dictionary = {}, heal_amount: int = 0) -> Dictionary:
	var out := {
		"conditions": [{"type": "hp_at_most", "percent": percent}],
		"condition_logic": "AND",
	}
	if not buff.is_empty():
		out["buff"] = buff
	if heal_amount > 0:
		out["heal_amount"] = heal_amount
	return out

func _conditionless_awakening(buff: Dictionary = {}, heal_amount: int = 0) -> Dictionary:
	var out := {"conditions": [], "condition_logic": "AND"}
	if not buff.is_empty():
		out["buff"] = buff
	if heal_amount > 0:
		out["heal_amount"] = heal_amount
	return out

func _battle(boss_def: Dictionary, hero_atk: int = 600, hero_spd: int = 100) -> RBMBattle:
	var party: Array[Dictionary] = [_ally_def("hero", hero_atk, hero_spd)]
	return RBMBattle.new(party, boss_def, 1)

func _action_type_entries(log: Array, action: String) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("action", "")) == action:
			out.append(entry)
	return out

# ---------------------------------------------------------------------------
# Battle runtime
# ---------------------------------------------------------------------------

func test_boss_without_awakening_field_behaves_unchanged() -> void:
	var battle := _battle(_boss_def({}))
	for i in range(4):
		battle.advance_to_next_decision()
		if battle.is_waiting_for_ally_action():
			battle.resolve_pending_ally_action(ATTACK)
	assert_false(battle.is_awakened)
	assert_false(battle.awakening_used)

func test_awakening_does_not_trigger_before_condition_met() -> void:
	var battle := _battle(_boss_def(_hp_awakening(50.0)), 50)  # 50/1000 damage -> 95%, condition not met
	battle.advance_to_next_decision()
	var log := battle.resolve_pending_ally_action(ATTACK)
	log.append_array(battle.advance_to_next_decision())
	assert_true(_action_type_entries(log, "awakening").is_empty())
	assert_false(battle.is_awakened)
	assert_false(battle.awakening_used)

func test_awakening_triggers_once_hp_condition_met_with_buff_and_heal() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0, {"buff_multiplier": 1.5, "duration_turns": 2}, 100), 1000, 10, [
		{"slot_id": "s1", "kind": "skill", "skill_id": "boss_hit", "conditions": [], "condition_logic": "AND", "max_uses": -1},
	])
	var battle := _battle(boss_def, 600, 100)  # hero acts first (higher SPD), 600 dmg -> boss at 400/1000 (40%)
	var log := battle.advance_to_next_decision()  # nothing to auto-resolve, hero is pending
	log.append_array(battle.resolve_pending_ally_action(ATTACK))
	log.append_array(battle.advance_to_next_decision())  # boss's own turn should still fire afterward
	var awakening_entries := _action_type_entries(log, "awakening")
	assert_eq(awakening_entries.size(), 1, "awakening fires exactly once")
	assert_true(battle.is_awakened)
	assert_true(battle.awakening_used)
	assert_eq(battle.boss.hp, 500, "400 post-damage + 100 heal_amount")
	assert_true(RBMConstants.timed_effect_active(battle.boss.timed_effects, "atk_buff", battle.current_turn))
	assert_eq(float(RBMConstants.timed_effect_value(battle.boss.timed_effects, "atk_buff", battle.current_turn, 1.0)), 1.5)
	# The boss still takes its own ordinary turn afterward -- awakening did not consume it.
	assert_eq(_action_type_entries(log, "skill").size(), 1, "boss's own action_sequence turn still fires")
	# Ordering: ally's attack, then awakening, then the boss's own turn.
	var awakening_index := -1
	var boss_skill_index := -1
	for i in range(log.size()):
		if str(log[i].get("action", "")) == "awakening": awakening_index = i
		if str(log[i].get("action", "")) == "skill": boss_skill_index = i
	assert_true(awakening_index >= 0 and boss_skill_index >= 0 and awakening_index < boss_skill_index, "awakening fires between the triggering hit and the boss's own next action")

func test_awakening_never_fires_twice_even_while_condition_stays_true() -> void:
	var boss_def := _boss_def(_hp_awakening(90.0), 1000, 10, [
		{"slot_id": "s1", "kind": "skill", "skill_id": "boss_hit", "conditions": [], "condition_logic": "AND", "max_uses": -1},
	])
	var battle := _battle(boss_def, 200, 100)
	var log: Array = []
	for i in range(4):
		log.append_array(battle.advance_to_next_decision())
		if battle.is_waiting_for_ally_action():
			log.append_array(battle.resolve_pending_ally_action(ATTACK))
	assert_eq(_action_type_entries(log, "awakening").size(), 1, "condition stays true for many turns, awakening still fires only once")

func test_awakening_buff_expires_but_is_awakened_persists() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0, {"buff_multiplier": 2.0, "duration_turns": 3}), 1000, 10, [])
	var battle := _battle(boss_def, 600, 100)
	battle.advance_to_next_decision()
	battle.resolve_pending_ally_action(ATTACK)
	assert_true(battle.is_awakened)
	assert_true(RBMConstants.timed_effect_active(battle.boss.timed_effects, "atk_buff", battle.current_turn), "buff still active shortly after triggering (turn %d)" % battle.current_turn)
	# Fast-forward far past the buff's 3-turn window without needing to
	# actually simulate dozens of rounds -- timed_effect_active() only ever
	# compares against current_turn, and current_turn is a plain public field.
	battle.current_turn += 50
	assert_false(RBMConstants.timed_effect_active(battle.boss.timed_effects, "atk_buff", battle.current_turn), "the buff itself has expired (turn %d)" % battle.current_turn)
	assert_true(battle.is_awakened, "awakening state is independent of the buff's own expiry")
	assert_true(battle.awakening_used)

func test_awakening_transform_only_no_buff_no_heal() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0), 1000, 10, [])
	var battle := _battle(boss_def, 600, 100)
	battle.advance_to_next_decision()
	var log := battle.resolve_pending_ally_action(ATTACK)
	log.append_array(battle.advance_to_next_decision())
	assert_eq(_action_type_entries(log, "awakening").size(), 1)
	assert_true(battle.is_awakened)
	assert_eq(battle.boss.hp, 400, "no heal configured -- HP stays exactly at the post-damage value")
	assert_false(RBMConstants.timed_effect_active(battle.boss.timed_effects, "atk_buff", battle.current_turn), "no buff configured")

func test_awakening_heal_only_no_buff() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0, {}, 250), 1000, 10, [])
	var battle := _battle(boss_def, 600, 100)
	battle.advance_to_next_decision()
	battle.resolve_pending_ally_action(ATTACK)
	battle.advance_to_next_decision()
	assert_eq(battle.boss.hp, 650, "400 post-damage + 250 heal_amount")
	assert_false(RBMConstants.timed_effect_active(battle.boss.timed_effects, "atk_buff", battle.current_turn))

## 条件なし覚醒(conditions=[])は「誰かの行動が初めて解決されるまで待つ」
## のではなく、戦闘開始後最初のadvance_to_next_decision()呼び出しの、
## TURN STARTの後始末が終わった安全なタイミングで発動しなければならない
## ——heroがturn_orderの先頭(SPDが最も高い)でも、hero自身の行動が解決
## される「前」に、待機列がhero入力待ちへ止まった状態のまま既に発動して
## いることを確認する。
func test_conditionless_awakening_fires_at_first_safe_turn_start_before_anyones_action() -> void:
	var boss_def := _boss_def(_conditionless_awakening({"buff_multiplier": 1.2, "duration_turns": 2}, 10))
	var battle := _battle(boss_def, 100, 999)  # hero SPD 999 > boss SPD 10 -- hero is turn_order[0]
	assert_false(battle.is_awakened)
	var log := battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action(), "must still correctly stop waiting for hero's own input")
	assert_eq(battle.pending_ally_id(), battle.party[0].id, "hero's turn has not been resolved yet")
	assert_true(battle.is_awakened, "a condition-less awakening must not wait for anyone's action to resolve first")
	assert_true(battle.awakening_used)
	assert_eq(_action_type_entries(log, "awakening").size(), 1)
	# Still fires only once, even though the (empty) condition stays trivially
	# true forever -- covered generally by test_awakening_never_fires_twice_
	# even_while_condition_stays_true(), reconfirmed here for the
	# condition-less case specifically.
	battle.resolve_pending_ally_action(ATTACK)
	var log2 := battle.advance_to_next_decision()
	assert_eq(_action_type_entries(log2, "awakening").size(), 0)

func test_awakening_does_not_skip_or_double_advance_the_normal_action_cursor() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0), 1000, 10, [
		{"slot_id": "s1", "kind": "skill", "skill_id": "boss_hit", "conditions": [], "condition_logic": "AND", "max_uses": -1},
		{"slot_id": "s2", "kind": "skill", "skill_id": "boss_hit", "conditions": [], "condition_logic": "AND", "max_uses": -1},
	])
	var battle := _battle(boss_def, 600, 100)  # hero acts first, drops boss to 40% and triggers awakening
	assert_eq(battle.hardcore_action_cursor(), 0)
	battle.advance_to_next_decision()
	battle.resolve_pending_ally_action(ATTACK)
	battle.advance_to_next_decision()  # boss's own turn (slot s1) fires immediately after awakening, same round
	assert_true(battle.is_awakened)
	assert_eq(battle.hardcore_action_cursor(), 1, "the boss's turn used exactly slot s1 and advanced the cursor by exactly one, awakening did not touch it")
	# Next round: awakening is already used and must not fire again; the boss's
	# turn must use the NEXT slot (s2), not skip it and not repeat s1. Hero
	# defends this round instead of attacking again -- a second 600-damage
	# hit would drop the 1000hp boss (already at 400) to 0 and end the battle
	# before the boss ever gets its round-2 turn, which would confound this
	# assertion with "battle already over" rather than a real cursor bug.
	battle.resolve_pending_ally_action({"type": "defend"})
	var log2 := battle.advance_to_next_decision()
	assert_eq(_action_type_entries(log2, "awakening").size(), 0, "awakening must not fire a second time")
	assert_eq(battle.hardcore_action_cursor(), 0, "cursor wrapped from slot s2 (index 1) back to 0, proving s2 was used, not skipped")
	var boss_actions := _action_type_entries(log2, "skill")
	assert_eq(boss_actions.size(), 1, "the boss still took exactly one normal action this round -- awakening did not cause it to skip or double up")

func test_awakening_survives_snapshot_restore_round_trip() -> void:
	var boss_def := _boss_def(_hp_awakening(50.0, {"buff_multiplier": 1.5, "duration_turns": 3}, 50), 1000, 10, [])
	var battle := _battle(boss_def, 600, 100)
	var pre_snapshot := battle.snapshot()
	battle.advance_to_next_decision()
	battle.resolve_pending_ally_action(ATTACK)
	battle.advance_to_next_decision()
	assert_true(battle.is_awakened)
	var post_snapshot := battle.snapshot()
	# Rewinding to before the triggering hit must also undo the awakening state.
	battle.restore(pre_snapshot)
	assert_false(battle.is_awakened)
	assert_false(battle.awakening_used)
	# Restoring the post-awakening snapshot must bring it back.
	battle.restore(post_snapshot)
	assert_true(battle.is_awakened)
	assert_true(battle.awakening_used)

# ---------------------------------------------------------------------------
# Creator draft data model
# ---------------------------------------------------------------------------

func _draft() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "覚醒テスト"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 10
	return draft

func test_draft_awakening_default_unset_then_set_then_removed() -> void:
	var draft := _draft()
	assert_false(draft.has_awakening())
	draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "percent", "heal_fixed_amount": 0, "heal_percent": 30.0}})
	assert_true(draft.has_awakening())
	draft.remove_awakening()
	assert_false(draft.has_awakening())

func test_draft_to_definition_omits_awakening_when_unset() -> void:
	var draft := _draft()
	var definition := draft.to_definition()
	assert_false(definition["boss"].has("awakening"))

func test_draft_to_definition_includes_resolved_awakening_when_set() -> void:
	var draft := _draft()
	draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "percent", "heal_fixed_amount": 0, "heal_percent": 30.0}})
	var definition := draft.to_definition()
	var awakening: Dictionary = definition["boss"]["awakening"]
	assert_eq(awakening["conditions"], [{"type": "hp_at_most", "percent": 50.0}])
	assert_eq(awakening["buff"], {"buff_multiplier": 1.5, "duration_turns": 3})
	assert_eq(int(awakening["heal_amount"]), 300, "30% of 1000 hp")

func test_draft_save_restore_round_trip_preserves_awakening() -> void:
	var draft := _draft()
	draft.set_awakening({"conditions": [{"type": "turn_at_least", "turn": 3}], "condition_logic": "AND",
		"buff": {}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 200, "heal_percent": 0.0}})
	var saved := draft.to_saved_dict()
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_true(restored.has_awakening())
	assert_eq(restored.awakening["conditions"], [{"type": "turn_at_least", "turn": 3}])
	assert_eq(restored.awakening["heal"], {"heal_mode": "fixed", "heal_fixed_amount": 200, "heal_percent": 0.0})

func test_draft_restore_from_saved_dict_without_awakening_key_is_backward_compatible() -> void:
	var draft := _draft()
	var saved := draft.to_saved_dict()
	saved.erase("awakening")  # simulate a stage saved before the awakening feature existed
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(saved)
	assert_false(restored.has_awakening())

# ---------------------------------------------------------------------------
# RBMDefinitionLoader validation
# ---------------------------------------------------------------------------

func _loader_base_boss() -> Dictionary:
	return {
		"boss_id": "awakening_loader_boss", "boss_name": "LoaderBoss", "hp": 1000, "atk": 100, "spd": 50,
		"skills": [{"skill_id": "claw", "name": "Claw", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
	}

func _loader_base_party() -> Array:
	return [{"character_id": "hero"}]

func test_loader_accepts_a_well_formed_awakening() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {
		"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal_amount": 100.0,
	}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_true(bool(result.get("ok", false)))
	var resolved: Dictionary = result["boss_def"]["awakening"]
	assert_eq(resolved["conditions"], [{"type": "hp_at_most", "percent": 50.0}])
	assert_eq(resolved["buff"], {"buff_multiplier": 1.5, "duration_turns": 3})
	assert_eq(int(resolved["heal_amount"]), 100)

func test_loader_resolves_missing_awakening_key_to_empty() -> void:
	var result := RBMDefinitionLoader.resolve({"boss": _loader_base_boss(), "party": _loader_base_party()})
	assert_true(bool(result.get("ok", false)), "old boss data with no awakening key at all must still load fine")
	assert_eq(result["boss_def"]["awakening"], {})

func test_loader_rejects_negative_buff_multiplier() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {"conditions": [], "condition_logic": "AND", "buff": {"buff_multiplier": -1.0, "duration_turns": 3}}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_false(bool(result.get("ok", false)))

func test_loader_rejects_non_positive_buff_duration() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {"conditions": [], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 0}}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_false(bool(result.get("ok", false)))

func test_loader_rejects_negative_heal_amount() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {"conditions": [], "condition_logic": "AND", "heal_amount": -50.0}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_false(bool(result.get("ok", false)))

func test_loader_rejects_unknown_condition_type_inside_awakening() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {"conditions": [{"type": "not_a_real_condition"}], "condition_logic": "AND"}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_false(bool(result.get("ok", false)))

func test_loader_accepts_awakening_with_no_buff_and_no_heal() -> void:
	var boss := _loader_base_boss()
	boss["awakening"] = {"conditions": [{"type": "turn_at_least", "turn": 3}], "condition_logic": "AND"}
	var result := RBMDefinitionLoader.resolve({"boss": boss, "party": _loader_base_party()})
	assert_true(bool(result.get("ok", false)), "a transform-only awakening (no buff, no heal) must be valid")
	var resolved: Dictionary = result["boss_def"]["awakening"]
	assert_false(resolved.has("buff"))
	assert_false(resolved.has("heal_amount"))

func test_battle_content_snapshot_changes_when_awakening_changes() -> void:
	var draft := _draft()
	var before := draft.battle_content_snapshot()
	draft.set_awakening({"conditions": [], "condition_logic": "AND", "buff": {"buff_multiplier": 2.0, "duration_turns": 1}, "heal": {}})
	var after := draft.battle_content_snapshot()
	assert_ne(before, after, "changing awakening must invalidate a prior Clear Check success snapshot")
