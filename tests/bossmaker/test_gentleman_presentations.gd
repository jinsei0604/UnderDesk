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
