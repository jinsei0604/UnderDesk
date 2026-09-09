extends GutTest

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "炎演出回帰"
	draft.hp = 100000
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	var skill_id := draft.add_skill({"name":"攻撃", "type":"attack", "target":"single", "attribute":"NEUTRAL", "atk_multiplier":1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return RBMCreatorTestSession.new(draft.to_definition(), 31)

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var result := RBMBattleStage.new()
	result.size = Vector2(1280,720)
	result.set_meta("fullscreen_formation",true)
	add_child_autofree(result)
	result.configure(session.battle,"appearance_dragon")
	result.set_state(session.battle.presentation_state())
	return result

func test_finish_blocks_next_entry_and_emits_each_impact_once() -> void:
	var session := _session()
	var before := session.battle.presentation_state()
	var stage := _stage(session)
	var log := session.resolve_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
	assert_eq(log.size(),2)
	var final_snapshot := session.battle.snapshot()
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array = []
	presenter.entry_impact.connect(func(entry): seen.append(entry))
	presenter.play(log,session.battle,before)
	stage._tween.custom_step(.70)
	assert_eq(seen.size(),1)
	assert_eq(stage._motion_offset,Vector2.ZERO,"Hero fires from home")
	assert_eq(stage._visuals["0"].position,stage._homes["0"])
	stage._tween.custom_step(1.0)
	assert_eq(seen.size(),1,"Boss cannot attack during the finish")
	assert_true(stage.is_playing())
	assert_eq(presenter.display_state(),log[0]["visual_state"],"No future boss damage in HUD")
	stage._tween.custom_step(1.2)
	await get_tree().process_frame
	assert_false(stage._hero_fire.visible)
	assert_false(stage._hero_finish)
	assert_eq(stage._hero_shake,Vector2.ZERO)
	stage._tween.custom_step(2.0)
	await get_tree().process_frame
	assert_eq(seen.size(),2)
	assert_false(presenter.is_playing())
	assert_eq(session.battle.snapshot(),final_snapshot,"VFX must not change battle or RNG")
	await get_tree().process_frame

func test_cancel_each_phase_then_rewind_and_replay_at_double_speed() -> void:
	for seconds in [.15,.5,.7,1.05,1.43,2.2]:
		var session := _session()
		var stage := _stage(session)
		var initial := session.battle.presentation_state()
		var log := session.resolve_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
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
		assert_false(stage._hero_fire.visible)
		assert_eq(stage._hero_fire.age,-1.0)
		assert_eq(stage._hero_shake,Vector2.ZERO)
		assert_eq(impacts.size(),impact_count,"Cancelled callbacks stay cancelled")
		assert_eq(finishes.size(),0)
		for key in stage._homes: assert_eq(stage._visuals[key].position,stage._homes[key])
		assert_eq(session.battle.snapshot(),final_snapshot)
		assert_true(session.rewind_to(1))
		stage.set_state(session.battle.presentation_state())
		assert_eq(stage._state,initial,"Rewind restores presentation state")
		var replay := session.resolve_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
		assert_eq(replay,log,"Rewind reproduces damage and RNG log")
		stage.play_entry(replay[0])
		stage._tween.set_speed_scale(2.0)
		stage._tween.custom_step(1.5)
		assert_false(stage.is_playing(),"Whole finish follows tween playback speed")
		assert_eq(impacts.size(),impact_count+1)
		assert_eq(finishes.size(),1)
		assert_false(stage._hero_fire.visible)
		assert_eq(session.battle.snapshot(),final_snapshot)
	await get_tree().process_frame
