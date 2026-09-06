extends GutTest

## Phase 3.5 Step 3 — 戦闘入力の正当性修正。
##
## ①SP不足スキルをUIから選択できないようにする
## ②選択不可能な対象をターゲット候補から除外する（RBMBattle.is_valid_skill_target()
##   を唯一の判定源とする）
## ③無効入力（insufficient_sp/invalid_target/unknown_skill/invalid_action）では
##   手番を消費しない（RBMBattle.resolve_pending_ally_action()の
##   "action_voided"マーカー）
## ④TEST/Clear Check開始・再開始時に前回ログを初期化する（CHALLENGEと同じ
##   考え方）
##
## Creator TEST / Clear Check / CHALLENGEの3画面すべてで同じ挙動になることを
## 直接検証する。party=[hero, butler]（butler.spd=120 > hero.spd=100、boss.spd=1
## で両者ともボスより確実に先に行動する）を共通fixtureとして使う。

const TEST_DIR := "user://bossmaker_test_phase35_step3/stages"

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

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## boss.hp is enormous so the boss never actually dies mid-test (battle_over
## must stay false for every scenario here — none of these tests are about
## win/loss). boss.spd=1 so both hero(spd100)/butler(spd120) always act
## before the boss, matching this test file's own established convention
## (test_rbm_phase3_hardcore_overrides.gd's _draft()).
func _definition_with_hero_and_butler() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "Phase35Step3ボス"
	draft.hp = 999999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.add_party_character("butler")
	return draft.to_definition()

func _new_main() -> RBMCreatorMain:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	return main

func _new_challenge_view() -> RBMChallengeBattleView:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	return view

# =============================================================================
# A. SP不足スキル
# =============================================================================

## butler_grand_ice(sp_cost=60, butler.max_sp=150)を使い、SP十分/不足の両方で
## ボタンのdisabled状態とテキストを直接確認する。3画面とも同一の結果になる
## ことを1つのテストで横断確認する。
func test_A_sp_sufficient_skill_button_is_enabled_and_insufficient_is_disabled_across_all_three_screens() -> void:
	var definition := _definition_with_hero_and_butler()

	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)
	var challenge_view := await _new_challenge_view()
	challenge_view.start_battle(definition)

	for view in [main._test_battle_view, main._clear_check_view, challenge_view]:
		var butler: RBMUnit = view.session.battle.party[1]
		assert_eq(str(butler.character_id), "butler", "sanity: party[1] is always butler regardless of SPD-derived turn order")

		# SP十分（満タン）: 選択可能。
		# _refresh_command_area()は旧ボタンをqueue_free()（次フレームまで
		# ツリーに残る）してから新ボタンを追加するため、find_child()が古い
		# 世代のボタンを拾わないよう1フレーム待ってから確認する。
		butler.sp = butler.max_sp
		view.refresh()
		await get_tree().process_frame
		var enabled_button := view.find_child("SkillButton_butler_grand_ice", true, false) as Button
		assert_not_null(enabled_button)
		assert_false(enabled_button.disabled, "%s: SP十分なら選択可能であること" % view.get_class())
		assert_false(enabled_button.text.contains("SP不足"), "%s: SP十分ならSP不足の表示を出さないこと" % view.get_class())

		# SP不足: 選択不可・SP不足であることが分かる表示。
		butler.sp = 10  # butler_grand_ice.sp_cost=60 を下回る
		view.refresh()
		await get_tree().process_frame
		var disabled_button := view.find_child("SkillButton_butler_grand_ice", true, false) as Button
		assert_not_null(disabled_button)
		assert_true(disabled_button.disabled, "%s: SP不足なら選択不可であること" % view.get_class())
		assert_true(disabled_button.text.contains("SP不足"), "%s: SP不足であることがUI上で分かること: %s" % [view.get_class(), disabled_button.text])

## Battleへ直接insufficient_spな行動を入力した場合も同じ結果になり、かつ
## 手番が消費されない（同じユニットがpending_ally_id()のまま、round_cursor()
## が変化しない）ことを、RBMBattle自体に対して直接確認する——UIを経由しない、
## 最終防御ラインの検証。
func test_A_battle_rejects_insufficient_sp_directly_and_does_not_consume_the_turn() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	assert_true(bool(start_result.get("ok", false)), "sanity")
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action(), "sanity")
	var pending_before := battle.pending_ally_id()
	var cursor_before := battle.round_cursor()
	assert_eq(str(battle.party[pending_before].character_id), "butler", "sanity: butler(spd120) acts before hero(spd100)")

	var butler := battle.party[pending_before]
	butler.sp = 10  # butler_grand_ice.sp_cost=60 を下回る
	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "butler_grand_ice", "target_id": -1})

	assert_eq(log.size(), 1, "sanity")
	assert_true(bool(log[0].get("failed", false)))
	assert_eq(str(log[0].get("reason", "")), "insufficient_sp")
	assert_eq(butler.sp, 10, "SPは一切消費されていないこと")
	assert_eq(battle.round_cursor(), cursor_before, "手番が進んでいないこと（無効操作＝行動していない）")
	assert_true(battle.is_waiting_for_ally_action(), "同じユニットの入力待ちのままであること")
	assert_eq(battle.pending_ally_id(), pending_before, "pending_ally_idが変化していないこと")

# =============================================================================
# B. 無効ターゲット（老執事の「SP回復」＝butler_sp_gift、自分自身が無効対象）
# =============================================================================

func test_B_invalid_target_is_excluded_from_the_picker_and_valid_target_remains_across_all_three_screens() -> void:
	var definition := _definition_with_hero_and_butler()

	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)
	var challenge_view := await _new_challenge_view()
	challenge_view.start_battle(definition)

	for view in [main._test_battle_view, main._clear_check_view, challenge_view]:
		var butler: RBMUnit = view.session.battle.party[1]
		var hero: RBMUnit = view.session.battle.party[0]
		butler.sp = butler.max_sp  # butler_sp_gift.sp_cost=30を満たしておく（①の対象外にする）。
		view.refresh()

		view.act_skill(butler.id, "butler_sp_gift")
		assert_true(view._target_picker.visible, "%s: sp_recover_single_no_selfは対象選択を経由すること" % view.get_class())

		var self_button: Button = view._target_picker.find_child(butler.display_name, true, false)
		# 候補ボタンは名前ではなくtextで識別されるため（既存実装、_open_target_picker
		# 参照）、_target_pickerの子を直接走査してテキスト一致で判定する。
		var self_present := false
		var hero_present := false
		for child in view._target_picker.get_children():
			var button := child as Button
			if button == null:
				continue
			if button.text == butler.display_name:
				self_present = true
			if button.text == hero.display_name:
				hero_present = true
		assert_false(self_present, "%s: 自分自身（無効対象）が候補に出ないこと" % view.get_class())
		assert_true(hero_present, "%s: 正しい対象（hero）は候補にあること" % view.get_class())

## Battleへ直接invalid_targetな行動（butler_sp_giftを自分自身へ）を入力した
## 場合も同じ結果になり、かつ手番が消費されないことを直接確認する。
func test_B_battle_rejects_invalid_target_directly_and_does_not_consume_the_turn() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	var pending_before := battle.pending_ally_id()
	var cursor_before := battle.round_cursor()
	var butler := battle.party[pending_before]
	assert_eq(str(butler.character_id), "butler", "sanity")
	butler.sp = butler.max_sp

	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "butler_sp_gift", "target_id": butler.id})

	assert_eq(log.size(), 1, "sanity")
	assert_true(bool(log[0].get("failed", false)))
	assert_eq(str(log[0].get("reason", "")), "invalid_target")
	assert_eq(butler.sp, butler.max_sp, "SPは一切消費されていないこと")
	assert_eq(battle.round_cursor(), cursor_before, "手番が進んでいないこと")
	assert_true(battle.is_waiting_for_ally_action())
	assert_eq(battle.pending_ally_id(), pending_before)

## RBMBattle.is_valid_skill_target()自体を直接確認する——UIが呼ぶ唯一の判定
## 関数の単体テスト（自分自身は無効、生存する他の味方は有効、戦闘不能の対象も
## 無効）。
func test_B_is_valid_skill_target_matches_battle_own_validation_rule() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	var battle: RBMBattle = start_result["battle"]
	var hero := battle.party[0]
	var butler := battle.party[1]
	assert_false(battle.is_valid_skill_target(butler.id, "butler_sp_gift", butler.id), "自分自身は無効")
	assert_true(battle.is_valid_skill_target(butler.id, "butler_sp_gift", hero.id), "生存する他の味方は有効")
	hero.hp = 0
	assert_false(battle.is_valid_skill_target(butler.id, "butler_sp_gift", hero.id), "戦闘不能の対象は無効")

# =============================================================================
# C. TESTログ初期化
# =============================================================================

func test_C_test_battle_log_is_cleared_on_start_and_restart() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	_btn(main._test_battle_view, "AttackButton").pressed.emit()
	assert_false(main._test_battle_view._log_label.text.is_empty(), "sanity: 何らかのログが出ていること")

	# 再開始 (retry): 旧ログが残っていないこと。
	main._test_battle_view.retry()
	assert_eq(main._test_battle_view._log_label.text, "", "retry()直後に旧ログが残っていないこと")

	# 新しいアクションでまたログが出ることを確認してから、もう一度start()。
	_btn(main._test_battle_view, "AttackButton").pressed.emit()
	assert_false(main._test_battle_view._log_label.text.is_empty(), "sanity")
	assert_true(main._test_battle_view.start(definition, 2), "sanity")
	assert_eq(main._test_battle_view._log_label.text, "", "start()直後に旧ログが残っていないこと")

# =============================================================================
# D. Clear Checkログ初期化
# =============================================================================

func test_D_clear_check_log_is_cleared_on_start_and_restart() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)
	_btn(main._clear_check_view, "AttackButton").pressed.emit()
	assert_false(main._clear_check_view._log_label.text.is_empty(), "sanity: 何らかのログが出ていること")

	# 最初からやり直す（確認ダイアログ経由）: 旧ログが残っていないこと。
	_btn(main._clear_check_view, "RestartButton").pressed.emit()
	_btn(main._clear_check_view, "RestartConfirmButton").pressed.emit()
	assert_eq(main._clear_check_view._log_label.text, "", "最初からやり直す直後に旧ログが残っていないこと")

	# 新しいアクションでまたログが出ることを確認してから、もう一度start_battle()。
	_btn(main._clear_check_view, "AttackButton").pressed.emit()
	assert_false(main._clear_check_view._log_label.text.is_empty(), "sanity")
	main._clear_check_view.start_battle(definition, 2)
	assert_eq(main._clear_check_view._log_label.text, "", "start_battle()直後に旧ログが残っていないこと")

# =============================================================================
# E. CHALLENGE回帰（既存挙動が壊れていないことの確認、Phase 3.5 Step 3自体は
##    CHALLENGEのログ初期化ロジックを変更していない——test_rbm_e2e_full_journey.gd
##    でも既存カバレッジがあるが、TEST/Clear Checkと横並びで3画面一貫性を
##    ここでも直接確認する）
# =============================================================================

func test_E_challenge_log_is_cleared_on_start_and_restart_unchanged() -> void:
	var view := await _new_challenge_view()
	var definition := _definition_with_hero_and_butler()
	view.start_battle(definition)
	_btn(view, "AttackButton").pressed.emit()
	assert_false(view._log_label.text.is_empty(), "sanity")

	_btn(view, "RestartButton").pressed.emit()
	_btn(view, "RestartConfirmButton").pressed.emit()
	assert_eq(view._log_label.text, "", "最初からやり直す直後に旧ログが残っていないこと")

	_btn(view, "AttackButton").pressed.emit()
	assert_false(view._log_label.text.is_empty(), "sanity")
	view.start_battle(definition)
	assert_eq(view._log_label.text, "", "start_battle()直後に旧ログが残っていないこと")

# =============================================================================
# 7. 既存仕様の回帰確認（通常攻撃・スキル使用・SP消費・SP回復・SPD順・
##    ターン進行・敵行動・REWIND・勝敗判定は無改修であることの直接確認）
# =============================================================================

## 正常系（SP十分・対象妥当）は今回の変更後も従来どおり実行され、手番も
## 正しく1つ進むことを確認する——action_voidedの導入が正常系の手番進行を
## 損なっていないことの直接証拠。
func test_normal_valid_actions_still_consume_the_turn_and_apply_effects_normally() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	var pending_before := battle.pending_ally_id()
	var cursor_before := battle.round_cursor()
	var butler := battle.party[pending_before]
	assert_eq(str(butler.character_id), "butler", "sanity")
	var boss_hp_before := battle.boss.hp

	var log := battle.resolve_pending_ally_action({"type": "skill", "skill_id": "butler_ice_bolt", "target_id": -1})

	assert_eq(log.size(), 1, "sanity")
	assert_false(bool(log[0].get("failed", false)), "正常なスキル使用は失敗しないこと")
	assert_false(bool(log[0].get("action_voided", false)), "正常な行動にaction_voidedは立たないこと")
	assert_lt(battle.boss.hp, boss_hp_before, "ダメージが実際に適用されること")
	assert_eq(butler.sp, butler.max_sp - 15, "SPが正しく消費されること（butler_ice_bolt.sp_cost=15）")
	assert_gt(battle.round_cursor(), cursor_before, "正常な行動は手番を消費し、次のユニットへ進むこと")

## 通常攻撃によるSP回復（RBMConstants.NORMAL_ATTACK_SP_GAIN）が無改修である
## ことの直接確認。
func test_normal_attack_still_recovers_sp() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	var butler := battle.party[battle.pending_ally_id()]
	butler.sp = 0
	battle.resolve_pending_ally_action({"type": "attack"})
	assert_eq(butler.sp, RBMConstants.NORMAL_ATTACK_SP_GAIN, "通常攻撃のSP回復量は無改修であること")

## SPD順（butler(120) > hero(100) > boss(1)）とターン進行が無改修であることの
## 直接確認。
func test_spd_order_and_turn_progression_unchanged() -> void:
	var start_result := RBMDefinitionLoader.start_battle(_definition_with_hero_and_butler(), 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	assert_eq(str(battle.party[battle.pending_ally_id()].character_id), "butler")
	battle.resolve_pending_ally_action({"type": "attack"})
	battle.advance_to_next_decision()
	assert_eq(str(battle.party[battle.pending_ally_id()].character_id), "hero")
	assert_eq(battle.current_turn, 1, "sanity: still turn 1")
	battle.resolve_pending_ally_action({"type": "attack"})
	battle.advance_to_next_decision()
	assert_eq(battle.current_turn, 2, "boss(spd1)は自動解決され、両味方の行動後にturn 2へ進むこと")

## REWINDが無改修であることの直接確認（今回のaction_voided導入後もsnapshot/
## restoreの往復が正しく機能する）。
func test_rewind_still_works_after_the_action_voided_change() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var session := main._test_battle_view.session
	assert_true(session.reachable_turns().has(1), "sanity")
	session.resolve_ally_action({"type": "attack"})
	session.resolve_ally_action({"type": "attack"})
	assert_true(session.rewind_to(1), "REWINDが引き続き成功すること")
	assert_eq(session.battle.current_turn, 1)

## 勝敗判定が無改修であることの直接確認（boss.hp=1なら1撃で確実に勝利する）。
func test_victory_condition_unchanged() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "勝敗テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	var start_result := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	battle.resolve_pending_ally_action({"type": "attack"})
	battle.advance_to_next_decision()
	assert_true(battle.battle_over)
	assert_eq(battle.winner, "ally")
