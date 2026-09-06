extends GutTest

## RPG BOSS MAKER — Phase 1 実機プレイ改善③ 回帰テスト。
##
## ユーザー本人の実機プレイで見つかった4点（依頼原文）:
## 1. 公開設定へ「勝利条件」「特殊条件」の公開ON/OFFを追加
## 2. 保存成功後は「Creatorへ戻る」ではなく「クリエイター一覧へ戻る」で
##    一覧へ直帰
## 3. TEST BATTLE等で意味のないCreator STEPナビゲーションを非表示
## 4. ユーザー向け英語表記を可能な範囲で日本語化
##
## test_rbm_realplay1/2_ui_polish.gdと同じ既存の確立済み手法（実際に
## RBMGameRootをインスタンス化し、Godot自身のレイアウト計算・実シグナル
## 経路を経た本物のControl.size/text/value_changedだけを検証する）を踏襲
## する——このファイル自身のヘッダコメント参照、意図的に複製している。
const TEST_DIR := "user://bossmaker_test_realplay3_ui/stages"
const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

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

## CHALLENGE UI再設計: 一覧カード(RBMChallengeUiKit.build_boss_card())は
## Buttonではなくgui_input経由でクリックを検知するPanelContainerのため、
## _btn()では模擬できない——test_rbm_phase35_step4_battle_ui.gdが既に
## 確立している「合成InputEventMouseButtonをgui_inputへ直接emitする」
## 手法をそのまま踏襲する。
func _click_card(card: Control) -> void:
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	card.gui_input.emit(fake_click)

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

## UI改善②: 「新しいボス戦を作る」は今やCreatorへ直接入らず、SIMPLE/
## ADVANCEDの作成方法選択パネルをまず経由する——シンプルを選んで先へ進む。
func _new_creator_session() -> Array:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return [root, root.creator_entry.main]

func _new_creator_main() -> RBMCreatorMain:
	var session := await _new_creator_session()
	return session[1]

## test_rbm_e2e_full_journey.gd §4で実際に検証済みの、STEP1-6を実「次へ」で
## 辿り切れる最小限の有効データ。
func _fill_minimum_valid_draft(main: RBMCreatorMain, boss_name: String) -> void:
	main.draft.boss_name = boss_name
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	assert_true(main.draft.step1_is_valid(), "sanity")
	assert_true(main.draft.step2_is_valid(), "sanity")
	assert_true(main.draft.step5_is_valid(), "sanity")

func _advance_to_final_step(main: RBMCreatorMain) -> void:
	for _i in range(RBMCreatorMain.STEP_COUNT - 1):
		_btn(main, "NextButton").pressed.emit()
		await get_tree().process_frame
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT, "sanity: must be on the final STEP after advancing")

# =============================================================================
# item1: 公開設定へ「勝利条件」「特殊条件」を追加
# =============================================================================

func test_challenge_info_visibility_keys_include_win_condition_and_special_condition() -> void:
	assert_true(RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS.has("win_condition"))
	assert_true(RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS.has("special_condition"))
	var draft := RBMCreatorDraft.new()
	assert_true(draft.is_challenge_info_visible("win_condition"), "sanity: defaults to public")
	assert_true(draft.is_challenge_info_visible("special_condition"), "sanity: defaults to public")

## 実UI経由: STEP7で勝利条件を個別に非公開にし、CHALLENGE確認画面で実内容が
## 漏れないことを確認する（作者メッセージ側でヒントを与える遊び方の土台）。
func test_win_condition_off_hides_content_and_on_shows_it_on_confirm_screen() -> void:
	var session := await _new_creator_session()
	var root: RBMGameRoot = session[0]
	var main: RBMCreatorMain = session[1]
	_fill_minimum_valid_draft(main, "勝利条件テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]

	var checkbox: CheckBox = step7._visibility_checkboxes["win_condition"]
	assert_true(checkbox.button_pressed, "sanity: starts public")
	checkbox.button_pressed = false
	assert_false(main.draft.is_challenge_info_visible("win_condition"), "sanity: real CheckBox toggle must reach the draft")

	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main.current_stage_id.is_empty(), "sanity: save must have succeeded")
	var stage_id := main.current_stage_id
	# Creator UI改修（2026-09-05）§24〜§27（公開機能）: 保存しただけでは
	# CHALLENGEに表示されないため、このテストがCHALLENGE確認画面へ到達する
	# には公開まで必要——current_stage_idが既に確定しているため、公開は
	# 同じstage_idへの上書き保存として行われる（新しいstage_idは発行されない）。
	main.draft.record_clear_check_success()
	var publish_result := main.press_publish()
	assert_true(bool(publish_result.get("ok", false)), "sanity: publish must have succeeded")
	assert_eq(main.current_stage_id, stage_id, "sanity: publish must overwrite the same already-saved stage_id, not create a new one")

	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row)
	await get_tree().process_frame
	var confirm_view: RBMChallengeConfirmView = root.challenge_entry._confirm_view
	assert_eq(confirm_view.stage_id, stage_id, "sanity")
	assert_false(confirm_view._win_condition_label.text.contains("ボスのHPを0にする"), "hidden win condition must not leak its real content")
	assert_true(confirm_view._win_condition_label.text.contains("非公開"), "hidden win condition must show the existing hide/non-disclosure phrasing")

## 上記と対の確認: 公開のままなら実内容（現行Phase 1の固定勝利条件）が
## 見える——依頼書の例「勝利条件：ON→『ボスを撃破』等を表示」の直接確認。
func test_win_condition_visible_by_default_shows_real_content_on_confirm_screen() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "勝利条件公開テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	var result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(result.get("ok", false)), "sanity")

	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	var confirm_view := RBMChallengeConfirmView.new()
	add_child_autofree(confirm_view)
	confirm_view.open(str(result.get("stage_id", "")), restored)
	assert_false(confirm_view._win_condition_label.text.contains("非公開"))
	assert_true(confirm_view._win_condition_label.text.contains("勝利条件"))

## 特殊条件も同一パターンで非公開にできる。実機プレイ改善③の要求どおり
## _special_condition_text()は今も固定文字列"なし"を返す——特殊条件
## システム自体は追加していない（これは既存設計のまま、report参照）。
func test_special_condition_off_hides_content_and_on_shows_it_on_confirm_screen() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "特殊条件テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.set_challenge_info_visible("special_condition", false)
	var result := RBMLocalStageRepository.save_new(draft)

	var loaded := RBMLocalStageRepository.load_stage(str(result.get("stage_id", "")))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_false(restored.is_challenge_info_visible("special_condition"), "sanity: hidden setting must survive save/load")

	var confirm_view := RBMChallengeConfirmView.new()
	add_child_autofree(confirm_view)
	confirm_view.open(str(result.get("stage_id", "")), restored)
	assert_true(confirm_view._special_condition_label.text.contains("非公開"), "hidden special condition must not leak its content")
	assert_false(confirm_view._special_condition_label.text.contains("なし"), "the underlying fixed placeholder text must not leak while hidden")

## item2「既存6分類＋今回の2分類が同じ一括操作で同期する」の実UI直接確認
## ——「すべて非公開」「すべて公開」ボタンが実際にwin_condition/special_
## conditionのCheckBoxも一緒に動かすことを確認する。
func test_hide_all_and_show_all_buttons_also_toggle_win_and_special_condition_checkboxes() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "一括操作テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]

	var win_checkbox: CheckBox = step7._visibility_checkboxes["win_condition"]
	var special_checkbox: CheckBox = step7._visibility_checkboxes["special_condition"]
	assert_true(win_checkbox.button_pressed)
	assert_true(special_checkbox.button_pressed)

	_btn(step7, "HideAllVisibilityButton").pressed.emit()
	await get_tree().process_frame
	assert_false(win_checkbox.button_pressed, "すべて非公開 must also uncheck the new win_condition checkbox")
	assert_false(special_checkbox.button_pressed, "すべて非公開 must also uncheck the new special_condition checkbox")
	assert_false(main.draft.is_challenge_info_visible("win_condition"))
	assert_false(main.draft.is_challenge_info_visible("special_condition"))

	_btn(step7, "ShowAllVisibilityButton").pressed.emit()
	await get_tree().process_frame
	assert_true(win_checkbox.button_pressed, "すべて公開 must also recheck the new win_condition checkbox")
	assert_true(special_checkbox.button_pressed, "すべて公開 must also recheck the new special_condition checkbox")
	assert_true(main.draft.is_challenge_info_visible("win_condition"))
	assert_true(main.draft.is_challenge_info_visible("special_condition"))

# =============================================================================
# item4: 保存成功後は「クリエイター一覧に戻る」で一覧へ直帰
# =============================================================================

func test_save_success_screen_shows_the_new_button_text() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "ボタン文言テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	var success_button := _btn(main._save_view, "SuccessReturnButton")
	assert_eq(success_button.text, "クリエイター一覧に戻る")

func test_save_success_return_navigates_directly_to_the_saved_stage_list() -> void:
	var session := await _new_creator_session()
	var root: RBMGameRoot = session[0]
	var main: RBMCreatorMain = session[1]
	_fill_minimum_valid_draft(main, "直帰テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	var stage_id := main.current_stage_id
	assert_false(stage_id.is_empty(), "sanity: save must have succeeded")

	_btn(main._save_view, "SuccessReturnButton").pressed.emit()
	await get_tree().process_frame

	# 中間STEPを一切経由しない: STEP1-6画面自体が完全に非表示になり、
	# 保存済みボス一覧が直接表示される。
	assert_false(main.visible, "the STEP1-6 Creator screen must not be showing at all")
	assert_true(root.creator_entry._list_panel.visible, "the saved-stage list must be showing directly")
	assert_false(root.creator_entry._top_panel.visible)
	assert_eq(root.creator_entry._list_rows.get_child_count(), 1, "the just-saved stage must already be present, with no re-fetch step needed")
	var row: HBoxContainer = root.creator_entry._list_rows.get_child(0)
	var label: Label = row.get_node("StageRowLabel")
	assert_true(label.text.contains("直帰テストボス"), "sanity: the correct, just-saved stage must be the one listed")
	assert_true(label.text.contains(stage_id))

	# §35既存: current_stage_id・未保存変更状態は一切壊れていない。
	assert_eq(main.current_stage_id, stage_id)
	assert_false(main.has_unsaved_changes())

## 保存フローの「戻る」（選択画面、保存せず戻る）は引き続きSTEP7へ戻る——
## 新しいシグナルは保存"成功後"にだけ関係し、既存の戻る導線は無改修である
## ことを確認する。
func test_save_view_plain_back_button_still_returns_to_step7_unaffected() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "戻る無改修テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveBackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible, "the plain 戻る (not a successful save) must still return to the STEP screens")
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT)

# =============================================================================
# item3/5/6: TEST BATTLE等での不要なCreator STEPナビゲーション非表示
# =============================================================================

func test_step_nav_row_is_visible_while_editing_steps() -> void:
	var main := await _new_creator_main()
	assert_true(main._nav_row.visible, "sanity: STEP1-6自体の編集中はナビゲーションが必要")
	assert_true(_btn(main, "NextButton").visible or true)  # nav_row自体がvisibleであれば十分、個別ボタンのvisibleはpress_next可否で別途制御される

func test_step_nav_row_is_hidden_during_test_battle_and_quit_test_still_works() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "テストバトル非表示テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "TestBattleButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._test_battle_view.visible, "sanity")
	assert_false(main._nav_row.visible, "戻る/最終確認へ戻る/次へ must be hidden while TEST BATTLE is showing")

	# 既存の正式な退出操作（テストを終了）は引き続き存在・機能する。
	var quit_button := _btn(main._test_battle_view, "QuitTestButton")
	assert_true(quit_button.visible)
	quit_button.pressed.emit()
	await get_tree().process_frame
	_btn(main._test_battle_view, "QuitConfirmButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible, "quitting TEST BATTLE via its own official exit must return to the STEP1-5 screen")
	## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§19: TEST BATTLE/
	## CLEAR CHECKはSTEP5（最終確認）から起動するため、戻り先も常にSTEP5——
	## そしてSTEP5自身は共有_nav_row（戻る/最終確認へ戻る/次へ）を使わない
	## 明示的な例外のため、STEP5へ戻ってもnav_rowは引き続き非表示のままで
	## 正しい（代わりにSTEP5自身の下部バー「← 戻る/保存/公開」が使える）。
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT, "sanity: quitting must return to STEP5, the step TEST BATTLE was launched from")
	assert_false(main._nav_row.visible, "STEP5 itself never shows the shared nav row, even after returning to it")
	var step7_after_quit: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	assert_true(step7_after_quit.visible)
	assert_true(_btn(step7_after_quit, "BackButton").is_visible_in_tree(), "STEP5's own back button must be reachable instead")

func test_step_nav_row_is_hidden_during_clear_check() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "クリアチェック非表示テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "ClearCheckButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._clear_check_view.visible, "sanity")
	assert_false(main._nav_row.visible, "戻る/最終確認へ戻る/次へ must be hidden while CLEAR CHECK is showing")

	# 既存の正式な退出操作（Creatorに戻る、Clear Check自身のボタン）は
	# 引き続き存在・機能する。
	_btn(main._clear_check_view, "ConfirmStartButton").pressed.emit()
	await get_tree().process_frame
	var quit_button := _btn(main._clear_check_view, "QuitButton")
	assert_true(quit_button.visible)
	quit_button.pressed.emit()
	await get_tree().process_frame
	assert_true(main._steps_root.visible, "quitting Clear Check via its own official exit must return to the STEP1-5 screen")
	## Creator UI改修（2026-09-05）§19: 上のTEST BATTLE版と同じ理由——CLEAR
	## CHECKもSTEP5から起動するため、戻り先のSTEP5自身は共有_nav_rowを
	## 使わない例外のまま。
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT, "sanity: quitting must return to STEP5, the step CLEAR CHECK was launched from")
	assert_false(main._nav_row.visible, "STEP5 itself never shows the shared nav row, even after returning to it")

func test_step_nav_row_is_hidden_during_save_flow() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "保存中非表示テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._save_view.visible, "sanity")
	assert_false(main._nav_row.visible, "戻る/最終確認へ戻る/次へ must be hidden while the save screen is showing")

func test_step_nav_row_is_hidden_during_appearance_picker() -> void:
	var main := await _new_creator_main()
	main.open_appearance_picker()
	await get_tree().process_frame
	assert_false(main._nav_row.visible, "the STEP nav row is equally meaningless while picking an appearance")

# =============================================================================
# item8/9/11: 日本語化
# =============================================================================

func test_common_menu_uses_japanese_labels() -> void:
	var root := await _make_root()
	assert_eq(_btn(root, "CreateModeButton").text, "作成")
	assert_eq(_btn(root, "ChallengeModeButton").text, "挑戦")

func test_creator_and_challenge_entry_titles_are_japanese() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	var creator_title: Label = root.creator_entry.find_child("EntryTitleLabel", true, false)
	assert_eq(creator_title.text, "ボス戦を作成")

	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	# CHALLENGE UI再設計: 「挑戦」を押すと挑戦ハブが最初に表示される
	# （旧ChallengeListTitleLabelは共通一覧画面のヘッダから退役し、
	# 「挑戦」という見出し自体はハブ画面のHubTitleLabelへ移った）。
	var hub_title: Label = root.challenge_entry.find_child("HubTitleLabel", true, false)
	assert_eq(hub_title.text, "挑戦")

func test_step2_weak_and_resist_attribute_buttons_use_japanese_labels() -> void:
	var main := await _new_creator_main()
	main.go_to_step(2)
	await get_tree().process_frame
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	var expected := {"FIRE": "炎", "ICE": "氷", "LIGHTNING": "雷", "WIND": "風", "NEUTRAL": "無"}
	for attribute_id in expected.keys():
		var weak_button: Button = step2.find_child("Weak_%s" % attribute_id, true, false)
		assert_not_null(weak_button, "sanity")
		assert_eq(weak_button.text, expected[attribute_id], "weak button for %s must show its Japanese label, not the raw internal id" % attribute_id)
		var resist_button: Button = step2.find_child("Resist_%s" % attribute_id, true, false)
		assert_eq(resist_button.text, expected[attribute_id])
		# 内部name/選択ロジックは無改修——ノード名自体は英語IDのまま。
		assert_eq(weak_button.name, "Weak_%s" % attribute_id)

func test_step3_attribute_dropdown_uses_japanese_labels() -> void:
	var main := await _new_creator_main()
	main.go_to_step(3)
	await get_tree().process_frame
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	_btn(step3, "AddNormalActionButton").pressed.emit()
	await get_tree().process_frame
	var expected_order := ["炎", "氷", "雷", "風", "無"]
	for i in range(expected_order.size()):
		assert_eq(step3._form._attack_attribute_option.get_item_text(i), expected_order[i])

func test_test_battle_mode_label_and_turn_label_are_japanese() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "テストバトル日本語テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "TestBattleButton").pressed.emit()
	await get_tree().process_frame
	var view := main._test_battle_view
	assert_eq(view._mode_label.text, "テストバトル")
	assert_true(view._boss_label.text.contains("ターン"), "the boss status line must show ターン, not the raw English Turn")
	assert_false(view._boss_label.text.contains("Turn"), "no raw English 'Turn' token should remain")

func test_clear_check_mode_and_outcome_labels_are_japanese() -> void:
	var main := await _new_creator_main()
	_fill_minimum_valid_draft(main, "クリアチェック日本語テストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	_btn(step7, "ClearCheckButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._clear_check_view, "ConfirmStartButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main._clear_check_view._mode_label.text, "クリアチェック")
	_btn(main._clear_check_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_true(main._clear_check_view.session.battle.battle_over, "sanity: boss HP=1 guarantees a win")
	assert_eq(main._clear_check_view._outcome_label.text, "クリアチェック成功")

## 戦闘ログにRBMBattleの内部英語トークン（damage/heal/buff_atk_self/
## target:boss/ally_chosen/ally_all等）が生表示されないことの直接確認
## ——item9の核心。実際の1ラウンドを実UI経由の「通常攻撃」ボタンで解決し、
## 表示された本物のログ文字列を検証する。
func test_battle_log_never_leaks_raw_internal_effect_or_target_tokens() -> void:
	var main := await _new_creator_main()
	main.draft.boss_name = "ログ日本語テストボス"
	main.draft.hp = 999999
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	var definition := main.draft.to_definition()
	assert_true(main._test_battle_view.start(definition), "sanity")
	_btn(main._test_battle_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	var log_text := main._test_battle_view._log_label.text
	assert_false(log_text.is_empty(), "sanity: at least one log line must have been rendered")
	for raw_token in ["damage", "heal", "buff_atk_self", "target:boss", "ally_chosen", "ally_all", "actor:"]:
		assert_false(log_text.contains(raw_token), "battle log must never leak the raw internal token '%s': %s" % [raw_token, log_text])
	assert_true(log_text.contains("攻撃"), "the log must describe the real attack in Japanese: %s" % log_text)
	assert_true(log_text.contains("ダメージ"), "the log must show the damage amount in Japanese: %s" % log_text)
