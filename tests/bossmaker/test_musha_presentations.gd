extends GutTest
## 朽ちた機械武者の専用演出(単体v3・全体v3・強化回復v1)の本番契約テスト。
## 見た目・映像の質はGPU実機(tools/verify_musha_gpu.gd)で確認し、ここでは
## 確定タイムライン・strikeの一度きり・後始末・音の重複禁止・戦闘不変を検証する。
const Driver = preload("res://src/bossmaker/visuals/rbm_musha_presentation.gd")
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
## 演出の契約は、事前読み込みが素材を読み終えた状態で検証する(QA-06。読み終えていない時の待ちは
## test_rbm_presentation_warmup.gd が検証する)。
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["musha"])

func after_all() -> void:
	_ready_assets.clear()

func after_each() -> void:
	await get_tree().process_frame

func _fixture(kind: String, attribute: String = "NEUTRAL", counter: bool = false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids:
		draft.add_party_character(id)
	var spec := {"name": "Musha QA skill", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	if kind in ["buff", "heal"]:
		spec = {"name": "Musha tune", "type": "self_heal" if kind == "heal" else "atk_self_buff", "heal_amount": 200, "buff_multiplier": 1.3, "duration_turns": 3}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_musha")
	stage.set_state(session.battle.presentation_state())
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		var entries := session.resolve_ally_action(action)
		for e in entries:
			if str(e.get("actor")) == "boss":
				entry = e
		if not entry.is_empty():
			break
	var skill := RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)
	if kind in ["buff", "heal"]:
		skill.attribute = attribute
	return {"stage": stage, "session": session, "entry": entry, "skill": skill}

func _restored(stage) -> void:
	assert_false(stage.is_playing())
	assert_null(stage._skill_presentation)
	assert_true(stage._visuals["boss"].visible)
	assert_eq(stage._asset_ids["boss"], "musha")
	for key in stage._homes:
		assert_eq(stage._visuals[key].position, stage._homes[key])

# ---------------------------------------------------------------------------
# 承認済みタイムライン(純粋な時刻→状態)
# ---------------------------------------------------------------------------

func _motion(home: Vector2 = Vector2(948, 518), target: Vector2 = Vector2(266, 492)) -> Motion:
	var m := Motion.new()
	m.configure(home, target)
	return m

func test_durations_and_strike_times_are_the_approved_values() -> void:
	assert_eq(Motion.duration("single"), 5.2)
	assert_eq(Motion.duration("all"), 7.0)
	assert_eq(Motion.duration("support"), 4.2)
	assert_eq(Motion.strike_time("single"), 2.75, "strike follows the giant final slash, not the first (text-less) hit")
	assert_eq(Motion.strike_time("all"), 4.15)

func test_single_body_timeline() -> void:
	var m := _motion()
	assert_eq(m.body_state("single", 0.2).pose, -1)
	assert_eq(m.body_state("single", 0.5).pose, 0)
	assert_almost_eq(float(m.body_state("single", 0.72).scale_y), 0.965, 0.0001)
	assert_almost_eq(float(m.body_state("single", 1.0).scale_y), 0.965, 0.0001, "completely still 0.72..1.22")
	assert_false(bool(m.body_state("single", 1.25).visible), "instant disappearance, not a slide")
	var behind: Dictionary = m.body_state("single", 1.5)
	assert_eq(behind.pose, 1)
	assert_true(bool(behind.flip))
	assert_eq(Vector2(behind.foot), Vector2(266, 492) + Motion.BEHIND_OFFSET, "behind the target: (266,492)+(-119,13) = (147,505)")
	assert_eq(Vector2(behind.foot), Vector2(147, 505))
	assert_true(float(m.body_state("single", 1.92).alpha) < 1.0, "fading out behind the target")
	var home_state: Dictionary = m.body_state("single", 2.3)
	assert_eq(home_state.pose, 2, "sheathing at home")
	assert_eq(Vector2(home_state.foot), Vector2(948, 518))
	assert_eq(m.body_state("single", 2.8).pose, -1)
	assert_eq(m.body_state("single", 5.0).pose, -1)

func test_all_body_timeline_swings_once_and_sheathes_last() -> void:
	var m := _motion()
	var poses: Array = []
	for t in [0.5, 0.9, 1.3, 1.6, 3.0, 4.5, 5.0, 5.2, 5.6, 6.5]:
		poses.append(m.body_state("all", t).pose)
	assert_eq(poses, [-1, 0, 3, 4, 4, 4, 2, 2, -1, -1], "one downswing held until 4.8, sheathe 4.8..5.4 (v3: sheathe last, not the rejected v4)")

func test_support_is_identical_for_buff_and_heal_and_only_the_body_pose_changes() -> void:
	var m := _motion()
	assert_eq(m.body_state("support", 0.2).pose, -1)
	assert_eq(m.body_state("support", 1.0).pose, 5)
	assert_eq(m.body_state("support", 2.9).pose, -1)
	var mid := float(m.body_state("support", 1.575).scale_y)
	assert_almost_eq(mid, 1.0 - 0.018, 0.001, "subtle 1.8% dip at the middle")

func test_shake_forces() -> void:
	var m := _motion()
	assert_eq(m.shake_force("single", 2.75), 42.0)
	assert_almost_eq(m.shake_force("single", 2.75 + 0.375), 21.0, 0.001)
	assert_eq(m.shake_force("single", 3.6), 0.0)
	assert_eq(m.shake_force("all", 1.6), 5.0)
	assert_eq(m.shake_force("all", 3.0), 3.0)
	assert_eq(m.shake_force("all", 4.15), 42.0)
	assert_eq(m.shake_force("all", 5.0), 0.0)
	assert_eq(m.shake_force("support", 2.0), 0.0)

func test_glyph_sizes_and_reaction_windows() -> void:
	var m := _motion()
	assert_eq(float(m.glyph_state("single", 2.8).size), 255.0)
	assert_lt(float(m.glyph_state("single", 1.4).age), 0.0, "no glyph on the first strike of the single attack")
	assert_eq(float(m.glyph_state("all", 2.0).size), 130.0)
	assert_eq(float(m.glyph_state("all", 4.3).size), 255.0)
	assert_true(Motion.target_reacting("single", 1.4, 0, 1))
	assert_false(Motion.target_reacting("single", 2.0, 0, 1))
	assert_true(Motion.target_reacting("single", 2.9, 0, 1))
	assert_true(Motion.target_reacting("all", 1.6, 2, 4))
	assert_true(Motion.target_reacting("all", 4.3, 3, 4))
	assert_eq(Motion.glyph_index("NEUTRAL"), 0)
	assert_eq(Motion.glyph_index("FIRE"), 1)
	assert_eq(Motion.glyph_index("ICE"), 2)
	assert_eq(Motion.glyph_index("LIGHTNING"), 3)
	assert_eq(Motion.glyph_index("WIND"), 4)

func test_ice_glyph_uses_the_dedicated_image() -> void:
	var regions: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets_bossmaker/battle/musha/regions.json"))
	assert_true(regions is Dictionary)
	assert_true((regions as Dictionary).has("ice"), "ink.png's third glyph reads as 水; ice.png is the approved replacement")
	assert_true(ResourceLoader.exists("res://assets_bossmaker/battle/musha/ice.png", "Texture2D"))

# ---------------------------------------------------------------------------
# 本番ステージ上の再生契約
# ---------------------------------------------------------------------------

func test_stage_dispatches_only_the_expected_presentation_scripts() -> void:
	assert_true(RBMBattleStage.BOSS_SINGLE_PRESENTATIONS.has("musha"))
	assert_true(RBMBattleStage.BOSS_ALL_PRESENTATIONS.has("musha"))
	assert_true(RBMBattleStage.BOSS_SUPPORT_PRESENTATIONS.has("musha"))
	# 振り分け表にある武者以外のボスはすべて、それぞれ自分の演出のまま
	var others := 0
	for other in RBMBattleStage.BOSS_SINGLE_PRESENTATIONS:
		if str(other).begins_with("musha"):
			continue
		others += 1
		assert_ne(RBMBattleStage.BOSS_SINGLE_PRESENTATIONS[other], RBMBattleStage.BOSS_SINGLE_PRESENTATIONS["musha"], "%s keeps its own presentation" % other)
	assert_gt(others, 0, "the existing golem (at least) is compared")

func test_attacks_all_colors_strike_once_at_the_final_slash_and_return_home() -> void:
	for kind in ["single", "aoe"]:
		for color in Palette.COLORS:
			var f = _fixture(kind, color)
			var before = f.session.battle.snapshot().duplicate(true)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage._sound.history.clear()
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			assert_true(d is Driver)
			assert_eq(d._attribute, color)
			assert_eq(d._hit_points.size(), 4 if kind == "aoe" else 1)
			assert_eq(d.impact_time, 4.15 if kind == "aoe" else 2.75)
			f.stage._tween.custom_step(d.impact_time - .01)
			assert_eq(seen.size(), 0, "the first hit / the 28 follow-up slashes must not strike")
			f.stage._tween.custom_step(.02)
			assert_eq(seen, [f.entry])
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(), 1, "damage is notified exactly once")
			assert_eq(f.session.battle.snapshot(), before, "presentation never touches the simulation")
			assert_eq(f.stage._sound.history.count("musha_aoe" if kind == "aoe" else "musha_single"), 1)
			assert_eq(f.stage._sound.history.size(), 1, "the completed track only; no generic cast/release/impact SE layered on top")
			_restored(f.stage)

func test_support_plays_one_track_and_identical_motion_for_buff_and_heal() -> void:
	var reference: Array = []
	for kind in ["buff", "heal"]:
		var f = _fixture(kind, "ICE" if kind == "buff" else "FIRE")
		f.stage._sound.history.clear()
		f.stage.play_entry(f.entry, f.skill)
		var d = f.stage._skill_presentation
		assert_eq(d.action_kind, kind)
		assert_eq(d._color, Color("ef4847") if kind == "buff" else Color("71da87"), "colour only differs; independent of the skill attribute")
		var samples: Array = []
		for i in range(240):
			f.stage._tween.custom_step(1.0 / 60.0)
			samples.append(d._body._state.duplicate(true))
		if reference.is_empty():
			reference = samples
		else:
			assert_eq(samples, reference, "buff and heal share body/timing exactly")
		f.stage._tween.custom_step(10)
		assert_eq(f.stage._sound.history, ["musha_buff" if kind == "buff" else "musha_heal"])
		_restored(f.stage)

func test_generic_se_phases_are_suppressed_by_the_presentation() -> void:
	var f = _fixture("single")
	f.stage.play_entry(f.entry, f.skill)
	var d = f.stage._skill_presentation
	for phase in ["cast", "release", "impact"]:
		assert_true(d.play_sound_phase(phase))
	f.stage.cancel()

func test_covering_ally_is_the_single_target_and_the_boss_appears_behind_them() -> void:
	var f = _fixture("single")
	var state: Dictionary = f.stage._state.duplicate(true)
	state.party["1"].protecting_ally_id = 0
	f.stage._state = state
	f.stage.play_entry({"actor": "boss", "action": "attack", "target": 1, "visual_original_target": 0, "amount": 20, "attribute": "ICE"})
	var d = f.stage._skill_presentation
	var foot: Vector2 = f.stage._foot("1") + Vector2(f.stage._guard_offsets["1"])
	assert_eq(d.motion.behind, foot + Motion.BEHIND_OFFSET, "positions come from the resolved target, not a fixed index")
	f.stage._tween.custom_step(1.5)
	assert_eq(Vector2(d._body._state.foot), foot + Motion.BEHIND_OFFSET)
	f.stage.cancel()
	_restored(f.stage)

func test_cancel_every_phase_restores_and_replays() -> void:
	for kind in ["single", "aoe", "buff", "heal"]:
		for t in [.4, .95, 1.45, 2.2, 2.9, 3.6, 4.4]:
			var f = _fixture(kind)
			var seen: Array = []
			f.stage.impact.connect(func(e): seen.append(e))
			f.stage.play_entry(f.entry, f.skill)
			var d = f.stage._skill_presentation
			f.stage._tween.custom_step(t)
			var count = seen.size()
			f.stage.cancel()
			await get_tree().process_frame
			assert_false(is_instance_valid(d))
			_restored(f.stage)
			f.stage.play_entry(f.entry, f.skill)
			f.stage._tween.custom_step(10)
			assert_eq(seen.size(), count + 1)
			_restored(f.stage)

func test_real_counter_preserves_damage_and_cleanup() -> void:
	for kind in ["single", "aoe"]:
		var f = _fixture(kind, "WIND", true)
		var count = int(f.entry.get("counter", false))
		for hit in f.entry.get("hits", {}).values():
			count += int(hit.get("counter", false))
		assert_eq(count, 1)
		var snapshot = f.session.battle.snapshot().duplicate(true)
		var seen: Array = []
		f.stage.impact.connect(func(e): seen.append(e))
		f.stage.play_entry(f.entry, f.skill)
		f.stage._tween.custom_step(1.7)
		assert_eq(seen.size(), 0)
		for i in range(180):
			if not f.stage.is_playing():
				break
			f.stage._tween.custom_step(.1)
		assert_eq(seen, [f.entry])
		assert_eq(f.session.battle.snapshot(), snapshot)
		_restored(f.stage)

func test_large_time_step_does_not_fire_strike_or_sound_twice() -> void:
	for kind in ["single", "aoe"]:
		var f = _fixture(kind)
		var seen: Array = []
		f.stage.impact.connect(func(e): seen.append(e))
		f.stage._sound.history.clear()
		f.stage.play_entry(f.entry, f.skill)
		f.stage._tween.custom_step(0.5)
		f.stage._tween.custom_step(20.0)
		assert_eq(seen.size(), 1)
		assert_eq(f.stage._sound.history.size(), 1)
		_restored(f.stage)

## 完成トラックは、既存の音と揃えた補正ゲイン(RBMMushaMotion.TRACK_GAIN_DB)で鳴る。
func test_completed_tracks_are_played_with_the_loudness_compensation_gain() -> void:
	for kind in ["single", "aoe", "buff", "heal"]:
		var f = _fixture(kind, "ICE" if kind == "buff" else "FIRE")
		f.stage.play_entry(f.entry, f.skill)
		var key: String = {"single": "musha_single", "aoe": "musha_aoe", "buff": "musha_buff", "heal": "musha_heal"}[kind]
		var expected: float = -9.0 + Motion.track_gain(key)
		var found := false
		for player in f.stage._sound._players:
			if player.playing and absf(player.volume_db - expected) < 0.001:
				found = true
		assert_true(found, "%s is played at %.1f dB" % [key, expected])
		f.stage.cancel()
