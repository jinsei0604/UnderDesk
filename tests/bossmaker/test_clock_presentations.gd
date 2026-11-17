extends GutTest
## 振り子の給仕長／終刻の給仕長（clock）の本番の演出の契約（2026-11-16〜17 に確認動画で採用した5技・登場・支援・撃破・常時のオーラ）。
## 表示だけで戦闘を変えない・命中は1回・途中の当たりの小さな数字・後始末・覚醒で外見が替わる・選択と保存。作りは test_lion_presentations.gd と同じ。
const Driver = preload("res://src/bossmaker/visuals/clock/rbm_clock_presentation.gd")
const Visual = preload("res://src/bossmaker/visuals/clock/rbm_clock_visual.gd")
const AudioCatalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const Intro = preload("res://src/bossmaker/visuals/encounter/intro/rbm_intro_clock.gd")
const Defeat = preload("res://src/bossmaker/visuals/clock/rbm_clock_defeat.gd")
const Support = preload("res://src/bossmaker/visuals/clock/rbm_clock_support.gd")
const IntroFx = preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_intro.gd")
const FallFx = preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_fall.gd")
const FallAwakenedFx = preload("res://src/bossmaker/visuals/clock/rbm_clock_fx_fall_awakened.gd")
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["clock"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(kind: String, awakened: bool = false, counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_clock"
	draft.boss_name = "Clock QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Clock QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_clock")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		for e in session.resolve_ally_action(action):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

## エフェクトだけを木に入れて動かす（つなぎなし）
func _fx_in_tree(script: GDScript) -> Node:
	var fx = script.new()
	var back := Node2D.new()
	var front := Node2D.new()
	add_child_autofree(back)
	add_child_autofree(front)
	fx.mid = back
	add_child_autofree(fx)
	fx.setup(back, front, [])
	return fx

func test_registered_like_the_other_bosses() -> void:
	assert_true(RBMCreatorAppearanceCatalog.supports_awakening("appearance_clock"))
	assert_eq(RBMCreatorAppearanceCatalog.display_name("appearance_clock"), TranslationServer.translate("振り子の給仕長"))
	assert_eq(RBMVisualAssets.boss_asset("appearance_clock"), "clock")
	assert_true(RBMVisualAssets.has_awakened_design("clock"))
	assert_true(RBMVisualAssets.has_pose_frames("clock"))
	assert_true(RBMVisualAssets.has_pose_frames("clock_awakened"))
	assert_eq(RBMVisualAssets.display_height("clock"), 176.0)
	assert_eq(RBMVisualAssets.display_height("clock_awakened"), 188.0)
	for key in ["clock_single", "clock_all", "clock_awakening", "clock_awakened_single", "clock_awakened_all", "clock_heal", "clock_buff", "clock_awakened_heal", "clock_awakened_buff"]:
		assert_true(ResourceLoader.exists(str(AudioCatalog.FILES[key])), key)
	# 登場・支援・撃破（2026-11-17 ユーザー「これでいいね」で本番へ）
	assert_eq(VictoryPlayer.defeat_script("clock"), Defeat)
	assert_eq(VictoryPlayer.defeat_script("clock_awakened"), Defeat)
	assert_true(IntroPlayer.has_intro("clock"))
	assert_eq(IntroPlayer.CHOREO["clock"], Intro)
	var stage := RBMBattleStage.new()
	assert_eq(stage.BOSS_SUPPORT_PRESENTATIONS["clock"], Support)
	assert_eq(stage.BOSS_SUPPORT_PRESENTATIONS["clock_awakened"], Support)
	assert_true(stage.BOSS_SINGLE_PRESENTATIONS.has("clock") and stage.BOSS_ALL_PRESENTATIONS.has("clock_awakened") and stage.BOSS_AWAKENING_PRESENTATIONS.has("clock"))
	stage.free()
	for script in [Intro, Defeat]:
		var consts: Dictionary = script.get_script_constant_map()
		for key in consts.get("SOUNDS", []):
			assert_true(ResourceLoader.exists("res://assets_bossmaker/audio/%s.wav" % str(key).trim_prefix("game:")), str(key))
		for path in consts.get("EXTRA_PATHS", []) + consts.get("VFX_PATHS", []):
			assert_true(ResourceLoader.exists(str(path)), str(path))

## 本体はキーポーズをそのまま切り替えるだけ（中割りなし）。ポーズの番号・位置・オーラの距離がそろっている。借りるポーズは番号9など、技の絵と重ならない。
func test_key_poses_and_their_data_line_up() -> void:
	for move in RBMClockMotion.MOVES:
		var n := RBMClockMotion.pose_count(move)
		assert_gt(n, 0, move)
		assert_eq((RBMClockMotion.anchors()[move] as Array).size(), n, move + ": anchors for every pose")
		for i in range(1, n + 1):
			var tex := load(RBMClockMotion.pose_path(move, i)) as Texture2D
			assert_eq(tex.get_size(), Vector2(320, 180), "%s %d keeps the key pose canvas" % [move, i])
		var fx: RBMClockFxBase = (Driver.FX_SCRIPTS[move] as GDScript).new()
		var extra: Dictionary = fx.extra_poses()
		for k in fx.pose_keys():
			var p := int(k[1])
			assert_true((p >= 0 and p <= n) or extra.has(p), "%s uses only its own poses, the stance (0) or borrowed ones" % move)
		for k in extra:
			assert_gt(int(k), n, move + ": a borrowed pose never hides one of its own")
			assert_true(ResourceLoader.exists(RBMClockMotion.pose_path(str(extra[k][0]), int(extra[k][1]))), str(extra[k]))
		var last := -1.0
		for s in fx.stops():
			assert_gt(float(s[0]), last, move + ": hit stops in order")
			last = float(s[0])
		assert_lt(fx.impact(), fx.duration(), move)
		fx.free()
	for move in RBMClockMotion.AURA_POSES:
		for i in RBMClockMotion.AURA_POSES[move]:
			assert_true(ResourceLoader.exists(RBMClockMotion.field_path(move, i)), "baked aura field %s %d" % [move, i])

func test_every_warm_path_exists() -> void:
	for asset_id in ["clock", "clock_awakened"]:
		for kind in ["single", "all", "awakening", "support"]:
			for path in Driver.warm_paths(asset_id, kind):
				assert_true(ResourceLoader.exists(path), path)

## 支援: 立ち姿 → 支援のポーズ（回復＝全体の2枚目・強化＝3枚目）→ 立ち姿（切り替えは1回だけ）。回復・強化とも命中（数字）は1回、戦闘は変えず、終わると元へ戻る。
## 覚醒後は支援のポーズの間もオーラが消えない（2026-11-15 ユーザー「覚醒後のときオーラ消えてるときある」）。
## 登場（2026-11-14〜15 ユーザーの案）: 花びらが少し → だんだん多く → 画面を覆い隠す → 晴れるとお辞儀をしている → 顔を上げて構え。カメラは寄らない（揺れだけ）。
## 撃破（2026-11-14〜16）: 花びらになってほどけ、床にカラーが一輪だけ残る。残った花は光を消さずに照らし続ける（2026-11-16 ユーザー指定）。
## 覚醒後は覚醒前より長く派手（背の大輪が枯れて弾ける）。
## 支援: 立ち姿 → 支援のポーズ（回復＝全体の2枚目・強化＝3枚目）→ 立ち姿（切り替えは1回だけ）。回復・強化とも命中（数字）は1回、戦闘は変えず、終わると元へ戻る。
## 覚醒後は支援のポーズの間もオーラが消えない（2026-11-15 ユーザー「覚醒後のときオーラ消えてるときある」）。
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
			assert_true(d is Support, "the boss's own support")
			if not d is Support: continue
			var form := "post" if aw else "pre"
			assert_eq(d.move, form + "_support")
			assert_eq(d._fx.heal, mode == "heal")
			assert_eq(d._fx.awakened, aw)
			assert_eq(d._audio.stream.resource_path, str(AudioCatalog.FILES[("clock_awakened_" if aw else "clock_") + mode]))
			var keys: Array = d._fx.pose_keys()
			assert_eq(keys.size(), 3)
			assert_eq([int(keys[0][1]), int(keys[2][1])], [0, 0], "starts and ends in the stance")
			var borrowed := int(keys[1][1])
			assert_eq(d._extra_src[borrowed], Driver.SUPPORT_POSES[d.move][mode], "borrows the pose the warm-up reads ahead")
			assert_true(d._textures.has(borrowed), "the borrowed pose is loaded")
			f.stage._tween.custom_step(d._fx.unwarp(float(keys[1][0])) + 0.1)
			assert_eq(int(d._fx.body.pose), borrowed)
			assert_eq(d._aura.visible, aw, "the awakened aura stays on in the borrowed pose")
			f.stage._tween.custom_step(d.impact_time - d.age - .01)
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
	draft.appearance_id = "appearance_clock"
	draft.boss_name = "Clock QA"
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
	stage.configure(session.battle, "appearance_clock")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	return {"stage": stage, "session": session, "entry": entry, "skill": RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)}

## 登場（2026-11-16〜17）: 懐中時計が降りて刻む → 12時でひび → 砕けて飛び散る途中で時が止まる → 止まった中で一礼して現れる → 時が動く → 構え。
## 砕けるまで体は出さない（2026-11-16 ユーザー「壊れる前に後ろにボスの足が出ちゃってる」）。カメラは寄らない（揺れだけ）。
func test_intro_shatters_then_stops_time_and_bows() -> void:
	var t_map: Dictionary = (IntroFx as Script).get_script_constant_map()["T"]
	var order := ["drop", "twelve", "burst", "stop", "bow", "resume", "rise", "end"]
	for i in range(1, order.size()):
		assert_lt(float(t_map[order[i - 1]]), float(t_map[order[i]]), order[i])
	var fx: RBMClockFxBase = _fx_in_tree(IntroFx)
	for t in [0.5, float(t_map.twelve), float(t_map.burst) + 0.03, float(t_map.stop) + 0.1]:
		fx.advance_pose(t)
		assert_true(bool(fx.view.body.get("hidden", false)), "nobody is there before the watch is gone (%.2f)" % t)
	fx.advance_pose(float(t_map.bow) + 0.2)
	assert_false(bool(fx.view.body.get("hidden", false)))
	assert_eq(int(fx.view.body.pose), int(IntroFx.BOW), "bowing while time stands still")
	assert_false(fx.watch.visible, "the watch has shattered")
	assert_gt(float(fx.view.get("post", {}).get("desat", 0.0)), 0.5, "colour drains while time is stopped")
	fx.advance_pose(float(t_map.rise) + 0.1)
	assert_eq(int(fx.view.body.pose), 0, "then takes the stance")
	var src := FileAccess.get_file_as_string((Intro as Script).resource_path)
	for call in ["camera.cut(", "\tcut(", "\tpan("]:
		assert_false(src.contains(call), "no zoom (shake only): " + call)

## 撃破（2026-11-16〜17）: 覚醒前は寝かせた小さな懐中時計、覚醒後は大時計の針が逆回転して12時で砕け、立てた懐中時計が残る。残った時計は照らされたまま。
func test_defeats_leave_a_lit_pocket_watch_and_the_awakened_one_rewinds() -> void:
	var t_map: Dictionary = (FallFx as Script).get_script_constant_map()["T"]
	var ta_map: Dictionary = (FallAwakenedFx as Script).get_script_constant_map()["TP"]
	for pair in [[t_map, ["slow", "stop", "crack", "melt", "gone", "remain", "end"]], [ta_map, ["surge", "sky", "twelve", "gone", "remain", "end"]]]:
		var tm: Dictionary = pair[0]
		var order: Array = pair[1]
		for i in range(1, order.size()):
			assert_lt(float(tm[order[i - 1]]), float(tm[order[i]]), str(order[i]))
	assert_gt(float(ta_map.end), float(t_map.end), "the awakened defeat lasts longer")
	for script in [FallFx, FallAwakenedFx]:
		var fx: RBMClockFxBase = _fx_in_tree(script)
		var end := float(fx.duration())
		fx.advance_pose(float(fx.impact()) + 1.2)
		assert_almost_eq(float(fx.body.dissolve), 1.0, 0.001, "gone by then")
		fx.advance_pose(end)
		assert_true(fx.left.visible, "a pocket watch is left on the floor")
		var lit := 0.0
		for c in fx.b_shaft._c:
			lit = maxf(lit, c.a)
		assert_gt(lit, 0.05, "and stays lit until the result screen")
	# 覚醒後: 大時計の針は反時計回り（角度が減っていく）
	var fa: RBMClockFxBase = _fx_in_tree(FallAwakenedFx)
	var minutes: Array = []
	for t in [float(ta_map.sky) + 0.3, float(ta_map.sky) + 0.6, float(ta_map.sky) + 0.9]:
		fa.advance_pose(t)
		minutes.append(float((fa.sky.material as ShaderMaterial).get_shader_parameter("minute")))
	assert_lt(float(minutes[1]), float(minutes[0]), "the hands rewind (counter-clockwise)")
	assert_lt(float(minutes[2]), float(minutes[1]))
	var src := FileAccess.get_file_as_string((Defeat as Script).resource_path)
	assert_false(src.contains("_world.visible = false"), "the watch stays until the victory layer is cleared")
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

## 覚醒後の単体: 止まった時の中で繰り出した連撃が、時が動くと何回も当たる（2026-11-16 ユーザー「ヒット判定が複数回」）。最後は振り子の一撃。
func test_awakened_single_lands_a_flurry_then_the_pendulum() -> void:
	var fx: RBMClockFxBase = (Driver.FX_SCRIPTS["post_single"] as GDScript).new()
	var hits: Array = fx.hits()
	assert_gte(hits.size(), 5, "a flurry of hits")
	var last := -1.0
	for h in hits:
		assert_gt(float(h[0]), last, "one after another")
		assert_lt(float(h[0]), fx.impact(), "all before the pendulum's final blow")
		last = float(h[0])
	fx.free()
	var f := _fixture("single", true)
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	f.stage._tween.custom_step(d.impact_time - .02)
	assert_gte(f.stage._damage_numbers._numbers.size(), 5, "each hit of the flurry shows its own small number")
	f.stage._tween.custom_step(30)
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
		assert_eq(d._fx.focus_delta, d._focus_delta, "the effect moves with the target")
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

func test_awakening_turns_into_the_awakened_form_with_the_aura() -> void:
	var f := _fixture("single")
	var seen: Array = []
	f.stage.impact.connect(func(e): seen.append(e))
	f.stage.play_entry({"actor": "boss", "action": "awakening"})
	var d = f.stage._skill_presentation
	assert_true(d is Driver)
	assert_eq(d.move, "awaken")
	f.stage._tween.custom_step(d.duration * 0.5)
	f.stage._tween.custom_step(d.duration)
	assert_eq(seen.size(), 1)
	assert_eq(f.stage._asset_ids.boss, "clock_awakened")
	assert_true(f.stage._visuals.boss.visible)
	assert_true(f.stage._visuals.boss is Visual)
	assert_not_null(f.stage._visuals.boss.find_child("ClockSunAura", false, false), "Awakened idle wears the aura")
	assert_eq(f.stage.scale, Vector2.ONE)
	# 巻き戻しで覚醒前へ戻るとオーラも消える
	var before: Dictionary = f.stage._state.duplicate(true)
	before.is_awakened = false
	f.stage.set_state(before)
	assert_eq(f.stage._asset_ids.boss, "clock")
	await get_tree().process_frame
	assert_null(f.stage._visuals.boss.find_child("ClockSunAura", false, false))

func test_selection_save_and_reload() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing("user://clock_integration_roundtrip")
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	var d = creator.draft
	d.appearance_id = "appearance_clock"; d.boss_name = "振り子の給仕長本番統合"; d.hp = 400; d.atk = 17; d.spd = 1
	d.add_party_character("hero")
	d.add_skill({"name": "QA攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.2})
	d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND", "buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 50, "heal_percent": 0.0}})
	var before: Dictionary = d.to_definition().duplicate(true)
	var saved: Dictionary = creator.press_save_as_new()
	assert_true(saved.get("ok", false))
	var loaded := RBMCreatorMain.new(); add_child_autofree(loaded)
	assert_true(loaded.start_loaded(str(saved.stage_id)).get("ok", false))
	assert_eq(loaded.draft.appearance_id, "appearance_clock")
	assert_eq(loaded.draft.to_definition(), before)
	var picker := RBMCreatorAppearancePicker.new(); add_child_autofree(picker)
	picker.open("")
	assert_true(picker._entry_buttons.has("appearance_clock"))
	picker._entry_buttons["appearance_clock"].pressed.emit()
	var toggle := picker.find_child("AwakenedPreviewToggle", true, false) as Button
	assert_not_null(toggle)
	if toggle != null:
		assert_true(toggle.visible)
		assert_false(toggle.disabled)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
