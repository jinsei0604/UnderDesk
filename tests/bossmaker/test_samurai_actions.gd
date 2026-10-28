extends GutTest
const Stage=preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
const Base=preload("res://src/bossmaker/visuals/rbm_samurai_action.gd")
const Review=preload("res://tools/verify_samurai_actions_gpu.gd")
const ACTIONS=["attack","samurai_slash","samurai_slash_all","samurai_iai","samurai_counter"]
var held: Array=[]

func before_all() -> void:
	for path in Base.warm_paths("samurai",""):held.append(load(path))
	held.append_array(preload("res://tests/bossmaker/presentation_assets_ready.gd").hold([]))

func after_each() -> void:
	# configure() queues old actors for deletion; flush the normal deferred
	# cleanup before GUT counts orphan nodes between test cases.
	await get_tree().process_frame

func _fixture() -> Dictionary:
	var session:=RBMCreatorTestSession.new(Review.definition_for(),20260906)
	while session.pending_ally_id()!=1:session.resolve_ally_action({"type":"defend"})
	session.battle.party[1].sp=130
	var stage:=Stage.new();stage.size=Vector2(1280,720);stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage);stage.configure(session.battle,"appearance_knight");stage.set_state(session.battle.presentation_state())
	return {"session":session,"stage":stage}

func _request(key: String) -> Dictionary:
	return {"type":"attack"} if key=="attack" else {"type":"skill","skill_id":key}

func test_resolved_actions_commit_once_and_leave_combat_unchanged() -> void:
	for key in ACTIONS:
		var f:=_fixture();var before: Dictionary=f.session.battle.presentation_state()
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
		var snapshot: Dictionary=f.session.battle.snapshot()
		var presenter:=RBMBattlePresenter.new();add_child_autofree(presenter);presenter.enabled=true;presenter.setup(f.stage)
		var hits: Array=[];var done: Array=[]
		f.stage.impact.connect(func(e):hits.append(e));f.stage.finished.connect(func():done.append(true))
		presenter.play(entries,f.session.battle,before)
		assert_not_null(f.stage._skill_presentation,key)
		if f.stage._skill_presentation==null:continue
		var action: Node2D=f.stage._skill_presentation
		f.stage._tween.custom_step(action.impact_time-0.02)
		assert_eq(hits.size(),0);assert_eq(presenter.display_state(),before)
		f.stage._tween.custom_step(0.03)
		assert_eq(hits.size(),1);assert_eq(presenter.display_state(),entries[0].visual_state)
		f.stage._tween.custom_step(2.0);await get_tree().process_frame
		assert_eq(hits.size(),1);assert_eq(done.size(),1)
		assert_eq(f.session.battle.snapshot(),snapshot,"SP, damage, RNG and order untouched")
		assert_null(f.stage._skill_presentation);assert_eq(f.stage._visuals["1"].position,f.stage._homes["1"])
		if key=="attack":assert_eq(f.stage._sound.history,["neutral_sword_swing","neutral_impact_light"])
		if key=="samurai_slash_all":assert_eq(entries[0].target,"boss");assert_false(entries[0].has("hits"))
		if key=="samurai_iai":assert_eq(f.stage._samurai_stance.frame,18)
		if key=="samurai_counter":assert_eq(f.stage._samurai_stance.frame,19)

func test_cancel_hide_and_double_speed_replay_clean_every_phase() -> void:
	for key in ACTIONS:
		for delay in [0.16,0.55,1.00]:
			var f:=_fixture();var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
			var snapshot: Dictionary=f.session.battle.snapshot();var hits: Array=[];var done: Array=[]
			f.stage.impact.connect(func(e):hits.append(e));f.stage.finished.connect(func():done.append(true))
			f.stage.play_entry(entries[0]);f.stage._tween.custom_step(minf(delay,float(f.stage._skill_presentation.duration)-0.02))
			var prior:=hits.size();f.stage.hide();await get_tree().process_frame
			assert_false(f.stage.is_playing());assert_null(f.stage._skill_presentation);assert_eq(hits.size(),prior);assert_eq(done.size(),0)
			for player in f.stage._sound._players:assert_false(player.playing)
			for actor in f.stage._visuals:
				assert_true(f.stage._visuals[actor].visible);assert_eq(f.stage._visuals[actor].position,f.stage._homes[actor])
			f.stage.show();f.stage.play_entry(entries[0]);f.stage._tween.set_speed_scale(2.0);f.stage._tween.custom_step(0.8)
			await get_tree().process_frame
			assert_false(f.stage.is_playing());assert_eq(hits.size(),prior+1);assert_eq(done.size(),1);assert_eq(f.session.battle.snapshot(),snapshot)

func test_iai_persists_through_normal_and_expires_on_attack_skill() -> void:
	var f:=_fixture();var b: RBMBattle=f.session.battle
	b.resolve_pending_ally_action(_request("samurai_iai"))
	f.stage.set_state(b.presentation_state());assert_eq(f.stage._samurai_stance.frame,18)
	while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
	var normal: Array=b.resolve_pending_ally_action(_request("attack"))
	assert_eq(b.party[1].next_attack_bonus_multiplier,2.5)
	f.stage.set_state(normal[0].visual_state);assert_eq(f.stage._samurai_stance.frame,18)
	while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
	var slash: Array=b.resolve_pending_ally_action(_request("samurai_slash"))
	assert_eq(b.party[1].next_attack_bonus_multiplier,1.0)
	f.stage.set_state(slash[0].visual_state);assert_eq(f.stage._samurai_stance.frame,-1);assert_true(f.stage._visuals["1"].visible)

func test_counter_expires_at_the_samurai_s_next_slot_and_protected_response_is_unchanged() -> void:
	var f:=_fixture();f.session.battle.resolve_pending_ally_action(_request("samurai_counter"))
	f.stage.set_state(f.session.battle.presentation_state());assert_eq(f.stage._samurai_stance.frame,19)
	# 2026-10-28: the stance is no longer cleared by the round end -- it lasts until the samurai's own next slot
	# (unless a boss hit consumed it first). The pose follows the real state either way.
	var turn: int=f.session.battle.current_turn
	while f.session.battle.current_turn==turn:f.session.resolve_ally_action({"type":"defend"})
	f.stage.set_state(f.session.battle.presentation_state())
	assert_eq(f.stage._samurai_stance.frame,19 if f.session.battle.party[1].counter_pending_this_turn else -1)
	while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
	assert_false(f.session.battle.party[1].counter_pending_this_turn,"cleared at the samurai's own next slot")
	f.stage.set_state(f.session.battle.presentation_state());assert_eq(f.stage._samurai_stance.frame,-1)
	var counter:=Review.counter_fixture();assert_false(counter.is_empty())
	if counter.is_empty():return
	f.session.battle.restore(counter.snapshot);f.stage.set_state(counter.before)
	var snapshot: Dictionary=f.session.battle.snapshot();var hits: Array=[];var done: Array=[]
	f.stage.impact.connect(func(e):hits.append(e));f.stage.finished.connect(func():done.append(true))
	var skill:=RBMBattleUiKit.find_skill_for_actor("boss",str(counter.entry.skill_id),f.session.battle)
	f.stage.play_entry(counter.entry,skill);f.stage._samurai_stance.refresh()
	assert_true(f.stage._samurai_finish);assert_eq(f.stage._samurai_stance.frame,-1)
	for i in 100:
		if not f.stage.is_playing():break
		f.stage._tween.custom_step(0.1)
	await get_tree().process_frame
	assert_eq(hits.size(),1);assert_eq(done.size(),1);assert_false(f.stage._samurai_wind.visible)
	assert_eq(f.session.battle.snapshot(),snapshot)

func test_rewind_restores_pose_and_damage_log_without_residuals() -> void:
	var f:=_fixture();assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
	var before: Dictionary=f.session.battle.presentation_state()
	var first: Array=f.session.resolve_ally_action(_request("samurai_slash"))
	f.stage.set_state(before);f.stage.play_entry(first[0]);f.stage._tween.custom_step(0.5);f.stage.cancel()
	assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
	f.stage.set_state(f.session.battle.presentation_state())
	assert_eq(f.stage._state,before);assert_eq(f.session.resolve_ally_action(_request("samurai_slash")),first)
	assert_null(f.stage._skill_presentation);assert_eq(f.stage._samurai_stance.frame,-1)

func test_warm_plan_is_party_scoped_and_releases() -> void:
	var f:=_fixture();var warm=f.stage._presentation_warmup
	var source: Dictionary=warm._source();var paths: Array=warm.plan_from(source)
	for path in Base.warm_paths("samurai",""):assert_has(paths,path)
	source["party"]=["hero","healer","tank"]
	var definition:=Review.definition_for();definition.party.remove_at(1)
	var other:=RBMCreatorTestSession.new(definition,5);source["battle"]=other.battle
	assert_does_not_have(warm.plan_from(source),Base.SHEET)
	f.stage.release_presentations();assert_true(warm.held_paths().is_empty());assert_true(warm.planned_paths().is_empty())
	assert_null(f.stage._samurai_stance.texture);assert_eq(f.stage._samurai_stance.frame,-1)
	f.stage.configure(other.battle,"appearance_knight");f.stage.set_state(other.battle.presentation_state())
	assert_eq(f.stage._samurai_stance.key,"");assert_eq(f.stage._samurai_stance.frame,-1)

func test_iai_wind_follows_real_buff_for_every_action_and_consumption() -> void:
	for key in ACTIONS:
		var f:=_fixture();var b: RBMBattle=f.session.battle
		b.resolve_pending_ally_action(_request("samurai_iai"))
		while f.session.pending_ally_id()!=1:f.session.resolve_ally_action({"type":"defend"})
		var before:=b.presentation_state();f.stage.set_state(before)
		assert_true(f.stage._samurai_stance.wind_active,"Wind is visible between actions")
		var entries:=b.resolve_pending_ally_action(_request(key));var snapshot:=b.snapshot()
		var presenter:=RBMBattlePresenter.new();add_child_autofree(presenter);presenter.enabled=true;presenter.setup(f.stage)
		presenter.play(entries,b,before)
		var action: Node2D=f.stage._skill_presentation
		assert_not_null(action,key)
		if action==null:continue
		var hit_time: float=action.impact_time
		assert_gt(action.wind_strength(),0.0,key+" starts with IAI wind")
		assert_false(f.stage._samurai_stance.wind_active,"Only the moving actor owns the mantle")
		f.stage._tween.custom_step(action.impact_time+0.02)
		assert_gt(action.wind_strength(),0.0,"Consuming hit retains its wind through contact")
		f.stage._tween.custom_step(2.0);await get_tree().process_frame
		var consumed: bool=key in ["samurai_slash","samurai_slash_all"]
		assert_eq(f.stage._samurai_stance.wind_active,not consumed,key+" final wind lifetime")
		assert_eq(b.snapshot(),snapshot,"Presentation never writes combat state")
		# Replaying and cancelling on either side of impact restores only the
		# actual displayed state; consumed wind must not leak from the latch.
		for after_hit in [false,true]:
			presenter.play(entries,b,before)
			f.stage._tween.custom_step(0.1 if not after_hit else hit_time+0.02)
			presenter.cancel();f.stage._samurai_stance.refresh()
			assert_false(f.stage._samurai_stance.counter_wind)
			assert_null(f.stage._skill_presentation)
			assert_eq(f.stage._samurai_stance.wind_active,preload("res://src/bossmaker/visuals/rbm_samurai_iai_wind.gd").is_active(f.stage._unit_state("1")))
		f.stage.set_state(before);assert_true(f.stage._samurai_stance.wind_active,"Rewind restores wind")
		var downed:=before.duplicate(true);downed.party["1"].is_downed=true
		f.stage.set_state(downed);assert_false(f.stage._samurai_stance.wind_active)
		f.stage.release_presentations();assert_false(f.stage._samurai_stance.wind_active)

func test_iai_wind_survives_counter_impact_then_clears_without_replacing_response() -> void:
	var f:=_fixture()
	var counter:=preload("res://tools/verify_samurai_iai_gpu.gd").charged_counter_fixture()
	assert_false(counter.is_empty())
	if counter.is_empty():return
	f.session.battle.restore(counter.snapshot)
	var presenter:=RBMBattlePresenter.new();add_child_autofree(presenter);presenter.enabled=true;presenter.setup(f.stage)
	presenter.play([counter.entry],f.session.battle,counter.before)
	assert_true(f.stage._samurai_finish)
	assert_eq(f.stage._skill_presentation.get_script().resource_path,"res://src/bossmaker/visuals/rbm_knight_single_slash.gd","Original incoming boss attack is preserved")
	assert_true(f.stage._samurai_stance.counter_wind)
	for i in 100:
		if not f.stage.is_playing():break
		f.stage._tween.custom_step(0.1)
		f.stage._samurai_stance.refresh()
	await get_tree().process_frame
	assert_false(f.stage._samurai_stance.counter_wind);assert_false(f.stage._samurai_stance.wind_active)
	assert_eq(f.session.battle.snapshot(),counter.snapshot)
	presenter.play([counter.entry],f.session.battle,counter.before)
	f.stage._tween.custom_step(0.1);presenter.cancel();f.stage._samurai_stance.refresh()
	assert_false(f.stage._samurai_stance.counter_wind);assert_false(f.stage._samurai_wind.visible)

func test_reconfiguring_without_samurai_releases_pose_wind_and_sheet() -> void:
	var f:=_fixture();f.session.battle.resolve_pending_ally_action(_request("samurai_iai"))
	f.stage.set_state(f.session.battle.presentation_state())
	assert_true(f.stage._samurai_stance.wind_active);assert_not_null(f.stage._samurai_stance.texture)
	var definition:=Review.definition_for();definition.party.remove_at(1)
	var other:=RBMCreatorTestSession.new(definition,6)
	f.stage.configure(other.battle,"appearance_knight");f.stage.set_state(other.battle.presentation_state())
	assert_eq(f.stage._samurai_stance.key,"");assert_null(f.stage._samurai_stance.texture)
	assert_false(f.stage._samurai_stance.wind_active);assert_false(f.stage._samurai_stance.is_processing())
	f.stage.configure(f.session.battle,"appearance_knight");f.stage.set_state(f.session.battle.presentation_state())
	assert_true(f.stage._samurai_stance.wind_active);assert_true(f.stage._samurai_stance.is_processing())
