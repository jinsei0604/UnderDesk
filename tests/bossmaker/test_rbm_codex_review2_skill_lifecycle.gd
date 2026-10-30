extends GutTest

## RPG BOSS MAKER HARDCORE Creator STEP3全面再設計 — 旧Codexレビュー指摘
## 対応の再発防止テストを新schema/新UIへ移植したもの。指摘は元々3点:
## ①保存済みHARDCORE行動削除時の孤立skillを回収する
## ②HARDCORE random候補編集後のセッションキャンセルで完全復元する
##   （fixed actionにも同じキャンセル契約を適用）
## ③HARDCORE固定行動に編集導線を追加する
## 加えて④SIMPLE/HARDCORE共通のskillライフサイクル確認、⑤last_boss_skill
## 条件との関係、⑥Clear Check影響、⑧同名行動の独立性、⑨last_boss_skill
## E2E、⑩RBMActionPatternSummary表示テスト補強——それぞれ指摘書の番号に
## 対応するセクションへ分けている。
##
## §29「旧仕様が撤去された箇所は、単に削除・弱体化するのではなく新仕様を
## 保証するテストへ置き換える」に従い全面書き直した——旧「1パターンが
## 複数actions(fixed/random)を1ターンで連続実行する」構造・cooldown・
## trigger_probability・瞬間条件は新schemaに一切存在しないため、それらに
## 依存していたテストは新設計（1スロット=1攻撃 or 1ランダムグループ、
## round-robinカーソルで1ターンにつき1スロットだけ実行）へ翻訳した。
## 既に他のテストファイルで十分に保証されている部分は重複させず、その
## カバレッジの所在を明示するだけの目印テストへ置き換えている
## （§30の重複禁止方針、test_rbm_advanced_e2e_full_pipeline.gdの
## test_section35_...と同じ精神）。
##
## test_rbm_advanced_creator_ui.gdと同じ「実UIツリーをインスタンス化して
## 公開API/シグナル経由で操作する」方針、test_rbm_advanced_battle.gdと同じ
## 「advance_to_next_decision()/resolve_pending_ally_action()で実際に戦闘を
## 駆動する」方針を、それぞれこのファイル自身のヘルパーとして複製する
## （このプロジェクト既存の「各テストファイルは小さな共通ヘルパーを継承
## ではなく複製して持つ」規約どおり）。

const TEST_DIR := "user://bossmaker_test_codex_review2/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	# Codexレビュー指摘⑪ Node Orphans対応と同じ理由: スロット一覧/候補一覧の
	# 再構築(remove_child()+queue_free())が次のアイドルフレームで確実に
	# 解放されるよう、テスト終了ごとに1フレーム分待機する。
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

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _fill_minimum_valid_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "レビュー対応テストボス"
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "初期スキル", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _step3(creator: RBMCreatorMain) -> RBMCreatorStep4:
	creator.go_to_step(3)
	var view: RBMCreatorStep4 = creator._step_views[2]
	return view

func _open_advanced(creator: RBMCreatorMain) -> RBMCreatorStep4:
	var step3 := _step3(creator)
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	step3.refresh()
	return step3

func _fill_and_save_form(form: RBMActionEditorForm, name: String, atk_multiplier: float = 1.0) -> void:
	form._name_edit.text = name
	form._attack_multiplier_spin.value = atk_multiplier
	form._on_save_pressed()

func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "card %s" % card_name)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

## 2026-10-28: HARDCORE の通常行動はターンごと（N ターン目に N 番目の設定、最後の次は1ターン目）。
## 新しい行動を「確定」で使うターンを1つ足す（実UIのボタン/入力欄経由）。足した行動の skill_id を返す。
func _create_skill_slot(advanced: RBMCreatorStep4ActionPatterns, name: String, atk_multiplier: float = 1.0) -> String:
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = name
	advanced._form._attack_multiplier_spin.value = atk_multiplier
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	return str(advanced.draft.turn_actions[-1]["entries"][0].get("skill_id", ""))

## 新しい行動を候補にして「使用率で抽選」するターンを1つ足す（使用率の初期値は残りの分: 最初の候補100%、あとは0%）。
## 候補の skill_id を足した順に返す。
func _create_random_turn(advanced: RBMCreatorStep4ActionPatterns, names: Array, multipliers: Array = []) -> Array:
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_random").pressed.emit()
	for i in range(names.size()):
		_btn(advanced, "AddTurnEntryButton").pressed.emit()
		_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
		advanced._form._name_edit.text = str(names[i])
		advanced._form._attack_multiplier_spin.value = float(multipliers[i]) if i < multipliers.size() else 1.0
		_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	var ids := []
	for entry in advanced.draft.turn_actions[-1]["entries"]:
		ids.append(str(entry.get("skill_id", "")))
	return ids

## ターンのカード → その中の行動のカード（③ 行動の詳細）を開く。
func _open_entry(advanced: RBMCreatorStep4ActionPatterns, turn_index: int, entry_index: int) -> void:
	_click(advanced, "TurnCard_%d" % turn_index)
	_click(advanced, "TurnEntryCard_%d" % entry_index)

## test_rbm_advanced_battle.gd._resolve_one_ally_turn()と同じ形——1体だけの
## 単純パーティ(hero)向けに1ターン分（heroの行動＋ボスの行動）を進め、
## そのターンの全ログを返す。session APIではなく実RBMBattleを直接、
## advance_to_next_decision()/resolve_pending_ally_action()という製品コードの
## 実駆動APIで動かす。
func _resolve_one_ally_turn(battle: RBMBattle, action: Dictionary = {"type": "attack"}) -> Array:
	var log: Array = []
	log.append_array(battle.advance_to_next_decision())
	if battle.battle_over or not battle.is_waiting_for_ally_action():
		return log
	log.append_array(battle.resolve_pending_ally_action(action))
	log.append_array(battle.advance_to_next_decision())
	return log

func _boss_log_entries(log: Array) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(entry)
	return out

# =============================================================================
# ①保存済みHARDCORE攻撃削除時の孤立skillを回収する
# =============================================================================

## A. 複数種の孤立skill同時回収: 確定のターン1つ＋抽選のターン（候補2つ）をそれぞれ削除すると、参照されなく
## なった全skill（確定1＋候補2=3件）がdraft.skillsから消え、保存JSONにも残らない。
func test_orphan_A_deleting_a_skill_slot_and_a_random_slot_removes_all_their_unreferenced_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var skills_before := creator.draft.skills.size()

	_create_skill_slot(advanced, "固定行動")
	_create_random_turn(advanced, ["候補A", "候補B"])

	assert_eq(creator.draft.skills.size(), skills_before + 3, "sanity: 固定1+抽選の候補2=3件が新規作成されていること")
	assert_eq(creator.draft.turn_actions.size(), 2)

	_click(advanced, "TurnCard_1")  # 抽選のターンを先に削除
	_btn(advanced, "TurnDeleteButton").pressed.emit()
	_click(advanced, "TurnCard_0")  # 確定のターンを削除
	_btn(advanced, "TurnDeleteButton").pressed.emit()

	assert_true(creator.draft.turn_actions.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before, "未参照になった全skillがdraft.skillsから消えること")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.skills.size(), skills_before, "保存JSONにも不要skillが残らないこと")

## ターンは位置がそのままターン番号: A/B/C の真ん中(B)を消すと A/C の2ターンになり、戦闘は A→C→A と繰り返す。
func test_orphan_B_removing_the_middle_of_three_skill_slots_and_saving_deletes_only_that_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	var a_id := _create_skill_slot(advanced, "A")
	var b_id := _create_skill_slot(advanced, "B")
	var c_id := _create_skill_slot(advanced, "C")
	assert_eq(creator.draft.turn_actions.size(), 3, "sanity")

	_click(advanced, "TurnCard_1")
	_btn(advanced, "TurnDeleteButton").pressed.emit()

	assert_true(creator.draft.find_skill(b_id).is_empty(), "未参照になったBは削除される")
	assert_false(creator.draft.find_skill(a_id).is_empty(), "Aは残る")
	assert_false(creator.draft.find_skill(c_id).is_empty(), "Cは残る")
	assert_eq(creator.draft.turn_actions.size(), 2)
	assert_eq(str(creator.draft.turn_actions[0]["entries"][0].get("skill_id", "")), a_id)
	assert_eq(str(creator.draft.turn_actions[1]["entries"][0].get("skill_id", "")), c_id, "ターンがA→Cになること")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))

	var start_result := RBMDefinitionLoader.start_battle(restored.to_definition(), 777)
	assert_true(bool(start_result.get("ok", false)), "sanity: %s" % str(start_result.get("errors", [])))
	var battle: RBMBattle = start_result["battle"]
	for expected in [a_id, c_id, a_id]:
		var boss := _boss_log_entries(_resolve_one_ally_turn(battle))
		assert_eq(boss.size(), 1, "sanity")
		assert_eq(str(boss[0].get("skill_id", "")), expected, "A→C→A（Bは一切現れない）")

## C. 抽選の候補の削除→保存: 抽選のターン(A/B/C)の設定を開き、
## Bだけを削除して保存すると、Bだけdraft.skillsから消え、候補もA/Cのみに
## なり、保存→読込後もBは復活しない。
func test_orphan_C_removing_one_random_candidate_from_an_existing_slot_and_saving_deletes_only_that_skill_and_does_not_resurrect_on_reload() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var ids := _create_random_turn(advanced, ["A", "B", "C"])
	var a_id := str(ids[0])
	var b_id := str(ids[1])
	var c_id := str(ids[2])

	_open_entry(advanced, 0, 1)
	assert_true(advanced._entry_view.visible, "sanity")
	_btn(advanced, "EntryDeleteButton").pressed.emit()  # remove B
	_btn(advanced, "TurnConfirmButton").pressed.emit()

	assert_true(creator.draft.find_skill(b_id).is_empty())
	assert_false(creator.draft.find_skill(a_id).is_empty())
	assert_false(creator.draft.find_skill(c_id).is_empty())
	assert_eq((creator.draft.turn_actions[0]["entries"] as Array).size(), 2)

	var result := RBMLocalStageRepository.save_new(creator.draft)
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_true(restored.find_skill(b_id).is_empty(), "保存→読込後もBは復活しないこと")

## D. 他参照あり: 2つの独立したスロットが同じskillを参照している場合、
## 1箇所を削除しただけでは消えない——test_rbm_advanced_creator_ui.gd:
## test_deleting_one_slot_does_not_delete_a_skill_still_used_by_another_slot
## で新schemaのUI経由の削除として既に直接検証済み（§30重複禁止方針）。
func test_orphan_D_shared_reference_survival_is_already_covered_elsewhere() -> void:
	pass_test("test_rbm_advanced_creator_ui.gd:test_deleting_one_slot_does_not_delete_a_skill_still_used_by_another_slot で直接検証済み")

## E. MAX_SKILLS: 上限到達後、孤立skillを1件削除すると枠が回復し、新規1件を
## 追加できるようになる——Draft自身のadd_skill/remove_skill_if_unreferenced/
## can_add_skillのみを使う純粋なDraftレベルの契約で、STEP3 UI再設計の
## 影響を一切受けない。
func test_orphan_E_deleting_an_unreferenced_skill_frees_a_max_skills_slot_for_a_new_one() -> void:
	var draft := RBMCreatorDraft.new()
	while draft.skills.size() < RBMCreatorDraft.MAX_SKILLS:
		draft.add_skill({"name": "埋め草", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	assert_eq(draft.skills.size(), RBMCreatorDraft.MAX_SKILLS)
	assert_false(draft.can_add_skill())

	var last_id := str(draft.skills[draft.skills.size() - 1].get("skill_id", ""))
	draft.remove_skill_if_unreferenced(last_id)
	assert_eq(draft.skills.size(), RBMCreatorDraft.MAX_SKILLS - 1)
	assert_true(draft.can_add_skill(), "枠が回復し新規追加可能になること")
	var new_id := draft.add_skill({"name": "新規", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	assert_false(new_id.is_empty())

# =============================================================================
# ②HARDCORE random候補編集後のセッションキャンセルで完全復元する
# =============================================================================

## 1つのターンの設定の中で複数の候補の性能を変えても、ターンをキャンセルすれば全部元へ戻る。
func test_cancel_A_multiple_random_candidate_edits_within_one_session_all_revert_on_whole_slot_cancel() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var ids := _create_random_turn(advanced, ["Fire", "Ice"], [1.0, 2.0])
	var candidate_a_id := str(ids[0])
	var candidate_b_id := str(ids[1])

	var snapshot_before := creator.draft.battle_content_snapshot()
	creator.draft.record_clear_check_success()
	assert_true(creator.draft.is_clear_check_currently_valid(), "sanity")

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.99
	advanced._form._on_save_pressed()
	assert_eq(float(creator.draft.find_skill(candidate_a_id).get("atk_multiplier", -1.0)), 9.99, "sanity: フォーム保存は即座にdraft.skillsへ反映される")
	_btn(advanced, "EntryCancelButton").pressed.emit()
	_click(advanced, "TurnEntryCard_1")
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 8.88
	advanced._form._on_save_pressed()
	assert_eq(float(creator.draft.find_skill(candidate_b_id).get("atk_multiplier", -1.0)), 8.88, "sanity")
	_btn(advanced, "EntryCancelButton").pressed.emit()

	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_eq(float(creator.draft.find_skill(candidate_a_id).get("atk_multiplier", -1.0)), 1.0, "Aが元へ戻ること")
	assert_eq(float(creator.draft.find_skill(candidate_b_id).get("atk_multiplier", -1.0)), 2.0, "Bも元へ戻ること")
	assert_eq(creator.draft.battle_content_snapshot(), snapshot_before, "battle_content_snapshot()が編集前と完全一致すること")
	assert_true(creator.draft.is_clear_check_currently_valid(), "Clear Check有効状態が維持されること")

## B. fixed action（skill_slot_view側）にも同じキャンセル契約が適用される
## ——test_rbm_advanced_creator_ui.gd:test_cancelling_performance_edit_
## restores_the_original_skill_content で既に直接検証済み（§30重複禁止方針）。
func test_cancel_B_fixed_action_edit_reverts_is_already_covered_elsewhere() -> void:
	pass_test("test_rbm_advanced_creator_ui.gd:test_cancelling_performance_edit_restores_the_original_skill_content で直接検証済み")

## C. 旧「1パターンセッション内で複数の固定行動を編集後にキャンセルすると
## 全て戻る」という概念は、新設計（1スロット=1skillのみ、複数skillを同時に
## 編集できるセッション自体が"ランダム候補"以外に存在しない）には
## 直接の対応物が無い——その精神は上のtest_cancel_A（ランダム攻撃の複数
## 候補）へ引き継がれている。
func test_cancel_C_multiple_edits_in_one_session_concept_is_superseded_by_cancel_A() -> void:
	pass_test("新設計では1スロット=1性能編集対象のため、旧概念はtest_cancel_A（ランダム攻撃の複数候補編集）で引き継ぎ済み")

# =============================================================================
# ③HARDCORE固定行動に編集導線を追加する
# =============================================================================

## 編集ボタンの存在・現在値のプリフィル・キャンセルでの復元は
## test_rbm_advanced_creator_ui.gd:test_editing_existing_slot_shows_
## performance_summary_not_form_by_default / test_edit_performance_button_
## opens_the_shared_form_inline / test_cancelling_performance_edit_restores_
## the_original_skill_content で既に直接検証済み（§30重複禁止方針）。ここでは
## それらではまだ確認していない2点——編集後、一覧カードの要約表示が更新
## されること・実際にto_definition()/実Battleへ新しい性能が伝播することを
## 追加で確認する。
func test_fixed_action_edit_button_exists_and_reverts_are_already_covered_elsewhere() -> void:
	pass_test("test_rbm_advanced_creator_ui.gd の複数テストで直接検証済み")

func test_fixed_action_edit_updates_list_card_summary_after_returning_to_list() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_create_skill_slot(advanced, "旧名", 1.0)

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "新名"
	advanced._form._attack_multiplier_spin.value = 5.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()

	var texts := PackedStringArray()
	for label in advanced.find_child("TurnCard_0", true, false).find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var joined := "\n".join(texts)
	assert_true(joined.contains("新名"), "カード要約が新しい内容へ更新されること: %s" % joined)
	assert_true(joined.contains("威力500"), "威力表示も更新されること: %s" % joined)

func test_fixed_action_edit_save_propagates_to_definition_and_real_battle_damage() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)  # boss.atk=100
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var skill_id := _create_skill_slot(advanced, "旧名", 1.0)

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "新名"
	advanced._form._attack_multiplier_spin.value = 5.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()

	assert_eq(str(creator.draft.find_skill(skill_id).get("name", "")), "新名", "Draft skillが更新されること")
	var definition := creator.draft.to_definition()
	var found_skill := {}
	for s in (definition["boss"] as Dictionary)["skills"]:
		if str((s as Dictionary).get("skill_id", "")) == skill_id:
			found_skill = s
	assert_eq(float(found_skill.get("atk_multiplier", -1.0)), 5.0, "Definition生成にも新性能が反映されること")

	var start_result := RBMDefinitionLoader.start_battle(definition, 999)
	assert_true(bool(start_result.get("ok", false)), "sanity: %s" % str(start_result.get("errors", [])))
	var battle: RBMBattle = start_result["battle"]
	var boss_entries := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(boss_entries.size(), 1, "sanity")
	assert_eq(str(boss_entries[0].get("skill_id", "")), skill_id, "sanity")
	assert_eq(int(boss_entries[0].get("amount", -1)), 500, "実Battleで編集後のskillデータ(atk_multiplier=5.0)を使ったダメージ結果(500)になること——boss.atk=100×5.0=500")

# =============================================================================
# ④SIMPLE/HARDCORE共通のskillライフサイクル確認（SIMPLE側、無改修対象）
# =============================================================================

func test_simple_normal_action_delete_removes_unreferenced_skill() -> void:
	var creator := _new_creator()
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view
	# 2026-10-17: SIMPLE も HARDCORE と同じ流れ（設定画面の確定ボタン1つ）
	_btn(simple, "AddNormalActionButton").pressed.emit()
	simple._form._name_edit.text = "通常行動"
	_btn(simple, "ActionConfirmButton").pressed.emit()
	assert_eq(creator.draft.normal_action_percentages.size(), 1, "sanity")
	var skill_id := str(creator.draft.normal_action_percentages.keys()[0])
	assert_false(creator.draft.find_skill(skill_id).is_empty(), "sanity")

	# 2026-10-28: 削除はカードから開いた「通常行動の設定」の中の「削除」で行う。
	_open_normal_card(simple, skill_id)
	var delete_button: Button = simple.find_child("ActionDeleteButton", true, false)
	assert_true(delete_button.visible)
	delete_button.pressed.emit()
	assert_true(creator.draft.find_skill(skill_id).is_empty(), "未参照になった通常行動skillが消えること")
	assert_false(creator.draft.normal_action_percentages.has(skill_id))

func test_simple_scripted_action_delete_removes_unreferenced_skill() -> void:
	var creator := _new_creator()
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view
	# 2026-10-17: SIMPLE も HARDCORE と同じ流れ（性能と発動ターン・タイミングを1つの設定画面で、確定ボタン1つ）
	_btn(simple, "AddScriptedActionButton").pressed.emit()
	simple._form._name_edit.text = "指定行動"
	_btn(simple, "ActionConfirmButton").pressed.emit()
	assert_eq(creator.draft.scripted_actions.size(), 1, "sanity")
	var skill_id := str(creator.draft.scripted_actions[0].get("skill_id", ""))
	assert_false(creator.draft.find_skill(skill_id).is_empty(), "sanity")

	simple.remove_scripted_action(0)
	assert_true(creator.draft.find_skill(skill_id).is_empty(), "未参照になった指定行動skillが消えること")
	assert_true(creator.draft.scripted_actions.is_empty())

## 同じskill_idがSIMPLE通常行動・SIMPLE指定行動の両方から参照されている
## 状態を用意し（この共有状態自体は現行UIでは通常発生し得ないため、
## fixture/Draft側で直接構築してよい）、片方の参照だけをSIMPLE UI経由で
## 削除しても、①skillはdraft.skillsに残る②残った参照（指定行動側）は
## 壊れない③保存→読込後も維持される、ことを確認する。その後、最後の参照
## （指定行動側）もSIMPLE UI経由で削除した場合にのみskillが実際に回収
## されることまで続けて確認する。
func test_simple_shared_reference_between_normal_and_scripted_action_is_preserved_and_final_deletion_removes_it() -> void:
	var creator := _new_creator()
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view

	var shared_id := creator.draft.add_skill({"name": "共有行動", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.normal_action_percentages[shared_id] = 100.0
	creator.draft.add_scripted_action(1, shared_id, "replace")
	simple.refresh()
	assert_false(creator.draft.find_skill(shared_id).is_empty(), "sanity")
	assert_eq(creator.draft.scripted_actions.size(), 1, "sanity")

	# 通常行動側の参照だけをSIMPLE UI経由で削除する。
	_open_normal_card(simple, shared_id)
	var delete_normal_button: Button = simple.find_child("ActionDeleteButton", true, false)
	assert_true(delete_normal_button.visible)
	delete_normal_button.pressed.emit()

	assert_false(creator.draft.find_skill(shared_id).is_empty(), "指定行動からまだ参照されているskillは削除してはならない")
	assert_false(creator.draft.normal_action_percentages.has(shared_id), "通常行動側の参照は消えていること")
	assert_eq(creator.draft.scripted_actions.size(), 1, "残った指定行動の件数が壊れていないこと")
	assert_eq(str(creator.draft.scripted_actions[0].get("skill_id", "")), shared_id, "残った指定行動の参照先skill_idが壊れていないこと")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_false(restored.find_skill(shared_id).is_empty(), "保存→読込後もskillが維持されること")
	assert_eq(restored.scripted_actions.size(), 1)
	assert_eq(str(restored.scripted_actions[0].get("skill_id", "")), shared_id, "保存→読込後も残った参照が壊れていないこと")

	# 最後の参照（指定行動）もSIMPLE UI経由で削除すると、今度こそ回収される。
	simple.refresh()
	# 2026-10-29: 指定行動もカード全体を押して設定画面を開き、そこで削除する（一覧の削除ボタンは無い）。
	assert_null(simple._scripted_list.find_child("DeleteScriptedActionButton_0", true, false), "一覧に削除ボタンは無い")
	_open_scripted_card(simple, 0)
	var delete_scripted_button: Button = simple.find_child("ActionDeleteButton", true, false)
	assert_true(delete_scripted_button.visible)
	delete_scripted_button.pressed.emit()

	assert_true(creator.draft.find_skill(shared_id).is_empty(), "最後の参照が消えれば削除されること")
	assert_true(creator.draft.scripted_actions.is_empty())

# =============================================================================
# ⑤last_boss_skill条件との関係（境界テスト）
# =============================================================================

func test_last_boss_skill_boundary_sole_reference_deleted_shared_reference_preserved() -> void:
	var draft := RBMCreatorDraft.new()

	# ケース1: last_boss_skill条件だけがこのskillを参照している——条件と
	# 他の参照をすべて取り除けば削除してよい。
	var skill_id := draft.add_skill({"name": "境界テスト1", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var other_id := draft.add_skill({"name": "別行動1", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var slot_x_id: String = draft.add_action_slot({
		"kind": "skill", "skill_id": other_id,
		"conditions": [{"type": "last_boss_skill", "skill_id": skill_id}],
		"condition_logic": "AND", "max_uses": -1,
	})
	assert_true(draft.is_boss_skill_referenced(skill_id), "last_boss_skill条件からの参照は「参照あり」と判定されること")
	draft.update_action_slot(slot_x_id, {"kind": "skill", "skill_id": other_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	draft.remove_skill_if_unreferenced(skill_id)
	assert_true(draft.find_skill(skill_id).is_empty(), "条件も他の参照も無くなればskillは削除してよい")

	# ケース2: 同じskillがスロット自身のskill_idからも同時に参照されている
	# ——last_boss_skill条件だけを取り除いても、スロット自身の参照が残って
	# いる限り削除してはならない。
	var skill_id_2 := draft.add_skill({"name": "境界テスト2", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var slot_y_id: String = draft.add_action_slot({
		"kind": "skill", "skill_id": skill_id_2,
		"conditions": [{"type": "last_boss_skill", "skill_id": skill_id_2}],
		"condition_logic": "AND", "max_uses": -1,
	})
	draft.update_action_slot(slot_y_id, {"kind": "skill", "skill_id": skill_id_2, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	draft.remove_skill_if_unreferenced(skill_id_2)
	assert_false(draft.find_skill(skill_id_2).is_empty(), "スロット自身からまだ参照されているため削除してはならない")

# =============================================================================
# ⑥Clear Check影響（失効する操作 / 失効しない操作）
# =============================================================================

func _draft_with_saved_skill_slot_and_clear_check(creator: RBMCreatorMain) -> Dictionary:
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var skill_id := _create_skill_slot(advanced, "固定行動", 1.0)
	creator.draft.record_clear_check_success()
	assert_true(creator.draft.is_clear_check_currently_valid(), "sanity")
	return {"advanced": advanced, "skill_id": skill_id}

func test_clear_check_invalidates_on_fixed_slot_performance_edit_and_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "確定の行動を実際に編集して保存すると失効すること")

func test_clear_check_invalidates_on_random_candidate_performance_edit_and_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_create_random_turn(advanced, ["候補", "候補2"])
	creator.draft.record_clear_check_success()

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "抽選の候補を実際に編集して保存すると失効すること")

func test_clear_check_invalidates_on_slot_delete() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	_click(advanced, "TurnCard_0")
	_btn(advanced, "TurnDeleteButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "ターンの削除で失効すること")

func test_clear_check_invalidates_on_random_candidate_delete_within_editor() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_create_random_turn(advanced, ["A", "B", "C"])
	creator.draft.record_clear_check_success()

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryDeleteButton").pressed.emit()
	_btn(advanced, "EqualizeTurnButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq((creator.draft.turn_actions[0]["entries"] as Array).size(), 2, "sanity")
	assert_false(creator.draft.is_clear_check_currently_valid(), "抽選の候補の削除で失効すること")

func test_clear_check_preserved_when_fixed_slot_performance_edit_form_is_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "CancelActionButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "ActionEditorForm単体のキャンセルでは変更しないため失効しないこと")

func test_clear_check_preserved_when_random_candidate_performance_edit_form_is_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_create_random_turn(advanced, ["候補", "候補2"])
	creator.draft.record_clear_check_success()

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "CancelActionButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid())

func test_clear_check_preserved_when_skill_edit_saved_then_whole_random_session_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_create_random_turn(advanced, ["候補", "候補2"])
	creator.draft.record_clear_check_success()

	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "EntryCancelButton").pressed.emit()
	_btn(advanced, "TurnCancelButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "候補の性能を保存した後もターン全体をキャンセルすれば失効しないこと")

func test_clear_check_preserved_when_slot_editor_opened_but_untouched() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	_open_entry(advanced, 0, 0)
	_btn(advanced, "EntryCancelButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "ターンの設定を開いて何も変えずに保存しても失効しないこと")

# =============================================================================
# ⑧同名行動の独立性
# =============================================================================

func test_same_name_actions_in_different_places_are_independent() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view
	_btn(simple, "AddNormalActionButton").pressed.emit()
	# 既存の行動がある時は、追加の方法（既存から選ぶ／新しく作る）を選ぶ画面が先に出る（HARDCORE と同じ流れ）
	if simple._add_choice_view.visible:
		_btn(simple, "AddChoiceCreateNewButton").pressed.emit()
	simple._form._name_edit.text = "炎"
	simple._form._attack_multiplier_spin.value = 1.0
	_btn(simple, "ActionConfirmButton").pressed.emit()
	var normal_skill_id := ""
	for id in creator.draft.normal_action_percentages.keys():
		normal_skill_id = str(id)

	var step3_advanced := _open_advanced(creator)
	var advanced := step3_advanced._advanced_view
	var advanced_skill_id := _create_skill_slot(advanced, "炎", 3.0)

	assert_ne(normal_skill_id, advanced_skill_id, "同名でも別々のskill_idを持つこと")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_true(restored.normal_action_percentages.has(normal_skill_id), "保存→読込後も通常行動側は同じskill_idのまま")
	assert_eq(str(restored.turn_actions[0]["entries"][0].get("skill_id", "")), advanced_skill_id, "保存→読込後もHARDCORE側は同じskill_idのまま")

	var normal_skill := creator.draft.find_skill(normal_skill_id).duplicate(true)
	normal_skill["atk_multiplier"] = 9.0
	creator.draft.update_skill(normal_skill_id, normal_skill)
	assert_eq(float(creator.draft.find_skill(normal_skill_id).get("atk_multiplier", -1.0)), 9.0)
	assert_eq(float(creator.draft.find_skill(advanced_skill_id).get("atk_multiplier", -1.0)), 3.0, "片方を編集してももう片方は変わらないこと")

	var definition := creator.draft.to_definition()
	var by_id := {}
	for s in (definition["boss"] as Dictionary)["skills"]:
		by_id[str((s as Dictionary).get("skill_id", ""))] = s
	assert_eq(float((by_id[normal_skill_id] as Dictionary).get("atk_multiplier", -1.0)), 9.0, "Battleでもそれぞれの性能が個別に使われること")
	assert_eq(float((by_id[advanced_skill_id] as Dictionary).get("atk_multiplier", -1.0)), 3.0)

## 同じ名前「炎」の行動2つ（1ターン目と2ターン目）が、実Battleでもそれぞれ自分の性能を使う。
func test_same_name_actions_fire_with_independent_performance_in_real_battle() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)  # boss.atk=100, boss.spd=50<hero.spd100
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	var skill_a := _create_skill_slot(advanced, "炎", 1.0)
	var skill_b := _create_skill_slot(advanced, "炎", 3.0)

	assert_ne(skill_a, skill_b, "sanity: 同名でも別skill_idであること")
	assert_eq(str(creator.draft.find_skill(skill_a).get("name", "")), "炎", "sanity")
	assert_eq(str(creator.draft.find_skill(skill_b).get("name", "")), "炎", "sanity")

	var start_result := RBMDefinitionLoader.start_battle(creator.draft.to_definition(), 4242)
	assert_true(bool(start_result.get("ok", false)), "sanity: %s" % str(start_result.get("errors", [])))
	var battle: RBMBattle = start_result["battle"]

	var turn1_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn1_boss.size(), 1, "sanity")
	assert_eq(str(turn1_boss[0].get("skill_id", "")), skill_a, "1ターン目は炎A(skill_id=%s)が実行されること" % skill_a)
	assert_eq(int(turn1_boss[0].get("amount", -1)), 100, "炎A(atk_multiplier=1.0, boss.atk=100)は実Battleでも100ダメージであること")

	var turn2_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn2_boss.size(), 1, "sanity")
	assert_eq(str(turn2_boss[0].get("skill_id", "")), skill_b, "2ターン目は炎B(skill_id=%s)が実行されること" % skill_b)
	assert_eq(int(turn2_boss[0].get("amount", -1)), 300, "炎B(atk_multiplier=3.0, boss.atk=100)は実Battleで300ダメージ——表示名が同じ'炎'でも、実行結果として明確に別々の性能を使うことの直接証明")

# =============================================================================
# ⑨last_boss_skill E2E（UI選択→Draft→保存→読込→Battle）
# =============================================================================

func test_last_boss_skill_e2e_ui_select_save_load_and_battle_condition_fires() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "last_boss_skillE2Eボス"
	creator.draft.hp = 99999
	creator.draft.atk = 10
	# hero(data_bossmaker/allies/hero.json)のspd=100より低くし、各ターン
	# 「味方が先に行動→ボスが応答する」という_resolve_one_ally_turn()の
	# 前提を保つ。
	creator.draft.spd = 10
	creator.draft.add_party_character("hero")
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	# 1ターン目: 「先制技」を確定で使う。
	var opener_id := _create_skill_slot(advanced, "先制技")

	# 2ターン目: 条件で分岐。「前回使った行動」が先制技なら「追撃」、それ以外は先制技。
	# 2026-10-29: 「前回使った行動」は新しく選べなくなった（4カテゴリ）。保存済みのボスに残っている旧条件として
	# 下書きへ入れ、画面でその行を開いて保存し直しても黙って消えないこと・戦闘で今までどおり働くことを確かめる。
	var pursuit_id := creator.draft.add_skill({"name": "追撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": pursuit_id, "conditions": [{"type": "last_boss_skill", "skill_id": opener_id}], "condition_logic": "AND"}], "else_skill_id": opener_id})
	advanced.refresh()
	_open_entry(advanced, 1, 0)
	assert_eq(advanced._pending_conditions, [{"type": "last_boss_skill", "skill_id": opener_id}], "the old condition is shown as is")
	_btn(advanced, "EntryConfirmButton").pressed.emit()
	_btn(advanced, "TurnConfirmButton").pressed.emit()
	assert_eq(creator.draft.turn_actions[1]["entries"][0]["conditions"], [{"type": "last_boss_skill", "skill_id": opener_id}], "re-saving through the screen keeps it")

	var save_result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(save_result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.turn_actions.size(), 2, "sanity: 両ターンが保存・復元されること")
	var restored_condition: Dictionary = (restored.turn_actions[1]["entries"][0].get("conditions", []) as Array)[0]
	assert_eq(str(restored_condition.get("skill_id", "")), opener_id, "読込後もlast_boss_skill条件が正しいskill_idを保持していること")

	var definition := restored.to_definition()
	var start_result := RBMDefinitionLoader.start_battle(definition, 12345)
	assert_true(bool(start_result.get("ok", false)), "sanity: %s" % str(start_result.get("errors", [])))
	var battle: RBMBattle = start_result["battle"]

	var turn1_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn1_boss.size(), 1, "sanity")
	assert_eq(str(turn1_boss[0].get("skill_id", "")), opener_id, "1ターン目に「先制技」が使われること")

	var turn2_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn2_boss.size(), 1, "sanity")
	assert_eq(str(turn2_boss[0].get("skill_id", "")), pursuit_id, "2ターン目、last_boss_skill条件が成立して「追撃」が使われること")
	var pursuit_name := str(restored.find_skill(pursuit_id).get("name", ""))
	assert_eq(pursuit_name, "追撃")

# =============================================================================
# ⑩RBMActionPatternSummary表示テスト補強（新API: slot_summary/condition_line/
# when_line/uses_line/skill_performance_line/slot_action_name）
# =============================================================================

func _summary_draft_with_two_skills() -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "SummaryTestBoss"
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_skill({"name": "炎ブレス", "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 1.5})
	return draft

func test_summary_when_line_joins_and_conditions_with_and() -> void:
	var draft := _summary_draft_with_two_skills()
	var conditions := [{"type": "turn_at_least", "turn": 2}, {"type": "hp_at_most", "percent": 50.0}]
	var line := RBMActionPatternSummary.when_line(conditions, "AND", draft)
	assert_true(line.contains("かつ"), "ANDは「かつ」で結合されること: %s" % line)
	assert_true(line.contains("2ターン目以降"))
	assert_true(line.contains("HPが50%以下"))

func test_summary_when_line_joins_or_conditions_with_or() -> void:
	var draft := _summary_draft_with_two_skills()
	var conditions := [{"type": "turn_at_least", "turn": 2}, {"type": "hp_at_most", "percent": 50.0}]
	var line := RBMActionPatternSummary.when_line(conditions, "OR", draft)
	assert_true(line.contains("または"), "ORは「または」で結合されること: %s" % line)

func test_summary_when_line_returns_explicit_no_condition_text_when_empty() -> void:
	var draft := _summary_draft_with_two_skills()
	var line := RBMActionPatternSummary.when_line([], "AND", draft)
	assert_eq(line, "条件：なし")

func test_summary_uses_line_unlimited_and_limited() -> void:
	assert_eq(RBMActionPatternSummary.uses_line(RBMActionPatternRules.UNLIMITED_USES), "使用回数：制限なし")
	assert_eq(RBMActionPatternSummary.uses_line(3), "使用回数：3回")

func test_summary_random_slot_action_name_lists_candidate_names() -> void:
	var draft := _summary_draft_with_two_skills()
	var a_id := str(draft.skills[0].get("skill_id", ""))
	var b_id := str(draft.skills[1].get("skill_id", ""))
	var slot := {"kind": "random", "candidates": [{"skill_id": a_id, "weight": 50.0}, {"skill_id": b_id, "weight": 50.0}]}
	var name := RBMActionPatternSummary.slot_action_name(slot, draft)
	assert_true(name.contains("ランダム攻撃"))
	assert_true(name.contains("斬撃"))
	assert_true(name.contains("炎ブレス"))

func test_summary_slot_summary_random_kind_lists_candidates_as_performance() -> void:
	var draft := _summary_draft_with_two_skills()
	var a_id := str(draft.skills[0].get("skill_id", ""))
	var b_id := str(draft.skills[1].get("skill_id", ""))
	var slot := {"kind": "random", "candidates": [{"skill_id": a_id, "weight": 50.0}, {"skill_id": b_id, "weight": 50.0}], "conditions": [], "condition_logic": "AND", "max_uses": -1}
	var summary := RBMActionPatternSummary.slot_summary(slot, draft, 0)
	assert_eq(int(summary["ordinal"]), 1)
	assert_eq(str(summary["name"]), "ランダム攻撃")
	assert_true(str(summary["performance"]).contains("斬撃"))
	assert_true(str(summary["performance"]).contains("炎ブレス"))
	assert_eq(str(summary["condition"]), "条件：なし")
	assert_eq(str(summary["uses"]), "使用回数：制限なし")

func test_summary_slot_summary_skill_kind_uses_referenced_skill_name_and_performance() -> void:
	var draft := _summary_draft_with_two_skills()
	var a_id := str(draft.skills[0].get("skill_id", ""))
	var slot := {"kind": "skill", "skill_id": a_id, "conditions": [{"type": "turn_at", "turn": 1}], "condition_logic": "AND", "max_uses": 2}
	var summary := RBMActionPatternSummary.slot_summary(slot, draft, 2)
	assert_eq(int(summary["ordinal"]), 3)
	assert_eq(str(summary["name"]), "斬撃")
	assert_eq(str(summary["performance"]), RBMActionPatternSummary.skill_performance_line(draft.skills[0]))
	assert_true(str(summary["condition"]).contains("1ターン目"))
	assert_eq(str(summary["uses"]), "使用回数：2回")

## 新schemaに瞬間条件・発動確率・Cooldown・複数行動ステップという概念が
## 存在しないことの直接証明——skill_performance_line/slot_summaryの出力に
## それらを示唆する文字列が一切含まれないことを確認する（旧テストが
## 存在確認していた文言の"存在しない版")。
func test_summary_never_mentions_removed_trigger_probability_cooldown_or_instant_concepts() -> void:
	var draft := _summary_draft_with_two_skills()
	var a_id := str(draft.skills[0].get("skill_id", ""))
	var b_id := str(draft.skills[1].get("skill_id", ""))
	var skill_slot := {"kind": "skill", "skill_id": a_id, "conditions": [{"type": "hp_at_most", "percent": 20.0}], "condition_logic": "AND", "max_uses": 2}
	var random_slot := {"kind": "random", "candidates": [{"skill_id": a_id, "weight": 40.0}, {"skill_id": b_id, "weight": 60.0}], "conditions": [], "condition_logic": "AND", "max_uses": -1}
	var joined := "\n".join([
		JSON.stringify(RBMActionPatternSummary.slot_summary(skill_slot, draft, 0)),
		JSON.stringify(RBMActionPatternSummary.slot_summary(random_slot, draft, 1)),
	])
	for banned_word in ["発動確率", "Cooldown", "再使用まで", "瞬間", "発動後"]:
		assert_false(joined.contains(banned_word), "新schemaの表示に撤去済み概念'%s'が残っていてはならない" % banned_word)

## Summary生成呼び出し自体がDraftを一切書き換えないこと——battle_content_
## snapshot()（保存用の安定したDraft表現）の呼び出し前後完全一致で確認する。
func test_summary_generation_does_not_mutate_draft_battle_content_snapshot_stays_identical() -> void:
	var draft := _summary_draft_with_two_skills()
	var a_id := str(draft.skills[0].get("skill_id", ""))
	var b_id := str(draft.skills[1].get("skill_id", ""))
	var slot := {
		"kind": "random",
		"candidates": [{"skill_id": a_id, "weight": 40.0}, {"skill_id": b_id, "weight": 60.0}],
		"conditions": [{"type": "hp_at_most", "percent": 20.0}],
		"condition_logic": "AND",
		"max_uses": 2,
	}
	var slot_id: String = draft.add_action_slot(slot)
	var full_slot := draft.find_action_slot(slot_id)
	assert_false(full_slot.is_empty(), "sanity")

	var snapshot_before := draft.battle_content_snapshot()
	for i in range(3):
		RBMActionPatternSummary.slot_summary(full_slot, draft, 0)
	var snapshot_after := draft.battle_content_snapshot()
	assert_eq(snapshot_after, snapshot_before, "Summary生成前後でbattle_content_snapshot()が完全一致すること（action_sequence/skillsを一切書き換えていないことの証明）")

## 2026-10-28: 通常行動はカードを押して「通常行動の設定」を開く（一覧の編集・削除のボタンは無くなった）。
func _open_scripted_card(simple: RBMCreatorStep4Actions, index: int) -> void:
	var card := simple._scripted_list.find_child("ScriptedActionCard_%d" % index, true, false) as Control
	assert_not_null(card, "the scripted action card exists")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)

func _open_normal_card(simple: RBMCreatorStep4Actions, skill_id: String) -> void:
	var card := simple._normal_list.find_child("NormalActionCard_%s" % skill_id, true, false) as Control
	assert_not_null(card, "the normal action card exists")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	card.gui_input.emit(release)
