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

## 「新しく攻撃を作る」フロー（skill_slot_view内、確定ボタンは1つだけ）で
## 単純な固定攻撃を1件追加する共通ヘルパー——このファイルの多くのテストが
## 同じ手順を繰り返すため、可読性のために1つにまとめる（Draftを直接
## 書き込むのではなく、常に実UIのボタン/入力欄経由）。追加されたskill_idを
## 返す。
func _create_skill_slot(advanced: RBMCreatorStep4ActionPatterns, name: String, atk_multiplier: float = 1.0) -> String:
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = name
	advanced._form._attack_multiplier_spin.value = atk_multiplier
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	return str(advanced.draft.action_sequence[-1].get("skill_id", ""))

## turn_at条件付きの固定攻撃を1件追加する——round-robin方式では、複数
## スロットを「その担当ターンにだけ確実に発火させる」ための最も簡潔な
## 手段がturn_at条件（他のスロットの使用回数/条件に依存せず、単独で
## その1ターンだけ成立する）。追加されたskill_idを返す。
func _create_skill_slot_at_turn(advanced: RBMCreatorStep4ActionPatterns, name: String, turn: int, atk_multiplier: float = 1.0) -> String:
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = name
	advanced._form._attack_multiplier_spin.value = atk_multiplier
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("turn_at"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	advanced._condition_turn_spin.value = float(turn)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	return str(advanced.draft.action_sequence[-1].get("skill_id", ""))

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

## A. 複数種の孤立skill同時回収: 固定攻撃1件+ランダム攻撃(候補2件)という
## 異なる2種類のスロットをそれぞれ削除すると、参照されなくなった全skill
## （固定1+ランダム候補2=3件）がdraft.skillsから消え、保存JSONにも残らない。
## 旧「1つのpatternが固定+ランダムの両方を同時に持ち、1回のパターン削除で
## まとめて回収される」という構成は、新設計（1スロット=1攻撃 or 1ランダム
## グループ、複数の性質を1つの塊にまとめない）には存在しないため、
## 「2つの独立したスロットをそれぞれ削除する」という形へ翻訳して同じ
## 回収の網羅性を確認する。
func test_orphan_A_deleting_a_skill_slot_and_a_random_slot_removes_all_their_unreferenced_skills() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var skills_before := creator.draft.skills.size()

	_create_skill_slot(advanced, "固定行動")

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補A")
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補B")
	_btn(advanced, "RandomConfirmButton").pressed.emit()

	assert_eq(creator.draft.skills.size(), skills_before + 3, "sanity: 固定1+ランダム候補2=3件が新規作成されていること")
	assert_eq(creator.draft.action_sequence.size(), 2)

	advanced._slot_list.find_child("DeleteSlotButton_1", true, false).pressed.emit()  # ランダムスロットを先に削除
	advanced._slot_list.find_child("DeleteSlotButton_0", true, false).pressed.emit()  # 固定スロットを削除

	assert_true(creator.draft.action_sequence.is_empty())
	assert_eq(creator.draft.skills.size(), skills_before, "未参照になった全skillがdraft.skillsから消えること")

	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.skills.size(), skills_before, "保存JSONにも不要skillが残らないこと")

## B. 複数スロットの中間を削除→保存: A(turn1)/B(turn2)/C(turn3)という3つの
## 独立したスロットからBを削除して保存すると、Bだけdraft.skillsから消え、
## A/Cは残り、実Battleでもturn1にA・turn2は(Bが消え、Aも条件不成立・Cも
## 条件不成立のため)何もせず・turn3にCが実行される——Bは一切現れない。
func test_orphan_B_removing_the_middle_of_three_skill_slots_and_saving_deletes_only_that_skill() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	var a_id := _create_skill_slot_at_turn(advanced, "A", 1)
	var b_id := _create_skill_slot_at_turn(advanced, "B", 2)
	var c_id := _create_skill_slot_at_turn(advanced, "C", 3)
	assert_eq(creator.draft.action_sequence.size(), 3, "sanity")

	advanced._slot_list.find_child("EditSlotButton_1", true, false).pressed.emit()
	_btn(advanced, "SkillSlotDeleteButton").pressed.emit()

	assert_true(creator.draft.find_skill(b_id).is_empty(), "未参照になったBは削除される")
	assert_false(creator.draft.find_skill(a_id).is_empty(), "Aは残る")
	assert_false(creator.draft.find_skill(c_id).is_empty(), "Cは残る")
	assert_eq(creator.draft.action_sequence.size(), 2)
	assert_eq(str(creator.draft.action_sequence[0].get("skill_id", "")), a_id)
	assert_eq(str(creator.draft.action_sequence[1].get("skill_id", "")), c_id, "action_sequenceがA→Cになること")

	# 保存→読込→実Battleでも、Bが完全に消えていることを直接確認する。
	var result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))

	var start_result := RBMDefinitionLoader.start_battle(restored.to_definition(), 777)
	assert_true(bool(start_result.get("ok", false)), "sanity: %s" % str(start_result.get("errors", [])))
	var battle: RBMBattle = start_result["battle"]

	var turn1_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn1_boss.size(), 1, "sanity")
	assert_eq(str(turn1_boss[0].get("skill_id", "")), a_id, "turn1はAが実行されること")

	var turn2_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn2_boss.size(), 1, "sanity: ボスは行動しなくても「何もしなかった」という1件のログを残す")
	assert_eq(str(turn2_boss[0].get("action", "")), "none", "turn2はA(turn_at1)もC(turn_at3)も条件を満たさず何もしない——Bは一切現れない")

	var turn3_boss := _boss_log_entries(_resolve_one_ally_turn(battle))
	assert_eq(turn3_boss.size(), 1, "sanity")
	assert_eq(str(turn3_boss[0].get("skill_id", "")), c_id, "turn3はCが実行されること")

## C. random候補削除→保存: 既存のランダムスロット(A/B/C)を編集画面で開き、
## Bだけを削除して保存すると、Bだけdraft.skillsから消え、候補もA/Cのみに
## なり、保存→読込後もBは復活しない。
func test_orphan_C_removing_one_random_candidate_from_an_existing_slot_and_saving_deletes_only_that_skill_and_does_not_resurrect_on_reload() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "A")
	var a_id := str((advanced._random_candidates[0] as Dictionary).get("skill_id", ""))
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "B")
	var b_id := str((advanced._random_candidates[1] as Dictionary).get("skill_id", ""))
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "C")
	var c_id := str((advanced._random_candidates[2] as Dictionary).get("skill_id", ""))
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	var slot_id := str(creator.draft.action_sequence[0].get("slot_id", ""))

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	assert_true(advanced._random_editor_view.visible, "sanity")
	advanced._random_candidate_list.find_child("DeleteRandomCandidateButton_1", true, false).pressed.emit()  # remove B
	_btn(advanced, "RandomConfirmButton").pressed.emit()

	assert_true(creator.draft.find_skill(b_id).is_empty())
	assert_false(creator.draft.find_skill(a_id).is_empty())
	assert_false(creator.draft.find_skill(c_id).is_empty())
	var slot := creator.draft.find_action_slot(slot_id)
	var candidates: Array = slot.get("candidates", [])
	assert_eq(candidates.size(), 2)

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

## A. random候補（複数件）を編集後、ランダム攻撃全体をキャンセルすると
## 全ての編集内容が元へ戻る——旧「1つのpatternセッション内で複数の固定
## 行動を編集後にキャンセルすると全て戻る」(旧②C)の精神を、新設計で唯一
## 複数skillを1セッション内で編集しうる場所（ランダム攻撃の複数候補）へ
## 適用したもの。battle_content_snapshot()の完全一致・Clear Check維持も
## 併せて確認する。
func test_cancel_A_multiple_random_candidate_edits_within_one_session_all_revert_on_whole_slot_cancel() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "Fire", 1.0)
	var candidate_a_id := str((advanced._random_candidates[0] as Dictionary).get("skill_id", ""))
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "Ice", 2.0)
	var candidate_b_id := str((advanced._random_candidates[1] as Dictionary).get("skill_id", ""))
	_btn(advanced, "RandomConfirmButton").pressed.emit()

	var snapshot_before := creator.draft.battle_content_snapshot()
	creator.draft.record_clear_check_success()
	assert_true(creator.draft.is_clear_check_currently_valid(), "sanity")

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	advanced._edit_random_candidate_performance(0)
	advanced._form._attack_multiplier_spin.value = 9.99
	advanced._form._on_save_pressed()
	assert_eq(float(creator.draft.find_skill(candidate_a_id).get("atk_multiplier", -1.0)), 9.99, "sanity: フォーム保存は即座にdraft.skillsへ反映される")
	advanced._edit_random_candidate_performance(1)
	advanced._form._attack_multiplier_spin.value = 8.88
	advanced._form._on_save_pressed()
	assert_eq(float(creator.draft.find_skill(candidate_b_id).get("atk_multiplier", -1.0)), 8.88, "sanity")

	_btn(advanced, "RandomCancelButton").pressed.emit()
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

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "新名"
	advanced._form._attack_multiplier_spin.value = 5.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

	var card: VBoxContainer = advanced._slot_list.get_child(0)
	var texts := PackedStringArray()
	for child in card.get_children():
		if child is Label:
			texts.append((child as Label).text)
	var joined := "\n".join(texts)
	assert_true(joined.contains("新名"), "カード要約が新しい内容へ更新されること: %s" % joined)
	assert_true(joined.contains("威力500"), "威力表示も更新されること: %s" % joined)

func test_fixed_action_edit_save_propagates_to_definition_and_real_battle_damage() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)  # boss.atk=100
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	var skill_id := _create_skill_slot(advanced, "旧名", 1.0)

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._name_edit.text = "新名"
	advanced._form._attack_multiplier_spin.value = 5.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()

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
	_btn(simple, "AddNormalActionButton").pressed.emit()
	simple._form._name_edit.text = "通常行動"
	simple._form._on_save_pressed()
	assert_eq(creator.draft.normal_action_percentages.size(), 1, "sanity")
	var skill_id := str(creator.draft.normal_action_percentages.keys()[0])
	assert_false(creator.draft.find_skill(skill_id).is_empty(), "sanity")

	var delete_button: Button = simple._normal_list.find_child("DeleteNormalActionButton_%s" % skill_id, true, false)
	assert_not_null(delete_button)
	delete_button.pressed.emit()
	assert_true(creator.draft.find_skill(skill_id).is_empty(), "未参照になった通常行動skillが消えること")
	assert_false(creator.draft.normal_action_percentages.has(skill_id))

func test_simple_scripted_action_delete_removes_unreferenced_skill() -> void:
	var creator := _new_creator()
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view
	_btn(simple, "AddScriptedActionButton").pressed.emit()
	_btn(simple, "ScriptedWhenNextButton").pressed.emit()
	simple._form._name_edit.text = "指定行動"
	simple._form._on_save_pressed()
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
	var delete_normal_button: Button = simple._normal_list.find_child("DeleteNormalActionButton_%s" % shared_id, true, false)
	assert_not_null(delete_normal_button)
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
	var delete_scripted_button: Button = simple._scripted_list.find_child("DeleteScriptedActionButton_0", true, false)
	assert_not_null(delete_scripted_button)
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
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "固定攻撃を実際に編集して保存すると失効すること")

func test_clear_check_invalidates_on_random_candidate_performance_edit_and_confirm() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補", 1.0)
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	creator.draft.record_clear_check_success()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	advanced._edit_random_candidate_performance(0)
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "ランダム候補を実際に編集して保存すると失効すること")

func test_clear_check_invalidates_on_slot_delete() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	advanced._slot_list.find_child("DeleteSlotButton_0", true, false).pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "スロット削除で失効すること")

func test_clear_check_invalidates_on_random_candidate_delete_within_editor() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "A")
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "B")
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	creator.draft.record_clear_check_success()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	advanced._random_candidate_list.find_child("DeleteRandomCandidateButton_0", true, false).pressed.emit()
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_false(creator.draft.is_clear_check_currently_valid(), "ランダム候補削除で失効すること")

func test_clear_check_preserved_when_fixed_slot_performance_edit_form_is_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotEditPerformanceButton").pressed.emit()
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "CancelActionButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "ActionEditorForm単体のキャンセルでは変更しないため失効しないこと")

func test_clear_check_preserved_when_random_candidate_performance_edit_form_is_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補")
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	creator.draft.record_clear_check_success()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	advanced._edit_random_candidate_performance(0)
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "CancelActionButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid())

func test_clear_check_preserved_when_skill_edit_saved_then_whole_random_session_cancelled() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	_btn(advanced, "RandomAddCandidateButton").pressed.emit()
	_btn(advanced, "RandomAddChoiceCreateNewButton").pressed.emit()
	_fill_and_save_form(advanced._form, "候補")
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	creator.draft.record_clear_check_success()

	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	advanced._edit_random_candidate_performance(0)
	advanced._form._attack_multiplier_spin.value = 9.0
	_btn(advanced._form, "SaveActionButton").pressed.emit()
	_btn(advanced, "RandomCancelButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "候補編集を保存した後もランダム攻撃全体をキャンセルすれば失効しないこと")

func test_clear_check_preserved_when_slot_editor_opened_but_untouched() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var setup := _draft_with_saved_skill_slot_and_clear_check(creator)
	var advanced: RBMCreatorStep4ActionPatterns = setup["advanced"]
	advanced._slot_list.find_child("EditSlotButton_0", true, false).pressed.emit()
	_btn(advanced, "SkillSlotCancelButton").pressed.emit()
	assert_true(creator.draft.is_clear_check_currently_valid(), "スロット編集画面を開いただけでは失効しないこと")

# =============================================================================
# ⑧同名行動の独立性
# =============================================================================

func test_same_name_actions_in_different_places_are_independent() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var step3 := _step3(creator)
	var simple: RBMCreatorStep4Actions = step3._simple_view
	_btn(simple, "AddNormalActionButton").pressed.emit()
	simple._form._name_edit.text = "炎"
	simple._form._attack_multiplier_spin.value = 1.0
	simple._form._on_save_pressed()
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
	assert_eq(str(restored.action_sequence[0].get("skill_id", "")), advanced_skill_id, "保存→読込後もHARDCORE側は同じskill_idのまま")

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

## test_same_name_actions_in_different_places_are_independentはDraft/保存/
## 編集レベルでの独立性を証明済みだが、その構成（SIMPLE通常行動+HARDCORE
## 固定攻撃が同一Draftに同居）は実は実Battleを起動しても片方(SIMPLE側の
## "炎")が絶対に発火しない——action_sequenceが非空なら、RBMBattleは
## normal_action_percentages/scripted_actionsを完全に無視する仕様
## （rbm_battle.gd _resolve_boss_turn_actions()参照）だからである。そのため、
## ここでは同じ目的（同名「炎」skillが2つとも実際に発動し、それぞれ自分
## 固有の性能を使うこと）を、実Battleを確実に駆動できる構成（HARDCOREの
## 2スロット、それぞれturn_at条件で担当ターンを分離）で直接検証する。
func test_same_name_actions_fire_with_independent_performance_in_real_battle() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)  # boss.atk=100, boss.spd=50<hero.spd100
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	var skill_a := _create_skill_slot_at_turn(advanced, "炎", 1, 1.0)
	var skill_b := _create_skill_slot_at_turn(advanced, "炎", 2, 3.0)

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
	creator.draft.hp = 999999
	creator.draft.atk = 10
	# hero(data_bossmaker/allies/hero.json)のspd=100より低くし、各ターン
	# 「味方が先に行動→ボスが応答する」という_resolve_one_ally_turn()の
	# 前提を保つ。
	creator.draft.spd = 10
	creator.draft.add_party_character("hero")
	var step3 := _open_advanced(creator)
	var advanced := step3._advanced_view

	# slot0: 1ターン目に「先制技」を使う。
	var opener_id := _create_skill_slot_at_turn(advanced, "先制技", 1)

	# slot1: 「前回使った行動」が先制技なら「追撃」を使う——実UIで「前回
	# 使った行動」プルダウンから実際にそのskillを選ぶ（item_count確認だけで
	# 済ませない）。ラウンドロビン方式ではturn_at条件を追加する必要は無い
	# ——slot0が発火した直後にcursorがslot1へ進み、last_boss_skill条件が
	# ちょうどその瞬間成立しているためそのまま発火する。
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	advanced._form._name_edit.text = "追撃"
	_btn(advanced, "AddConditionButton").pressed.emit()
	advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("last_boss_skill"))
	advanced._on_condition_type_selected(advanced._condition_type_option.selected)
	var opener_index := -1
	for i in range(creator.draft.skills.size()):
		if str(creator.draft.skills[i].get("skill_id", "")) == opener_id:
			opener_index = i
	assert_true(opener_index >= 0, "sanity")
	advanced._condition_boss_skill_option.select(opener_index)
	_btn(advanced, "ConfirmConditionButton").pressed.emit()
	assert_eq(str(advanced._pending_conditions[0].get("skill_id", "")), opener_id, "UI選択で正しいskill_idがDraftへ保存されること")
	_btn(advanced, "SkillSlotConfirmButton").pressed.emit()
	var pursuit_id := str(creator.draft.action_sequence[1].get("skill_id", ""))

	var save_result := RBMLocalStageRepository.save_new(creator.draft)
	assert_true(bool(save_result.get("ok", false)))
	var loaded := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.action_sequence.size(), 2, "sanity: 両スロットが保存・復元されること")
	var restored_condition: Dictionary = ((restored.action_sequence[1] as Dictionary).get("conditions", []) as Array)[0]
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
