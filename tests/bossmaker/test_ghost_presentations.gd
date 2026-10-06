extends GutTest
## Limited integration coverage for the dragon's production presentation contract.
const Driver = preload("res://src/bossmaker/visuals/rbm_ghost_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_ghost"
	draft.boss_name = "Ghost QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "Ghost QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Ghost support", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
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
	stage.configure(session.battle, "appearance_ghost")
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


func _restored(stage) -> void:
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._asset_ids["boss"],"ghost")
	for key in stage._homes: assert_eq(stage._visuals[key].position,stage._homes[key])

func test_attacks_all_colors_emit_once_and_return_home() -> void:
	for kind in ["single","aoe"]:
		for color in Palette.COLORS:
			var f=_fixture(kind,color)
			var before=f.session.battle.snapshot().duplicate(true)
			var seen: Array=[]
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var d=f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d._body.attribute,color)
			assert_eq(d._body.targets.size(),4 if kind=="aoe" else 1)
			f.stage._tween.custom_step(d.impact_time-.01)
			assert_eq(seen.size(),0)
			f.stage._tween.custom_step(.02)
			assert_eq(seen,[f.entry])
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(),1)
			assert_eq(f.session.battle.snapshot(),before)
			_restored(f.stage)

func test_support_motion_identical_red_and_green() -> void:
	var reference: Array=[]
	for kind in ["buff","heal"]:
		var f=_fixture(kind,"ICE" if kind=="buff" else "FIRE")
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		assert_eq(d._body.color_for(),Color("ef4847") if kind=="buff" else Color("71da87"))
		var samples: Array=[]
		for i in range(240):
			f.stage._tween.custom_step(1.0/60.0)
			samples.append(d._body.state.duplicate(true))
		if reference.is_empty(): reference=samples
		else: assert_eq(samples,reference)
		f.stage._tween.custom_step(10)
		_restored(f.stage)

func test_teleport_targets_covering_ally_and_crosses_once() -> void:
	var f=_fixture("single")
	var state: Dictionary=f.stage._state.duplicate(true)
	state.party["1"].protecting_ally_id=0
	f.stage._state=state
	f.stage.play_entry({"actor":"boss","action":"attack","target":1,"visual_original_target":0,"amount":20,"attribute":"ICE"})
	var d=f.stage._skill_presentation
	var foot: Vector2=f.stage._foot("1")+Vector2(f.stage._guard_offsets["1"])
	assert_eq(d.motion.target_foot,foot)
	f.stage._tween.custom_step(.92)
	assert_eq(d._body.state.alpha,0.0)
	f.stage._tween.custom_step(.18)
	assert_eq(d._body.state.foot,foot+Vector2(-132,0))
	assert_true(d._body.state.flip)
	f.stage._tween.custom_step(.33)
	assert_lt(absf(d._body.state.foot.x-foot.x),2.0)
	f.stage.cancel()
	_restored(f.stage)

func test_cancel_every_phase_restores_and_replays() -> void:
	for kind in ["single","aoe","buff","heal"]:
		for t in [.4,.95,1.45,2.2,2.9,3.6]:
			var f=_fixture(kind)
			var seen: Array=[]
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry,f.skill)
			var d=f.stage._skill_presentation
			f.stage._tween.custom_step(t)
			var count=seen.size()
			f.stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(d))
			_restored(f.stage)
			f.stage.play_entry(f.entry,f.skill)
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(),count+1)
			_restored(f.stage)

func test_real_counter_preserves_damage_and_cleanup() -> void:
	for kind in ["single","aoe"]:
		var f=_fixture(kind,"WIND",false,true)
		var count=int(f.entry.get("counter",false))
		for hit in f.entry.get("hits",{}).values(): count+=int(hit.get("counter",false))
		assert_eq(count,1)
		var snapshot=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e): seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		f.stage._tween.custom_step(1.7)
		assert_eq(seen.size(),0)
		for i in range(180):
			if not f.stage.is_playing(): break
			f.stage._tween.custom_step(.1)
		assert_eq(seen,[f.entry])
		assert_eq(f.session.battle.snapshot(),snapshot)
		_restored(f.stage)
