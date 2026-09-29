extends GutTest
## 朽ちた機械武者の覚醒演出「封剣機構・解放」と覚醒後の単体/全体攻撃(承認済みv4)、
## および持続オーラの独立部品としての契約テスト。見た目・映像の質はGPU実機
## (tools/verify_musha_awakening_gpu.gd)で確認し、ここでは確定タイムライン・一度きりの
## 発火・後始末・音の重複禁止・戦闘不変・覚醒状態への追従を検証する。
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const Awakening = preload("res://src/bossmaker/visuals/rbm_musha_awakening.gd")
const Attack = preload("res://src/bossmaker/visuals/rbm_musha_awakened_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

func after_each() -> void:
	await get_tree().process_frame

func _draft(kind: String = "single", attribute: String = "NEUTRAL", ids: Array = ["hero", "butler", "healer", "samurai"]) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha Awakening QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ids:
		draft.add_party_character(id)
	var spec := {"name": "Musha QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Musha tune", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	return draft

func _stage_for(session: RBMCreatorTestSession) -> RBMBattleStage:
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_musha")
	stage.set_state(session.battle.presentation_state())
	return stage

## 覚醒をまだ起こしていない戦闘。
func _plain_fixture(kind: String = "single", attribute: String = "NEUTRAL") -> Dictionary:
	var draft := _draft(kind, attribute)
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	var stage := _stage_for(session)
	var entry: Dictionary = {}
	for attempt in range(12):
		for e in session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", str(draft.skills[0].get("skill_id", "")), session.battle)
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

## 覚醒条件(HP50%以下)を満たす戦闘。
func _awakening_fixture() -> Dictionary:
	var draft := _draft()
	draft.set_awakening({
		"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
		"heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0},
	})
	var session := RBMCreatorTestSession.new(draft.to_definition(), 1)
	session.battle.boss.hp = 1000
	var stage := _stage_for(session)
	var entry: Dictionary = {}
	for e in session.resolve_ally_action({"type": "attack"}):
		if str(e.get("action", "")) == "awakening":
			entry = e
	return {"stage": stage, "session": session, "entry": entry}

## 覚醒済みの戦闘(外見が覚醒後)。
func _awakened_fixture(kind: String, attribute: String = "NEUTRAL", counter: bool = false) -> Dictionary:
	var ids: Array = ["hero", "butler", "healer", "samurai"]
	if counter:
		ids = ["samurai"] if kind == "single" else ["samurai", "hero", "healer", "butler"]
	var draft := _draft(kind, attribute, ids)
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = true
	var stage := _stage_for(session)
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		for e in session.resolve_ally_action(action):
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", str(draft.skills[0].get("skill_id", "")), session.battle)
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

# ---------------------------------------------------------------------------
# 承認済みタイムライン(純粋な時刻→状態)
# ---------------------------------------------------------------------------

func test_durations_impacts_and_shake_peaks_are_the_approved_values() -> void:
	assert_eq(Motion.duration("awakening"), 6.9)
	assert_eq(Motion.duration("single"), 4.5)
	assert_eq(Motion.duration("all"), 7.0)
	assert_eq(Motion.impact_time("single"), 2.15)
	assert_eq(Motion.impact_time("all"), 4.85)
	assert_eq(Motion.shake_force("awakening", 4.8), 55.0)
	assert_eq(Motion.shake_force("single", 2.15), 38.0)
	assert_eq(Motion.shake_force("all", 4.85), 68.0)
	assert_almost_eq(Motion.shake_force("all", 4.85 + 0.625), 34.0, 0.001, "decays over 1.25 seconds")
	assert_eq(Motion.shake_force("all", 4.85 + 1.25), 0.0)
	assert_eq(Motion.shake_force("single", 1.0), 0.0)

func test_awakening_body_timeline() -> void:
	var samples := {0.5: [0, true], 0.9: [0, false], 3.0: [0, false], 3.5: [0, true], 4.0: [1, true], 4.8: [2, true], 5.5: [3, true]}
	for t in samples:
		var state := Motion.body_state("awakening", float(t))
		assert_eq(int(state.index), samples[t][0], "index at %.1f" % t)
		assert_eq(bool(state.eye), samples[t][1], "eye at %.1f" % t)
	assert_eq(float(Motion.body_state("awakening", 2.0).bands), 0.0)
	assert_gt(float(Motion.body_state("awakening", 4.0).bands), 0.5, "the coat deforms in bands while unsealing")
	assert_eq(float(Motion.body_state("awakening", 5.4).bands), 0.0)
	assert_eq(Motion.APPEARANCE_SWITCH, 5.3)

func test_lock_bars_unlock_in_sequence_shoulders_arms_legs() -> void:
	for i in range(6):
		var start := 1.8 + i * 0.2
		assert_lt(Motion.lock_age(i, start - 0.01), 0.0)
		assert_gte(Motion.lock_age(i, start + 0.01), 0.0)
		assert_lt(Motion.lock_age(i, start + 0.7), 0.0)

func test_aura_appears_between_5_15_and_5_65_during_the_awakening() -> void:
	assert_eq(Motion.aura_power(5.0), 0.0)
	assert_almost_eq(Motion.aura_power(5.4), 0.5, 0.05)
	assert_eq(Motion.aura_power(5.65), 1.0)

func test_attack_body_timeline_swings_once_in_100ms_without_moving() -> void:
	for kind in ["single", "all"]:
		var sweep := Motion.sweep_start(kind)
		var start := 0.60 if kind == "single" else 0.75
		assert_eq(Motion.body_state(kind, start - 0.01).source, "awakened", "idle before the raised guard")
		var frames: Array = []
		for t in [start + 0.05, sweep - 0.01, sweep + 0.01, sweep + 0.05, sweep + 0.08, sweep + 0.5]:
			var state := Motion.body_state(kind, t)
			frames.append("%s%d" % [state.source, state.index])
		assert_eq(frames, ["swing0", "swing0", "swing1", "swing2", "swing3", "swing3"], "raised guard, then the 100ms downswing in four distinct frames")
	assert_eq(Motion.body_state("single", 3.6).source, "awakened", "single returns to the drawn-sword wait after 3.55")
	assert_eq(Motion.body_state("all", 6.2).source, "awakened", "all returns after 6.15")
	assert_eq(int(Motion.body_state("all", 6.2).index), 3)

func test_brush_and_reaction_windows() -> void:
	assert_lt(Motion.brush_age("single", 2.0), 0.0)
	assert_almost_eq(Motion.brush_age("single", 2.65), 0.5, 0.001)
	assert_lt(Motion.brush_age("single", 3.7), 0.0, "gone after 1.5 seconds")
	assert_true(Motion.target_reacting("all", 4.9))
	assert_false(Motion.target_reacting("all", 5.2))

func test_brush_atlas_has_attribute_and_suffix_glyphs() -> void:
	var regions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets_bossmaker/battle/musha_awakened/new_regions.json"))
	assert_true(regions is Dictionary)
	assert_gte(((regions as Dictionary)["brush"] as Array).size(), 7, "無炎氷雷風 + 境 + 界")
	for asset in ["awakened.png", "swing.png", "brush.png", "design.png"]:
		assert_true(ResourceLoader.exists("res://assets_bossmaker/battle/musha_awakened/" + asset, "Texture2D"), asset)
	assert_true(RBMVisualAssets.has_pose_frames("musha_awakened"))

# ---------------------------------------------------------------------------
# 覚醒エントリ
# ---------------------------------------------------------------------------

func test_awakening_entry_plays_once_switches_appearance_and_keeps_the_aura() -> void:
	var f = _awakening_fixture()
	assert_false(f.entry.is_empty(), "the real awakening entry")
	var snapshot = f.session.battle.snapshot().duplicate(true)
	var stage: RBMBattleStage = f.stage
	var impacts: Array = []
	var finishes: Array = []
	stage.impact.connect(func(e):
		impacts.append(e)
		stage.set_state(e.get("visual_state", f.session.battle.presentation_state())))
	stage.finished.connect(func(): finishes.append(true))
	stage._sound.history.clear()
	stage.play_entry(f.entry)
	var driver = stage._skill_presentation
	assert_true(driver is Awakening)
	assert_eq(stage._phase, "awakening")
	assert_false(stage._awakening_transform.visible, "the dedicated effect replaces the placeholder flash")
	assert_eq(stage._sound.history, ["musha_awakening"])
	assert_false(stage._visuals["boss"].visible, "the drawn body replaces the boss visual during the effect")
	stage._tween.custom_step(Motion.APPEARANCE_SWITCH - .01)
	assert_eq(stage._asset_ids["boss"], "musha")
	assert_eq(impacts.size(), 0)
	stage._tween.custom_step(.02)
	assert_eq(stage._asset_ids["boss"], "musha_awakened")
	stage._tween.custom_step(Motion.AWAKENING_DURATION)
	await get_tree().process_frame
	assert_eq(impacts.size(), 1, "impact exactly once, at the end (existing awakening contract)")
	assert_eq(impacts[0], f.entry)
	assert_eq(finishes.size(), 1)
	assert_eq(stage._sound.history, ["musha_awakening"], "the approved track plays once")
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_false(is_instance_valid(driver))
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._asset_ids["boss"], "musha_awakened")
	assert_true(stage._musha_aura.visible, "the persistent aura stays after the awakening")
	assert_eq(stage._musha_aura.power(), 1.0)
	assert_eq(f.session.battle.snapshot(), snapshot, "presentation never touches the simulation")
	for key in stage._homes:
		assert_eq(stage._visuals[key].position, stage._homes[key])

func test_cancel_mid_awakening_restores_the_snapshot_form_and_replays() -> void:
	for elapsed in [.2, 2.4, 3.5, 4.9, 5.5, 6.5]:
		var f = _awakening_fixture()
		var stage: RBMBattleStage = f.stage
		var impacts: Array = []
		stage.impact.connect(func(e): impacts.append(e))
		stage.play_entry(f.entry)
		var driver = stage._skill_presentation
		stage._tween.custom_step(elapsed)
		stage.cancel()
		await get_tree().process_frame
		assert_false(is_instance_valid(driver))
		assert_false(stage.is_playing())
		assert_true(stage._visuals["boss"].visible)
		assert_eq(impacts.size(), 0, "a cancelled awakening never emits impact")
		# 覚醒前のスナップショットへ戻れば通常の外見・オーラ無し。
		var before_state: Dictionary = stage._state.duplicate(true)
		before_state["is_awakened"] = false
		stage.set_state(before_state)
		assert_eq(stage._asset_ids["boss"], "musha")
		assert_false(stage._musha_aura.visible)
		stage.play_entry(f.entry)
		stage._tween.custom_step(20.0)
		await get_tree().process_frame
		assert_eq(impacts.size(), 1)
		assert_eq(stage._asset_ids["boss"], "musha_awakened")

func test_restored_awakened_snapshot_shows_the_awakened_form_and_aura_without_replaying() -> void:
	var f = _awakened_fixture("single")
	var stage: RBMBattleStage = f.stage
	assert_eq(stage._asset_ids["boss"], "musha_awakened")
	assert_true(stage._musha_aura.visible)
	assert_false(stage.is_playing())

# ---------------------------------------------------------------------------
# 覚醒後の単体/全体
# ---------------------------------------------------------------------------

func test_awakened_attacks_strike_once_at_the_approved_moment_and_return_home() -> void:
	for kind in ["single", "aoe"]:
		for color in Palette.COLORS:
			var f = _awakened_fixture(kind, color)
			var stage: RBMBattleStage = f.stage
			var before = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			stage.impact.connect(func(e): seen.append(e))
			stage._sound.history.clear()
			stage.play_entry(f.entry, f.skill)
			var d = stage._skill_presentation
			assert_true(d is Attack, "dedicated awakened presentation is chosen for %s" % kind)
			assert_eq(d.kind, "all" if kind == "aoe" else "single")
			assert_eq(d.impact_time, 4.85 if kind == "aoe" else 2.15)
			# 承認済み(2026-09-27): 単体は掲げてから2.4秒の溜めの後に、全体は見えない速さの抜刀・納め直しの後に遅れて着弾する。
			# 元の時刻(impact_time)は変えず、演出の時刻で通知が一度だけ出る。
			assert_eq(d.strike_at, 8.92 if kind == "aoe" else 4.55)
			assert_eq(d._attribute, color)
			stage._tween.custom_step(d.strike_at - .01)
			assert_eq(seen.size(), 0, "the precursor line/incision opening must not strike")
			stage._tween.custom_step(.02)
			assert_eq(seen, [f.entry])
			stage._tween.custom_step(10)
			assert_eq(seen.size(), 1, "damage is notified exactly once")
			assert_eq(f.session.battle.snapshot(), before)
			assert_eq(stage._sound.history, ["musha_awakened_aoe" if kind == "aoe" else "musha_awakened_single"], "the completed track only")
			assert_false(stage.is_playing())
			assert_null(stage._skill_presentation)
			assert_true(stage._visuals["boss"].visible)
			assert_eq(stage._asset_ids["boss"], "musha_awakened", "the awakened state is not reverted by an attack ending")
			assert_true(stage._musha_aura.visible, "the aura outlives the attack")
			for key in stage._homes:
				assert_eq(stage._visuals[key].position, stage._homes[key])

func test_attack_does_not_move_the_boss_toward_the_target() -> void:
	var f = _awakened_fixture("single")
	var stage: RBMBattleStage = f.stage
	stage.play_entry(f.entry, f.skill)
	var d = stage._skill_presentation
	var home: Vector2 = stage._foot("boss")
	var elapsed := 0.0
	for t in [.7, 1.0, 1.4, 2.0, 3.0]:
		stage._tween.custom_step(t - elapsed)
		elapsed = t
		assert_eq(d._body._foot, home, "the awakened boss stays planted at %.1f" % t)
	stage.cancel()

func test_cancel_every_phase_cleans_up_and_replays_without_losing_the_aura() -> void:
	for kind in ["single", "aoe"]:
		for t in [.4, .95, 1.5, 2.2, 3.0, 4.6, 5.2, 6.4]:
			var f = _awakened_fixture(kind)
			var stage: RBMBattleStage = f.stage
			var seen: Array = []
			stage.impact.connect(func(e): seen.append(e))
			stage.play_entry(f.entry, f.skill)
			var d = stage._skill_presentation
			stage._tween.custom_step(t)
			var count = seen.size()
			stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(d))
			assert_false(stage.is_playing())
			assert_true(stage._visuals["boss"].visible)
			assert_true(stage._musha_aura.visible, "cancelling an attack does not end the awakened state")
			for key in stage._homes:
				assert_eq(stage._visuals[key].position, stage._homes[key])
			stage.play_entry(f.entry, f.skill)
			stage._tween.custom_step(20.0)
			assert_eq(seen.size(), count + 1)

func test_real_counter_preserves_damage_and_cleanup() -> void:
	for kind in ["single", "aoe"]:
		var f = _awakened_fixture(kind, "WIND", true)
		var stage: RBMBattleStage = f.stage
		var count = int(f.entry.get("counter", false))
		for hit in f.entry.get("hits", {}).values():
			count += int(hit.get("counter", false))
		assert_eq(count, 1)
		var snapshot = f.session.battle.snapshot().duplicate(true)
		var seen: Array = []
		stage.impact.connect(func(e): seen.append(e))
		stage.play_entry(f.entry, f.skill)
		stage._tween.custom_step(1.7)
		assert_eq(seen.size(), 0)
		for i in range(200):
			if not stage.is_playing():
				break
			stage._tween.custom_step(.1)
		assert_eq(seen, [f.entry])
		assert_eq(f.session.battle.snapshot(), snapshot)
		assert_false(stage.is_playing())
		assert_true(stage._musha_aura.visible)

func test_awakened_support_uses_the_awakened_body_and_the_same_tracks() -> void:
	for kind in ["buff", "heal"]:
		var f = _awakened_fixture(kind)
		var stage: RBMBattleStage = f.stage
		stage._sound.history.clear()
		stage.play_entry(f.entry, f.skill)
		var d = stage._skill_presentation
		assert_true(d._awakened)
		for i in range(240):
			stage._tween.custom_step(1.0 / 60.0)
			assert_eq(int(d._body._state.get("pose", -1)), -1, "no sheathing/bowing pose exists for the awakened form")
		stage._tween.custom_step(10)
		assert_eq(stage._sound.history, ["musha_buff" if kind == "buff" else "musha_heal"])
		assert_eq(stage._asset_ids["boss"], "musha_awakened")
		assert_true(stage._musha_aura.visible)

# ---------------------------------------------------------------------------
# 持続オーラ(独立部品)
# ---------------------------------------------------------------------------

func test_aura_follows_the_awakened_state_only() -> void:
	var f = _plain_fixture()
	var stage: RBMBattleStage = f.stage
	assert_false(stage._musha_aura.visible, "no aura before the awakening")
	var awakened_state: Dictionary = stage._state.duplicate(true)
	awakened_state["is_awakened"] = true
	stage.set_state(awakened_state)
	assert_eq(stage._asset_ids["boss"], "musha_awakened")
	assert_true(stage._musha_aura.visible)
	awakened_state["is_awakened"] = false
	stage.set_state(awakened_state)
	assert_false(stage._musha_aura.visible, "rewinding to before the awakening removes it")

func test_aura_is_separate_from_temporary_buffs_and_never_covers_the_body() -> void:
	var f = _awakened_fixture("buff")
	var stage: RBMBattleStage = f.stage
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(20.0)
	assert_true(stage._musha_aura.visible, "the aura is not a temporary buff; buff playback/expiry never stops it")
	# 戦場全体の補正・墨は、すべてボス(z=1)より背面に描く(本体と赤い単眼を埋もれさせない)。
	var boss_index: int = stage._visuals["boss"].get_index()
	for child in stage._musha_aura.get_children():
		if child == stage._musha_aura._eye:
			continue  # 単眼の光(加算)だけは本体の上に重ねる
		assert_lte(child.z_index, stage._visuals["boss"].z_index, "%s stays behind the boss" % child.name)
	assert_lt(stage._musha_aura.get_index(), boss_index, "the aura sits before the boss in draw order (ties at z=1 go to the boss)")

func test_the_normal_form_never_shows_the_aura() -> void:
	var f = _plain_fixture("aoe")
	var stage: RBMBattleStage = f.stage
	stage.play_entry(f.entry, f.skill)
	stage._tween.custom_step(20.0)
	assert_false(stage._musha_aura.visible)
	assert_eq(stage._asset_ids["boss"], "musha")

## 覚醒系の完成トラックも、補正ゲインで鳴る(+3dB)。
func test_awakening_and_awakened_tracks_are_played_with_the_loudness_compensation_gain() -> void:
	var GainMotion = load("res://src/bossmaker/visuals/rbm_musha_motion.gd")
	var f = _awakening_fixture()
	f.stage.play_entry(f.entry)
	var found := false
	for player in f.stage._sound._players:
		if player.playing and absf(player.volume_db - (-9.0 + GainMotion.track_gain("musha_awakening"))) < 0.001:
			found = true
	assert_true(found, "musha_awakening is played with its gain")
	f.stage.cancel()
	for kind in ["single", "aoe"]:
		var g = _awakened_fixture(kind)
		g.stage.play_entry(g.entry, g.skill)
		# 単体は溜めの後(track_at)に完成トラックを鳴らし始める(承認済み 2026-09-27)
		g.stage._tween.custom_step(float(g.stage._skill_presentation.track_at) + .01)
		var key := "musha_awakened_aoe" if kind == "aoe" else "musha_awakened_single"
		var ok := false
		for player in g.stage._sound._players:
			if player.playing and absf(player.volume_db - (-9.0 + GainMotion.track_gain(key))) < 0.001:
				ok = true
		assert_true(ok, "%s is played with its gain" % key)
		g.stage.cancel()
