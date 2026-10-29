extends GutTest

## RPG BOSS MAKER HARDCORE Creator — STEP3全面再設計後の通し確認 (Step 11)。
##
## 単一のHARDCOREボス定義で「発動条件 + 使用回数上限 + ランダム攻撃」を
## 同時に持つ複合シナリオを、Creator（実UI駆動）→ TEST BATTLE → Clear Check
## → 保存 → 読込 → CHALLENGEの実パイプライン全体を通して検証する。
##
## 2026-10-28: HARDCORE の通常行動をターンごとの設定に作り直した（ユーザー確定・案A）。この通し確認も、
## 「確定・使用率で抽選・条件で分岐」の3ターンを実UIで組み、TEST BATTLE→Clear Check→保存→読込→CHALLENGE を
## 通す形へ書き換えた（使用回数・順番に回して飛ばす方式は廃止）。
##
## §35（旧・複数HP閾値が1発で同時に閾値超えする瞬間条件シナリオ）は、
## 今回の再設計で「瞬間条件」概念そのものが完全に撤去された（通常条件の
## みが残る）ため、対応するテストごと存在しない——これはテストを弱めた
## のではなく、テスト対象の仕様自体が無くなったことの直接の帰結。

# ---------------------------------------------------------------------------
# 共有ヘルパー（既存test_rbm_challenge_flow.gd/test_rbm_creator_flow.gdと
# 同じ規約）
# ---------------------------------------------------------------------------

const TEST_DIR := "user://bossmaker_test_advanced_e2e/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

## Codexレビュー指摘対応⑪ Node Orphans: test_rbm_creator_flow.gdのafter_each()
## と同じ理由・同じ対処——スロット一覧/候補一覧の再構築がremove_child()+
## queue_free()で切り離した旧ノードは次のアイドルフレームで確実に解放される
## （本番UIのリークではない）。このファイルもtoggle系の連続操作を伴うため、
## 1フレーム分の待機を挟んで確実に解放させる。
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

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _new_challenge_entry() -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	add_child_autofree(entry)
	return entry

func _step4(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _all_label_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	for found in node.find_children("*", "Label", true, false):
		texts.append((found as Label).text)
	return texts

## 条件の無い確定のターンを保存→読込→再編集しても、生の「いつでも」という文字列は一覧にも詳細にも出ない。
func test_conditionless_slot_save_load_list_and_reedit_never_shows_a_raw_anytime_placeholder() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "条件なし表示テスト"
	creator.draft.hp = 1000
	creator.draft.atk = 10
	creator.draft.spd = 10
	creator.draft.add_party_character("hero")
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var skill_id := creator.draft.add_skill({"name": "常時行動", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_turn_action({"mode": "fixed", "entries": [{"skill_id": skill_id}]})
	var save_result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(save_result.get("ok", false)))

	var loaded_creator := _new_creator()
	var load_result := loaded_creator.start_loaded(str(save_result.get("stage_id", "")))
	assert_true(bool(load_result.get("ok", false)))
	var step3 := _step4(loaded_creator)
	var advanced := step3._advanced_view
	advanced.refresh()
	var list_texts := _all_label_texts(advanced._turn_list)
	assert_false(list_texts.has("いつでも"), "実ファイル保存→読込後の一覧にも「いつでも」を出さないこと")
	assert_true(list_texts.has("常時行動"), "行動名が出ること: %s" % [list_texts])

	_click(advanced, "TurnCard_0")
	_click(advanced, "TurnEntryCard_0")
	assert_true(advanced._pending_conditions.is_empty())
	assert_false(_all_label_texts(advanced._entry_view).has("いつでも"), "保存→読込後の再編集にも「いつでも」を出さないこと")

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

## 実際のCreator UI（実ボタン/実SpinBox/実OptionButtonとカードのクリック）だけで、3ターンの通常行動を組み立てる:
##   1ターン目 = 確定: skill_a「怒りの一撃」
##   2ターン目 = 使用率で抽選: skill_b「炎ブレス」50% / skill_c「強撃」50%
##   3ターン目 = 条件で分岐: 6ターン目以降なら skill_d「回復」（自己回復固定50）、それ以外は skill_a
## 4ターン目からは1ターン目へ戻る（a, b/c, a, a, b/c, d, a, b/c, d, ...）。
## ボスはhp=2200・atk=1・spd=1（味方は毎ラウンド先に行動しボスから一切脅かされない）。
func _build_composite_advanced_draft(creator: RBMCreatorMain) -> Dictionary:
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	step1._name_edit.text = "複合HARDCOREボスUI版"
	_btn(step1, "ConfirmNameButton").pressed.emit()
	assert_eq(creator.draft.boss_name, "複合HARDCOREボスUI版", "sanity: STEP1実UI経由でボス名が反映されること")

	creator.go_to_step(2)
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	assert_true(step2._edit_panel.visible, "能力は最初から編集可能")
	step2._hp_spin.value = 2200
	step2._atk_spin.value = 1
	step2._spd_spin.value = 1
	assert_null(step2.find_child("ConfirmStatsButton", true, false), "数値反映に決定は不要")
	assert_eq(creator.draft.hp, 2200, "sanity: STEP2実UI経由で能力が反映されること")

	creator.go_to_step(creator.party_step())
	var step4_party: RBMCreatorStep5Party = creator._step_views[3]
	_btn(step4_party, "SelectCharacterButton_hero").pressed.emit()
	_btn(step4_party, "AddCharacterButton").pressed.emit()
	assert_true(creator.draft.party_character_ids.has("hero"), "sanity: STEP4実UI経由でパーティが反映されること")

	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var step3 := _step4(creator)
	var advanced := step3._advanced_view
	advanced.refresh()

	# --- 1ターン目: 確定 skill_a「怒りの一撃」 -----------------------------
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "怒りの一撃"
	advanced._form._attack_multiplier_spin.value = 0.3
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var skill_a := str(creator.draft.turn_actions[0]["entries"][0]["skill_id"])

	# --- 2ターン目: 使用率で抽選 skill_b「炎ブレス」50% / skill_c「強撃」50% -------
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "炎ブレス"
	advanced._form._attack_attribute_option.select(RBMDefinitionLoader.VALID_ATTRIBUTES.find("FIRE"))
	advanced._form._attack_multiplier_spin.value = 0.3
	advanced._weight_spin.value = 50.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "強撃"
	advanced._form._attack_multiplier_spin.value = 0.3
	assert_almost_eq(advanced._weight_spin.value, 50.0, 0.001, "残りの50%が初期値")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var skill_b := str(creator.draft.turn_actions[1]["entries"][0]["skill_id"])
	var skill_c := str(creator.draft.turn_actions[1]["entries"][1]["skill_id"])

	# --- 3ターン目: 条件で分岐 6ターン目以降なら skill_d「回復」、それ以外は skill_a ---
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "回復"
	advanced._form._type_option.select(1)
	advanced._form._on_type_selected(1)
	advanced._form._self_heal_mode_option.select(0)
	advanced._form._on_heal_mode_selected(0)
	advanced._form._self_heal_fixed_spin.value = 50
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._select_condition_type("turn_at_least")
	advanced._condition_turn_spin.value = 6.0
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_click(advanced, "TurnElseCard")
	_btn(advanced, "AddChoicePickExistingButton").pressed.emit()
	var a_index := -1
	for i in range(creator.draft.skills.size()):
		if str(creator.draft.skills[i].get("skill_id", "")) == skill_a:
			a_index = i
	_click(advanced, "PickExistingSkillCard_%d" % a_index)
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.turn_actions.size(), 3, "確定 → 抽選 → 条件で分岐 の3ターン")
	var skill_d := str(creator.draft.turn_actions[2]["entries"][0]["skill_id"])
	assert_true(step3.is_step_valid())

	return {"skill_a": skill_a, "skill_b": skill_b, "skill_c": skill_c, "skill_d": skill_d}

## 実機プレイ改善①以降の確立済み慣習: SPD順で入力待ちの唯一の味方(hero)
## だけをact_attack()で解決し続ける——battle_overになるまで（安全上限
## 20ラウンド）。is_waiting_for_ally_action()/pending_ally_id()はsession側の
## API（RBMBattle自身ではない、test_rbm_creator_flow.gdの既存慣習どおり）。
func _win_by_plain_attacks(get_session: Callable, act_attack: Callable) -> void:
	var safety_turns := 0
	while true:
		safety_turns += 1
		assert_true(safety_turns <= 20, "runaway battle — something is wrong with the fixture")
		var session = get_session.call()
		if session.battle.battle_over:
			return
		if not session.is_waiting_for_ally_action():
			continue
		act_attack.call(session.pending_ally_id())

const ATTACK := {"type": "attack"}

## test_rbm_advanced_battle.gd._resolve_one_ally_turn()と同じ形——1体だけの
## 単純パーティ(hero)向けに1ターン分（heroの行動＋ボスの行動）を進め、
## そのターンのボス側ログエントリ（actor=="boss"の分）だけを返す。
## session.battle（実RBMBattle）を直接、advance_to_next_decision()/
## resolve_pending_ally_action()という製品コードの実駆動APIで動かす。
func _drive_one_turn_and_collect_boss_entries(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	log.append_array(battle.advance_to_next_decision())
	if battle.battle_over or not battle.is_waiting_for_ally_action():
		return _boss_entries_only(log)
	log.append_array(battle.resolve_pending_ally_action(action))
	log.append_array(battle.advance_to_next_decision())
	return _boss_entries_only(log)

func _boss_entries_only(log: Array) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(entry)
	return out

func test_composite_condition_and_max_uses_random_slot_survives_the_full_pipeline() -> void:
	var creator := _new_creator()
	var ids := _build_composite_advanced_draft(creator)

	# --- TEST BATTLE: ターンごとに設定どおり動くことを実ログから直接確かめる ----
	var test_result := creator.press_test_battle()
	assert_true(bool(test_result.get("ok", false)), "errors: %s" % str(test_result.get("errors", [])))
	var test_view := creator._test_battle_view
	var battle: RBMBattle = test_view.session.battle

	var turns_boss_entries: Dictionary = {}
	var turn := 0
	while not battle.battle_over:
		turn += 1
		assert_true(turn <= 20, "runaway battle — something is wrong with the fixture")
		turns_boss_entries[turn] = _drive_one_turn_and_collect_boss_entries(battle)
	assert_eq(battle.winner, "ally")
	assert_true(turn >= 6, "battle must reach turn 6 to see the conditional turn switch to its condition — only reached turn %d" % turn)

	for t in range(1, turn + 1):
		var entries: Array = turns_boss_entries.get(t, [])
		assert_true(entries.size() <= 1, "turn %d: ボスは1ターンにつき最大1回しか行動しない" % t)
		if entries.is_empty():
			assert_eq(t, turn, "ボスが行動しないのは最終ターン（味方の一撃で決着した場合）のみ")
			continue
		var picked := str(entries[0].get("skill_id", ""))
		match (t - 1) % 3:
			0:
				assert_eq(picked, ids["skill_a"], "turn %d は1ターン目の設定（確定）" % t)
			1:
				assert_true(picked in [ids["skill_b"], ids["skill_c"]], "turn %d は2ターン目の設定（抽選）" % t)
			2:
				assert_eq(picked, ids["skill_d"] if t >= 6 else ids["skill_a"], "turn %d は3ターン目の設定（6ターン目以降なら回復、それ以外は怒りの一撃）" % t)
	test_view.return_to_creator_requested.emit()

	# --- Clear Check: 実際に成功として記録されること ---------------------
	creator.press_clear_check()
	var clear_check_start := creator.press_clear_check_start()
	assert_true(bool(clear_check_start.get("ok", false)))
	var clear_check_view := creator._clear_check_view
	_win_by_plain_attacks(
		func(): return clear_check_view.session,
		func(unit_id): clear_check_view.act_attack(unit_id),
	)
	assert_eq(clear_check_view.session.battle.winner, "ally")
	assert_true(creator.draft.has_ever_cleared())
	assert_true(creator.draft.is_clear_check_currently_valid())

	# --- 保存 → 読込: 3ターンの決め方・候補・使用率・条件がそのまま残る -------
	creator.press_save()
	creator._save_view._on_save_new_pressed()
	var stage_id: String = creator.current_stage_id
	assert_false(stage_id.is_empty())
	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	restored.restore_clear_check_snapshot(load_result.get("clear_check_data", {}))
	assert_eq(restored.creator_mode, "advanced")
	assert_eq(restored.turn_actions, creator.draft.turn_actions)
	assert_eq(restored.turn_actions[2]["entries"][0]["conditions"], [{"type": "turn_at_least", "turn": 6}])
	assert_true(restored.action_sequence.is_empty(), "旧方式のデータは持たない")
	assert_true(restored.has_ever_cleared(), "Clear Check success must also round-trip through save/load")
	assert_true(restored.is_clear_check_currently_valid())

	var resolved := RBMDefinitionLoader.resolve(restored.to_definition())
	assert_true(bool(resolved.get("ok", false)), "errors: %s" % str(resolved.get("errors", [])))
	assert_eq(((resolved["boss_def"] as Dictionary).get("turn_actions", []) as Array).size(), 3)

	# --- CHALLENGE: 抽選のターンがあるので変動通知が出たうえで、挑戦→勝利まで完走できる ---
	var challenge_entry := _new_challenge_entry()
	challenge_entry._on_stage_row_pressed(stage_id)
	assert_true(challenge_entry._confirm_view._random_notice_label.visible)
	challenge_entry._confirm_view._on_challenge_pressed()
	var challenge_view := challenge_entry._battle_view
	_win_by_plain_attacks(
		func(): return challenge_view.session,
		func(unit_id): challenge_view.act_attack(unit_id),
	)
	assert_eq(challenge_view.session.battle.winner, "ally")
	assert_eq(challenge_view._outcome_label.text, "CLEAR", "結果の画面の見出し（2026-10-18 案C: VICTORY ではなく CLEAR）")

	# --- CHALLENGEでの勝利は、保存済みJSONを書き換えない -------------------
	var after_challenge := RBMLocalStageRepository.load_stage(stage_id)
	assert_eq(JSON.stringify(after_challenge.get("draft_data", {})), JSON.stringify(load_result.get("draft_data", {})), "a CHALLENGE win must never rewrite the saved stage file")

## 抽選の結果そのものは保存JSONへ残らず、CHALLENGEでは読み込んだ候補・使用率から戦闘が新しく抽選する。
func test_random_slot_result_is_not_persisted_and_challenge_redraws_independently_from_the_saved_rule() -> void:
	var creator := _new_creator()
	var ids := _build_composite_advanced_draft(creator)

	var test_result := creator.press_test_battle()
	assert_true(bool(test_result.get("ok", false)), "errors: %s" % str(test_result.get("errors", [])))
	var test_view := creator._test_battle_view
	var test_battle: RBMBattle = test_view.session.battle
	var test_turn := 0
	var random_fired_in_test_battle := false
	while not test_battle.battle_over:
		test_turn += 1
		assert_true(test_turn <= 20, "runaway battle — something is wrong with the fixture")
		var entries := _drive_one_turn_and_collect_boss_entries(test_battle)
		if entries.size() == 1 and str(entries[0].get("skill_id", "")) in [ids["skill_b"], ids["skill_c"]]:
			random_fired_in_test_battle = true
	assert_true(random_fired_in_test_battle, "sanity: TEST BATTLE中に抽選のターンが実際に1回以上実行されている")
	test_view.return_to_creator_requested.emit()

	creator.press_clear_check()
	var clear_check_start := creator.press_clear_check_start()
	assert_true(bool(clear_check_start.get("ok", false)))
	var clear_check_view := creator._clear_check_view
	_win_by_plain_attacks(
		func(): return clear_check_view.session,
		func(unit_id): clear_check_view.act_attack(unit_id),
	)
	assert_eq(clear_check_view.session.battle.winner, "ally")
	assert_true(creator.draft.has_ever_cleared())

	creator.press_save()
	creator._save_view._on_save_new_pressed()
	var stage_id: String = creator.current_stage_id
	assert_false(stage_id.is_empty())

	# --- 保存JSON確認: 抽選のターンのキーは作者の設定（mode/entries）だけ、候補は skill_id/weight だけ ---
	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	var draft_data: Dictionary = load_result.get("draft_data", {})
	var saved_turns: Array = draft_data.get("turn_actions", [])
	assert_eq(saved_turns.size(), 3)
	var saved_random_turn: Dictionary = saved_turns[1]
	var actual_keys: Array = saved_random_turn.keys()
	actual_keys.sort()
	assert_eq(actual_keys, ["entries", "mode"], "抽選のターンに想定外のキー（抽選結果など）を保存しない")
	assert_eq(str(saved_random_turn["mode"]), RBMActionPatternRules.TURN_MODE_RANDOM)
	var weights_by_skill := {}
	for candidate_variant in saved_random_turn["entries"]:
		var candidate: Dictionary = candidate_variant
		var candidate_keys: Array = candidate.keys()
		candidate_keys.sort()
		assert_eq(candidate_keys, ["skill_id", "weight"], "候補に想定外のキーを保存しない")
		weights_by_skill[str(candidate.get("skill_id", ""))] = float(candidate.get("weight", -1.0))
	assert_eq(weights_by_skill.get(ids["skill_b"], -1.0), 50.0, "skill_bの使用率が保存->読込後も一致している")
	assert_eq(weights_by_skill.get(ids["skill_c"], -1.0), 50.0, "skill_cの使用率が保存->読込後も一致している")

	# --- CHALLENGE: 読み込んだ候補・使用率から戦闘側が新しく抽選する -----------
	var challenge_entry := _new_challenge_entry()
	challenge_entry._on_stage_row_pressed(stage_id)
	challenge_entry._confirm_view._on_challenge_pressed()
	var challenge_view := challenge_entry._battle_view
	var challenge_battle: RBMBattle = challenge_view.session.battle
	var challenge_turn := 0
	var random_fired_in_challenge := false
	while not challenge_battle.battle_over and challenge_turn < 9:
		challenge_turn += 1
		var entries := _drive_one_turn_and_collect_boss_entries(challenge_battle)
		if entries.size() == 1 and str(entries[0].get("skill_id", "")) in [ids["skill_b"], ids["skill_c"]]:
			random_fired_in_challenge = true
	assert_true(random_fired_in_challenge, "sanity: CHALLENGE中にも抽選のターンが実際に1回以上実行されている——保存データに抽選結果が無い以上、戦闘側が候補/使用率から新規に抽選した結果である")
