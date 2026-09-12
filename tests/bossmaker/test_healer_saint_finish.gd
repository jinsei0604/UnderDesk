extends GutTest

func _fixture() -> Dictionary:
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"] = []
	for id in ["hero","butler","healer","samurai"]:
		var master: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/allies/"+id+".json")
		var skills: Array = []
		for skill in master["skills"]: skills.append(skill["id"])
		definition["party"].append({"character_id":id,"allowed_skill_ids":skills})
	var session := RBMCreatorTestSession.new(definition,20260906)
	while session.pending_ally_id()!=2: session.resolve_ally_action({"type":"defend"})
	for unit in session.battle.party: unit.hp = unit.max_hp-300
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_dragon")
	var before := session.battle.presentation_state()
	stage.set_state(before)
	var logs := session.resolve_ally_action({"type":"skill","skill_id":"healer_heal_all"})
	return {"session":session,"stage":stage,"before":before,"logs":logs}

func test_real_heal_peak_and_cleanup_without_simulation_changes() -> void:
	var f := _fixture()
	var stage = f.stage
	var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
	var seen: Array = []
	var done: Array = []
	stage.impact.connect(func(e): seen.append(e))
	stage.finished.connect(func(): done.append(true))
	stage.play_entry(f.logs[0])
	assert_not_null(stage._skill_presentation)
	stage._tween.custom_step(3.0)
	assert_eq(seen.size(),0,"HP must remain unchanged before prayer peak")
	stage._tween.custom_step(.1)
	assert_eq(seen.size(),1)
	for id in f.before.party:
		assert_eq(int(seen[0].visual_state.party[id].hp)-int(f.before.party[id].hp),200)
	assert_eq(int(seen[0].visual_state.party["2"].sp),80)
	stage._tween.custom_step(3.1)
	assert_eq(seen.size(),1,"One recovery peak")
	assert_eq(done.size(),1)
	assert_null(stage._skill_presentation)
	assert_false(stage.is_playing())
	assert_eq(f.session.battle.snapshot(),snapshot)
	for key in stage._homes: assert_eq(stage._visuals[key].position,stage._homes[key])

func test_cancel_each_phase_and_replay() -> void:
	for elapsed in [.1,1.0,2.9,3.2,5.5]:
		var f := _fixture()
		var stage = f.stage
		var seen: Array = []
		stage.impact.connect(func(e): seen.append(e))
		stage.play_entry(f.logs[0])
		stage._tween.custom_step(elapsed)
		var count := seen.size()
		stage.cancel()
		await get_tree().process_frame
		assert_null(stage._skill_presentation)
		assert_eq(seen.size(),count,"No late impact after cancellation")
		assert_false(stage.is_playing())
		stage.play_entry(f.logs[0])
		stage._tween.custom_step(6.2)
		assert_eq(seen.size(),count+1)
		assert_null(stage._skill_presentation)

func test_other_actor_and_failed_action_do_not_dispatch() -> void:
	var f := _fixture()
	var stage = f.stage
	stage.play_entry({"actor":0,"action":"skill","skill_id":"healer_heal_all","healed":{"0":200}})
	assert_null(stage._skill_presentation)
	stage.cancel()
	stage.play_entry({"actor":2,"action":"skill","failed":true,"skill_id":"healer_heal_all"})
	assert_null(stage._skill_presentation)
