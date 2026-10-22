extends GutTest
const HeroAction=preload("res://src/bossmaker/visuals/rbm_hero_action.gd")
var held: Array=[]

func before_all() -> void:
	for path in preload("res://src/bossmaker/visuals/rbm_hero_burst.gd").warm_paths("hero",""):held.append(load(path))

func _session() -> RBMCreatorTestSession:
	var definition:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var session:=RBMCreatorTestSession.new(definition,20260906)
	while session.pending_ally_id()!=0:session.resolve_ally_action({"type":"defend"})
	session.battle.party[0].sp=100
	return session

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_knight")
	stage.set_state(session.battle.presentation_state())
	return stage

func test_real_resolved_actions_one_hit_and_no_combat_mutation() -> void:
	for key in ["attack","hero_slash","hero_blaze_all","hero_flame_wrap"]:
		var session:=_session()
		var stage:=_stage(session)
		var action: Dictionary={"type":"attack"} if key=="attack" else {"type":"skill","skill_id":key}
		var before:=session.battle.presentation_state()
		var log:=session.battle.resolve_pending_ally_action(action)
		var final_snapshot:=session.battle.snapshot()
		var presenter:=RBMBattlePresenter.new()
		add_child_autofree(presenter)
		presenter.enabled=true
		presenter.setup(stage)
		var hits: Array=[]
		var finishes: Array=[]
		stage.impact.connect(func(entry):hits.append(entry))
		stage.finished.connect(func():finishes.append(true))
		presenter.play(log,session.battle,before)
		assert_not_null(stage._skill_presentation,key+" selected dedicated hero action")
		if stage._skill_presentation==null:continue
		var timing: float=stage._skill_presentation.impact_time
		stage._tween.custom_step(timing-0.02)
		assert_eq(hits.size(),0,"No early HP/SP/buff commit")
		stage._tween.custom_step(0.03)
		assert_eq(hits.size(),1,"Exactly one hit")
		assert_eq(presenter.display_state(),log[0].visual_state)
		stage._tween.custom_step(2.0)
		await get_tree().process_frame
		assert_eq(hits.size(),1)
		assert_eq(finishes.size(),1)
		assert_eq(session.battle.snapshot(),final_snapshot,"Damage/SP/turn order/RNG immutable during presentation")
		assert_eq(stage._visuals["0"].position,stage._homes["0"])
		assert_true(stage._visuals["0"].visible)
		assert_null(stage._skill_presentation)
		if key=="attack":
			for cue in stage._sound.history:assert_false(cue.begins_with("fire"),"Normal attack has no fire audio")
		if key=="hero_blaze_all":
			assert_eq(log.size(),1)
			assert_eq(log[0].target,"boss")
			assert_false(log[0].has("hits"))
		if key=="hero_flame_wrap":
			assert_eq(session.battle.party[0].sp,70)
			assert_false(log[0].visual_state.party["0"].timed_effects.is_empty())

func test_cancel_before_and_after_impact_then_replay() -> void:
	for key in ["attack","hero_slash","hero_blaze_all","hero_flame_wrap"]:
		for at in [0.10,0.51,0.68]:
			var session:=_session()
			var stage:=_stage(session)
			var action: Dictionary={"type":"attack"} if key=="attack" else {"type":"skill","skill_id":key}
			var log:=session.battle.resolve_pending_ally_action(action)
			var skill:=RBMBattleUiKit.find_skill_for_actor(0,key,session.battle)
			var hits: Array=[]
			var finishes: Array=[]
			stage.impact.connect(func(entry):hits.append(entry))
			stage.finished.connect(func():finishes.append(true))
			stage.play_entry(log[0],skill)
			stage._tween.custom_step(at)
			var prior:=hits.size()
			stage.cancel()
			await get_tree().process_frame
			assert_eq(hits.size(),prior)
			assert_eq(finishes.size(),0)
			assert_false(stage.is_playing())
			assert_null(stage._skill_presentation)
			for player in stage._sound._players:assert_false(player.playing)
			stage.play_entry(log[0],skill)
			stage._tween.set_speed_scale(2.0)
			stage._tween.custom_step(1.2)
			await get_tree().process_frame
			assert_eq(hits.size(),prior+1)
			assert_eq(finishes.size(),1)
			for actor in stage._visuals:
				assert_eq(stage._visuals[actor].position,stage._homes[actor])
				assert_true(stage._visuals[actor].visible)

func test_finisher_uses_approved_upright_route() -> void:
	var session:=_session()
	var stage:=_stage(session)
	var log:=session.battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
	var skill:=RBMBattleUiKit.find_skill_for_actor(0,"hero_burst_slash",session.battle)
	stage.play_entry(log[0],skill)
	assert_false(stage._hero_finish)
	assert_eq(stage._skill_presentation.get_script(),preload("res://src/bossmaker/visuals/rbm_hero_burst.gd"))
	assert_eq(stage._motion_offset,Vector2.ZERO)
	stage.cancel()

func test_hide_cancels_hero_action_and_restores_actor() -> void:
	var session:=_session()
	var stage:=_stage(session)
	var log:=session.battle.resolve_pending_ally_action({"type":"attack"})
	stage.play_entry(log[0])
	stage._tween.custom_step(0.23)
	stage.hide()
	await get_tree().process_frame
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_true(stage._visuals["0"].visible)
	assert_eq(stage._visuals["0"].position,stage._homes["0"])
	for player in stage._sound._players:assert_false(player.playing)

func test_failed_actions_and_other_heroes_keep_existing_routes() -> void:
	var session:=_session()
	var stage:=_stage(session)
	stage.play_entry({"action":"attack","actor":0,"target":"boss","failed":true})
	assert_null(stage._skill_presentation)
	stage.cancel()
	stage._asset_ids["0"]="butler"
	stage.play_entry({"action":"attack","actor":0,"target":"boss"})
	assert_null(stage._skill_presentation)
	stage.cancel()

func test_normal_attack_assets_are_planned_before_first_input() -> void:
	var session:=_session()
	var stage:=_stage(session)
	for i in 100:
		await get_tree().process_frame
		if stage._presentation_warmup.planned_paths().has(HeroAction.SHEET_PATH): break
	assert_has(stage._presentation_warmup.planned_paths(),HeroAction.SHEET_PATH)
	assert_has(stage._presentation_warmup.planned_paths(),HeroAction.RETURN_PATH)

func test_melee_landing_stays_inside_embedded_stage() -> void:
	var session:=_session()
	var stage:=_stage(session)
	stage.remove_meta("fullscreen_formation")
	stage.size=Vector2(700,300)
	stage._layout_actors()
	stage.play_entry({"action":"attack","actor":0,"target":"boss"})
	assert_not_null(stage._skill_presentation)
	assert_lt(stage._skill_presentation._land.y,stage.size.y)
	stage.cancel()
