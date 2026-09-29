extends GutTest
## 朽ちた機械武者の覚醒後の常時オーラ(戦場全体の変質)の契約テスト。見た目・映像の質は
## GPU実機(tools/verify_musha_aura_gpu.gd)で確認し、ここでは時間割・出現/消滅・演出中の
## 静音化・表示専用(戦闘不変)・本体を隠さない描画順・背景(松明/溝)の扱いを検証する。
const Aura = preload("res://src/bossmaker/visuals/rbm_musha_aura.gd")
const Timeline = preload("res://src/bossmaker/visuals/rbm_musha_aura_timeline.gd")
const Ink = preload("res://src/bossmaker/visuals/rbm_musha_aura_ink.gd")
const Shaders = preload("res://src/bossmaker/visuals/rbm_musha_aura_shaders.gd")
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")

func after_each() -> void:
	await get_tree().process_frame

func _session(ids: Array = ["hero", "butler", "healer", "samurai"]) -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha Aura QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ids:
		draft.add_party_character(id)
	var id := draft.add_skill({"name": "Musha QA skill", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	return RBMCreatorTestSession.new(draft.to_definition(), 5)

func _stage(session: RBMCreatorTestSession, awakened: bool) -> RBMBattleStage:
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_musha")
	var state: Dictionary = session.battle.presentation_state().duplicate(true)
	state["is_awakened"] = awakened
	stage.set_state(state)
	return stage

# ---------------------------------------------------------------------------
# 時間割(純粋関数)
# ---------------------------------------------------------------------------

func test_the_timeline_is_deterministic() -> void:
	for age in [0.0, 1.7, 4.4, 9.3, 27.9]:
		assert_eq(Timeline.eye_env(age), Timeline.eye_env(age))
		assert_eq(Timeline.compress(age), Timeline.compress(age))
		assert_eq(Timeline.slash(age), Timeline.slash(age))
		assert_eq(Timeline.edge(age), Timeline.edge(age))
	assert_eq(Timeline.edge_shape(3, Vector2(1280, 720)), Timeline.edge_shape(3, Vector2(1280, 720)))

func test_events_never_overlap_themselves_and_stay_sparse() -> void:
	# 各出来事の間隔の最小値が継続時間より長い(重なって派手にならない)。
	var kinds := [
		["eye", Timeline.EYE_FIRST, Timeline.EYE_PERIOD, Timeline.EYE_JITTER, 11.0, Timeline.EYE_SPAN],
		["compress", Timeline.COMPRESS_FIRST, Timeline.COMPRESS_PERIOD, Timeline.COMPRESS_JITTER, 23.0, Timeline.COMPRESS_SPAN],
		["slash", Timeline.SLASH_FIRST, Timeline.SLASH_PERIOD, Timeline.SLASH_JITTER, 37.0, Timeline.SLASH_SPAN],
		["edge", Timeline.EDGE_FIRST, Timeline.EDGE_PERIOD, Timeline.EDGE_JITTER, 51.0, Timeline.EDGE_SPAN],
	]
	for kind in kinds:
		var previous := -1.0
		for k in range(60):
			var at := Timeline.event_time(kind[1], kind[2], kind[3], kind[4], k)
			if previous >= 0.0:
				assert_gte(at - previous, float(kind[5]), "%s #%d does not overlap the previous one" % [kind[0], k])
			previous = at
	# 数秒に一度(眼)・2〜3秒に1回程度(空間圧)。
	assert_between(Timeline.EYE_PERIOD, 3.5, 6.0)
	assert_between(Timeline.COMPRESS_PERIOD, 2.0, 3.0)
	assert_gte(Timeline.SLASH_PERIOD - Timeline.SLASH_JITTER * 0.5, 6.0, "the slash mark is rare")

func test_envelopes_are_bounded_and_quiet_before_the_first_event() -> void:
	assert_eq(Timeline.eye_env(0.0), 0.0)
	assert_eq(Timeline.jolt(0.0), 0.0)
	assert_eq(Timeline.compress(0.0), 0.0)
	assert_eq(int(Timeline.slash(0.0).index), -1)
	assert_eq(int(Timeline.edge(0.0).index), -1)
	var eye_peak := 0.0
	var jolt_peak := 0.0
	var comp_peak := 0.0
	for i in range(0, 3000):
		var age := i * 0.01
		var e := Timeline.eye_env(age)
		var j := Timeline.jolt(age)
		var c := Timeline.compress(age)
		assert_between(e, 0.0, 1.0)
		assert_between(j, 0.0, 1.0)
		assert_between(c, 0.0, 1.0)
		eye_peak = maxf(eye_peak, e)
		jolt_peak = maxf(jolt_peak, j)
		comp_peak = maxf(comp_peak, c)
	assert_gt(eye_peak, 0.9, "the eye does light up")
	assert_gt(jolt_peak, 0.6, "the field reacts to the eye")
	assert_gt(comp_peak, 0.9, "the space compresses")

func test_compression_is_only_a_pixel_or_two() -> void:
	# シェーダーの定数: 端(約640px)でも2px前後、沈みは1px強。「画面揺れ」にしない。
	var code: String = Shaders.POST
	assert_true(code.contains("0.0032*comp"), "edge shift is 0.0032 * distance")
	assert_lt(0.0032 * 640.0, 2.5)
	assert_true(code.contains("vec2(0.0,1.2*comp)"))

func test_edge_ink_enters_from_outside_toward_the_inside() -> void:
	var size := Vector2(1280, 720)
	for k in range(12):
		var shape := Timeline.edge_shape(k, size)
		var base: Vector2 = shape.base
		assert_true(base.x < 0.0 or base.x > size.x or base.y < 0.0 or base.y > size.y, "stroke %d starts outside the stage" % k)
		var direction := Vector2(sin(float(shape.theta)), -cos(float(shape.theta)))
		assert_gt(direction.dot(size * 0.5 - base), 0.0, "stroke %d points inward" % k)

func test_slash_is_a_short_straight_mark_beside_the_body() -> void:
	for k in range(12):
		var shape := Timeline.slash_shape(k)
		var offset: Vector2 = shape.offset
		assert_gte(absf(offset.x), 56.0)
		assert_lt(offset.y, -60.0)
		assert_between(float(shape.length), 62.0, 88.0)
		assert_between(absf(float(shape.angle)), 0.28, 0.6, "vertical/diagonal only")

func test_groove_traces_are_few_and_start_after_the_aura_appears() -> void:
	assert_true(Timeline.active_traces(Timeline.TRACE_FIRST - 0.01).is_empty())
	for i in range(0, 400):
		var traces := Timeline.active_traces(i * 0.1)
		assert_lte(traces.size(), 7)
		for t in traces:
			assert_lt(int(t.path), Timeline.TRACE_POOL)

# ---------------------------------------------------------------------------
# 溝に沿う墨筆の通り道
# ---------------------------------------------------------------------------

func test_groove_paths_follow_a_dark_groove_and_stay_on_the_ground() -> void:
	var foot := Vector2(600, 400)
	# 明るい石畳に、足元から少し下(y=410)を横切る暗い溝が1本。
	var luminance := func(p: Vector2) -> float:
		return 0.10 if absf(p.y - 410.0) < 2.5 else 0.45
	var paths := Ink.groove_paths(luminance, foot, 700.0)
	assert_eq(paths.size(), Timeline.TRACE_POOL)
	var again := Ink.groove_paths(luminance, foot, 700.0)
	assert_eq(paths, again, "deterministic")
	for path in paths:
		assert_gt(path.size(), 30)
		for p in path:
			assert_gte(p.y, foot.y - 8.0 - 4.0)
			assert_lte(p.y, 700.0 + 1.0)
	# 溝の近くから始まる墨筆は、溝(y=410)の近くを進む。
	var near := 0
	for path in paths:
		var sum := 0.0
		for p in path:
			sum += absf(p.y - 410.0)
		if sum / path.size() < 6.0:
			near += 1
	assert_gt(near, paths.size() / 2, "most traces settle into the groove")

# ---------------------------------------------------------------------------
# コンポーネント
# ---------------------------------------------------------------------------

func test_eye_offset_matches_the_awakened_idle_pose() -> void:
	var expected: Vector2 = (Vector2(Motion.ATLAS_EYES[3]) - Vector2(Motion.ATLAS_FEET[3])) * Motion.ATLAS_SCALE
	assert_almost_eq(Aura.EYE_OFFSET.x, expected.x, 0.1)
	assert_almost_eq(Aura.EYE_OFFSET.y, expected.y, 0.1)

func test_the_field_widens_over_seconds_during_the_awakening_but_not_on_restore() -> void:
	var stage := _stage(_session(), false)
	var aura: Node2D = stage._musha_aura
	assert_false(aura.visible)
	assert_eq(aura.amount, 0.0)
	# 覚醒演出の途中: 出現区間の強さが渡され、影響は数秒かけて広がる。
	aura.power_override = 0.0
	aura.refresh()
	assert_true(aura.visible)
	aura._advance(0.5)
	assert_eq(aura.amount, 0.0, "nothing before the aura appears")
	aura.power_override = 1.0
	aura._advance(1.0)
	assert_gt(aura.amount, 0.0)
	assert_lt(aura.amount, 0.9, "still widening after one second")
	# 外見が覚醒後へ切り替わり(演出の途中)、そのあと演出が終わる。
	var awakened_state: Dictionary = stage._state.duplicate(true)
	awakened_state["is_awakened"] = true
	stage.set_state(awakened_state)
	aura.power_override = -1.0
	aura.refresh()
	assert_true(aura.visible, "the awakened form keeps it (after the awakening ends)")
	assert_lt(aura.amount, 0.95, "the widening is not cut short when the effect ends")
	for i in range(8):
		aura._advance(0.5)
	assert_eq(aura.amount, 1.0)
	# 覚醒済みのスナップショットの復元は、広がりを待たず完成形から。
	var restored := _stage(_session(), true)
	assert_true(restored._musha_aura.visible)
	assert_eq(restored._musha_aura.amount, 1.0)

func test_the_field_disappears_when_the_form_returns_to_normal() -> void:
	var stage := _stage(_session(), true)
	var aura: Node2D = stage._musha_aura
	aura._process(0.1)
	assert_gt(aura.amount, 0.0)
	var state: Dictionary = stage._state.duplicate(true)
	state["is_awakened"] = false
	stage.set_state(state)
	assert_false(aura.visible)
	assert_eq(aura.amount, 0.0)
	assert_eq(aura._event_age, 0.0)
	for key in stage._visuals:
		assert_null(stage._visuals[key].material, "no ally keeps the grading material")

func test_events_fire_while_idle_and_go_quiet_during_playback() -> void:
	var stage := _stage(_session(), true)
	var aura: Node2D = stage._musha_aura
	var eye_peak := 0.0
	var comp_count := 0
	var was_compressing := false
	for i in range(0, 1800):
		aura._advance(1.0 / 30.0)
		eye_peak = maxf(eye_peak, aura.eye)
		var now: bool = aura.compression > 0.5
		if now and not was_compressing:
			comp_count += 1
		was_compressing = now
	assert_gt(eye_peak, 0.9)
	# 60秒で、2〜3秒に1回程度(およそ20回)。
	assert_between(comp_count, 15, 30)
	# 演出中(攻撃/覚醒の再生中)は出来事を引っ込める(常時の色・光・足元の墨だけ)。
	stage._playing = true
	for i in range(0, 60):
		aura._advance(1.0 / 30.0)
	assert_lt(aura.quiet_gate, 0.01)
	assert_eq(aura.eye, 0.0)
	assert_eq(aura.jolt, 0.0)
	assert_eq(aura.compression, 0.0)
	assert_eq(aura.amount, 1.0, "the constant field stays")
	var frozen: float = aura._event_age
	aura._advance(1.0)
	assert_eq(aura._event_age, frozen, "the schedule waits while playing")
	stage._playing = false
	for i in range(0, 30):
		aura._advance(1.0 / 30.0)
	assert_gt(aura.quiet_gate, 0.99)

func test_the_field_is_display_only_and_never_touches_the_battle() -> void:
	var session := _session()
	var stage := _stage(session, true)
	var before: Dictionary = session.battle.snapshot().duplicate(true)
	var aura: Node2D = stage._musha_aura
	for i in range(0, 600):
		aura._process(1.0 / 30.0)
	assert_eq(session.battle.snapshot(), before)

func test_the_scene_nodes_are_laid_out_behind_the_body() -> void:
	var stage := _stage(_session(), true)
	var aura: Node2D = stage._musha_aura
	aura._process(0.1)
	assert_true(aura._post.visible)
	assert_eq(aura._post.size, stage.size, "the full pass covers the stage")
	assert_eq(aura._post.z_index, 1, "behind the boss (z=1, later in the tree), so the body keeps its colours")
	assert_eq(int(stage._visuals[stage._party_keys[0]].z_index), 2, "allies are in front of the pass; they get the grading material instead")
	assert_lt(aura.get_index(), stage._visuals["boss"].get_index())
	for child in aura.get_children():
		if child is Control:
			assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s never blocks clicks" % child.name)
	# 足元の墨染みはボスの足元に置かれ、味方の足元にも薄く置かれる。
	assert_true(aura._boss_blot.visible)
	var foot: Vector2 = aura._home_foot("boss")
	assert_true(aura._boss_blot.get_rect().has_point(foot))
	var visible_ally_blots := 0
	for rect in aura._ally_blots:
		if rect.visible:
			visible_ally_blots += 1
	assert_eq(visible_ally_blots, 4)

func test_allies_get_the_grading_material_and_the_boss_does_not() -> void:
	var stage := _stage(_session(), true)
	var aura: Node2D = stage._musha_aura
	aura._process(0.1)
	assert_null(stage._visuals["boss"].material, "the boss keeps its own colours")
	for key in stage._party_keys:
		assert_true(stage._visuals[key].material is ShaderMaterial, "ally %s is graded" % key)
		for child in stage._visuals[key].get_children():
			if child is CanvasItem:
				assert_true((child as CanvasItem).use_parent_material, "ally accessories are graded too")
	# 覚醒後の攻撃が始まっても(補正は常時)味方は補正されたまま、位置は変わらない。
	for key in stage._homes:
		assert_eq(stage._visuals[key].position, stage._homes[key])

func test_no_post_pass_or_ink_before_the_awakening() -> void:
	var stage := _stage(_session(), false)
	var aura: Node2D = stage._musha_aura
	for i in range(0, 60):
		aura._process(1.0 / 30.0)
	assert_false(aura.visible)
	assert_false(aura._post.visible)
	assert_false(aura._boss_blot.visible)

func test_the_background_gives_torch_positions_and_groove_paths() -> void:
	var stage := _stage(_session(), true)
	var bg := TextureRect.new()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = load("res://assets_bossmaker/art/battle_courtyard_night.png")
	stage.add_child(bg)
	stage.move_child(bg, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var aura: Node2D = stage._musha_aura
	aura._process(0.1)
	assert_eq(aura._paths.size(), Timeline.TRACE_POOL)
	# 1280x720にカバー表示した背景上の松明(画像の36.6%/63.3%, 40.4%)。
	var a: Vector2 = aura._torches[0]
	var b: Vector2 = aura._torches[1]
	assert_almost_eq(a.x, 0.366 * 1280.0, 6.0)
	assert_almost_eq(b.x, 0.633 * 1280.0, 6.0)
	assert_almost_eq(a.y, 0.404 * 720.0, 8.0)
	assert_gt(aura._torch_radius, 50.0)
	# 溝の墨筆はボスの足元から始まり、地面の内側に収まる。
	var foot: Vector2 = aura._home_foot("boss")
	for path in aura._paths:
		assert_lt(absf(path[0].x - foot.x), 130.0)
		for p in path:
			assert_lte(p.y, stage.size.y - 11.0)

func test_without_a_background_there_are_no_torches_or_grooves_and_nothing_breaks() -> void:
	var stage := _stage(_session(), true)
	var aura: Node2D = stage._musha_aura
	for i in range(0, 30):
		aura._process(1.0 / 30.0)
	assert_eq(aura._paths.size(), 0)
	assert_lt(aura._torches[0].x, 0.0, "no torch is dimmed without a known background")

func test_shaders_are_shared_but_materials_are_per_instance() -> void:
	var a := Shaders.material("post")
	var b := Shaders.material("post")
	assert_ne(a, b)
	assert_eq(a.shader, b.shader)
	a.set_shader_parameter("amount", 0.5)
	assert_ne(b.get_shader_parameter("amount"), 0.5, "uniforms are per material")
	assert_true(String(Shaders.material("ally").shader.code).contains("COLOR"))
