extends GutTest

## RPG BOSS MAKER — Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）
## §24〜§27: 公開機能の専用テスト（ユーザー確定仕様の12項目）。
##
## 公開状態の正式仕様（ユーザー確定）:
## - 保存はいつでも可能（Clear Check/公開の有無に関わらない）
## - Clear Checkは公開の必須条件だが、達成しただけで自動公開はしない
## - 公開はClear Check達成済みの場合のみ可能。published=trueにし、
##   CHALLENGE側（RBMLocalStageRepository.list()経由）へ実際に露出させる
## - 公開後にClear Check無効化（内容変更）が起きたら、publishedも自動的に
##   falseへ戻る——ただしClear Check達成状態自体（has_ever_cleared()）は
##   公開取り下げだけでは失われない
## - published未保持の旧保存データはfalse扱い（安全側フォールバック）

const TEST_DIR := "user://bossmaker_test_publish_flow/stages"

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

func _playable_draft(boss_name: String = "公開テストボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

func _new_challenge_entry() -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	add_child_autofree(entry)
	return entry

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

# ---------------------------------------------------------------------------
# 1. Clear Check未達でも保存可能
# ---------------------------------------------------------------------------

func test_1_save_is_always_possible_even_without_clear_check() -> void:
	var draft := _playable_draft()
	assert_false(draft.is_clear_check_currently_valid(), "sanity: never cleared")
	var result := RBMLocalStageRepository.save_new(draft)
	assert_true(bool(result.get("ok", false)), "saving must never be gated on Clear Check")

func test_1_save_is_always_possible_even_with_zero_test_battles_run() -> void:
	# RBMCreatorTestSession/RBMCreatorTestBattleViewを一切経由せず、
	# 保存だけを直接叩く——TEST BATTLEの実施回数は保存条件に一切含まれない。
	var main := _new_creator()
	main.draft.boss_name = "テストバトル未実施ボス"
	main.draft.hp = 1000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	var result := main.press_save_as_new()
	assert_true(bool(result.get("ok", false)))

# ---------------------------------------------------------------------------
# 2. 保存しただけではCHALLENGEに表示されない
# ---------------------------------------------------------------------------

func test_2_saving_alone_does_not_expose_the_stage_to_challenge() -> void:
	var draft := _playable_draft("保存のみボス")
	RBMLocalStageRepository.save_new(draft)
	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0)

func test_2_a_saved_but_unpublished_stage_remains_editable_from_creator() -> void:
	var draft := _playable_draft("下書き継続ボス")
	var save_result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(save_result.get("stage_id", ""))
	var main := _new_creator()
	var load_result := main.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "an unpublished stage must remain re-openable from Creator")
	assert_eq(main.draft.boss_name, "下書き継続ボス")

# ---------------------------------------------------------------------------
# 3. Clear Check達成だけではCHALLENGEに表示されない
# ---------------------------------------------------------------------------

func test_3_achieving_clear_check_alone_does_not_auto_publish() -> void:
	var draft := _playable_draft("クリア済み未公開ボス")
	draft.record_clear_check_success()
	assert_true(draft.is_clear_check_currently_valid())
	assert_false(draft.is_published(), "record_clear_check_success() itself must never flip published")
	RBMLocalStageRepository.save_new(draft)
	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0)

# ---------------------------------------------------------------------------
# 4. Clear Check達成後に公開するとCHALLENGEに表示される
# ---------------------------------------------------------------------------

func test_4_publishing_after_clear_check_exposes_the_stage_to_challenge() -> void:
	var draft := _playable_draft("公開済みボス")
	draft.record_clear_check_success()
	assert_true(draft.publish())
	assert_true(draft.is_published())
	RBMLocalStageRepository.save_new(draft)
	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1)

## 実UI経由: 最終確認画面の[公開]ボタンを実際に押す。
func test_4_real_publish_button_press_exposes_the_stage_to_challenge() -> void:
	var main := _new_creator()
	main.draft.boss_name = "実UI公開ボス"
	main.draft.hp = 1000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	main.draft.record_clear_check_success()
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	var step5: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	step5.refresh()
	assert_false(step5._publish_button.disabled, "sanity: publish must be enabled once cleared")
	assert_eq(step5._publish_status_label.text, "未公開", "must show an explicit 未公開 status before publishing")
	_btn(step5, "PublishButton").pressed.emit()
	assert_true(main.draft.is_published())
	assert_false(main.current_stage_id.is_empty(), "publishing an unsaved-but-cleared draft must implicitly save it")
	step5.refresh()
	assert_eq(step5._publish_status_label.text, "公開中", "must show an explicit 公開中 status once published")

	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1)

# ---------------------------------------------------------------------------
# 5. 公開未達では公開ボタンが無効
# ---------------------------------------------------------------------------

func test_5_publish_returns_false_and_does_nothing_before_clear_check() -> void:
	var draft := _playable_draft()
	assert_false(draft.publish(), "publish() must fail before Clear Check is achieved")
	assert_false(draft.is_published())

func test_5_real_publish_button_is_disabled_before_clear_check() -> void:
	var main := _new_creator()
	main.draft.boss_name = "未達成ボス"
	main.draft.hp = 1000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	var step5: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	step5.refresh()
	assert_true(step5._publish_button.disabled, "the publish button must be disabled until Clear Check is achieved")
	_btn(step5, "PublishButton").pressed.emit()
	assert_false(main.draft.is_published(), "a disabled button must not be clickable in real UI, but even a direct emit must not publish")

# ---------------------------------------------------------------------------
# 6. 公開後にClear Check無効化変更をすると自動的に非公開になる
# ---------------------------------------------------------------------------

func test_6_editing_content_after_publish_invalidates_clear_check_and_auto_unpublishes() -> void:
	var main := _new_creator()
	main.draft.boss_name = "自動非公開ボス"
	main.draft.hp = 1000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	main.draft.record_clear_check_success()
	assert_true(main.draft.publish())
	assert_true(main.draft.is_published())

	# HPを変更する——battle_content_snapshot()に含まれるフィールドのため、
	# Clear Check成功時のsnapshotと一致しなくなりis_clear_check_currently_
	# valid()がfalseへ変わる（既存のClear Check無効化契約、無改修）。
	main.draft.hp = 9999
	assert_false(main.draft.is_clear_check_currently_valid(), "sanity: the edit must invalidate Clear Check via the existing snapshot comparison")

	# published自体はまだ手つかずのまま真——RBMCreatorMain._refresh()を
	# 経由して初めて是正される（都度再評価する設計、ユーザー確定仕様）。
	main._refresh()
	assert_false(main.draft.is_published(), "an edit that invalidates Clear Check must automatically revert published to false")

func test_6_draft_level_sync_helper_only_moves_published_one_way() -> void:
	var draft := _playable_draft()
	draft.record_clear_check_success()
	assert_true(draft.publish())
	draft.hp += 1
	draft.sync_published_with_clear_check()
	assert_false(draft.is_published())
	# A→B→Aで内容を元に戻しても（Clear Check自体は再び有効になるが）、
	# published自体は自動的には復活しない——ユーザー確定仕様
	# 「作者が『公開』を押すまでCHALLENGEには表示しない」。
	draft.hp -= 1
	assert_true(draft.is_clear_check_currently_valid(), "sanity: content restored exactly, Clear Check itself is valid again")
	draft.sync_published_with_clear_check()
	assert_false(draft.is_published(), "published must NOT automatically resurrect even if content is restored to the exact cleared state")

# ---------------------------------------------------------------------------
# 7. 再Clear Check後に再公開できる
# ---------------------------------------------------------------------------

func test_7_can_republish_after_reachieving_clear_check() -> void:
	var draft := _playable_draft()
	draft.record_clear_check_success()
	assert_true(draft.publish())
	draft.hp += 1
	draft.sync_published_with_clear_check()
	assert_false(draft.is_published())

	# 変更後の内容で改めてClear Check達成→再公開できること。
	draft.record_clear_check_success()
	assert_true(draft.publish(), "publishing again after a fresh Clear Check success must succeed")
	assert_true(draft.is_published())

# ---------------------------------------------------------------------------
# 8. 公開取り下げでCHALLENGEから消える
# ---------------------------------------------------------------------------

func test_8_unpublishing_removes_the_stage_from_challenge() -> void:
	var draft := _playable_draft("取り下げボス")
	draft.record_clear_check_success()
	draft.publish()
	var save_result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(save_result.get("stage_id", ""))
	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1, "sanity: published stage is visible")

	draft.unpublish()
	RBMLocalStageRepository.overwrite(stage_id, draft)
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "an explicitly unpublished stage must disappear from CHALLENGE")

## 実UI経由: 最終確認画面の[公開を取り下げる]ボタン。
func test_8_real_unpublish_button_removes_the_stage_from_challenge() -> void:
	var main := _new_creator()
	main.draft.boss_name = "実UI取り下げボス"
	main.draft.hp = 1000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_party_character("hero")
	main.draft.record_clear_check_success()
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	var step5: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	step5.refresh()
	_btn(step5, "PublishButton").pressed.emit()
	assert_true(main.draft.is_published(), "sanity")
	step5.refresh()
	assert_true(step5._unpublish_button.visible, "once published, the screen must show 公開中/[公開を取り下げる] instead of [公開]")
	assert_false(step5._publish_button.visible)
	assert_eq(step5._publish_status_label.text, "公開中")

	_btn(step5, "UnpublishButton").pressed.emit()
	assert_false(main.draft.is_published())
	step5.refresh()
	assert_true(step5._publish_button.visible, "after withdrawing, [公開] must be offered again")
	assert_false(step5._unpublish_button.visible)
	assert_eq(step5._publish_status_label.text, "未公開", "withdrawing must restore the explicit 未公開 status")

	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0)

# ---------------------------------------------------------------------------
# 9. 公開取り下げだけではClear Check達成状態を失わない
# ---------------------------------------------------------------------------

func test_9_unpublishing_alone_does_not_lose_clear_check_achievement() -> void:
	var draft := _playable_draft()
	draft.record_clear_check_success()
	draft.publish()
	assert_true(draft.has_ever_cleared())
	assert_true(draft.is_clear_check_currently_valid())

	draft.unpublish()
	assert_true(draft.has_ever_cleared(), "unpublish() must never touch the Clear Check success record")
	assert_true(draft.is_clear_check_currently_valid())
	assert_false(draft.is_published())

# ---------------------------------------------------------------------------
# 10. published未保持の旧保存データはfalse扱い
# ---------------------------------------------------------------------------

func test_10_saved_data_without_a_published_field_defaults_to_unpublished() -> void:
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict({"boss_name": "旧データボス"})
	assert_false(restored.is_published(), "a save payload predating the publish feature must default to unpublished, never auto-published")

func test_10_a_pre_publish_feature_stage_written_directly_to_disk_is_excluded_from_challenge() -> void:
	# published自体を一切知らない、旧バージョンのCreatorが書き出したのと
	# 同じ形の生JSON（"published"キー自体が存在しない）を直接書き込む。
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var stage_id := "9999999999"
	var payload := {
		"save_format_version": 2,
		"stage_id": stage_id,
		"created_unix_time": 0,
		"updated_unix_time": 0,
		"draft": {
			"boss_name": "旧バージョン保存ボス", "hp": 1000, "atk": 100, "spd": 50,
			"skills": [{"skill_id": "s1", "name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
			"party_character_ids": ["hero"],
		},
		"clear_check_success_snapshot": {},
	}
	var file := FileAccess.open("%s/%s.json" % [TEST_DIR, stage_id], FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()

	var entry := _new_challenge_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "pre-publish-feature saves must never be silently auto-exposed to CHALLENGE")

# ---------------------------------------------------------------------------
# 11. SIMPLE/HARDCORE双方で公開状態が正しく保存・読込される
# ---------------------------------------------------------------------------

func test_11_published_flag_round_trips_through_save_and_load_in_simple_mode() -> void:
	var draft := _playable_draft("SIMPLE公開ボス")
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	draft.record_clear_check_success()
	assert_true(draft.publish())
	var save_result := RBMLocalStageRepository.save_new(draft)
	var load_result := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	assert_true(bool(load_result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	assert_true(restored.is_published(), "SIMPLE mode: published=true must survive a real file round trip")

func test_11_published_flag_round_trips_through_save_and_load_in_advanced_mode() -> void:
	var draft := _playable_draft("HARDCORE公開ボス")
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	draft.record_clear_check_success()
	assert_true(draft.publish())
	var save_result := RBMLocalStageRepository.save_new(draft)
	var load_result := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
	assert_true(bool(load_result.get("ok", false)))
	var restored := RBMCreatorDraft.new()
	restored.restore_from_saved_dict(load_result.get("draft_data", {}))
	assert_true(restored.is_published(), "HARDCORE mode: published=true must survive a real file round trip")

func test_11_unpublished_flag_round_trips_as_false_in_both_modes() -> void:
	for mode in [RBMCreatorDraft.CREATOR_MODE_SIMPLE, RBMCreatorDraft.CREATOR_MODE_ADVANCED]:
		var draft := _playable_draft("未公開往復ボス")
		draft.set_creator_mode(mode)
		var save_result := RBMLocalStageRepository.save_new(draft)
		var load_result := RBMLocalStageRepository.load_stage(str(save_result.get("stage_id", "")))
		var restored := RBMCreatorDraft.new()
		restored.restore_from_saved_dict(load_result.get("draft_data", {}))
		assert_false(restored.is_published(), "mode=%s: an unpublished draft must round-trip as unpublished" % mode)

func test_11_published_field_with_wrong_type_is_rejected_by_the_repository() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var stage_id := "8888888888"
	var payload := {
		"save_format_version": 1, "stage_id": stage_id,
		"created_unix_time": 0, "updated_unix_time": 0,
		"draft": {"published": "not a bool"},
		"clear_check_success_snapshot": {},
	}
	var file := FileAccess.open("%s/%s.json" % [TEST_DIR, stage_id], FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var result := RBMLocalStageRepository.load_stage(stage_id)
	assert_false(bool(result.get("ok", false)), "a non-boolean published field must be rejected as malformed")
