extends GutTest
## Dragon-specific awakening and synchronization of presentation snapshots.
const Awakening = preload("res://src/bossmaker/visuals/rbm_dragon_awakening.gd")

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_dragon"
	draft.boss_name = "覚醒演出テスト"
	draft.hp = 400
	draft.atk = 10
	draft.spd = 10
	draft.add_party_character("hero")
	draft.set_awakening({
		"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
		"heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0},
	})
	return RBMCreatorTestSession.new(draft.to_definition(), 1)

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_dragon")
	stage.set_state(session.battle.presentation_state())
	return stage

func _awakening_entry(session: RBMCreatorTestSession) -> Dictionary:
	for entry in session.resolve_ally_action({"type": "attack"}):
		if str(entry.get("action", "")) == "awakening": return entry
	return {}

func test_awakening_entry_plays_and_emits_impact_and_finished_exactly_once() -> void:
	var session := _session()
	var stage := _stage(session)
	var entry := _awakening_entry(session)
	assert_false(entry.is_empty())
	var snapshot := session.battle.snapshot().duplicate(true)
	var impacts: Array = []
	var finishes: Array = []
	stage.impact.connect(func(e):
		impacts.append(e)
		stage.set_state(e.get("visual_state", session.battle.presentation_state()))
	)
	stage.finished.connect(func(): finishes.append(true))
	stage._sound.history.clear()
	stage.play_entry(entry)
	assert_eq(stage._sound.history,["dragon_awakening"])
	var driver = stage._skill_presentation
	assert_true(driver is Awakening)
	assert_eq(stage._phase, "awakening")
	assert_false(stage._awakening_transform.visible, "Dragon uses its dedicated effect")
	stage._tween.custom_step(Awakening.DARK_START - .01)
	assert_eq(stage._asset_ids["boss"], "dragon")
	assert_eq(impacts.size(), 0)
	stage._tween.custom_step(.02)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	stage._tween.custom_step(Awakening.DURATION)
	await get_tree().process_frame
	assert_eq(impacts.size(), 1)
	assert_eq(impacts[0], entry)
	assert_eq(finishes.size(), 1)
	assert_eq(stage._sound.history,["dragon_awakening"],"Approved soundtrack plays once")
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_false(is_instance_valid(driver))
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	assert_true(stage._dragon_aura.visible)
	assert_eq(session.battle.snapshot(), snapshot)

func test_cancel_mid_awakening_playback_cleans_up_and_restores_snapshot_form() -> void:
	for elapsed in [.2, 2.4, 3.35, 4.0]:
		var session := _session()
		var stage := _stage(session)
		var entry := _awakening_entry(session)
		var finishes: Array = []
		var impacts: Array = []
		stage.finished.connect(func(): finishes.append(true))
		stage.impact.connect(func(e): impacts.append(e))
		stage.play_entry(entry)
		var driver = stage._skill_presentation
		stage._tween.custom_step(elapsed)
		stage.cancel()
		for player in stage._sound._players: assert_false(player.playing)
		await get_tree().process_frame
		assert_false(stage.is_playing())
		assert_null(stage._skill_presentation)
		assert_false(is_instance_valid(driver))
		assert_eq(finishes.size(), 0)
		assert_eq(impacts.size(), 0)
		assert_true(stage._visuals["boss"].visible)
		assert_eq(stage._visuals["boss"].scale, Vector2.ONE)
		assert_eq(stage._asset_ids["boss"], "dragon")
		assert_false(stage._dragon_aura.visible)
		for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])

func test_awakening_entry_does_not_go_through_generic_windup_travel_chain() -> void:
	var session := _session()
	var stage := _stage(session)
	stage.play_entry(_awakening_entry(session))
	assert_true(stage._skill_presentation is Awakening)
	assert_eq(stage._profile, {})
	assert_eq(stage._targets, [])
	stage._tween.custom_step(Awakening.DURATION + .1)
	await get_tree().process_frame

func test_awakened_snapshot_persists_after_buff_expiry_and_rewinds_to_normal() -> void:
	var session := _session()
	var stage := _stage(session)
	var normal := session.battle.presentation_state().duplicate(true)
	_awakening_entry(session)
	var awakened := session.battle.presentation_state().duplicate(true)
	stage.set_state(awakened)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	assert_true(stage._dragon_aura.visible)
	awakened.boss.timed_effects.clear()
	stage.set_state(awakened)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	assert_true(stage._dragon_aura.visible)
	stage.set_state(normal)
	assert_eq(stage._asset_ids["boss"], "dragon")
	assert_false(stage._dragon_aura.visible)
	stage.set_state(awakened)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	stage.cancel()
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")

func test_loading_an_already_awakened_battle_applies_appearance_and_aura() -> void:
	var session := _session()
	_awakening_entry(session)
	var stage := _stage(session)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened")
	assert_true(stage._dragon_aura.visible)
	assert_eq(stage._visuals["boss"].scale, Vector2.ONE)

func test_snapshot_updates_during_awakening_wait_for_reveal_and_survive_cancel() -> void:
	var session := _session()
	var stage := _stage(session)
	var entry := _awakening_entry(session)
	stage.play_entry(entry)
	stage._tween.custom_step(.8)
	stage.set_state(session.battle.presentation_state())
	assert_eq(stage._asset_ids["boss"], "dragon", "Do not reveal early when the presenter provides a resolved snapshot")
	stage.cancel()
	assert_eq(stage._asset_ids["boss"], "dragon_awakened", "Cancellation restores the most recently supplied presentation state")
	assert_true(stage._dragon_aura.visible)

func test_dragon_awakened_assets_use_idempotent_suffix_and_complete_pose_frames() -> void:
	assert_eq(RBMVisualAssets.awakened_asset_id("dragon"), "dragon_awakened")
	assert_eq(RBMVisualAssets.awakened_asset_id("dragon_awakened"), "dragon_awakened")
	assert_true(RBMVisualAssets.has_awakened_design("dragon"))
	assert_true(RBMVisualAssets.has_awakened_design("dragon_awakened"))
	assert_true(RBMVisualAssets.has_pose_frames("dragon_awakened"))
	assert_eq(RBMVisualAssets.display_height("dragon_awakened"), RBMVisualAssets.display_height("dragon"))
