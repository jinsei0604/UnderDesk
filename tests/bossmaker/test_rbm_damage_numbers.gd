extends GutTest
## ダメージ・回復の数字（rbm_damage_numbers.gd）: 出来事ごとの出し分け・跳ね方・置き場所・後片付け・ステージとのつなぎ。
## 数字は表示専用で、戦闘の状態を変えないことも確かめる。

const Numbers = preload("res://src/bossmaker/visuals/rbm_damage_numbers.gd")

func _session(party: Array = ["hero", "butler", "healer", "samurai"], boss_target := "single") -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "数字の確認"
	draft.hp = 99999
	draft.atk = 30
	draft.spd = 1
	draft.weak_attributes = ["FIRE"]
	draft.resist_attributes = ["ICE"]
	for id in party:
		draft.add_party_character(id)
	var skill_id := draft.add_skill({"name": "攻撃", "type": "attack", "target": boss_target, "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return RBMCreatorTestSession.new(draft.to_definition(), 7)

func _stage(session: RBMCreatorTestSession, stage_size := Vector2(1280, 720)) -> RBMBattleStage:
	var stage := RBMBattleStage.new()
	stage.size = stage_size
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "")
	stage.set_state(session.battle.presentation_state())
	return stage

func _skill(session: RBMCreatorTestSession, actor: Variant, skill_id: String) -> Dictionary:
	return RBMBattleUiKit.find_skill_for_actor(actor, skill_id, session.battle)

func _shown(stage: RBMBattleStage) -> Array:
	return stage._damage_numbers.audit()

func _texts(stage: RBMBattleStage) -> Array:
	return _shown(stage).map(func(n): return "%s:%s:%s" % [n["key"], n["text"], n["kind"]])

func test_one_digit_hop_follows_the_reference_keyframes() -> void:
	var h := Numbers.HOP_HEIGHT
	assert_eq(Numbers.hop_offset(0.0), 0.0)
	assert_almost_eq(Numbers.hop_offset(0.24), h, 0.01, "top of the jump at 24%")
	assert_almost_eq(Numbers.hop_offset(0.46), 0.0, 0.01, "lands at 46%")
	assert_almost_eq(Numbers.hop_offset(0.60), h * 0.32, 0.01, "second, smaller hop at 60%")
	assert_eq(Numbers.hop_offset(0.74), 0.0, "settled at 74%")
	assert_eq(Numbers.hop_offset(1.0), 0.0)
	assert_gt(Numbers.hop_offset(0.12), h * 0.5, "slows down while rising")
	assert_gt(Numbers.hop_offset(0.35), h * 0.5, "speeds up while falling")
	assert_eq(Numbers.STAGGER, 0.055)
	assert_eq(Numbers.HOP, 0.62)
	assert_eq(Numbers.HOLD, 0.9)

func test_each_result_shows_its_own_number_and_kind() -> void:
	var session := _session()
	var stage := _stage(session)
	var before := session.battle.snapshot()
	var numbers: Node2D = stage._damage_numbers
	numbers.show_entry({"actor": 0, "action": "attack", "target": "boss", "amount": 240}, {}, session.battle)
	numbers.show_entry({"actor": 0, "action": "skill", "skill_id": "hero_slash", "target": "boss", "amount": 432}, _skill(session, 0, "hero_slash"), session.battle)
	numbers.show_entry({"actor": 1, "action": "skill", "skill_id": "butler_ice_bolt", "target": "boss", "amount": 440}, _skill(session, 1, "butler_ice_bolt"), session.battle)
	numbers.show_entry({"actor": 2, "action": "skill", "skill_id": "healer_heal_single", "target": 3, "amount": 34}, _skill(session, 2, "healer_heal_single"), session.battle)
	numbers.show_entry({"actor": 2, "action": "skill", "skill_id": "healer_heal_all", "healed": {0: 34, 1: 0}}, _skill(session, 2, "healer_heal_all"), session.battle)
	numbers.show_entry({"actor": 1, "action": "skill", "skill_id": "butler_sp_gift", "target": 0, "amount": 15}, _skill(session, 1, "butler_sp_gift"), session.battle)
	numbers.show_entry({"actor": 2, "action": "skill", "skill_id": "healer_sp_all", "recovered": {1: 20}}, _skill(session, 2, "healer_sp_all"), session.battle)
	var texts := _texts(stage)
	for expected in ["boss:240:damage", "boss:432:weak", "boss:440:resist", "3:+34:heal", "0:+34:heal", "0:SP+15:sp", "1:SP+20:sp"]:
		assert_true(texts.has(expected), "%s in %s" % [expected, texts])
	assert_eq(texts.size(), 7, "a zero heal shows nothing: %s" % [texts])
	assert_eq(session.battle.snapshot(), before, "numbers never touch the battle")

func test_counter_shows_only_the_reflected_damage_on_the_boss() -> void:
	var session := _session()
	var stage := _stage(session)
	stage._damage_numbers.show_entry({"actor": "boss", "action": "skill", "skill_id": "boss_skill_1", "hits": {
		0: {"amount": 34, "target": 0}, 3: {"blocked": true, "counter": true, "amount": 0, "reflected": 840, "target": 3}}}, {}, session.battle)
	assert_eq(_texts(stage), ["0:34:damage", "boss:840:damage"])
	stage._damage_numbers.clear()
	stage._damage_numbers.show_entry({"actor": "boss", "action": "attack", "blocked": true, "counter": true, "target": 3, "amount": 0, "reflected": 77}, {}, session.battle)
	assert_eq(_texts(stage), ["boss:77:damage"], "single-target counter")
	stage._damage_numbers.clear()
	var aoe := {"actor": "boss", "action": "skill", "skill_id": "boss_skill_1", "hits": {
		0: {"amount": 34, "target": 0}, 3: {"blocked": true, "counter": true, "amount": 0, "reflected": 840, "target": 3}}}
	stage._damage_numbers.show_entry(aoe, {}, session.battle, "hits")
	assert_eq(_texts(stage), ["0:34:damage"], "before the counter: only the allies who were hit")
	stage._damage_numbers.show_entry(aoe, {}, session.battle, "reflected")
	assert_eq(_texts(stage), ["0:34:damage", "boss:840:damage"], "at the counter: only the reflected damage is added")

## 全体攻撃を侍がカウンターで防いだ時: 当たった仲間の数字はボスの攻撃が当たった瞬間に出て、侍には出ず、
## 侍の反撃が当たった瞬間にボスへの反撃の数字だけが足される（仲間の数字が反撃まで待たされない）。
func test_allies_hit_by_an_area_attack_show_numbers_before_the_samurai_counter() -> void:
	var session := _session(["hero", "samurai"], "all")
	var stage := _stage(session)
	var boss_entry := {}
	for i in range(4):
		var actor: int = session.pending_ally_id()
		if actor < 0:
			break
		var unit := RBMBattleUiKit.unit_by_id(session.battle, actor)
		var action := {"type": "skill", "skill_id": "samurai_counter"} if str(unit.character_id) == "samurai" else {"type": "defend"}
		for entry in session.resolve_ally_action(action):
			if str(entry.get("actor")) == "boss" and entry.has("hits"):
				boss_entry = entry
	assert_false(boss_entry.is_empty(), "sanity: the boss used its area attack")
	var samurai := ""
	var hero := ""
	for uid in boss_entry["hits"]:
		var hit: Dictionary = boss_entry["hits"][uid]
		if bool(hit.get("blocked", false)): samurai = str(hit["target"])
		else: hero = str(hit["target"])
	assert_ne(samurai, "", "sanity: the samurai blocked")
	var impacts: Array = []
	stage.impact.connect(func(_e): impacts.append(stage._damage_numbers.audit()))
	stage.play_entry(boss_entry, RBMBattleUiKit.find_skill_for_actor("boss", str(boss_entry["skill_id"]), session.battle))
	var seen_before_counter := []
	for i in range(400):
		if not stage.is_playing():
			break
		if impacts.is_empty() and seen_before_counter.is_empty() and stage._damage_numbers.active_count() > 0:
			seen_before_counter = stage._damage_numbers.audit()
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.02)
		await get_tree().process_frame
	assert_eq(seen_before_counter.map(func(n): return n["key"]), [hero], "the hit ally's number appears at the boss's hit, before the counter; none for the samurai")
	assert_eq(impacts.size(), 1, "the counter's impact")
	var at_counter: Array = impacts[0].map(func(n): return "%s:%s" % [n["key"], n["text"]])
	assert_eq(at_counter.size(), 2, "at the counter: the ally's number (already shown) + the reflected damage: %s" % [at_counter])
	assert_true(at_counter.has("boss:%d" % int(boss_entry["hits"][int(samurai)]["reflected"])), str(at_counter))
	for n in impacts[0]:
		assert_ne(n["key"], samurai, "never a number on the samurai who blocked")

func test_nothing_for_failed_support_or_awakening_entries_and_zero_damage_still_shows() -> void:
	var session := _session()
	var stage := _stage(session)
	var numbers: Node2D = stage._damage_numbers
	numbers.show_entry({"actor": 0, "action": "skill", "skill_id": "hero_slash", "failed": true, "reason": "insufficient_sp"}, {}, session.battle)
	numbers.show_entry({"actor": 0, "action": "defend"}, {}, session.battle)
	numbers.show_entry({"actor": "boss", "action": "awakening"}, {}, session.battle)
	numbers.show_entry({"actor": 3, "action": "skill", "skill_id": "samurai_counter"}, _skill(session, 3, "samurai_counter"), session.battle)
	assert_eq(numbers.active_count(), 0)
	numbers.show_entry({"actor": "boss", "action": "skill", "skill_id": "boss_skill_1", "target": 1, "amount": 0}, {}, session.battle)
	assert_eq(_texts(stage), ["1:0:damage"], "a hit for 0 still says 0")

func test_numbers_stay_inside_the_battlefield_and_clear_of_each_other() -> void:
	for stage_size in [Vector2(1280, 720), Vector2(640, 360)]:
		var session := _session()
		var stage := _stage(session, stage_size)
		stage._damage_numbers.show_entry({"actor": "boss", "action": "skill", "skill_id": "boss_skill_1", "hits": {
			0: {"amount": 99999, "target": 0}, 1: {"amount": 99999, "target": 1}, 2: {"amount": 99999, "target": 2}, 3: {"amount": 99999, "target": 3}}}, {}, session.battle)
		stage._damage_numbers.show_entry({"actor": 0, "action": "skill", "skill_id": "hero_slash", "target": "boss", "amount": 99999}, _skill(session, 0, "hero_slash"), session.battle)
		var rects: Array[Rect2] = []
		for n in _shown(stage):
			var width: float = ((str(n["text"]).length() - 1) * Numbers.ADVANCE + Numbers.GLYPH_W) * Numbers.PIXEL
			var origin: Vector2 = n["origin"]
			var top := origin.y - Numbers.GLYPH_H * Numbers.PIXEL - Numbers.HOP_HEIGHT
			assert_gte(origin.x, Numbers.SAFE_SIDE, "%s left %s" % [stage_size, n])
			assert_lte(origin.x + width, stage_size.x - Numbers.SAFE_SIDE + 0.5, "%s right %s" % [stage_size, n])
			if stage_size.y >= 720:
				assert_gte(top, Numbers.SAFE_TOP, "the whole jump stays below the top HUD: %s" % [n])
				assert_lte(origin.y, stage_size.y - Numbers.SAFE_BOTTOM, "above the bottom HUD: %s" % [n])
			var rest := Rect2(origin.x, origin.y - Numbers.GLYPH_H * Numbers.PIXEL, width, Numbers.GLYPH_H * Numbers.PIXEL)
			if stage_size.y >= 720:
				for other in rects:
					assert_false(other.intersects(rest), "numbers of one moment never overlap: %s / %s" % [other, rest])
			rects.append(rest)
		assert_eq(rects.size(), 5)

func test_a_second_hit_on_the_same_target_lifts_the_previous_number() -> void:
	var session := _session()
	var stage := _stage(session)
	var numbers: Node2D = stage._damage_numbers
	numbers.show_entry({"actor": 0, "action": "attack", "target": "boss", "amount": 240}, {}, session.battle)
	numbers.show_entry({"actor": 1, "action": "attack", "target": "boss", "amount": 220}, {}, session.battle)
	var shown := _shown(stage)
	assert_eq(shown[0]["stack"], Numbers.STACK_STEP, "the older number moves one step up")
	assert_eq(shown[1]["stack"], 0.0, "the newest number always appears at the same place")
	assert_eq(shown[0]["origin"], shown[1]["origin"])
	for i in range(30):
		numbers._process(1.0 / 60.0)
	assert_almost_eq(float(_shown(stage)[0]["lift"]), Numbers.STACK_STEP, 1.0, "the lift settles within half a second")

func test_each_number_lives_for_its_digits_then_stops_processing() -> void:
	var session := _session()
	var stage := _stage(session)
	var numbers: Node2D = stage._damage_numbers
	numbers.show_entry({"actor": 0, "action": "attack", "target": "boss", "amount": 1234}, {}, session.battle)
	assert_true(numbers.is_processing())
	var life := 3 * Numbers.STAGGER + Numbers.HOP + Numbers.HOLD + Numbers.FADE
	assert_almost_eq(float(numbers._numbers[0]["life"]), life, 0.001, "(digits - 1) x stagger + hop + hold + fade")
	var t := 0.0
	while t < life - 0.05:
		numbers._process(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_eq(numbers.active_count(), 1, "still fading just before the end")
	for i in range(6):
		numbers._process(1.0 / 60.0)
	assert_eq(numbers.active_count(), 0)
	assert_false(numbers.is_processing(), "no work once every number is gone")

func test_glyphs_are_made_once_and_shared() -> void:
	var a: ImageTexture = Numbers._glyph("7", "damage")
	var b: ImageTexture = Numbers._glyph("7", "damage")
	assert_same(a, b)
	assert_ne(Numbers._glyph("7", "weak"), a, "each colour has its own glyph")
	assert_eq(a.get_size(), Vector2(Numbers.GLYPH_W + 2, Numbers.GLYPH_H + 3), "fill + outline + shadow")
	var image := a.get_image()
	assert_eq(image.get_pixel(0, 1), Numbers.OUTLINE, "outlined")
	assert_eq(image.get_pixel(1, 1).a, 1.0, "filled")

func test_stage_shows_numbers_once_at_the_impact_of_a_real_entry() -> void:
	var session := _session(["hero"])
	var before := session.battle.presentation_state()
	var stage := _stage(session)
	var log := session.resolve_ally_action({"type": "defend"})
	assert_eq(log.size(), 2, "sanity: the hero defends, the boss attacks")
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var impacts: Array = []
	presenter.entry_impact.connect(func(entry): impacts.append(entry))
	presenter.play(log, session.battle, before)
	for i in range(240):
		if impacts.size() >= 2:
			break
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.05)
		await get_tree().process_frame
	assert_eq(impacts.size(), 2)
	var target := str(log[1]["target"])
	assert_eq(_texts(stage), ["%s:%d:damage" % [target, int(log[1]["amount"])]], "defend shows nothing; the boss hit shows once")
	stage.impact.emit(stage._entry)
	assert_eq(stage._damage_numbers.active_count(), 1, "a repeated impact of the same entry adds nothing")

func test_stage_switch_release_and_motion_speed() -> void:
	var session := _session()
	var stage := _stage(session)
	stage.show_damage_numbers = false
	stage._show_damage_numbers({"actor": 0, "action": "attack", "target": "boss", "amount": 5})
	assert_eq(stage._damage_numbers.active_count(), 0, "turned off (home monitor preview)")
	stage.show_damage_numbers = true
	stage._damage_numbers_shown = false
	stage._show_damage_numbers({"actor": 0, "action": "attack", "target": "boss", "amount": 5})
	assert_eq(stage._damage_numbers.active_count(), 1)
	stage.set_motion_speed(0.25)
	assert_eq(stage._damage_numbers.time_scale, 0.25, "the final blow's slow motion slows the numbers too")
	stage.release_presentations()
	assert_eq(stage._damage_numbers.active_count(), 0, "leaving the battle clears the numbers")
	stage._damage_numbers_shown = false
	stage._show_damage_numbers({"actor": 0, "action": "attack", "target": "boss", "amount": 5})
	stage.configure(null)
	assert_eq(stage._damage_numbers.active_count(), 0)
	assert_eq(stage._damage_numbers.time_scale, 1.0)
