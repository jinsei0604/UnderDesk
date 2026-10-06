extends GutTest
const Driver = preload("res://src/bossmaker/visuals/rbm_astronaut_presentation.gd")
const Timeline = preload("res://src/bossmaker/visuals/rbm_astronaut_timeline.gd")
func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_astronaut"
	draft.boss_name = "宇宙飛行士"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "宇宙飛行士 skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "宇宙装備", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
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
	stage.configure(session.battle, "appearance_astronaut")
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


func after_each() -> void:
	await get_tree().process_frame

func test_four_attacks_deliver_exactly_one_resolved_impact_and_restore() -> void:
	for awakened in [false,true]:
		for kind in ["single","aoe"]:
			var f := _fixture(kind,"NEUTRAL",awakened)
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d.action_kind,("planet" if kind=="single" else "blackhole") if awakened else ("single" if kind=="single" else "all"))
			f.stage._tween.custom_step(d.impact_time-.01)
			assert_eq(seen.size(),0)
			f.stage._tween.custom_step(.02)
			assert_eq(seen.size(),1)
			assert_eq(seen[0],f.entry)
			f.stage._tween.custom_step(20)
			assert_eq(seen.size(),1)
			assert_false(f.stage.is_playing())
			assert_null(f.stage._skill_presentation)
			assert_eq(f.stage._visuals.boss.z_index,1)
			for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])
			assert_eq(f.session.battle.snapshot(),snapshot)

func test_blackhole_center_is_party_center_and_cancellation_restores_every_layer() -> void:
	var f := _fixture("aoe","NEUTRAL",true)
	f.stage.play_entry(f.entry,f.skill)
	var d = f.stage._skill_presentation
	var center := Vector2.ZERO
	for key in f.stage._party_keys: center += f.stage._foot(key)-Vector2(0,RBMVisualAssets.display_height(f.stage._asset_ids[key])*.35)
	center /= f.stage._party_keys.size()
	assert_eq(d.center,center)
	assert_eq(d.duration,7.2)
	assert_eq(Timeline.RIFT_CONCEPT,"A")
	assert_almost_eq(Timeline.SUCTION_END-Timeline.SUCTION_START,2.1,.001)
	f.stage._tween.custom_step(4.5)
	assert_gt(float(d._post.material.get_shader_parameter("amount")),.5)
	assert_lt(float(d._post.material.get_shader_parameter("cutoff")),f.stage._foot("boss").x)
	var audio = d._audio
	f.stage.cancel()
	assert_false(audio.playing)
	assert_false(d._post.visible)
	assert_false(d._layer.visible)
	assert_eq(f.stage._visuals.boss.z_index,1)
	for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_supported_awakening_reveals_at_climax_and_keeps_cosmic_aura() -> void:
	var f := _fixture("single")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry({"actor":"boss","action":"awakening"},{})
	var d = f.stage._skill_presentation
	assert_true(d is Driver)
	assert_eq(d.action_kind,"awakening")
	f.stage._tween.custom_step(6.4)
	assert_eq(f.stage._asset_ids.boss,"astronaut")
	f.stage._tween.custom_step(.1)
	assert_eq(f.stage._asset_ids.boss,"astronaut_awakened")
	assert_eq(seen.size(),0)
	f.stage._tween.custom_step(20)
	assert_eq(seen.size(),1)
	assert_true(f.stage._astronaut_aura.visible)
	assert_eq(f.stage._visuals.boss.z_index,1)
	var restored: Dictionary = f.session.battle.presentation_state()
	restored.is_awakened = false
	f.stage.set_state(restored)
	assert_eq(f.stage._asset_ids.boss,"astronaut")
	assert_false(f.stage._astronaut_aura.visible)

func test_buff_and_heal_share_motion_and_emit_one_impact() -> void:
	for awakened in [false,true]:
		for kind in ["buff","heal"]:
			var f := _fixture(kind,"FIRE",awakened)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			assert_true(f.stage._skill_presentation is Driver)
			assert_eq(f.stage._skill_presentation.action_kind,kind)
			f.stage._tween.custom_step(20)
			assert_eq(seen.size(),1)
		for i in 30: assert_eq(Timeline.pose("heal",i/10.0,awakened),Timeline.pose("buff",i/10.0,awakened))

func test_counter_continuation_and_resolved_single_target() -> void:
	for awakened in [false,true]:
		var f := _fixture("single","WIND",awakened,true)
		var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
		var seen: Array = []
		f.stage.impact.connect(func(e): seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		assert_false(f.stage._counters.is_empty())
		var d = f.stage._skill_presentation
		var key: String = f.stage._targets[0]
		assert_eq(d.target,f.stage._foot(key)+Vector2(f.stage._guard_offsets.get(key,Vector2.ZERO)))
		f.stage._tween.custom_step(30)
		assert_false(f.stage.is_playing())
		assert_eq(seen.size(),1)
		assert_eq(f.session.battle.snapshot(),snapshot)

func test_picker_name_art_and_awakening_are_available() -> void:
	assert_eq(RBMCreatorAppearanceCatalog.by_id("appearance_astronaut").name,"宇宙飛行士")
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_astronaut"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_astronaut"),"astronaut")
	assert_true(RBMVisualAssets.has_awakened_design("astronaut"))
	for id in ["astronaut","astronaut_awakened"]:
		assert_true(RBMVisualAssets.has_pose_frames(id))
		assert_eq(RBMVisualAssets.display_height(id),116.0)
	var picker := RBMCreatorAppearancePicker.new()
	picker.size = Vector2(1280,720)
	add_child_autofree(picker)
	picker.open("appearance_astronaut")
	await get_tree().process_frame
	var label = picker.find_child("AppearanceName_appearance_astronaut",true,false)
	assert_not_null(label)
	assert_eq(label.text,"宇宙飛行士")
	var seen: Array = []
	picker.confirmed.connect(func(id): seen.append(id))
	picker.find_child("Appearance_appearance_astronaut",true,false).pressed.emit()
	assert_eq(seen,["appearance_astronaut"])

func test_guarded_meteor_and_planet_follow_the_redirected_recipient() -> void:
	for awakened in [false,true]:
		var f := _fixture("single","ICE",awakened)
		var state: Dictionary = f.stage._state.duplicate(true)
		state.party["1"].protecting_ally_id = 0
		f.stage._state = state
		f.stage.play_entry({"actor":"boss","action":"attack","target":1,"visual_original_target":0,"amount":20,"attribute":"ICE"})
		assert_eq(f.stage._guards,["1"])
		var d = f.stage._skill_presentation
		assert_eq(d.target,f.stage._foot("1")+Vector2(f.stage._guard_offsets["1"]))
		f.stage._tween.custom_step(2)
		f.stage.cancel()
		for key in f.stage._homes: assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_cancel_each_phase_then_replay_does_not_leak_sound_or_impacts() -> void:
	for awakened in [false,true]:
		for kind in ["single","aoe"]:
			for fraction in [.16,.55,.86]:
				var f := _fixture(kind,"NEUTRAL",awakened)
				var seen: Array = []
				f.stage.impact.connect(func(e):seen.append(e))
				f.stage.play_entry(f.entry,f.skill)
				var d = f.stage._skill_presentation
				f.stage._tween.custom_step(d.duration*fraction)
				var count := seen.size()
				f.stage.cancel()
				await get_tree().process_frame
				assert_false(is_instance_valid(d))
				assert_eq(seen.size(),count)
				f.stage.play_entry(f.entry,f.skill)
				f.stage._tween.custom_step(20)
				assert_eq(seen.size(),count+1)
				assert_false(f.stage.is_playing())

func test_all_attribute_accents_keep_astronaut_assets_and_damage_unchanged() -> void:
	for attribute in ["FIRE","ICE","LIGHTNING","WIND","NEUTRAL"]:
		var f := _fixture("aoe",attribute,true)
		var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
		f.stage.play_entry(f.entry,f.skill)
		assert_eq(f.stage._skill_presentation._vfx.attack_attribute,attribute)
		assert_eq(f.stage._skill_presentation._vfx.hit_points.size(),4)
		f.stage._tween.custom_step(20)
		assert_eq(f.session.battle.snapshot(),snapshot)

func test_astronaut_name_is_localized_and_draft_can_save_awakening() -> void:
	var saved := RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_astronaut"),"Astronaut")
	RBMLocale.set_locale(saved)
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_astronaut"
	draft.boss_name = "宇宙飛行士"
	draft.hp = 1000
	draft.atk = 40
	draft.spd = 1
	draft.add_party_character("hero")
	draft.set_awakening({"conditions":[],"condition_logic":"AND","buff":{},"heal":{}})
	assert_true(draft.supports_awakening())
	assert_true(draft.is_awakening_appearance_valid())
	assert_true(draft.is_playable())
