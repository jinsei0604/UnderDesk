extends GutTest

## 見た目の刷新（2026-10、ユーザーが完成イメージで承認）で作り直した4画面の振る舞い:
##   挑戦ハブ / ボス戦作成の入口（2枚のカードと保存件数）/ 保存したボス戦の一覧（カード・詳細・検索・
##   0件・一致なし・読み込めないファイル・編集・削除の確認）。
## 保存先はテスト専用のフォルダ（実プレイヤーの保存データには触れない）。

const TEST_DIR := "user://bossmaker_test_entry_menu_ui/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir_name in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(dir_name))
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)

func _new_entry() -> RBMCreatorEntry:
	var entry := RBMCreatorEntry.new()
	entry.size = Vector2(1280, 720)
	add_child_autofree(entry)
	await get_tree().process_frame
	return entry

func _valid_draft(boss_name: String) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.appearance_id = "appearance_slime"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

## クリアチェックを実際の戦闘で達成させる（test_rbm_creator_save_load と同じ手順）。
func _win_clear_check(draft: RBMCreatorDraft) -> void:
	var atk_id := str(draft.skills[0]["skill_id"])
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[atk_id] = 100.0
	var start := RBMDefinitionLoader.start_battle(draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity: fixture must actually win")
	draft.record_clear_check_success()

func _save(draft: RBMCreatorDraft, updated_unix_time: int = 0) -> String:
	var result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(result.get("ok", false)), "sanity: save must succeed")
	var stage_id := str(result.get("stage_id", ""))
	if updated_unix_time > 0:
		# 並び順の確認のため、保存ファイルの最終更新だけをテスト用に書き換える（テスト専用フォルダの中だけ）。
		var path := RBMLocalStageRepository.stages_dir().path_join("%s.json" % stage_id)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		data["updated_unix_time"] = updated_unix_time
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
	return stage_id

## 下書き1・挑戦可能1・クリアチェック済みで公開中1・覚醒ありの下書き1。
func _save_mixed_library() -> Dictionary:
	var ids := {}
	var draft_only := RBMCreatorDraft.new()
	draft_only.boss_name = "下書きのボス"
	ids["draft"] = _save(draft_only, 1_700_000_100)
	ids["playable"] = _save(_valid_draft("挑戦できるボス"), 1_700_000_300)
	var checked := _valid_draft("公開したボス")
	_win_clear_check(checked)
	assert_true(checked.publish(), "sanity: a clear-checked boss can be published")
	# 「公開中」の札・公開状態はオンラインの公開状態を見る（2026-10-17、PX-05）。オンライン公開に成功した時と同じ値にする
	checked.set_online_boss_id("online-boss-1")
	checked.set_online_published(true)
	ids["published"] = _save(checked, 1_700_000_200)
	var awakening := RBMCreatorDraft.new()
	awakening.boss_name = "覚醒する竜"
	awakening.appearance_id = "appearance_dragon"
	awakening.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	awakening.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"})
	ids["awakening"] = _save(awakening, 1_700_000_050)
	return ids

## 一覧に表示中の行（検索で隠れたカードは数えない）。
func _rows(entry: RBMCreatorEntry) -> Array:
	return entry._list_rows.get_children().filter(func(c): return (c as Control).visible)

# ---------------------------------------------------------------------------
# ボス戦作成の入口
# ---------------------------------------------------------------------------

func test_top_screen_shows_saved_counts_and_breakdown() -> void:
	_save_mixed_library()
	var entry := await _new_entry()
	var edit: Button = entry.find_child("EditSavedBossButton", true, false)
	assert_false((edit.find_child("SavedEmptyLabel", true, false) as Label).visible)
	assert_eq((edit.find_child("SavedCountValue", true, false) as Label).text, "4")
	assert_eq((edit.find_child("SavedCountSuffix", true, false) as Label).text, "件　（うち下書き 2件）")
	assert_eq((edit.find_child("ClearCheckedChip", true, false) as Label).text, "✓ クリアチェック済み 1")
	assert_eq((edit.find_child("PlayableChip", true, false) as Label).text, "挑戦可能 1")
	assert_eq((edit.find_child("PublishedChip", true, false) as Label).text, "公開中 1")
	# 内訳の札は、編集のカードが選ばれている時だけ見せる。
	var chips: Control = edit.find_child("SavedStatusChips", true, false)
	assert_false(chips.visible)
	var choice: RBMCreatorTopChoice = entry._top_choice
	choice.select(1, true)
	assert_true(chips.visible)
	assert_eq(chips.modulate.a, 1.0)

## 共通ルート（RBMGameRoot）と同じ順番: 見えない状態で作り、enter_create() の後に表示する。
## 作った時点では保存データを読まず、表示された時に数える。
func test_top_screen_counts_appear_when_the_hidden_entry_is_shown() -> void:
	_save_mixed_library()
	var entry := RBMCreatorEntry.new()
	entry.visible = false
	add_child_autofree(entry)
	await get_tree().process_frame
	var edit: Button = entry.find_child("EditSavedBossButton", true, false)
	assert_true(entry._top_counts_dirty, "a hidden entry must not read the saves yet")
	entry.enter_create()
	entry.visible = true
	assert_false(entry._top_counts_dirty)
	assert_false((edit.find_child("SavedEmptyLabel", true, false) as Label).visible)
	assert_eq((edit.find_child("SavedCountValue", true, false) as Label).text, "4")

func test_top_screen_counts_refresh_when_returning_from_the_list() -> void:
	var entry := await _new_entry()
	var edit: Button = entry.find_child("EditSavedBossButton", true, false)
	assert_true((edit.find_child("SavedEmptyLabel", true, false) as Label).visible, "no saves yet")
	_save(_valid_draft("あとから保存"))
	entry._on_edit_saved_pressed()
	entry._on_list_back_pressed()
	assert_false((edit.find_child("SavedEmptyLabel", true, false) as Label).visible)
	assert_eq((edit.find_child("SavedCountValue", true, false) as Label).text, "1")

func test_top_screen_returns_to_the_even_layout_when_shown_again() -> void:
	var entry := await _new_entry()
	entry._top_choice.select(0, true)
	entry._on_edit_saved_pressed()
	entry._on_list_back_pressed()
	await get_tree().process_frame
	assert_eq(entry._top_choice.selected, RBMCreatorTopChoice.NONE)
	assert_eq(entry._top_choice.new_card.size, entry._top_choice.edit_card.size)

func test_top_cards_open_the_mode_choice_and_the_saved_list() -> void:
	var entry := await _new_entry()
	entry.find_child("NewBossButton", true, false).pressed.emit()
	assert_true(entry._mode_choice_panel.visible)
	entry.find_child("ModeChoiceBackButton", true, false).pressed.emit()
	assert_true(entry._top_panel.visible)
	entry.find_child("EditSavedBossButton", true, false).pressed.emit()
	assert_true(entry._list_panel.visible)
	assert_false(entry._top_panel.visible)

func test_new_screens_keep_their_own_colors_instead_of_the_gold_conversion() -> void:
	var entry := await _new_entry()
	for key in ["NewBossButton", "EditSavedBossButton", "BackToRootButton"]:
		var button: Button = entry.find_child(key, true, false)
		assert_false(button.has_meta("world_semantic"), "%s must not be touched by RBMWorldUi.walk()" % key)
		assert_false(button.get_theme_stylebox("normal") is StyleBoxTexture, "%s must keep its flat (non-gold) style" % key)
	assert_true(entry._top_panel.has_meta("world_skip"))
	assert_true(entry._list_panel.has_meta("world_skip"))
	assert_true(entry._mode_choice_panel.has_meta("world_skip"))

# ---------------------------------------------------------------------------
# 保存したボス戦の一覧
# ---------------------------------------------------------------------------

func test_saved_list_is_sorted_by_last_update_and_shows_card_details() -> void:
	var ids := _save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	var rows := _rows(entry)
	assert_eq(rows.size(), 4)
	var order: Array = rows.map(func(r): return (r as RBMSavedBossCard).stage_id)
	assert_eq(order, [ids["playable"], ids["published"], ids["draft"], ids["awakening"]], "newest update first")
	assert_eq((entry.find_child("SavedCountLabel", true, false) as Label).text, "4件 / 更新が新しい順")

	var published: RBMSavedBossCard = rows[1]
	assert_eq((published.get_node("NameLabel") as Label).text, "公開したボス")
	assert_eq((published.get_node("StatusLabel") as Label).text, "✓ クリアチェック済み")
	assert_eq((published.get_node("StageIdLabel") as Label).text, "ID %s" % ids["published"])
	assert_not_null(published.get_node_or_null("PublishedTag"), "published bosses carry the 公開中 tag")
	assert_null(published.get_node_or_null("AwakeningTag"))
	assert_eq((published.get_node("ModeTag") as Label).text, "SIMPLE")
	for removed in ["AuthorLabel", "ChallengersValue", "ClearRateValue"]:
		assert_null(published.get_node_or_null(removed), "saved cards replace the online-only %s" % removed)
	var awakening: RBMSavedBossCard = rows[3]
	assert_eq((awakening.get_node("StatusLabel") as Label).text, "下書き")
	assert_not_null(awakening.get_node_or_null("AwakeningTag"), "an awakening HARDCORE boss carries the 覚醒 tag")
	assert_eq((awakening.get_node("ModeTag") as Label).text, "HARDCORE")
	assert_eq((rows[0].get_node("StatusLabel") as Label).text, "挑戦可能")
	assert_eq(RBMSavedBossCard.SIZE, RBMOnlineBossCard.SIZE, "same card frame as the online list")

func test_saved_list_search_states_and_clear_button() -> void:
	_save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	var count: Label = entry.find_child("SavedCountLabel", true, false)
	var no_match: Control = entry.find_child("SavedListNoMatch", true, false)
	entry._name_search_field.text = "ボス"
	entry._refresh_list()
	assert_eq(_rows(entry).size(), 3)
	assert_eq(count.text, "3件が一致 / 全4件")
	assert_false(no_match.visible)
	entry._name_search_field.text = "存在しない名前"
	entry._refresh_list()
	assert_eq(_rows(entry).size(), 0)
	assert_true(no_match.visible, "no-match message must show")
	assert_false((entry.find_child("SavedListEmpty", true, false) as Control).visible, "the empty-library message is for 0 saves only")
	assert_eq(count.text, "0件が一致 / 全4件")
	(no_match.find_child("SavedListClearSearchButton", true, false) as Button).pressed.emit()
	assert_eq(entry._name_search_field.text, "")
	assert_eq(_rows(entry).size(), 4)
	assert_false(no_match.visible)

## 検索欄の入力は、読み込み済みの行を絞り込むだけ（1文字ごとに保存ファイルを読み直さない・カードを作り直さない）。
## 外れたカードは置き場で保たれ、戻した時は同じカード（選択の状態も保つ）。
func test_search_filters_loaded_rows_without_rereading_or_rebuilding() -> void:
	var ids := _save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	var card_before := entry._find_row(ids["published"])
	card_before.pressed.emit()
	# 読み直しが起きていないことは、行の配列そのものが同じであることで確かめる。
	var entries_before: Array = entry._entries
	entry._name_search_field.text = "竜"
	entry._name_search_field.text_changed.emit("竜")
	assert_eq(_rows(entry).size(), 1)
	assert_same(entry._entries, entries_before, "typing must not re-read the save files")
	entry._name_search_field.text = ""
	entry._name_search_field.text_changed.emit("")
	assert_eq(_rows(entry).size(), 4)
	assert_same(entry._find_row(ids["published"]), card_before, "the same card comes back")
	# 選んでいたボス戦が検索で外れたら選択も外れる（見えないボス戦の詳細を出したままにしない）。
	assert_false(card_before.is_selected())
	assert_eq(entry._selected_stage_id, "")
	assert_not_null(entry._saved_detail.find_child("DetailHint", true, false))
	# 選んだまま絞り込んで、選んだボス戦が残る時は、選択も詳細もそのまま。
	card_before.pressed.emit()
	entry._name_search_field.text = "公開"
	entry._name_search_field.text_changed.emit("公開")
	assert_eq(_rows(entry).size(), 1)
	assert_true(card_before.is_selected())
	assert_eq((entry._saved_detail.find_child("DetailBossName", true, false) as Label).text, "公開したボス")
	assert_eq(entry._list_rows.get_child_count(), 4, "filtering hides cards instead of making new ones")

## 一覧を開き直した時、内容の変わっていないボス戦のカードはそのまま使い、変わったものだけ作り直す。
func test_reopening_the_list_reuses_unchanged_cards_and_rebuilds_changed_ones() -> void:
	var ids := _save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	var kept := entry._find_row(ids["playable"])
	var changed := entry._find_row(ids["draft"])
	var loaded := RBMLocalStageRepository.load_stage(ids["draft"])
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(loaded["draft_data"])
	draft.boss_name = "名前を変えたボス"
	assert_true(bool(RBMLocalStageRepository.overwrite(ids["draft"], draft).get("ok", false)))
	entry._on_list_back_pressed()
	entry._on_edit_saved_pressed()
	assert_same(entry._find_row(ids["playable"]), kept, "an unchanged boss keeps its card")
	var rebuilt := entry._find_row(ids["draft"])
	assert_ne(rebuilt, changed, "a changed boss gets a new card")
	assert_eq((rebuilt.get_node("NameLabel") as Label).text, "名前を変えたボス")
	assert_eq((_rows(entry)[0] as RBMSavedBossCard).stage_id, ids["draft"], "the just-updated boss moves to the top")
	assert_eq(entry._list_rows.get_child_count(), 4)

func test_saved_list_empty_state() -> void:
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	assert_eq(_rows(entry).size(), 0)
	assert_true((entry.find_child("SavedListEmpty", true, false) as Control).visible)
	assert_false((entry.find_child("SavedListNoMatch", true, false) as Control).visible)
	assert_eq((entry.find_child("SavedCountLabel", true, false) as Label).text, "")
	assert_null(entry._saved_detail.find_child("DetailHint", true, false), "nothing to choose, so no hint")

func test_unreadable_files_are_counted_but_never_listed() -> void:
	var good := _save(_valid_draft("健全なボス"))
	var file := FileAccess.open(RBMLocalStageRepository.stages_dir().path_join("1234567890.json"), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	assert_eq(_rows(entry).size(), 1, "§43: broken files stay out of the list")
	assert_eq((_rows(entry)[0] as RBMSavedBossCard).stage_id, good)
	var warning: Control = entry.find_child("SavedUnreadableWarning", true, false)
	assert_true(warning.visible)
	assert_eq((warning.find_child("SavedUnreadableLabel", true, false) as Label).text, "読み込めないボス戦が1件あります（ファイルが壊れている可能性）")
	assert_gte(entry._list_scroll.position.y, warning.position.y + warning.size.y, "the list must start below the warning")
	assert_true(RBMLocalStageRepository.stages_dir().path_join("1234567890.json") != "" and FileAccess.file_exists(RBMLocalStageRepository.stages_dir().path_join("1234567890.json")), "the broken file itself is left untouched")

func test_card_press_shows_detail_and_edit_opens_the_creator() -> void:
	var ids := _save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	var detail := entry._saved_detail
	assert_eq((detail.find_child("DetailHint", true, false) as Label).text, "左の一覧から編集するボス戦を選んでください")
	var card := entry._find_row(ids["published"])
	card.pressed.emit()
	assert_true(card.is_selected())
	assert_eq((detail.find_child("DetailBossName", true, false) as Label).text, "公開したボス")
	assert_eq((detail.find_child("DetailStageIdValue", true, false) as Label).text, ids["published"])
	assert_eq((detail.find_child("DetailBossHpValue", true, false) as Label).text, "1000")
	assert_eq((detail.find_child("DetailPublishStateValue", true, false) as Label).text, "公開中")
	assert_eq((detail.find_child("DetailClearCheck", true, false) as Label).text, "✓ クリアチェック済み")
	assert_not_null(detail.find_child("DetailPartyChip_hero", true, false))
	assert_null(detail.find_child("DetailChallengeButton", true, false), "the saved list edits instead of challenging")
	var awakening := entry._find_row(ids["awakening"])
	awakening.pressed.emit()
	assert_false(card.is_selected(), "only one card is selected at a time")
	assert_not_null(detail.find_child("DetailAwakeningTag", true, false))
	assert_eq((detail.find_child("DetailClearCheck", true, false) as Label).text, "下書き（未完成の項目があります）")
	assert_eq((detail.find_child("DetailPartyEmpty", true, false) as Label).text, "（まだ選ばれていません）")
	(detail.find_child("DetailEditButton", true, false) as Button).pressed.emit()
	assert_true(entry.main.visible, "the real 編集する button must open the creator")
	assert_eq(entry.main.current_stage_id, ids["awakening"])
	assert_eq(entry.main.draft.boss_name, "覚醒する竜")

func test_opening_a_stage_that_disappeared_shows_the_reason_and_stays_on_the_list() -> void:
	var stage_id := _save(_valid_draft("消えるボス"))
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	entry._find_row(stage_id).pressed.emit()
	DirAccess.remove_absolute(RBMLocalStageRepository.stages_dir().path_join("%s.json" % stage_id))
	(entry._saved_detail.find_child("DetailEditButton", true, false) as Button).pressed.emit()
	assert_true(entry._list_panel.visible)
	assert_false(entry.main.visible)
	assert_eq((entry._saved_detail.find_child("DetailError", true, false) as Label).text, "このボス戦を開けませんでした。\nファイルが壊れている可能性があります。")

func test_delete_dialog_from_the_detail_starts_on_cancel_and_deletes_only_on_confirm() -> void:
	var keep := _save(_valid_draft("残すボス"), 1_700_000_100)
	var target := _save(_valid_draft("消すボス"), 1_700_000_200)
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	entry._find_row(target).pressed.emit()
	(entry._saved_detail.find_child("DetailDeleteButton", true, false) as Button).pressed.emit()
	var dialog := entry._delete_confirm_panel
	assert_true(dialog.visible)
	assert_eq((dialog.find_child("DeleteConfirmLabel", true, false) as Label).text, "消すボス")
	assert_eq((dialog.find_child("DeleteConfirmStageId", true, false) as Label).text, "ステージID %s" % target)
	assert_true((dialog.find_child("DeleteCancelButton", true, false) as Button).has_focus(), "UI_UX §13: the safe side gets the initial focus")
	assert_eq(dialog.mouse_filter, Control.MOUSE_FILTER_STOP, "the dialog blocks clicks on the screen behind it")
	# キーボードの操作対象は、ダイアログの2つのボタンの間だけで動く。
	var cancel: Button = dialog.find_child("DeleteCancelButton", true, false)
	var confirm: Button = dialog.find_child("DeleteConfirmButton", true, false)
	assert_eq(cancel.get_node(cancel.focus_next), confirm)
	assert_eq(confirm.get_node(confirm.focus_next), cancel)
	cancel.pressed.emit()
	assert_false(dialog.visible)
	assert_true(RBMLocalStageRepository.exists(target), "cancel must not delete")
	(entry._saved_detail.find_child("DetailDeleteButton", true, false) as Button).pressed.emit()
	confirm.pressed.emit()
	assert_false(dialog.visible)
	assert_false(RBMLocalStageRepository.exists(target))
	assert_true(RBMLocalStageRepository.exists(keep), "deleting one boss must not touch the others")
	assert_eq(_rows(entry).size(), 1)
	assert_eq(entry._selected_stage_id, "")
	assert_not_null(entry._saved_detail.find_child("DetailHint", true, false), "after deleting, the detail asks to choose again")

func test_saved_list_screen_layout_matches_the_online_list() -> void:
	_save_mixed_library()
	var entry := await _new_entry()
	entry._on_edit_saved_pressed()
	await get_tree().process_frame
	var panel: Control = entry.find_child("SavedListPanel", true, false)
	assert_eq(panel.get_global_rect(), Rect2(RBMOnlineBossListView.LIST_RECT.position, RBMOnlineBossListView.LIST_RECT.size))
	assert_eq(entry._saved_detail.get_global_rect(), Rect2(RBMOnlineBossListView.DETAIL_RECT.position, RBMOnlineBossListView.DETAIL_RECT.size))
	var back: Button = entry.find_child("ListBackButton", true, false)
	assert_eq(back.position, Vector2(24, 20))
	assert_eq(back.text, "ボス戦を作成")
	for field in [entry._name_search_field, entry._id_search_field]:
		assert_true(Rect2(0, 0, 1280, 76).encloses(field.get_global_rect()), "search fields sit in the header row")
		assert_false(field.get_global_rect().intersects(back.get_global_rect()))
	assert_false(entry._name_search_field.get_global_rect().intersects(entry._id_search_field.get_global_rect()))
	for row in _rows(entry):
		var card := row as RBMSavedBossCard
		for label_variant in card.find_children("*", "Label", true, false):
			var label := label_variant as Label
			assert_true(Rect2(Vector2.ZERO, card.size).grow(0.5).encloses(Rect2(label.position, label.size)), "%s/%s must stay inside the card" % [card.name, label.name])

# ---------------------------------------------------------------------------
# 挑戦ハブ
# ---------------------------------------------------------------------------

func _new_hub() -> RBMChallengeHubView:
	var hub := RBMChallengeHubView.new()
	hub.size = Vector2(1280, 720)
	add_child_autofree(hub)
	await get_tree().process_frame
	return hub

func test_hub_layout_follows_the_approved_design() -> void:
	var hub := await _new_hub()
	assert_true(hub.has_meta("world_skip"))
	assert_true(hub.find_child("HubBackground", true, false) is RBMMenuUi.Backdrop)
	var simple: Button = hub.find_child("SimpleCategoryButton", true, false)
	var hardcore: Button = hub.find_child("HardcoreCategoryButton", true, false)
	assert_eq(simple.text, "SIMPLE")
	assert_eq(hardcore.text, "HARDCORE")
	assert_eq(simple.size, hardcore.size)
	assert_almost_eq(simple.position.y, hardcore.position.y, 0.5)
	var tiles := ["FeaturedCategoryButton", "NewCategoryButton", "UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton"]
	var previous: Button = null
	for key in tiles:
		var tile: Button = hub.find_child(key, true, false)
		assert_gt(tile.position.y, simple.get_rect().end.y, "%s sits below the mode cards" % key)
		if previous != null:
			assert_gt(tile.position.x, previous.get_rect().end.x, "tiles are in one row, left to right")
		previous = tile
	assert_lte(previous.get_rect().end.x, 1280.0 - 24.0)
	var search: Button = hub.find_child("SearchBossButton", true, false)
	var random: Button = hub.find_child("RandomChallengeButton", true, false)
	assert_gt(search.position.y, previous.get_rect().end.y)
	assert_gt(random.position.x, search.get_rect().end.x)
	for button_variant in hub.find_children("*", "Button", true, false):
		var button := button_variant as Button
		assert_true(Rect2(0, 0, 1280, 720).encloses(button.get_rect()), "%s must be within the screen" % button.name)
		for label_variant in button.find_children("*", "Label", true, false):
			var label := label_variant as Label
			assert_true(Rect2(Vector2.ZERO, button.size).grow(0.5).encloses(Rect2(label.position, label.size)), "%s/%s must stay inside its button" % [button.name, label.name])
			assert_lte(label.get_minimum_size().x, label.size.x + 0.5, "%s/%s text must not be clipped" % [button.name, label.name])

func test_hub_buttons_emit_their_categories() -> void:
	var hub := await _new_hub()
	var seen: Array[String] = []
	hub.category_selected.connect(func(category: String): seen.append(category))
	for key in ["SimpleCategoryButton", "HardcoreCategoryButton", "FeaturedCategoryButton", "NewCategoryButton", "UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton"]:
		(hub.find_child(key, true, false) as Button).pressed.emit()
	assert_eq(seen, [RBMChallengeHubView.CATEGORY_SIMPLE, RBMChallengeHubView.CATEGORY_HARDCORE, RBMChallengeHubView.CATEGORY_FEATURED, RBMChallengeHubView.CATEGORY_NEW, RBMChallengeHubView.CATEGORY_UNCHALLENGED, RBMChallengeHubView.CATEGORY_POPULAR, RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY])
	watch_signals(hub)
	(hub.find_child("SearchBossButton", true, false) as Button).pressed.emit()
	(hub.find_child("RandomChallengeButton", true, false) as Button).pressed.emit()
	(hub.find_child("BackToRootButton", true, false) as Button).pressed.emit()
	assert_signal_emitted(hub, "search_requested")
	assert_signal_emitted(hub, "random_requested")
	assert_signal_emitted(hub, "back_to_root_requested")

func test_hub_cards_highlight_their_open_hint_on_hover_and_focus() -> void:
	var hub := await _new_hub()
	var simple: Button = hub.find_child("SimpleCategoryButton", true, false)
	var open: Label = simple.find_child("OpenListLabel", true, false)
	assert_eq(open.get_theme_color("font_color"), RBMChallengeListStyle.SILVER)
	simple.mouse_entered.emit()
	assert_eq(open.get_theme_color("font_color"), RBMChallengeListStyle.TEXT)
	simple.mouse_exited.emit()
	assert_eq(open.get_theme_color("font_color"), RBMChallengeListStyle.SILVER)
	simple.grab_focus()
	assert_eq(open.get_theme_color("font_color"), RBMChallengeListStyle.TEXT)
	simple.release_focus()
	assert_eq(open.get_theme_color("font_color"), RBMChallengeListStyle.SILVER)
