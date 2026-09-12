extends GutTest
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

func _fixture(attribute: String="NEUTRAL",character: String="hero",with_tank: bool=false) -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="Golem QA"
	draft.hp=99999
	draft.atk=40
	draft.spd=1
	draft.add_party_character(character)
	if with_tank: draft.add_party_character("tank")
	var id:=draft.add_skill({"name":"パンチ","type":"attack","target":"single","attribute":attribute,"atk_multiplier":1.0})
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),5)
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_golem")
	stage.set_state(session.battle.presentation_state())
	var action: Dictionary={"type":"defend"} if character!="samurai" else {"type":"skill","skill_id":"samurai_counter"}
	var log:=session.resolve_ally_action(action)
	while str(log[-1].get("actor"))!="boss": log=session.resolve_ally_action({"type":"defend"})
	return {"stage":stage,"session":session,"entry":log[-1],"skill":RBMBattleUiKit.find_skill_for_actor("boss",id,session.battle)}

func test_all_attributes_one_hit_exact_fist_contact_and_unchanged_simulation() -> void:
	for attribute in Palette.COLORS:
		var f:=_fixture(attribute)
		var snapshot: Dictionary=f.session.battle.snapshot()
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var driver=f.stage._skill_presentation
		assert_not_null(driver)
		f.stage._tween.custom_step(.77)
		assert_eq(seen.size(),0)
		f.stage._tween.custom_step(.02)
		assert_eq(seen.size(),1)
		var fist: Vector2=f.stage._foot("boss")+Vector2(40-256,280-460)*f.stage._visuals["boss"]._pixel_scale
		assert_lt(fist.distance_to(driver.contact),1.5,"Native fist touches intended upper torso")
		f.stage._tween.custom_step(.10)
		assert_eq(driver._vfx.impact_color,Palette.COLORS[attribute])
		f.stage._tween.custom_step(2)
		assert_eq(seen.size(),1)
		assert_null(f.stage._skill_presentation)
		assert_eq(f.session.battle.snapshot(),snapshot)
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
	assert_eq(Palette.color_for("UNKNOWN"),Color("b7bbc2"))

func test_cancel_and_replay_all_phases() -> void:
	for t in [.1,.5,.79,.95,1.4]:
		var f:=_fixture()
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(t)
		var count:=seen.size()
		f.stage.cancel()
		await get_tree().process_frame
		assert_eq(seen.size(),count)
		assert_null(f.stage._skill_presentation)
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(2)
		assert_eq(seen.size(),count+1)

func test_counter_retains_existing_samurai_finish_and_one_reflected_impact() -> void:
	var f:=_fixture("FIRE","samurai")
	assert_true(f.entry.get("counter",false))
	var seen: Array=[]
	f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry(f.entry,f.skill)
	f.stage._tween.custom_step(1.1)
	assert_eq(seen.size(),0)
	f.stage._tween.custom_step(.36)
	assert_eq(f.stage._visuals["0"].position,f.stage._homes["0"],"Ranged counter stays at its home while the golem returns")
	for i in range(100):
		if not f.stage.is_playing(): break
		f.stage._tween.custom_step(.1)
	assert_eq(seen.size(),1)
	assert_false(f.stage.is_playing())
	assert_null(f.stage._skill_presentation)
	assert_false(f.stage._samurai_wind.visible)

func test_cover_target_contact_uses_redirected_target_position() -> void:
	var f:=_fixture("ICE","hero",true)
	# Presentation fixture for an already resolved cover log.
	var state: Dictionary=f.stage._state.duplicate(true)
	state.party["1"].protecting_ally_id=0
	f.stage._state=state
	var entry={"actor":"boss","action":"skill","skill_id":"qa_cover","target":1,"visual_original_target":0,"amount":20}
	f.stage.play_entry(entry,{"effect":"damage","target":"ally_random_single","attribute":"ICE"})
	assert_eq(f.stage._guards,["1"])
	f.stage._tween.custom_step(.70)
	var driver=f.stage._skill_presentation
	var upper: Vector2=f.stage._foot("1")-Vector2(0,f.stage.Assets.display_height("tank")*.80)
	assert_lt(driver.contact.distance_to(upper),1.5)
	f.stage.cancel()
	assert_eq(f.stage._visuals["1"].position,f.stage._homes["1"])

func test_non_single_or_other_boss_does_not_dispatch() -> void:
	var f:=_fixture()
	f.stage.play_entry({"actor":"boss","action":"skill","hits":{"0":{"amount":20}}},{"effect":"damage","target":"ally_all"})
	assert_null(f.stage._skill_presentation)
	f.stage.cancel()
	f.stage.play_entry({"actor":"boss","action":"skill","target":"boss","amount":20},{"effect":"self_heal"})
	assert_null(f.stage._skill_presentation)
	f.stage.cancel()
	f.stage.configure(f.session.battle,"appearance_dragon")
	f.stage.play_entry(f.entry,f.skill)
	assert_null(f.stage._skill_presentation)
	f.stage.cancel()
	await get_tree().process_frame
