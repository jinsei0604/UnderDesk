extends GutTest
## Limited integration coverage for the plush's production presentation contract.
const Driver = preload("res://src/bossmaker/visuals/plush/rbm_plush_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
## 演出の契約は、事前読み込みが素材を読み終えた状態で検証する(QA-06。読み終えていない時の待ちは
## test_rbm_presentation_warmup.gd が検証する)。
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["plush"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_plush"
	draft.boss_name = "Plush QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "Plush QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Plush support", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_mode": "fixed", "heal_fixed_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_plush")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		var entries := session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)
	if kind in ["buff", "heal"]: skill.attribute = attribute
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

func test_native_actions_damage_numbers_and_no_battle_mutation() -> void:
	for aw in [false,true]:
		for kind in ["single","aoe","buff","heal"]:
			for attribute in Palette.COLORS:
				var f:=_fixture(kind,attribute,aw)
				var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
				var seen: Array=[]
				f.stage.impact.connect(func(e):seen.append(e))
				f.stage.play_entry(f.entry,f.skill)
				var d=f.stage._skill_presentation
				assert_true(d is Driver)
				if not d is Driver:continue
				assert_eq(d.form,"awakened" if aw else "normal")
				f.stage._tween.custom_step(d.impact_time-.01)
				assert_eq(seen.size(),0,"No damage before contact")
				assert_eq(f.stage._damage_numbers._numbers.size(),0)
				f.stage._tween.custom_step(.02)
				if kind=="single" and not aw:
					var fist: Vector2=d._body.boss+Vector2(d._body.frame_record.far_hand[0],d._body.frame_record.far_hand[1])
					assert_lt(fist.distance_to(d._body.target_foot()+Vector2(0,-43)),2.0,"Swollen fist reaches resolved target")
				assert_eq(seen.size(),1)
				var numbers: Array=f.stage._damage_numbers._numbers
				assert_eq(numbers.size(),4 if kind=="aoe" else (0 if kind=="buff" else 1))
				for n in numbers:
					var hit: Dictionary=f.entry.get("hits",{}).get(int(n.key),f.entry)
					assert_eq(n.text,("+" if kind=="heal" else "")+str(int(hit.get("amount",0))))
				assert_lt(d._body.screen_fx.z_index,f.stage._damage_numbers.z_index)
				assert_lt(d._body.space.z_index,f.stage._damage_numbers.z_index)
				if kind=="single":
					var target: String=f.stage._targets[0]
					assert_eq(d._body.target_foot(),(f.stage._homes[target]+f.stage._visuals[target].foot_position()).round())
				f.stage._tween.custom_step(20)
				assert_eq(seen.size(),1)
				assert_false(f.stage.is_playing())
				assert_null(f.stage._skill_presentation)
				assert_eq(f.session.battle.snapshot(),snapshot)
				assert_true(f.stage._visuals.boss.visible)
				assert_eq(f.stage.scale,Vector2.ONE)
				for key in f.stage._homes:assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
				f.stage.queue_free()
				await get_tree().process_frame

func test_cancel_before_and_after_impact_and_counter() -> void:
	for aw in [false,true]:
		for kind in ["single","aoe","heal","buff"]:
			for fraction in [.1,.55,.9]:
				var f:=_fixture(kind,"WIND",aw)
				f.stage.play_entry(f.entry,f.skill)
				var d=f.stage._skill_presentation
				f.stage._tween.custom_step(d.duration*fraction)
				f.stage.cancel()
				await get_tree().process_frame
				assert_false(is_instance_valid(d))
				assert_true(f.stage._visuals.boss.visible)
				assert_eq(f.stage.scale,Vector2.ONE)
				assert_false(f.stage.is_playing())
				f.stage.queue_free()
				await get_tree().process_frame
	for aw in [false,true]:
		for kind in ["single","aoe"]:
			var f:=_fixture(kind,"NEUTRAL",aw,true)
			var seen: Array=[]
			f.stage.impact.connect(func(e):seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			assert_false(f.stage._counters.is_empty())
			f.stage._tween.custom_step(30)
			assert_eq(seen.size(),1)
			assert_false(f.stage.is_playing())
			f.stage.queue_free()
			await get_tree().process_frame

func test_selection_save_reload_custom_awakening_and_real_trigger() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("user://plush_integration_roundtrip")
	var creator:=RBMCreatorMain.new()
	add_child_autofree(creator)
	var d=creator.draft
	d.appearance_id="appearance_plush";d.boss_name="ぬいぐるみ本番統合";d.hp=400;d.atk=17;d.spd=1
	d.add_party_character("hero")
	d.add_skill({"name":"つめ","type":"attack","target":"single","attribute":"ICE","atk_multiplier":1.73})
	d.set_awakening({"conditions":[{"type":"hp_at_most","percent":61.0}],"condition_logic":"AND","buff":{"buff_multiplier":1.7,"duration_turns":4},"heal":{"heal_mode":"fixed","heal_fixed_amount":77,"heal_percent":0.0}})
	var before: Dictionary=d.to_definition().duplicate(true)
	var saved: Dictionary=creator.press_save_as_new()
	assert_true(saved.get("ok",false))
	var loaded:=RBMCreatorMain.new();add_child_autofree(loaded)
	assert_true(loaded.start_loaded(str(saved.stage_id)).get("ok",false))
	assert_eq(loaded.draft.appearance_id,"appearance_plush")
	assert_eq(loaded.draft.awakening,d.awakening)
	assert_eq(loaded.draft.to_definition(),before)
	var picker:=RBMCreatorAppearancePicker.new();add_child_autofree(picker)
	picker.open("")
	assert_true(picker._entry_buttons.has("appearance_plush"))
	picker._entry_buttons["appearance_plush"].pressed.emit()
	assert_true(picker.find_child("AwakenedPreviewToggle",true,false).visible)
	assert_false(picker.find_child("AwakenedPreviewToggle",true,false).disabled)
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_plush"))
	assert_true(RBMVisualAssets.has_awakened_design("plush"))
	var session:=RBMCreatorTestSession.new(loaded.draft.to_definition(),1)
	var stage:=RBMBattleStage.new();stage.size=Vector2(1280,720);stage.set_meta("fullscreen_formation",true);add_child_autofree(stage)
	stage.configure(session.battle,"appearance_plush");stage.set_state(session.battle.presentation_state())
	var entry: Dictionary={}
	for e in session.resolve_ally_action({"type":"attack"}):
		if str(e.get("action",""))=="awakening":entry=e
	assert_false(entry.is_empty())
	var seen: Array=[];stage.impact.connect(func(e):seen.append(e);stage.set_state(e.visual_state))
	stage.play_entry(entry)
	assert_true(stage._skill_presentation is Driver)
	stage._tween.custom_step(stage._skill_presentation.impact_time-.01)
	assert_eq(stage._asset_ids.boss,"plush")
	stage._tween.custom_step(.02)
	assert_eq(stage._asset_ids.boss,"plush_awakened")
	assert_eq(seen.size(),0)
	stage._tween.custom_step(9)
	assert_eq(seen.size(),1)
	assert_eq(stage._asset_ids.boss,"plush_awakened")
	assert_eq(stage.scale,Vector2.ONE)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func test_real_cover_aims_at_the_redirected_guard_and_keeps_damage() -> void:
	var review=load("res://tools/verify_tank_actions_gpu.gd")
	for awakened in [false,true]:
		var cover: Dictionary=review.cover_fixture("ICE")
		assert_false(cover.is_empty())
		var session:=RBMCreatorTestSession.new(review.definition_for(),20260906)
		session.battle.restore(cover.snapshot)
		var before: Dictionary=cover.before.duplicate(true)
		before.is_awakened=awakened
		var stage:=RBMBattleStage.new();stage.size=Vector2(1280,720);stage.set_meta("fullscreen_formation",true);add_child_autofree(stage)
		stage.configure(session.battle,"appearance_plush");stage.set_state(before)
		var seen: Array=[];stage.impact.connect(func(e):seen.append(e))
		var skill:=RBMBattleUiKit.find_skill_for_actor("boss",str(cover.entry.skill_id),session.battle)
		stage.play_entry(cover.entry,skill)
		assert_eq(stage._guards,["3"])
		var d=stage._skill_presentation
		var target: Vector2=stage._foot("0")+Vector2(44,-4)
		assert_eq(d._body.target_foot(),target)
		stage._tween.custom_step(d.impact_time+.02)
		assert_eq(stage._foot("3"),target)
		assert_eq(stage._damage_numbers._numbers.size(),1)
		assert_eq(stage._damage_numbers._numbers[0].key,"3")
		assert_eq(stage._damage_numbers._numbers[0].text,str(cover.entry.amount))
		stage._tween.custom_step(20)
		assert_eq(seen,[cover.entry]);assert_eq(session.battle.snapshot(),cover.snapshot)
		assert_eq(stage._visuals["3"].position,stage._homes["3"])
		stage.queue_free();await get_tree().process_frame

func test_plain_attack_and_rewind_restore_the_approved_static_forms() -> void:
	var f:=_fixture("single")
	var entry:={"actor":"boss","action":"attack","target":0,"amount":31}
	var seen: Array=[];f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry(entry)
	assert_true(f.stage._skill_presentation is Driver)
	f.stage._tween.custom_step(4)
	assert_eq(seen,[entry])
	var before: Dictionary=f.stage._state.duplicate(true)
	var awakened: Dictionary=before.duplicate(true);awakened.is_awakened=true
	f.stage.set_state(awakened)
	assert_eq(f.stage._asset_ids.boss,"plush_awakened")
	f.stage.set_state(before)
	assert_eq(f.stage._asset_ids.boss,"plush")
	assert_eq(f.stage._visuals.boss._pixel_scale,1.0)
	f.stage.play_entry({"actor":"boss","action":"awakening"})
	f.stage._tween.custom_step(f.stage._skill_presentation.impact_time+.25)
	assert_eq(f.stage._asset_ids.boss,"plush_awakened")
	f.stage.cancel()
	assert_eq(f.stage._asset_ids.boss,"plush")
	assert_eq(f.stage.scale,Vector2.ONE)
	assert_true(f.stage._visuals.boss.visible)

func test_v7_grab_and_darkness_cancel_restore_actual_party_visuals() -> void:
	for kind in ["single","aoe"]:
		for moment in [1.9,2.4,4.2]:
			var f:=_fixture(kind,"NEUTRAL",true)
			var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
			var original: Dictionary={}
			for id in f.stage._visuals:
				var actor=f.stage._visuals[id]
				original[id]={"color":actor.modulate,"z":actor.z_index,"relative":actor.z_as_relative}
			f.stage.play_entry(f.entry,f.skill)
			var driver=f.stage._skill_presentation
			f.stage._tween.custom_step(moment)
			if kind=="single" and moment==1.9:
				var id: String=f.stage._targets[0]
				assert_lt(f.stage._visuals[id].position.y,f.stage._homes[id].y-60,"Resolved victim visibly lifted before the slam")
				assert_eq(f.stage._damage_numbers._numbers.size(),0,"Grab is visual; damage waits for the slam")
			if kind=="aoe" and moment==2.4:
				for id in f.stage._targets:
					assert_lt(f.stage._visuals[id].z_index,90,"Party stays hidden underneath the opaque veil")
				assert_lt(driver._body.dark_front.z_index,f.stage._damage_numbers.z_index)
			f.stage.cancel()
			await get_tree().process_frame
			for id in original:
				assert_eq(f.stage._visuals[id].modulate,original[id].color)
				assert_eq(f.stage._visuals[id].z_index,original[id].z)
				assert_eq(f.stage._visuals[id].z_as_relative,original[id].relative)
				assert_eq(f.stage._visuals[id].position,f.stage._homes[id])
			assert_eq(f.session.battle.snapshot(),snapshot)
			assert_eq(f.stage.scale,Vector2.ONE)
			f.stage.queue_free()
			await get_tree().process_frame

func test_v9_awakening_silent_blackout_one_sting_and_cancel() -> void:
	for moment in [2.85,3.42,4.2]:
		var f:=_fixture("single")
		var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
		f.stage.play_entry({"actor":"boss","action":"awakening"})
		var d=f.stage._skill_presentation
		f.stage._tween.custom_step(moment)
		if moment==2.85:
			assert_eq(d._body.blackout(),1.0)
			assert_false(d._body.sound_marks.has("loom"),"Silence precedes the face")
			assert_false(d._revealed)
		else:
			assert_true(d._body.sound_marks.has("loom"))
			var voice: int=d._body.audio._next
			f.stage._tween.custom_step(.01)
			assert_eq(d._body.audio._next,voice,"The jolt plays once, never every frame")
		f.stage.cancel()
		for player in d._body.audio._players:assert_false(player.playing)
		assert_eq(f.stage._asset_ids.boss,"plush")
		assert_true(f.stage._visuals.boss.visible)
		assert_eq(f.stage.scale,Vector2.ONE)
		assert_eq(f.session.battle.snapshot(),snapshot)
		f.stage.queue_free();await get_tree().process_frame

func test_v9_rush_has_one_final_damage_event_and_hits_every_resolved_target() -> void:
	var f:=_fixture("aoe","NEUTRAL",true)
	var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
	var seen: Array=[];f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry(f.entry,f.skill)
	var d=f.stage._skill_presentation
	var previous:=0.0;var visited: Dictionary={}
	for moment in [2.36,2.58,2.77,2.94,3.10,3.25,3.39,3.52,3.64,3.76,3.88,4.00]:
		f.stage._tween.custom_step(moment-previous);previous=moment
		assert_eq(seen.size(),0,"Visual rush does not multiply combat hits")
		assert_eq(f.stage._damage_numbers._numbers.size(),0)
		for id in f.stage._targets:
			if f.stage._visuals[id].position!=f.stage._homes[id]:visited[id]=true
	assert_eq(visited.size(),4,"All four real party visuals react during the rush")
	f.stage._tween.custom_step(d.impact_time-previous+.02)
	assert_eq(seen,[f.entry]);assert_eq(f.stage._damage_numbers._numbers.size(),4)
	f.stage._tween.custom_step(3)
	assert_eq(seen.size(),1);assert_eq(f.session.battle.snapshot(),snapshot)

func test_v9_complete_black_then_face_and_sound_share_the_same_update() -> void:
	var approved_path:="res://assets_bossmaker/battle/plush/v12/audio/awakening_scream.wav"
	assert_has(Driver.warm_paths("plush","awakening"),approved_path,"Approved scream is loaded before the cue")
	var f:=_fixture("single")
	f.stage.play_entry({"actor":"boss","action":"awakening"})
	var d=f.stage._skill_presentation
	f.stage._tween.custom_step(2.5)
	assert_eq(d._body.camera.zoom,2,"V7 anticipation retains its integer zoom")
	f.stage._tween.custom_step(.8)
	assert_eq(d._body.blackout(),1.0)
	assert_false(d._body.face_visible())
	assert_false(d._body.sound_marks.has("loom"))
	for player in d._body.audio._players:assert_false(player.playing,"Complete black contains silence")
	f.stage._tween.custom_step(.101)
	assert_eq(d._body.blackout(),0.0,"Background returns in the first face update")
	assert_true(d._body.face_visible())
	assert_true(d._body.sound_marks.has("loom"),"Sound and face use the identical JUMP boundary")
	assert_eq(d._body.sound_streams["loom_jolt_v9"].resource_path,approved_path,"The approved human-voice scream replaces only the old audio asset")
	assert_almost_eq(d._body.sound_streams["loom_jolt_v9"].get_length(),1.20,.001)
	assert_eq(d._body.camera.zoom,1,"No slow face zoom")
	f.stage.cancel()
	assert_eq(f.stage.scale,Vector2.ONE)

func test_v11_preparation_then_rush_and_cancel_restore_the_original_view() -> void:
	for moment in [.65,1.55,2.36,3.40,4.49,5.8]:
		var f:=_fixture("aoe","NEUTRAL",true)
		var before: Dictionary=f.session.battle.snapshot().duplicate(true)
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		f.stage._tween.custom_step(moment)
		if moment==.65:
			assert_eq(d._body.blackout(),0.0,"Belly anomaly is visible before darkness starts")
			assert_eq(f.stage._damage_numbers._numbers.size(),0)
		if moment==1.55:
			assert_gt(d._body.blackout(),0.0)
			assert_lt(d._body.blackout(),1.0,"Darkness spreads progressively, not an instant screen cut")
		if moment==2.36:
			var pose: Dictionary=d._body.combo_state()
			assert_false(pose.is_empty(),"A body and connected arm share the same attack pose")
			assert_lt(Vector2(pose.body).distance_to(Vector2(pose.origin)),100.0)
			assert_eq(Vector2(pose.body),d._body.home,"V12: the bear stays at its original position")
		f.stage.cancel()
		assert_eq(f.session.battle.snapshot(),before)
		assert_true(f.stage._visuals.boss.visible)
		assert_eq(f.stage.scale,Vector2.ONE)
		for player in d._body.audio._players:assert_false(player.playing)
		f.stage.queue_free();await get_tree().process_frame

func test_v12_stationary_body_and_connected_arm_reach_strike_and_recovery() -> void:
	var f:=_fixture("aoe","NEUTRAL",true)
	f.stage.play_entry(f.entry,f.skill)
	var d=f.stage._skill_presentation
	var body=d._body
	assert_eq(d.duration,6.6,"V11 duration stays unchanged")
	assert_eq(d.impact_time,4.48,"Damage still uses the approved final hit")
	var reached: Array=[]
	for hit in body.HITS:
		var positions: Array=[]
		for offset in [-.05,-.025,0.0,.02,.05]:
			body.show_action("awakened_all",float(hit)+offset)
			var state: Dictionary=body.combo_state()
			assert_false(state.is_empty())
			assert_eq(state.body,body.home,"No body translation at any rush frame")
			assert_eq(state.pose,5.8,"The body pose never becomes a whole-body attack")
			assert_eq(state.origin,body.home+Vector2(1,-86),"Arm stays attached to the fixed shoulder")
			positions.append(state.hand)
			if offset==0.0:reached.append(state.hand)
		assert_gt(Vector2(positions[1]).distance_to(positions[2]),20.0,"Arm swings down before contact")
		assert_gt(Vector2(positions[2]).distance_to(positions[4]),20.0,"Arm visibly returns after contact")
	for target in body.HOMES.values():assert_has(reached,target+Vector2(0,-32),"Every resolved party position is struck")
	body.show_action("awakened_all",4.48)
	assert_eq(body.combo_state().body,body.home,"Finisher also leaves body fixed")
	assert_lt(body.BODY_TINT.r,.25)
	assert_lt(body.RUSH_TINT.r,.30)
	f.stage.cancel()
