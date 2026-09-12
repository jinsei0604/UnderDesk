extends GutTest

## src/bossmaker/visuals/rbm_battle_stage.gd's samurai_counter finish wiring:
## when a boss's attack is countered by a samurai holding counter_stance,
## _strike() poses the counterer GUARD and hands off to
## _samurai_finish_progress() instead of the generic counter/recovery
## sequence -- a short "counter established" contact flash
## (rbm_samurai_wind_block.gd), the boss sliding back home, then the long
## wind finish (rbm_samurai_wind_finish.gd) that reflects the damage back
## onto the boss at its own explosion beat. Mirrors test_hero_fire_finish.gd/
## test_healer_lightning_finish.gd's guarantees for their own finishes.
##
## resolve_ally_action({"skill_id":"samurai_counter"}) returns a 2-entry log:
## log[0] is the samurai's own stance-setting action (actor=samurai, never
## triggers this finish), log[1] is the boss's subsequent attack, countered
## (actor=boss, the entry this finish is scoped to).

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "風カウンター回帰"
	draft.hp = 99999
	draft.atk = 40
	draft.spd = 1
	draft.add_party_character("samurai")
	var skill_id := draft.add_skill({"name": "攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return RBMCreatorTestSession.new(draft.to_definition(), 5)

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var result := RBMBattleStage.new()
	result.size = Vector2(1280, 720)
	result.set_meta("fullscreen_formation", true)
	add_child_autofree(result)
	result.configure(session.battle, "appearance_golem")
	result.set_state(session.battle.presentation_state())
	return result

func _skill_for(entry: Dictionary, battle: Variant) -> Dictionary:
	return RBMBattleUiKit.find_skill_for_actor(entry.get("actor"), str(entry.get("skill_id", "")), battle)

func test_samurai_finish_flag_set_only_for_the_countered_boss_attack() -> void:
	var session := _session()
	var stage := _stage(session)
	var log := session.resolve_ally_action({"type": "skill", "skill_id": "samurai_counter"})
	assert_eq(log.size(), 2)
	assert_true(bool(log[1].get("counter", false)), "sanity: the boss's attack was actually countered")
	stage.play_entry(log[0])
	assert_false(stage._samurai_finish, "the stance-setup entry (actor=samurai) must never trigger the finish")
	stage.cancel()
	stage.play_entry(log[1], _skill_for(log[1], session.battle))
	assert_true(stage._samurai_finish, "a boss attack countered by the samurai must trigger the wind finish")
	stage.cancel()

func test_finish_eventually_finishes_and_reflects_damage_exactly_once() -> void:
	var session := _session()
	var stage := _stage(session)
	var log := session.resolve_ally_action({"type": "skill", "skill_id": "samurai_counter"})
	var final_snapshot := session.battle.snapshot()
	var impacts: Array = []
	var finishes: Array = []
	stage.impact.connect(func(entry): impacts.append(entry))
	stage.finished.connect(func(): finishes.append(true))
	stage.play_entry(log[1], _skill_for(log[1], session.battle))
	assert_true(stage._samurai_finish)
	var guard := 0
	while stage.is_playing() and guard < 200:
		stage._tween.custom_step(0.1)
		guard += 1
	await get_tree().process_frame
	assert_false(stage.is_playing(), "the finish must eventually end on its own")
	assert_eq(impacts.size(), 1, "the reflected damage must land exactly once")
	assert_eq(finishes.size(), 1)
	assert_false(stage._samurai_wind.visible)
	assert_false(stage._samurai_wind_block.visible)
	assert_false(stage._samurai_finish)
	assert_eq(stage._samurai_shake, Vector2.ZERO)
	for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])
	assert_eq(session.battle.snapshot(), final_snapshot, "VFX must not change battle or RNG")

func test_cancel_each_phase_then_rewind_and_replay_at_double_speed() -> void:
	for seconds in [.1, .2, .5, 1.0, 2.0, 3.5]:
		var session := _session()
		var stage := _stage(session)
		var log := session.resolve_ally_action({"type": "skill", "skill_id": "samurai_counter"})
		var final_snapshot := session.battle.snapshot()
		var impacts: Array = []
		var finishes: Array = []
		stage.impact.connect(func(entry): impacts.append(entry))
		stage.finished.connect(func(): finishes.append(true))
		stage.play_entry(log[1], _skill_for(log[1], session.battle))
		stage._tween.custom_step(seconds)
		var impact_count := impacts.size()
		stage.cancel()
		await get_tree().process_frame
		assert_false(stage.is_playing())
		assert_false(stage._samurai_wind.visible)
		assert_eq(stage._samurai_wind.age, -1.0)
		assert_false(stage._samurai_wind_block.visible)
		assert_eq(stage._samurai_shake, Vector2.ZERO)
		assert_eq(impacts.size(), impact_count, "Cancelled callbacks stay cancelled")
		assert_eq(finishes.size(), 0)
		for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])
		assert_eq(session.battle.snapshot(), final_snapshot)
		assert_true(session.rewind_to(1))
		stage.set_state(session.battle.presentation_state())
		var replay := session.resolve_ally_action({"type": "skill", "skill_id": "samurai_counter"})
		assert_eq(replay, log, "Rewind reproduces damage and RNG log")
		stage.play_entry(replay[1], _skill_for(replay[1], session.battle))
		stage._tween.set_speed_scale(2.0)
		var guard := 0
		while stage.is_playing() and guard < 200:
			stage._tween.custom_step(0.2)  # 0.2*2=0.4s effective per step
			guard += 1
		await get_tree().process_frame
		assert_false(stage.is_playing(), "Whole finish follows tween playback speed")
		assert_eq(impacts.size(), impact_count + 1)
		assert_eq(finishes.size(), 1)
		assert_false(stage._samurai_wind.visible)
		assert_eq(session.battle.snapshot(), final_snapshot)
	await get_tree().process_frame
