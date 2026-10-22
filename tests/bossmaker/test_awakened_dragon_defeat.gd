extends GutTest
const Victory = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")

func test_refresh_cannot_resurrect_the_awakened_aura_during_defeat_or_result(params=use_parameters(["dragon","musha","astronaut","gentleman"])) -> void:
	var boss: String = params
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_"+boss
	draft.boss_name = "Defeat refresh regression"
	draft.hp = 1
	draft.spd = 1
	for id in ["hero","butler","healer","samurai"]: draft.add_party_character(id)
	var id := draft.add_skill({"name":"attack","type":"attack","target":"single","attribute":"NEUTRAL","atk_multiplier":1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	view.start_battle(draft.to_definition(),RBMBattleUiKit.ALL_VISIBLE,"appearance_"+boss)
	view.session.battle.is_awakened = true
	var snapshot: Dictionary = view.session.battle.presentation_state()
	var st = view._battlefield_ally_row.get_meta("visual_stage")
	st.set_state(snapshot)
	var aura = st.get("_"+boss+"_aura")
	var original_process: bool = aura.is_processing()
	var original_visibility: bool = aura.visible
	assert_true(original_visibility)
	var player = Victory.new()
	player.boss = boss+"_awakened"
	player.setup(st,view,st.get_meta("battle_hud") if st.has_meta("battle_hud") else null,view._encounter.audio)
	player.on_final_impact()
	st.set_state(snapshot)
	assert_false(aura.visible,"final-hit refresh must not resurrect the aura")
	player.begin()
	player._process(2.65)
	st.set_state(snapshot)
	assert_true(player.defeat.gone)
	assert_false(st._visuals.boss.visible,"original actor stays hidden")
	assert_false(aura.visible,"victory refresh must not resurrect the aura")
	player._process(4.0)
	player._process(0.3)
	st.set_state(snapshot)
	assert_false(aura.visible,"result refresh must not resurrect the aura")
	if boss == "musha":
		st._musha_ink._refresh()
		for canvas in [st._musha_ink.back,st._musha_ink.mid,st._musha_ink.top]:
			assert_false(canvas.disp.visible,"ink must remain hidden")
			assert_eq(canvas.vp.render_target_update_mode,SubViewport.UPDATE_DISABLED)
		assert_false(st._musha_idle.visible)
		assert_false(aura._allies_on)
	assert_false(st._visuals.boss.visible)
	var volume_ref: WeakRef
	if boss != "dragon":
		assert_eq(player.defeat.field.viewport.render_target_update_mode,SubViewport.UPDATE_DISABLED,"finished volume stops rendering")
		volume_ref = weakref(player.defeat.field.viewport)
	player.cancel()
	await get_tree().process_frame
	if volume_ref != null:
		assert_null(volume_ref.get_ref(),"cancellation releases the defeat viewport")
	assert_eq(aura.is_processing(),original_process)
	assert_eq(aura.visible,original_visibility)
	if boss == "astronaut":
		assert_true(is_instance_valid(aura._layer),"cancel restores the discarded aura viewport")
	aura.refresh()
	assert_true(aura.visible,"a new battle can show the aura again")
	if boss == "musha":
		assert_true(st._musha_ink.is_processing())
		assert_true(st._musha_idle.is_processing())
		assert_eq(st._musha_ink.back.vp.render_target_update_mode,SubViewport.UPDATE_ALWAYS)
