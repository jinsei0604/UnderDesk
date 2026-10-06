extends GutTest
const Ground=preload("res://src/bossmaker/visuals/rbm_golem_ground_slam.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
## ゴーレム専用の演出(単体・全体・支援)。他のボスには選ばれてはいけない。
const GOLEM_PRESENTATIONS=[preload("res://src/bossmaker/visuals/rbm_golem_single_punch.gd"),preload("res://src/bossmaker/visuals/rbm_golem_ground_slam.gd"),preload("res://src/bossmaker/visuals/rbm_golem_support.gd")]

func _is_golem_presentation(presentation) -> bool:
	return is_instance_valid(presentation) and GOLEM_PRESENTATIONS.has(presentation.get_script())

func _fixture(attribute: String="NEUTRAL",counter: bool=false) -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="Ground slam QA"
	draft.hp=99999
	draft.atk=40
	draft.spd=1
	for id in (["samurai","hero","healer","butler"] if counter else ["hero","butler","healer","samurai"]): draft.add_party_character(id)
	var skill_id:=draft.add_skill({"name":"Ground slam","type":"attack","target":"all","attribute":attribute,"atk_multiplier":1.0})
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[skill_id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),5)
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_golem")
	stage.set_state(session.battle.presentation_state())
	var entries: Array=[]
	for attempt in range(12):
		var action: Dictionary={"type":"skill","skill_id":"samurai_counter"} if counter and session.pending_ally_id()==0 else {"type":"defend"}
		entries=session.resolve_ally_action(action)
		if entries.any(func(e):return str(e.get("actor"))=="boss"): break
	var entry: Dictionary={}
	for e in entries:
		if str(e.get("actor"))=="boss": entry=e
	return {"stage":stage,"session":session,"entry":entry,"skill":RBMBattleUiKit.find_skill_for_actor("boss",skill_id,session.battle)}

func test_five_colors_ground_contact_eruption_and_single_four_target_event() -> void:
	for attribute in Palette.COLORS:
		var f:=_fixture(attribute)
		assert_eq(f.entry.get("hits",{}).size(),4,"Production AoE hits all four")
		var before: Dictionary=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var driver=f.stage._skill_presentation
		assert_eq(driver.get_script(),Ground)
		f.stage._tween.custom_step(.73)
		assert_true(driver._slammed)
		assert_eq(f.stage._poses["boss"],5)
		assert_eq(seen.size(),0,"Ground contact does not apply party damage")
		assert_eq(driver._vfx.attribute,attribute)
		assert_eq(driver._vfx.ground_contacts[0],f.stage._foot("boss")-driver._shake+Vector2(-70,-5))
		f.stage._tween.custom_step(.90)
		assert_eq(seen.size(),0,"Wait for the rock impact")
		f.stage._tween.custom_step(.02)
		assert_eq(seen.size(),1)
		assert_eq(seen[0],f.entry)
		for key in f.stage._targets: assert_eq(f.stage._poses[key],11)
		f.stage._tween.custom_step(5)
		assert_eq(seen.size(),1)
		assert_null(f.stage._skill_presentation)
		assert_false(f.stage.is_playing())
		assert_eq(f.session.battle.snapshot(),before,"Presentation never mutates simulation")
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_cancel_cleanup_and_replay_at_each_phase() -> void:
	for elapsed in [.2,.75,1.2,1.7,2.7,3.9]:
		var f:=_fixture()
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var driver=f.stage._skill_presentation
		f.stage._tween.custom_step(elapsed)
		var count:=seen.size()
		f.stage.cancel()
		await get_tree().process_frame
		assert_false(is_instance_valid(driver),"Driver, viewport and VFX freed")
		assert_eq(seen.size(),count)
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(5)
		assert_eq(seen.size(),count+1)

func test_real_aoe_counter_keeps_existing_finish_and_one_combined_event() -> void:
	var f:=_fixture("WIND",true)
	var counters:=0
	for hit in f.entry.get("hits",{}).values():
		if hit.get("counter",false): counters+=1
	assert_eq(counters,1,"Real session establishes exactly one samurai counter")
	var before: Dictionary=f.session.battle.snapshot().duplicate(true)
	var seen: Array=[]
	f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry(f.entry,f.skill)
	f.stage._tween.custom_step(1.70)
	assert_eq(seen.size(),0,"Combined counter entry keeps the existing delayed impact contract")
	assert_eq(f.stage._poses["0"],10)
	for key in ["1","2","3"]: assert_eq(f.stage._poses[key],11)
	for i in range(150):
		if not f.stage.is_playing(): break
		f.stage._tween.custom_step(.1)
	assert_eq(seen.size(),1)
	assert_eq(seen[0],f.entry)
	assert_false(f.stage.is_playing())
	assert_null(f.stage._skill_presentation)
	assert_false(f.stage._samurai_wind.visible)
	assert_eq(f.session.battle.snapshot(),before)
	for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_other_boss_aoe_keeps_generic_presentation() -> void:
	var f:=_fixture()
	f.stage.configure(f.session.battle,"appearance_dragon")
	f.stage.play_entry(f.entry,f.skill)
	# 竜は自分の専用演出を持つようになった(以前の「竜はnull」の前提は古い)。確かめるのは、
	# 他のボスの全体攻撃にゴーレムの演出が選ばれないこと。
	assert_false(_is_golem_presentation(f.stage._skill_presentation),"another boss's AoE never uses a golem presentation")
	f.stage.cancel()
	await get_tree().process_frame
