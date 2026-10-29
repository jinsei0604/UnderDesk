extends GutTest

## HARDCORE 限定の勝利条件（2026-10-29 ユーザー確定）のテスト。行動の発動条件とは別の機能。
## - ボスを撃破する（通常・初期値・勝利条件の無い旧データ）: 今までどおり HP0 で勝利
## - 指定ターンを生き残る: HP0 でも戦闘は続き、ボスは行動を続ける。N ターン目の終わり（ターン終了時に追加する
##   行動の後）に味方が1人でも生きていれば勝利、それまでに全滅すれば敗北。ターン数は 1〜99（初期値 10）
## - HP0 になった時の「まだ［ボス名］は倒れない…！！」は1戦闘に1回だけ（回復して再び0になっても出さない）
## - HARDCORE は6STEP（行動の次に「勝利条件」）、SIMPLE は今までどおり5STEP

const ATTACK := {"type": "attack"}
const DEFEND := {"type": "defend"}

func after_each() -> void:
	await get_tree().process_frame

func _party_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json"))
	return out

func _boss_def(hp: int, atk: int, turn_actions: Array, victory := {}) -> Dictionary:
	var def := {
		"id": "victory_boss", "display_name": "竜王", "hp": hp, "atk": atk, "spd": 10,
		"skills": [
			{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "boss_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 100},
		],
		"normal_action_candidates": [],
		"turn_actions": turn_actions,
	}
	if not victory.is_empty():
		def["victory_condition"] = victory
	return def

func _fixed(skill_id: String) -> Dictionary:
	return {"mode": "fixed", "entries": [{"skill_id": skill_id}]}

func _survive(turns: int) -> Dictionary:
	return {"type": "survive_turns", "turns": turns}

## 1ラウンド分（味方の入力も含めて）を進め、そのラウンドの全ログを返す。
func _round(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	var start_turn := battle.current_turn
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn or not battle.is_waiting_for_ally_action():
			break
		log.append_array(battle.resolve_pending_ally_action(action))
	return log

func _actions(log: Array, actor: Variant = "boss") -> Array:
	var out := []
	for entry in log:
		if str(entry.get("actor", "")) == str(actor):
			out.append(str(entry.get("action", "")) if str(entry.get("action", "")) != "skill" else str(entry.get("skill_id", "")))
	return out

# ---------------------------------------------------------------------------
# 戦闘
# ---------------------------------------------------------------------------

func test_survival_boss_keeps_acting_at_zero_hp_and_the_allies_win_at_the_end_of_turn_n() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_hit")], _survive(3)), 1)
	var round1 := _round(battle)
	assert_eq(battle.boss.hp, 0, "the hero's first attack takes the boss to 0")
	assert_false(battle.battle_over, "HP0 does not end a survival battle")
	assert_false(battle.boss.is_downed(), "the boss is not treated as downed")
	assert_true(_actions(round1).has("boss_hit"), "the boss still acts in the turn it reached HP0")
	assert_eq(_actions(round1).count("endure"), 1)
	var round2 := _round(battle)
	assert_false(battle.battle_over)
	assert_true(_actions(round2).has("boss_hit"), "turn 2: the boss attacks at HP0")
	assert_false(_actions(round2, 0).has("none"), "the hero can still attack the HP0 boss: %s" % [round2])
	assert_eq(_actions(round2).count("endure"), 0, "no repeat while it stays at HP0")
	var round3 := _round(battle)
	assert_true(_actions(round3).has("boss_hit"), "turn 3 is played in full")
	assert_true(battle.battle_over, "won at the end of turn 3")
	assert_eq(battle.winner, "ally")
	assert_eq(battle.current_turn, 3)

func test_survival_battle_is_lost_when_the_party_falls_before_turn_n() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(99999, 99999, [_fixed("boss_hit")], _survive(5)), 1)
	_round(battle, DEFEND)
	assert_true(battle.battle_over)
	assert_eq(battle.winner, "boss")
	assert_eq(battle.current_turn, 1)

func test_survival_win_does_not_need_the_boss_at_zero() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(99999, 1, [_fixed("boss_hit")], _survive(2)), 1)
	_round(battle, DEFEND)
	assert_false(battle.battle_over)
	_round(battle, DEFEND)
	assert_true(battle.battle_over)
	assert_eq(battle.winner, "ally")
	assert_gt(battle.boss.hp, 0)

func test_normal_victory_still_ends_at_zero_hp_without_the_message() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_hit")]), 1)
	var log := _round(battle)
	assert_true(battle.battle_over)
	assert_eq(battle.winner, "ally")
	assert_true(battle.boss.is_downed())
	assert_eq(_actions(log).count("endure"), 0)
	assert_false(_actions(log).has("boss_hit"), "a defeated boss does not act")

func test_the_message_is_shown_only_once_per_battle_even_after_healing() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_heal"), _fixed("boss_hit")], _survive(6)), 1)
	var total := []
	for _i in range(4):
		total.append_array(_round(battle))
	assert_gt(_actions(total).count("boss_heal"), 0, "the boss healed back above 0 at least once")
	assert_eq(battle.boss.hp, 0, "and the hero brought it back to 0 again (heal 100 < hero 240)")
	assert_eq(_actions(total).count("endure"), 1, "once per battle")

func test_rewind_restores_whether_the_message_was_shown() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_hit")], _survive(5)), 1)
	var before := battle.snapshot()
	_round(battle)
	assert_true(battle.endure_announced)
	battle.restore(before)
	assert_false(battle.endure_announced)

func test_the_message_names_the_boss_without_a_speaker_prefix() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_hit")], _survive(5)), 1)
	var log := _round(battle)
	var endure := {}
	for entry in log:
		if str(entry.get("action", "")) == "endure":
			endure = entry
	assert_false(endure.is_empty())
	var text := RBMBattleUiKit.format_latest_info([endure], battle)
	assert_eq(text, tr("まだ%sは倒れない…！！") % "竜王")
	assert_true(RBMBattleUiKit.format_log_window_text([endure] as Array[Dictionary], battle).contains(tr("まだ%sは倒れない…！！") % "竜王"))

func test_english_message_is_natural() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate("まだ%sは倒れない…！！") % "Dragon King", "Dragon King won't fall yet…!!")
	TranslationServer.set_locale(previous)

# ---------------------------------------------------------------------------
# 下書き・定義・保存
# ---------------------------------------------------------------------------

func _draft() -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = "竜王"
	d.hp = 1000
	d.atk = 100
	d.spd = 50
	d.add_skill({"name": "単体攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	d.add_party_character("hero")
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	d.add_turn_action({"mode": "fixed", "entries": [{"skill_id": str(d.skills[0].get("skill_id", ""))}]})
	return d

func test_default_is_defeat_the_boss_and_old_saves_without_the_key_stay_normal() -> void:
	var d := _draft()
	assert_false(d.is_survival_victory())
	assert_false(d.to_definition()["boss"].has("victory_condition"))
	var data: Dictionary = d.to_saved_dict()
	data.erase("victory_condition")  # 勝利条件より前に保存された stage
	var old := RBMCreatorDraft.new()
	old.restore_from_saved_dict(data)
	assert_false(old.is_survival_victory())
	assert_true(RBMLocalStageRepository.validate_draft_shape_for_online(data))

func test_survival_round_trips_through_save_definition_and_battle() -> void:
	var d := _draft()
	d.set_victory_survive_turns(12)
	var data: Dictionary = JSON.parse_string(JSON.stringify(d.to_saved_dict()))
	assert_true(RBMLocalStageRepository.validate_draft_shape_for_online(data))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(data)
	assert_eq(restored.survive_turns(), 12)
	var result := RBMDefinitionLoader.resolve(restored.to_definition())
	assert_true(bool(result.get("ok", false)), "errors: %s" % [result.get("errors", [])])
	assert_eq(result["boss_def"]["victory_condition"], {"type": "survive_turns", "turns": 12})
	var start := RBMDefinitionLoader.start_battle(restored.to_definition(), 3)
	assert_eq((start["battle"] as RBMBattle).survive_turns, 12)

func test_turns_are_limited_to_1_to_99() -> void:
	var d := _draft()
	d.set_victory_survive_turns(0)
	assert_eq(d.survive_turns(), 1)
	d.set_victory_survive_turns(500)
	assert_eq(d.survive_turns(), 99)
	var definition := d.to_definition()
	definition["boss"]["victory_condition"] = {"type": "survive_turns", "turns": 100}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)), "the loader rejects 100")
	definition["boss"]["victory_condition"] = {"type": "survive_turns", "turns": 0}
	assert_false(bool(RBMDefinitionLoader.resolve(definition).get("ok", true)), "the loader rejects 0")

func test_simple_never_uses_a_special_victory() -> void:
	var d := _draft()
	d.set_victory_survive_turns(10)
	d.discard_advanced_settings_and_revert_to_simple()
	assert_false(d.is_survival_victory())
	assert_false(d.to_definition()["boss"].has("victory_condition"))

func test_clear_record_stays_valid_for_normal_bosses_and_tracks_the_victory_condition() -> void:
	var d := _draft()
	assert_false(d.battle_content_snapshot().has("victory_condition"), "old clear records of normal bosses stay valid")
	d.record_clear_check_success()
	d.set_victory_survive_turns(10)
	assert_false(d.is_clear_check_currently_valid(), "changing the win condition needs a new clear check")
	d.record_clear_check_success()
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(d.to_saved_dict())
	restored.restore_clear_check_snapshot(JSON.parse_string(JSON.stringify(d.clear_check_snapshot_for_save())))
	assert_true(restored.is_clear_check_currently_valid())

func test_win_condition_text_follows_the_setting() -> void:
	var d := _draft()
	assert_eq(d.win_condition_text(), tr("ボスのHPを0にする"))
	d.set_victory_survive_turns(10)
	assert_eq(d.win_condition_text(), tr("%dターン生き残る") % 10)

# ---------------------------------------------------------------------------
# 作成画面: HARDCORE は6STEP（行動の次に勝利条件）、SIMPLE は5STEP
# ---------------------------------------------------------------------------

func _creator(mode: String) -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.draft.boss_name = "竜王"
	creator.draft.set_creator_mode(mode)
	creator.go_to_step(1)
	return creator

func test_hardcore_has_six_steps_with_the_victory_step_after_actions() -> void:
	var creator := _creator(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(creator.step_count(), 6)
	assert_eq(creator.step_names(), ["外見と基本情報", "能力", "行動", "勝利条件", "攻略パーティ", "最終確認"])
	creator.go_to_step(4)
	assert_true(creator._current_view() is RBMCreatorStepVictory)
	assert_eq(creator._header.step_label.text, "STEP 4 / 6")
	creator.go_to_step(5)
	assert_true(creator._current_view() is RBMCreatorStep5Party)
	creator.go_to_step(6)
	assert_true(creator._current_view() is RBMCreatorStep7Summary)
	assert_eq(creator._step_nav_column.step_count(), 5, "the left list shows the five editing steps")
	var summary := creator._current_view() as RBMCreatorStep7Summary
	assert_eq((summary.find_child("CreationStepNameLabel_4", true, false) as Label).text, tr("勝利条件"))

func test_simple_keeps_five_steps_and_has_no_victory_step() -> void:
	var creator := _creator(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_eq(creator.step_count(), 5)
	assert_false(creator.step_names().has("勝利条件"))
	creator.go_to_step(4)
	assert_true(creator._current_view() is RBMCreatorStep5Party)
	assert_eq(creator._header.step_label.text, "STEP 4 / 5")
	assert_eq(creator._step_nav_column.step_count(), 4)

func test_victory_step_sets_and_clears_the_survival_condition() -> void:
	var creator := _creator(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.go_to_step(4)
	var view := creator._current_view() as RBMCreatorStepVictory
	var defeat := view.find_child("VictoryDefeatBossButton", true, false) as Button
	var survive := view.find_child("VictorySurviveTurnsButton", true, false) as Button
	var spin := view.find_child("SurviveTurnsSpin", true, false) as SpinBox
	assert_true(defeat.button_pressed, "defeat the boss is the default")
	assert_false(view.find_child("SurviveTurnsBlock", true, false).visible)
	survive.pressed.emit()
	assert_true(creator.draft.is_survival_victory())
	assert_eq(creator.draft.survive_turns(), 10, "default 10 turns")
	assert_true(view.find_child("SurviveTurnsBlock", true, false).visible)
	spin.value = 25
	assert_eq(creator.draft.survive_turns(), 25)
	assert_eq(spin.min_value, 1.0)
	assert_eq(spin.max_value, 99.0)
	defeat.pressed.emit()
	assert_false(creator.draft.is_survival_victory())
	assert_true(view.is_step_valid())

# ---------------------------------------------------------------------------
# 2026-10-29 正式採用: 耐久勝利の演出・記録・非公開の勝利条件
# ---------------------------------------------------------------------------

const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")

func test_a_survival_win_ends_with_a_survived_entry_and_a_normal_win_does_not() -> void:
	var battle := RBMBattle.new(_party_defs(), _boss_def(99999, 1, [_fixed("boss_hit")], _survive(2)), 1)
	_round(battle, DEFEND)
	var last_round := _round(battle, DEFEND)
	var last: Dictionary = last_round[-1]
	assert_eq(str(last.get("action", "")), "survived", "the win is announced as its own entry (after the turn-end actions)")
	assert_true(bool(last["visual_state"]["battle_over"]))
	assert_eq(str(last["visual_state"]["winner"]), "ally")
	assert_eq(RBMBattleUiKit.format_latest_info([last], battle), tr("耐久成功！"), "no turn count is written")
	var normal := RBMBattle.new(_party_defs(), _boss_def(1, 1, [_fixed("boss_hit")]), 1)
	assert_eq(_actions(_round(normal)).count("survived"), 0)

func test_survival_presentations_can_be_swapped_per_boss_and_fall_back_to_the_common_one() -> void:
	assert_true(VictoryPlayer.SURVIVAL is Dictionary, "per-boss survival motions are registered here")
	for boss in ["slime", "dragon", "dragon_awakened", "musha", "gentleman_awakened", "plush", ""]:
		assert_eq(VictoryPlayer.survival_script(boss), VictoryPlayer.SURVIVAL_GENERIC, "%s uses the common survival presentation for now" % boss)
		assert_ne(VictoryPlayer.survival_script(boss), VictoryPlayer.defeat_script(boss), "%s never uses its defeat presentation for a survival win" % boss)
	assert_eq(VictoryPlayer.victory_keys("dragon_awakened", true), VictoryPlayer.COMMON_SOUNDS, "no defeat-only sound (e.g. the detonation) is played")
	assert_true(VictoryPlayer.victory_keys("dragon_awakened").has("enc:dragon_detonation"), "the normal victory keeps its own sounds")

func _survival_definition(turns: int) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_dragon"
	draft.boss_name = "竜王"
	draft.hp = 99999
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]:
		draft.add_party_character(id)
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var id := draft.add_skill({"name": "QA attack", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_turn_action({"mode": "fixed", "entries": [{"skill_id": id}]})
	draft.set_victory_survive_turns(turns)
	return draft.to_definition()

func test_the_survival_win_shows_the_common_presentation_and_the_boss_does_not_fall() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	var wins := [0]
	view.challenge_won.connect(func(): wins[0] += 1)
	view.start_battle(_survival_definition(2), RBMBattleUiKit.ALL_VISIBLE, "appearance_dragon")
	for i in 40:
		if view.session.battle.battle_over:
			break
		view.act_defend(view.session.pending_ally_id())
	assert_true(view.session.battle.battle_over)
	assert_eq(view.session.battle.winner, "ally")
	assert_eq(wins[0], 1, "a survival win is recorded as a normal clear, once")
	var director: RBMEncounterDirector = view._encounter
	var stage: Control = view._battlefield_ally_row.get_meta("visual_stage")
	var boss_visual: Control = stage._visuals["boss"]
	director.begin_battle({"boss_name": "竜王", "author": "qa"})
	director.on_impact({"action": "survived", "visual_state": view.session.battle.presentation_state()})
	assert_true(director.holds_outcome(), "the result waits for the survival presentation")
	assert_true(director._victory.survival)
	assert_eq(director._victory.defeat.get_script(), VictoryPlayer.SURVIVAL_GENERIC)
	assert_true(boss_visual.visible, "no final blow: the boss is not hidden")
	assert_true(director.on_presentation_finished())
	for i in 5:
		await get_tree().process_frame
	assert_true(boss_visual.visible, "the boss keeps standing")
	director.cancel()
	await get_tree().process_frame
	view.refresh()
	assert_true(view._outcome_area.visible)

func test_the_normal_victory_still_uses_the_defeat_presentation() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	var definition := _survival_definition(2)
	definition["boss"].erase("victory_condition")
	definition["boss"]["hp"] = 1
	view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_dragon")
	for i in 20:
		if view.session.battle.battle_over:
			break
		view.act_attack(view.session.pending_ally_id())
	var director: RBMEncounterDirector = view._encounter
	director.begin_battle({"boss_name": "竜王", "author": "qa"})
	director.on_impact({"visual_state": view.session.battle.presentation_state()})
	assert_false(director._victory.survival)
	assert_eq(director._victory.defeat.get_script(), VictoryPlayer.defeat_script("dragon"))
	director.cancel()

func _confirm_text(draft: RBMCreatorDraft) -> String:
	var view := RBMChallengeConfirmView.new()
	add_child_autofree(view)
	view.open("qa_stage", draft)
	return view._win_condition_label.text

## 非公開なら、必要なターン数を挑戦前に見せない。公開なら見せる。
func test_a_hidden_win_condition_never_shows_the_turns() -> void:
	var d := _draft()
	d.set_victory_survive_turns(12)
	assert_true(_confirm_text(d).contains(tr("%dターン生き残る") % 12), "public: shown before the challenge")
	d.set_challenge_info_visible("win_condition", false)
	var hidden := _confirm_text(d)
	assert_true(hidden.contains(tr("非公開")))
	assert_false(hidden.contains("12"), "hidden: no turn count")
