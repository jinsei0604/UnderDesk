extends GutTest

## 最終確認(STEP5)からクリエイター一覧へ直接戻る導線。従来は最終確認の
## 「戻る」でSTEP4へ戻り、そこで初めて共通の「Creator一覧へ戻る」
## (RBMCreatorMain._nav_row内、STEP5では隠れる)を押す2段階操作が必要
## だった——最終確認の「戻る」ボタンのすぐ隣に、既存のRBMCreatorMain.
## press_exit_creator()(未保存変更があれば確認ダイアログ、なければ即座に
## 退出、既存仕様は無改修)をそのまま呼ぶ新しいボタンを追加し、1回の操作
## で一覧へ戻れるようにした。

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _summary_of(creator: RBMCreatorMain) -> RBMCreatorStep7Summary:
	return creator._step_views[4] as RBMCreatorStep7Summary

func test_summary_has_both_the_existing_back_button_and_the_new_back_to_list_button() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	var back_button: Button = summary.find_child("BackButton", true, false)
	var back_to_list_button: Button = summary.find_child("BackToCreatorListButton", true, false)
	assert_not_null(back_button, "the existing STEP5 back button must not be removed")
	assert_not_null(back_to_list_button, "a new back-to-creator-list button must exist on STEP5")
	assert_eq(back_to_list_button.text, "クリエイター一覧へ戻る")

func test_back_to_list_button_sits_next_to_back_and_not_among_save_publish_actions() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	var bottom_bar: Control = summary.find_child("SummaryBottomBar", true, false)
	var names: Array[String] = []
	for child in bottom_bar.get_children():
		names.append(str(child.name))
	var back_index := names.find("BackButton")
	var back_to_list_index := names.find("BackToCreatorListButton")
	var save_index := names.find("SaveButton")
	var publish_index := names.find("PublishOnlineButton")
	assert_eq(back_to_list_index, back_index + 1, "must sit immediately next to the existing back button")
	assert_true(back_to_list_index < save_index, "must stay on the navigation side, before the save/publish action group")
	assert_true(back_to_list_index < publish_index, "must stay on the navigation side, before the save/publish action group")

func test_pressing_it_exits_immediately_when_there_are_no_unsaved_changes() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	watch_signals(creator)
	summary.find_child("BackToCreatorListButton", true, false).pressed.emit()
	assert_signal_emitted(creator, "exited")
	assert_false(creator._exit_confirm_panel.visible)

func test_pressing_it_shows_the_existing_unsaved_confirmation_when_there_are_unsaved_changes() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	creator.draft.boss_name = "未保存の最終確認"
	watch_signals(creator)
	summary.find_child("BackToCreatorListButton", true, false).pressed.emit()
	assert_signal_not_emitted(creator, "exited", "must not discard unsaved work silently")
	assert_true(creator._exit_confirm_panel.visible, "must reuse the existing save/discard/cancel confirmation")

func test_discarding_from_the_confirmation_still_exits_and_cancel_still_stays() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	creator.draft.boss_name = "未保存の最終確認2"
	watch_signals(creator)
	summary.find_child("BackToCreatorListButton", true, false).pressed.emit()
	creator._on_exit_confirm_cancel_pressed()
	assert_signal_not_emitted(creator, "exited")
	assert_eq(creator.draft.boss_name, "未保存の最終確認2", "cancel must not discard the edit")
	summary.find_child("BackToCreatorListButton", true, false).pressed.emit()
	creator._on_exit_confirm_discard_pressed()
	assert_signal_emitted(creator, "exited")
	assert_false(creator._exit_confirm_panel.visible)

func test_save_and_publish_buttons_are_unaffected() -> void:
	var creator := _new_creator()
	var summary := _summary_of(creator)
	assert_not_null(summary.find_child("SaveButton", true, false))
	assert_not_null(summary.find_child("PublishOnlineButton", true, false))
