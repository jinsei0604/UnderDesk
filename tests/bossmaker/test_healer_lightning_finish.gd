extends GutTest

## src/bossmaker/visuals/rbm_battle_stage.gd's healer_shock finish wiring,
## mirroring test_hero_fire_finish.gd/test_butler_ice_finish.gd's guarantees
## for hero_burst_slash/butler_grand_ice: the presenter stays on this single
## entry until the finish layer has ended, the boss's own next action never
## plays early, cancel-at-any-phase leaves no residue, and rewind/replay at
## double speed reproduces the same damage/RNG log. Scoped to healer_shock
## only -- healer's other three skills (heal_single/heal_all/sp_all) never
## trigger it (they target allies, never "boss", but are checked directly
## via _healer_finish for documentation, same as the ice test's own skills).

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "雷フィニッシュ回帰"
	draft.hp = 99999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("healer")
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
	var log := session.resolve_ally_action({"type": "skill", "skill_id": "healer_shock"})
	assert_eq(log.size(), 2)
	var final_snapshot := session.battle.snapshot()
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array = []
	presenter.entry_impact.connect(func(entry): seen.append(entry))
	presenter.play(log, session.battle, before)
	# healer_shock's windup(0.24)+travel(0.16) = 0.40s, and the finish itself
	# runs 0.85s (total sequence 1.25s) -- step points are sized for THIS
	# skill's own (much shorter, regular-attack-tier) timing, not copied from
	# the hero/butler ultimate-tier tests.
	stage._tween.custom_step(.43)
	assert_eq(seen.size(), 1)
	assert_eq(stage._motion_offset, Vector2.ZERO, "Healer casts from home (ranged attack, no lunge)")
	assert_eq(stage._visuals["0"].position, stage._homes["0"])
	stage._tween.custom_step(.5)
	assert_eq(seen.size(), 1, "Boss cannot attack during the finish")
	assert_true(stage.is_playing())
	assert_eq(presenter.display_state(), log[0]["visual_state"], "No future boss damage in HUD")
	stage._tween.custom_step(.5)
	await get_tree().process_frame
	assert_false(stage._healer_lightning.visible)
	assert_false(stage._healer_finish)
	assert_eq(stage._healer_shake, Vector2.ZERO)
	# healer_shock自身のフィニッシュ(1.25s)が終わった後は、ボス側の反撃
	# (log[1])が続けて再生される。その反撃の演出時間はボス外見ごとの専用
	# 演出(例: golemの反撃は専用のGolem Punch VFXを使い、より長い)によって
	# 変わりうるため、固定秒数を1回足すだけでは足りない場合がある――
	# presenter自身が完了を報告するまで、少しずつtweenを進め続ける
	# (無限ループ防止のため合計10秒相当を上限とする)。
	var advanced := 0.0
	while presenter.is_playing() and advanced < 10.0:
		if is_instance_valid(stage._tween):
			stage._tween.custom_step(.25)
		advanced += .25
		await get_tree().process_frame
	assert_eq(seen.size(), 2)
	assert_false(presenter.is_playing(), "presenter must finish once the boss's own follow-up presentation (whatever its actual duration) has completed")
	assert_eq(session.battle.snapshot(), final_snapshot, "VFX must not change battle or RNG")
	await get_tree().process_frame

func test_cancel_each_phase_then_rewind_and_replay_at_double_speed() -> void:
	# Checkpoints across windup(0-0.24)/travel(0.24-0.40)/finish(0.40-1.25),
	# sized for healer_shock's own (much shorter than hero's/butler's) timing.
	for seconds in [.1, .2, .35, .43, .7, 1.15]:
		var session := _session()
		var stage := _stage(session)
		var initial := session.battle.presentation_state()
		var log := session.resolve_ally_action({"type": "skill", "skill_id": "healer_shock"})
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
		assert_false(stage._healer_lightning.visible)
		assert_eq(stage._healer_lightning.age, -1.0)
		assert_eq(stage._healer_shake, Vector2.ZERO)
		assert_eq(impacts.size(), impact_count, "Cancelled callbacks stay cancelled")
		assert_eq(finishes.size(), 0)
		for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])
		assert_eq(session.battle.snapshot(), final_snapshot)
		assert_true(session.rewind_to(1))
		stage.set_state(session.battle.presentation_state())
		assert_eq(stage._state, initial, "Rewind restores presentation state")
		var replay := session.resolve_ally_action({"type": "skill", "skill_id": "healer_shock"})
		assert_eq(replay, log, "Rewind reproduces damage and RNG log")
		stage.play_entry(replay[0])
		stage._tween.set_speed_scale(2.0)
		stage._tween.custom_step(.7)  # .7*2=1.4s effective, past the 1.25s total sequence
		assert_false(stage.is_playing(), "Whole finish follows tween playback speed")
		assert_eq(impacts.size(), impact_count + 1)
		assert_eq(finishes.size(), 1)
		assert_false(stage._healer_lightning.visible)
		assert_eq(session.battle.snapshot(), final_snapshot)
	await get_tree().process_frame

func test_only_healer_shock_triggers_the_finish_not_healers_other_skills() -> void:
	var session := _session()
	var stage := _stage(session)
	for skill_id in ["healer_heal_all", "healer_sp_all"]:
		var log := session.resolve_ally_action({"type": "skill", "skill_id": skill_id})
		stage.play_entry(log[0])
		assert_false(stage._healer_finish, "%s must never trigger the lightning finish" % skill_id)
		stage.cancel()
