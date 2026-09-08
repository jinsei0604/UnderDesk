extends GutTest

class ManualStage extends Node:
	signal impact(entry: Dictionary)
	signal finished
	var entries: Array[Dictionary] = []
	var state: Dictionary = {}
	var cancel_count: int = 0
	func play_entry(entry: Dictionary, _skill: Dictionary = {}) -> void:
		entries.append(entry)
	func set_state(snapshot: Dictionary) -> void:
		state = snapshot.duplicate(true)
	func cancel() -> void:
		cancel_count += 1

func _definition(fast_boss: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "演出同期検証"
	draft.hp = 100000
	draft.atk = 1
	draft.spd = 500 if fast_boss else 1
	draft.add_party_character("hero")
	var skill_id := draft.add_skill({"name": "検証攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return draft.to_definition()

func test_opening_and_rewind_keep_actual_events_and_detached_before_state() -> void:
	var creator := RBMCreatorTestSession.new(_definition(true), 74)
	assert_true(creator.start_ok())
	var ally := creator.battle.party[0]
	var id_key := str(ally.id)
	var initial: Dictionary = creator.presentation_initial_state
	var opening := creator.take_presentation_log()
	assert_eq(opening.size(), 1, "Fast boss opening must be retained")
	assert_eq(opening[0]["actor"], "boss")
	assert_eq(initial["party"][id_key]["hp"], ally.max_hp)
	assert_lt(ally.hp, int(initial["party"][id_key]["hp"]))
	assert_eq(opening[0]["visual_state"]["party"][id_key]["hp"], ally.hp)
	assert_true(creator.take_presentation_log().is_empty(), "Opening is consumed once")
	assert_true(creator.rewind_to(1))
	var replay := creator.take_presentation_log()
	assert_eq(replay, opening, "Rewind retains the same RNG result and visual snapshots")
	assert_false(creator.battle.snapshot().has("visual_state"), "Presentation metadata stays out of save/rewind snapshots")
	var challenge := RBMChallengeSession.new(_definition(true), 74)
	assert_eq(challenge.take_presentation_log(), opening, "Both session types retain the same opening")

func test_presenter_commits_hud_at_impact_in_order_without_changing_battle() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 3)
	var before := session.battle.presentation_state()
	var ally := session.battle.party[0]
	var hud := Control.new()
	add_child_autofree(hud)
	hud.add_child(RBMBattleUiKit.build_party_card(ally, func(_id: int): pass))
	var hp_bar := hud.find_child("PartyRowHPBar_%d" % ally.id, true, false) as ProgressBar
	var initial_hp := ally.hp
	var log := session.resolve_ally_action({"type": "attack"})
	assert_eq(log.size(), 2, "Ally action is followed by the boss")
	var final_sim := session.battle.snapshot()
	var stage := ManualStage.new()
	add_child_autofree(stage)
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array[Dictionary] = []
	presenter.entry_impact.connect(func(entry: Dictionary): seen.append(entry))
	presenter.entry_impact.connect(func(entry: Dictionary): RBMBattlePresenter.apply_status_snapshot(hud, entry["visual_state"]))
	presenter.play(log, session.battle, before)
	assert_eq(stage.entries.size(), 1)
	assert_true(seen.is_empty(), "Pre-motion must not reveal resolved damage")
	assert_eq(stage.state, before)
	assert_lt(ally.hp, initial_hp, "The simulation already includes the later boss attack")
	assert_eq(int(hp_bar.value), initial_hp, "The HUD must not reveal that future attack")
	stage.impact.emit(log[0])
	stage.impact.emit(log[0])
	assert_eq(seen.size(), 1, "One HUD commit even if a marker is duplicated")
	assert_eq(stage.state, log[0]["visual_state"])
	assert_eq(int(hp_bar.value), initial_hp, "The ally impact must preserve pre-boss HP")
	assert_eq(session.battle.snapshot(), final_sim, "Playback never writes the simulation")
	stage.finished.emit()
	stage.finished.emit()
	await get_tree().process_frame
	assert_eq(stage.entries.size(), 2, "Duplicate completion cannot skip the next action")
	assert_true(presenter.is_playing())
	stage.impact.emit(log[1])
	assert_eq(seen.size(), 2)
	assert_eq(int(hp_bar.value), ally.hp, "Boss damage becomes visible at its own impact")
	stage.finished.emit()
	await get_tree().process_frame
	assert_false(presenter.is_playing())
	assert_eq(session.battle.snapshot(), final_sim)

func test_cancel_invalidates_queued_next_action_and_ignores_late_markers() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 5)
	var before := session.battle.presentation_state()
	var log := session.resolve_ally_action({"type": "attack"})
	var stage := ManualStage.new()
	add_child_autofree(stage)
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array[Dictionary] = []
	presenter.entry_impact.connect(func(entry: Dictionary): seen.append(entry))
	presenter.play(log, session.battle, before)
	stage.finished.emit() # Fallback impact and deferred next action.
	assert_eq(seen.size(), 1)
	presenter.cancel()
	stage.impact.emit(log[0])
	stage.finished.emit()
	await get_tree().process_frame
	assert_false(presenter.is_playing())
	assert_eq(stage.entries.size(), 1, "Cancelled deferred callbacks cannot start the next attack")
	assert_eq(seen.size(), 1)
	presenter.play([log[1]], session.battle, log[0]["visual_state"])
	stage.impact.emit(log[1])
	stage.finished.emit()
	await get_tree().process_frame
	assert_eq(seen.size(), 2, "A new generation still plays after cancellation")
	assert_false(presenter.is_playing())

func test_headless_views_keep_synchronous_commands_with_presentation_explicitly_off() -> void:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	var definition := _definition()
	var test_view := main._test_battle_view
	test_view.presentation_enabled = false
	assert_true(test_view.start(definition, 1))
	var clear_view := main._clear_check_view
	clear_view.presentation_enabled = false
	clear_view.open(main.draft)
	clear_view.start_battle(definition, 1)
	var challenge_view := RBMChallengeBattleView.new()
	add_child_autofree(challenge_view)
	await get_tree().process_frame
	challenge_view.presentation_enabled = false
	challenge_view.start_battle(definition)
	for view in [test_view, clear_view, challenge_view]:
		var before_hp: int = view.session.battle.boss.hp
		view.act_attack(view.session.pending_ally_id())
		assert_lt(view.session.battle.boss.hp, before_hp)
		assert_false(view._is_presenting())
		assert_false(view._log_label.text.is_empty())
