extends GutTest
const Support=preload("res://src/bossmaker/visuals/rbm_golem_support.gd")
const VFX=preload("res://src/bossmaker/visuals/rbm_boss_support_vfx.gd")
## ゴーレム専用の演出(単体・全体・支援)。他のボスには選ばれてはいけない。
const GOLEM_PRESENTATIONS=[preload("res://src/bossmaker/visuals/rbm_golem_single_punch.gd"),preload("res://src/bossmaker/visuals/rbm_golem_ground_slam.gd"),preload("res://src/bossmaker/visuals/rbm_golem_support.gd")]

func _is_golem_presentation(presentation) -> bool:
	return is_instance_valid(presentation) and GOLEM_PRESENTATIONS.has(presentation.get_script())

func _fixture(mode: String) -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="Support QA"
	draft.hp=3000
	draft.spd=1
	draft.add_party_character("hero")
	var id:=draft.add_skill({"name":"Support","type":"self_heal" if mode=="heal" else "atk_self_buff","heal_amount":200,"buff_multiplier":1.3,"duration_turns":3})
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),5)
	session.battle.boss.hp=1500
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"appearance_golem")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary={}
	for attempt in range(12):
		var entries:=session.resolve_ally_action({"type":"defend"})
		for e in entries:
			if str(e.get("actor"))=="boss": entry=e
		if not entry.is_empty(): break
	return {"stage":stage,"session":session,"entry":entry,"skill":RBMBattleUiKit.find_skill_for_actor("boss",id,session.battle)}

func test_real_support_one_event_same_motion_and_attribute_independent_color() -> void:
	var reference: Array=[]
	for mode in ["buff","heal"]:
		for attribute in ["NEUTRAL","FIRE","ICE","LIGHTNING","WIND","UNKNOWN"]:
			var f:=_fixture(mode)
			assert_false(f.entry.is_empty())
			var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
			f.skill.attribute=attribute
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			assert_eq(driver.get_script(),Support)
			assert_eq(driver.mode,mode)
			assert_eq(VFX.COLORS[driver._vfx.mode],Color("ef4847") if mode=="buff" else Color("71da87"))
			var poses: Array=[]
			for i in range(168):
				f.stage._tween.custom_step(1.0/60)
				poses.append(f.stage._poses["boss"])
				if i==85: assert_eq(seen.size(),0)
				if i==95: assert_eq(seen.size(),1)
			if reference.is_empty(): reference=poses
			else: assert_eq(poses,reference,"Both actions and all attributes share the same motion")
			for p in poses.slice(132): assert_eq(p,0,"No second crouch after returning from the upright pose")
			f.stage._tween.custom_step(1)
			assert_eq(seen.size(),1)
			assert_eq(seen[0],f.entry)
			assert_null(f.stage._skill_presentation)
			assert_eq(f.session.battle.snapshot(),snapshot)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_cancel_then_replay_cleans_every_phase() -> void:
	for mode in ["buff","heal"]:
		for elapsed in [.2,.8,1.6,2.3,2.75]:
			var f:=_fixture(mode)
			var events: Array=[]
			f.stage.impact.connect(func(e):events.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			f.stage._tween.custom_step(elapsed)
			var count:=events.size()
			f.stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(driver))
			assert_eq(events.size(),count)
			assert_eq(f.stage._poses["boss"],0)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
			f.stage.play_entry(f.entry,f.skill)
			f.stage._tween.custom_step(3)
			assert_eq(events.size(),count+1)

func test_other_boss_keeps_existing_support() -> void:
	for mode in ["buff","heal"]:
		var f:=_fixture(mode)
		f.stage.configure(f.session.battle,"appearance_dragon")
		f.stage.play_entry(f.entry,f.skill)
		# 竜は自分の専用演出を持つようになった(以前の「竜はnull」の前提は古い)。確かめるのは、
		# 他のボスの強化・回復にゴーレムの演出が選ばれないこと。
		assert_false(_is_golem_presentation(f.stage._skill_presentation),"another boss's %s never uses a golem presentation"%mode)
		f.stage.cancel()
		await get_tree().process_frame
