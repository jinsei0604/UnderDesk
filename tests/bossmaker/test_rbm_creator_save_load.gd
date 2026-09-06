extends GutTest

## RPG BOSS MAKER Phase 1 Step 6 — ローカル保存・再編集の統合テスト。
## RBMCreatorMain（保存/ロード/退出の統括）、RBMCreatorSaveView（保存UI）、
## RBMCreatorEntry（Creator入口・一覧・検索・削除）を実際のControlツリーとして
## インスタンス化し、公開メソッド/シグナル経由で駆動する（このプロジェクト
## 既存の"実UIを本物のまま動かす"規約、test_rbm_creator_flow.gd等と同じ）。
##
## 実プレイヤーのuser://保存ライブラリを一切汚さないよう、専用のテスト用
## ディレクトリへ差し替えて実行する。

const TEST_DIR := "user://bossmaker_test_save_load/stages"

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

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _new_entry() -> RBMCreatorEntry:
	var entry := RBMCreatorEntry.new()
	add_child_autofree(entry)
	return entry

func _fill_minimum_valid_boss(creator: RBMCreatorMain, boss_name: String = "テストボス") -> void:
	creator.draft.boss_name = boss_name
	creator.draft.hp = 1000
	creator.draft.atk = 100
	creator.draft.spd = 50
	creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.add_party_character("hero")

func _win_clear_check(creator: RBMCreatorMain) -> void:
	var atk_id := str(creator.draft.skills[0]["skill_id"])
	creator.draft.normal_actions_enabled = true
	creator.draft.normal_action_percentages[atk_id] = 100.0
	var start := RBMDefinitionLoader.start_battle(creator.draft.to_definition(), 1)
	var battle: RBMBattle = start["battle"]
	while not battle.battle_over:
		battle.resolve_turn({"0": {"type": "attack"}})
	assert_eq(battle.winner, "ally", "sanity: fixture must actually win")
	creator.draft.record_clear_check_success()

# ---------------------------------------------------------------------------
# §14/§19/§37/§52 — 未保存変更判定
# ---------------------------------------------------------------------------

func test_new_creator_has_no_unsaved_changes_initially() -> void:
	var creator := _new_creator()
	assert_false(creator.has_unsaved_changes())

func test_editing_boss_name_creates_unsaved_changes() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "変更後"
	assert_true(creator.has_unsaved_changes())

func test_editing_appearance_creates_unsaved_changes() -> void:
	var creator := _new_creator()
	creator.draft.appearance_id = "appearance_dragon"
	assert_true(creator.has_unsaved_changes())

func test_reverting_to_initial_state_a_to_b_to_a_clears_unsaved_changes() -> void:
	var creator := _new_creator()
	creator.draft.hp = 9999
	assert_true(creator.has_unsaved_changes())
	creator.draft.hp = 1
	assert_false(creator.has_unsaved_changes(), "restoring the exact initial value must clear the unsaved flag, not just leave it stuck true")

## §16/§52: 内容自体は何も変更していなくても、Clear Check成功だけで未保存
## 変更ありと判定される（確定仕様）。
func test_clear_check_success_alone_creates_unsaved_changes() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	# ここまでの変更をいったん保存済み扱いにする(初期状態としてではなく、
	# 「保存直後」の状態を作るためpress_save_as_newを使う)。
	var save_result := creator.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)))
	assert_false(creator.has_unsaved_changes(), "sanity: right after saving, no unsaved changes")

	_win_clear_check(creator)
	assert_true(creator.has_unsaved_changes(), "Clear Check success alone (no other content edit) must count as an unsaved change")

# ---------------------------------------------------------------------------
# §23/§30/§52 — 新規保存
# ---------------------------------------------------------------------------

func test_press_save_as_new_from_a_brand_new_draft_issues_a_stage_id_and_clears_unsaved_changes() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	assert_true(creator.current_stage_id.is_empty())
	var result := creator.press_save_as_new()
	assert_true(bool(result.get("ok", false)))
	var stage_id: String = str(result.get("stage_id", ""))
	assert_eq(stage_id.length(), 10)
	assert_eq(creator.current_stage_id, stage_id, "§23: after a successful initial save, current_stage_id must switch to the new id")
	assert_false(creator.has_unsaved_changes())

# ---------------------------------------------------------------------------
# §24/§52/§54 — 上書き保存
# ---------------------------------------------------------------------------

func test_press_overwrite_save_without_a_current_stage_fails() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var result := creator.press_overwrite_save()
	assert_false(bool(result.get("ok", false)), "overwrite must fail cleanly when no stage has ever been saved yet")

func test_press_overwrite_save_updates_the_same_stage_and_clears_unsaved_changes() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	var saved := creator.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	creator.draft.hp = 5000
	assert_true(creator.has_unsaved_changes())
	var result := creator.press_overwrite_save()
	assert_true(bool(result.get("ok", false)))
	assert_eq(creator.current_stage_id, stage_id, "overwrite must never change current_stage_id")
	assert_false(creator.has_unsaved_changes())

	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.hp, 5000)
	assert_eq(RBMLocalStageRepository.list().size(), 1, "overwrite must not create a second file")

# ---------------------------------------------------------------------------
# §25/§55 — 新しいボスとして保存 (Save As型、確定仕様)
# ---------------------------------------------------------------------------

func test_save_as_new_from_an_existing_stage_creates_a_second_file_and_switches_current_stage_id() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "元祖ボス")
	var first := creator.press_save_as_new()
	var first_id: String = str(first.get("stage_id", ""))
	var first_text_before := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, first_id])

	creator.draft.boss_name = "分岐ボス"
	var second := creator.press_save_as_new()
	var second_id: String = str(second.get("stage_id", ""))

	assert_ne(second_id, first_id, "§25: a brand-new stage_id must be issued")
	assert_eq(creator.current_stage_id, second_id, "§25: current_stage_id must switch to the new stage (Save As型、確定仕様)")

	var first_text_after := FileAccess.get_file_as_string("%s/%s.json" % [TEST_DIR, first_id])
	assert_eq(first_text_before, first_text_after, "§25: the original stage must remain completely unchanged")

	# §25: 以後の上書き保存は新stageを更新する。
	creator.draft.hp = 7777
	creator.press_overwrite_save()
	var reloaded_second := RBMLocalStageRepository.load_stage(second_id)
	var restored_second := RBMCreatorDraft.new()
	restored_second.restore_from_saved_dict(reloaded_second.get("draft_data", {}))
	assert_eq(restored_second.hp, 7777)
	var reloaded_first := RBMLocalStageRepository.load_stage(first_id)
	var restored_first := RBMCreatorDraft.new()
	restored_first.restore_from_saved_dict(reloaded_first.get("draft_data", {}))
	assert_ne(restored_first.hp, 7777, "the subsequent overwrite must never touch the original stage")

## §25末尾: stage_id変更だけではClear Check証明を無効化しない——現在Draftに
## 有効な証明があれば、新しいボスとして保存してもそのまま引き継がれる。
func test_save_as_new_inherits_a_currently_valid_clear_check_proof() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.press_save_as_new()
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid(), "sanity")

	var result := creator.press_save_as_new()
	var new_id: String = str(result.get("stage_id", ""))
	var loaded := RBMLocalStageRepository.load_stage(new_id)
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	restored.restore_clear_check_snapshot(loaded.get("clear_check_data", {}))
	assert_true(restored.is_clear_check_currently_valid(), "the new stage must inherit the still-valid Clear Check proof")

# ---------------------------------------------------------------------------
# §26/§56 — 同名警告
# ---------------------------------------------------------------------------

func test_boss_name_already_saved_elsewhere_reports_a_real_collision() -> void:
	var first := _new_creator()
	_fill_minimum_valid_boss(first, "重複候補")
	first.press_save_as_new()

	var second := _new_creator()
	_fill_minimum_valid_boss(second, "重複候補")
	assert_true(second.boss_name_already_saved_elsewhere())

	second.draft.boss_name = "被らない名前"
	assert_false(second.boss_name_already_saved_elsewhere())

# ---------------------------------------------------------------------------
# §31/§34/§43/§52 — ロード
# ---------------------------------------------------------------------------

func test_start_loaded_has_no_unsaved_changes_right_after_loading() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "ロード対象")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var reader := _new_creator()
	reader.draft.boss_name = "編集前の下書き内容"  # will be overwritten by start_loaded
	var result := reader.start_loaded(stage_id)
	assert_true(bool(result.get("ok", false)))
	assert_eq(reader.draft.boss_name, "ロード対象")
	assert_eq(reader.current_stage_id, stage_id)
	assert_false(reader.has_unsaved_changes(), "§34末尾: right after loading, there must be no unsaved changes")

## §35: ロード後にCreator設定を変更しても、保存操作をするまでディスク上の
## 元stageは一切変更されない。
func test_editing_after_load_does_not_touch_the_saved_file_until_an_explicit_save() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "編集前保護テスト")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))
	var path := "%s/%s.json" % [TEST_DIR, stage_id]
	var text_before := FileAccess.get_file_as_string(path)

	var reader := _new_creator()
	reader.start_loaded(stage_id)
	reader.draft.hp = 424242
	reader.draft.boss_name = "編集中（未保存）"

	var text_after_edit := FileAccess.get_file_as_string(path)
	assert_eq(text_before, text_after_edit, "in-memory edits after loading must never write to disk on their own")

	reader.press_overwrite_save()
	var text_after_save := FileAccess.get_file_as_string(path)
	assert_ne(text_before, text_after_save, "sanity: an explicit save DOES change the file")

## §51: ロード後、ボス名のみ/外見のみ/パーティ並び順のみの変更はClear Check
## 有効性を維持し、skill_idが変わる変更（削除→再作成）は無効化する——保存/
## ロードという往復を経てもStep 5の既存比較ロジック(無改修)がそのまま正しく
## 機能することを、Repositoryを通した実際のファイル往復で直接確認する。
func test_clear_check_validity_after_save_load_round_trip_matches_step5_rules() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "ロード後比較テスト")
	creator.draft.appearance_id = "appearance_dragon"
	creator.draft.add_party_character("tank")
	_win_clear_check(creator)
	var saved := creator.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var reader := _new_creator()
	reader.start_loaded(stage_id)
	assert_true(reader.draft.is_clear_check_currently_valid(), "sanity: valid right after load")

	# ボス名のみ変更 -> 維持
	reader.draft.boss_name = "名前だけ変更"
	assert_true(reader.draft.is_clear_check_currently_valid(), "boss_name-only change must keep Clear Check valid after a save/load round trip")

	# 外見のみ変更 -> 維持
	reader.draft.appearance_id = "appearance_slime"
	assert_true(reader.draft.is_clear_check_currently_valid(), "appearance-only change must keep Clear Check valid after a save/load round trip")

	# パーティ並び替え -> 同速時の行動順へ影響するため失効
	reader.draft.party_character_ids = ["tank", "hero"]
	assert_false(reader.draft.is_clear_check_currently_valid(), "party order must invalidate Clear Check because it is the equal-SPD tie-break")
	reader.draft.party_character_ids = ["hero", "tank"]
	assert_true(reader.draft.is_clear_check_currently_valid(), "restoring the cleared party order restores validity")

	# skill_idが変わる変更（削除して同内容で再作成） -> 無効化
	var original_skill := reader.draft.skills[0].duplicate(true)
	var original_skill_id := str(original_skill["skill_id"])
	reader.draft.remove_skill(original_skill_id)
	original_skill.erase("skill_id")
	var recreated_id := reader.draft.add_skill(original_skill)
	assert_ne(recreated_id, original_skill_id)
	assert_false(reader.draft.is_clear_check_currently_valid(), "a skill_id change (delete+recreate, even with identical values) must invalidate Clear Check even after a save/load round trip")

func test_start_loaded_with_a_missing_id_returns_ok_false_and_does_not_touch_the_draft() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "維持されるはず"
	var result := creator.start_loaded("0000000000")
	assert_false(bool(result.get("ok", false)))
	assert_eq(creator.draft.boss_name, "維持されるはず", "a failed load must not clobber the current draft")

func test_start_new_resets_current_stage_id_and_unsaved_state() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "何か")
	creator.press_save_as_new()
	creator.draft.hp = 42
	assert_true(creator.has_unsaved_changes())

	creator.start_new()
	assert_true(creator.current_stage_id.is_empty())
	assert_eq(creator.draft.boss_name, "")
	assert_false(creator.has_unsaved_changes())

# ---------------------------------------------------------------------------
# §36/§37 — Creator退出
# ---------------------------------------------------------------------------

func test_press_exit_creator_emits_exited_immediately_when_no_unsaved_changes() -> void:
	var creator := _new_creator()
	watch_signals(creator)
	creator.press_exit_creator()
	assert_signal_emitted(creator, "exited")
	assert_false(creator._exit_confirm_panel.visible)

func test_press_exit_creator_shows_confirmation_when_unsaved_changes_exist() -> void:
	var creator := _new_creator()
	watch_signals(creator)
	creator.draft.boss_name = "未保存"
	creator.press_exit_creator()
	assert_signal_not_emitted(creator, "exited")
	assert_true(creator._exit_confirm_panel.visible)

func test_exit_confirm_discard_emits_exited_and_hides_confirm_panel() -> void:
	var creator := _new_creator()
	watch_signals(creator)
	creator.draft.boss_name = "捨てる変更"
	creator.press_exit_creator()
	creator._on_exit_confirm_discard_pressed()
	assert_signal_emitted(creator, "exited")
	assert_false(creator._exit_confirm_panel.visible)

func test_exit_confirm_cancel_stays_in_creator() -> void:
	var creator := _new_creator()
	watch_signals(creator)
	creator.draft.boss_name = "取り消す"
	creator.press_exit_creator()
	creator._on_exit_confirm_cancel_pressed()
	assert_signal_not_emitted(creator, "exited")
	assert_false(creator._exit_confirm_panel.visible)
	assert_eq(creator.draft.boss_name, "取り消す", "cancel must not discard the edit")

## §36「保存する」: 通常の保存画面へ進むだけで、自動的に上書き/退出しない。
func test_exit_confirm_save_opens_the_normal_save_flow() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "保存してから終了")
	watch_signals(creator)
	creator.press_exit_creator()
	creator._on_exit_confirm_save_pressed()
	assert_false(creator._exit_confirm_panel.visible)
	assert_true(creator._save_view.visible, "must route into the normal save view, matching STEP7's own 保存 button")
	assert_signal_not_emitted(creator, "exited", "pressing 保存する must not itself exit Creator")

# ---------------------------------------------------------------------------
# §38/§39/§40 — RBMCreatorSaveView UI
# ---------------------------------------------------------------------------

func test_save_view_shows_only_the_new_save_button_for_a_brand_new_stage() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.press_save()
	assert_true(creator._save_view._save_new_button.visible)
	assert_false(creator._save_view._overwrite_button.visible)
	assert_false(creator._save_view._save_as_new_button.visible)

func test_save_view_shows_overwrite_and_save_as_for_an_existing_stage() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.press_save_as_new()
	creator.press_save()
	assert_false(creator._save_view._save_new_button.visible)
	assert_true(creator._save_view._overwrite_button.visible)
	assert_true(creator._save_view._save_as_new_button.visible)

func test_save_view_new_save_shows_success_screen_with_stage_id() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.press_save()
	creator._save_view._on_save_new_pressed()
	assert_true(creator._save_view._success_panel.visible)
	assert_eq(creator._save_view._success_stage_id_label.text, "ステージID：%s" % creator.current_stage_id)

func test_save_view_same_name_warning_blocks_until_confirmed() -> void:
	var first := _new_creator()
	_fill_minimum_valid_boss(first, "衝突名")
	first.press_save_as_new()

	var second := _new_creator()
	_fill_minimum_valid_boss(second, "衝突名")
	second.press_save()
	second._save_view._on_save_new_pressed()
	assert_true(second._save_view._same_name_panel.visible, "must warn before actually saving a colliding name")
	assert_true(second.current_stage_id.is_empty(), "must not have saved yet")

	second._save_view._on_same_name_confirmed()
	assert_false(second.current_stage_id.is_empty(), "confirming proceeds with the save")
	assert_eq(RBMLocalStageRepository.list().size(), 2)

## 確定仕様の必須シナリオそのもの: "Dragon"保存済み -> 新規stage名"dragon" ->
## 同名警告あり -> それでも保存続行可能 -> 新しいstage_idで別stageとして
## 保存される。大文字小文字違いでも同名警告が発火することをUIレベルで確認。
func test_save_view_same_name_warning_fires_for_a_case_only_difference() -> void:
	var first := _new_creator()
	_fill_minimum_valid_boss(first, "Dragon")
	var first_result := first.press_save_as_new()
	var first_id: String = str(first_result.get("stage_id", ""))

	var second := _new_creator()
	_fill_minimum_valid_boss(second, "dragon")
	second.press_save()
	second._save_view._on_save_new_pressed()
	assert_true(second._save_view._same_name_panel.visible, "a case-only difference ('Dragon' vs 'dragon') must still trigger the same-name warning")
	assert_true(second.current_stage_id.is_empty(), "must not have saved yet")

	second._save_view._on_same_name_confirmed()
	assert_false(second.current_stage_id.is_empty(), "confirming proceeds with the save despite the warning")
	assert_ne(second.current_stage_id, first_id, "must be issued a NEW, different stage_id")
	assert_eq(RBMLocalStageRepository.list().size(), 2, "both stages must now exist separately")

func test_save_view_same_name_warning_cancel_does_not_save() -> void:
	var first := _new_creator()
	_fill_minimum_valid_boss(first, "衝突名2")
	first.press_save_as_new()

	var second := _new_creator()
	_fill_minimum_valid_boss(second, "衝突名2")
	second.press_save()
	second._save_view._on_save_new_pressed()
	second._save_view._on_same_name_cancelled()
	assert_true(second.current_stage_id.is_empty(), "cancel must leave the stage unsaved")
	assert_eq(RBMLocalStageRepository.list().size(), 1, "only the first stage exists")

## §26末尾: 上書き保存は自分自身と同名なのが当然のため、同名警告を経由しない。
func test_save_view_overwrite_never_triggers_same_name_warning() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator, "自分自身")
	creator.press_save_as_new()
	creator.draft.hp = 2222
	creator.press_save()
	creator._save_view._on_overwrite_pressed()
	assert_false(creator._save_view._same_name_panel.visible)
	assert_true(creator._save_view._success_panel.visible)

func test_save_view_back_button_returns_without_saving() -> void:
	var creator := _new_creator()
	_fill_minimum_valid_boss(creator)
	creator.press_save()
	creator._save_view._on_back_pressed()
	assert_true(creator._steps_root.visible)
	assert_true(creator.current_stage_id.is_empty(), "戻る must not have saved anything")
	assert_eq(RBMLocalStageRepository.list().size(), 0)

# ---------------------------------------------------------------------------
# §29〜§33/§41 — RBMCreatorEntry
# ---------------------------------------------------------------------------

func test_entry_starts_on_the_top_panel() -> void:
	var entry := _new_entry()
	assert_true(entry._top_panel.visible)
	assert_false(entry._list_panel.visible)
	assert_false(entry.main.visible)

## UI改善②: 「新しいボス戦を作る」は今やCreatorへ直接入らず、まず作成方法
## 選択パネルを経由する——ここではモードの区別自体は本題ではないため、
## シンプルを選んで先へ進む。
func test_entry_new_boss_button_shows_a_blank_creator() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	assert_true(entry._mode_choice_panel.visible, "「新しいボス戦を作る」の直後はまず作成方法選択パネルを見せる")
	assert_false(entry.main.visible)
	entry._on_choose_simple_mode_pressed()
	assert_true(entry.main.visible)
	assert_eq(entry.main.draft.boss_name, "")
	assert_true(entry.main.current_stage_id.is_empty())

func test_entry_list_includes_drafts_playable_and_clear_checked_stages() -> void:
	var draft_only := RBMCreatorDraft.new()
	draft_only.boss_name = "下書き専用"
	RBMLocalStageRepository.save_new(draft_only)

	var playable := RBMCreatorDraft.new()
	playable.boss_name = "挑戦可能専用"
	playable.hp = 100
	playable.atk = 10
	playable.spd = 5
	playable.add_skill({"name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	playable.add_party_character("hero")
	RBMLocalStageRepository.save_new(playable)

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	assert_true(entry._list_panel.visible)
	assert_eq(entry._list_rows.get_child_count(), 2, "§31: drafts must be included in the Creator edit list")

## §33: ボス名は大文字小文字を区別しない部分一致。
## queue_free()されたノードはそのフレーム内はまだ子として残るため
## (Godotの既知の挙動)、2回目以降のリフレッシュ後にget_child_count()を見る
## 前は必ず1フレーム待つ——このawaitはテスト側の検証タイミングの都合であり、
## _refresh_list()自体は既存のRBMCreatorClearCheckView._refresh_rewind_list()
## 等と同じqueue_free()パターンのまま(production側は変更していない)。
func test_entry_list_search_by_name_is_case_insensitive_partial_match() -> void:
	var a := _new_creator()
	_fill_minimum_valid_boss(a, "Fire Dragon")
	a.press_save_as_new()
	var b := _new_creator()
	_fill_minimum_valid_boss(b, "Ice Golem")
	b.press_save_as_new()

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._name_search_field.text = "dragon"
	entry._refresh_list()
	await get_tree().process_frame
	assert_eq(entry._list_rows.get_child_count(), 1)

## §33: stage_idは10桁完全一致。
func test_entry_list_search_by_stage_id_is_exact_match() -> void:
	var a := _new_creator()
	_fill_minimum_valid_boss(a, "検索対象A")
	var result_a := a.press_save_as_new()
	var id_a: String = str(result_a.get("stage_id", ""))
	var b := _new_creator()
	_fill_minimum_valid_boss(b, "検索対象B")
	b.press_save_as_new()

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._id_search_field.text = id_a
	entry._refresh_list()
	await get_tree().process_frame
	assert_eq(entry._list_rows.get_child_count(), 1)

	entry._id_search_field.text = "0000000000"  # well-formed but non-existent id must find nothing
	entry._refresh_list()
	await get_tree().process_frame
	assert_eq(entry._list_rows.get_child_count(), 0, "a well-formed but unsaved stage_id must match nothing")

	entry._id_search_field.text = id_a.substr(0, 5)  # partial id must NOT match
	entry._refresh_list()
	await get_tree().process_frame
	assert_eq(entry._list_rows.get_child_count(), 0, "stage_id search must be exact, not partial")

func test_entry_opening_a_stage_from_the_list_loads_it_into_the_creator() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "開く対象")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_open_stage_pressed(stage_id)
	assert_true(entry.main.visible)
	assert_eq(entry.main.draft.boss_name, "開く対象")
	assert_eq(entry.main.current_stage_id, stage_id)

## §43: 壊れた/存在しないstageを開こうとしてもクラッシュせず一覧に留まる。
func test_entry_opening_a_missing_stage_stays_on_the_list_screen() -> void:
	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_open_stage_pressed("0000000000")
	assert_true(entry._list_panel.visible, "must remain on the list screen, not crash or switch to a broken Creator view")
	assert_false(entry.main.visible)

func test_entry_exiting_the_creator_returns_to_the_top_panel() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	assert_true(entry.main.visible)
	entry.main.exited.emit()
	assert_true(entry._top_panel.visible)
	assert_false(entry.main.visible)

# ---------------------------------------------------------------------------
# §41/§60 — RBMCreatorEntryからの削除
# ---------------------------------------------------------------------------

func test_entry_delete_shows_confirmation_before_removing() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "削除対象")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_delete_stage_pressed(stage_id, "削除対象")
	assert_true(entry._delete_confirm_panel.visible)
	assert_true(RBMLocalStageRepository.exists(stage_id), "must not delete until confirmed")

func test_entry_delete_confirmed_removes_the_stage_and_refreshes_the_list() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "削除対象2")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_delete_stage_pressed(stage_id, "削除対象2")
	entry._on_delete_confirmed()
	await get_tree().process_frame  # queue_free()されたrowが実際に取り除かれるのを待つ
	assert_false(RBMLocalStageRepository.exists(stage_id))
	assert_false(entry._delete_confirm_panel.visible)
	assert_eq(entry._list_rows.get_child_count(), 0)

func test_entry_delete_cancelled_keeps_the_stage() -> void:
	var author := _new_creator()
	_fill_minimum_valid_boss(author, "削除対象3")
	var saved := author.press_save_as_new()
	var stage_id: String = str(saved.get("stage_id", ""))

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_delete_stage_pressed(stage_id, "削除対象3")
	entry._on_delete_cancelled()
	assert_false(entry._delete_confirm_panel.visible)
	assert_true(RBMLocalStageRepository.exists(stage_id))

func test_entry_deleting_one_stage_does_not_affect_others() -> void:
	var a := _new_creator()
	_fill_minimum_valid_boss(a, "残す方")
	var saved_a := a.press_save_as_new()
	var id_a: String = str(saved_a.get("stage_id", ""))
	var b := _new_creator()
	_fill_minimum_valid_boss(b, "消す方")
	var saved_b := b.press_save_as_new()
	var id_b: String = str(saved_b.get("stage_id", ""))

	var entry := _new_entry()
	entry._on_edit_saved_pressed()
	entry._on_delete_stage_pressed(id_b, "消す方")
	entry._on_delete_confirmed()
	assert_true(RBMLocalStageRepository.exists(id_a))
	assert_false(RBMLocalStageRepository.exists(id_b))

# ---------------------------------------------------------------------------
# §64 — end-to-end round trip: 新規作成 -> 保存 -> 退出 -> 一覧から再編集 -> 上書き
# ---------------------------------------------------------------------------

func test_full_create_save_exit_reopen_edit_overwrite_round_trip() -> void:
	var entry := _new_entry()
	entry._on_new_pressed()
	entry._on_choose_simple_mode_pressed()
	_fill_minimum_valid_boss(entry.main, "往復テスト")
	entry.main.press_save()
	entry.main._save_view._on_save_new_pressed()
	var stage_id: String = entry.main.current_stage_id
	entry.main._save_view._on_success_return_pressed()

	entry.main.press_exit_creator()
	assert_true(entry._top_panel.visible)

	entry._on_edit_saved_pressed()
	entry._on_open_stage_pressed(stage_id)
	assert_eq(entry.main.draft.boss_name, "往復テスト")
	assert_false(entry.main.has_unsaved_changes())

	entry.main.draft.hp = 8888
	entry.main.press_save()
	entry.main._save_view._on_overwrite_pressed()
	assert_eq(entry.main.current_stage_id, stage_id, "overwrite must keep the same stage_id through the whole round trip")

	var loaded := RBMLocalStageRepository.load_stage(stage_id)
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(loaded.get("draft_data", {}))
	assert_eq(restored.hp, 8888)
	assert_eq(RBMLocalStageRepository.list().size(), 1)
