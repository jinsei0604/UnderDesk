extends GutTest
const Driver=preload("res://src/bossmaker/visuals/rbm_slime_presentation.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_slime_vfx.gd")

func _fixture(kind: String,attribute: String="NEUTRAL",counter: bool=false) -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="Slime QA"
	draft.hp=3000
	draft.atk=40
	draft.spd=1
	var ids: Array=["samurai"] if counter and kind=="single" else (["samurai","hero","healer","butler"] if counter else ["hero","butler","healer","samurai"])
	for id in ids: draft.add_party_character(id)
	var spec={"name":"Slime QA skill","type":"attack","target":"all" if kind=="aoe" else "single","attribute":attribute,"atk_multiplier":1.0}
	if kind in ["buff","heal"]:
		spec={"name":"Slime support","type":"self_heal" if kind=="heal" else "atk_self_buff","heal_amount":200,"buff_multiplier":1.3,"duration_turns":3}
	var id:=draft.add_skill(spec)
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),5)
	session.battle.boss.hp=1500
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_slime")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary={}
	for attempt in range(12):
		var action: Dictionary={"type":"skill","skill_id":"samurai_counter"} if counter and session.pending_ally_id()==0 else {"type":"defend"}
		var entries:=session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor"))=="boss": entry=e
		if not entry.is_empty(): break
	var skill:=RBMBattleUiKit.find_skill_for_actor("boss",id,session.battle)
	if kind in ["buff","heal"]: skill.attribute=attribute
	return {"stage":stage,"session":session,"entry":entry,"skill":skill}


func test_real_attacks_palette_impact_cleanup_and_simulation_unchanged() -> void:
	for kind in ["single","aoe"]:
		for attribute in Palette.COLORS:
			var f:=_fixture(kind,attribute)
			assert_false(f.entry.is_empty())
			var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var d=f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d.kind,kind)
			assert_eq(d._vfx.attack_attribute,attribute)
			assert_eq(Palette.color_for(d._vfx.attack_attribute),Palette.COLORS[attribute])
			assert_eq(d._vfx.slime,f.stage.Assets.texture("slime",0))
			assert_false(f.stage._visuals["boss"].visible)
			f.stage._tween.custom_step(d.impact_time-.01)
			assert_eq(seen.size(),0)
			f.stage._tween.custom_step(.02)
			assert_eq(seen.size(),1)
			assert_eq(seen[0],f.entry)
			if kind=="single":
				assert_eq(d._vfx.state.arm,1.0)
				assert_gt(float(d._vfx.state.crush),0.0)
			else:
				assert_eq(f.entry.get("hits",{}).size(),4)
				assert_eq(d._vfx.feet.size(),4)
				assert_eq(d._vfx.particles.size(),76)
				for lane in range(4):
					var near:=0
					for p in d._vfx.particles:
						if p.lane==lane and p.target.distance_to(d._vfx.feet[lane])<110: near+=1
					assert_eq(near,19,"Each actual target receives one broad fluid lane")
			f.stage._tween.custom_step(5)
			assert_eq(seen.size(),1)
			assert_null(f.stage._skill_presentation)
			assert_true(f.stage._visuals["boss"].visible)
			assert_eq(f.stage._visuals["boss"].scale,Vector2.ONE)
			assert_eq(f.stage._visuals["boss"].pivot_offset,Vector2.ZERO)
			assert_eq(f.session.battle.snapshot(),snapshot)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_support_shared_body_and_attribute_independent_color() -> void:
	var reference: Array=[]
	for kind in ["buff","heal"]:
		var f:=_fixture(kind,"ICE" if kind=="buff" else "FIRE")
		var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		assert_eq(d.kind,kind)
		assert_eq(VFX.SUPPORT[d._vfx.kind],Color("ef4847") if kind=="buff" else Color("71da87"))
		var samples: Array=[]
		for i in range(181):
			f.stage._tween.custom_step(1.0/60)
			samples.append(d._vfx.state.duplicate(true))
		if reference.is_empty(): reference=samples
		else: assert_eq(samples,reference,"Every rendered body sample is identical")
		assert_eq(d._vfx.state.scale,Vector2.ONE)
		f.stage._tween.custom_step(1)
		assert_eq(seen.size(),1)
		assert_null(f.stage._skill_presentation)
		assert_true(f.stage._visuals["boss"].visible)
		assert_eq(f.session.battle.snapshot(),snapshot)

func test_cancel_during_deformation_shake_spray_and_support_then_replay() -> void:
	for kind in ["single","aoe","buff","heal"]:
		for elapsed in [.32,.94,1.43,2.05]:
			var f:=_fixture(kind)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var d=f.stage._skill_presentation
			f.stage._tween.custom_step(elapsed)
			var count:=seen.size()
			f.stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(d))
			assert_eq(seen.size(),count)
			assert_true(f.stage._visuals["boss"].visible)
			assert_eq(f.stage._visuals["boss"].scale,Vector2.ONE)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
			f.stage.play_entry(f.entry,f.skill)
			f.stage._tween.custom_step(5)
			assert_eq(seen.size(),count+1)

func test_cover_redirected_target_and_normal_attack() -> void:
	var f:=_fixture("single")
	var state: Dictionary=f.stage._state.duplicate(true)
	state.party["1"].protecting_ally_id=0
	f.stage._state=state
	var entry={"actor":"boss","action":"attack","target":1,"visual_original_target":0,"amount":20,"attribute":"ICE"}
	f.stage.play_entry(entry)
	assert_eq(f.stage._guards,["1"])
	var d=f.stage._skill_presentation
	assert_true(d is Driver)
	assert_eq(d.kind,"single")
	f.stage._tween.custom_step(.85)
	var chest: Vector2=f.stage._foot("1")-Vector2(0,f.stage.Assets.display_height("butler")*.52)+Vector2(23,0)
	assert_lt(d.motion.contact.distance_to(chest),1.0)
	f.stage.cancel()
	for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_real_single_and_aoe_counter_complete_with_one_combined_entry() -> void:
	for kind in ["single","aoe"]:
		var f:=_fixture(kind,"FIRE",true)
		var count:=int(f.entry.get("counter",false))
		for hit in f.entry.get("hits",{}).values(): count+=int(hit.get("counter",false))
		assert_eq(count,1,"Exactly one real samurai counter")
		var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(1.3)
		assert_eq(seen.size(),0)
		for i in range(160):
			if not f.stage.is_playing(): break
			f.stage._tween.custom_step(.1)
		assert_eq(seen.size(),1)
		assert_eq(seen[0],f.entry)
		assert_false(f.stage.is_playing())
		assert_null(f.stage._skill_presentation)
		assert_false(f.stage._samurai_wind.visible)
		assert_eq(f.session.battle.snapshot(),snapshot)
		assert_eq(f.stage._visuals["boss"].scale,Vector2.ONE)
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

