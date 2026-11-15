extends GutTest
## 金環の聖獣／日蝕の獅皇（lion）の本番の演出の契約（2026-11-12 採用の5技・常時の太陽のオーラ）。
## 表示だけで戦闘を変えない・命中は1回・途中の当たりの小さな数字・後始末・覚醒で外見が替わる・選択と保存。
const Driver = preload("res://src/bossmaker/visuals/lion/rbm_lion_presentation.gd")
const Visual = preload("res://src/bossmaker/visuals/lion/rbm_lion_visual.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const Intro = preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_lion.gd")
const Defeat = preload("res://src/bossmaker/visuals/lion/rbm_lion_defeat.gd")
const Support = preload("res://src/bossmaker/visuals/lion/rbm_lion_support.gd")
const IntroFx = preload("res://src/bossmaker/visuals/lion/rbm_lion_fx_intro.gd")
const FallFx = preload("res://src/bossmaker/visuals/lion/rbm_lion_fx_fall.gd")
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["lion"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(kind: String, awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_lion"
	draft.boss_name = "Lion QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Lion QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_lion")
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
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_lion"))
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_lion"), TranslationServer.translate("金環の聖獣"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_lion"), "lion")
	assert_true(RBMVisualAssets.has_awakened_design("lion"))
	assert_true(RBMVisualAssets.has_pose_frames("lion"))
	assert_true(RBMVisualAssets.has_pose_frames("lion_awakened"))
	assert_eq(RBMVisualAssets.display_height("lion"), 180.0)
	assert_eq(RBMVisualAssets.display_height("lion_awakened"), 240.0)
	for key in ["lion_single", "lion_all", "lion_awakening", "lion_awakened_single", "lion_awakened_all", "lion_heal", "lion_buff", "lion_awakened_heal", "lion_awakened_buff"]:
		assert_true(ResourceLoader.exists(str(AudioCatalog.FILES[key])), key)
	# 撃破は覚醒前・覚醒後とも専用（金環日食が欠けて消えていく。2026-11-13）
	assert_eq(VictoryPlayer.defeat_script("lion"), Defeat)
	assert_eq(VictoryPlayer.defeat_script("lion_awakened"), Defeat)
	# 登場（剣の雨 → 巨大な剣 → 金の大爆発 → 咆哮。2026-11-13）と支援（回復・強化）
	assert_true(IntroPlayer.has_intro("lion"))
	assert_eq(IntroPlayer.CHOREO["lion"], Intro)
	var stage := RBMBattleStage.new()
	assert_eq(stage.BOSS_SUPPORT_PRESENTATIONS["lion"], Support)
	assert_eq(stage.BOSS_SUPPORT_PRESENTATIONS["lion_awakened"], Support)
	stage.free()
	for script in [Intro, Defeat]:
		var consts: Dictionary = script.get_script_constant_map()
		for key in consts.get("SOUNDS", []):
			assert_true(ResourceLoader.exists("res://assets_bossmaker/audio/%s.wav" % str(key).trim_prefix("game:")), str(key))
		for path in consts.get("EXTRA_PATHS", []) + consts.get("VFX_PATHS", []):
			assert_true(ResourceLoader.exists(str(path)), str(path))

## 本体はキーポーズをそのまま切り替えるだけ（中割りなし）。ポーズの番号・位置・オーラの距離がそろっている。
func test_key_poses_and_their_data_line_up() -> void:
	for move in RBMLionMotion.MOVES:
		var n := RBMLionMotion.pose_count(move)
		assert_gt(n, 0, move)
		assert_eq((RBMLionMotion.anchors()[move] as Array).size(), n, move + ": anchors for every pose")
		for i in range(1, n + 1):
			var tex := load(RBMLionMotion.pose_path(move, i)) as Texture2D
			assert_eq(tex.get_size(), Vector2(320, 180), "%s %d keeps the key pose canvas" % [move, i])
		var fx: RBMLionFxBase = (Driver.FX_SCRIPTS[move] as GDScript).new()
		for k in fx.pose_keys():
			assert_between(int(k[1]), 0, n, "%s uses only its own poses (0 = stance)" % move)
		var last := -1.0
		for s in fx.stops():
			assert_gt(float(s[0]), last, move + ": hit stops in order")
			last = float(s[0])
		assert_lt(fx.impact(), fx.duration(), move)
		fx.free()
	for move in RBMLionMotion.AURA_POSES:
		for i in RBMLionMotion.AURA_POSES[move]:
			assert_true(ResourceLoader.exists(RBMLionMotion.field_path(move, i)), "baked aura field %s %d" % [move, i])

## 覚醒後全体: 後脚で立つポーズ（2枚目）は使わず、咆哮（3枚目）は太陽が落ちてくる所の1回だけ（2026-11-12 ユーザー指定）。
func test_awakened_all_roars_once_and_never_rears_up() -> void:
	var fx: RBMLionFxBase = (Driver.FX_SCRIPTS["post_all"] as GDScript).new()
	var roars := 0
	for k in fx.pose_keys():
		assert_ne(int(k[1]), 2, "no rearing pose")
		if int(k[1]) == 3:
			roars += 1
			var t_map: Dictionary = fx.get_script().get_script_constant_map()["T"]
			assert_almost_eq(float(k[0]), float(t_map.fall), 0.001, "the roar comes with the falling sun")
	assert_eq(roars, 1)
	fx.free()

func test_every_warm_path_exists() -> void:
	for asset_id in ["lion", "lion_awakened"]:
		for kind in ["single", "all", "awakening", "support"]:
			for path in Driver.warm_paths(asset_id, kind):
				assert_true(ResourceLoader.exists(path), path)

## 支援（2026-11-13）: 立ち姿 → 支援のポーズ → 立ち姿（切り替えは1回だけ）。回復・強化とも命中（数字）は1回、戦闘は変えず、終わると元へ戻る。
func test_support_changes_pose_once_and_shows_one_number() -> void:
	for aw in [false, true]:
		for mode in ["heal", "buff"]:
			var f := _support_fixture(mode, aw)
			assert_false(f.entry.is_empty(), "%s %s: a real support entry" % [aw, mode])
			if f.entry.is_empty(): continue
			var snapshot: Dictionary = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Support, "the lion's own support")
			if not d is Support: continue
			var form := "post" if aw else "pre"
			assert_eq(d.move, form + "_support")
			assert_eq(d._fx.heal, mode == "heal")
			assert_eq(d._fx.awakened, aw)
			assert_eq(d._audio.stream.resource_path, str(AudioCatalog.FILES[("lion_awakened_" if aw else "lion_") + mode]))
			var keys: Array = d._fx.pose_keys()
			assert_eq(keys.size(), 3)
			assert_eq([int(keys[0][1]), int(keys[2][1])], [0, 0], "starts and ends in the stance")
			assert_eq(int(keys[1][1]), int(Driver.SUPPORT_POSE[d.move][1]))
			assert_true(d._textures.has(int(keys[1][1])), "the borrowed pose is loaded")
			f.stage._tween.custom_step(d.impact_time - .01)
			assert_eq(seen.size(), 0)
			f.stage._tween.custom_step(.02)
			assert_eq(seen.size(), 1)
			f.stage._tween.custom_step(20)
			assert_eq(seen.size(), 1)
			assert_null(f.stage._skill_presentation)
			assert_eq(f.session.battle.snapshot(), snapshot)
			assert_true(f.stage._visuals.boss.visible)
			for key in f.stage._homes:
				assert_eq(f.stage._visuals[key].position, f.stage._homes[key])
			f.stage.queue_free()
			await get_tree().process_frame

func _support_fixture(mode: String, awakened: bool) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_lion"
	draft.boss_name = "Lion QA"
	draft.hp = 3000
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Support", "type": "self_heal" if mode == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_lion")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	return {"stage": stage, "session": session, "entry": entry, "skill": RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)}

## 登場（2026-11-13）: 剣が順に刺さり、最後に巨大な剣 → 爆発 → 聖獣が現れて咆哮 → 立ち姿。カメラは寄らない（揺れだけ）。
func test_intro_order_and_body_reveal() -> void:
	var t_map: Dictionary = (IntroFx as Script).get_script_constant_map()["T"]
	var swords: Array = t_map.swords
	for i in range(1, swords.size()):
		assert_gt(float(swords[i]), float(swords[i - 1]), "swords land one after another")
	assert_lt(float(swords[-1]), float(t_map.giant_in))
	assert_lt(float(t_map.giant_in), float(t_map.giant_hit))
	assert_lt(float(t_map.giant_hit), float(t_map.burst))
	assert_lt(float(t_map.burst), float(t_map.reveal))
	assert_lt(float(t_map.reveal), float(t_map.roar))
	assert_lt(float(t_map.roar), float(t_map.stance))
	var fx: RBMLionFxBase = IntroFx.new()
	fx.seq = "pre_all"
	var back := Node2D.new()
	var front := Node2D.new()
	add_child_autofree(back)
	add_child_autofree(front)
	fx.mid = back
	add_child_autofree(fx)
	fx.setup(back, front, [])
	fx.advance_pose(float(t_map.giant_hit))
	assert_true(bool(fx.view.body.get("hidden", false)), "the beast is not there before the blast")
	fx.advance_pose(float(t_map.roar))
	assert_false(bool(fx.view.body.get("hidden", false)))
	assert_eq(int(fx.view.body.pose), 3, "roars on the roar pose")
	fx.advance_pose(float(t_map.stance) + 0.1)
	assert_eq(int(fx.view.body.pose), 0, "ends in the stance")
	var src := FileAccess.get_file_as_string((Intro as Script).resource_path)
	for call in ["camera.cut(", "\tcut(", "\tpan("]:
		assert_false(src.contains(call), "no zoom (shake only): " + call)

## 撃破（2026-11-13）: 金環日食が上から両側へ欠けていき、最後は消える。体も輪に合わせて光の粒になってほどける。
func test_defeat_eclipse_wanes_away() -> void:
	var t_map: Dictionary = (FallFx as Script).get_script_constant_map()["T"]
	var fx: RBMLionFxBase = FallFx.new()
	var back := Node2D.new()
	var front := Node2D.new()
	add_child_autofree(back)
	add_child_autofree(front)
	add_child_autofree(fx)
	fx.setup(back, front, [])
	var last := -1.0
	for t in [0.0, float(t_map.wane), (float(t_map.wane) + float(t_map.last)) * 0.5, float(t_map.last)]:
		var w: float = fx.wane_at(t)
		assert_true(w >= last, "the ring only wanes")
		last = w
	assert_eq(fx.wane_at(float(t_map.wane)), 0.0)
	assert_almost_eq(fx.wane_at(float(t_map.last)), 1.0, 0.001)
	fx.advance_pose(float(t_map.full))
	assert_true(fx.eclipse.visible, "the annular eclipse is up")
	fx.advance_pose(float(t_map.end))
	assert_false(fx.eclipse.visible, "and gone at the end")
	assert_lt(float(t_map.melt), float(t_map.gone))
	assert_lt(float(t_map.gone), float(t_map.end))

## 撃破の後に剣が床に刺さって残る（2026-11-13 ユーザー指定）。覚醒後は別の時刻で、長く・爆発つき（「もっと派手に」）。
func test_defeat_leaves_a_sword_and_the_awakened_one_is_bigger() -> void:
	var consts: Dictionary = (FallFx as Script).get_script_constant_map()
	var t_map: Dictionary = consts["T"]
	var ta_map: Dictionary = consts["TA"]
	for tm in [t_map, ta_map]:
		assert_lt(float(tm.last), float(tm.stab), "the sword comes after the last fragment")
		assert_lt(float(tm.stab), float(tm.end))
	assert_gt(float(ta_map.end), float(t_map.end), "the awakened defeat lasts longer")
	assert_true(ta_map.has("burst") and ta_map.has("flare"), "the awakened defeat flares and explodes")
	assert_lt(float(ta_map.last), float(ta_map.burst))
	for aw in [false, true]:
		var fx: RBMLionFxBase = FallFx.new()
		fx.awakened = aw
		var back := Node2D.new()
		var front := Node2D.new()
		add_child_autofree(back)
		add_child_autofree(front)
		add_child_autofree(fx)
		fx.setup(back, front, [])
		assert_eq(fx.tm(), ta_map if aw else t_map)
		assert_eq(fx.duration(), float((ta_map if aw else t_map).end))
		assert_eq(fx.blast != null, aw, "only the awakened defeat has the big explosion")
	# 撃破のスクリプトは剣の層を最後まで消さない（結果の画面まで残る）
	var src := FileAccess.get_file_as_string((Defeat as Script).resource_path)
	assert_false(src.contains("_world.visible = false"), "the sword stays until the victory layer is cleared")
	assert_eq(Array((Defeat as Script).get_script_constant_map()["SOUNDS"]).size(), 2, "the awakened defeat has its own sound")

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
			var expected: String = ("post" if aw else "pre") + ("_single" if kind == "single" else "_all")
			assert_eq(d.move, expected)
			assert_false(f.stage._visuals.boss.visible, "The presentation draws the body itself")
			f.stage._tween.custom_step(d.impact_time - .01)
			assert_eq(seen.size(), 0, "No impact before the final blow")
			if not d._fx.hits().is_empty():
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
		assert_eq(d._focus_delta, world - Driver.PARTY[Driver.SINGLE_SLOT])
		var probe: RBMLionFxBase = d._fx.get_script().new()
		assert_eq(d._fx._reach() - d._focus_delta, probe._reach(), "The leap moves with the target")
		probe.free()
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

func test_awakening_turns_into_the_eclipse_form_with_the_sun_aura() -> void:
	var f := _fixture("single")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry({"actor": "boss", "action": "awakening"})
	var d = f.stage._skill_presentation
	assert_true(d is Driver)
	assert_eq(d.move, "awaken")
	# 皆既の後は姿が影になる（目だけが光る）
	var t_map: Dictionary = d._fx.get_script().get_script_constant_map()["T"]
	f.stage._tween.custom_step(d._fx.unwarp(float(t_map.total) + 0.5))
	assert_gt(float(d._fx.view["hero"].get("silhouette", 0.0)), 0.9, "The body turns into a shadow after totality")
	f.stage._tween.custom_step(d.duration)
	assert_eq(seen.size(), 1)
	assert_eq(f.stage._asset_ids.boss, "lion_awakened")
	assert_true(f.stage._visuals.boss.visible)
	assert_true(f.stage._visuals.boss is Visual)
	assert_not_null(f.stage._visuals.boss.find_child("LionSunAura", false, false), "Awakened idle wears the sun aura")
	assert_eq(f.stage.scale, Vector2.ONE)
	# 巻き戻しで覚醒前へ戻るとオーラも消える
	var before: Dictionary = f.stage._state.duplicate(true)
	before.is_awakened = false
	f.stage.set_state(before)
	assert_eq(f.stage._asset_ids.boss, "lion")
	await get_tree().process_frame
	assert_null(f.stage._visuals.boss.find_child("LionSunAura", false, false))

func test_selection_save_and_reload() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("user://lion_integration_roundtrip")
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	var d = creator.draft
	d.appearance_id = "appearance_lion"; d.boss_name = "金環の聖獣本番統合"; d.hp = 400; d.atk = 17; d.spd = 1
	d.add_party_character("hero")
	d.add_skill({"name": "爪撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.2})
	d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 50, "heal_percent": 0.0}})
	var before: Dictionary = d.to_definition().duplicate(true)
	var saved: Dictionary = creator.press_save_as_new()
	assert_true(saved.get("ok", false))
	var loaded := RBMCreatorMain.new(); add_child_autofree(loaded)
	assert_true(loaded.start_loaded(str(saved.stage_id)).get("ok", false))
	assert_eq(loaded.draft.appearance_id, "appearance_lion")
	assert_eq(loaded.draft.to_definition(), before)
	var picker := RBMCreatorAppearancePicker.new(); add_child_autofree(picker)
	picker.open("")
	assert_true(picker._entry_buttons.has("appearance_lion"))
	picker._entry_buttons["appearance_lion"].pressed.emit()
	var toggle := picker.find_child("AwakenedPreviewToggle", true, false) as Button
	assert_not_null(toggle)
	if toggle != null:
		assert_true(toggle.visible)
		assert_false(toggle.disabled)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
