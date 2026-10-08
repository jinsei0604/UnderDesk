extends GutTest
## 演出の素材の事前読み込み(rbm_presentation_warmup.gd)の契約テスト。
## 起動して最初の再生で、演出がその場で画像を読み込まないこと(事前に読み込んで持っていること)、
## 計画がボスの技・外見(覚醒の前後)・味方に従うこと、戦闘を変えないこと、後始末を検証する。
## 実際の停止時間は実GPU・実時間で測る(性能はここでは測らない)。
const Warmup = preload("res://src/bossmaker/visuals/rbm_presentation_warmup.gd")
const GentlemanMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const Catalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const ASSET_ROOT := "res://assets_bossmaker/"
const PARTY := ["hero", "butler", "healer", "samurai"]
## 数えない物: 異形紳士の小さなモーションのコマ(再生中に1枚ずつ読む。1枚約70KBで停止にならないので事前読み込みの対象外)と、
## 異形紳士の着弾画像( rbm_gentleman_impact_sheets.gd(QA-05)が戦闘の間持つ)。
const LAZY_ALLOWED := ["res://assets_bossmaker/battle/gentleman/motion_frames/", "res://assets_bossmaker/battle/gentleman/impacts/"]

static var _assets: Array[String] = []

func after_each() -> void:
	await get_tree().process_frame

func _battle(appearance: String, specs: Array, awakening: bool = false, awakened: bool = false, party: Array = PARTY) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance
	draft.boss_name = "Warmup QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in party:
		draft.add_party_character(id)
	var ids: Array[String] = []
	for spec in specs:
		ids.append(draft.add_skill(spec))
	if awakening:
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
			"buff": {"buff_multiplier": 1.5, "duration_turns": 3}, "heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0}})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[ids[0]] = 100.0
	var session := RBMCreatorTestSession.new(draft.to_definition(), 5)
	session.battle.boss.hp = 1000 if awakening and not awakened else 1500
	session.battle.is_awakened = awakened
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, appearance)
	stage.set_state(session.battle.presentation_state())
	return {"stage": stage, "session": session, "ids": ids}

static func _attack(target: String) -> Dictionary:
	return {"name": "QA attack", "type": "attack", "target": target, "attribute": "FIRE", "atk_multiplier": 1.0}

static func _heal() -> Dictionary:
	return {"name": "QA heal", "type": "self_heal", "heal_amount": 200}

## 事前読み込みが計画を作り、すべて読み終えるまで待つ。持っているパスを返す。
func _settle(stage: RBMBattleStage) -> Array:
	var warm = stage._presentation_warmup
	for i in 900:
		await get_tree().process_frame
		if warm._key == str(warm._source().get("key", "")) and warm.is_ready():
			break
	var held: Array = warm.held_paths()
	held.sort()
	return held

## 次のボスの行動(と、その直前の表示状態)。
func _boss_entry(f: Dictionary) -> Array:
	for attempt in 24:
		var before: Dictionary = f.session.battle.presentation_state().duplicate(true)
		for e in f.session.resolve_ally_action({"type": "defend"}):
			if str(e.get("actor")) == "boss" and str(e.get("action")) in ["attack", "skill"]:
				return [e, before]
	return []

static func _asset_paths() -> Array[String]:
	if _assets.is_empty():
		_collect(ASSET_ROOT.trim_suffix("/"))
	return _assets

static func _collect(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		if file.get_extension() in ["png", "json", "wav", "ogg"]:
			_assets.append(dir.path_join(file))
	for sub in d.get_directories():
		_collect(dir.path_join(sub))

static func _cached() -> Dictionary:
	var out := {}
	for path in _asset_paths():
		if ResourceLoader.has_cached(path):
			out[path] = true
	return out

## 演出を最後まで進め、その間に新しく読み込まれた素材(キャッシュに無かったもの)を集める。
func _play_and_collect_reads(stage: RBMBattleStage, entry: Dictionary, skill: Dictionary = {}) -> Array:
	var before := _cached()
	var read := {}
	stage.play_entry(entry, skill)
	for step in 400:
		for path in _cached():
			if not before.has(path):
				read[path] = true
		if not stage.is_playing():
			break
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.1)
		await get_tree().process_frame
	var out: Array = read.keys()
	out.sort()
	return out

## 新しく読み込まれた画像・データのうち、事前に持っていなかったもの(小さなコマの許可分を除く)。
static func _unwarmed(read: Array, held: Array) -> Array:
	var out: Array = []
	for path in read:
		if str(path).get_extension() == "wav" or held.has(path):
			continue
		var allowed := false
		for prefix in LAZY_ALLOWED:
			if str(path).begins_with(prefix):
				allowed = true
		if not allowed:
			out.append(path)
	return out

func _assert_first_play_reads_nothing_new(f: Dictionary, track: String) -> void:
	var held := await _settle(f.stage)
	var pair := _boss_entry(f)
	assert_false(pair.is_empty(), "a real boss entry")
	f.stage.set_state(pair[1])
	var skill: Dictionary = RBMBattleUiKit.find_skill_for_actor("boss", str(pair[0].get("skill_id", "")), f.session.battle)
	var read := await _play_and_collect_reads(f.stage, pair[0], skill)
	assert_eq(_unwarmed(read, held), [], "%s: every image and data file the first play reads was read in the background" % track)
	if track != "":
		assert_has(held, str(Catalog.FILES[track]), "%s: the dedicated track is kept" % track)

# ---------------------------------------------------------------------------

func test_every_declared_path_exists_for_each_form_and_kind() -> void:
	var stage := RBMBattleStage.new()
	add_child_autofree(stage)
	var declared := 0
	for table in [["single", stage.BOSS_SINGLE_PRESENTATIONS], ["all", stage.BOSS_ALL_PRESENTATIONS], ["support", stage.BOSS_SUPPORT_PRESENTATIONS]]:
		for asset_id in table[1]:
			var script: Script = table[1][asset_id]
			if not Warmup._declares_paths(script):
				continue
			for path in script.call("warm_paths", asset_id, table[0]):
				declared += 1
				assert_true(ResourceLoader.exists(path), "%s %s declares %s" % [asset_id, table[0], path])
	for base_id in stage.BOSS_AWAKENING_PRESENTATIONS:
		var script: Script = stage.BOSS_AWAKENING_PRESENTATIONS[base_id]
		if Warmup._declares_paths(script):
			for path in script.call("warm_paths", base_id, "awakening"):
				declared += 1
				assert_true(ResourceLoader.exists(path), "%s awakening declares %s" % [base_id, path])
	for skill_id in stage.SKILL_PRESENTATIONS:
		var entry: Dictionary = stage.SKILL_PRESENTATIONS[skill_id]
		for path in entry.script.call("warm_paths", entry.actor, entry.kind):
			declared += 1
			assert_true(ResourceLoader.exists(path), "%s declares %s" % [skill_id, path])
	assert_gt(declared, 100)

func test_an_unprepared_battle_waits_before_reading_and_never_changes_the_battle() -> void:
	var f := _battle("appearance_musha", [_attack("single")], true)
	var snapshot = f.session.battle.snapshot().duplicate(true)
	var warm = f.stage._presentation_warmup
	for i in Warmup.START_DELAY_FRAMES - 2:
		await get_tree().process_frame
	assert_false(warm.planned_paths().is_empty(), "the plan is made as soon as the battle is known")
	assert_eq(warm.held_paths(), [], "nothing is read while the battle screen is still opening (no prepare() before it)")
	var held := await _settle(f.stage)
	assert_eq(held, _sorted(warm.planned_paths()), "everything planned is read and kept")
	assert_eq(f.session.battle.snapshot(), snapshot, "reading ahead never touches the simulation")

# ---------------------------------------------------------------------------
# QA-06 (A+C): 戦闘を始める前の画面から読み始め、早く要る可能性がある順に読む

## 戦闘を始める前の画面にあるステージ(まだ戦闘を持たない)と、その戦闘の定義。
func _prepared_stage(appearance: String, boss_spd: int, specs: Array, awakening: Dictionary = {}, scripted_turn1: bool = false, party: Array = PARTY) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance
	draft.boss_name = "Warmup QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = boss_spd
	for id in party:
		draft.add_party_character(id)
	var ids: Array[String] = []
	for spec in specs:
		ids.append(draft.add_skill(spec))
	if not awakening.is_empty():
		draft.set_awakening(awakening)
	if scripted_turn1:
		draft.add_scripted_action(1, ids[-1], "turn_start_interrupt")
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[ids[0]] = 100.0
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	return {"stage": stage, "definition": draft.to_definition(), "appearance": appearance}

static func _index(planned: Array, path: String) -> int:
	return planned.find(ASSET_ROOT + path)

## prepare() の後、計画ができるまで待つ(使い捨ての戦闘を作る・計画を作るは、呼んだ後の別々のフレーム)。
func _until_planned(stage) -> void:
	var warm = stage._presentation_warmup
	for i in 10:
		if warm._prepare_request.is_empty() and not warm.planned_paths().is_empty():
			return
		await get_tree().process_frame

func test_prepare_plans_and_reads_before_the_battle_without_waiting() -> void:
	var p := _prepared_stage("appearance_musha", 1, [_attack("single")])
	var stage: RBMBattleStage = p.stage
	var warm = stage._presentation_warmup
	stage.prepare_presentations(p.definition, p.appearance, "day")
	assert_eq(warm.planned_paths(), [], "the pre-battle screen's own frame only asks (the work is spread over the next frames)")
	await _until_planned(stage)
	assert_false(warm.planned_paths().is_empty(), "planned within the next frames")
	assert_ne(warm._loading, "", "the first background read starts with the plan")
	for i in 8:
		await get_tree().process_frame
	assert_false(warm.held_paths().is_empty(), "reading goes on without the opening delay of an unprepared battle")
	var held := await _settle(stage)
	assert_eq(held, _sorted(warm.planned_paths()))
	assert_has(held, ASSET_ROOT + "audio/musha_single.wav")

func test_what_can_play_as_the_battle_opens_is_read_first() -> void:
	# The boss is faster than every ally and the awakening has no condition: both play as the battle opens,
	# the awakening first (it is checked at the turn start, before the boss acts).
	var p := _prepared_stage("appearance_musha", 500, [_attack("single"), _attack("all")], {"conditions": [], "condition_logic": "AND", "buff": {}, "heal": {}})
	p.stage.prepare_presentations(p.definition, p.appearance, "day")
	await _until_planned(p.stage)
	var planned: Array = p.stage._presentation_warmup.planned_paths()
	var awakening := _index(planned, "audio/musha_awakening.wav")
	var single := _index(planned, "audio/musha_single.wav")
	var all := _index(planned, "audio/musha_aoe.wav")
	var hit_pose := _index(planned, "battle/hero/frames/11.png")
	var finisher := _index(planned, "battle/healer/frames/04.png")
	assert_true(awakening >= 0 and single >= 0 and all >= 0 and hit_pose >= 0 and finisher >= 0, str(planned))
	assert_lt(awakening, single, "the awakening at the turn start comes before the boss's first action")
	assert_lt(single, finisher, "the boss's opening action comes before the first ally command")
	assert_lt(all, finisher)
	assert_lt(finisher, hit_pose, "the first ally command comes before the reaction poses")

func test_with_a_slower_boss_the_first_command_and_a_first_hit_awakening_come_first() -> void:
	# The boss is slower than every ally: nothing plays as the battle opens. The healer's finisher can be the
	# first command, and an HP awakening can follow the first attack, before the boss's turn-1 action.
	var p := _prepared_stage("appearance_musha", 1, [_attack("single")], {"conditions": [{"type": "hp_at_most", "percent": 99.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	p.stage.prepare_presentations(p.definition, p.appearance, "day")
	await _until_planned(p.stage)
	var planned: Array = p.stage._presentation_warmup.planned_paths()
	var finisher := _index(planned, "battle/healer/frames/04.png")
	var awakening := _index(planned, "audio/musha_awakening.wav")
	var single := _index(planned, "audio/musha_single.wav")
	var hit_pose := _index(planned, "battle/hero/frames/11.png")
	assert_true(finisher >= 0 and awakening >= 0 and single >= 0 and hit_pose >= 0, str(planned))
	assert_lt(finisher, awakening)
	assert_lt(awakening, single)
	assert_lt(single, hit_pose)

func test_a_turn_one_scripted_action_is_read_first() -> void:
	var p := _prepared_stage("appearance_musha", 1, [_attack("single"), _attack("all")], {}, true)
	p.stage.prepare_presentations(p.definition, p.appearance, "day")
	await _until_planned(p.stage)
	var planned: Array = p.stage._presentation_warmup.planned_paths()
	assert_lt(_index(planned, "audio/musha_aoe.wav"), _index(planned, "battle/healer/frames/04.png"), "the turn-start scripted all-target attack plays as the battle opens")
	assert_lt(_index(planned, "battle/healer/frames/04.png"), _index(planned, "audio/musha_single.wav"))

func test_the_prepared_battle_keeps_what_was_read_and_release_lets_it_go() -> void:
	var p := _prepared_stage("appearance_musha", 1, [_attack("single")], {"conditions": [{"type": "hp_at_most", "percent": 10.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	var stage: RBMBattleStage = p.stage
	var warm = stage._presentation_warmup
	stage.prepare_presentations(p.definition, p.appearance, "day")
	var held := await _settle(stage)
	var ink := ASSET_ROOT + "battle/musha/ink.png"
	var kept: Resource = warm._held[ink]
	# The battle starts on the same stage: planned again from the real battle, nothing is read again.
	var session := RBMCreatorTestSession.new(p.definition, 5)
	stage.configure(session.battle, p.appearance)
	stage.set_state(session.battle.presentation_state())
	await get_tree().process_frame
	assert_eq(warm._hold_frames, 0, "a prepared battle does not wait")
	assert_eq(_sorted(warm.held_paths()), held, "the same things are kept")
	assert_same(warm._held[ink], kept, "kept, not read again")
	# Leaving the battle lets everything go and the stage's old battle is not planned again.
	stage.release_presentations()
	assert_eq(warm.held_paths(), [])
	for i in Warmup.START_DELAY_FRAMES + 10:
		await get_tree().process_frame
	assert_eq(warm.planned_paths(), [], "the battle the stage still shows is not read again")
	assert_eq(warm.held_paths(), [])
	# A new battle (a rematch) is planned again.
	var rematch := RBMCreatorTestSession.new(p.definition, 6)
	stage.configure(rematch.battle, p.appearance)
	await get_tree().process_frame
	assert_false(warm.planned_paths().is_empty())

func test_the_battle_views_release_on_leaving_and_prepare_from_the_pre_battle_screens() -> void:
	var p := _prepared_stage("appearance_musha", 1, [_attack("single")])
	var view := RBMCreatorTestBattleView.new()
	view.setup(null)
	add_child_autofree(view)
	var stage = view._battlefield_ally_row.get_meta("visual_stage")
	var warm = stage._presentation_warmup
	view.prepare_presentations(p.definition, p.appearance, "day")
	await _until_planned(view._battlefield_ally_row.get_meta("visual_stage"))
	assert_false(warm.planned_paths().is_empty(), "Test Battle: prepared from the Creator's summary")
	view.set_boss_appearance(p.appearance)
	view.start(p.definition, 7)
	await _settle(stage)
	assert_false(warm.held_paths().is_empty())
	view._on_return_pressed()
	assert_eq(warm.held_paths(), [], "Test Battle: let go on returning to the Creator")
	assert_eq(warm.planned_paths(), [])
	var challenge := RBMChallengeBattleView.new()
	add_child_autofree(challenge)
	var cstage = challenge._battlefield_ally_row.get_meta("visual_stage")
	challenge.prepare_presentations(p.definition, p.appearance, "night")
	await _until_planned(cstage)
	assert_false(cstage._presentation_warmup.planned_paths().is_empty(), "Challenge: prepared from the boss confirmation")
	challenge._on_return_pressed()
	assert_eq(cstage._presentation_warmup.planned_paths(), [], "Challenge: let go on returning to the list")

func test_the_musha_aura_prepares_its_background_before_the_battle() -> void:
	var p := _prepared_stage("appearance_musha", 1, [_attack("single")], {"conditions": [{"type": "hp_at_most", "percent": 10.0}], "condition_logic": "AND", "buff": {}, "heal": {}})
	var stage: RBMBattleStage = p.stage
	var aura = stage._musha_aura
	stage.prepare_presentations(p.definition, p.appearance, "day")
	for i in 30:
		await get_tree().process_frame
		if aura._bg_prepared != null:
			break
	assert_not_null(aura._bg_prepared, "the battle background is read before the battle")
	assert_eq(aura._bg_prepared.resource_path, RBMBattleBackgrounds.path_for("musha", "day"))
	assert_eq(aura._bg_copy_tried, aura._bg_prepared.get_instance_id(), "its RGBA8 copy is made before the battle")
	stage.release_presentations()
	assert_null(aura._bg_prepared)
	# Without an awakening the aura never shows: nothing is prepared.
	var plain := _prepared_stage("appearance_musha", 1, [_attack("single")])
	plain.stage.prepare_presentations(plain.definition, plain.appearance, "day")
	await get_tree().process_frame
	assert_null(plain.stage._musha_aura._bg_prepared)
	assert_eq(plain.stage._musha_aura._bg_request, "")

static func _sorted(values: Array) -> Array:
	var out := values.duplicate()
	out.sort()
	return out

func test_musha_plan_follows_the_skills_the_form_and_the_awakening() -> void:
	var f := _battle("appearance_musha", [_attack("single"), _attack("all"), _heal()], true)
	var held := await _settle(f.stage)
	for path in ["battle/musha/ink.png", "battle/musha/ice.png", "battle/musha/poses.png", "battle/musha/design.png",
			"battle/musha_frames/p0d.png", "battle/musha_frames/p4i.png", "battle/musha_frames/p5d.png",
			"audio/musha_single.wav", "audio/musha_aoe.wav", "audio/musha_heal.wav", "audio/musha_buff.wav",
			"battle/hero/frames/10.png", "battle/samurai/frames/11.png",
			"battle/musha_awakened/awakened.png", "battle/musha_awakened/swing.png", "battle/musha_awakened/frames/00.png", "audio/musha_awakening.wav"]:
		assert_has(held, ASSET_ROOT + path, "before the awakening: " + path)
	assert_does_not_have(held, ASSET_ROOT + "battle/musha_awakened/brush.png", "awakened attacks are read once the form changes")
	# 覚醒した外見: 覚醒後の技の分へ替わり、覚醒の演出だけの物は手放す。
	var awakened: Dictionary = f.session.battle.presentation_state()
	awakened.is_awakened = true
	f.stage.set_state(awakened)
	held = await _settle(f.stage)
	for path in ["battle/musha_awakened/brush.png", "battle/musha_awakened/awakened.png", "battle/musha_awakened/swing.png",
			"battle/musha_frames/s3i.png", "battle/musha_frames/kcs14.png", "audio/musha_awakened_single.wav", "audio/musha_awakened_aoe.wav",
			"battle/musha/ink.png", "battle/musha_awakened/design.png"]:
		assert_has(held, ASSET_ROOT + path, "after the awakening: " + path)
	assert_does_not_have(held, ASSET_ROOT + "audio/musha_awakening.wav")
	assert_does_not_have(held, ASSET_ROOT + "battle/musha/design.png")
	# 覚醒の設定が無く、単体だけを使うボス: 全体・支援・覚醒の分は読まない。
	var plain := _battle("appearance_musha", [_attack("single")])
	held = await _settle(plain.stage)
	assert_has(held, ASSET_ROOT + "audio/musha_single.wav")
	for path in ["audio/musha_aoe.wav", "audio/musha_heal.wav", "battle/musha_awakened/awakened.png", "battle/musha_frames/p4i.png"]:
		assert_does_not_have(held, ASSET_ROOT + path)

func test_other_bosses_read_only_their_own_presentations_and_the_party_poses() -> void:
	var f := _battle("appearance_slime", [_attack("single")])
	var held := await _settle(f.stage)
	var expected: Array = []
	for id in PARTY:
		for pose in Warmup.REACTION_POSES:
			expected.append(RBMVisualAssets.frame_path(id, pose))
	expected.append_array([RBMVisualAssets.frame_path("healer", 4), RBMVisualAssets.frame_path("healer", 5)])
	assert_eq(held, _sorted(expected), "a boss without declared presentations: the party's reaction poses and the healer's finisher")

func test_first_plays_read_nothing_that_was_not_read_ahead() -> void:
	await _assert_first_play_reads_nothing_new(_battle("appearance_musha", [_attack("single")]), "musha_single")
	await _assert_first_play_reads_nothing_new(_battle("appearance_musha", [_attack("all")]), "musha_aoe")
	await _assert_first_play_reads_nothing_new(_battle("appearance_musha", [_heal()]), "")
	await _assert_first_play_reads_nothing_new(_battle("appearance_musha", [_attack("single")], false, true), "musha_awakened_single")
	await _assert_first_play_reads_nothing_new(_battle("appearance_musha", [_attack("all")], false, true), "musha_awakened_aoe")
	await _assert_first_play_reads_nothing_new(_battle("appearance_dragon", [_attack("single")]), "")
	await _assert_first_play_reads_nothing_new(_battle("appearance_ghost", [_attack("single")]), "")
	await _assert_first_play_reads_nothing_new(_battle("appearance_ghost", [_attack("all")]), "")
	await _assert_first_play_reads_nothing_new(_battle("appearance_gentleman", [_attack("single")]), "gentleman_single")
	await _assert_first_play_reads_nothing_new(_battle("appearance_gentleman", [_attack("all")]), "gentleman_all")

func test_first_awakenings_read_nothing_that_was_not_read_ahead() -> void:
	for appearance in ["appearance_musha", "appearance_gentleman"]:
		var f := _battle(appearance, [_attack("single")], true)
		var held := await _settle(f.stage)
		var entry: Dictionary = {}
		var before: Dictionary = f.session.battle.presentation_state().duplicate(true)
		for e in f.session.resolve_ally_action({"type": "attack"}):
			if str(e.get("action", "")) == "awakening":
				entry = e
		assert_false(entry.is_empty(), "%s: the real awakening entry" % appearance)
		f.stage.set_state(before)
		var read := await _play_and_collect_reads(f.stage, entry)
		assert_eq(_unwarmed(read, held), [], "%s: the awakening reads nothing that was not read ahead" % appearance)

func test_healer_finisher_reads_nothing_that_was_not_read_ahead() -> void:
	var f := _battle("appearance_slime", [_attack("single")])
	var held := await _settle(f.stage)
	var entry: Dictionary = {}
	var before: Dictionary = {}
	for attempt in 24:
		before = f.session.battle.presentation_state().duplicate(true)
		var action := {"type": "defend"}
		var pending = RBMBattleUiKit.unit_by_id(f.session.battle, f.session.pending_ally_id())
		if pending != null and str(pending.character_id) == "healer":
			pending.sp = pending.max_sp
			action = {"type": "skill", "skill_id": "healer_heal_all"}
		for e in f.session.resolve_ally_action(action):
			if str(e.get("skill_id", "")) == "healer_heal_all":
				entry = e
		if not entry.is_empty():
			break
	assert_false(entry.is_empty(), "a real healer_heal_all entry")
	f.stage.set_state(before)
	var read := await _play_and_collect_reads(f.stage, entry, RBMBattleUiKit.find_skill_for_actor(entry.actor, "healer_heal_all", f.session.battle))
	assert_eq(_unwarmed(read, held), [])

## 武者の単体の行動と、事前読み込みを手放して素材がキャッシュから消えた状態(戦闘を始める前の画面からすぐに
## 戦闘を始めた時・遅い PC で読み終えていない時と同じ)。宣言した素材とそのうち読まれていない物も返す。
func _unread_musha_single() -> Dictionary:
	var f := _battle("appearance_musha", [_attack("single")])
	await _settle(f.stage)
	var pair := _boss_entry(f)
	var declared: Array = f.stage.BOSS_SINGLE_PRESENTATIONS["musha"].warm_paths("musha", "single")
	f.stage._presentation_warmup.release()
	await get_tree().process_frame
	var unread: Array = []
	for path in declared:
		if not ResourceLoader.has_cached(path):
			unread.append(path)
	return {"f": f, "pair": pair, "declared": declared, "unread": unread}

## QA-06: 素材を読み終えていない専用の演出は、その行動の演出を始める境界で待つ(固定の時間ではなく、読み終える
## まで)。待つ間はその行動が再生中のままで、HP の表示・次の行動は先へ進まない。読み終えてから始まった演出は、
## 宣言した素材を始めた時点で持っている(演出の最中に同期で読まない)。
func test_a_presentation_whose_assets_are_not_read_waits_at_its_start_and_nothing_moves_on() -> void:
	var u := await _unread_musha_single()
	var f: Dictionary = u.f
	assert_false(u.pair.is_empty(), "a real boss entry")
	assert_gt(u.unread.size(), 0, "some declared assets are not read (the premise of this test)")
	var presenter := RBMBattlePresenter.new()
	presenter.enabled = true
	add_child_autofree(presenter)
	presenter.setup(f.stage)
	var impacts: Array = []
	presenter.entry_impact.connect(func(e): impacts.append(e))
	var next := {"actor": "boss", "action": "none", "visual_state": u.pair[0].get("visual_state", {})}
	presenter.play([u.pair[0], next], f.session.battle, u.pair[1])
	assert_true(f.stage.is_playing(), "the action is playing while it waits")
	assert_null(f.stage._skill_presentation, "the presentation waits for its assets")
	var warm = f.stage._presentation_warmup
	assert_true(u.unread.has(warm._loading), "the missing assets are read first")
	var waited := 0
	var moved_on := false
	while f.stage._skill_presentation == null and waited < 900:
		await get_tree().process_frame
		waited += 1
		if f.stage._skill_presentation == null and (not impacts.is_empty() or presenter._cursor != 0 or presenter.display_state() != u.pair[1] or not f.stage.is_playing()):
			moved_on = true
	assert_not_null(f.stage._skill_presentation, "the presentation starts once its assets are read")
	assert_gt(waited, 1, "it waited for the reads (at least one frame after they were done)")
	assert_false(moved_on, "while waiting, no HP display, impact or next action moved on")
	var missing_at_start: Array = []
	for path in u.declared:
		if not ResourceLoader.has_cached(path) and not warm._failed.has(path):
			missing_at_start.append(path)
	assert_eq(missing_at_start, [], "every declared asset was read before the presentation started")
	assert_eq(presenter._cursor, 0, "the next action waits for this presentation")
	presenter.cancel()

func test_cancelling_while_waiting_never_starts_the_presentation() -> void:
	var u := await _unread_musha_single()
	var f: Dictionary = u.f
	assert_gt(u.unread.size(), 0, "some declared assets are not read (the premise of this test)")
	var skill: Dictionary = RBMBattleUiKit.find_skill_for_actor("boss", str(u.pair[0].get("skill_id", "")), f.session.battle)
	f.stage.play_entry(u.pair[0], skill)
	assert_null(f.stage._skill_presentation)
	f.stage.cancel()
	assert_false(f.stage.is_playing())
	for i in 120:
		await get_tree().process_frame
	assert_null(f.stage._skill_presentation, "a cancelled wait never starts the presentation")
	assert_false(f.stage.is_processing(), "the stage stops checking once nothing waits")

func test_a_presentation_whose_assets_are_read_starts_at_once() -> void:
	var f := _battle("appearance_musha", [_attack("single")])
	await _settle(f.stage)
	var pair := _boss_entry(f)
	var skill: Dictionary = RBMBattleUiKit.find_skill_for_actor("boss", str(pair[0].get("skill_id", "")), f.session.battle)
	f.stage.set_state(pair[1])
	f.stage.play_entry(pair[0], skill)
	assert_not_null(f.stage._skill_presentation, "nothing to wait for: it starts in the same call as before")
	f.stage.cancel()

func test_moving_the_stage_keeps_the_reads_and_freeing_it_collects_the_pending_one() -> void:
	var f := _battle("appearance_musha", [_attack("single"), _attack("all")], true)
	var warm = f.stage._presentation_warmup
	var loading := ""
	for i in 300:
		await get_tree().process_frame
		if warm._loading != "":
			loading = warm._loading
			break
	assert_ne(loading, "", "a background read is in flight")
	var planned: Array = warm.planned_paths()
	# The battle views move their stage into the full-screen layout: nothing is lost.
	var parent: Node = f.stage.get_parent()
	parent.remove_child(f.stage)
	assert_eq(warm._loading, loading, "moving the stage keeps the read in flight")
	assert_eq(warm.planned_paths(), planned)
	parent.add_child(f.stage)
	# Freeing the stage collects the read in flight.
	loading = warm._loading
	if loading == "":
		for i in 300:
			await get_tree().process_frame
			if warm._loading != "":
				loading = warm._loading
				break
	parent.remove_child(f.stage)
	f.stage.free()
	if loading != "":
		assert_eq(ResourceLoader.load_threaded_get_status(loading), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "the request was collected")

func test_gentleman_motion_data_read_as_a_json_resource_matches_the_file() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GentlemanMotion.MOTION_PATH))
	for kind in ["single", "all", "awakening", "awakened_single", "awakened_all", "buff", "heal"]:
		assert_eq(GentlemanMotion.clip(kind), parsed["clips"][kind], kind)
	assert_true(load(GentlemanMotion.MOTION_PATH) is JSON)
