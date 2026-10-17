extends GutTest

## プレイ体験監査（2026-10-16）の P1 の修正（2026-10-17）の回帰テスト。
## - PX-01 終了・やり直しの確認と結果パネルの重なり（テストバトル・クリアチェック・挑戦）
## - PX-02 通常行動の使用率0%（SIMPLE の初期値・検証、HARDCORE の「自分で設定」のランダム攻撃）
## - 回復量の上限 99,999（入力・検証・保存・読み込み）
## - PX-04 一覧の通信が返らない時に、ほかのカテゴリまで止まらない
## - PX-05 保存したボス戦の一覧の公開状態（オンライン公開）
## - PX-06 全体攻撃の結果が最新の行動の欄に全員分収まる
## - PX-14 通信の失敗を人が読める文で出す
## - PX-25・PX-26 英語の翻訳（書式の順番・討伐記録）
## 戦闘の計算・乱数・保存の形には触れない（画面の表示・作成の入力の検証だけ）。

var _saved_locale := "ja"
var _dir := ""

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()
	_dir = "user://bossmaker_test_play_audit_fixes/stages"
	RBMLocalStageRepository.set_stages_dir_for_testing(_dir)
	_clear_dir(_dir)

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)
	_clear_dir(_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	if FileAccess.file_exists(STEAM_APPID_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STEAM_APPID_PATH))
	await get_tree().process_frame

func _clear_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))

func _new_main() -> RBMCreatorMain:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	return main

func _btn(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button

## HP1 のボス（最初の一撃で決着する）
func _one_hit_definition() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "一撃のボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	return draft.to_definition()

func _simple(main: RBMCreatorMain) -> RBMCreatorStep4Actions:
	main.go_to_step(3)
	return (main._step_views[2] as RBMCreatorStep4)._simple_view

# =============================================================================
# PX-01 確認と結果パネルの重なり
# =============================================================================

func test_test_battle_closes_the_quit_confirm_when_the_result_shows_and_on_retry() -> void:
	var main := await _new_main()
	var view := main._test_battle_view
	assert_true(view.start(_one_hit_definition()), "sanity")
	view._on_quit_pressed()
	assert_true(view._quit_confirm.visible, "sanity: 「テストを終了しますか？」が開いている")
	_btn(view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(view.session.battle.battle_over, "sanity: 一撃で決着")
	assert_true(view._outcome_area.visible, "結果パネルが出る")
	assert_false(view._quit_confirm.visible, "結果パネルの下に終了の確認を残さない")
	view._on_quit_pressed()
	view.retry()
	assert_false(view._quit_confirm.visible, "もう一度テストの後に確認が残らない")

func test_challenge_closes_quit_and_restart_confirms_when_the_result_shows_and_on_restart() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	view.start_battle(_one_hit_definition())
	view._quit_confirm.visible = true
	view._restart_confirm.visible = true
	_btn(view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(view.session.battle.battle_over, "sanity")
	assert_true(view._outcome_area.visible)
	assert_false(view._quit_confirm.visible, "結果パネルの下に「挑戦を終了しますか？」を残さない")
	assert_false(view._restart_confirm.visible)
	view._quit_confirm.visible = true
	view._do_restart()
	assert_false(view._quit_confirm.visible, "やり直しの後に確認が残らない")

func test_clear_check_closes_the_restart_confirm_when_the_result_shows() -> void:
	var main := await _new_main()
	main.draft.boss_name = "一撃のボス"
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	main.press_clear_check()
	assert_true(bool(main.press_clear_check_start(1).get("ok", false)), "sanity")
	var view := main._clear_check_view
	view._restart_confirm.visible = true
	_btn(view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(view.session.battle.battle_over, "sanity")
	assert_false(view._restart_confirm.visible, "結果パネルの下に「最初からやり直しますか？」を残さない")

# =============================================================================
# PX-02 通常行動の使用率（SIMPLE）
# =============================================================================

func _add_normal_via_ui(simple: RBMCreatorStep4Actions, action_name: String) -> void:
	_btn(simple, "AddNormalActionButton").pressed.emit()
	if simple._add_choice_view.visible:
		_btn(simple, "AddChoiceCreateNewButton").pressed.emit()
	simple._form._name_edit.text = action_name
	_btn(simple, "ActionConfirmButton").pressed.emit()

func test_simple_first_normal_action_is_100_percent_and_the_boss_uses_it() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "かみつき")
	assert_eq(main.draft.normal_action_percentages.values(), [100.0], "最初の通常行動は100%")
	assert_true(main.draft.normal_actions_enabled)
	assert_true(simple.is_step_valid())
	main.draft.boss_name = "使用率のボス"
	main.draft.hp = 1000
	main.draft.atk = 10
	main.draft.add_party_character("hero")
	var normal: Array = main.draft.to_definition()["boss"]["normal_actions"]
	assert_eq(normal.size(), 1, "戦闘の定義にも通常行動が入る（ボスが行動しないままにならない）")

func test_simple_adding_to_an_even_split_keeps_it_even() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "A")
	_add_normal_via_ui(simple, "B")
	assert_eq(main.draft.normal_action_percentages.values(), [50.0, 50.0])
	_add_normal_via_ui(simple, "C")
	assert_almost_eq(main.draft.normal_action_percentage_total(), 100.0, 0.001, "均等のまま合計100%")
	for v in main.draft.normal_action_percentages.values():
		assert_almost_eq(float(v), 33.3, 0.11)

func test_simple_adding_to_a_custom_split_uses_the_remaining_percent() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "A")
	_add_normal_via_ui(simple, "B")
	var ids: Array = main.draft.normal_action_percentages.keys()
	simple.set_percentage(str(ids[0]), 60.0)
	simple.set_percentage(str(ids[1]), 30.0)
	_add_normal_via_ui(simple, "C")
	var c_id := str(main.draft.normal_action_percentages.keys()[2])
	assert_almost_eq(float(main.draft.normal_action_percentages[c_id]), 10.0, 0.001, "残りの10%")
	assert_eq(float(main.draft.normal_action_percentages[ids[0]]), 60.0, "作者が決めた割合は変えない")
	assert_true(simple.is_step_valid())

func test_simple_all_zero_normal_actions_block_next_with_a_reason() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "A")
	var id := str(main.draft.normal_action_percentages.keys()[0])
	simple.set_percentage(id, 0.0)
	assert_false(simple.is_step_valid(), "通常行動が全部0%（ボスが一度も使わない）なら先へ進めない")
	assert_true(simple.validation_message().contains("0%"), simple.validation_message())
	assert_not_null(simple.find_child("NormalActionZeroNote_%s" % id, true, false), "カードに「使われません」と出る")

func test_simple_scripted_action_can_reuse_an_existing_action() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "かみつき")
	var skill_id := str(main.draft.skills[0].get("skill_id", ""))
	_btn(simple, "AddScriptedActionButton").pressed.emit()
	assert_true(simple._add_choice_view.visible, "既存の行動があれば追加の方法を選ぶ（HARDCORE と同じ）")
	_btn(simple, "AddChoicePickExistingButton").pressed.emit()
	_btn(simple, "PickExistingSkillButton_0").pressed.emit()
	simple._scripted_turn_spin.value = 3
	_btn(simple, "ActionConfirmButton").pressed.emit()
	assert_eq(main.draft.skills.size(), 1, "新しい行動は作らない")
	assert_eq(main.draft.scripted_actions, [{"turn": 3, "skill_id": skill_id, "timing": "replace"}])
	# 通常行動から外しても、指定行動が使っているので行動は残る
	simple._on_delete_normal_pressed(skill_id)
	assert_false(main.draft.find_skill(skill_id).is_empty())

func test_simple_cancel_after_editing_performance_restores_the_action() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_add_normal_via_ui(simple, "かみつき")
	var skill_id := str(main.draft.skills[0].get("skill_id", ""))
	_btn(simple, "EditNormalActionButton_%s" % skill_id).pressed.emit()
	_btn(simple, "EditPerformanceButton").pressed.emit()
	simple._form._name_edit.text = "変えた名前"
	simple._form._on_save_pressed()
	assert_eq(str(main.draft.find_skill(skill_id).get("name", "")), "変えた名前", "sanity")
	_btn(simple, "ActionCancelButton").pressed.emit()
	assert_eq(str(main.draft.find_skill(skill_id).get("name", "")), "かみつき", "設定画面のキャンセルで元に戻る")

func test_simple_new_action_needs_a_name() -> void:
	var main := await _new_main()
	var simple := _simple(main)
	_btn(simple, "AddNormalActionButton").pressed.emit()
	_btn(simple, "ActionConfirmButton").pressed.emit()
	assert_true(main.draft.skills.is_empty(), "名前が空なら作らない")
	assert_true(simple._editor_view.visible, "設定画面のまま")
	assert_true(simple._editor_error_label.visible, "理由を出す")

func test_simple_existing_save_with_zero_percent_entries_still_loads() -> void:
	# 以前の版で0%のまま保存された通常行動（ボスが使わない）も、書き換えずに読み込める
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "古い保存"
	var id := draft.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_action_percentages[id] = 0.0
	var saved := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(saved.get("ok", false)), "sanity")
	var loaded := RBMLocalStageRepository.load_stage(str(saved.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(float(restored.normal_action_percentages[id]), 0.0, "値は書き換えない")
	assert_false(restored.step4_is_valid(), "作成画面で直すように知らせる")

# =============================================================================
# PX-02 HARDCORE の「自分で設定」のランダム攻撃
# =============================================================================

func _open_advanced(main: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.go_to_step(3)
	return (main._step_views[2] as RBMCreatorStep4)._advanced_view

func test_hardcore_manual_random_never_confirms_with_a_total_other_than_100() -> void:
	var main := await _new_main()
	var advanced := _open_advanced(main)
	var a := main.draft.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var b := main.draft.add_skill({"name": "B", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateRandomButton").pressed.emit()
	advanced._on_random_add_choice_pick_existing_pressed()
	advanced._on_random_pick_existing_skill_selected(a)
	advanced._on_random_add_choice_pick_existing_pressed()
	advanced._on_random_pick_existing_skill_selected(b)
	advanced._random_mode_option.select(RBMActionPatternRules.RANDOM_MODES.find(RBMActionPatternRules.RANDOM_MODE_MANUAL))
	advanced._on_random_mode_selected(advanced._random_mode_option.selected)
	assert_almost_eq(advanced._random_manual_total(), 100.0, 0.001, "全部0%なら「自分で設定」へ切り替えた時に均等に分ける")
	advanced._set_random_candidate_weight(0, 10.0)
	assert_true(advanced._random_total_label.visible)
	assert_true(advanced._random_total_label.text.contains("100%"), advanced._random_total_label.text)
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_true(main.draft.action_sequence.is_empty(), "合計が100%でなければ確定しない")
	advanced._set_random_candidate_weight(0, 50.0)
	_btn(advanced, "RandomConfirmButton").pressed.emit()
	assert_eq(main.draft.action_sequence.size(), 1)

# =============================================================================
# 回復量の上限 99,999
# =============================================================================

func test_heal_amount_input_stops_at_99999_in_both_modes() -> void:
	var main := await _new_main()
	for form in [_simple(main)._form, _open_advanced(main)._form]:
		var f: RBMActionEditorForm = form
		assert_eq(f._self_heal_fixed_spin.max_value, 99999.0)
		assert_eq(f._awakening_heal_fixed_spin.max_value, 99999.0, "覚醒のHP回復も同じ上限")
		f._self_heal_fixed_spin.value = 100000
		assert_eq(int(f._self_heal_fixed_spin.value), 99999)
		f._self_heal_fixed_spin.value = 99999
		assert_eq(int(f._self_heal_fixed_spin.value), 99999, "99,999 は設定できる")

func test_over_limit_heal_from_an_old_save_is_kept_reported_and_not_saved_again() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "上限を超えた古い保存"
	draft.add_skill({"name": "大回復", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 150000, "heal_percent": 0.0})
	var saved := RBMLocalStageRepository.save_new(draft)  # 上限より前の版で保存されたデータの代わり
	assert_true(bool(saved.get("ok", false)), "sanity")
	var stage_id := str(saved.get("stage_id", ""))
	var main := await _new_main()
	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	main.draft.restore_from_saved_dict(loaded.get("draft_data", {}))
	main.current_stage_id = stage_id
	assert_eq(int(main.draft.skills[0].get("heal_fixed_amount", 0)), 150000, "読み込みでは書き換えない")
	assert_false(main.draft.heal_limit_problems().is_empty(), "上限を超えていることを知らせる")
	assert_false(main.draft.step4_is_valid())
	var simple := _simple(main)
	assert_true(simple.validation_message().contains("99,999"), simple.validation_message())
	var result := main.press_overwrite_save()
	assert_false(bool(result.get("ok", true)), "上限を超えたままは保存しない")
	assert_eq(str(result.get("error", "")), "heal_over_limit")
	var reread := RBMLocalStageRepository.load_stage(stage_id)
	assert_eq(int((reread.get("draft_data", {})["skills"] as Array)[0].get("heal_fixed_amount", 0)), 150000, "保存済みのファイルも書き換えていない")

func test_over_limit_awakening_heal_is_reported_for_hardcore() -> void:
	var draft := RBMCreatorDraft.new()
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	draft.awakening = {"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 100000, "heal_percent": 0.0}}
	assert_false(draft.heal_limit_problems().is_empty())
	assert_false(draft.step4_advanced_is_valid())
	draft.awakening["heal"]["heal_fixed_amount"] = 99999
	assert_true(draft.heal_limit_problems().is_empty(), "99,999 は通る")

# =============================================================================
# PX-05 保存したボス戦の一覧の公開状態
# =============================================================================

func test_saved_list_marks_only_online_published_bosses() -> void:
	var online := RBMCreatorDraft.new()
	online.boss_name = "オンライン公開したボス"
	online.set_online_boss_id("online-1")
	online.set_online_published(true)
	RBMLocalStageRepository.save_new(online)
	var legacy := RBMCreatorDraft.new()
	legacy.boss_name = "手元だけの印のボス"
	legacy.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	legacy.add_party_character("hero")
	legacy.record_clear_check_success()
	assert_true(legacy.publish(), "sanity: 以前の版の手元公開の印")
	RBMLocalStageRepository.save_new(legacy)
	var by_name := {}
	for entry in RBMLocalStageRepository.list():
		by_name[str(entry.get("boss_name", ""))] = entry
	assert_true(bool(by_name["オンライン公開したボス"].get("online_published", false)))
	assert_false(bool(by_name["手元だけの印のボス"].get("online_published", true)))
	var card := RBMSavedBossCard.new()
	add_child_autofree(card)
	card.setup_saved(by_name["オンライン公開したボス"])
	assert_not_null(card.get_node_or_null("PublishedTag"), "オンライン公開しているボスに「公開中」")
	var legacy_card := RBMSavedBossCard.new()
	add_child_autofree(legacy_card)
	legacy_card.setup_saved(by_name["手元だけの印のボス"])
	assert_null(legacy_card.get_node_or_null("PublishedTag"), "手元だけの印では「公開中」を付けない")

# =============================================================================
# PX-04・PX-14 オンライン一覧の通信
# =============================================================================

func test_a_hung_list_request_does_not_block_another_category() -> void:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	api.configure_list_response({"ok": true, "bosses": [{"id": "a", "boss_name": "ボスA", "author_name": "A"}]})
	var view := RBMOnlineBossListView.new()
	view.set_api_adapter_for_testing(api)
	add_child_autofree(view)
	await get_tree().process_frame
	api.list_delay_frames = 100000  # 返らない通信
	view.refresh_with("", RBMOnlineBossListView.CATEGORY_ONLINE, "オンライン")
	api.list_delay_frames = 0
	view.refresh_with("", RBMOnlineBossListView.CATEGORY_NEW, "新着")
	for i in range(10):
		await get_tree().process_frame
	assert_false(view._skeleton_container.visible, "新着は前の通信を待たずに表示される")
	assert_not_null(view.find_child("OnlineBossRow_a", true, false))

func test_online_errors_are_readable_and_keep_the_code_small() -> void:
	var text := RBMOnlineErrorText.full_text({"ok": false, "error_kind": "network_error", "message": "x"})
	assert_true(text.begins_with(TranslationServer.translate("通信できませんでした。インターネットへの接続を確かめて、もう一度お試しください。")), text)
	assert_true(text.contains("network_error"), "問い合わせ用にコードは小さく添える")
	var steam := RBMOnlineErrorText.describe({"ok": false, "error_kind": "steam_unavailable", "message": "Steamを起動してください"})
	assert_eq(steam, "Steamを起動してください", "Steam の時は人が読める文（message）をそのまま使う")
	assert_eq(RBMBossApiAdapter.REQUEST_TIMEOUT_SECONDS, 12.0, "通信には待ち時間の上限がある")

func test_detail_error_wraps_inside_its_frame() -> void:
	var panel := RBMOnlineBossDetailPanel.new()
	panel.size = Vector2(770, 610)
	add_child_autofree(panel)
	await get_tree().process_frame
	var message := TranslationServer.translate("このボスを取得できませんでした。") + "\n" + RBMOnlineErrorText.full_text({"ok": false, "error_kind": "network_error", "message": "x"})
	panel.show_error({"id": "a", "boss_name": "ボスA", "author_name": "A"}, message)
	await get_tree().process_frame
	var error := panel.find_child("DetailError", true, false) as Label
	assert_eq(error.size.x, 370.0, "長い理由の文でも枠（幅370）の中で折り返す")
	assert_gt(error.get_line_count(), 3, "1行に収まらない文は折り返す")

# =============================================================================
# PX-06 最新の行動の欄に全体攻撃の結果が全員分収まる
# =============================================================================

func test_four_target_results_fit_in_two_rows() -> void:
	var lines: Array = ["炎属性・勇者 に 9999 ダメージ", "氷属性・老執事 に 9999 ダメージ", "雷属性・少女 に 9999 ダメージ", "風属性・侍 に 9999 ダメージ"]
	var rows := RBMBattleUiKit._pack_result_lines(lines)
	assert_eq(rows.size(), 2, "4人分を2行に並べる")
	var joined := "\n".join(rows)
	for line in lines:
		assert_true(joined.contains(line), "どの結果も欠けない: %s" % line)
	assert_eq(RBMBattleUiKit._pack_result_lines(["とても長い結果の行です。とても長い結果の行です。とても長い結果の行です。", "短い"]).size(), 2, "幅に収まらない時は並べない")

# =============================================================================
# PX-25・PX-26 英語の翻訳
# =============================================================================

func test_every_translation_keeps_the_placeholder_order() -> void:
	var text := FileAccess.get_file_as_string("res://localization/ui_strings.csv")
	var regex := RegEx.new()
	regex.compile("%[-+0-9.]*[sdf]")
	var bad: Array = []
	for row in _parse_csv(text):
		if row.size() < 2 or str(row[1]).is_empty():
			continue
		var a: Array = regex.search_all(str(row[0])).map(func(m): return m.get_string())
		var b: Array = regex.search_all(str(row[1])).map(func(m): return m.get_string())
		if a != b:
			bad.append("%s ⇒ %s" % [row[0], row[1]])
	assert_eq(bad, [], "日本語と英語で %s・%d の順番がそろっていること（逆だと「%d damage to %s」のように書式が壊れる）")

func test_english_damage_lines_and_defeat_record_are_translated() -> void:
	RBMLocale.set_locale("en")
	var line: String = TranslationServer.translate("%s に %d ダメージ") % ["Slime", 140]
	assert_eq(line, "Slime takes 140 damage")
	# 2026-10-17 ユーザー指定の表記（Clear Record／Rare Clears ＋小さく ≤5%）
	assert_eq(TranslationServer.translate("あなたの討伐記録"), "Clear Record")
	assert_eq(TranslationServer.translate("難関ボス討伐"), "Rare Clears")

func test_rare_clears_shows_the_5_percent_threshold_only_in_english() -> void:
	RBMLocale.set_locale("en")
	var hub_en := RBMChallengeHubView.new()
	add_child_autofree(hub_en)
	var threshold := hub_en.find_child("RareClearThreshold", true, false) as Label
	assert_not_null(threshold, "英語では Rare Clears に基準を添える")
	assert_eq(threshold.text, "≤5%")
	RBMLocale.set_locale("ja")
	var hub_ja := RBMChallengeHubView.new()
	add_child_autofree(hub_ja)
	assert_null(hub_ja.find_child("RareClearThreshold", true, false), "日本語の表記は変えない")

# =============================================================================
# PX-03 検索・ランダム（オンライン公開ボス、サーバー側で探す・抽選する）
# =============================================================================

const BOSS_ID_A := "1a2b3c4d-0000-4000-8000-000000000001"
const BOSS_ID_B := "9f8e7d6c-1111-4000-8000-000000000002"
const STEAM_APPID_PATH := "user://test_steam_dev_appid_play_audit_fixes.local.txt"

func _boss_row(id: String, boss_name: String, mode: String = "simple") -> Dictionary:
	return {"id": id, "boss_name": boss_name, "author_name": "作者", "published_at": "2026-10-01T00:00:00+00:00", "creator_mode": mode, "appearance_id": "appearance_dragon", "unique_challengers": 3, "unique_clearers": 1}

func _playable_draft(boss_name: String) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	draft.record_clear_check_success()
	return draft

func _search_api() -> RBMFakeBossApiAdapter:
	var api := RBMFakeBossApiAdapter.new()
	add_child_autofree(api)
	api.configure_get_response({"ok": true, "boss": {"id": "x", "boss_name": "", "author_name": "", "revision": 1, "payload": RBMOnlineBossPayload.build_for_publish(_playable_draft("詳細"))["payload"]}})
	return api

## Steam を使えない偽の記録係（本物の Steam に触れない）。
func _offline_recorder() -> RBMOnlineChallengeRecorder:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(STEAM_APPID_PATH)
	var file := FileAccess.open(STEAM_APPID_PATH, FileAccess.WRITE)
	file.store_string("480")
	file.close()
	var steam := RBMFakeSteamAdapter.new()
	steam.configure_unavailable()
	var auth := RBMSteamAuth.new()
	auth.set_adapter_for_testing(steam)
	add_child_autoqfree(auth)
	auth.initialize()
	var recorder_api := RBMFakeBossApiAdapter.new()
	add_child_autofree(recorder_api)
	var recorder := RBMOnlineChallengeRecorder.new()
	add_child_autofree(recorder)
	recorder.set_steam_auth_for_testing(auth)
	recorder.set_api_adapter_for_testing(recorder_api)
	return recorder

func _entry(api: RBMFakeBossApiAdapter) -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	entry.set_online_api_adapter_for_testing(api)
	entry.set_online_recorder_for_testing(_offline_recorder())
	add_child_autofree(entry)
	entry.enter_challenge()
	return entry

func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame

func test_hub_search_opens_the_online_search_and_waits_for_a_query() -> void:
	var api := _search_api()
	var entry := _entry(api)
	_btn(entry._hub_view, "SearchBossButton").pressed.emit()
	await _frames(2)
	var view := entry._online_list_view
	assert_true(view.visible, "オンライン一覧の「検索」を開く")
	assert_false(entry._list_panel.visible, "手元の一覧は開かない")
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_SEARCH)
	assert_true(view._search_row.visible, "検索の行が出る")
	assert_eq(api.search_calls.size(), 0, "検索語が無いうちは通信しない")
	assert_eq(view._status_label.text, TranslationServer.translate("ボス名・作者名・公開IDで探せます。"))

func test_search_sends_the_query_and_mode_and_reads_more_pages() -> void:
	var api := _search_api()
	api.configure_search_responses({
		"竜": {"ok": true, "bosses": [_boss_row(BOSS_ID_A, "黒炎竜")], "has_more": true, "next_cursor": "c1"},
		"竜|c1": {"ok": true, "bosses": [_boss_row(BOSS_ID_B, "氷竜")], "has_more": false},
	})
	var entry := _entry(api)
	entry._on_hub_search_requested()
	var view := entry._online_list_view
	view._search_edit.text = "  竜  "
	view._search_edit.text_submitted.emit(view._search_edit.text)
	await _frames(3)
	assert_eq(api.search_calls.size(), 1, "Enter の時だけ通信する")
	assert_eq(api.search_calls[0]["query"], "竜", "前後の空白は除く")
	assert_eq(api.search_calls[0]["mode"], "")
	assert_not_null(view.find_child("OnlineBossRow_%s" % BOSS_ID_A, true, false))
	assert_true(view._load_more_button.visible, "続きがあれば「さらに表示」")
	view.load_more()
	await _frames(3)
	assert_eq(api.search_calls[1]["cursor"], "c1")
	assert_not_null(view.find_child("OnlineBossRow_%s" % BOSS_ID_B, true, false))
	assert_false(view._load_more_button.visible)
	# モードを切り替えると、同じ検索語で探し直す
	view._on_mode_segment_pressed(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	await _frames(3)
	assert_eq(api.search_calls[2]["query"], "竜")
	assert_eq(api.search_calls[2]["mode"], RBMCreatorDraft.CREATOR_MODE_ADVANCED)

func test_search_with_no_match_says_so() -> void:
	var api := _search_api()
	api.configure_search_response({"ok": true, "bosses": [], "has_more": false})
	var entry := _entry(api)
	entry._on_hub_search_requested()
	entry._online_list_view.submit_search("該当なし")
	await _frames(3)
	assert_eq(entry._online_list_view._status_label.text, TranslationServer.translate("条件に合うボスは見つかりませんでした。"))

func test_hub_random_draws_from_the_selected_mode_and_selects_the_boss() -> void:
	var api := _search_api()
	api.configure_list_response({"ok": true, "bosses": []})
	api.configure_random_sequence([
		{"ok": true, "bosses": [_boss_row(BOSS_ID_A, "引いたボス", "advanced")]},
		{"ok": true, "bosses": [_boss_row(BOSS_ID_B, "次のボス", "advanced")]},
	])
	var entry := _entry(api)
	# 一覧で HARDCORE を選んでから挑戦トップへ戻る（選択中のモード）
	entry._on_hub_category_selected(RBMChallengeHubView.CATEGORY_HARDCORE)
	await _frames(2)
	entry._on_back_to_hub_pressed()
	_btn(entry._hub_view, "RandomChallengeButton").pressed.emit()
	await _frames(4)
	var view := entry._online_list_view
	assert_eq(view.current_category(), RBMOnlineBossListView.CATEGORY_RANDOM)
	assert_eq(api.random_calls[0], {"mode": RBMCreatorDraft.CREATOR_MODE_ADVANCED, "exclude": ""}, "選択中のモードの公開ボス全体から引く")
	assert_eq(view.selected_boss_id(), BOSS_ID_A, "引いたボスを選んだ状態にする")
	assert_true(api.get_calls.has(BOSS_ID_A), "詳細を取得して右に出す")
	assert_true(view._reroll_button.visible, "「もう一度引く」が出る")
	assert_false(entry._battle_view.visible, "戦闘は始めない")
	view.reroll()
	await _frames(4)
	assert_eq(api.random_calls[1]["exclude"], BOSS_ID_A, "もう一度引く時は今のボスを除く")
	assert_eq(view.selected_boss_id(), BOSS_ID_B)

func test_random_with_no_published_boss_says_so() -> void:
	var api := _search_api()
	api.configure_random_response({"ok": true, "bosses": []})
	var entry := _entry(api)
	entry._on_hub_random_requested()
	await _frames(3)
	var view := entry._online_list_view
	assert_eq(view._status_label.text, TranslationServer.translate("抽選できる公開ボスがありません。"))
	assert_false(view._reroll_button.visible)

func test_public_id_is_the_first_8_characters_and_shows_in_both_details() -> void:
	assert_eq(RBMPublicBossId.from_boss_id(BOSS_ID_A.to_upper()), "1a2b3c4d")
	assert_eq(RBMPublicBossId.from_boss_id("not-a-uuid"), "")
	var draft := _playable_draft("詳細")
	var online := RBMOnlineBossDetailPanel.new()
	online.size = Vector2(772, 612)
	add_child_autofree(online)
	online.show_boss(_boss_row(BOSS_ID_A, "詳細"), draft)
	assert_eq((online.find_child("DetailPublicId", true, false) as Label).text, TranslationServer.translate("公開ID %s") % "1a2b3c4d")
	var saved := RBMSavedBossDetailPanel.new()
	saved.size = Vector2(772, 612)
	add_child_autofree(saved)
	saved.show_boss({"stage_id": "0123456789", "boss_name": "詳細", "online_published": true, "online_boss_id": BOSS_ID_B}, draft)
	assert_eq((saved.find_child("DetailPublicId", true, false) as Label).text, TranslationServer.translate("公開ID %s") % "9f8e7d6c", "作者の保存したボス戦の詳細にも出す")
	saved.show_boss({"stage_id": "0123456789", "boss_name": "詳細", "online_published": false, "online_boss_id": BOSS_ID_B}, draft)
	await get_tree().process_frame
	assert_null(saved.find_child("DetailPublicId", true, false), "公開を取り下げたボスには出さない")

func test_saved_list_entries_carry_the_online_boss_id_without_changing_the_save() -> void:
	var draft := _playable_draft("公開済み")
	draft.set_online_boss_id(BOSS_ID_A)
	draft.set_online_published(true)
	var saved := RBMLocalStageRepository.save_new(draft)
	var path := _dir.path_join("%s.json" % str(saved["stage_id"]))
	var before := FileAccess.get_file_as_string(path)
	var entry: Dictionary = RBMLocalStageRepository.list()[0]
	assert_eq(entry.get("online_boss_id"), BOSS_ID_A)
	assert_eq(FileAccess.get_file_as_string(path), before, "一覧を読むだけで保存は書き換えない")

func test_old_locally_published_saves_still_load_and_stay_unchanged() -> void:
	# 以前の版で「手元公開」したボス（published=true、手元の挑戦回数）。挑戦トップの検索・ランダムはオンラインを
	# 見るようになったが、保存はそのまま読め、手元の一覧（_open_local_published_list）からは今までどおり出る。
	var draft := _playable_draft("手元公開ボス")
	assert_true(draft.publish(), "sanity: 手元公開（旧機能）")
	var stage_id := str(RBMLocalStageRepository.save_new(draft)["stage_id"])
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	var path := _dir.path_join("%s.json" % stage_id)
	var before := FileAccess.get_file_as_string(path)
	var api := _search_api()
	var entry := _entry(api)
	entry._on_hub_search_requested()
	entry._on_hub_random_requested()
	await _frames(3)
	assert_eq(FileAccess.get_file_as_string(path), before, "挑戦トップの検索・ランダムは手元の保存を書き換えない")
	assert_true(bool(RBMLocalStageRepository.list()[0].get("published", false)), "手元公開の印は読める")
	entry._open_local_published_list()
	assert_eq(entry._list_rows.get_child_count(), 1, "手元公開のボスは手元の一覧から今までどおり出る")

func test_bosses_sharing_a_public_id_are_fetched_and_challenged_by_their_full_id() -> void:
	# 公開IDは id の先頭8文字なので、ほかのボスと重なることがある。検索では両方が出て、選んだボスの
	# id 全体で詳細を取り、挑戦する（もう一方のボスを取り違えない）。
	var same_prefix := "1a2b3c4d-ffff-4000-8000-000000000009"
	var api := _search_api()
	api.configure_search_response({"ok": true, "bosses": [_boss_row(BOSS_ID_A, "先のボス"), _boss_row(same_prefix, "後のボス")], "has_more": false})
	var entry := _entry(api)
	entry._on_hub_search_requested()
	var view := entry._online_list_view
	view.submit_search("1a2b3c4d")
	await _frames(3)
	assert_eq(view._rows_container.get_child_count(), 2, "同じ公開IDのボスはどちらも出る")
	var requested: Array = []
	view.challenge_requested.connect(func(id: String, _draft: RBMCreatorDraft): requested.append(id))
	view._on_card_pressed(same_prefix)
	await _frames(3)
	assert_eq(api.get_calls[-1], same_prefix, "詳細は選んだボスの id 全体で取る")
	assert_eq((view.find_child("DetailBossName", true, false) as Label).text, "後のボス")
	view._on_challenge_pressed()
	assert_eq(requested, [same_prefix], "挑戦も選んだボスの id 全体")

func test_repeated_search_and_reroll_while_loading_send_one_request() -> void:
	var api := _search_api()
	api.search_delay_frames = 30
	api.configure_search_response({"ok": true, "bosses": [_boss_row(BOSS_ID_A, "竜")], "has_more": false})
	api.configure_random_response({"ok": true, "bosses": [_boss_row(BOSS_ID_A, "竜")]})
	var entry := _entry(api)
	entry._on_hub_search_requested()
	var view := entry._online_list_view
	for i in range(5):
		view.submit_search("竜")
		await get_tree().process_frame
	assert_eq(api.search_calls.size(), 1, "読み込み中の同じ検索は通信を重ねない")
	view.submit_search("氷")
	assert_eq(api.search_calls.size(), 2, "別の言葉ならすぐ探し直す")
	await _frames(40)
	entry._on_back_to_hub_pressed()
	entry._on_hub_random_requested()
	for i in range(5):
		view._on_refresh_pressed()
		await get_tree().process_frame
	assert_eq(api.random_calls.size(), 1, "抽選中の「更新」は通信を重ねない")

# =============================================================================
# 2026-10-17 追加: 画面の部品の大きさ・ハンマー使いの技の英語
# =============================================================================

func test_gradient_and_floor_shadow_keep_the_requested_size() -> void:
	var holder := Control.new()
	add_child_autofree(holder)
	var gradient := RBMChallengeListStyle.gradient_rect(holder, Rect2(0, 230, 770, 70), Color(0, 0, 0, 0), Color(0, 0, 0, 1))
	assert_eq(gradient.size, Vector2(770, 70), "グラデーションは決めた大きさのまま（以前は画像の512pxまで広がった）")
	var shadow := RBMChallengeListStyle.floor_shadow(holder, Rect2(100, 247, 240, 30))
	assert_eq(shadow.size, Vector2(240, 30), "足元の影は決めた大きさのまま（以前は画像の256pxまで広がった）")

func test_every_tank_skill_has_an_english_name() -> void:
	RBMLocale.set_locale("en")
	var tank := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS["tank"]))
	for skill in tank.get("skills", []):
		var ja := str(skill.get("display_name", ""))
		assert_ne(TranslationServer.translate(ja), ja, "ハンマー使いの技「%s」に英語がある" % ja)
	assert_eq(TranslationServer.translate("渾身の一撃"), "All-Out Strike")

## 作成画面の右の BOSS PROFILE の「覚醒：未設定／設定済み」は、英語でも日本語のまま出ていた（翻訳の表に無かった）。
func test_boss_profile_awakening_line_is_translated() -> void:
	RBMLocale.set_locale("en")
	var panel := RBMCreatorUiKit.BossProfilePanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	var draft := RBMCreatorDraft.new()
	panel.update(draft)
	var line := panel.find_child("BossProfileAwakeningLabel", true, false) as Label
	assert_eq(line.text, "Awakening: Not Set")
	draft.awakening = {"trigger": "hp_below"}
	panel.update(draft)
	assert_eq(line.text, "Awakening: Set", "覚醒を設定した時も英語")
	RBMLocale.set_locale("ja")
	panel.update(draft)
	assert_eq(line.text, "覚醒：設定済み", "日本語は今までどおり")

func _parse_csv(text: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var field := ""
	var quoted := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if quoted:
			if c == "\"":
				if i + 1 < text.length() and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					quoted = false
			else:
				field += c
		elif c == "\"":
			quoted = true
		elif c == ",":
			row.append(field)
			field = ""
		elif c == "\n":
			row.append(field)
			rows.append(row)
			row = []
			field = ""
		elif c != "\r":
			field += c
		i += 1
	if not field.is_empty() or not row.is_empty():
		row.append(field)
		rows.append(row)
	return rows
