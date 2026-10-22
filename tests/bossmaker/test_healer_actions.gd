extends GutTest
const Stage=preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
const Base=preload("res://src/bossmaker/visuals/rbm_healer_action.gd")
const ACTIONS=["attack","healer_heal_single","healer_sp_all"]
var held: Array=[]

func before_all() -> void:
	for path in Base.warm_paths("healer",""):held.append(load(path))
	held.append_array(preload("res://tests/bossmaker/presentation_assets_ready.gd").hold([]))

func _fixture() -> Dictionary:
	var definition:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var session:=RBMCreatorTestSession.new(definition,20260906)
	while session.pending_ally_id()!=2:session.resolve_ally_action({"type":"defend"})
	for unit in session.battle.party:
		unit.hp=unit.max_hp-500
		unit.sp=120 if unit.id==2 else 20
	var stage:=Stage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_knight")
	stage.set_state(session.battle.presentation_state())
	return {"session":session,"stage":stage}

func _request(key: String,target: int=0) -> Dictionary:
	return {"type":"attack"} if key=="attack" else {"type":"skill","skill_id":key,"target_id":target}

func test_resolved_actions_commit_once_at_impact_without_battle_mutation() -> void:
	for key in ACTIONS:
		var f:=_fixture()
		var before: Dictionary=f.session.battle.presentation_state()
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
		var snapshot: Dictionary=f.session.battle.snapshot()
		var presenter:=RBMBattlePresenter.new()
		add_child_autofree(presenter)
		presenter.enabled=true
		presenter.setup(f.stage)
		var hits: Array=[];var done: Array=[]
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
		assert_eq(f.session.battle.snapshot(),snapshot,"Damage, SP, order, RNG unchanged by presentation")
		assert_null(f.stage._skill_presentation)
		assert_true(f.stage._visuals["2"].visible)
		assert_eq(f.stage._visuals["2"].position,f.stage._homes["2"])
		if key=="attack":assert_eq(f.stage._sound.history,["neutral_staff_tap","neutral_impact_light"])
		elif key=="healer_heal_single":
			assert_eq(entries[0].amount,400)
			assert_eq(f.session.battle.party[2].sp,100)
		else:
			assert_false(entries[0].recovered.has(2))
			assert_eq(f.session.battle.party[2].sp,60)

func test_cancel_hide_and_double_speed_replay_clean_every_phase() -> void:
	for key in ACTIONS:
		for delay in [0.16,0.55,1.00]:
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
			assert_false(f.stage.is_playing());assert_null(f.stage._skill_presentation)
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

func test_heal_self_clamp_full_hp_and_invalid_target() -> void:
	for target in [0,2]:
		for deficit in [0,50,500]:
			var f:=_fixture()
			var unit=f.session.battle.party[target]
			unit.hp=unit.max_hp-deficit
			var entries: Array=f.session.battle.resolve_pending_ally_action(_request("healer_heal_single",target))
			f.stage.play_entry(entries[0])
			var recipients: Array=f.stage._skill_presentation._recipients
			assert_eq(entries[0].amount,mini(400,deficit))
			assert_eq(recipients.size(),0 if deficit==0 else 1)
			if deficit>0:
				assert_eq(recipients[0].key,str(target))
				assert_lt(recipients[0].center.y,430.0,"HP core clears HUD log")
			f.stage.cancel()
	var f:=_fixture()
	f.session.battle.party[0].hp=0
	var entries: Array=f.session.battle.resolve_pending_ally_action(_request("healer_heal_single"))
	f.stage.play_entry(entries[0])
	assert_true(entries[0].failed)
	assert_null(f.stage._skill_presentation)
	assert_eq(f.session.battle.party[2].sp,120)
	f.stage.cancel()

func test_sp_recipients_follow_actual_gain_excluding_caster_downed_and_full() -> void:
	var f:=_fixture()
	f.session.battle.party[0].sp=95
	f.session.battle.party[1].hp=0
	f.session.battle.party[3].sp=f.session.battle.party[3].max_sp
	var entries: Array=f.session.battle.resolve_pending_ally_action(_request("healer_sp_all"))
	f.stage.play_entry(entries[0])
	var recipients: Array=f.stage._skill_presentation._recipients
	assert_eq(recipients.size(),1)
	assert_eq(recipients[0].key,"0");assert_eq(recipients[0].amount,5)
	assert_eq(f.session.battle.party[2].sp,60)
	f.stage.cancel()
	f=_fixture()
	for unit in f.session.battle.party:
		if unit.id!=2:unit.sp=unit.max_sp
	entries=f.session.battle.resolve_pending_ally_action(_request("healer_sp_all"))
	f.stage.play_entry(entries[0])
	assert_true(f.stage._skill_presentation._recipients.is_empty())
	f.stage._tween.custom_step(2.0)
	await get_tree().process_frame
	assert_false(f.stage.is_playing())
	f=_fixture()
	for unit in f.session.battle.party:
		if unit.id!=2:unit.hp=0
	entries=f.session.battle.resolve_pending_ally_action(_request("healer_sp_all"))
	f.stage.play_entry(entries[0])
	assert_not_null(f.stage._skill_presentation,"Empty eligible list is a valid completed cast")
	assert_true(f.stage._skill_presentation._recipients.is_empty())
	f.stage.cancel()

func test_finished_lightning_saint_and_hero_keep_existing_routes() -> void:
	for key in ["healer_shock","healer_heal_all"]:
		var f:=_fixture()
		var entries: Array=f.session.battle.resolve_pending_ally_action(_request(key))
		f.stage.play_entry(entries[0])
		if key=="healer_shock":assert_true(f.stage._healer_finish)
		else:assert_eq(f.stage._skill_presentation.get_script(),preload("res://src/bossmaker/visuals/rbm_healer_saint_finish.gd"))
		f.stage.cancel()
	var f:=_fixture()
	f.stage.play_entry({"actor":0,"action":"attack","target":"boss"})
	assert_eq(f.stage._skill_presentation.get_script(),preload("res://src/bossmaker/visuals/rbm_hero_normal.gd"))
	f.stage.cancel()

func test_rewind_reproduces_resolved_heal_and_clears_cast() -> void:
	var f:=_fixture()
	assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=2:f.session.resolve_ally_action({"type":"defend"})
	var before: Dictionary=f.session.battle.presentation_state()
	var first: Array=f.session.resolve_ally_action(_request("healer_heal_single"))
	f.stage.set_state(before);f.stage.play_entry(first[0]);f.stage._tween.custom_step(0.53);f.stage.cancel()
	assert_true(f.session.rewind_to(1))
	while f.session.pending_ally_id()!=2:f.session.resolve_ally_action({"type":"defend"})
	f.stage.set_state(f.session.battle.presentation_state())
	assert_eq(f.stage._state,before)
	assert_eq(first,f.session.resolve_ally_action(_request("healer_heal_single")))
	assert_null(f.stage._skill_presentation)

func test_party_plan_declares_assets_only_for_present_healer_and_releases() -> void:
	var f:=_fixture()
	var warm=f.stage._presentation_warmup
	var source: Dictionary=warm._source()
	var paths: Array=warm.plan_from(source)
	for path in Base.warm_paths("healer",""):assert_has(paths,path)
	source["party"]=["hero","butler","tank"]
	var definition:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	definition["party"].remove_at(2)
	var without_healer:=RBMCreatorTestSession.new(definition,20260906)
	source["battle"]=without_healer.battle
	assert_does_not_have(warm.plan_from(source),Base.SHEET)
	f.stage.release_presentations()
	assert_true(warm.held_paths().is_empty())
	assert_true(warm.planned_paths().is_empty())
