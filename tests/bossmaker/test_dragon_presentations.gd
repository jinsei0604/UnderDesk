extends GutTest
## Limited integration coverage for the dragon's production presentation contract.
const Driver = preload("res://src/bossmaker/visuals/rbm_dragon_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_dragon"
	draft.boss_name = "Dragon QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "Dragon QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Dragon support", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
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
	stage.configure(session.battle, "appearance_dragon")
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

func _expected_action(kind: String, awakened: bool) -> String:
	if kind in ["buff", "heal"]: return kind
	return ("focused_breath" if kind == "single" else "meteors") if awakened else ("bite" if kind == "single" else "breath")

func _assert_restored(stage: RBMBattleStage, awakened: bool) -> void:
	assert_null(stage._skill_presentation)
	assert_false(stage.is_playing())
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._visuals["boss"].scale, Vector2.ONE)
	assert_eq(stage._visuals["boss"].pivot_offset, Vector2.ZERO)
	assert_eq(stage._asset_ids["boss"], "dragon_awakened" if awakened else "dragon")
	for key in stage._homes: assert_eq(stage._visuals[key].position, stage._homes[key])

func test_real_four_attack_actions_all_five_colors_impact_and_cleanup() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe"]:
			for attribute in Palette.COLORS:
				var f := _fixture(kind, attribute, awakened)
				assert_false(f.entry.is_empty())
				var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
				var seen: Array = []
				f.stage.impact.connect(func(e): seen.append(e))
				f.stage.play_entry(f.entry, f.skill)
				var d = f.stage._skill_presentation
				assert_true(d is Driver)
				assert_eq(d.kind, kind)
				assert_eq(d.form, "awakened" if awakened else "normal")
				assert_eq(d.action_kind, _expected_action(kind, awakened))
				assert_eq(d._vfx.kind, d.action_kind)
				assert_eq(d._vfx.attack_attribute, attribute)
				assert_eq(Palette.color_for(d._vfx.attack_attribute), Palette.COLORS[attribute])
				assert_false(f.stage._visuals["boss"].visible)
				f.stage._tween.custom_step(d.impact_time - .01)
				assert_eq(seen.size(), 0)
				f.stage._tween.custom_step(.02)
				assert_eq(seen.size(), 1)
				assert_eq(seen[0], f.entry)
				if kind == "aoe": assert_eq(f.entry.get("hits", {}).size(), 4)
				f.stage._tween.custom_step(10)
				assert_eq(seen.size(), 1)
				_assert_restored(f.stage, awakened)
				assert_eq(f.session.battle.snapshot(), snapshot)

func test_support_uses_identical_body_motion_in_both_forms() -> void:
	for awakened in [false, true]:
		var reference: Array = []
		for kind in ["buff", "heal"]:
			var f := _fixture(kind, "ICE" if kind == "buff" else "FIRE", awakened)
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d.action_kind, kind)
			var samples: Array = []
			var step: float = d.duration / 61.0
			for i in range(60):
				f.stage._tween.custom_step(step)
				samples.append(d._body.state.duplicate(true))
			if reference.is_empty(): reference = samples
			else: assert_eq(samples, reference, "The body uses the same roar samples for buff and heal")
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(), 1)
			_assert_restored(f.stage, awakened)
			assert_eq(f.session.battle.snapshot(), snapshot)

func test_approved_bite_closes_jaw_with_planted_feet_then_steps_home() -> void:
	var f := _fixture("single")
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	assert_eq(d.motion.get_script(), preload("res://src/bossmaker/visuals/rbm_dragon_bite_motion.gd"))
	assert_eq(d.duration, 3.85)
	f.stage._tween.custom_step(1.40)
	assert_eq(d._body.state.pose, 5, "Approved open-jaw frame")
	var planted: Vector2 = d._body.state.foot
	f.stage._tween.custom_step(.11)
	assert_eq(d._body.state.pose, 6, "Approved closed-jaw contact frame")
	assert_eq(d._body.state.foot, planted, "Feet remain planted while the jaw closes")
	assert_lt(d._body.mouth_point().distance_to(d.motion.contact), 2.0)
	f.stage._tween.custom_step(.8)
	assert_eq(d._body.state.pose, 9, "Approved facing-left recovery step")
	assert_eq(d._body.scale, Vector2.ONE)
	f.stage._tween.custom_step(10)
	_assert_restored(f.stage, false)

func test_cancel_during_windup_strike_and_return_then_replay() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe", "buff", "heal"]:
			for progress in [.16, .51, .82]:
				var f := _fixture(kind, "NEUTRAL", awakened)
				var seen: Array = []
				f.stage.impact.connect(func(e): seen.append(e))
				f.stage.play_entry(f.entry, f.skill)
				var d = f.stage._skill_presentation
				f.stage._tween.custom_step(d.duration * progress)
				var count := seen.size()
				f.stage.cancel()
				await get_tree().process_frame
				assert_false(is_instance_valid(d))
				assert_eq(seen.size(), count)
				_assert_restored(f.stage, awakened)
				f.stage.play_entry(f.entry, f.skill)
				f.stage._tween.custom_step(10)
				assert_eq(seen.size(), count + 1)
				_assert_restored(f.stage, awakened)

func test_cover_aims_at_redirected_target_in_both_forms() -> void:
	for awakened in [false, true]:
		var f := _fixture("single", "ICE", awakened)
		var state: Dictionary = f.stage._state.duplicate(true)
		state.party["1"].protecting_ally_id = 0
		f.stage._state = state
		var entry := {"actor": "boss", "action": "attack", "target": 1, "visual_original_target": 0, "amount": 20, "attribute": "ICE"}
		f.stage.play_entry(entry)
		assert_eq(f.stage._guards, ["1"])
		var d = f.stage._skill_presentation
		assert_true(d is Driver)
		assert_eq(d.action_kind, _expected_action("single", awakened))
		var chest: Vector2 = f.stage._foot("1") + Vector2(f.stage._guard_offsets["1"]) - Vector2(0, f.stage.Assets.display_height("butler") * .52)
		assert_lt(d.motion.contact.distance_to(chest), 40.0, "The actual covered ally receives the bite/breath")
		if not awakened:
			f.stage._tween.custom_step(d.impact_time)
			assert_lt(d._body.mouth_point().distance_to(d.motion.contact), 2.0, "The approved bite reaches the covering ally")
		f.stage.cancel()
		_assert_restored(f.stage, awakened)

func test_real_counters_finish_once_and_preserve_battle_state() -> void:
	for awakened in [false, true]:
		for kind in ["single", "aoe"]:
			var f := _fixture(kind, "FIRE", awakened, true)
			var counter_count := int(f.entry.get("counter", false))
			for hit in f.entry.get("hits", {}).values(): counter_count += int(hit.get("counter", false))
			assert_eq(counter_count, 1)
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			f.stage._tween.custom_step(d.impact_time + .05)
			assert_eq(seen.size(), 0, "Counter entries emit only after the complete combined action")
			for i in range(200):
				if not f.stage.is_playing(): break
				f.stage._tween.custom_step(.1)
			assert_eq(seen.size(), 1)
			assert_eq(seen[0], f.entry)
			_assert_restored(f.stage, awakened)
			assert_false(f.stage._samurai_wind.visible)
			assert_eq(f.session.battle.snapshot(), snapshot)

func test_ranged_sfx_play_once_independent_of_attribute_and_stop_on_cancel() -> void:
	for spec in [["aoe",false,"dragon_normal_breath",4.05],["single",true,"dragon_awakened_breath",4.45],["aoe",true,"dragon_awakened_meteors",6.65]]:
		for attribute in Palette.COLORS:
			var f := _fixture(spec[0],attribute,spec[1])
			f.stage._sound.history.clear()
			f.stage.play_entry(f.entry,f.skill)
			var d = f.stage._skill_presentation
			assert_eq(f.stage._sound.history,[spec[2]],"One attack-specific clip, without attribute cast")
			var stream: AudioStreamWAV=f.stage._sound._cache[spec[2]]
			assert_almost_eq(stream.get_length(),spec[3],.001)
			assert_true(stream.stereo)
			assert_eq(stream.loop_mode,AudioStreamWAV.LOOP_DISABLED)
			f.stage._tween.custom_step(2.9)
			assert_eq(f.stage._sound.history,[spec[2]],"Release/impact do not layer generic attribute SFX")
			f.stage.cancel()
			for player in f.stage._sound._players: assert_false(player.playing)
			f.stage.play_entry(f.entry,f.skill)
			assert_eq(f.stage._sound.history,[spec[2],spec[2]],"Replay starts exactly one fresh clip")
			f.stage.cancel()

func test_approved_breath_holds_mouth_pose_and_reaches_beyond_left_edge() -> void:
	for awakened in [false,true]:
		var f := _fixture("single" if awakened else "aoe","ICE",awakened)
		f.stage.play_entry(f.entry,f.skill)
		var d = f.stage._skill_presentation
		f.stage._tween.pause()
		for elapsed in [1.1,1.6,2.1,2.4,2.60]:
			d._advance(elapsed)
			var b: Dictionary=d._vfx.beam_values()
			assert_lt((b.mouth+b.dir*b.span*b.travel).x,-32.0)
			assert_gt(b.fade,0.0)
			assert_eq(d._body.state.pose,5 if awakened else 2)
			assert_eq(b.mouth,d._body.mouth_point())
			if awakened:
				assert_eq(d._body.state.foot,d.motion.home)
				assert_eq(d._body.state.scale,Vector2.ONE)
				assert_eq(d._shake,Vector2.ZERO)
		d._advance(3.2)
		assert_eq(d._body.state.pose,0)
		f.stage.cancel()

func test_meteor_final_impact_precedes_cleanup_and_damage_stays_single() -> void:
	var f := _fixture("aoe","FIRE",true)
	var seen: Array=[]
	f.stage.impact.connect(func(entry): seen.append(entry))
	f.stage.play_entry(f.entry,f.skill)
	var d = f.stage._skill_presentation
	assert_eq(d._vfx.meteors.size(),33)
	var last: Dictionary=d._vfx.meteors.back()
	assert_almost_eq(last.arrival,4.15,.001)
	assert_gt(last.radius,d._vfx.meteors[0].radius)
	f.stage._tween.custom_step(3.0)
	assert_true(f.stage.is_playing())
	assert_eq(seen.size(),1,"Repeated visual impacts do not repeat damage")
	assert_gt(d.duration,last.arrival+1.7)
	f.stage._tween.custom_step(10)
	assert_eq(seen.size(),1)
	_assert_restored(f.stage,true)
