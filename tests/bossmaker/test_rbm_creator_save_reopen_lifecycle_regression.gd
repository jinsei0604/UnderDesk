extends GutTest

## RPG BOSS MAKER Creator — 「保存 → クリエイター一覧に戻る → 再編集」で
## Creator編集画面ではなく保存完了画面が再表示されてしまう重大な状態遷移
## 不具合の回帰テスト。
##
## 根本原因: RBMCreatorEntryはRBMCreatorMainを1つだけ保持し続け、Creatorを
## 開くたびに破棄・再構築しない(RBMCreatorEntry冒頭のコメント参照)。保存
## 完了画面の「クリエイター一覧に戻る」(RBMCreatorSaveView._on_success_
## return_pressed() → RBMCreatorMain._on_save_return_to_creator_list())は、
## Creator自体を非表示にするだけで、内部の_show_only()サブビュー状態
## (_steps_root/_appearance_picker/_test_battle_view/_clear_check_view/
## _save_view のうちどれが「現在の中身」か)を_steps_rootへ戻していなかった
## ——他の「Creatorへ戻る」経路(_on_save_return_to_creator()/_on_test_battle_
## return_to_creator()/_on_clear_check_return_to_creator()等)は全て
## _show_only(_steps_root)を呼んでいるのに、この経路だけ欠落していた。
## そのため、次に同じRBMCreatorMainインスタンスをstart_new()/start_loaded()
## で再利用した際、保存完了画面(_save_view、特に_success_panel)が残留
## 表示されてしまう——アプリを再起動すると直っていたのは、再起動によって
## RBMCreatorEntry/RBMCreatorMain/RBMCreatorSaveViewが全て新規インスタンスへ
## 作り直され、_success_panel.visible等の既定値(false)へ戻るため。
##
## 修正: start_new()とstart_loaded()自身に_show_only(_steps_root)を追加した
## ——「新しい編集セッションを開始する」ことの一部として、前回セッションが
## どのサブビューを表示していたかに関わらず必ず_steps_rootへ戻す(draft等の
## 永続データには一切触れない)。

const TEST_DIR := "user://bossmaker_test_creator_lifecycle/stages"

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

func _new_entry() -> RBMCreatorEntry:
	var entry := RBMCreatorEntry.new()
	add_child_autofree(entry)
	return entry

func _fill_minimum_valid_boss(creator: RBMCreatorMain, boss_name: String) -> void:
	creator.draft.boss_name = boss_name
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

## 保存完了画面から「クリエイター一覧に戻る」を実際のボタン操作(公開シグナル
## 経由)で押し、一覧へ戻る——ユーザーの実操作と同じ経路のみを通る
## (press_exit_creator()等の別経路は一切使わない)。
func _save_new_and_return_to_list_via_success_button(main: RBMCreatorMain) -> String:
	main.press_save()
	main._save_view._save_new_button.pressed.emit()
	var stage_id := main.current_stage_id
	main._save_view._success_return_button.pressed.emit()
	return stage_id

func _overwrite_and_return_to_list_via_success_button(main: RBMCreatorMain) -> void:
	main.press_save()
	main._save_view._overwrite_button.pressed.emit()
	main._save_view._success_return_button.pressed.emit()

# ---------------------------------------------------------------------------
# ユーザー要求の中核シナリオ: 保存 → 一覧 → 同一アプリセッションで再編集
# ---------------------------------------------------------------------------

func test_save_then_reopen_same_boss_without_app_restart() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_advanced_mode_pressed()
	var main := entry.main
	_fill_minimum_valid_boss(main, "再現テストボス")

	var stage_id := _save_new_and_return_to_list_via_success_button(main)
	assert_true(main._save_view._success_panel.visible, "sanity: 保存完了画面はこの時点でまだvisible=trueのまま(Creator自体は非表示)")
	assert_true(entry._list_panel.visible, "「クリエイター一覧に戻る」でCreator入口の一覧画面が表示されること")

	# 同一アプリセッション(entry/mainを一切作り直さない)で、今保存したボスの
	# 「編集」を押す。
	entry._on_open_stage_pressed(stage_id)

	# 6. 保存完了Viewが非表示、7. 通常Creator Viewが表示。
	assert_false(main._save_view.visible, "再編集時、保存完了画面(SaveView)が残留表示されてはならない")
	assert_true(main._steps_root.visible, "再編集時、通常のCreator STEP画面(_steps_root)が表示されること")
	assert_true(main.visible)

	# 8. Draftが正しくロードされている。
	assert_eq(main.draft.boss_name, "再現テストボス")
	assert_eq(main.current_stage_id, stage_id)

	# 9. 編集操作が可能であること(単にvisibleなだけでなく、実際に編集して
	# 再度保存できるところまで確認する)。
	main.draft.boss_name = "再編集で変更した名前"
	assert_true(main.has_unsaved_changes(), "編集操作が正しくdraftへ反映され、未保存変更として検知されること")
	var overwrite_result := main.press_overwrite_save()
	assert_true(bool(overwrite_result.get("ok", false)), "再編集後の上書き保存が正常に成功すること")
	assert_false(main.has_unsaved_changes())

# ---------------------------------------------------------------------------
# §7: 新規作成にも影響がないこと
# ---------------------------------------------------------------------------

func test_save_then_new_creation_does_not_show_stale_save_success_screen() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	var main := entry.main
	_fill_minimum_valid_boss(main, "旧ボス")
	_save_new_and_return_to_list_via_success_button(main)

	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()

	assert_false(main._save_view.visible, "新規作成でも保存完了画面が残留表示されてはならない")
	assert_true(main._steps_root.visible, "新規作成は必ず通常のCreator STEP画面から始まること")
	assert_eq(main.current_step, 1, "新規作成は必ずSTEP1から始まること")
	assert_eq(main.draft.boss_name, "", "新規作成では前のボスの内容を引き継がないこと")
	assert_eq(main.current_stage_id, "", "新規作成はstage_idを持たないこと")

# ---------------------------------------------------------------------------
# §8-C: 保存→一覧→別ボスの編集
# ---------------------------------------------------------------------------

func test_save_boss_a_then_editing_boss_b_does_not_show_stale_save_success_screen() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	var main := entry.main
	_fill_minimum_valid_boss(main, "ボスA")
	_save_new_and_return_to_list_via_success_button(main)

	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	_fill_minimum_valid_boss(main, "ボスB")
	var stage_id_b := _save_new_and_return_to_list_via_success_button(main)

	entry._on_open_stage_pressed(stage_id_b)
	assert_false(main._save_view.visible)
	assert_true(main._steps_root.visible)
	assert_eq(main.draft.boss_name, "ボスB")

# ---------------------------------------------------------------------------
# §8-A/§8-B/§10: 保存→再編集を連続で繰り返しても壊れないこと
# ---------------------------------------------------------------------------

func test_repeated_save_and_reopen_cycles_on_the_same_boss_keep_working() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_advanced_mode_pressed()
	var main := entry.main
	_fill_minimum_valid_boss(main, "連続テストボス")
	var stage_id := _save_new_and_return_to_list_via_success_button(main)

	for i in range(3):
		entry._on_open_stage_pressed(stage_id)
		assert_false(main._save_view.visible, "%d回目の再編集で保存完了画面が残留表示されてはならない" % (i + 1))
		assert_true(main._steps_root.visible, "%d回目の再編集で通常のCreator画面が表示されること" % (i + 1))
		assert_eq(main.draft.boss_name, "連続テストボス")
		main.draft.hp = 1000 + i
		_overwrite_and_return_to_list_via_success_button(main)
		assert_eq(main.current_stage_id, stage_id, "上書き保存を繰り返してもstage_idは変わらないこと")

	entry._on_open_stage_pressed(stage_id)
	assert_true(main._steps_root.visible)
	assert_eq(main.draft.hp, 1002, "3回分の編集内容がすべて正しく保存・再ロードされていること")

## §8全体: 新規作成→保存→一覧→編集→保存→一覧→再編集、という連続操作。
func test_scenario_a_new_creation_then_edit_then_reopen_in_sequence() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	var main := entry.main
	_fill_minimum_valid_boss(main, "シナリオAボス")
	var stage_id := _save_new_and_return_to_list_via_success_button(main)

	entry._on_open_stage_pressed(stage_id)
	assert_true(main._steps_root.visible, "1回目の編集で正常にCreatorが開くこと")
	main.draft.atk = 999
	_overwrite_and_return_to_list_via_success_button(main)

	entry._on_open_stage_pressed(stage_id)
	assert_true(main._steps_root.visible, "2回目の再編集でも正常にCreatorが開くこと")
	assert_eq(main.draft.atk, 999)
