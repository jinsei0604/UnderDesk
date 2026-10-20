extends GutTest

## 総合品質改善（2026-10-18）の回帰テスト。プレイ体験監査の残り（PX-07・PX-08・PX-09・PX-13）。
## - PX-07 新しいボスの能力の初期値（HP1・ATK1・SPD1 ではない）。保存済みのボスは変えない
## - PX-08 「名前を決める」で入力欄にフォーカス、Enter で決定、Esc でキャンセル
## - PX-09 名前が空のまま「次へ」を押すと、名前の欄に一言が出る
## - PX-13 Esc で戻る・閉じる・キャンセル（挑戦・作成の各画面、戦闘中、保存の画面）
## 保存は一時のフォルダ（本物の保存には触れない）。通信・Steam は使わない。

const TEST_DIR := "user://bossmaker_test_quality_pass_2026_10_18"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR + "/stages")

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path + "/" + name
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	DirAccess.remove_absolute(path)

func _btn(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button

## 本物の入力と同じ経路で Esc（ui_cancel）を送る。
func _press_escape() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame

func _new_creator_entry() -> RBMCreatorEntry:
	var entry := RBMCreatorEntry.new()
	entry.size = Vector2(1280, 720)
	add_child_autofree(entry)
	await get_tree().process_frame
	entry.enter_create()
	await get_tree().process_frame
	return entry

func _start_simple(entry: RBMCreatorEntry) -> RBMCreatorMain:
	entry._on_choose_simple_mode_pressed()
	await get_tree().process_frame
	return entry.main

# =============================================================================
# PX-07 能力の初期値
# =============================================================================

func test_a_new_boss_starts_with_usable_stats_and_no_unsaved_changes() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	assert_eq([main.draft.hp, main.draft.atk, main.draft.spd], [RBMCreatorDraft.NEW_BOSS_HP, RBMCreatorDraft.NEW_BOSS_ATK, RBMCreatorDraft.NEW_BOSS_SPD])
	assert_eq([RBMCreatorDraft.NEW_BOSS_HP, RBMCreatorDraft.NEW_BOSS_ATK, RBMCreatorDraft.NEW_BOSS_SPD], [3000, 150, 90], "同梱の基準のボスと同じ値")
	assert_false(main.has_unsaved_changes(), "作り始めた直後は未保存の変更なし")
	main.go_to_step(2)
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_eq(int(step2._hp_spin.value), 3000, "STEP2 の入力欄にも同じ値")

func test_saved_bosses_keep_their_own_stats() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "保存済み"
	draft.hp = 1234
	draft.atk = 56
	draft.spd = 7
	draft.add_party_character("hero")
	var saved := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(saved.get("ok", false)), "sanity")
	var entry := await _new_creator_entry()
	var result := entry.main.start_loaded(str(saved.get("stage_id", "")))
	assert_true(bool(result.get("ok", false)), "sanity")
	assert_eq([entry.main.draft.hp, entry.main.draft.atk, entry.main.draft.spd], [1234, 56, 7], "読み込んだボスの値は変えない")
	var empty := RBMCreatorDraft.new()
	assert_eq([empty.hp, empty.atk, empty.spd], [1, 1, 1], "読み込みの既定値（キーが無い古い保存の補完）は今までどおり")

# =============================================================================
# PX-08・PX-09 名前の入力
# =============================================================================

func test_the_name_field_gets_focus_and_enter_confirms() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	assert_true(step1._name_edit.has_focus(), "開いたら入力欄にフォーカス")
	step1._name_edit.text = "エンターのボス"
	step1._name_edit.text_submitted.emit(step1._name_edit.text)
	await get_tree().process_frame
	assert_eq(main.draft.boss_name, "エンターのボス", "Enter で決定")
	assert_false(step1._name_edit_row.visible)
	assert_true(_btn(step1, "EditNameButton").has_focus(), "閉じた後のフォーカスは「編集」へ")

func test_escape_cancels_the_name_editing() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "元の名前"
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	step1.refresh()
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	step1._name_edit.text = "書きかけ"
	await _press_escape()
	assert_eq(main.draft.boss_name, "元の名前", "Esc は決定しない")
	assert_false(step1._name_edit_row.visible, "Esc で入力をやめる")
	assert_eq(main.current_step, 1, "入力をやめるだけで、STEP は変わらない")
	assert_true(main.visible, "作成は終わらない")

func test_next_with_an_empty_name_shows_why() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	var hint := step1.find_child("NameRequiredLabel", true, false) as Label
	assert_false(hint.visible, "最初は出さない")
	assert_false(main.press_next(), "名前が空なら進めない（今までどおり）")
	assert_true(hint.visible, "名前の欄に一言が出る")
	assert_eq(hint.text, "ボス名を入力してください")
	step1.set_boss_name("名前あり")
	assert_false(hint.visible, "名前を決めたら消える")
	assert_true(main.press_next())

# =============================================================================
# PX-13 Esc
# =============================================================================

func test_escape_walks_back_through_the_creator_entry_screens() -> void:
	var entry := await _new_creator_entry()
	watch_signals(entry)
	entry._show_mode_choice()
	await _press_escape()
	assert_true(entry._top_panel.visible, "作成方法の選択 → 作成トップ")
	entry._show_list()
	await _press_escape()
	assert_true(entry._top_panel.visible, "保存したボス戦の一覧 → 作成トップ")
	assert_signal_not_emitted(entry, "exit_requested")
	await _press_escape()
	assert_signal_emitted(entry, "exit_requested", "作成トップ → ホーム")

func test_escape_closes_the_delete_confirmation_without_deleting() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "消さないボス"
	draft.add_party_character("hero")
	var saved := RBMLocalStageRepository.save_new(draft)
	var entry := await _new_creator_entry()
	entry._show_list()
	entry._on_delete_stage_pressed(str(saved.get("stage_id", "")), "消さないボス")
	assert_true(entry._delete_confirm_panel.visible, "sanity")
	await _press_escape()
	assert_false(entry._delete_confirm_panel.visible, "Esc で削除の確認を閉じる")
	assert_true(entry._list_panel.visible, "一覧に残る")
	assert_true(bool(RBMLocalStageRepository.load_stage(str(saved.get("stage_id", ""))).get("ok", false)), "消していない")

func test_escape_in_the_creator_goes_back_a_step_and_asks_before_leaving() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "未保存のボス"
	main.go_to_step(3)
	await _press_escape()
	assert_eq(main.current_step, 2, "1つ前の STEP へ")
	main.go_to_step(1)
	await _press_escape()
	assert_true(main._exit_confirm_panel.visible, "STEP1 では「作成を終了」と同じ（未保存なので確認）")
	await _press_escape()
	assert_false(main._exit_confirm_panel.visible, "確認は Esc でキャンセル")
	assert_true(main.visible, "作成は続く")

func test_escape_closes_the_party_status_sheet_first() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "パーティのボス"
	main.draft.add_party_character("hero")
	main.go_to_step(4)
	var party: RBMCreatorStep5Party = main._step_views[3]
	party._selected_character_id = "hero"
	party.open_status_sheet()
	assert_true(party.is_status_sheet_open(), "sanity")
	await _press_escape()
	assert_false(party.is_status_sheet_open(), "Esc でステータス編集を閉じる")
	assert_eq(main.current_step, 4, "STEP は戻らない")

func test_escape_in_the_save_view_goes_back_without_saving() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "保存しないボス"
	main.draft.add_party_character("hero")
	main.press_save()
	await get_tree().process_frame
	await _press_escape()
	assert_false(main._save_view.visible, "保存の画面から戻る")
	assert_true(main.current_stage_id.is_empty(), "保存していない")

func test_escape_on_the_clear_check_start_screen_goes_back() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "クリアチェックのボス"
	main.draft.add_party_character("hero")
	main.press_clear_check()
	await get_tree().process_frame
	assert_true(main._clear_check_view._confirm_panel.visible, "sanity")
	await _press_escape()
	assert_false(main._clear_check_view.visible, "開始の画面から作成へ戻る")
	assert_true(main._steps_root.visible)

func test_escape_walks_back_from_the_challenge_list_to_home() -> void:
	var entry := RBMChallengeEntry.new()
	add_child_autofree(entry)
	await get_tree().process_frame
	watch_signals(entry)
	entry.enter_challenge()
	entry._show_browse()
	await _press_escape()
	assert_true(entry._hub_view.visible, "一覧 → 挑戦トップ")
	assert_signal_not_emitted(entry, "exit_requested")
	await _press_escape()
	assert_signal_emitted(entry, "exit_requested", "挑戦トップ → ホーム")

func test_escape_in_battle_closes_windows_then_asks_before_quitting() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "戦闘のボス"
	draft.hp = 99999
	draft.add_party_character("hero")
	view.start_battle(draft.to_definition())
	view.open_log_window()
	await _press_escape()
	assert_false((view._log_window_overlay["overlay"] as Control).visible, "開いている窓を閉じる")
	assert_false(view._quit_confirm.visible, "窓を閉じただけ")
	await _press_escape()
	assert_true(view._quit_confirm.visible, "何も開いていなければ「挑戦をやめる」の確認")
	await _press_escape()
	assert_false(view._quit_confirm.visible, "確認は Esc でキャンセル（やめない）")
	assert_false(view.session.battle.battle_over, "戦闘は続く")

# =============================================================================
# 英語の不足: 外見の名前（外見を選ぶ画面・挑戦の確認）
# =============================================================================

func test_every_appearance_name_has_an_english_name() -> void:
	var saved := RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	for entry in RBMCreatorAppearanceCatalog.all():
		var ja := str(entry.get("name", ""))
		var en := RBMCreatorAppearanceCatalog.display_name(str(entry.get("id", "")))
		assert_ne(en, ja, "%s は英語の時に日本語のまま出ない" % ja)
		assert_false(en.is_empty())
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_slime"), "Slime")
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_golem"), "Golem")
	RBMLocale.set_locale("ja")
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_slime"), "スライム", "日本語は今までどおり")
	RBMLocale.set_locale(saved)

func test_the_english_appearance_picker_shows_english_names() -> void:
	var saved := RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1280, 720)
	add_child_autofree(picker)
	await get_tree().process_frame
	var label := picker.find_child("AppearanceName_appearance_wolf", true, false) as Label
	assert_not_null(label)
	if label != null:
		assert_eq(label.text, "Wolf")
	RBMLocale.set_locale(saved)

# =============================================================================
# PX-11 の一部: STEP4 を開いただけで「パーティを1人以上選んでください」が出ない
# =============================================================================

func test_the_party_step_does_not_complain_before_next_is_pressed() -> void:
	var entry := await _new_creator_entry()
	var main := await _start_simple(entry)
	main.draft.boss_name = "パーティを選ぶ前のボス"
	main.go_to_step(4)
	assert_eq(main._status_label.text, "", "開いただけでは出さない")
	assert_false(main.press_next(), "パーティが空なら進めない（今までどおり）")
	assert_eq(main._status_label.text, "パーティを1人以上選んでください", "「次へ」を押したら理由を出す")
	main.draft.add_party_character("hero")
	main.on_party_changed()
	assert_eq(main._status_label.text, "", "選んだら消える")
	main.draft.remove_party_character("hero")
	main.on_party_changed()
	assert_eq(main._status_label.text, "パーティを1人以上選んでください", "自分で全員を外したら、すぐ出す")
	main.go_to_step(3)
	main.go_to_step(4)
	assert_eq(main._status_label.text, "", "別の STEP から戻って開き直した時も、開いただけでは出さない")
