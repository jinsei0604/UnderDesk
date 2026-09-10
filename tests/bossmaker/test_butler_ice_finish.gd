extends GutTest

## src/bossmaker/visuals/rbm_battle_stage.gd's butler_grand_ice finish wiring,
## mirroring test_hero_fire_finish.gd's guarantees for hero_burst_slash:
## the presenter stays on this single entry until every finish layer has
## ended, the boss's own next action never plays early, cancel-at-any-phase
## leaves no residue, and rewind/replay at double speed reproduces the same
## damage/RNG log. Scoped to butler_grand_ice only -- none of butler's other
## three skills (butler_ice_bolt/butler_ice_storm/butler_sp_gift) trigger it.

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "氷フィニッシュ回帰"
	draft.hp = 99999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("butler")
	var skill_id := draft.add_skill({"name": "攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return RBMCreatorTestSession.new(draft.to_definition(), 31)

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var result := RBMBattleStage.new()
	result.size = Vector2(1280, 720)
	result.set_meta("fullscreen_formation", true)
	add_child_autofree(result)
	result.configure(session.battle, "appearance_golem")
	result.set_state(session.battle.presentation_state())
	return result

func test_finish_blocks_next_entry_and_emits_each_impact_once() -> void:
	var session := _session()
	var before := session.battle.presentation_state()
	var stage := _stage(session)
	var log := session.resolve_ally_action({"type": "skill", "skill_id": "butler_grand_ice"})
	assert_eq(log.size(), 2)
	var final_snapshot := session.battle.snapshot()
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array = []
	presenter.entry_impact.connect(func(entry): seen.append(entry))
	presenter.play(log, session.battle, before)
	# butler_grand_ice's windup(0.48)+travel(0.34) = 0.82s, longer than
	# hero_burst_slash's 0.64s, and the finish itself runs 2.4s (vs fire's
	# 2.1s) -- step points are sized for THIS skill's own timing, not copied
	# from the hero test.
	stage._tween.custom_step(.85)
	assert_eq(seen.size(), 1)
	assert_eq(stage._motion_offset, Vector2.ZERO, "Butler casts from home")
	assert_eq(stage._visuals["0"].position, stage._homes["0"])
	stage._tween.custom_step(1.0)
	assert_eq(seen.size(), 1, "Boss cannot attack during the finish")
	assert_true(stage.is_playing())
	assert_eq(presenter.display_state(), log[0]["visual_state"], "No future boss damage in HUD")
	stage._tween.custom_step(1.5)
	await get_tree().process_frame
	assert_false(stage._butler_ice.visible)
	assert_false(stage._butler_finish)
	assert_eq(stage._butler_shake, Vector2.ZERO)
	stage._tween.custom_step(2.0)
	await get_tree().process_frame
	assert_eq(seen.size(), 2)
	assert_false(presenter.is_playing())
	assert_eq(session.battle.snapshot(), final_snapshot, "VFX must not change battle or RNG")
	await get_tree().process_frame

func test_cancel_each_phase_then_rewind_and_replay_at_double_speed() -> void:
	# Checkpoints across windup(0-0.48)/travel(0.48-0.82)/finish(0.82-3.22),
	# sized for butler_grand_ice's own (longer than hero's) timing.
	for seconds in [.15, .6, .85, 1.3, 1.8, 2.9]:
		var session := _session()
		var stage := _stage(session)
		var initial := session.battle.presentation_state()
		var log := session.resolve_ally_action({"type": "skill", "skill_id": "butler_grand_ice"})
		var final_snapshot := session.battle.snapshot()
		var impacts: Array = []
		var finishes: Array = []
		stage.impact.connect(func(entry): impacts.append(entry))
		stage.finished.connect(func(): finishes.append(true))
		stage.play_entry(log[0])
		stage._tween.custom_step(seconds)
		var impact_count := impacts.size()
		stage.cancel()
		await get_tree().process_frame
		assert_false(stage.is_playing())
		assert_false(stage._butler_ice.visible)
		assert_eq(stage._butler_ice.age, -1.0)
		assert_eq(stage._butler_shake, Vector2.ZERO)
		assert_eq(impacts.size(), impact_count, "Cancelled callbacks stay cancelled")
		assert_eq(finishes.size(), 0)
		for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])
		assert_eq(session.battle.snapshot(), final_snapshot)
		assert_true(session.rewind_to(1))
		stage.set_state(session.battle.presentation_state())
		assert_eq(stage._state, initial, "Rewind restores presentation state")
		var replay := session.resolve_ally_action({"type": "skill", "skill_id": "butler_grand_ice"})
		assert_eq(replay, log, "Rewind reproduces damage and RNG log")
		stage.play_entry(replay[0])
		stage._tween.set_speed_scale(2.0)
		stage._tween.custom_step(1.7)  # 1.7*2=3.4s effective, past the 3.22s total sequence
		assert_false(stage.is_playing(), "Whole finish follows tween playback speed")
		assert_eq(impacts.size(), impact_count + 1)
		assert_eq(finishes.size(), 1)
		assert_false(stage._butler_ice.visible)
		assert_eq(session.battle.snapshot(), final_snapshot)
	await get_tree().process_frame

func test_only_butler_grand_ice_triggers_the_finish_not_butlers_other_skills() -> void:
	var session := _session()
	var stage := _stage(session)
	for skill_id in ["butler_ice_bolt", "butler_ice_storm"]:
		var log := session.resolve_ally_action({"type": "skill", "skill_id": skill_id})
		stage.play_entry(log[0])
		assert_false(stage._butler_finish, "%s must never trigger the ice finish" % skill_id)
		stage.cancel()
