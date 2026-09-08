extends GutTest

func _main() -> RBMCreatorMain:
	var main := RBMCreatorMain.new()
	main.size = Vector2(1280,720)
	add_child_autofree(main)
	await get_tree().process_frame
	await get_tree().process_frame
	return main

func test_background_round_trip_and_old_save_default() -> void:
	var draft := RBMCreatorDraft.new()
	draft.battle_background = "day"
	var saved := draft.to_saved_dict()
	var loaded := RBMCreatorDraft.new()
	loaded.restore_from_saved_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(loaded.battle_background,"day")
	saved.erase("battle_background")
	loaded.restore_from_saved_dict(saved)
	assert_eq(loaded.battle_background,"night")
	saved["battle_background"] = "invalid"
	loaded.restore_from_saved_dict(saved)
	assert_eq(loaded.battle_background,"night")

func test_background_is_authoring_metadata_not_combat_content() -> void:
	var draft := RBMCreatorDraft.new()
	var combat := draft.battle_content_snapshot()
	var definition := draft.to_definition()
	var authoring := draft.full_authoring_snapshot()
	draft.battle_background = "day"
	assert_eq(draft.battle_content_snapshot(),combat)
	assert_eq(draft.to_definition(),definition)
	assert_ne(draft.full_authoring_snapshot(),authoring)

func test_summary_buttons_follow_draft_and_reopening() -> void:
	var main := await _main()
	main.go_to_step(5)
	await get_tree().process_frame
	var day: Button = main.find_child("DayBackgroundButton",true,false)
	var night: Button = main.find_child("NightBackgroundButton",true,false)
	day.pressed.emit()
	assert_eq(main.draft.battle_background,"day")
	assert_true(day.button_pressed)
	assert_false(night.button_pressed)
	main.go_to_step(2)
	main.go_to_step(5)
	# Reopening Step 5 rebuilds RBMWorldUi's WorldSummaryColumns wrapper, which
	# queue_free()s the previous one -- give the engine a frame to actually process
	# that deferred free before the test ends (real gameplay always gets one; a
	# fully synchronous test does not unless it awaits here), otherwise GUT's
	# orphan-node count flags it even though nothing is actually leaking.
	await get_tree().process_frame
	assert_true(day.button_pressed)
	night.pressed.emit()
	assert_eq(main.draft.battle_background,"night")
	assert_true(night.button_pressed)
	assert_false(day.button_pressed)

func test_stat_typing_commits_without_enter_and_attributes_remain_exclusive() -> void:
	var main := await _main()
	main.go_to_step(2)
	var stats = main._step_views[1]
	stats._hp_spin.get_line_edit().text = "3800"
	stats._hp_spin.get_line_edit().text_changed.emit("3800")
	await get_tree().process_frame
	assert_eq(main.draft.hp,3800)
	assert_eq(stats._hp_slider.value,3800.0)
	stats._weak_buttons.FIRE.pressed.emit()
	stats._resist_buttons.FIRE.pressed.emit()
	assert_false(main.draft.weak_attributes.has("FIRE"))
	assert_true(main.draft.resist_attributes.has("FIRE"))
	assert_false(stats._weak_buttons.FIRE.button_pressed)
	assert_true(stats._resist_buttons.FIRE.button_pressed)
	assert_null(stats.find_child("ConfirmStatsButton",true,false))

func test_battle_roots_fill_creator_without_editor_margins() -> void:
	var main := await _main()
	for battle in [main._test_battle_view,main._clear_check_view]:
		assert_eq(battle.get_parent(),main)
		assert_eq(battle.get_rect(),Rect2(0,0,1280,720))
		assert_not_null(battle._world_battle.canvas)
		assert_eq(battle._world_battle.stage.get_rect(),Rect2(0,0,1280,720))

func test_no_rewind_controls_are_added_to_challenge() -> void:
	var battle := RBMChallengeBattleView.new()
	battle.size = Vector2(1280,720)
	add_child_autofree(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(battle.find_children("*Rewind*","",true,false).size(),0)
	assert_not_null(battle._world_battle.canvas)
