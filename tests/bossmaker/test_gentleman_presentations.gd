extends GutTest
const Driver = preload("res://src/bossmaker/visuals/rbm_gentleman_presentation.gd")
const Timeline = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
func _fixture(kind: String, attribute: String = "NEUTRAL", awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_gentleman"
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "異形紳士 skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
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
	stage.configure(session.battle, "appearance_gentleman")
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

func test_all_attributes_and_both_forms_deliver_one_impact_and_preserve_combat() -> void:
	for awakened in [false,true]:
		for kind in ["single","aoe"]:
			for attribute in ["NEUTRAL","FIRE","ICE","LIGHTNING","WIND"]:
				var f := _fixture(kind,attribute,awakened)
				var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
				var seen: Array=[]
				f.stage.impact.connect(func(e):seen.append(e))
				f.stage.play_entry(f.entry,f.skill)
				var d=f.stage._skill_presentation
				assert_true(d is Driver)
				assert_eq(d._vfx.attribute,attribute)
				f.stage._tween.custom_step(d.impact_time-.01)
				assert_eq(seen.size(),0)
				f.stage._tween.custom_step(.02)
				assert_eq(seen.size(),1)
				f.stage._tween.custom_step(30)
				assert_eq(seen.size(),1)
				assert_eq(seen[0],f.entry)
				assert_false(f.stage.is_playing())
				assert_true(f.stage._visuals.boss.visible)
				assert_null(f.stage._skill_presentation)
				assert_eq(f.session.battle.snapshot(),snapshot)
				for key in f.stage._homes:assert_eq(f.stage._visuals[key].position,f.stage._homes[key])

func test_v8_frames_bow_hold_two_guns_and_support_motion() -> void:
	for kind in ["all","awakened_all"]:
		var data: Dictionary=Timeline.clip(kind)
		var last: Dictionary=data.shadows.back()
		assert_gt(float(data.bow.rise),float(last.hit))
		assert_gt(float(data.bow.bow),float(data.bow.all_visible))
		assert_eq(Timeline.frame(kind,float(last.hit)),"bow_down_15")
	for kind in ["awakened_single","awakened_all"]:
		var data: Dictionary=Timeline.clip(kind)
		assert_eq(data.host.size(),2)
		assert_ne(data.host[0].hand,data.host[1].hand)
		for e in data.host:
			assert_gt(Timeline.muzzle(kind,float(e.time),"far").distance_to(Timeline.muzzle(kind,float(e.time),"near")),12.0)
	assert_eq(Timeline.clip("buff").frames,Timeline.clip("heal").frames)
	assert_almost_eq(float(Timeline.clip("all").duration)+float(Timeline.clip("awakened_single").duration)+float(Timeline.clip("awakened_all").duration),30.3,.001)

func test_awakening_aura_and_rewind_restore_normal_form() -> void:
	var f:=_fixture("single")
	var seen: Array=[]
	f.stage.impact.connect(func(e):seen.append(e))
	f.stage.play_entry({"actor":"boss","action":"awakening"},{})
	var d=f.stage._skill_presentation
	assert_true(d is Driver)
	f.stage._tween.custom_step(8.0)
	assert_eq(f.stage._asset_ids.boss,"gentleman")
	f.stage._tween.custom_step(.10)
	assert_eq(f.stage._asset_ids.boss,"gentleman_awakened")
	assert_eq(seen.size(),0)
	f.stage._tween.custom_step(20)
	assert_eq(seen.size(),1)
	assert_true(f.stage._gentleman_aura.visible)
	assert_true(f.stage._visuals.boss.visible)
	var restored: Dictionary=f.session.battle.presentation_state()
	restored.is_awakened=false;f.stage.set_state(restored)
	assert_eq(f.stage._asset_ids.boss,"gentleman")
	assert_false(f.stage._gentleman_aura.visible)

func test_cancel_hides_effects_stops_audio_and_restores_body() -> void:
	for kind in ["single","aoe","buff","heal"]:
		var f:=_fixture(kind,"NEUTRAL",true)
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		f.stage._tween.custom_step(1.0)
		assert_false(f.stage._visuals.boss.visible)
		f.stage.cancel()
		assert_false(d._audio.playing)
		assert_false(d._picture.visible)
		assert_true(f.stage._visuals.boss.visible)
		assert_eq(d._viewport.render_target_update_mode,SubViewport.UPDATE_DISABLED)

func test_support_and_counter_each_complete_one_resolved_entry() -> void:
	for kind in ["single","aoe","buff","heal"]:
		var f:=_fixture(kind,"WIND",true,kind in ["single","aoe"])
		var snapshot: Dictionary=f.session.battle.snapshot().duplicate(true)
		var seen: Array=[]
		f.stage.impact.connect(func(e):seen.append(e))
		f.stage.play_entry(f.entry,f.skill)
		var d=f.stage._skill_presentation
		if kind=="single":
			var key: String=f.stage._targets[0]
			assert_eq(d.target,f.stage._foot(key)+Vector2(f.stage._guard_offsets.get(key,Vector2.ZERO)))
		f.stage._tween.custom_step(40)
		assert_eq(seen.size(),1)
		assert_false(f.stage.is_playing())
		assert_eq(f.session.battle.snapshot(),snapshot)

const Vfx = preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")
const Sheets = preload("res://src/bossmaker/visuals/rbm_gentleman_impact_sheets.gd")

func _sheet_stage(appearance: String = "appearance_gentleman", awakening: bool = true) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	var single := draft.add_skill({"name": "単体", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.0})
	draft.add_skill({"name": "全体", "type": "attack", "target": "all", "attribute": "ICE", "atk_multiplier": 1.0})
	draft.add_skill({"name": "回復", "type": "self_heal", "heal_amount": 200})
	if awakening:
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 10.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[single] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, appearance)
	stage.set_state(session.battle.presentation_state())
	return {"stage": stage, "session": session, "skill": single}

## Lets the stage's sheet keeper notice the boss and finish its background reads.
func _settle(stage: RBMBattleStage) -> Array:
	var sheets = stage._gentleman_impacts
	for i in 300:
		await get_tree().process_frame
		if sheets._boss_id == str(stage._asset_ids.boss) and sheets._pending.is_empty(): break
	var held: Array = sheets._held.keys()
	held.sort()
	return held

func _sheets(pairs: Array) -> Array:
	var paths: Array = []
	for pair in pairs: paths.append(Vfx.impact_path(pair[0], pair[1]))
	paths.sort()
	return paths

func test_impact_sheets_are_read_once_per_battle_for_the_boss_attacks_and_form() -> void:
	var f := _sheet_stage()
	var stage: RBMBattleStage = f.stage
	# Before awakening only the single FIRE draws a sheet (the normal all-target attack draws none).
	assert_eq(await _settle(stage), _sheets([["FIRE", "duel"]]))
	var kept: Texture2D = stage._gentleman_impacts._held[Vfx.impact_path("FIRE", "duel")]
	for attack in 2:
		var entry: Dictionary = {}
		var before: Dictionary = {}
		for attempt in 12:
			before = f.session.battle.presentation_state().duplicate(true)
			for e in f.session.resolve_ally_action({"type": "defend"}):
				if str(e.get("actor")) == "boss": entry = e
			if not entry.is_empty(): break
		stage.set_state(before)
		stage.play_entry(entry, RBMBattleUiKit.find_skill_for_actor("boss", f.skill, f.session.battle))
		var d = stage._skill_presentation
		assert_eq(d.action_kind, "single")
		stage._tween.custom_step(d.impact_time + .1)
		await get_tree().process_frame
		await get_tree().process_frame
		# The drawn sheet is the one kept since the battle began, not a fresh read.
		assert_same(d._vfx._impact_textures.get("duel"), kept)
		stage._tween.custom_step(30)
		await get_tree().process_frame
	assert_eq(await _settle(stage), _sheets([["FIRE", "duel"]]))
	# Awakened: the duel sheet can no longer be drawn and is released; REWIND reads it again.
	var awakened: Dictionary = f.session.battle.presentation_state()
	awakened.is_awakened = true
	stage.set_state(awakened)
	assert_eq(await _settle(stage), _sheets([["FIRE", "first"], ["FIRE", "heavy"], ["ICE", "first"]]))
	awakened.is_awakened = false
	stage.set_state(awakened)
	assert_eq(await _settle(stage), _sheets([["FIRE", "duel"]]))
	# Leaving the battle releases every sheet.
	var sheets = stage._gentleman_impacts
	stage.get_parent().remove_child(stage)
	assert_true(sheets._held.is_empty())
	assert_true(sheets._pending.is_empty())
	stage.queue_free()

func test_impact_sheets_without_awakening_and_for_other_bosses() -> void:
	var f := _sheet_stage("appearance_gentleman", false)
	assert_eq(await _settle(f.stage), _sheets([["FIRE", "duel"]]))
	var other := _sheet_stage("appearance_slime")
	assert_eq(await _settle(other.stage), [])

func test_impact_sheets_stay_within_three_for_a_boss_of_many_attributes() -> void:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_gentleman"
	draft.boss_name = "異形紳士"
	draft.hp = 3000
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	draft.normal_actions_enabled = true
	for attribute in ["NEUTRAL", "FIRE", "ICE", "LIGHTNING", "WIND"]:
		var id := draft.add_skill({"name": attribute, "type": "attack", "target": "single", "attribute": attribute, "atk_multiplier": 1.0})
		draft.normal_action_percentages[id] = 20.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_gentleman")
	stage.set_state(session.battle.presentation_state())
	var sheets = stage._gentleman_impacts
	# Read ahead in the order of the boss's skills, up to three sheets.
	assert_eq(await _settle(stage), _sheets([["NEUTRAL", "duel"], ["FIRE", "duel"], ["ICE", "duel"]]))
	var entry: Dictionary = {}
	var before: Dictionary = {}
	for attempt in 12:
		before = session.battle.presentation_state().duplicate(true)
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	for attribute in ["ICE", "LIGHTNING", "WIND", "NEUTRAL", "FIRE"]:
		stage.set_state(before)
		stage.play_entry(entry, {"attribute": attribute, "effect": "damage", "target": "ally_random_single"})
		var d = stage._skill_presentation
		assert_eq(d._vfx.attribute, attribute)
		assert_true(sheets._held.size() + sheets._pending.size() <= Sheets.MAX_SHEETS, attribute)
		stage._tween.custom_step(d.impact_time + .1)
		await get_tree().process_frame
		await get_tree().process_frame
		var drawn = d._vfx._impact_textures.get("duel")
		assert_not_null(drawn, attribute)
		assert_same(drawn, sheets._held.get(Vfx.impact_path(attribute, "duel")), attribute)
		assert_true(sheets._held.size() + sheets._pending.size() <= Sheets.MAX_SHEETS, attribute)
		stage._tween.custom_step(30)
		await get_tree().process_frame
	# The three most recently used remain.
	var held: Array = sheets._held.keys()
	held.sort()
	assert_eq(held, _sheets([["WIND", "duel"], ["NEUTRAL", "duel"], ["FIRE", "duel"]]))

func test_each_attack_draws_exactly_the_sheets_kept_for_it() -> void:
	for setup in [["single", false], ["single", true], ["aoe", true], ["aoe", false]]:
		var f := _fixture(setup[0], "WIND", setup[1])
		var stage: RBMBattleStage = f.stage
		await _settle(stage)
		var kept: Array = stage._gentleman_impacts._held.keys()
		stage.play_entry(f.entry, f.skill)
		var d = stage._skill_presentation
		# The presentation frees itself when it ends; keep what it drew.
		var used: Dictionary = d._vfx._impact_textures
		var action: String = d.action_kind
		var duration: float = d.duration
		var t := 0.0
		while stage.is_playing() and t < duration:
			stage._tween.custom_step(1.0 / 30)
			t += 1.0 / 30
			await get_tree().process_frame
		var drawn: Array = used.keys()
		drawn.sort()
		var expected: Array = Vfx.IMPACT_STYLES.get(action, []).duplicate()
		expected.sort()
		assert_eq(drawn, expected, action)
		for style in drawn: assert_true(kept.has(Vfx.impact_path("WIND", style)), action + " " + style)
		if stage.is_playing(): stage._tween.custom_step(30)
		assert_false(stage.is_playing())

func test_boss_catalog_art_and_fixed_background() -> void:
	const Backgrounds=preload("res://src/bossmaker/visuals/rbm_battle_backgrounds.gd")
	assert_eq(RBMCreatorAppearanceCatalog.by_id("appearance_gentleman").name,"異形紳士")
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_gentleman"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_gentleman"),"gentleman")
	assert_true(RBMVisualAssets.has_awakened_design("gentleman"))
	for id in ["gentleman","gentleman_awakened"]:
		assert_true(RBMVisualAssets.has_pose_frames(id))
		for time in ["day","night"]:assert_eq(Backgrounds.path_for(id,time),"res://assets_bossmaker/battle/backgrounds/gentleman/background.png")
	var saved:=RBMLocale.current_locale()
	RBMLocale.set_locale("en")
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_gentleman"),"Faceless Gentleman")
	RBMLocale.set_locale(saved)
