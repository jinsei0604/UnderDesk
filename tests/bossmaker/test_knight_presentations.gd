extends GutTest
const Driver=preload("res://src/bossmaker/visuals/rbm_knight_presentation.gd")
const Palette=preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_knight_vfx.gd")

func _fixture(kind: String,attribute: String="NEUTRAL",counter: bool=false) -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="Knight QA"
	draft.hp=3000
	draft.atk=40
	draft.spd=1
	var ids: Array=["samurai"] if counter and kind=="single" else (["samurai","hero","healer","butler"] if counter else ["hero","butler","healer","samurai"])
	for id in ids: draft.add_party_character(id)
	var spec={"name":"Knight QA skill","type":"attack","target":"all" if kind=="aoe" else "single","attribute":attribute,"atk_multiplier":1.0}
	if kind in ["buff","heal"]:
		spec={"name":"Knight support","type":"self_heal" if kind=="heal" else "atk_self_buff","heal_amount":200,"buff_multiplier":1.3,"duration_turns":3}
	var id:=draft.add_skill(spec)
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),5)
	session.battle.boss.hp=1500
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_knight")
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

func test_attack_palette_contact_and_approved_followthrough() -> void:
	for kind in ["single","aoe"]:
		for attribute in Palette.COLORS:
			var f:=_fixture(kind,attribute)
			assert_false(f.entry.is_empty())
			var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			assert_true(driver is Driver)
			assert_eq(driver.kind,kind)
			assert_eq(Palette.color_for(driver._vfx.attack_attribute),Palette.COLORS[attribute])
			f.stage._tween.custom_step(driver.impact_time-.01)
			assert_eq(seen.size(),0)
			f.stage._tween.custom_step(.02)
			assert_eq(seen.size(),1)
			assert_eq(seen[0],f.entry)
			if kind=="single":
				var tip: Vector2=f.stage._foot("boss")+driver.Motion.SWORD_TIP
				assert_lt(tip.distance_to(driver.motion.contact),1.0)
				f.stage._tween.custom_step(1.20-driver.age)
				assert_gt(f.stage._visuals["boss"].scale.x,0.0,"Single return does not turn away")
			else:
				assert_eq(f.entry.get("hits",{}).size(),4)
				assert_eq(f.stage._poses["boss"],3,"Sword follows through to the right")
				assert_true(driver._pose_layer.visible)
				assert_false(f.stage._visuals["boss"].visible)
				f.stage._tween.custom_step(1.47-driver.age)
				assert_eq(f.stage._foot("boss"),driver.motion.home)
				assert_true(f.stage._visuals["boss"].visible)
			f.stage._tween.custom_step(4)
			assert_eq(seen.size(),1)
			assert_null(f.stage._skill_presentation)
			assert_eq(f.stage._visuals["boss"].scale,Vector2.ONE)
			assert_eq(f.stage._visuals["boss"].pivot_offset,Vector2.ZERO)
			assert_true(f.stage._visuals["boss"].visible)
			assert_eq(f.session.battle.snapshot(),snapshot)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_support_motion_shared_and_colors_ignore_attack_attribute() -> void:
	var reference: Array=[]
	for kind in ["buff","heal"]:
		for attribute in ["FIRE","ICE","WIND"]:
			var f:=_fixture(kind,attribute)
			var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			assert_eq(driver.kind,kind)
			assert_eq(VFX.SUPPORT[driver._vfx.kind],Color("ef4847") if kind=="buff" else Color("71da87"))
			var poses: Array=[]
			for i in range(170):
				f.stage._tween.custom_step(1.0/60)
				poses.append(f.stage._poses["boss"])
			if reference.is_empty(): reference=poses
			else: assert_eq(poses,reference)
			assert_eq(f.stage._poses["boss"],0)
			f.stage._tween.custom_step(1)
			assert_eq(seen.size(),1)
			assert_null(f.stage._skill_presentation)
			assert_eq(f.session.battle.snapshot(),snapshot)

func test_cancel_and_replay_including_composite_followthrough() -> void:
	for kind in ["single","aoe","buff","heal"]:
		for elapsed in [.1,.45,.70,1.20,1.55]:
			var f:=_fixture(kind)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			f.stage._tween.custom_step(elapsed)
			var count:=seen.size()
			f.stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(driver))
			assert_eq(seen.size(),count)
			assert_eq(f.stage._visuals["boss"].scale,Vector2.ONE)
			assert_eq(f.stage._visuals["boss"].pivot_offset,Vector2.ZERO)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
			f.stage.play_entry(f.entry,f.skill)
			f.stage._tween.custom_step(4)
			assert_eq(seen.size(),count+1)

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

func test_cover_redirected_target_and_normal_attack_use_slash() -> void:
	var f:=_fixture("single")
	var state: Dictionary=f.stage._state.duplicate(true)
	state.party["1"].protecting_ally_id=0
	f.stage._state=state
	var entry={"actor":"boss","action":"attack","target":1,"visual_original_target":0,"amount":20,"attribute":"ICE"}
	f.stage.play_entry(entry)
	assert_eq(f.stage._guards,["1"])
	var driver=f.stage._skill_presentation
	assert_eq(driver.kind,"single")
	f.stage._tween.custom_step(.85)
	var chest: Vector2=f.stage._foot("1")-Vector2(0,f.stage.Assets.display_height("butler")*.55)+Vector2(6,0)
	assert_lt(driver.motion.contact.distance_to(chest),1.0)
	assert_lt((f.stage._foot("boss")+driver.Motion.SWORD_TIP).distance_to(chest),1.5)
	f.stage.cancel()
	for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_overhead_horizontal_and_no_right_facing_support_poses() -> void:
	var motion=Driver.Motion.new()
	assert_eq(motion.sample("single",.30).pose,9)
	assert_eq(motion.sample("aoe",.30).pose,4)
	assert_eq(motion.sample("aoe",.67).pose,5)
	assert_eq(motion.sample("aoe",1.0).pose,3)
	for i in range(180):
		var t:=i/60.0
		var buff: Dictionary=motion.sample("buff",t)
		assert_eq(buff,motion.sample("heal",t))
		assert_true(buff.pose in [0,8])
		assert_false(buff.flip)
