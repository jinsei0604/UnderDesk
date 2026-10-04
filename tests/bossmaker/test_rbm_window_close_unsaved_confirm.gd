extends GutTest

## ウィンドウ終了要求(右上の×/Alt+F4 = NOTIFICATION_WM_CLOSE_REQUEST)時の
## 未保存確認の回帰テスト。
##
## 確認UI・判定・文言はCreator既存のもの(RBMCreatorMainのExitConfirmPanel /
## has_unsaved_changes())をそのまま使う。ここでは「終了要求が来た時にそれを
## 開くか/そのまま終了するか」と、確認結果に応じた行き先だけを検証する。
## 実際にプロセスを終了させないよう、RBMGameRoot.quit_actionへカウンタを
## 差し込んで「終了へ進んだ回数」を数える。

const CLOSE := NOTIFICATION_WM_CLOSE_REQUEST

func after_each() -> void:
	await get_tree().process_frame

## ホーム上中央モニターの初期化(_init_battle)は自前のawaitループを持ち、
## 完了前に解放するとエラーになるため、必ず完了させてから停止する。
func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	var ticks := 0
	while not root._top_monitor_battle._initialized and ticks < 300:
		await get_tree().process_frame
		ticks += 1
	root._top_monitor_battle.stop_loop()
	await get_tree().process_frame
	return root

func _hook_quit(root: RBMGameRoot) -> Array:
	var quits := [0]
	root.quit_action = func(): quits[0] += 1
	return quits

func _panel(root: RBMGameRoot) -> PanelContainer:
	return root.creator_entry.main._exit_confirm_panel

func _btn(root: RBMGameRoot, button_name: String) -> Button:
	var found: Button = root.creator_entry.main.find_child(button_name, true, false)
	assert_not_null(found, "expected %s" % button_name)
	return found

## Creator編集画面(main表示中)を開き、boss_nameを書き換えて未保存にする。
func _enter_creator_editing(root: RBMGameRoot, make_dirty: bool = true) -> RBMCreatorMain:
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_simple_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	assert_true(main.visible, "sanity: the creator editing screen is shown")
	if make_dirty:
		main.draft.boss_name = "未保存のボス"
	return main

# ---------------------------------------------------------------------------
# 1〜3: 未保存あり
# ---------------------------------------------------------------------------

func test_unsaved_creator_close_request_shows_the_existing_confirm_and_does_not_quit() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	assert_true(main.has_unsaved_changes())
	assert_false(_panel(root).visible)

	root.notification(CLOSE)

	assert_eq(quits[0], 0, "must not quit while unsaved changes are unresolved")
	assert_true(_panel(root).visible, "the existing unsaved-changes panel is shown")
	assert_eq((_btn(root, "ExitConfirmSaveButton") as Button).text, tr("保存する"))
	assert_eq((_btn(root, "ExitConfirmDiscardButton") as Button).text, tr("保存せず終了"))
	assert_eq((_btn(root, "ExitConfirmCancelButton") as Button).text, tr("キャンセル"))

func test_confirm_uses_the_same_panel_node_and_label_as_the_back_flow() -> void:
	var root := await _make_root()
	var main := _enter_creator_editing(root)
	var label_text := (main.find_child("ExitConfirmLabel", true, false) as Label).text

	root.notification(CLOSE)
	assert_eq(main.find_children("ExitConfirmPanel", "PanelContainer", true, false).size(), 1, "no second dialog is created")
	assert_eq((main.find_child("ExitConfirmLabel", true, false) as Label).text, label_text, "the wording is the existing one")
	assert_eq(label_text, tr("変更内容が保存されていません。\n保存せず終了すると変更内容は失われます。"))

func test_cancel_keeps_the_creator_and_the_edits_and_does_not_quit() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	main.draft.hp = 1234
	root.notification(CLOSE)

	_btn(root, "ExitConfirmCancelButton").pressed.emit()

	assert_eq(quits[0], 0)
	assert_false(_panel(root).visible)
	assert_true(main.visible, "still on the creator screen")
	assert_eq(main.draft.boss_name, "未保存のボス", "edits are kept")
	assert_eq(main.draft.hp, 1234)
	assert_true(main.has_unsaved_changes())

	# キャンセル後に再度×を押せば、また同じ確認が出る(黙って終了しない)。
	root.notification(CLOSE)
	assert_true(_panel(root).visible)
	assert_eq(quits[0], 0)

func test_discard_confirms_the_quit_and_does_not_prompt_again() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	watch_signals(main)
	root.notification(CLOSE)

	_btn(root, "ExitConfirmDiscardButton").pressed.emit()

	assert_eq(quits[0], 1, "proceeds to the normal quit")
	assert_false(_panel(root).visible)
	assert_signal_not_emitted(main, "exited", "quitting the game is not the same as leaving the creator screen")

	# 確定後にもう一度終了要求が来ても、確認ループにならず二重終了もしない。
	root.notification(CLOSE)
	assert_false(_panel(root).visible, "no second confirmation after the user already confirmed")
	assert_eq(quits[0], 1)

func test_save_button_in_the_window_close_confirm_goes_to_the_existing_save_flow() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	root.notification(CLOSE)

	_btn(root, "ExitConfirmSaveButton").pressed.emit()

	assert_eq(quits[0], 0, "existing behaviour: 保存する opens the save screen, it does not quit")
	assert_false(_panel(root).visible)
	assert_true(main._save_view.visible)

# ---------------------------------------------------------------------------
# 4〜5: 確認を出さない場合
# ---------------------------------------------------------------------------

func test_creator_without_unsaved_changes_quits_without_confirmation() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root, false)
	assert_false(main.has_unsaved_changes())

	root.notification(CLOSE)

	assert_eq(quits[0], 1)
	assert_false(_panel(root).visible)

func test_title_home_quits_without_confirmation() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	assert_true(root._title_screen.visible)

	root.notification(CLOSE)

	assert_eq(quits[0], 1)
	assert_false(_panel(root).visible)

func test_challenge_quits_without_confirmation() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	root._show_only(root.challenge_entry)
	# 別経路で作りかけのCreator draftが残っていても、Challenge中は確認しない。
	root.creator_entry.main.draft.boss_name = "残っているdraft"

	root.notification(CLOSE)

	assert_eq(quits[0], 1)
	assert_false(_panel(root).visible)

func test_creator_screens_other_than_editing_quit_without_confirmation() -> void:
	# CREATEのTOP/作成方法選択/保存済み一覧(mainが表示されていない画面)。
	for screen in ["_show_top", "_show_mode_choice", "_show_list"]:
		var root := await _make_root()
		var quits := _hook_quit(root)
		root._show_only(root.creator_entry)
		root.creator_entry.call(screen)
		assert_false(root.creator_entry.main.visible, screen)

		root.notification(CLOSE)

		assert_eq(quits[0], 1, screen)
		assert_false(_panel(root).visible, screen)
		root.free()
		await get_tree().process_frame

# ---------------------------------------------------------------------------
# 6: 連打
# ---------------------------------------------------------------------------

func test_repeated_close_requests_do_not_duplicate_the_dialog_or_slip_through() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)

	for i in range(8):
		root.notification(CLOSE)

	assert_eq(quits[0], 0, "mashing × / Alt+F4 must not quit")
	assert_true(_panel(root).visible)
	assert_eq(main.find_children("ExitConfirmPanel", "PanelContainer", true, false).size(), 1, "still exactly one dialog")

	_btn(root, "ExitConfirmDiscardButton").pressed.emit()
	assert_eq(quits[0], 1)
	for i in range(3):
		root.notification(CLOSE)
	assert_eq(quits[0], 1, "quits exactly once")

func test_close_request_while_the_back_flow_confirm_is_already_open_does_not_slip_through() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	main.press_exit_creator()
	assert_true(_panel(root).visible)

	root.notification(CLOSE)

	assert_eq(quits[0], 0)
	assert_true(_panel(root).visible)
	assert_eq(main.find_children("ExitConfirmPanel", "PanelContainer", true, false).size(), 1)

# ---------------------------------------------------------------------------
# 7: 既存の「戻る」等の未保存確認は変わらない
# ---------------------------------------------------------------------------

func test_existing_back_flow_still_leaves_the_creator_and_never_quits() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	watch_signals(main)

	main.press_exit_creator()
	assert_true(_panel(root).visible, "the back flow still asks first")
	_btn(root, "ExitConfirmDiscardButton").pressed.emit()

	assert_signal_emitted(main, "exited")
	assert_eq(quits[0], 0, "the back flow's 保存せず終了 only leaves the creator")
	assert_false(main.visible, "returned to the CREATE top")

func test_existing_back_flow_cancel_and_no_change_behaviour_are_unchanged() -> void:
	var root := await _make_root()
	var main := _enter_creator_editing(root)
	main.press_exit_creator()
	_btn(root, "ExitConfirmCancelButton").pressed.emit()
	assert_false(_panel(root).visible)
	assert_true(main.visible)

	var clean_root := await _make_root()
	var clean_main := _enter_creator_editing(clean_root, false)
	watch_signals(clean_main)
	clean_main.press_exit_creator()
	assert_signal_emitted(clean_main, "exited", "no unsaved changes: leaves immediately, no dialog")
	assert_false(_panel(clean_root).visible)

func test_a_cancelled_window_close_does_not_turn_the_next_back_flow_into_a_quit() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	root.notification(CLOSE)
	_btn(root, "ExitConfirmCancelButton").pressed.emit()

	main.press_exit_creator()
	_btn(root, "ExitConfirmDiscardButton").pressed.emit()

	assert_eq(quits[0], 0, "the window-close mode does not leak into the back flow")
	assert_false(main.visible)

func test_window_close_and_back_use_the_same_unsaved_judgement() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root, false)
	# 未保存なし: 両方とも確認しない。
	assert_false(main.request_window_close())
	watch_signals(main)
	main.press_exit_creator()
	assert_signal_emitted(main, "exited")

	# 未保存あり(A→B→Aで戻れば未保存なしへ戻る、既存の比較ロジックのまま)。
	var main2 := _enter_creator_editing(root, false)
	main2.draft.boss_name = "変更"
	assert_true(main2.request_window_close())
	_btn(root, "ExitConfirmCancelButton").pressed.emit()
	main2.draft.boss_name = ""
	assert_false(main2.has_unsaved_changes())
	assert_false(main2.request_window_close(), "back to the reference state: no prompt")
	assert_eq(quits[0], 0)

# ---------------------------------------------------------------------------
# Creator編集中の別画面(外見選択・保存画面)でも同じ確認を出す
# ---------------------------------------------------------------------------

func test_close_request_inside_a_creator_sub_screen_also_shows_the_same_confirm() -> void:
	var root := await _make_root()
	var quits := _hook_quit(root)
	var main := _enter_creator_editing(root)
	main.open_appearance_picker()
	assert_true(main._appearance_picker.visible)

	root.notification(CLOSE)

	assert_eq(quits[0], 0)
	assert_true(_panel(root).visible)

# ---------------------------------------------------------------------------
# 自動終了の停止/復元
# ---------------------------------------------------------------------------

func test_auto_accept_quit_is_disabled_while_the_game_root_lives_and_restored_after() -> void:
	var root := await _make_root()
	assert_false(get_tree().auto_accept_quit, "the OS close must reach the root's confirmation first")

	root.free()
	await get_tree().process_frame
	assert_true(get_tree().auto_accept_quit, "restored so nothing else is left unable to quit")
