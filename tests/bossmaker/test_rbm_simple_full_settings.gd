extends GutTest

## SIMPLE・HARDCORE 再設計（2026-10-29 ユーザー確定）のテスト。モードの差は「行動の設計の自由度」と「特殊勝利条件」だけにする。
## - SIMPLE でもボスの覚醒（4カテゴリの発動条件・ATK強化・持続ターン・HP回復）を HARDCORE と同じ画面で設定でき、戦闘で使う
## - SIMPLE でも味方の能力・技・覚醒の調整を編集でき、テストバトル・クリアチェック・挑戦（定義）の戦闘で使う
## - 行動が0件でも完成できる（SIMPLE: 通常行動0件・指定行動だけ／両方0件、HARDCORE: ターン0件）。勝手に行動を補わない
## - SIMPLE の指定行動はカード（左に発動ターン、番号・↑↓・一覧の編集/削除なし）、設定画面は「発動ターン」「発動タイミング」
## - 作成方法の選択画面の説明文、体験版でも SIMPLE の新しい設定が使える（HARDCORE は製品版のまま）

const ATTACK := {"type": "attack"}

func after_each() -> void:
	RBMEdition.reset_for_testing()
	await get_tree().process_frame

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## SIMPLE の最小のボス（竜＝覚醒できる外見）。
func _simple_draft(appearance := "appearance_dragon") -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	d.boss_name = "SIMPLE覚醒テスト"
	d.appearance_id = appearance
	d.hp = 1000
	d.atk = 100
	d.spd = 10
	var hit := d.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	d.normal_action_percentages[hit] = 100.0
	d.normal_actions_enabled = true
	d.add_party_character("hero")
	return d

func _awakening_at_half_hp() -> Dictionary:
	return {
		"conditions": [{"type": "hp_at_most", "percent": 50.0}],
		"condition_logic": "AND",
		"buff": {"buff_multiplier": 2.0, "duration_turns": 3},
		"heal": {"heal_mode": "fixed", "heal_fixed_amount": 300, "heal_percent": 0.0},
	}

## 1ラウンド分（味方の入力も含めて）を進め、そのラウンドの全ログを返す。
func _round(battle: RBMBattle) -> Array:
	var log: Array = []
	var start_turn := battle.current_turn
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn or not battle.is_waiting_for_ally_action():
			break
		log.append_array(battle.resolve_pending_ally_action(ATTACK))
	return log

func _boss_actions(log: Array) -> Array:
	var out := []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(str(entry.get("action", "")) if str(entry.get("action", "")) != "skill" else str(entry.get("skill_id", "")))
	return out

# ---------------------------------------------------------------------------
# ボスの覚醒（SIMPLE）
# ---------------------------------------------------------------------------

func test_simple_boss_awakening_goes_through_save_definition_and_battle() -> void:
	var d := _simple_draft()
	d.set_awakening(_awakening_at_half_hp())
	assert_true(d.step4_is_valid())
	var data: Dictionary = JSON.parse_string(JSON.stringify(d.to_saved_dict()))
	assert_true(RBMLocalStageRepository.validate_draft_shape_for_online(data), "公開の形の検査も通る")
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(data)
	assert_eq(restored.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	assert_true(restored.has_awakening(), "保存・読み込みで覚醒が残る")
	var definition := restored.to_definition()
	assert_eq(definition["boss"]["awakening"]["buff"], {"buff_multiplier": 2.0, "duration_turns": 3})
	assert_eq(int(definition["boss"]["awakening"]["heal_amount"]), 300)
	assert_true(restored.battle_content_snapshot()["awakening"].size() > 0, "クリアチェックの照合にも覚醒が入る")
	var start := RBMDefinitionLoader.start_battle(definition, 3)
	assert_true(start.has("battle"), str(start.get("errors", [])))
	var battle: RBMBattle = start["battle"]
	battle.boss.hp = 400  # 半分以下
	battle.boss.max_hp = 1000
	var log := _round(battle)
	assert_true(_boss_actions(log).has("awakening"), "条件を満たすと SIMPLE のボスも覚醒する: %s" % [_boss_actions(log)])
	assert_true(battle.is_awakened)

func test_simple_awakening_condition_problems_block_the_step_like_hardcore() -> void:
	var d := _simple_draft()
	d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 500.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	assert_false(d.step4_is_valid(), "条件の不備は HARDCORE と同じく止める")

func test_simple_list_opens_the_shared_hardcore_awakening_editor_and_comes_back() -> void:
	var creator := _new_creator()
	creator.draft.appearance_id = "appearance_dragon"
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	var simple := step3._simple_view
	var advanced := step3._advanced_view
	step3.refresh()
	assert_eq((simple.find_child("AwakeningHeader", true, false) as Label).text, tr("覚醒"))
	assert_false(_btn(simple, "AddAwakeningButton").disabled)
	_btn(simple, "AddAwakeningButton").pressed.emit()
	assert_true(advanced.visible and not simple.visible, "HARDCORE と同じ覚醒の設定を開く")
	assert_true(advanced._entry_view.visible)
	var categories := advanced.find_child("ConditionCategoryOption", true, false) as OptionButton
	assert_eq(categories.item_count, 4, "発動条件は4カテゴリ")
	for i in range(4):
		assert_eq(categories.get_item_text(i), tr(str(RBMActionPatternRules.CONDITION_CATEGORIES[i]["label"])))
	assert_true(step3.escape(), "Esc は開いている覚醒の画面が受ける")
	advanced._pending_conditions = [{"type": "turn_at_least", "turn": 3}]
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	assert_true(creator.draft.has_awakening())
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE, "モードは SIMPLE のまま")
	assert_true(simple.visible and not advanced.visible, "保存すると SIMPLE の一覧へ戻る")
	assert_not_null(simple.find_child("AwakeningCardButton", true, false), "一覧に覚醒のカードが出る")
	assert_false(_btn(simple, "AddAwakeningButton").visible)

func test_non_awakening_appearance_cannot_add_and_says_why() -> void:
	var creator := _new_creator()
	creator.draft.appearance_id = "appearance_slime"
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	step3.refresh()
	var simple := step3._simple_view
	assert_true(_btn(simple, "AddAwakeningButton").disabled)
	var note := simple.find_child("AwakeningUnsupportedNote", true, false) as Label
	assert_true(note.visible)
	assert_eq(note.text, tr("このボスの外見は覚醒に対応していません"))
	_btn(simple, "AddAwakeningButton").pressed.emit()
	assert_true(simple.visible, "押せない時は開かない")
	assert_false(creator.draft.has_awakening())

# ---------------------------------------------------------------------------
# 味方の調整（SIMPLE）
# ---------------------------------------------------------------------------

func test_simple_ally_stat_skill_and_awakening_tuning_reach_the_battle() -> void:
	var d := _simple_draft()
	assert_true(d.set_ally_stat_override("hero", "hp", 4321))
	assert_true(d.set_ally_stat_override("hero", "max_sp", 321))
	assert_true(d.set_ally_skill_override("hero", "hero_slash", "atk_multiplier", 3.0))
	assert_true(d.set_ally_skill_override("hero", "hero_awakening", "awakening_multiplier", 2.0))
	assert_true(d.set_ally_skill_override("hero", "hero_awakening", "awakening_turns", 5))
	assert_true(d.set_ally_skill_override("hero", "hero_awakening", "awakening_sp_percent", 40))
	var data: Dictionary = JSON.parse_string(JSON.stringify(d.to_saved_dict()))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(data)
	var resolved := RBMDefinitionLoader.resolve(restored.to_definition())
	assert_true(bool(resolved.get("ok", false)), str(resolved.get("errors", [])))
	var hero: Dictionary = resolved["ally_defs"][0]
	assert_eq(int(hero["hp"]), 4321)
	assert_eq(int(hero["max_sp"]), 321)
	var by_id := {}
	for skill in hero["skills"]:
		by_id[str(skill["id"])] = skill
	assert_eq(float(by_id["hero_slash"]["atk_multiplier"]), 3.0)
	assert_eq(float(by_id["hero_awakening"]["awakening_multiplier"]), 2.0)
	assert_eq(int(by_id["hero_awakening"]["awakening_turns"]), 5)
	assert_eq(int(by_id["hero_awakening"]["awakening_sp_percent"]), 40)
	var snapshot_party: Array = restored.battle_content_snapshot()["party"]
	assert_eq(int(snapshot_party[0]["hp"]), 4321, "クリアチェックの照合も調整した値")

func test_simple_ally_tuning_uses_the_same_limits_as_hardcore() -> void:
	var d := _simple_draft()
	assert_false(d.set_ally_stat_override("hero", "hp", RBMDefinitionLoader.BOSS_HP_MAX + 1), "SIMPLE 専用の上限は作らない（HARDCORE と同じ上限）")
	assert_true(d.set_ally_stat_override("hero", "hp", RBMDefinitionLoader.BOSS_HP_MAX))

func test_untuned_simple_boss_keeps_its_old_definition_and_clear_record() -> void:
	var d := _simple_draft()
	var before_definition := d.to_definition()
	assert_false((before_definition["party"][0] as Dictionary).has("stat_overrides"), "調整していなければ定義は今までと同じ")
	assert_false((before_definition["party"][0] as Dictionary).has("skill_overrides"))
	d.record_clear_check_success()
	assert_true(d.is_clear_check_currently_valid())
	var saved := RBMLocalStageRepository.save_new(d)
	var loaded := RBMLocalStageRepository.load_stage(str(saved.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	restored.restore_clear_check_snapshot(loaded.get("clear_check_data", {}))
	assert_true(restored.is_clear_check_currently_valid(), "調整していない SIMPLE ボスのクリアチェックは消えない")

func test_simple_party_step_shows_editors_and_the_reset_all_button() -> void:
	var creator := _new_creator()
	creator.draft.add_party_character("hero")
	creator.go_to_step(4)
	var step: RBMCreatorStep5Party = creator._step_views[3]
	await get_tree().process_frame
	assert_true(_btn(step, "ResetAllAllyOverridesButton").visible, "「全員を標準に戻す」は SIMPLE にもある")
	_btn(step, "SelectCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	_btn(step, "StatusEditButton").pressed.emit()
	_btn(step, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame
	assert_not_null(step.find_child("AllyStatOverrideSpin_hero_atk", true, false))
	assert_not_null(step.find_child("AllySkillOverrideSpin_hero_hero_awakening_awakening_multiplier", true, false), "味方の覚醒の倍率も編集できる")
	var spin := step.find_child("AllyStatOverrideSpin_hero_atk", true, false) as SpinBox
	spin.value = 777
	assert_eq(int(creator.draft.effective_character_def("hero")["atk"]), 777)
	for node in step.find_children("*", "Label", true, false):
		assert_false((node as Label).text.contains(tr("ハードコア ステータス設定")), "SIMPLE に「ハードコア」の見出しを出さない")

# ---------------------------------------------------------------------------
# 行動が0件
# ---------------------------------------------------------------------------

func test_simple_boss_with_only_a_turn_ten_scripted_action_waits_until_then() -> void:
	var d := _simple_draft()
	var hit := str(d.skills[0]["skill_id"])
	d.normal_action_percentages.clear()
	d.normal_actions_enabled = false
	d.add_scripted_action(3, hit, "replace")
	assert_true(d.step4_is_valid(), "通常行動0件・指定行動だけで完成できる（使用率100%を求めない）")
	var start := RBMDefinitionLoader.start_battle(d.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	battle.boss.hp = 999999
	battle.boss.max_hp = 999999
	var per_turn := []
	for i in range(3):
		per_turn.append(_boss_actions(_round(battle)))
	assert_eq(per_turn[0], ["none"], "1ターン目は行動しない")
	assert_eq(per_turn[1], ["none"], "2ターン目は行動しない")
	assert_eq(per_turn[2], [hit], "3ターン目だけ指定の行動を使う")

func test_simple_and_hardcore_bosses_with_no_actions_can_be_completed_and_fought() -> void:
	for mode in [RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMCreatorDraft.CREATOR_MODE_ADVANCED]:
		var d := _simple_draft()
		d.normal_action_percentages.clear()
		d.normal_actions_enabled = false
		d.set_creator_mode(mode)  # 新しく作る HARDCORE と同じく、行動の無い状態から
		d.turn_actions.clear()
		assert_true(d.action_sequence.is_empty())
		assert_true(d.step4_is_valid() if mode == RBMCreatorDraft.CREATOR_MODE_SIMPLE else d.step4_advanced_is_valid(), "%s: 行動0件でも次へ進める" % mode)
		var saved := RBMLocalStageRepository.save_new(d)
		assert_true(bool(saved.get("ok", false)), "%s: 行動0件でも保存できる" % mode)
		var start := RBMDefinitionLoader.start_battle(d.to_definition(), 1)
		assert_true(start.has("battle"), "%s: %s" % [mode, start.get("errors", [])])
		var battle: RBMBattle = start["battle"]
		for i in range(4):
			var actions := _boss_actions(_round(battle))
			assert_eq(actions, ["none"], "%s: ボスは行動しない（勝手に補わない）" % mode)
			if battle.battle_over:
				break
		assert_true(battle.current_turn >= 2, "%s: 戦闘は止まらずに進む" % mode)

# ---------------------------------------------------------------------------
# 指定行動の設定画面・作成方法の説明・体験版
# ---------------------------------------------------------------------------

func test_scripted_editor_uses_trigger_turn_and_timing_labels() -> void:
	var creator := _new_creator()
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	var simple := step3._simple_view
	_btn(simple, "AddScriptedActionButton").pressed.emit()
	var texts: Array[String] = []
	for node in simple.find_child("ScriptedWhenPanel", true, false).find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	assert_true(texts.has(tr("発動ターン")), str(texts))
	assert_true(texts.has(tr("発動タイミング")), str(texts))
	for text in texts:
		assert_false(text.contains("いつ使う"), text)
	var timing := simple.find_child("ScriptedTimingOption", true, false) as OptionButton
	assert_eq(timing.item_count, 3, "通常行動の代わり・ターン開始時・ターン終了時")

func test_mode_choice_cards_use_the_confirmed_descriptions() -> void:
	var entry := RBMCreatorEntry.new()
	entry.size = Vector2(1280, 720)
	add_child_autofree(entry)
	await get_tree().process_frame
	entry._ensure_mode_choice_content_built()
	var simple := entry.find_child("ChooseSimpleModeButton", true, false).find_child("DescriptionLabel", true, false) as Label
	var hard := entry.find_child("ChooseAdvancedModeButton", true, false).find_child("DescriptionLabel", true, false) as Label
	assert_eq(simple.text, tr("使用率や指定ターンを設定して手軽にボスを作成"))
	assert_eq(hard.text, "%s\n%s" % [tr("ターンごとの行動や複雑な発動条件を組み合わせボスの戦術を自由に設計"), tr("特殊な勝利条件も設定できる上級者向けモード")])
	for node in entry.find_children("*", "Label", true, false):
		assert_false((node as Label).text.contains(tr("SIMPLE で設定できることすべて")), "誤解を招く古い一覧は無い")

func test_demo_edition_gets_the_new_simple_settings_but_not_hardcore() -> void:
	RBMEdition.set_demo_for_testing(true)
	assert_false(RBMEdition.allows_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED), "HARDCORE は製品版のまま")
	for appearance in ["appearance_dragon", "appearance_musha"]:
		var d := _simple_draft(appearance)
		assert_true(d.supports_awakening(), "%s は覚醒できる" % appearance)
		d.set_awakening(_awakening_at_half_hp())
		d.set_ally_stat_override("hero", "atk", 500)
		assert_true(d.step4_is_valid())
		assert_true(RBMEdition.allows_online_boss(d.creator_mode, d.appearance_id), "体験版でも公開・挑戦できる SIMPLE のボス")
		var resolved := RBMDefinitionLoader.resolve(d.to_definition())
		assert_true(bool(resolved.get("ok", false)))
		assert_eq(int(resolved["ally_defs"][0]["atk"]), 500)
	assert_false(_simple_draft("appearance_slime").supports_awakening(), "覚醒しない外見には付けられない")

# ---------------------------------------------------------------------------
# 2026-10-29（続き）: HARDCORE の追加行動の文言・味方の覚醒の説明のリアルタイム更新
# ---------------------------------------------------------------------------

func test_hardcore_extra_action_editor_uses_trigger_turn_and_timing_labels() -> void:
	var creator := _new_creator()
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.go_to_step(3)
	var step3: RBMCreatorStep4 = creator._step_views[2]
	step3.refresh()
	var advanced := step3._advanced_view
	_btn(advanced, "AddExtraActionButton").pressed.emit()
	if advanced._add_choice_view.visible:
		_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	var block := advanced.find_child("EntryExtraBlock", true, false) as Control
	assert_true(block.visible)
	var texts: Array[String] = []
	for node in block.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	assert_true(texts.has(tr("発動ターン")), str(texts))
	assert_true(texts.has(tr("発動タイミング")), str(texts))
	for text in texts:
		assert_false(text.contains("いつ使う"), text)
	var timing := advanced.find_child("ExtraTimingOption", true, false) as OptionButton
	assert_eq(timing.item_count, 2, "ターン開始時・終了時の2つのまま（HARDCORE に「通常行動の代わり」は無い）")

func _open_hero_performance(creator: RBMCreatorMain) -> RBMCreatorStep5Party:
	creator.draft.add_party_character("hero")
	creator.go_to_step(creator.party_step())
	var step: RBMCreatorStep5Party = creator._step_views[3]
	await get_tree().process_frame
	_btn(step, "SelectCharacterButton_hero").pressed.emit()
	await get_tree().process_frame
	_btn(step, "StatusEditButton").pressed.emit()
	_btn(step, "PerformanceTabButton").pressed.emit()
	await get_tree().process_frame
	return step

func _label_text(root: Node, node_name: String) -> String:
	var label := root.find_child(node_name, true, false) as Label
	assert_not_null(label, node_name)
	return label.text if label != null else ""

func test_ally_awakening_description_follows_the_inputs_immediately_in_both_modes() -> void:
	for mode in [RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMCreatorDraft.CREATOR_MODE_ADVANCED]:
		var creator := _new_creator()
		creator.draft.set_creator_mode(mode)
		var step := await _open_hero_performance(creator)
		assert_true(_label_text(step, "SkillEffectLabel_hero_awakening").contains(tr("全能力：%s倍") % "1.5"), "%s: 初めは標準の1.5倍" % mode)
		var spin := step.find_child("AllySkillOverrideSpin_hero_hero_awakening_awakening_multiplier", true, false) as SpinBox
		spin.value = 2.0
		assert_eq(_label_text(step, "SkillEffectLabel_hero_awakening"), tr("全能力：%s倍") % "2.0", "%s: 変えた瞬間に説明も 2.0倍" % mode)
		assert_eq(float(creator.draft.effective_character_def("hero")["skills"].filter(func(s): return s["id"] == "hero_awakening")[0]["awakening_multiplier"]), 2.0, "%s: 表示と保存される値が同じ" % mode)
		(step.find_child("AllySkillOverrideSpin_hero_hero_awakening_awakening_turns", true, false) as SpinBox).value = 5
		assert_eq(_label_text(step, "SkillDurationLabel_hero_awakening"), tr("効果時間：%dターン（次の自分の行動から）") % 5)
		(step.find_child("AllySkillOverrideSpin_hero_hero_awakening_awakening_sp_percent", true, false) as SpinBox).value = 40
		var max_sp := int(creator.draft.effective_character_def("hero")["max_sp"])
		assert_eq(_label_text(step, "SkillSpCostLabel_hero_awakening"), tr("消費SP：最大SPの%d%%（%d）") % [40, RBMDataLoader.awakening_sp_cost(max_sp, 40)])
		# 最大SP を変えると、消費SP の数も合わせる
		(step.find_child("AllyStatOverrideSpin_hero_max_sp", true, false) as SpinBox).value = 200
		assert_eq(_label_text(step, "SkillSpCostLabel_hero_awakening"), tr("消費SP：最大SPの%d%%（%d）") % [40, RBMDataLoader.awakening_sp_cost(200, 40)])
		assert_eq(step.find_child("AllySkillOverrideSpin_hero_hero_awakening_awakening_multiplier", true, false), spin, "%s: 入力欄は作り直さない（入力中のフォーカスを外さない）" % mode)
