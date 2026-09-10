extends GutTest

## RPG BOSS MAKER — Phase 1 実機プレイ改善② 回帰テスト。
##
## ユーザー本人の実機プレイで見つかった4点（依頼原文）:
## 1. 「作者備考」→「作者メッセージ」への表示名変更（内部フィールド名
##    author_notesは既存セーブ互換のため無改修）
## 2. 保存済みボス編集時はSTEP1ではなくSTEP7確認画面から開始（「新しい
##    ボス戦を作る」は引き続きSTEP1から開始、既存の未保存変更判定・
##    STEP7の戻る連鎖は無改修）
## 3. ボス名・数値入力・スキル名など、文字が見切れる入力欄をcustom_minimum_
##    sizeで拡張（HSliderで確立済みの既存修正技法をLineEdit/SpinBoxへ
##    適用しただけ——値の範囲・validation自体には一切触れていない）
## 4. スキルATK倍率Slider操作が数値表示・基準ダメージ表示・Draft値へ
##    反映されない不具合の修正。根本原因はRBMCreatorStep3Skillsの4つの
##    Slider/SpinBoxペア全てに共通する同一のバグ（Sliderのvalue_changed.
##    connect()を、ペア先のSpinBoxがまだnullの時点でbind()していたため、
##    Slider操作のたびに`paired.value = v`がnullに対する呼び出しで
##    エラーとなり中断——_syncingガードが解除されないまま永久にtrueへ
##    張り付き、以後そのペアの双方向同期が完全に停止していた）。ユーザーが
##    実機で気づいたのはATK倍率ペアだが、同一の根本原因を持つ自己回復
##    固定値・自己回復割合・ATK自己強化倍率の3ペアも合わせて修正した
##    （詳細はrbm_creator_step3_skills.gd自身のコメント参照）。
##
## test_rbm_realplay1_ui_polish.gdと同じ既存の確立済み手法（実際に
## RBMGameRootをインスタンス化し、Godot自身のレイアウト計算・実シグナル
## 経路を経た本物のControl.size/value_changedだけを検証する）を踏襲する
## ——このファイル自身のヘッダコメント参照、意図的に複製している。
const TEST_DIR := "user://bossmaker_test_realplay2_ui/stages"
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
## ADVANCEDの作成方法選択パネルをまず経由する——この2つのヘルパーは
## シンプルを選んで先へ進む。
func _new_creator_main() -> RBMCreatorMain:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return root.creator_entry.main

## item2/item1後半のCHALLENGE確認画面検証で、Creator退出後の共通ルートへ
## 戻る必要があるテスト専用——rootとmainの両方を返す。
func _new_creator_session() -> Array:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return [root, root.creator_entry.main]

## §16と同じ既存の再帰探索技法（test_rbm_realplay1_ui_polish.gdの
## _check_no_visible_overlap()参照、意図的に複製している）——Label.textの
## 部分一致で1つ見つけて返す。見つからなければnull。
func _find_label_containing(node: Node, substring: String) -> Label:
	if node is Label and (node as Label).text.contains(substring):
		return node
	for child in node.get_children():
		var found := _find_label_containing(child, substring)
		if found != null:
			return found
	return null

## STEP1-6を実「次へ」ボタンで辿り切れる最小限の有効データ——
## test_rbm_e2e_full_journey.gd §4で実際に検証済みの組み合わせをそのまま
## 踏襲（boss_name/hp/atk/spd/1名のparty character）。
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
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT, "sanity: must be on the final STEP after advancing through all NextButton presses")

# =============================================================================
# item1: 「作者備考」→「作者メッセージ」
# =============================================================================

func test_author_message_label_reads_new_text_not_the_old_one_in_step7_and_challenge_confirm() -> void:
	var session := await _new_creator_session()
	var root: RBMGameRoot = session[0]
	var main: RBMCreatorMain = session[1]
	_fill_minimum_valid_draft(main, "作者メッセージテストボス")
	await _advance_to_final_step(main)
	var step7: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]

	# STEP7側: 「作者メッセージ」というラベルが実際に存在し、旧「作者備考」
	# という文字列はもう画面のどこにも出ていないことを確認する。
	var step7_label := _find_label_containing(step7, "作者メッセージ")
	assert_not_null(step7_label, "STEP7 must show a label containing '作者メッセージ'")
	assert_null(_find_label_containing(step7, "作者備考"), "STEP7 must no longer show the old '作者備考' text anywhere")

	# 実UI（本物のTextEdit）経由で作者メッセージを入力する——既存の200文字
	# 制限・保存/読込機構には一切触れない、表示名だけの変更であることを
	# 実UIから確認する。
	var notes_edit: TextEdit = step7.find_child("AuthorNotesEdit", true, false)
	assert_not_null(notes_edit)
	notes_edit.text = "これはテスト用の作者メッセージです"
	notes_edit.text_changed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.author_notes, "これはテスト用の作者メッセージです", "real TextEdit input must still reach draft.author_notes (internal field name unchanged)")

	_btn(step7, "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main.current_stage_id.is_empty(), "sanity: save must have succeeded")
	_btn(main._save_view, "SuccessReturnButton").pressed.emit()
	await get_tree().process_frame

	# Creator UI改修（2026-09-05）§24〜§27（公開機能）: 保存しただけでは
	# CHALLENGEに表示されないため、このテストがCHALLENGE確認画面側の内容を
	# 確認するには実際に公開する必要がある——Clear Check達成はrecord_clear_
	# check_success()（他の多くのテストで確立済みの直接API、実バトルを経ずに
	# 状態だけ確定する）。公開UI整理（2026-09-10）でローカル公開ボタンは
	# UIから廃止されたため、press_publish()を直接呼ぶ（機能自体は無改修）。
	main.draft.record_clear_check_success()
	step7.refresh()
	await get_tree().process_frame
	main.press_publish()
	await get_tree().process_frame
	assert_true(main.draft.is_published(), "sanity: publish must have succeeded")

	_btn(main, "ExitCreatorButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame

	# CHALLENGE確認画面側も同様に確認する。
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(root.challenge_entry._list_rows.get_child_count(), 1, "sanity: the just-saved stage must appear in the CHALLENGE list")
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row)
	await get_tree().process_frame
	var confirm_view: RBMChallengeConfirmView = root.challenge_entry._confirm_view
	assert_true(confirm_view.visible, "sanity: CHALLENGE confirm screen must be showing")
	assert_true(confirm_view._author_notes_label.text.contains("作者メッセージ:"), "CHALLENGE confirm screen must show the new '作者メッセージ:' label")
	assert_true(confirm_view._author_notes_label.text.contains("これはテスト用の作者メッセージです"), "CHALLENGE confirm screen must still show the actual author message content")
	assert_false(confirm_view._author_notes_label.text.contains("作者備考"), "CHALLENGE confirm screen must not show the old '作者備考' text anywhere")

func test_author_message_still_respects_the_existing_200_char_limit_and_round_trips_through_save_load() -> void:
	assert_eq(RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH, 200, "the existing 200-character limit itself must not change")

	var draft := RBMCreatorDraft.new()
	draft.boss_name = "文字数テストボス"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	var long_text := "あ".repeat(250)
	draft.set_author_notes(long_text)
	assert_eq(draft.author_notes.length(), 200, "set_author_notes() must still truncate to MAX_AUTHOR_NOTES_LENGTH, unchanged")

	var result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(result.get("ok", false)), "sanity: save must succeed")
	var stage_id := str(result.get("stage_id", ""))

	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	assert_true(bool(loaded.get("ok", false)))
	var loaded_draft := RBMCreatorDraft.new()
	loaded_draft.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(loaded_draft.author_notes, draft.author_notes, "author_notes (the internal field, unchanged by the display-name rename) must round-trip through save/load exactly")
	assert_eq(loaded_draft.author_notes.length(), 200)

# =============================================================================
# item2: 保存済みボス編集時はSTEP1ではなくSTEP7確認画面から開始
# =============================================================================

## Creator UI再設計によりSTEP_COUNTは7→6へ減ったため、この既存テスト
## （旧「保存済みボス編集はSTEP7から開始、STEP7の戻るはSTEP6へ」）は
## 「保存済みボス編集は最終STEP（新STEP6=旧STEP7Summary）から開始、その
## 戻るは1つ前のSTEP（新STEP5=旧STEP6PartySkills）へ」という等価な内容
## へ更新した——検証している仕様自体（保存済み編集時は確認画面から開始/
## 戻るボタンは1つ前のstepへ戻る）は変更していない。
func test_editing_a_saved_stage_starts_on_the_final_step_and_its_back_button_reaches_the_previous_step() -> void:
	var session := await _new_creator_session()
	var root: RBMGameRoot = session[0]
	var main: RBMCreatorMain = session[1]
	_fill_minimum_valid_draft(main, "STEP7優先テストボス")
	await _advance_to_final_step(main)
	_btn(main._step_views[RBMCreatorMain.STEP_COUNT - 1], "SaveButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._save_view, "SaveNewButton").pressed.emit()
	await get_tree().process_frame
	var stage_id := main.current_stage_id
	assert_false(stage_id.is_empty(), "sanity: save must have succeeded")
	_btn(main._save_view, "SuccessReturnButton").pressed.emit()
	await get_tree().process_frame

	_btn(main, "ExitCreatorButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.creator_entry._top_panel.visible, "sanity: must be back on the CREATE top screen")

	# =========================================================================
	# 実機プレイ改善② item2の核心: 「保存したボス戦を編集」経由で本物の
	# 一覧「編集」ボタンを押した瞬間、STEP1ではなく最終確認画面（新STEP6）
	# が最初に表示されること。
	# =========================================================================
	_btn(root.creator_entry, "EditSavedBossButton").pressed.emit()
	await get_tree().process_frame
	assert_true(root.creator_entry._list_panel.visible, "sanity: must be on the saved-stage list")
	assert_eq(root.creator_entry._list_rows.get_child_count(), 1, "sanity: exactly the one just-saved stage must be listed")
	var row: HBoxContainer = root.creator_entry._list_rows.get_child(0)
	_btn(row, "OpenButton").pressed.emit()
	await get_tree().process_frame

	assert_true(main.visible, "sanity: the real Creator STEP screens must be showing again")
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT, "editing a saved stage must start on the final confirmation STEP, not STEP1")
	assert_true(main.has_reached_summary, "showing the final STEP first must count as 'reached summary' so 最終確認へ戻る stays consistent with other entry points")
	assert_eq(main.current_stage_id, stage_id)
	assert_false(main.has_unsaved_changes(), "loading a just-saved stage must still report no unsaved changes, exactly as before this change")

	var step7_after_load: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	assert_true(step7_after_load.visible, "the final-confirmation view itself must be the one actually visible, not just current_step==STEP_COUNT as a number")

	# §7既存の「戻る」連鎖: 最終確認画面→1つ前のSTEP（新STEP5=旧STEP6
	# PartySkills）…がこの変更後も正しく機能すること。
	_btn(main, "BackButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.current_step, RBMCreatorMain.STEP_COUNT - 1, "the final confirmation screen's existing 戻る chain must still correctly reach the previous STEP")
	var previous_step_view: Control = main._step_views[RBMCreatorMain.STEP_COUNT - 2]
	assert_true(previous_step_view.visible, "the previous STEP's own view must actually be the one visible after 戻る")

func test_creating_a_new_boss_still_starts_on_step1_unaffected_by_the_step7_on_edit_change() -> void:
	var main := await _new_creator_main()
	assert_eq(main.current_step, 1, "creating a brand-new boss must still start on STEP1, unaffected by the STEP7-on-edit change")
	assert_false(main.has_reached_summary, "a brand-new Creator session must not already report 'reached summary'")

# =============================================================================
# item3/4: 見切れる入力欄の拡張（LineEdit/SpinBox）
# =============================================================================

func _assert_control_is_wide_enough(control: Control, min_width: float, min_height: float, description: String) -> void:
	assert_gte(control.size.x, min_width, "%s: width (%s) must be wide enough that its content does not clip" % [description, control.size.x])
	assert_gte(control.size.y, min_height, "%s: height (%s) must be tall enough" % [description, control.size.y])

## §12カードUI化: 名前入力欄は「編集」を押した時だけカード内へ展開する
## ——実際の編集/決定の実UI経路（EditNameButton→入力→ConfirmNameButton）で
## 幅・文字数制限の両方を確認する。フィールド幅の拡張自体はUIの見た目だけの
## 変更であり、既存のmax_length制限・truncationロジックには一切触れて
## いないことの直接証明でもある。
func test_step1_boss_name_field_is_wide_enough_and_stays_editable_near_max_length() -> void:
	var main := await _new_creator_main()
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	_assert_control_is_wide_enough(step1._name_edit, 300.0, 24.0, "STEP1 boss name LineEdit")

	var near_max_name := "十九文字までのテストボス名前です"  # 16 chars, well under 20
	step1._name_edit.text = near_max_name
	_btn(step1, "ConfirmNameButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.boss_name, near_max_name)

	# 手打ちの日本語リテラルは文字数を数え間違えやすいため、確実にちょうど
	# MAX_BOSS_NAME_LENGTH文字になるよう組み立てる。
	var exactly_max_name := "あ".repeat(RBMCreatorDraft.MAX_BOSS_NAME_LENGTH)
	assert_eq(exactly_max_name.length(), 20, "sanity: this literal is exactly MAX_BOSS_NAME_LENGTH long")
	_btn(step1, "EditNameButton").pressed.emit()
	await get_tree().process_frame
	step1._name_edit.text = exactly_max_name
	_btn(step1, "ConfirmNameButton").pressed.emit()
	await get_tree().process_frame
	assert_eq(main.draft.boss_name, exactly_max_name, "the full 20-character name must still be accepted, unclipped by validation")
	assert_eq(main.draft.boss_name.length(), RBMCreatorDraft.MAX_BOSS_NAME_LENGTH)

func test_step2_hp_atk_spd_spin_boxes_are_wide_enough_and_hp_is_wider_than_atk_and_spd() -> void:
	var main := await _new_creator_main()
	main.go_to_step(2)
	await get_tree().process_frame
	var step2: RBMCreatorStep2Stats = main._step_views[1]

	# BOSS_HP_MAX=1,000,000（7桁）はBOSS_ATK_MAX=9,999（4桁）/
	# BOSS_SPD_MAX=500（3桁）よりずっと多い桁数を要求するため、HPの
	# SpinBoxだけ明確に広い幅を持つこと（値の範囲自体は変更していない）。
	assert_eq(RBMDefinitionLoader.BOSS_HP_MAX, 1000000, "sanity: value ranges themselves must not have changed")
	assert_eq(RBMDefinitionLoader.BOSS_ATK_MAX, 9999, "sanity: value ranges themselves must not have changed")
	assert_eq(RBMDefinitionLoader.BOSS_SPD_MAX, 500, "sanity: value ranges themselves must not have changed")

	_assert_control_is_wide_enough(step2._hp_spin, 150.0, 24.0, "STEP2 HP SpinBox")
	_assert_control_is_wide_enough(step2._atk_spin, 100.0, 24.0, "STEP2 ATK SpinBox")
	_assert_control_is_wide_enough(step2._spd_spin, 100.0, 24.0, "STEP2 SPD SpinBox")
	assert_gt(step2._hp_spin.size.x, step2._atk_spin.size.x, "the HP SpinBox must be wider than the ATK SpinBox, since HP holds much larger numbers")
	assert_gt(step2._hp_spin.size.x, step2._spd_spin.size.x, "the HP SpinBox must be wider than the SPD SpinBox, since HP holds much larger numbers")

	# 現在値が常に全て表示可能であることを、実際に最大桁数の値を設定して
	# 確認する（値の範囲自体は変更していない）。
	step2.set_hp(RBMDefinitionLoader.BOSS_HP_MAX)
	await get_tree().process_frame
	assert_eq(step2._hp_spin.value, float(RBMDefinitionLoader.BOSS_HP_MAX))
	assert_eq(main.draft.hp, RBMDefinitionLoader.BOSS_HP_MAX)

func test_step3_skill_name_field_is_wide_enough() -> void:
	var main := await _new_creator_main()
	main.go_to_step(3)
	await get_tree().process_frame
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	_btn(step3, "AddNormalActionButton").pressed.emit()
	await get_tree().process_frame
	_assert_control_is_wide_enough(step3._form._name_edit, 300.0, 24.0, "STEP3 action name LineEdit")

# =============================================================================
# item4/§7: ATK倍率Sliderの数値表示・基準ダメージ表示・Draft値への反映
# =============================================================================

## Creator UI再設計により、STEP3スキル編集フォーム自体はRBMActionEditorForm
## へ切り出され共通化された（rbm_action_editor_form.gd自身のコメント参照）
## ——ここで検証していたSlider/SpinBoxペア同期バグとその修正は、このフォーム
## へそのまま引き継がれている（フィールド名・修正内容とも無改修）。以下の
## テストは新STEP3画面（RBMCreatorStep4Actions）から共通フォームを開く経路
## へ更新したのみで、検証している根本原因バグの再発防止という目的自体は
## 変更していない。
func _open_form_for_new_normal_action(main: RBMCreatorMain) -> RBMActionEditorForm:
	main.go_to_step(3)
	await get_tree().process_frame
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	_btn(step3, "AddNormalActionButton").pressed.emit()
	await get_tree().process_frame
	return step3._form

## 旧バグの再現条件そのもの: デフォルト値(1.0)とは明確に異なる値へ実際に
## Sliderをドラッグ（.valueへの直接書き込み——実HSlider実装が発火する
## value_changedシグナル経由、合成マウスイベントではない）し、ペアの
## SpinBox表示・基準ダメージ表示・保存されるスキルデータの3つ全てが
## 追従することを確認する。旧バグ（Sliderのconnect()がbind()した時点で
## ペアのSpinBoxがまだnullだったため、Slider操作のたびに_syncingが
## 永久にtrueへ張り付き、以後SpinBox表示側が一切更新されなくなる）が
## 再発すれば、この関数は必ずFAILする——_attack_multiplier_spin.valueが
## 初期値1.0のまま変化しないため。
func test_step3_attack_multiplier_slider_drag_updates_spinbox_display_baseline_preview_and_draft_value() -> void:
	var main := await _new_creator_main()
	var form := await _open_form_for_new_normal_action(main)
	assert_eq(form._attack_multiplier_spin.value, 1.0, "sanity: new skills default atk_multiplier to 1.0")

	var before_preview := form._attack_preview_label.text
	form._attack_multiplier_slider.value = 3.33
	await get_tree().process_frame

	assert_eq(form._attack_multiplier_spin.value, 3.33, "dragging the Slider must live-update the paired SpinBox's displayed number")
	assert_eq(form._editor_action_data()["atk_multiplier"], 3.33, "the value that would actually be saved must match the Slider's new value")

	# §7: 「基準ダメージ表示」は既存設計どおりATK倍率Slider操作に連動して
	# 即座に再計算される（RBMCreatorDraft.baseline_attack_damage()経由、
	# このファイル自身の再計算ではない）——変更後の値と一致し、かつ
	# ドラッグ前の表示から実際に変化していること。
	var expected_damage := main.draft.baseline_attack_damage({"atk_multiplier": 3.33})
	assert_eq(form._attack_preview_label.text, "基準ダメージ: %d" % expected_damage, "the baseline damage preview must live-recalculate via the same existing draft.baseline_attack_damage() path in response to the Slider change")
	assert_ne(form._attack_preview_label.text, before_preview, "the baseline damage preview text must have actually changed")

func test_step3_attack_multiplier_direct_numeric_edit_updates_slider_and_draft_value() -> void:
	var main := await _new_creator_main()
	var form := await _open_form_for_new_normal_action(main)

	form._attack_multiplier_spin.value = 7.25
	await get_tree().process_frame

	assert_eq(form._attack_multiplier_slider.value, 7.25, "typing directly into the SpinBox must update the Slider's position to match")
	assert_eq(form._editor_action_data()["atk_multiplier"], 7.25, "the value that would actually be saved must match the directly-typed value")

## 保存経路そのものを実際に通し、Slider操作の結果が本当にDraft.skillsへ
## 書き込まれること（_editor_action_data()の一時読み取りだけでなく）を確認
## する。
func test_step3_attack_multiplier_slider_value_actually_persists_through_save() -> void:
	var main := await _new_creator_main()
	var form := await _open_form_for_new_normal_action(main)
	form._name_edit.text = "スライダー保存テスト"
	await get_tree().process_frame

	form._attack_multiplier_slider.value = 5.5
	await get_tree().process_frame
	_btn(form, "SaveActionButton").pressed.emit()
	await get_tree().process_frame

	assert_eq(main.draft.skills.size(), 1, "sanity: one skill must have been added")
	var saved_skill: Dictionary = main.draft.skills[0]
	assert_eq(float(saved_skill.get("atk_multiplier", -1.0)), 5.5, "the Slider-set multiplier must be the value that actually reaches draft.skills")

## 同じ根本原因バグを共有していた残り3ペア（自己回復固定値・自己回復
## 割合・ATK自己強化倍率）も同じ技法で修正されたことを確認する——
## _type_option.select(N) + _on_type_selected(N)は既存の他テスト
## （test_rbm_creator_flow.gd）でも使われている確立済みの型切り替え技法。
func test_step3_self_heal_and_atk_buff_slider_pairs_also_sync_after_the_same_root_cause_fix() -> void:
	var main := await _new_creator_main()

	# 自己回復（固定値・割合の両方とも同じバグ・同じ修正）
	var form := await _open_form_for_new_normal_action(main)
	form._type_option.select(1)
	form._on_type_selected(1)
	await get_tree().process_frame

	form._self_heal_fixed_slider.value = 12345.0
	await get_tree().process_frame
	assert_eq(form._self_heal_fixed_spin.value, 12345.0, "SelfHealFixed: dragging the Slider must update the paired SpinBox")

	form._self_heal_percent_slider.value = 42.5
	await get_tree().process_frame
	assert_eq(form._self_heal_percent_spin.value, 42.5, "SelfHealPercent: dragging the Slider must update the paired SpinBox")

	form._on_cancel_pressed()
	await get_tree().process_frame

	# ATK自己強化
	form = await _open_form_for_new_normal_action(main)
	form._type_option.select(2)
	form._on_type_selected(2)
	await get_tree().process_frame

	form._atk_buff_multiplier_slider.value = 8.5
	await get_tree().process_frame
	assert_eq(form._atk_buff_multiplier_spin.value, 8.5, "AtkBuffMultiplier: dragging the Slider must update the paired SpinBox")
