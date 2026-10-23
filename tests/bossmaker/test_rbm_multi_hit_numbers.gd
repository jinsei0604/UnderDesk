extends GutTest
## 何回も当たる攻撃のダメージの数字（2026-10-23 ユーザーの決定）: 当たるたびに小さな数字（その回の分）、最後の一撃で合計。
## 小さな数字を全部足すと合計。HP は当たるたびに減り、最後の一撃（impact）で確定。戦闘の計算・記録は変えない。
## 対象: 竜の覚醒後の全体（小さな隕石→巨大隕石）、武者（単体・全体）、武者の覚醒後（単体・全体）、紳士（全体・覚醒後の単体・全体）。
const AssetsReady = preload("res://tests/bossmaker/presentation_assets_ready.gd")
const DamageNumbers = preload("res://src/bossmaker/visuals/rbm_damage_numbers.gd")
var _ready_assets: Array = []

func before_all() -> void:
	_ready_assets = AssetsReady.hold(["dragon", "musha", "gentleman"])

func after_all() -> void:
	_ready_assets.clear()

func _fixture(boss: String, target: String, awakened: bool, counter := false) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_" + boss
	draft.boss_name = "多段 QA"
	draft.hp = 3000
	draft.atk = 60
	draft.spd = 1
	var ids: Array = ["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"]
	for id in ids:
		draft.add_party_character(id)
	var id := draft.add_skill({"name": "多段", "type": "attack", "target": target, "attribute": "FIRE", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "appearance_" + boss)
	var before := session.battle.presentation_state()
	stage.set_state(before)
	var entry: Dictionary = {}
	for attempt in range(12):
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and session.pending_ally_id() == 0 else {"type": "defend"}
		for e in session.resolve_ally_action(action):
			if str(e.get("actor")) == "boss" and e.has("visual_state") and (e.has("hits") or e.has("amount")):
				entry = e
			elif entry.is_empty():
				before = e.get("visual_state", before)
		if not entry.is_empty():
			break
	stage.set_state(before)
	return {"stage": stage, "session": session, "entry": entry, "before": before, "skill": RBMBattleUiKit.find_skill_for_actor("boss", id, session.battle)}

## この行動で各相手が受けるダメージ（防いだ相手は 0）。
func _amounts(entry: Dictionary) -> Dictionary:
	var out := {}
	if entry.has("hits"):
		for uid in entry["hits"]:
			var hit = entry["hits"][uid]
			out[str(uid)] = 0 if bool(hit.get("blocked", false)) else int(hit.get("amount", 0))
	else:
		out[str(entry.get("target"))] = int(entry.get("amount", 0))
	return out

## 再生して、途中の当たり・impact の瞬間の数字を記録する。
func _play(f: Dictionary) -> Dictionary:
	var stage: RBMBattleStage = f.stage
	var rec := {"partials": [], "impacts": 0, "hits_landed": 0, "at_impact": [], "parts": {}, "first_partial_t": -1.0, "impact_t": -1.0}
	var clock := {"t": 0.0}
	stage.partial_hits.connect(func(_e: Dictionary, landed: Dictionary):
		if rec.partials.is_empty():
			rec.first_partial_t = clock.t
		rec.partials.append(landed.duplicate()))
	var on_final := func():
		rec.at_impact = stage._damage_numbers.audit()
		rec.impact_t = clock.t
		for n in stage._damage_numbers._numbers:
			n["qa_counted"] = true
	stage.impact.connect(func(_e: Dictionary):
		rec.impacts += 1
		if rec.at_impact.is_empty():
			on_final.call())
	stage.hits_landed.connect(func(_e: Dictionary):
		rec.hits_landed += 1
		on_final.call())
	stage.play_entry(f.entry, f.skill)
	for i in range(1200):
		if not stage.is_playing():
			break
		stage._tween.custom_step(0.02)
		clock.t += 0.02
		# 小さな数字（途中の当たりの分）を、出た時に1回ずつ数える（最後の一撃の分は on_final で数えない印を付ける）
		for n in stage._damage_numbers._numbers:
			if bool(n.get("small", false)) and not n.has("qa_counted"):
				n["qa_counted"] = true
				rec.parts[n.key] = (rec.parts.get(n.key, []) as Array) + [int(n.text)]
	return rec

func _check_sums(f: Dictionary, rec: Dictionary, label: String) -> void:
	var amounts := _amounts(f.entry)
	var last: Dictionary = rec.partials.back() if not rec.partials.is_empty() else {}
	var totals := {}
	var rests := {}
	for n in rec.at_impact:
		if bool(n.pending):
			totals[n.key] = int(n.text)
		elif bool(n.small):
			rests[n.key] = int(n.text)
	for key in amounts:
		var amount: int = amounts[key]
		if amount <= 0:
			assert_false(last.has(key), "%s: no numbers for %s (blocked)" % [label, key])
			continue
		assert_true(last.has(key), "%s: %s is hit before the final blow" % [label, key])
		assert_lt(int(last.get(key, 0)), amount, "%s: the final blow still has damage left for %s" % [label, key])
		assert_eq(totals.get(key, -1), amount, "%s: the total for %s appears at the final blow" % [label, key])
		assert_eq(int(last.get(key, 0)) + int(rests.get(key, 0)), amount, "%s: small numbers add up to the total for %s" % [label, key])
		var shown := 0
		for part in rec.parts.get(key, []):
			shown += int(part)
		assert_eq(shown, int(last.get(key, 0)), "%s: every partial hit showed its small number for %s" % [label, key])

func test_split_always_adds_up_and_the_final_blow_keeps_its_share() -> void:
	for spec in [[53, 8, 0.4], [1000, 1, 0.6], [5, 8, 0.4], [0, 3, 0.4], [99999, 12, 0.4], [7, 2, 0.6]]:
		var parts: Array[int] = RBMBattleStage.split_amount(int(spec[0]), int(spec[1]), float(spec[2]))
		assert_eq(parts.size(), int(spec[1]) + 1)
		var sum := 0
		for p in parts:
			assert_gte(p, 0)
			sum += p
		assert_eq(sum, int(spec[0]), "parts add up to the amount: %s" % str(spec))
		assert_almost_eq(float(parts.back()), float(spec[0]) * float(spec[2]), float(spec[1]) + 1.0, "the final blow keeps about its share")

func test_hp_goes_down_hit_by_hit_but_waits_for_the_final_blow() -> void:
	var start := {"party": {"0": {"hp": 100, "max_hp": 100, "is_downed": false}, "1": {"hp": 30, "max_hp": 80, "is_downed": false}}, "boss": {"hp": 500}}
	var entry := {"visual_state": {"party": {"0": {"hp": 20, "is_downed": false}, "1": {"hp": 0, "is_downed": true}}, "boss": {"hp": 500}}}
	var s := RBMBattlePresenter.partial_state(start, start, entry, {"0": 30, "1": 10})
	assert_eq([s.party["0"].hp, s.party["1"].hp], [70, 20])
	s = RBMBattlePresenter.partial_state(start, s, entry, {"0": 95, "1": 29})
	assert_eq(s.party["0"].hp, 20, "never below the HP after the final blow")
	assert_eq(s.party["1"].hp, 1, "an ally downed by the final blow stays at 1 until it lands")
	assert_false(s.party["1"].is_downed)
	assert_eq(s.boss.hp, 500)

func test_the_total_appears_shortly_after_and_lifts_the_small_numbers() -> void:
	var f := _fixture("dragon", "all", true)
	var stage: RBMBattleStage = f.stage
	var numbers: Node2D = stage._damage_numbers
	var key := str(f.entry.hits.keys()[0])
	numbers.show_part(key, 12, "damage")
	numbers.show_entry(f.entry, f.skill, f.session.battle, "all", {key: 9})
	var mine: Array = numbers.audit().filter(func(n): return n.key == key)
	assert_eq(mine.size(), 3, "earlier small number, the last small number and the total")
	assert_true(bool(mine[2].pending), "the total waits a moment")
	assert_eq(int(mine[1].text), 9)
	assert_eq(float(mine[0].stack), 18.0, "the new small number lifts the earlier one")
	assert_eq(float(mine[1].stack), 0.0, "the total has not lifted anything yet")
	numbers._process(DamageNumbers.TOTAL_DELAY + 0.01)
	mine = numbers.audit().filter(func(n): return n.key == key)
	assert_false(bool(mine[2].pending))
	assert_gt(float(mine[1].stack), 0.0, "the total lifts the small numbers when it appears")

func test_dragon_awakened_meteors_count_down_to_the_giant_meteor() -> void:
	var f := _fixture("dragon", "all", true)
	var before: Dictionary = f.session.battle.snapshot().duplicate(true)
	var rec := _play(f)
	var d_impact: float = 4.15
	assert_eq(rec.impacts, 1, "one combat impact")
	assert_false(rec.partials.is_empty())
	assert_between(float(rec.first_partial_t), 1.5, 1.8, "the first small meteor")
	assert_between(float(rec.impact_t), d_impact - 0.1, d_impact + 0.1, "the total comes with the giant meteor")
	_check_sums(f, rec, "dragon meteors")
	for key in rec.parts:
		assert_gte((rec.parts[key] as Array).size(), 5, "one small number per small meteor (%s)" % key)
	assert_eq(f.session.battle.snapshot(), before, "display only")

func test_musha_gentleman_and_awakened_attacks_split_their_hits() -> void:
	for spec in [["musha", "single", false], ["musha", "all", false], ["musha", "single", true], ["musha", "all", true],
			["gentleman", "all", false], ["gentleman", "single", true], ["gentleman", "all", true]]:
		var f := _fixture(spec[0], spec[1], spec[2])
		var label := "%s %s%s" % [spec[0], spec[1], " awakened" if spec[2] else ""]
		assert_false(f.entry.is_empty(), label)
		var before: Dictionary = f.session.battle.snapshot().duplicate(true)
		var rec := _play(f)
		assert_eq(rec.impacts, 1, label + ": one combat impact")
		assert_false(rec.partials.is_empty(), label + ": hits before the final blow")
		assert_lt(float(rec.first_partial_t), float(rec.impact_t), label)
		_check_sums(f, rec, label)
		assert_eq(f.session.battle.snapshot(), before, label + ": display only")
		# 演出が差し替えて捨てた部品（武者の元の本体の絵など）の解放を済ませる
		await get_tree().process_frame

func test_single_hit_attacks_are_unchanged() -> void:
	for spec in [["dragon", "all", false], ["dragon", "single", true], ["gentleman", "single", false]]:
		var f := _fixture(spec[0], spec[1], spec[2])
		var rec := _play(f)
		assert_eq(rec.impacts, 1)
		assert_true(rec.partials.is_empty(), "%s %s: one hit, one number" % [spec[0], spec[1]])
		for n in rec.at_impact:
			assert_false(bool(n.small) or bool(n.pending), "%s %s: the usual number" % [spec[0], spec[1]])

func test_a_samurai_counter_still_shows_the_others_hits_and_only_the_reflected_damage_later() -> void:
	var f := _fixture("musha", "all", false, true)
	var rec := _play(f)
	assert_eq(rec.hits_landed, 1)
	assert_eq(rec.impacts, 1)
	_check_sums(f, rec, "musha all with counter")
	await get_tree().process_frame

func test_the_hud_hp_follows_each_partial_hit() -> void:
	var f := _fixture("dragon", "all", true)
	var stage: RBMBattleStage = f.stage
	var hud := Control.new()
	add_child_autofree(hud)
	for unit in f.session.battle.party:
		var label := Label.new()
		label.name = "PartyRowHP_%d" % unit.id
		hud.add_child(label)
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	RBMBattlePresenter.apply_status_snapshot(hud, f.before)
	var seen: Array = []
	presenter.entry_partial.connect(func(state: Dictionary):
		RBMBattlePresenter.apply_status_snapshot(hud, state, true)
		seen.append((hud.get_child(0) as Label).text))
	presenter.entry_impact.connect(func(e: Dictionary): RBMBattlePresenter.apply_status_snapshot(hud, e.visual_state, true))
	presenter.play([f.entry], f.session.battle, f.before)
	for i in range(1200):
		if not presenter.is_playing():
			break
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.02)
		await get_tree().process_frame
	assert_gt(seen.size(), 2, "the HP text changes at each partial hit")
	var first_unit: RBMUnit = f.session.battle.party[0]
	var after: Dictionary = f.entry.visual_state.party[str(first_unit.id)]
	assert_eq((hud.get_child(0) as Label).text, "HP %d / %d" % [int(after.hp), int(after.max_hp)], "the final blow commits the real HP")
