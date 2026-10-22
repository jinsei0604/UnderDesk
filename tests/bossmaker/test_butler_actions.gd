extends GutTest
const Stage=preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
const ACTIONS=["attack","butler_ice_bolt","butler_ice_storm","butler_sp_gift"]
const Base=preload("res://src/bossmaker/visuals/rbm_butler_action.gd")
var held: Array=[]

func before_all() -> void:
	for path in Base.warm_paths("butler",""): held.append(load(path))
	for path in preload("res://src/bossmaker/visuals/rbm_hero_normal.gd").warm_paths("hero",""): held.append(load(path))

func _fixture(target_sp: int=20) -> Dictionary:
	var definition:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var session:=RBMCreatorTestSession.new(definition,20260906)
	while session.pending_ally_id()!=1: session.resolve_ally_action({"type":"defend"})
	session.battle.party[1].sp=150
	session.battle.party[0].sp=target_sp
	var stage:=Stage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_knight")
	stage.set_state(session.battle.presentation_state())
	return {"session":session,"stage":stage}

func _request(key: String, target: int=0) -> Dictionary:
	return {"type":"attack"} if key=="attack" else {"type":"skill","skill_id":key,"target_id":target}

func test_all_four_resolved_actions_commit_once_at_hit_without_mutation() -> void:
	for key in ACTIONS:
		var f:=_fixture()
		var before: Dictionary=f.session.battle.presentation_state()
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
		var snapshot: Dictionary=f.session.battle.snapshot()
		var presenter:=RBMBattlePresenter.new()
		add_child_autofree(presenter)
		presenter.enabled=true
		presenter.setup(f.stage)
		var hits: Array=[]; var done: Array=[]
		f.stage.impact.connect(func(e):hits.append(e))
		f.stage.finished.connect(func():done.append(true))
		presenter.play(entries,f.session.battle,before)
		assert_not_null(f.stage._skill_presentation,key)
		if f.stage._skill_presentation==null:continue
		var action: Node2D=f.stage._skill_presentation
		f.stage._tween.custom_step(action.impact_time-0.02)
		assert_eq(hits.size(),0)
		assert_eq(presenter.display_state(),before)
		f.stage._tween.custom_step(0.03)
		assert_eq(hits.size(),1)
		assert_eq(presenter.display_state(),entries[0].visual_state)
		f.stage._tween.custom_step(1.5)
		await get_tree().process_frame
		assert_eq(hits.size(),1);assert_eq(done.size(),1)
		assert_eq(f.session.battle.snapshot(),snapshot,"Damage/SP/order/RNG remain resolved values")
		assert_null(f.stage._skill_presentation)
		assert_eq(f.stage._visuals["1"].position,f.stage._homes["1"])
		assert_true(f.stage._visuals["1"].visible)
		if key=="attack":
			for sound in f.stage._sound.history: assert_false(sound.begins_with("ice"))
		if key=="butler_ice_storm":
			assert_eq(entries.size(),1)
			assert_eq(entries[0].target,"boss")
			assert_false(entries[0].has("hits"))
		if key=="butler_sp_gift":
			assert_eq(entries[0].target,0)
			assert_eq(entries[0].amount,40)
			assert_eq(f.session.battle.party[0].sp,60)

func test_cancel_hide_restore_and_double_speed_replay() -> void:
	for key in ACTIONS:
		for delay in [0.16,0.55,0.91]:
			var f:=_fixture()
			var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
			var snapshot: Dictionary=f.session.battle.snapshot()
			var hits: Array=[];var done: Array=[]
			f.stage.impact.connect(func(e):hits.append(e))
			f.stage.finished.connect(func():done.append(true))
			f.stage.play_entry(entries[0])
			f.stage._tween.custom_step(minf(delay,float(f.stage._skill_presentation.duration)-0.02))
			var prior:=hits.size()
			f.stage.hide()
			await get_tree().process_frame
			assert_false(f.stage.is_playing())
			assert_null(f.stage._skill_presentation)
			assert_eq(hits.size(),prior);assert_eq(done.size(),0)
			for player in f.stage._sound._players:assert_false(player.playing)
			for actor in f.stage._visuals:
				assert_true(f.stage._visuals[actor].visible)
				assert_eq(f.stage._visuals[actor].position,f.stage._homes[actor])
			f.stage.show()
			f.stage.play_entry(entries[0])
			f.stage._tween.set_speed_scale(2.0)
			f.stage._tween.custom_step(0.8)
			await get_tree().process_frame
			assert_false(f.stage.is_playing())
			assert_eq(hits.size(),prior+1);assert_eq(done.size(),1)
			assert_eq(f.session.battle.snapshot(),snapshot)

func test_sp_gift_clamp_zero_and_invalid_target_are_not_false_recovery() -> void:
	for sp in [90,100]:
		var f:=_fixture(sp)
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request("butler_sp_gift"))
		f.stage.play_entry(entries[0])
		assert_eq(f.stage._skill_presentation._recovered_amount,100-sp)
		assert_eq(f.stage._skill_presentation._target_key,"0")
		assert_lt(f.stage._skill_presentation._target.y,450.0,"Recovery core above log")
		f.stage.cancel()
	var f:=_fixture()
	var bad: Array=f.session.battle.resolve_pending_ally_action(_request("butler_sp_gift",1))
	f.stage.play_entry(bad[0])
	assert_null(f.stage._skill_presentation)
	assert_eq(f.session.battle.party[1].sp,150,"Invalid target costs nothing")
	f.stage.cancel()

func test_existing_grand_magic_and_other_actor_keep_their_routes() -> void:
	var f:=_fixture()
	var entries: Array=f.session.battle.resolve_pending_ally_action(_request("butler_grand_ice"))
	f.stage.play_entry(entries[0])
	assert_true(f.stage._butler_finish)
	assert_null(f.stage._skill_presentation)
	f.stage.cancel()
	f.stage.play_entry({"actor":0,"action":"attack","target":"boss"})
	assert_eq(f.stage._skill_presentation.get_script(),preload("res://src/bossmaker/visuals/rbm_hero_normal.gd"))
	f.stage.cancel()

func test_rewind_reproduces_sp_gift_and_clears_cast() -> void:
	var f:=_fixture()
	# Rewind semantics are driven by the production session, not a visual timer.
	assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=1: f.session.resolve_ally_action({"type":"defend"})
	var before: Dictionary=f.session.battle.presentation_state()
	var first: Array=f.session.resolve_ally_action(_request("butler_sp_gift"))
	f.stage.set_state(before)
	f.stage.play_entry(first[0])
	f.stage._tween.custom_step(0.58)
	f.stage.cancel()
	assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=1: f.session.resolve_ally_action({"type":"defend"})
	f.stage.set_state(f.session.battle.presentation_state())
	assert_eq(f.stage._state,before)
	var replay: Array=f.session.resolve_ally_action(_request("butler_sp_gift"))
	assert_eq(first,replay)
	assert_null(f.stage._skill_presentation)

func test_declared_assets_exist_and_motion_keeps_sprite_scale() -> void:
	for path in Base.warm_paths("butler",""): assert_true(ResourceLoader.exists(path),path)
	for key in ACTIONS:
		var f:=_fixture()
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
		f.stage.play_entry(entries[0])
		var action: Node2D=f.stage._skill_presentation
		for t in [0.18,0.34,0.58]:
			action._advance(t)
			assert_eq(action.scale,Vector2.ONE)
			assert_lt(action._foot.distance_to(action._home),3.1)
			assert_lt(action._watch_position().distance_to(action._foot),140.0)
		f.stage.cancel()

func test_party_warmup_plan_includes_only_present_butler_assets() -> void:
	var f:=_fixture()
	var warm=f.stage._presentation_warmup
	var source: Dictionary=warm._source()
	var paths: Array=warm.plan_from(source)
	for path in Base.warm_paths("butler",""):
		assert_has(paths,path,"Butler assets are planned before the first action")
	var without_butler: Dictionary=source.duplicate()
	without_butler["party"]=["hero","healer","tank"]
	# The source's battle must also agree with the party for initial-SP eligibility.
	var definition:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"].remove_at(1)
	var no_butler:=RBMCreatorTestSession.new(definition,20260906)
	without_butler["battle"]=no_butler.battle
	assert_does_not_have(warm.plan_from(without_butler),Base.SHEET)
