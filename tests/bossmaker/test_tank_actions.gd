extends GutTest
const Stage=preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
const Base=preload("res://src/bossmaker/visuals/rbm_tank_action.gd")
const Review=preload("res://tools/verify_tank_actions_gpu.gd")
const ACTIONS=["attack","tank_smash","tank_guard_swap","tank_guard_boost","tank_iron_wall"]
var held: Array=[]
func before_all() -> void:
	for path in Base.warm_paths("tank",""):held.append(load(path))
	held.append_array(preload("res://tests/bossmaker/presentation_assets_ready.gd").hold([]))
func after_each() -> void:await get_tree().process_frame
func _fixture() -> Dictionary:
	var session:=RBMCreatorTestSession.new(Review.definition_for(),20260906)
	while session.pending_ally_id()!=3:session.resolve_ally_action({"type":"defend"})
	var stage:=Stage.new();stage.size=Vector2(1280,720);stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage);stage.configure(session.battle,"appearance_knight");stage.set_state(session.battle.presentation_state())
	return {"session":session,"stage":stage}
func test_resolved_actions_commit_once_at_impact_and_preserve_combat() -> void:
	for key in ACTIONS:
		var f:=_fixture();var before: Dictionary=f.session.battle.presentation_state()
		var entries: Array=f.session.battle.resolve_pending_ally_action(Review.request_for(key))
		var snapshot: Dictionary=f.session.battle.snapshot()
		var presenter:=RBMBattlePresenter.new();add_child_autofree(presenter);presenter.enabled=true;presenter.setup(f.stage)
		var hits: Array=[];var done: Array=[]
		f.stage.impact.connect(func(e):hits.append(e));f.stage.finished.connect(func():done.append(true))
		presenter.play(entries,f.session.battle,before)
		assert_not_null(f.stage._skill_presentation,key)
		if f.stage._skill_presentation==null:continue
		var action: Node2D=f.stage._skill_presentation
		f.stage._tween.custom_step(action.impact_time-.02)
		assert_eq(hits.size(),0);assert_eq(presenter.display_state(),before)
		f.stage._tween.custom_step(.03)
		assert_eq(hits.size(),1);assert_eq(presenter.display_state(),entries[0].visual_state)
		f.stage._tween.custom_step(2.0);await get_tree().process_frame
		assert_eq(hits.size(),1);assert_eq(done.size(),1);assert_eq(f.session.battle.snapshot(),snapshot)
		assert_null(f.stage._skill_presentation);assert_eq(f.stage._visuals["3"].position,f.stage._homes["3"]);assert_true(f.stage._visuals["3"].visible)
		assert_eq(f.stage._sound.history.size(),2,"One cue at each intended event, no duplicate fallback sounds")
		if key in ["attack","tank_smash"]:assert_eq(entries[0].target,"boss");assert_false(entries[0].has("hits"))
func test_hide_cancel_and_replay_leave_no_motion_sound_or_late_event() -> void:
	for key in ACTIONS:
		for delay in [.16,.62,.98]:
			var f:=_fixture();var entries: Array=f.session.battle.resolve_pending_ally_action(Review.request_for(key))
			var snapshot: Dictionary=f.session.battle.snapshot();var hits: Array=[];var done: Array=[]
			f.stage.impact.connect(func(e):hits.append(e));f.stage.finished.connect(func():done.append(true))
			f.stage.play_entry(entries[0]);f.stage._tween.custom_step(delay)
			var count:=hits.size();f.stage.hide();await get_tree().process_frame
			assert_false(f.stage.is_playing());assert_null(f.stage._skill_presentation);assert_eq(hits.size(),count);assert_eq(done.size(),0)
			for player in f.stage._sound._players:assert_false(player.playing)
			for actor in f.stage._visuals:
				assert_true(f.stage._visuals[actor].visible);assert_eq(f.stage._visuals[actor].position,f.stage._homes[actor])
			f.stage.show();f.stage.play_entry(entries[0]);f.stage._tween.set_speed_scale(2);f.stage._tween.custom_step(.8)
			await get_tree().process_frame
			assert_false(f.stage.is_playing());assert_eq(hits.size(),count+1);assert_eq(done.size(),1);assert_eq(f.session.battle.snapshot(),snapshot)
func test_support_markers_follow_real_state_and_expire_at_turn_boundary() -> void:
	for key in ["tank_guard_swap","tank_guard_boost","tank_iron_wall"]:
		var f:=_fixture();var battle: RBMBattle=f.session.battle
		battle.resolve_pending_ally_action(Review.request_for(key));f.stage.set_state(battle.presentation_state());f.stage._tank_state.refresh()
		assert_eq(f.stage._tank_state.cover_id,"0" if key=="tank_guard_swap" else "")
		assert_eq(f.stage._tank_state.boost,key=="tank_guard_boost");assert_eq(f.stage._tank_state.wall,key=="tank_iron_wall")
		var turn:=battle.current_turn
		while battle.current_turn==turn:f.session.resolve_ally_action({"type":"defend"})
		f.stage.set_state(battle.presentation_state());f.stage._tank_state.refresh()
		assert_eq(f.stage._tank_state.cover_id,"");assert_false(f.stage._tank_state.boost);assert_false(f.stage._tank_state.wall)
func test_cover_response_preserves_actual_redirect_and_single_impact() -> void:
	for attribute in ["NEUTRAL","FIRE","ICE","LIGHTNING","WIND"]:
		var cover:=Review.cover_fixture(attribute);assert_false(cover.is_empty(),attribute)
		if cover.is_empty():continue
		var f:=_fixture();f.session.battle.restore(cover.snapshot);f.stage.set_state(cover.before)
		var hits: Array=[];f.stage.impact.connect(func(e):hits.append(e))
		var skill:=RBMBattleUiKit.find_skill_for_actor("boss",str(cover.entry.skill_id),f.session.battle)
		f.stage.play_entry(cover.entry,skill)
		for i in 120:
			if not f.stage.is_playing():break
			f.stage._tween.custom_step(.1)
		await get_tree().process_frame
		assert_eq(hits.size(),1);assert_eq(int(hits[0].target),3);assert_eq(int(hits[0].visual_original_target),0)
		assert_eq(f.session.battle.snapshot(),cover.snapshot);assert_eq(f.stage._visuals["3"].position,f.stage._homes["3"])
func test_rewind_restores_support_marker_and_identical_resolved_log() -> void:
	var f:=_fixture();var before: Dictionary=f.session.battle.presentation_state()
	var first: Array=f.session.resolve_ally_action(Review.request_for("tank_iron_wall"))
	f.stage.set_state(before);f.stage.play_entry(first[0]);f.stage._tween.custom_step(.71);f.stage.cancel()
	assert_true(f.session.rewind_to(1));f.stage.set_state(f.session.battle.presentation_state());f.stage._tank_state.refresh()
	assert_eq(f.stage._state,before);assert_false(f.stage._tank_state.wall)
	assert_eq(f.session.resolve_ally_action(Review.request_for("tank_iron_wall")),first)
func test_warmup_is_party_scoped_and_state_releases_on_exit() -> void:
	var f:=_fixture();var warm=f.stage._presentation_warmup
	var source: Dictionary=warm._source()
	assert_has(warm.plan_from(source),Base.Body.SHEET)
	# Reconfigure the real battle and actor list together; the warm plan also
	# checks skills available in source.battle, not just source.party.
	var definition:=Review.definition_for();definition.party.remove_at(3)
	var other:=RBMCreatorTestSession.new(definition,7)
	f.stage.configure(other.battle,"appearance_knight")
	source=warm._source()
	assert_false(warm.plan_from(source).has(Base.Body.SHEET))
	f.stage.release_presentations();assert_false(f.stage._tank_state.enabled);assert_false(f.stage._tank_state.is_processing())
	assert_eq(f.stage._tank_state.cover_id,"");assert_false(f.stage._tank_state.wall);assert_true(warm._held.is_empty())

func test_reconfigure_and_release_clear_markers_then_resume_for_tank() -> void:
	var f:=_fixture()
	f.session.battle.resolve_pending_ally_action(Review.request_for("tank_iron_wall"))
	f.stage.set_state(f.session.battle.presentation_state())
	assert_true(f.stage._tank_state.wall)
	f.stage.release_presentations()
	assert_false(f.stage._tank_state.is_processing());assert_false(f.stage._tank_state.wall)
	var definition:=Review.definition_for();definition.party.remove_at(3)
	var other:=RBMCreatorTestSession.new(definition,7)
	f.stage.configure(other.battle,"appearance_knight");f.stage.set_state(other.battle.presentation_state())
	assert_false(f.stage._tank_state.is_processing());assert_false(f.stage._tank_state.wall)
	assert_false(f.stage._tank_state.boost);assert_eq(f.stage._tank_state.cover_id,"")
	f.stage.configure(f.session.battle,"appearance_knight");f.stage.set_state(f.session.battle.presentation_state())
	assert_true(f.stage._tank_state.is_processing());assert_true(f.stage._tank_state.wall)
