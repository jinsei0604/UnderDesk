extends GutTest

## RPG BOSS MAKER HARDCORE Creator — STEP3全面再設計後の通し確認 (Step 11)。
##
## 単一のHARDCOREボス定義で「発動条件 + 使用回数上限 + ランダム攻撃」を
## 同時に持つ複合シナリオを、Creator（実UI駆動）→ TEST BATTLE → Clear Check
## → 保存 → 読込 → CHALLENGEの実パイプライン全体を通して検証する。
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

## 旧「行動パターン」時代、条件0件のパターンを保存→読込→再編集すると
## 一覧/編集画面に生の「いつでも」というプレースホルダー文字列が復元されて
## しまう不具合があった。新STEP3では条件0件を明示的に「条件：なし」と表示
## する仕様（RBMActionPatternSummary.when_line()）へ変わったが、退行防止の
## 精神自体は引き継ぐ——保存/読込/再編集のいずれの経路でも「いつでも」という
## 生の文字列が一切出てこないこと・かわりに「条件：なし」が明示されている
## ことを、実ファイル保存→実読込という本番と同じ経路で確認する。
func test_conditionless_slot_save_load_list_and_reedit_never_shows_a_raw_anytime_placeholder() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "条件なし表示テスト"
	creator.draft.hp = 1000
	creator.draft.atk = 10
	creator.draft.spd = 10
	creator.draft.add_party_character("hero")
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	var skill_id := creator.draft.add_skill({"name": "常時行動", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	var save_result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(save_result.get("ok", false)))

	var loaded_creator := _new_creator()
	var load_result := loaded_creator.start_loaded(str(save_result.get("stage_id", "")))
	assert_true(bool(load_result.get("ok", false)))
	var step3 := _step4(loaded_creator)
	var advanced := step3._advanced_view
	advanced.refresh()
	var list_texts := _all_label_texts(advanced._slot_list)
	assert_false(list_texts.has("いつでも"), "実ファイル保存→読込後の一覧にも「いつでも」を出さないこと")
	assert_true(list_texts.any(func(t): return str(t).contains("条件：なし")), "条件なしは明示的に「条件：なし」と表示すること")

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	assert_true(advanced._pending_conditions.is_empty())
	assert_false(_all_label_texts(advanced._skill_slot_view).has("いつでも"), "保存→読込後の再編集にも「いつでも」を出さないこと")

## 実際のCreator UI（実ボタン/実SpinBox/実OptionButtonだけ）を操作して、
## 3スロットの複合action_sequenceを組み立てる——test_rbm_advanced_creator_
## ui.gdで確立済みの実UI駆動パターンをそのまま踏襲する。
##
## 構成（round-robinカーソルの挙動を実際の複数ターンにわたって観測できる
## よう意図的に設計）:
##   slot0 = skill_a「怒りの一撃」— 条件: turn_at_least(3)、使用回数2回
##   slot1 = ランダム攻撃（skill_b「炎ブレス」/skill_c「強撃」、手動重み
##           50/50） — 条件なし、使用回数1回
##   slot2 = skill_d「回復」（自己回復固定50） — 条件なし、使用回数無制限
##           （常に成立する最終フォールバック）
##
## ボスはhp=2200・atk=1・spd=1（味方は毎ラウンド先に行動しボスから一切
## 脅かされない、旧E2Eテストと同じ設定値をそのまま踏襲——戦闘がターンを
## 十分な数だけ経由し、条件窓・両スロットの使用回数上限・フォールバックへの
## 移行を実際の複数ターンにわたって観測できるだけの長さを確保する）。
func _build_composite_advanced_draft(creator: RBMCreatorMain) -> Dictionary:
	var step1: RBMCreatorStep1Basic = creator._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	step1._name_edit.text = "複合HARDCOREボスUI版"
	_btn(step1, "ConfirmNameButton").pressed.emit()
	assert_eq(creator.draft.boss_name, "複合HARDCOREボスUI版", "sanity: STEP1実UI経由でボス名が反映されること")

	creator.go_to_step(2)
	var step2: RBMCreatorStep2Stats = creator._step_views[1]
	_btn(step2, "EditStatsButton").pressed.emit()
	step2._hp_spin.value = 2200
	step2._atk_spin.value = 1
	step2._spd_spin.value = 1
	_btn(step2, "ConfirmStatsButton").pressed.emit()
	assert_eq(creator.draft.hp, 2200, "sanity: STEP2実UI経由で能力が反映されること")
	assert_eq(creator.draft.atk, 1)
	assert_eq(creator.draft.spd, 1)

	creator.go_to_step(4)
	var step4_party: RBMCreatorStep5Party = creator._step_views[3]
	_btn(step4_party, "AddCharacterButton").pressed.emit()
	(_btn(step4_party, "AddCandidateButton_hero") as CheckBox).button_pressed = true
	_btn(step4_party, "ConfirmAddCandidatesButton").pressed.emit()
	assert_true(creator.draft.party_character_ids.has("hero"), "sanity: STEP4実UI経由でパーティが反映されること")

	# Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§23-A: モード切替
	# UI自体が最終確認画面から削除されたため、切替ロジック本体
	# （draft.set_creator_mode()、SIMPLE→HARDCOREは常に無確認）を直接叩く。
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	assert_eq(creator.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_ADVANCED, "sanity: HARDCOREへ切り替わること")

	var step3 := _step4(creator)
	# 直前のset_creator_mode(ADVANCED)内部の自動変換は、この時点で
	# normal_action_percentages/scripted_actionsのいずれも未設定のため恒等的に
	# 0件しか追加しない——このclear()は常に空集合に対する防御的初期化。
	creator.draft.action_sequence.clear()
	var advanced := step3._advanced_view
	advanced.refresh()

	# --- slot0: skill_a「怒りの一撃」— turn_at_least(3) + 使用回数2回 -------
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "怒りの一撃"
	advanced._form._attack_multiplier_spin.value = 0.3
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("turn_at_least"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	advanced._condition_turn_spin.value = 3.0
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	assert_eq(advanced._pending_conditions.size(), 1)
	advanced._uses_limited_check.button_pressed = true
	advanced._on_uses_limited_toggled(true)
	advanced._uses_count_spin.value = 2.0
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 1)
	var skill_a := str(creator.draft.action_sequence[0].get("skill_id", ""))

	# --- slot1: ランダム攻撃（skill_b「炎ブレス」/skill_c「強撃」、手動重み
	# 50/50） — 条件なし・使用回数1回 ----------------------------------------
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	advanced._random_mode_option.select(RBMActionPatternRules.RANDOM_MODES.find(RBMActionPatternRules.RANDOM_MODE_MANUAL))
	advanced._on_random_mode_selected(advanced._random_mode_option.selected)

	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "炎ブレス"
	advanced._form._attack_attribute_option.select(RBMDefinitionLoader.VALID_ATTRIBUTES.find("FIRE"))
	advanced._form._attack_multiplier_spin.value = 0.3
	advanced._form._on_save_pressed()
	advanced._set_random_candidate_weight(0, 50.0)
	var skill_b := str((advanced._random_candidates[0] as Dictionary).get("skill_id", ""))

	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "強撃"
	advanced._form._attack_multiplier_spin.value = 0.3
	advanced._form._on_save_pressed()
	advanced._set_random_candidate_weight(1, 50.0)
	var skill_c := str((advanced._random_candidates[1] as Dictionary).get("skill_id", ""))

	advanced._uses_limited_check.button_pressed = true
	advanced._on_uses_limited_toggled(true)
	advanced._uses_count_spin.value = 1.0
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 2)
	assert_eq(str(creator.draft.action_sequence[1].get("kind", "")), "random")

	# --- slot2: skill_d「回復」（自己回復固定50） — 条件なし・使用回数無制限
	# （常に成立する最終フォールバック、新規スロットの既定値のまま） --------
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "回復"
	advanced._form._type_option.select(1)
	advanced._form._on_type_selected(1)
	advanced._form._self_heal_mode_option.select(0)
	advanced._form._on_heal_mode_selected(0)
	advanced._form._self_heal_fixed_spin.value = 50
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_eq(creator.draft.action_sequence.size(), 3, "skill_a -> random(skill_b/skill_c) -> skill_d の3スロット")
	assert_eq(str(creator.draft.action_sequence[2].get("kind", "")), "skill")
	var skill_d := str(creator.draft.action_sequence[2].get("skill_id", ""))

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

	# --- TEST BATTLE: 実バトルをターン単位で駆動し、「値が存在するだけでなく、
	# 実際に新しいround-robinカーソル方式どおりに動く」ことをターンごとの
	# 実ログから直接検証する --------------------------------------------------
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
	assert_true(turn >= 7, "battle must last long enough to exhaust both skill_a's and the random slot's own max_uses (by turn 6) and observe the permanent fallback afterward — only reached turn %d" % turn)

	# 1ターン=1スロットのみ実行される（新設計の核心）——ただし最終ターンだけ
	# は、ally側の一撃でボスが倒れボス自身の番が来ないまま決着することがある
	# ため0件を許容する（1件を超えることは絶対に無い、という上限だけを常に
	# 保証する）。
	for t in range(1, turn + 1):
		var entries: Array = turns_boss_entries.get(t, [])
		assert_true(entries.size() <= 1, "turn %d: ボスは1ターンにつき最大1回しか行動しない" % t)
		if entries.is_empty():
			assert_eq(t, turn, "ボスが1ターンも行動しないのは最終ターン（ally側の一撃で決着した場合）のみであるべき")

	# turn1: cursorは0(skill_a)から開始するが、turn_at_least(3)がまだ成立
	# しないためskip、次のスロット(random、条件なし・使用回数まだ0/1)が
	# 適格でそのまま発火する。
	var turn1: Array = turns_boss_entries.get(1, [])
	assert_true(str(turn1[0].get("skill_id", "")) in [ids["skill_b"], ids["skill_c"]], "turn1はランダムスロットが発火し、2つの候補のいずれかへ解決される")

	# turn2: cursorはrandomスロットの直後(skill_d)へ進んでいる——skill_aは
	# まだturn_at_least(3)を満たさないため、フォールバックのskill_dが発火する。
	var turn2: Array = turns_boss_entries.get(2, [])
	assert_eq(str(turn2[0].get("skill_id", "")), ids["skill_d"])

	# turn3: cursorはskill_aへ戻っており、条件が初めて成立する——ここで発火する。
	var turn3: Array = turns_boss_entries.get(3, [])
	assert_eq(str(turn3[0].get("skill_id", "")), ids["skill_a"])

	# turn4: cursorはrandomスロットへ戻るが、自身の使用回数1回は既にturn1で
	# 使い切っている（=以後永久にineligible）——フォールバックのskill_dへ。
	var turn4: Array = turns_boss_entries.get(4, [])
	assert_eq(str(turn4[0].get("skill_id", "")), ids["skill_d"])

	# turn5: cursorはskill_aへ戻り、条件は成立したまま・使用回数もまだ
	# 1/2回しか使っていない——2回目の発火。
	var turn5: Array = turns_boss_entries.get(5, [])
	assert_eq(str(turn5[0].get("skill_id", "")), ids["skill_a"])

	# turn6: randomスロットは依然として永久にineligibleのまま——skill_dへ。
	var turn6: Array = turns_boss_entries.get(6, [])
	assert_eq(str(turn6[0].get("skill_id", "")), ids["skill_d"])

	# turn7以降: skill_aの使用回数(2回)もturn5で使い切られた——唯一残る
	# 適格なスロットはskill_d(使用回数無制限)のみで、それ以後は毎ターン
	# 必ずこれが発火する恒常状態になる（戦闘が何ターン続いても不変）。
	# 唯一の例外は最終ターン自身——ally側の一撃で決着し、ボスの番が来ない
	# まま終わることがある（上のループで既に「最終ターンに限る」ことを
	# 確認済み）。
	for later_turn in range(7, turn + 1):
		var entries: Array = turns_boss_entries.get(later_turn, [])
		if entries.is_empty():
			continue
		assert_eq(str(entries[0].get("skill_id", "")), ids["skill_d"], "turn %d は skill_a/random 両方の使用回数上限を使い切った後の恒久フォールバック" % later_turn)

	assert_eq(battle.winner, "ally")
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

	# --- 保存 --------------------------------------------------------------
	creator.press_save()
	creator._save_view._on_save_new_pressed()
	var stage_id: String = creator.current_stage_id
	assert_false(stage_id.is_empty())

	# --- 読込: action_sequenceの全要素（条件・使用回数・skill_a単発 -> random
	# -> skill_d単発の3スロット構成）が保存/読込を経てもそのまま残っていること
	# ------------------------------------------------------------------------
	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	restored.restore_clear_check_snapshot(load_result.get("clear_check_data", {}))
	assert_eq(restored.creator_mode, "advanced")
	assert_eq(restored.action_sequence.size(), 3)

	var restored_slot0: Dictionary = restored.action_sequence[0]
	assert_eq(str(restored_slot0.get("kind", "")), "skill")
	assert_eq(str(restored_slot0.get("skill_id", "")), ids["skill_a"])
	var restored_slot0_conditions: Array = restored_slot0.get("conditions", [])
	assert_eq(restored_slot0_conditions.size(), 1)
	assert_eq(str(restored_slot0_conditions[0].get("type", "")), "turn_at_least")
	assert_eq(int(restored_slot0_conditions[0].get("turn", -1)), 3)
	assert_eq(int(restored_slot0.get("max_uses", -1)), 2)
	assert_false(restored_slot0.has("cooldown_turns"), "新schemaにcooldownという概念は存在しない")
	assert_false(restored_slot0.has("trigger_probability"), "新schemaにtrigger_probabilityという概念は存在しない")

	var restored_slot1: Dictionary = restored.action_sequence[1]
	assert_eq(str(restored_slot1.get("kind", "")), "random")
	var restored_candidates: Array = restored_slot1.get("candidates", [])
	assert_eq(restored_candidates.size(), 2)
	assert_eq(int(restored_slot1.get("max_uses", -1)), 1)
	assert_true((restored_slot1.get("conditions", []) as Array).is_empty())

	var restored_slot2: Dictionary = restored.action_sequence[2]
	assert_eq(str(restored_slot2.get("kind", "")), "skill")
	assert_eq(str(restored_slot2.get("skill_id", "")), ids["skill_d"])
	assert_eq(int(restored_slot2.get("max_uses", -1)), RBMActionPatternRules.UNLIMITED_USES)

	assert_true(restored.has_ever_cleared(), "Clear Check success must also round-trip through save/load")

	# --- RBMDefinitionLoader.resolve()が読込済みDraftを問題なく解決できる
	# こと（保存データが壊れていれば、ここで初めて発覚しうる） ------------
	var resolved := RBMDefinitionLoader.resolve(restored.to_definition())
	assert_true(bool(resolved.get("ok", false)), "errors: %s" % str(resolved.get("errors", [])))
	var resolved_sequence: Array = (resolved["boss_def"] as Dictionary).get("action_sequence", [])
	assert_eq(resolved_sequence.size(), 3)

	# --- CHALLENGE: ランダム候補2件を持つため変動通知が実際に出るうえで、
	# 実際に挑戦→勝利まで完走できること -------------------------------------
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
	assert_eq(challenge_view._outcome_label.text, "クリア！")

	# --- CHALLENGEでの勝利は、既に記録済みのClear Check成功・保存済み
	# JSONのいずれも書き換えない（Phase 1既存規約、この複合シナリオでも
	# 引き続き成立することを確認する） -------------------------------------
	var after_challenge := RBMLocalStageRepository.load_stage(stage_id)
	assert_eq(JSON.stringify(after_challenge.get("draft_data", {})), JSON.stringify(load_result.get("draft_data", {})), "a CHALLENGE win must never rewrite the saved stage file")

## ランダムスロットで実行された抽選結果そのものが保存JSONへ永続化/共有され
## ず、CHALLENGEでは読み込んだ候補・重みルールからBattle側が新しく抽選する
## 構造であることを、実際のCreator→TEST BATTLE→Clear Check→保存→保存JSON
## 確認→読込→CHALLENGEという製品パイプラインを通して直接証明する。複合
## スロットの構築ロジック自体は既存test_composite_condition_and_max_uses_
## random_slot_survives_the_full_pipelineと同一のもの（_build_composite_
## advanced_draft、実Creator UI駆動）をそのまま再利用する。
func test_random_slot_result_is_not_persisted_and_challenge_redraws_independently_from_the_saved_rule() -> void:
	var creator := _new_creator()
	var ids := _build_composite_advanced_draft(creator)

	# --- TEST BATTLE: ランダムスロットを実際に1回以上実行させる
	# (turn1で必ず発火する設計——_build_composite_advanced_draft参照) --------
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
	assert_true(random_fired_in_test_battle, "sanity: TEST BATTLE中にランダムスロットが実際に1回以上実行されている")
	test_view.return_to_creator_requested.emit()

	# --- Clear Check: 成功として記録する（保存の前提） ---------------------
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

	# --- 保存 --------------------------------------------------------------
	creator.press_save()
	creator._save_view._on_save_new_pressed()
	var stage_id: String = creator.current_stage_id
	assert_false(stage_id.is_empty())

	# --- 保存JSON確認: randomスロットのキー集合が「作者設定ルールだけ」
	# （slot_id/kind/mode/candidates/conditions/condition_logic/max_uses、
	# 候補はskill_id/weightのみ）と完全一致し、chosen/selected/result/
	# resolved/last_choice等の抽選結果を固定するランタイム値や、
	# trigger_probability/cooldown_turnsのような新schemaで撤去された概念が
	# 一切存在しないことを確認する。重み値自体も保存->読込後に一致している
	# ことを確認する。 --------------------------------------------------------
	var load_result := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(load_result.get("ok", false)))
	var draft_data: Dictionary = load_result.get("draft_data", {})
	var saved_sequence: Array = draft_data.get("action_sequence", [])
	assert_eq(saved_sequence.size(), 3)
	var saved_random_slot: Dictionary = saved_sequence[1]
	assert_eq(str(saved_random_slot.get("kind", "")), "random")

	var banned_keys := ["chosen", "selected", "result", "resolved", "last_choice", "picked", "pick", "outcome", "drawn", "trigger_probability", "cooldown_turns"]
	for banned in banned_keys:
		assert_false(saved_random_slot.has(banned), "保存データのrandomスロットに'%s'が含まれてはいけない" % banned)

	# キー名を推測しただけのチェックで終わらせず、保存されているキー集合が
	# 作者設定ルール(slot_id/kind/mode/candidates/conditions/condition_logic/
	# max_uses)だけで構成されていることまで網羅的に確認する——未知のキーが
	# 1つでも紛れ込んでいれば必ずFAILする。
	var expected_slot_keys: Array = ["slot_id", "kind", "mode", "candidates", "conditions", "condition_logic", "max_uses"]
	for key in saved_random_slot.keys():
		assert_true(key in expected_slot_keys, "randomスロットに想定外のキー'%s'が保存されている" % key)
	assert_eq(saved_random_slot.keys().size(), expected_slot_keys.size(), "randomスロットのキー数が期待構造と一致しない")
	var actual_slot_keys: Array = saved_random_slot.keys()
	actual_slot_keys.sort()
	var sorted_expected_slot_keys: Array = expected_slot_keys.duplicate()
	sorted_expected_slot_keys.sort()
	assert_eq(actual_slot_keys, sorted_expected_slot_keys, "保存randomスロットのキー集合(ソート済み)が期待構造と完全一致しない")

	# modeの値そのものも、Creator UIで実際に選択した方式（このE2Eは手動重み
	# ——RBMActionPatternRules.RANDOM_MODE_MANUAL、新しい文字列リテラルを
	# 定義せず既存の正式定数を使う）と保存->読込後も一致していることを確認する。
	assert_eq(str(saved_random_slot.get("mode", "")), RBMActionPatternRules.RANDOM_MODE_MANUAL, "保存->読込後のmode値が、Creator UIで選択した手動重み方式(RANDOM_MODE_MANUAL)と一致しない")
	assert_true((saved_random_slot.get("conditions", []) as Array).is_empty())
	assert_eq(int(saved_random_slot.get("max_uses", -99)), 1)

	var saved_candidates: Array = saved_random_slot.get("candidates", [])
	assert_eq(saved_candidates.size(), 2)
	var expected_candidate_keys: Array = ["skill_id", "weight"]
	var weights_by_skill := {}
	for candidate_variant in saved_candidates:
		var candidate: Dictionary = candidate_variant
		for key in candidate.keys():
			assert_true(key in expected_candidate_keys, "候補に想定外のキー'%s'が保存されている" % key)
		weights_by_skill[str(candidate.get("skill_id", ""))] = float(candidate.get("weight", -1.0))
	assert_eq(weights_by_skill.get(ids["skill_b"], -1.0), 50.0, "skill_bの重みが保存->読込後も一致している")
	assert_eq(weights_by_skill.get(ids["skill_c"], -1.0), 50.0, "skill_cの重みが保存->読込後も一致している")

	# --- CHALLENGE: 保存された「前回抽選結果」を再利用するのではなく、
	# 読み込んだ候補・重みルールからBattle側が新しく抽選する構造であることを
	# 実際に確認する——turn1で改めてrandomスロットを実行させ、その場で
	# candidates(skill_b/skill_c)のいずれかへ正しく解決されることを直接確認
	# する（「必ずClear Checkと違う結果を引く」ことは要求しない）。 -----------
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
			var picked := str(entries[0].get("skill_id", ""))
			assert_true(picked in [ids["skill_b"], ids["skill_c"]], "CHALLENGE側でも読み込んだcandidatesルールから正しく新規抽選される")
			random_fired_in_challenge = true
	assert_true(random_fired_in_challenge, "sanity: CHALLENGE中にもランダムスロットが実際に1回以上実行されている——保存データに抽選結果自体が無い以上、これはBattle側が候補/重みルールから新規に抽選した結果である")
