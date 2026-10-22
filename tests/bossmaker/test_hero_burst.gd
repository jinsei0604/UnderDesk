extends GutTest
const CandidateStage=preload("res://src/bossmaker/visuals/rbm_battle_stage.gd")
var held:Array=[]
func before_all() -> void:
	for path in preload("res://src/bossmaker/visuals/rbm_hero_burst.gd").warm_paths("hero",""):held.append(load(path))
func _fixture() -> Dictionary:
	var d:=RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var session:=RBMCreatorTestSession.new(d,31)
	while session.pending_ally_id()!=0:session.resolve_ally_action({"type":"defend"})
	session.battle.party[0].sp=100
	var stage:=CandidateStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_knight")
	stage.set_state(session.battle.presentation_state())
	var entries:=session.battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_burst_slash"})
	return {"session":session,"stage":stage,"entry":entries[0]}
func test_upright_charge_and_one_impact_without_simulation_changes() -> void:
	var f:=_fixture()
	var snapshot:Dictionary=f.session.battle.snapshot().duplicate(true)
	var hits:Array=[];var done:Array=[]
	f.stage.impact.connect(func(e):hits.append(e))
	f.stage.finished.connect(func():done.append(true))
	f.stage.play_entry(f.entry)
	f.stage._tween.custom_step(0.3)
	assert_eq(f.stage._skill_presentation._frame,12,"Upright blade stance; no seated pose")
	assert_eq(f.stage._skill_presentation._foot,f.stage._skill_presentation._home)
	f.stage._tween.custom_step(1.30)
	assert_eq(hits.size(),0)
	f.stage._tween.custom_step(.05)
	assert_eq(hits.size(),1)
	f.stage._tween.custom_step(2.0)
	await get_tree().process_frame
	assert_eq(hits.size(),1);assert_eq(done.size(),1)
	assert_eq(f.session.battle.snapshot(),snapshot)
	assert_null(f.stage._skill_presentation)
	assert_eq(f.stage._visuals["0"].position,f.stage._homes["0"])
func test_cancel_hide_and_double_speed_replay() -> void:
	for t in [.2,.7,1.67,2.65]:
		var f:=_fixture()
		f.stage.play_entry(f.entry)
		f.stage._tween.custom_step(t)
		f.stage.hide()
		await get_tree().process_frame
		assert_false(f.stage.is_playing());assert_null(f.stage._skill_presentation)
		for player in f.stage._sound._players:assert_false(player.playing)
		for key in f.stage._homes:
			assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
			assert_true(f.stage._visuals[key].visible)
		f.stage.show()
		f.stage.play_entry(f.entry)
		f.stage._tween.set_speed_scale(2.0)
		f.stage._tween.custom_step(1.65)
		await get_tree().process_frame
		assert_false(f.stage.is_playing())
