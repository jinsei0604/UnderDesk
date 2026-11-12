extends GutTest
## ヒーロー（hero_boss）の本番の演出の契約（2026-11-10 採用の5技・常時オーラ）。
## 表示だけで戦闘を変えない・命中は1回・途中の当たりの小さな数字・後始末・覚醒で外見が替わる・選択と保存。
const Driver = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_presentation.gd")
const Motion = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_motion.gd")
const Visual = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_visual.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["hero_boss"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(kind: String, awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_hero_boss"
	draft.boss_name = "Hero QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Hero QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_hero_boss")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		for e in session.resolve_ally_action(action):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

func test_registered_like_the_other_bosses() -> void:
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_hero_boss"))
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_hero_boss"), TranslationServer.translate("ヒーロー"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_hero_boss"), "hero_boss")
	assert_true(RBMVisualAssets.has_awakened_design("hero_boss"))
	assert_true(RBMVisualAssets.has_pose_frames("hero_boss"))
	assert_true(RBMVisualAssets.has_pose_frames("hero_boss_awakened"))
	assert_eq(RBMVisualAssets.display_height("hero_boss"), 180.0)
	for key in ["hero_boss_single", "hero_boss_all", "hero_boss_awakening", "hero_boss_awakened_single", "hero_boss_awakened_all"]:
		assert_true(ResourceLoader.exists(str(AudioCatalog.FILES[key])), key)
	# 味方の勇者（hero）と名前が混ざらない
	assert_eq(RBMVisualAssets.ALLY_IDS.count("hero_boss"), 0)
	assert_false(RBMVisualAssets.BOSS_IDS.has("hero"))

func test_motion_follows_the_approved_exposures() -> void:
	for scene in Motion.SEQUENCES:
		var timing: Dictionary = Motion.TIMINGS[scene]
		var frames := Motion.frames(scene)
		assert_eq(frames.size(), int(round(float(timing["duration"]) * 30.0)), scene)
		for row in frames:
			assert_not_null(row, scene + ": no gap in the playback")
		for cel in Motion.cels_of(scene):
			assert_true(ResourceLoader.exists(RBMHeroDarkAura.field_path(cel)), "baked aura field " + cel)
	# ② 照射の姿勢 91 コマは、溜めを足した後もそのまま続く
	var array := Motion.frames("array")
	var start := 45 + int(RBMHeroFxTiming.ARRAY["tame_hold"])
	for i in range(91):
		assert_eq(str(array[start + i][0]), "array_standing_palms")
	assert_ne(str(array[start + 91][0]), "array_standing_palms")
	# ④ 切った後は直立しない（2026-11-10）
	for i in range(76, 87):
		assert_eq(str(Motion.frames("shear")[i][0]), "shear1")

func test_every_warm_path_exists() -> void:
	for asset_id in ["hero_boss", "hero_boss_awakened"]:
		for kind in ["single", "all", "awakening"]:
			for path in Driver.warm_paths(asset_id, kind):
				assert_true(ResourceLoader.exists(path), path)

func test_actions_show_partial_and_total_numbers_once_without_battle_mutation() -> void:
	for aw in [false, true]:
		for kind in ["single", "aoe"]:
			var f := _fixture(kind, aw)
			assert_false(f.entry.is_empty())
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Driver)
			if not d is Driver: continue
			var expected: String = ("shear" if aw else "blade") if kind == "single" else ("press" if aw else "array")
			assert_eq(d.scene, expected)
			assert_false(f.stage._visuals.boss.visible, "The presentation draws the body itself")
			f.stage._tween.custom_step(d.impact_time - .01)
			assert_eq(seen.size(), 0, "No impact before the final blow")
			assert_gt(f.stage._damage_numbers._numbers.size(), 0, "Earlier hits show small numbers")
			f.stage._tween.custom_step(.02)
			assert_eq(seen.size(), 1)
			f.stage._tween.custom_step(20)
			assert_eq(seen.size(), 1)
			assert_false(f.stage.is_playing())
			assert_null(f.stage._skill_presentation)
			assert_eq(f.session.battle.snapshot(), snapshot)
			assert_true(f.stage._visuals.boss.visible)
			assert_eq(f.stage.scale, Vector2.ONE)
			for key in f.stage._homes:
				assert_eq(f.stage._visuals[key].position, f.stage._homes[key])
				assert_eq(f.stage._visuals[key].self_modulate, Color.WHITE)
			f.stage.queue_free()
			await get_tree().process_frame

func test_single_attacks_aim_at_the_resolved_target() -> void:
	for aw in [false, true]:
		var f := _fixture("single", aw)
		f.stage.play_entry(f.entry, f.skill)
		var d = f.stage._skill_presentation
		var target: String = f.stage._targets[0]
		var world: Vector2 = (f.stage._foot(target) - d._offset) * 0.5
		assert_eq(d._slot_keys[Driver.SINGLE_SLOT], target)
		var probe: Node2D = d._fx.get_script().new()
		assert_eq(d._fx.HIT - d._focus_delta, probe.HIT, "The strike moves with the target")
		probe.free()
		assert_eq(d._focus_delta, world - Driver.PARTY[Driver.SINGLE_SLOT])
		f.stage._tween.custom_step(30)
		f.stage.queue_free()
		await get_tree().process_frame

func test_cancel_and_counter_restore_the_stage() -> void:
	for aw in [false, true]:
		for kind in ["single", "aoe"]:
			for fraction in [.1, .55, .9]:
				var f := _fixture(kind, aw)
				f.stage.play_entry(f.entry, f.skill)
				var d = f.stage._skill_presentation
				f.stage._tween.custom_step(d.duration * fraction)
				f.stage.cancel()
				await get_tree().process_frame
				assert_false(is_instance_valid(d))
				assert_true(f.stage._visuals.boss.visible)
				assert_eq(f.stage.scale, Vector2.ONE)
				assert_false(f.stage.is_playing())
				for key in f.stage._party_keys:
					assert_eq(f.stage._visuals[key].self_modulate, Color.WHITE)
				f.stage.queue_free()
				await get_tree().process_frame
	for aw in [false, true]:
		for kind in ["single", "aoe"]:
			var f := _fixture(kind, aw, true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			assert_false(f.stage._counters.is_empty())
			f.stage._tween.custom_step(30)
			assert_eq(seen.size(), 1)
			assert_false(f.stage.is_playing())
			f.stage.queue_free()
			await get_tree().process_frame

func test_awakening_turns_into_the_dark_form_with_its_aura() -> void:
	var f := _fixture("single")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry({"actor": "boss", "action": "awakening"})
	var d = f.stage._skill_presentation
	assert_true(d is Driver)
	assert_eq(d.scene, "breach")
	f.stage._tween.custom_step(d.duration - .05)
	assert_eq(f.stage._asset_ids.boss, "hero_boss", "The dark form appears at the end")
	assert_eq(seen.size(), 0)
	f.stage._tween.custom_step(1)
	assert_eq(seen.size(), 1)
	assert_eq(f.stage._asset_ids.boss, "hero_boss_awakened")
	assert_true(f.stage._visuals.boss.visible)
	assert_true(f.stage._visuals.boss is Visual)
	assert_not_null(f.stage._visuals.boss.find_child("HeroDarkAura", false, false), "Awakened idle wears the dark aura")
	assert_eq(f.stage.scale, Vector2.ONE)
	# 巻き戻しで覚醒前へ戻るとオーラも消える
	var before: Dictionary = f.stage._state.duplicate(true)
	before.is_awakened = false
	f.stage.set_state(before)
	assert_eq(f.stage._asset_ids.boss, "hero_boss")
	await get_tree().process_frame
	assert_null(f.stage._visuals.boss.find_child("HeroDarkAura", false, false))

func test_selection_save_and_reload() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("user://hero_boss_integration_roundtrip")
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	var d = creator.draft
	d.appearance_id = "appearance_hero_boss"; d.boss_name = "ヒーロー本番統合"; d.hp = 400; d.atk = 17; d.spd = 1
	d.add_party_character("hero")
	d.add_skill({"name": "光の刃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.2})
	d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 50, "heal_percent": 0.0}})
	var before: Dictionary = d.to_definition().duplicate(true)
	var saved: Dictionary = creator.press_save_as_new()
	assert_true(saved.get("ok", false))
	var loaded := RBMCreatorMain.new(); add_child_autofree(loaded)
	assert_true(loaded.start_loaded(str(saved.stage_id)).get("ok", false))
	assert_eq(loaded.draft.appearance_id, "appearance_hero_boss")
	assert_eq(loaded.draft.to_definition(), before)
	var picker := RBMCreatorAppearancePicker.new(); add_child_autofree(picker)
	picker.open("")
	assert_true(picker._entry_buttons.has("appearance_hero_boss"))
	picker._entry_buttons["appearance_hero_boss"].pressed.emit()
	var toggle := picker.find_child("AwakenedPreviewToggle", true, false) as Button
	assert_not_null(toggle)
	if toggle != null:
		assert_true(toggle.visible)
		assert_false(toggle.disabled)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

# ---------------------------------------------------------------------------
# 覚醒後の撃破（2026-11-11）: 専用の撃破（覚醒前は共通の倒れ方のまま）、素材の宣言、中断で元に戻る、倒れ切る

const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const Defeat = preload("res://src/bossmaker/visuals/hero_boss/rbm_hero_boss_defeat_awakened.gd")

func test_awakened_defeat_is_dedicated_and_declares_its_materials() -> void:
	assert_eq(VictoryPlayer.defeat_script("hero_boss_awakened"), Defeat)
	assert_eq(VictoryPlayer.defeat_script("hero_boss"), VictoryPlayer.GENERIC, "the normal form keeps the common fall for now")
	var warm := VictoryPlayer.warm_paths("hero_boss_awakened", ["hero", "butler", "healer", "samurai"])
	var before_hit := VictoryPlayer.final_blow_paths("hero_boss_awakened")
	for path in Defeat.VFX_PATHS:
		assert_true(ResourceLoader.exists(path), path)
		assert_true(warm.has(path), "read before the victory: " + path)
		assert_true(before_hit.has(path), "read before the final blow: " + path)
	var sound_path := "res://assets_bossmaker/audio/hero_boss/awakened_defeat.wav"
	assert_true(ResourceLoader.exists(sound_path))
	assert_true(VictoryPlayer.victory_keys("hero_boss_awakened").has(Defeat.SOUND))
	assert_true(warm.has(sound_path))
	assert_false(VictoryPlayer.victory_keys("hero_boss").has(Defeat.SOUND), "only the awakened defeat plays it")
	for cel in Defeat.CEL_TOP_LEFT:
		var tex := load(Defeat.ROOT + cel + ".png") as Texture2D
		assert_eq(tex.get_size(), Defeat.DEFEAT_CANVAS, cel)
	assert_almost_eq(Defeat.new().duration(), float(RBMHeroFxTiming.FALL.end), 0.001)

func _awakened_victory() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_hero_boss"
	draft.boss_name = "Hero QA"
	draft.hp = 1
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Hero QA skill", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	view.start_battle(draft.to_definition(), RBMBattleUiKit.ALL_VISIBLE, "appearance_hero_boss")
	var stage: Control = view._battlefield_ally_row.get_meta("visual_stage")
	view.session.battle.is_awakened = true
	stage.set_state(view.session.battle.presentation_state())
	stage._apply_awakened_appearance()
	for i in 20:
		if view.session.battle.battle_over:
			break
		view.act_attack(view.session.pending_ally_id())
	var director: RBMEncounterDirector = view._encounter
	director.begin_battle({"boss_name": "QA", "author": "qa"})
	director.on_impact({"visual_state": view.session.battle.presentation_state()})
	return {"view": view, "stage": stage, "director": director}

func _defeat_nodes(stage: Control) -> Array:
	var out: Array = []
	for n in stage.get_children():
		if str(n.name).begins_with("HeroDefeat") or str(n.name).begins_with("Victory"):
			out.append(str(n.name))
	return out

func test_awakened_defeat_cancel_restores_the_stage() -> void:
	var f := _awakened_victory()
	var view = f.view
	var stage: Control = f.stage
	var director: RBMEncounterDirector = f.director
	assert_true(view.session.battle.battle_over)
	assert_eq(str(stage._asset_ids.boss), "hero_boss_awakened")
	var state_before := JSON.stringify(view.session.battle.presentation_state())
	assert_true(director.on_presentation_finished())
	assert_true(_defeat_nodes(stage).has("HeroDefeatWorld"), "the defeat builds its own layers")
	assert_true(_defeat_nodes(stage).has("HeroDefeatPost"))
	for i in 20:
		await get_tree().process_frame
	director.cancel()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_defeat_nodes(stage), [], "no defeat layer remains")
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage.scale, Vector2.ONE)
	assert_eq(JSON.stringify(view.session.battle.presentation_state()), state_before, "the battle state is untouched")

func test_awakened_defeat_runs_through_and_the_body_is_gone() -> void:
	var f := _awakened_victory()
	var stage: Control = f.stage
	var director: RBMEncounterDirector = f.director
	assert_true(director.on_presentation_finished())
	var player: Node = null
	for n in stage.get_children():
		if n.get_script() == VictoryPlayer:
			player = n
	assert_not_null(player)
	# とどめのスローの後、勝利の本体が始まるまで待つ
	for i in 600:
		if player.state == "playing":
			break
		await get_tree().process_frame
	assert_eq(player.state, "playing")
	# 撃破の秒を順に進める（実時間は待たない）
	var cels := {}
	var t := 0.0
	while t < float(RBMHeroFxTiming.FALL.end) + 0.3 and is_instance_valid(player):
		player._process(1.0 / 30.0)
		t += 1.0 / 30.0
		if player.state == "playing" and not player.defeat.gone:
			cels[str(player.defeat.bs.get("cel", ""))] = true
	assert_eq(cels.keys(), ["omega", "release2", "release3", "release1"], "kneel → burst → restored → light")
	assert_true(player.defeat.gone, "the body is gone at the end")
	assert_true(player.defeat.dissolve >= 0.99)
