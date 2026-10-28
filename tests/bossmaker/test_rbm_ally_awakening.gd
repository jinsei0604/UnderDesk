extends GutTest

## 味方の覚醒（2026-10-24）: 技の定義・SIMPLE/HARDCORE の値・倍率と HP/SP の割合・必要SP・持続（次の自分の行動から数える）・
## 重ねがけの禁止・戦闘不能で解除・ほかの強化との共存・行動順・REWIND・保存と復元・戦闘UIの文字・演出のつなぎ。

const TEST_DIR := "user://bossmaker_test_ally_awakening/stages"
const IDS := ["hero", "butler", "healer", "samurai", "tank"]
const Stage = preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
const AllyAwakening = preload("res://src/bossmaker/visuals/rbm_ally_awakening_presentation.gd")
## 演出の素材（事前読み込みの代わりにテストが持つ。持っていないと演出が読み終えるまで始まらない）。
var held: Array = []

func before_all() -> void:
	for character_id in IDS:
		for path in AllyAwakening.warm_paths(character_id, "awakening_ally"):
			held.append(load(path))

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

## 味方1人（＋任意）と、ほとんど痛くないボスの定義。boss_spd でボスが先か後かを決める。
func _definition(party: Array, overrides := {}, boss_spd := 1, boss_atk := 1) -> Dictionary:
	var entries: Array = []
	for character_id in party:
		var entry := {"character_id": character_id}
		if overrides.has(character_id):
			entry["skill_overrides"] = {"%s_awakening" % character_id: overrides[character_id]}
		entries.append(entry)
	return {
		"boss": {
			"boss_id": "awakening_test_boss", "boss_name": "覚醒テスト", "hp": 99999, "atk": boss_atk, "spd": boss_spd,
			"skills": [{"skill_id": "poke", "name": "つつく", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.01}],
			"normal_actions": [{"skill_id": "poke", "weight": 1}],
		},
		"party": entries,
	}

func _battle(party: Array, overrides := {}, boss_spd := 1, boss_atk := 1) -> RBMBattle:
	var started := RBMDefinitionLoader.start_battle(_definition(party, overrides, boss_spd, boss_atk), 7)
	assert_true(bool(started.get("ok", false)), "定義が通る: %s" % str(started.get("errors", [])))
	return started.get("battle")

func _unit(battle: RBMBattle, character_id: String) -> RBMUnit:
	for unit in battle.party:
		if unit.character_id == character_id:
			return unit
	return null

## 指定した味方の番まで進める（ほかの味方は防御）。
func _until_turn_of(battle: RBMBattle, unit: RBMUnit) -> void:
	for i in 200:
		battle.advance_to_next_decision()
		if battle.battle_over:
			return
		if battle.pending_ally_id() == unit.id:
			return
		battle.resolve_pending_ally_action({"type": "defend"})

func _awaken(battle: RBMBattle, unit: RBMUnit) -> Array[Dictionary]:
	_until_turn_of(battle, unit)
	return battle.resolve_pending_ally_action({"type": "skill", "skill_id": "%s_awakening" % unit.character_id, "target_id": -1})

func _skill(unit: RBMUnit) -> Dictionary:
	for skill in unit.skills:
		if str(skill.get("effect", "")) == RBMDataLoader.AWAKENING_EFFECT:
			return skill
	return {}

# --- 技の定義・値の範囲 ---

func test_all_five_allies_own_the_awakening_skill_with_simple_values() -> void:
	for character_id in IDS:
		var master := RBMDataLoader.load_dict(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id])
		var found := {}
		for skill in master.get("skills", []):
			if str(skill.get("effect", "")) == RBMDataLoader.AWAKENING_EFFECT:
				found = skill
		assert_eq(str(found.get("id", "")), "%s_awakening" % character_id, character_id)
		assert_eq(float(found.get("awakening_multiplier", 0.0)), 1.5, "SIMPLE は 1.5 倍")
		assert_eq(int(found.get("awakening_turns", 0)), 3, "SIMPLE は 3 ターン")
		assert_eq(int(found.get("awakening_sp_percent", 0)), 70, "SIMPLE は最大SPの70%")
		assert_false(found.has("sp_cost"), "必要SP は最大SP から決まる（固定値を持たない）")
		assert_eq(RBMDefinitionLoader.ally_skill_override_fields(found), ["awakening_multiplier", "awakening_turns", "awakening_sp_percent"] as Array[String])

func test_hardcore_value_ranges() -> void:
	for ok in [1.0, 1.5, 2.3, 10.0, 7.0]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_multiplier", ok), "倍率 %s は使える" % str(ok))
	for ng in [0.9, 10.1, 1.55, -1.0, "2"]:
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_multiplier", ng), "倍率 %s は使えない" % str(ng))
	for ok in [1, 3, 99, 50.0]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_turns", ok))
	for ng in [0, 100, 1.5, -3]:
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_turns", ng))
	for ok in [0, 1, 70, 100]:
		assert_true(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_sp_percent", ok))
	for ng in [-1, 101, 70.5]:
		assert_false(RBMDefinitionLoader.validate_ally_skill_override_value("awakening_sp_percent", ng))

func test_required_sp_is_ceil_of_pre_awakening_max_sp_times_rate() -> void:
	assert_eq(RBMDataLoader.awakening_sp_cost(100, 70), 70)
	assert_eq(RBMDataLoader.awakening_sp_cost(1000, 70), 700)
	assert_eq(RBMDataLoader.awakening_sp_cost(33, 70), 24, "23.1 は切り上げて 24")
	assert_eq(RBMDataLoader.awakening_sp_cost(10, 1), 1, "0.1 は切り上げて 1")
	assert_eq(RBMDataLoader.awakening_sp_cost(100, 0), 0)
	assert_eq(RBMDataLoader.awakening_sp_cost(100, 100), 100)
	assert_eq(RBMDataLoader.awakening_sp_cost(RBMConstants.NO_SP, 70), 0)
	var battle := _battle(["hero"], {"hero": {"awakening_sp_percent": 33}})
	assert_eq(int(_skill(_unit(battle, "hero")).get("sp_cost", -1)), 33, "勇者の最大SP 100 × 33%")
	var master := RBMDataLoader.load_dict(RBMDefinitionLoader.KNOWN_ALLY_PATHS["hero"])
	for skill in master.get("skills", []):
		assert_false(skill.has("sp_cost") and str(skill.get("effect", "")) == RBMDataLoader.AWAKENING_EFFECT, "元の定義へ書き戻さない")

# --- 倍率・HP/SP の割合 ---

func test_multiplier_scales_every_stat_and_keeps_hp_ratio() -> void:
	var cases := [
		# [倍率, 覚醒前のHP, 覚醒後のHP, 解除後のHP]（勇者の最大HP 650）
		[1.0, 650, 650, 650],
		[1.5, 650, 975, 650],
		[1.5, 520, 780, 520],
		[1.5, 1, 2, 1],
		[10.0, 650, 6500, 650],
		[10.0, 520, 5200, 520],
		[10.0, 1, 10, 1],
	]
	for c in cases:
		var battle := _battle(["hero"], {"hero": {"awakening_multiplier": c[0], "awakening_turns": 1}})
		var hero := _unit(battle, "hero")
		_until_turn_of(battle, hero)
		hero.hp = int(c[1])
		battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_awakening", "target_id": -1})
		assert_true(hero.awakened)
		assert_eq(hero.max_hp, int(round(650 * float(c[0]))), "最大HP ×%s" % str(c[0]))
		assert_eq(hero.hp, int(c[2]), "HP %d → %d（×%s）" % [c[1], c[2], str(c[0])])
		assert_eq(hero.atk, int(round(240 * float(c[0]))), "ATK")
		assert_eq(hero.spd, int(round(100 * float(c[0]))), "SPD")
		assert_eq(hero.max_sp, int(round(100 * float(c[0]))), "最大SP")
		# 次の自分の行動（1 回）の後で解ける。ボスの攻撃は 0 ダメージにならない程度に弱いので HP を戻して比べる。
		hero.hp = int(c[2])
		_until_turn_of(battle, hero)
		battle.resolve_pending_ally_action({"type": "defend"})
		assert_false(hero.awakened)
		assert_eq(hero.max_hp, 650)
		assert_eq(hero.hp, int(c[3]), "解除で割合のまま戻る")
		assert_eq([hero.atk, hero.spd, hero.max_sp], [240, 100, 100], "覚醒していない時の値へ戻る")

func test_sp_is_paid_before_the_multiplier_and_keeps_its_ratio() -> void:
	# 最大SP 100・SP 80 で、最大SPの70% = 70 を払って 10/100 → ×10 で 100/1000。
	var battle := _battle(["hero"], {"hero": {"awakening_multiplier": 10.0}})
	var hero := _unit(battle, "hero")
	_until_turn_of(battle, hero)
	hero.sp = 80
	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_awakening", "target_id": -1})
	assert_eq([hero.sp, hero.max_sp], [100, 1000])
	assert_eq(float(log[0].get("awakening_multiplier", 0.0)), 10.0)
	assert_eq(int(log[0].get("awakening_turns", 0)), 3)
	var state: Dictionary = log[0]["visual_state"]["party"][str(hero.id)]
	assert_true(bool(state["awakened"]))
	assert_eq(int(state["awakening_turns_left"]), 3)
	assert_eq([int(state["sp"]), int(state["max_sp"])], [100, 1000], "表示の状態も同じ値")

func test_insufficient_sp_does_not_awaken_or_spend_the_turn() -> void:
	var battle := _battle(["hero"])
	var hero := _unit(battle, "hero")
	_until_turn_of(battle, hero)
	hero.sp = 69
	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_awakening", "target_id": -1})
	assert_true(bool(log[0].get("action_voided", false)))
	assert_eq(str(log[0].get("reason", "")), "insufficient_sp")
	assert_false(hero.awakened)
	assert_eq(hero.sp, 69)
	assert_eq(battle.pending_ally_id(), hero.id, "手番はそのまま")

func test_tank_awakening_uses_its_own_sp() -> void:
	var battle := _battle(["tank"])
	var tank := _unit(battle, "tank")
	assert_true(tank.has_sp_resource())
	assert_eq(int(_skill(tank).get("sp_cost", -1)), RBMDataLoader.awakening_sp_cost(tank.base_max_sp, 70))

# --- 持続・重ねがけ・解除 ---

func test_duration_counts_from_the_next_own_action() -> void:
	for turns in [1, 3, 99]:
		var battle := _battle(["hero"], {"hero": {"awakening_turns": turns}})
		var hero := _unit(battle, "hero")
		_awaken(battle, hero)
		assert_eq(hero.awakening_turns_left, turns, "発動した行動は数えない")
		var ended_after := -1
		for action in range(1, turns + 2):
			_until_turn_of(battle, hero)
			var log := battle.resolve_pending_ally_action({"type": "defend"})
			var ended := false
			for entry in log:
				if str(entry.get("action", "")) == "awakening_end":
					ended = true
					assert_eq(int(entry.get("actor", -1)), hero.id)
					assert_false(bool(entry["visual_state"]["party"][str(hero.id)]["awakened"]), "解けた時の表示")
			if ended:
				ended_after = action
				break
			assert_true(hero.awakened, "%d ターン中の %d 回目の後も覚醒中" % [turns, action])
			assert_eq(hero.awakening_turns_left, turns - action)
		assert_eq(ended_after, turns, "%d 回目の自分の行動の後で解ける" % turns)
		assert_false(hero.awakened)

func test_cannot_awaken_again_while_awakened_but_can_after_it_ends() -> void:
	var battle := _battle(["hero"], {"hero": {"awakening_turns": 1, "awakening_sp_percent": 0}})
	var hero := _unit(battle, "hero")
	_awaken(battle, hero)
	_until_turn_of(battle, hero)
	var sp_before := hero.sp
	var again := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_awakening", "target_id": -1})
	assert_true(bool(again[0].get("action_voided", false)))
	assert_eq(str(again[0].get("reason", "")), "already_awakened")
	assert_eq(hero.sp, sp_before, "SP を払わない")
	assert_eq(battle.pending_ally_id(), hero.id, "手番を使わない")
	assert_true(RBMBattleUiKit.skill_is_disabled(_skill(hero), hero))
	assert_string_contains(RBMBattleUiKit.skill_row_text(_skill(hero), hero), "（覚醒中）")
	battle.resolve_pending_ally_action({"type": "defend"})
	assert_false(hero.awakened)
	assert_false(RBMBattleUiKit.skill_is_disabled(_skill(hero), hero))
	_awaken(battle, hero)
	assert_true(hero.awakened, "解けた後はもう一度覚醒できる")
	assert_eq(hero.awakening_turns_left, 1, "再覚醒で残りは設定の回数に戻る")
	assert_eq(hero.max_hp, 975, "倍率は重ならない（元の値 × 1.5）")

func test_other_allies_are_not_affected() -> void:
	var battle := _battle(["hero", "butler", "healer"], {"hero": {"awakening_multiplier": 4.0}})
	var butler := _unit(battle, "butler")
	var healer := _unit(battle, "healer")
	var before := [butler.max_hp, butler.atk, butler.spd, butler.max_sp, healer.max_hp, healer.atk, healer.spd, healer.max_sp]
	_awaken(battle, _unit(battle, "hero"))
	assert_eq([butler.max_hp, butler.atk, butler.spd, butler.max_sp, healer.max_hp, healer.atk, healer.spd, healer.max_sp], before)
	assert_false(butler.awakened or healer.awakened)

func test_hp_and_sp_changes_while_awakened_are_kept_as_a_ratio_on_end() -> void:
	# 覚醒中（×10）に被弾・回復・SP 回復で値が動いても、解除はその時点の割合で戻る（400/1000 → 40/100 と同じ考え方）。
	# 勇者は ×10 で少女より速くなり、2ラウンド目から先に動く（少女の番まで進める間に勇者の防御が1回数えられる）。
	var battle := _battle(["hero", "healer"], {"hero": {"awakening_multiplier": 10.0, "awakening_turns": 3}})
	var hero := _unit(battle, "hero")
	var healer := _unit(battle, "healer")
	_awaken(battle, hero)
	assert_eq([hero.hp, hero.max_hp], [6500, 6500])
	hero.hp = 2600
	_until_turn_of(battle, healer)
	battle.resolve_pending_ally_action({"type": "skill", "skill_id": "healer_heal_single", "target_id": hero.id})
	assert_eq(hero.hp, 3000, "回復は覚醒中の最大HPまで（400 回復）")
	hero.sp = 300
	_until_turn_of(battle, hero)
	battle.resolve_pending_ally_action({"type": "attack"})
	assert_eq(hero.sp, 310, "通常攻撃の SP +10 も覚醒中の最大SP の範囲で")
	_until_turn_of(battle, hero)
	battle.resolve_pending_ally_action({"type": "defend"})
	assert_false(hero.awakened)
	assert_eq([hero.hp, hero.max_hp], [300, 650], "3000/6500 → 300/650")
	assert_eq([hero.sp, hero.max_sp], [31, 100], "310/1000 → 31/100")

func test_heal_reaching_full_hp_while_awakened_and_large_values_at_ten_times() -> void:
	var battle := _battle(["tank"], {"tank": {"awakening_multiplier": 10.0, "awakening_sp_percent": 0}})
	var tank := _unit(battle, "tank")
	_awaken(battle, tank)
	assert_eq([tank.hp, tank.max_hp, tank.atk, tank.spd, tank.max_sp], [9500, 9500, 2000, 1400, 1000])
	assert_eq(tank.heal(99999), 0, "満タンからは増えない")
	tank.hp = 1
	assert_eq(tank.heal(99999), 9499, "回復は覚醒中の最大HPで止まる")

func test_downed_ends_awakening_and_reverts_stats() -> void:
	var battle := _battle(["hero", "tank"])
	var hero := _unit(battle, "hero")
	_awaken(battle, hero)
	assert_true(hero.awakened)
	battle._compute_and_apply_damage(battle.boss, hero, 100000.0, RBMConstants.Attribute.NEUTRAL, false)
	assert_true(hero.is_downed())
	assert_false(hero.awakened)
	assert_eq(hero.hp, 0)
	assert_eq([hero.max_hp, hero.atk, hero.spd, hero.max_sp], [650, 240, 100, 100])
	assert_eq(hero.awakening_turns_left, 0)

func test_coexists_with_atk_buff_and_does_not_touch_it() -> void:
	var battle := _battle(["hero"], {"hero": {"awakening_turns": 1, "awakening_sp_percent": 0}})
	var hero := _unit(battle, "hero")
	_until_turn_of(battle, hero)
	battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_flame_wrap", "target_id": -1})
	var buff: Dictionary = hero.timed_effects.get("atk_buff", {}).duplicate(true)
	assert_false(buff.is_empty())
	_awaken(battle, hero)
	assert_eq(hero.atk, 360, "覚醒は ATK の元の値を変える（強化は別に掛かる）")
	assert_eq(hero.timed_effects.get("atk_buff", {}), buff, "強化は残る")
	var lines := RBMBattleUiKit.unit_state_lines(hero, battle)
	assert_true(lines.has("覚醒 ×1.5　残り1ターン"), str(lines))
	assert_true(lines.any(func(l): return str(l).begins_with("ATK強化")), str(lines))
	_until_turn_of(battle, hero)
	battle.resolve_pending_ally_action({"type": "defend"})
	assert_false(hero.awakened)
	assert_eq(hero.atk, 240)
	assert_eq(hero.timed_effects.get("atk_buff", {}), buff, "解除でも強化には触れない")

func test_spd_change_reorders_from_the_next_round_only() -> void:
	# 勇者 SPD 100 < ボス 150。×2 の覚醒で 200 になり、次のラウンドから勇者が先。
	var battle := _battle(["hero"], {"hero": {"awakening_multiplier": 2.0, "awakening_turns": 5}}, 150)
	assert_eq(battle.turn_order, ["boss", "ally:0"] as Array[String])
	var hero := _unit(battle, "hero")
	_awaken(battle, hero)
	assert_eq(battle.turn_order, ["boss", "ally:0"] as Array[String], "ラウンドの途中では並べ替えない")
	_until_turn_of(battle, hero)
	assert_eq(battle.turn_order, ["ally:0", "boss"] as Array[String], "次のラウンドから反映")

# --- REWIND・保存 ---

func test_snapshot_restore_round_trips_awakening() -> void:
	var battle := _battle(["hero"], {"hero": {"awakening_multiplier": 2.0}}, 150)
	var hero := _unit(battle, "hero")
	_until_turn_of(battle, hero)
	var before := battle.snapshot()
	battle.resolve_pending_ally_action({"type": "skill", "skill_id": "hero_awakening", "target_id": -1})
	_until_turn_of(battle, hero)
	var during := battle.snapshot()
	assert_true(bool(during["units"]["0"]["awakened"]))
	battle.restore(before)
	assert_false(hero.awakened)
	assert_eq([hero.max_hp, hero.atk, hero.spd, hero.max_sp], [650, 240, 100, 100])
	assert_eq(battle.turn_order, ["boss", "ally:0"] as Array[String])
	battle.restore(during)
	assert_true(hero.awakened)
	assert_eq([hero.max_hp, hero.atk, hero.spd, hero.max_sp], [1300, 480, 200, 200])
	assert_eq(hero.awakening_turns_left, 3)
	assert_eq(battle.turn_order, ["ally:0", "boss"] as Array[String])
	# 古い形の（覚醒のキーが無い）スナップショットは、覚醒していない状態として戻す。
	var legacy := before.duplicate(true)
	for key in ["max_hp", "atk", "spd", "max_sp", "awakened", "awakening_multiplier", "awakening_turns_left", "awakening_fresh"]:
		(legacy["units"]["0"] as Dictionary).erase(key)
	legacy.erase("turn_order")
	battle.restore(during)
	battle.restore(legacy)
	assert_false(hero.awakened)
	assert_eq([hero.max_hp, hero.atk, hero.spd, hero.max_sp], [650, 240, 100, 100])

func test_base_stats_are_not_written_back_to_the_definition() -> void:
	var definition := _definition(["hero"], {"hero": {"awakening_multiplier": 3.0}})
	var original := definition.duplicate(true)
	var battle: RBMBattle = RBMDefinitionLoader.start_battle(definition, 1)["battle"]
	_awaken(battle, _unit(battle, "hero"))
	assert_eq(definition, original)
	var again: RBMBattle = RBMDefinitionLoader.start_battle(definition, 1)["battle"]
	var hero := _unit(again, "hero")
	assert_false(hero.awakened)
	assert_eq([hero.max_hp, hero.atk, hero.spd, hero.max_sp], [650, 240, 100, 100])

func test_simple_draft_uses_fixed_values_and_new_members_get_the_skill() -> void:
	var draft := RBMCreatorDraft.new()
	draft.add_party_character("hero")
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_true(draft.is_ally_skill_allowed("hero", "hero_awakening"), "新しく入れた味方は覚醒も ON")
	var entry: Dictionary = draft.to_definition()["party"][0]
	assert_false(entry.has("skill_overrides"), "SIMPLE は固定の値（性能調整を出さない）")
	assert_true((entry["allowed_skill_ids"] as Array).has("hero_awakening"))

func test_hardcore_values_are_saved_and_restored() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "覚醒保存"
	draft.hp = 9999
	draft.atk = 1
	draft.spd = 1
	draft.add_skill({"name": "待機攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.0})
	draft.add_party_character("samurai")
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_true(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_multiplier", 2.3000000001))
	assert_true(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_turns", 99))
	assert_true(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_sp_percent", 0))
	assert_false(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_multiplier", 10.1))
	assert_false(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_turns", 0))
	assert_false(draft.set_ally_skill_override("samurai", "samurai_awakening", "awakening_sp_percent", 101))
	var values: Dictionary = draft.ally_overrides["samurai"]["skills"]["samurai_awakening"]
	assert_eq(values, {"awakening_multiplier": 2.3, "awakening_turns": 99, "awakening_sp_percent": 0})
	var saved := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(saved.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(saved["stage_id"]))
	assert_true(bool(loaded.get("ok", false)), str(loaded))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded["draft_data"])
	assert_eq(restored.ally_overrides["samurai"]["skills"]["samurai_awakening"], values)
	assert_true(restored.is_ally_skill_allowed("samurai", "samurai_awakening"))
	var battle: RBMBattle = RBMDefinitionLoader.start_battle(restored.to_definition(), 3)["battle"]
	var skill := _skill(_unit(battle, "samurai"))
	assert_eq([float(skill["awakening_multiplier"]), int(skill["awakening_turns"]), int(skill["sp_cost"])], [2.3, 99, 0])

func test_awakening_off_alone_is_not_custom_so_old_saves_stay_plain() -> void:
	var draft := RBMCreatorDraft.new()
	draft.add_party_character("hero")
	draft.ally_allowed_skill_ids["hero"] = ["hero_slash", "hero_blaze_all", "hero_flame_wrap", "hero_burst_slash"]
	assert_false(draft.is_ally_customized("hero"), "覚醒の無い古い保存は CUSTOM にしない")
	assert_false((draft.to_definition()["party"][0]["allowed_skill_ids"] as Array).has("hero_awakening"), "古い保存は覚醒 OFF のまま")
	draft.set_ally_skill_allowed("hero", "hero_slash", false)
	assert_true(draft.is_ally_customized("hero"), "ほかの技を外せば今までどおり CUSTOM")

func test_disabled_awakening_is_not_in_battle() -> void:
	var draft := RBMCreatorDraft.new()
	draft.add_party_character("healer")
	draft.set_ally_skill_allowed("healer", "healer_awakening", false)
	var entry: Dictionary = draft.to_definition()["party"][0]
	assert_false((entry["allowed_skill_ids"] as Array).has("healer_awakening"))
	var definition := _definition(["healer"])
	definition["party"][0]["allowed_skill_ids"] = entry["allowed_skill_ids"]
	var battle: RBMBattle = RBMDefinitionLoader.start_battle(definition, 1)["battle"]
	assert_true(_skill(_unit(battle, "healer")).is_empty(), "OFF の時は戦闘の技に無い")

# --- 戦闘UIの文字 ---

func test_battle_texts() -> void:
	var battle := _battle(["butler"], {"butler": {"awakening_multiplier": 2.5, "awakening_turns": 4}})
	var butler := _unit(battle, "butler")
	var skill := _skill(butler)
	var details := RBMBattleUiKit.skill_detail_lines(skill, true)
	assert_true(details.has("消費SP：%d" % int(skill["sp_cost"])), str(details))
	assert_true(details.has("効果：全能力 ×2.5"), str(details))
	assert_true(details.has("効果時間：4ターン（次の自分の行動から）"), str(details))
	var master_skill := {"effect": "ally_awakening", "awakening_multiplier": 1.5, "awakening_turns": 3, "awakening_sp_percent": 70}
	assert_true(RBMBattleUiKit.skill_detail_lines(master_skill, true).has("消費SP：最大SPの70%"))
	var log := _awaken(battle, butler)
	var described := RBMBattleUiKit.describe_entry(log[0], battle)
	assert_eq(described["headline"], "覚醒")
	assert_true((described["result_lines"] as Array).has("覚醒！ 能力 ×2.5　4ターン"), str(described))
	var end_entry := {"actor": butler.id, "action": "awakening_end"}
	assert_eq(RBMBattleUiKit.describe_entry(end_entry, battle)["headline"], "覚醒が解けた")
	var latest := RBMBattleUiKit.format_latest_info([log[0], end_entry], battle)
	assert_true(latest.contains("覚醒！"), "最新の情報は解けた知らせで直前の結果を隠さない: %s" % latest)

func test_party_card_chip_follows_state() -> void:
	var card := PanelContainer.new()
	card.name = "PartyRow_2"
	var chip := PanelContainer.new()
	chip.name = "PartyRowAwakening_2"
	var text := Label.new()
	text.name = "PartyRowAwakeningText_2"
	chip.add_child(text)
	card.add_child(chip)
	add_child_autofree(card)
	RBMBattlePresenter.apply_awakening_chip(card, 2, true, 3)
	assert_true(chip.visible)
	assert_eq(text.text, "覚醒 残り3")
	RBMBattlePresenter.apply_awakening_chip(card, 2, false, 0)
	assert_false(chip.visible)

# --- 演出のつなぎ（表示だけ。戦闘の状態を変えない） ---

func _stage_fixture(character_id: String) -> Dictionary:
	var battle := _battle([character_id])
	var unit := _unit(battle, character_id)
	_until_turn_of(battle, unit)
	var stage := Stage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(battle, "appearance_knight")
	stage.set_state(battle.presentation_state())
	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "%s_awakening" % character_id, "target_id": -1})
	return {"battle": battle, "stage": stage, "entry": log[0], "unit": unit}

func test_presentation_plays_once_with_impact_at_release_for_all_five() -> void:
	for character_id in IDS:
		var f := _stage_fixture(character_id)
		var stage: Control = f.stage
		var snapshot: Dictionary = f.battle.snapshot().duplicate(true)
		var hits: Array = []
		var done: Array = []
		stage.impact.connect(func(e): hits.append(e))
		stage.finished.connect(func(): done.append(true))
		stage.play_entry(f.entry, _skill(f.unit))
		assert_true(stage._skill_presentation is AllyAwakening, character_id)
		var presentation = stage._skill_presentation
		var release: float = presentation._sequence.release_time
		stage._tween.custom_step(release - 0.05)
		assert_eq(hits.size(), 0, "%s: 解放の前は結果を出さない" % character_id)
		assert_false(stage._visuals["0"].visible, "本体は発動の演出が描く")
		if character_id == "samurai":
			assert_eq(presentation._frame, "s:18", "侍は納刀のまま")
		stage._tween.custom_step(0.1)
		assert_eq(hits.size(), 1, "%s: 解放で1回" % character_id)
		stage._tween.custom_step(presentation.duration)
		await get_tree().process_frame
		assert_eq(hits.size(), 1)
		assert_eq(done.size(), 1)
		assert_null(stage._skill_presentation)
		assert_true(stage._visuals["0"].visible)
		assert_eq(stage.scale, Vector2.ONE, "寄りを戻す")
		assert_eq(f.battle.snapshot(), snapshot, "演出は戦闘の状態を変えない")

func test_scenes_are_the_approved_ones_and_keep_the_codex_sound_timing() -> void:
	# 2026-10-28 ユーザーの決定: 少女は Codex の版、ほか4人は新しい版。音（Codex の charge/release）の解放の時刻と長さは同じ。
	assert_eq(AllyAwakening.SCENES["healer"], "res://ally_awakening/scenes/healer.tscn")
	for id in IDS:
		var scene: Node2D = (load(AllyAwakening.SCENES[id]) as PackedScene).instantiate()
		var codex: Node2D = (load("res://ally_awakening/scenes/%s.tscn" % id) as PackedScene).instantiate()
		assert_eq(scene.character_id, id)
		assert_eq([scene.duration, scene.release_time], [codex.duration, codex.release_time], id)
		if id != "healer":
			assert_true(str(AllyAwakening.SCENES[id]).begins_with("res://src/bossmaker/visuals/ally_awakening/"), id)
		scene.free()
		codex.free()

func test_aura_follows_awakened_state() -> void:
	var f := _stage_fixture("hero")
	var stage: Control = f.stage
	stage.set_state(f.entry["visual_state"])
	var auras: Dictionary = stage._ally_auras.auras()
	assert_true(auras.has("0"))
	assert_true(bool(auras["0"].active))
	assert_eq(str(auras["0"].character_id), "hero")
	var ended := (f.entry["visual_state"] as Dictionary).duplicate(true)
	ended["party"]["0"]["awakened"] = false
	stage.set_state(ended)
	assert_false(bool(stage._ally_auras.auras()["0"].active), "解けたら消す")
	stage.configure(null)
	assert_true(stage._ally_auras.auras().is_empty())

func test_cancel_mid_presentation_restores_stage() -> void:
	var f := _stage_fixture("tank")
	var stage: Control = f.stage
	stage.play_entry(f.entry, _skill(f.unit))
	stage._tween.custom_step(1.2)
	assert_eq(stage.scale, Vector2(2, 2), "寄りの間")
	stage.hide()
	await get_tree().process_frame
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_eq(stage.scale, Vector2.ONE)
	assert_true(stage._visuals["0"].visible)
