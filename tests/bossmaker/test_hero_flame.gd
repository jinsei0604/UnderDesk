extends GutTest
const Flame=preload("res://src/bossmaker/visuals/rbm_hero_flame.gd")
const Aura=preload("res://src/bossmaker/visuals/rbm_hero_sword_aura.gd")
var held: Array=[]

func before_all() -> void:
	for path in preload("res://src/bossmaker/visuals/rbm_hero_burst.gd").warm_paths("hero",""): held.append(load(path))

func _fixture() -> Dictionary:
	var draft:=RBMCreatorDraft.new()
	draft.boss_name="持続炎の確認"
	draft.hp=99999
	draft.atk=1
	draft.spd=1
	draft.add_party_character("hero")
	var attack_id:=draft.add_skill({"name":"攻撃","type":"attack","target":"single","attribute":"NEUTRAL","atk_multiplier":1.0})
	draft.normal_actions_enabled=true
	draft.normal_action_percentages[attack_id]=100.0
	var session:=RBMCreatorTestSession.new(draft.to_definition(),31)
	var stage:=RBMBattleStage.new()
	stage.size=Vector2(1280,720)
	stage.set_meta("fullscreen_formation",true)
	add_child_autofree(stage)
	stage.configure(session.battle,"")
	stage.set_state(session.battle.presentation_state())
	var aura: Node2D
	for child in stage._visuals["0"].get_children():
		if child.get_script()==Aura: aura=child
	return {"session":session,"stage":stage,"aura":aura}

func test_flame_begins_at_real_buff_impact_not_resolution_or_cast_start() -> void:
	var f:=_fixture()
	var before: Dictionary=f.session.battle.presentation_state()
	var entries: Array=f.session.battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_flame_wrap"})
	var final_snapshot: Dictionary=f.session.battle.snapshot()
	var presenter:=RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled=true
	presenter.setup(f.stage)
	presenter.play(entries,f.session.battle,before)
	f.stage._tween.custom_step(0.59)
	assert_false(Flame.is_active(f.stage._state,"0"),"Resolved future buff must not appear early")
	f.stage._tween.custom_step(0.02)
	assert_true(Flame.is_active(f.stage._state,"0"))
	f.stage._tween.custom_step(0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(f.aura.visible)
	f.stage.cancel()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(f.aura.visible,"Cancelling a visual does not remove an already committed buff")
	assert_eq(f.session.battle.snapshot(),final_snapshot)
	f.stage.set_state(before)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(f.aura.visible,"Rewind before application removes flame")
	f.stage.set_state(entries[0].visual_state)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(f.aura.visible,"Restoring a buffed snapshot restores flame")

func test_actual_three_turn_expiry_reapply_and_removal() -> void:
	var f:=_fixture()
	var battle: RBMBattle=f.session.battle
	battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_flame_wrap"})
	var applied:=battle.current_turn
	var buffed:=battle.presentation_state()
	for i in range(4):
		while battle.current_turn<applied+i:
			battle.advance_to_next_decision()
			if battle.current_turn<applied+i: battle.resolve_pending_ally_action({"type":"defend"})
		f.stage.set_state(battle.presentation_state())
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(f.aura.visible,i<3,"Actual turn "+str(battle.current_turn))
		assert_eq(Flame.is_active(f.stage._state,"0"),RBMConstants.timed_effect_active(battle.party[0].timed_effects,"atk_buff",battle.current_turn))
	assert_true(battle.party[0].timed_effects.has("atk_buff"),"Expired dictionary entry alone must not keep flame alive")
	battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_flame_wrap"})
	f.stage.set_state(battle.presentation_state())
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(f.aura.visible,"Reapplication after expiry")
	f.stage.set_state(buffed)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(f.aura.visible,"Rewind to an active turn")
	var removed:=buffed.duplicate(true)
	removed.party["0"].timed_effects.clear()
	f.stage.set_state(removed)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(f.aura.visible,"State with removed effect")

func test_weapon_flame_tracks_run_swing_return_without_changing_neutral_attack() -> void:
	var f:=_fixture()
	var battle: RBMBattle=f.session.battle
	battle.resolve_pending_ally_action({"type":"skill","skill_id":"hero_flame_wrap"})
	battle.advance_to_next_decision()
	f.stage.set_state(battle.presentation_state())
	var entries:=battle.resolve_pending_ally_action({"type":"attack"})
	var snapshot:=battle.snapshot()
	f.stage.play_entry(entries[0])
	var action: Node2D=f.stage._skill_presentation
	for t in [0.10,0.20,0.28,0.38,0.52,0.64]:
		action._advance(t)
		assert_true(action._frame>=0)
		assert_gt(action._sword_hand().distance_to(action._sword_tip()),20.0)
		assert_lt(action._sword_hand().distance_to(action._sword_tip()),65.0)
		assert_true(Flame.is_active(f.stage._state,"0"))
	for cue in f.stage._sound.history: assert_false(cue.begins_with("fire"),"Persistent buff has no repeated or extra fire sounds")
	f.stage.cancel()
	assert_eq(battle.snapshot(),snapshot)
	assert_false(Flame.is_active({"party":{"0":{"character_id":"butler","timed_effects":{"atk_buff":{"applied_at_turn":1,"duration_turns":3}}}},"turn":1},"0"))
