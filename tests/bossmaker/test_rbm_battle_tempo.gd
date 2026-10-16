extends GutTest
## 戦闘テンポの改善（2026-10-16）の契約。
## 味方のカード: 同じ戦闘・同じ顔ぶれなら作り直さず値だけ更新し、作り直した時と同じ表示になる。新しい戦闘・顔ぶれでは作り直す。
## 顔の切り出し: 絵ごとに1回だけ求め、同じ切り出しを使い回す。

func _definition(party: Array = ["hero", "butler", "healer", "tank"]) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "テンポ検証"
	draft.hp = 99999
	draft.atk = 200
	draft.spd = 1
	for character_id in party:
		draft.add_party_character(character_id)
	var skill_id := draft.add_skill({"name": "検証攻撃", "type": "attack", "target": "all", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return draft.to_definition()

## カードに表示している中身（名前・HP・SP・バー・薄さ）
func _shown(rows: Control) -> Array:
	var out: Array = []
	for card in rows.get_children():
		var id := str(card.name).trim_prefix("PartyRow_")
		var sp_bar := card.find_child("PartyRowSPBar_" + id, true, false) as ProgressBar
		out.append([str(card.name),
			(card.find_child("PartyRowName_" + id, true, false) as Label).text,
			(card.find_child("PartyRowHP_" + id, true, false) as Label).text,
			(card.find_child("PartyRowHPBar_" + id, true, false) as ProgressBar).value,
			(card.find_child("PartyRowHPBar_" + id, true, false) as ProgressBar).max_value,
			(card.find_child("PartyRowSP_" + id, true, false) as Label).text,
			sp_bar.value if sp_bar != null else -1.0,
			card.modulate])
	return out

func _fresh(battle: RBMBattle) -> Control:
	var rows := VBoxContainer.new()
	add_child_autofree(rows)
	for unit in battle.party:
		rows.add_child(RBMBattleUiKit.build_party_card(unit, func(_id: int): pass))
	return rows

func test_same_battle_updates_values_without_rebuilding_and_matches_a_fresh_build() -> void:
	var session := RBMChallengeSession.new(_definition(), 7)
	var battle := session.battle
	var rows := VBoxContainer.new()
	add_child_autofree(rows)
	RBMBattleUiKit.sync_party_cards(rows, battle, func(_id: int): pass)
	var first: Array = rows.get_children()
	assert_eq(first.size(), 4)
	# 戦闘を進めて HP・SP を変え、1人を戦闘不能にする
	for i in 3:
		session.resolve_ally_action({"type": "attack"})
	battle.party[1].hp = 0
	battle.party[0].sp = maxi(0, battle.party[0].sp - 10)
	RBMBattleUiKit.sync_party_cards(rows, battle, func(_id: int): pass)
	assert_eq(rows.get_children(), first, "同じ戦闘・同じ顔ぶれならカードを作り直さない")
	assert_eq(_shown(rows), _shown(_fresh(battle)), "値だけ更新した表示が、作り直した表示と同じ")

func test_new_battle_or_different_party_rebuilds_the_cards() -> void:
	var a := RBMChallengeSession.new(_definition(), 7)
	var rows := VBoxContainer.new()
	add_child_autofree(rows)
	RBMBattleUiKit.sync_party_cards(rows, a.battle, func(_id: int): pass)
	var first: Array = rows.get_children()
	var b := RBMChallengeSession.new(_definition(["samurai", "butler", "healer", "hero"]), 7)
	RBMBattleUiKit.sync_party_cards(rows, b.battle, func(_id: int): pass)
	assert_ne(rows.get_children(), first, "別の戦闘では作り直す")
	assert_eq(_shown(rows), _shown(_fresh(b.battle)))
	assert_eq(str(rows.get_child(0).get_meta("character_id")), "samurai", "顔ぶれが変われば、そのキャラクターのカードになる")
	await get_tree().process_frame  # 外した前のカードは次のフレームで解放される（作り直しは queue_free）

func test_portrait_region_is_computed_once_and_reused() -> void:
	var one := RBMBattleUiKit.build_portrait("hero", 32.0, "A")
	var two := RBMBattleUiKit.build_portrait("hero", 32.0, "B")
	add_child_autofree(one)
	add_child_autofree(two)
	assert_true(one.texture is AtlasTexture)
	assert_eq((one.texture as AtlasTexture).region, (two.texture as AtlasTexture).region)
	var texture := RBMVisualAssets.texture("hero")
	var used := texture.get_image().get_used_rect()
	var side := mini(used.size.x, int(used.size.y * 0.50))
	assert_eq((one.texture as AtlasTexture).region, Rect2(used.position.x + (used.size.x - side) * 0.5, used.position.y, side, side), "切り出しは今までと同じ位置")
	assert_true(RBMBattleUiKit._portrait_regions.has(texture.resource_path))

# ---------------------------------------------------------------------------
# 演出の時刻の対応表（rbm_tempo_map.gd）と、ボスごとの詰める区間

const TempoMap = preload("res://src/bossmaker/visuals/rbm_tempo_map.gd")
const GentlemanMotion = preload("res://src/bossmaker/visuals/rbm_gentleman_motion.gd")
const MushaMotion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
const MushaAwakenedMotion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const MushaAwakenedFrames = preload("res://src/bossmaker/visuals/rbm_musha_awakened_frame_presentation.gd")
const MushaInk = preload("res://src/bossmaker/visuals/rbm_musha_ink_director.gd")
const AstronautTimeline = preload("res://src/bossmaker/visuals/rbm_astronaut_timeline.gd")
const DragonMotion = preload("res://src/bossmaker/visuals/rbm_dragon_motion.gd")
const GhostMotion = preload("res://src/bossmaker/visuals/rbm_ghost_motion.gd")
const GhostDriver = preload("res://src/bossmaker/visuals/rbm_ghost_presentation.gd")
const KnightMotion = preload("res://src/bossmaker/visuals/rbm_knight_motion.gd")
const KnightSupport = preload("res://src/bossmaker/visuals/rbm_knight_support.gd")
const GolemSlam = preload("res://src/bossmaker/visuals/rbm_golem_ground_slam.gd")

const SAMPLE := [[1.0, 2.0, 0.0], [3.0, 4.0, 0.5]]

func test_time_map_lengths_and_round_trip() -> void:
	assert_almost_eq(TempoMap.real_length(6.0, SAMPLE), 6.0 - 1.0 - 0.5, 0.0001)
	assert_almost_eq(TempoMap.real_length(6.0, []), 6.0, 0.0001)
	# 飛ばさない区間の時刻は、行き（演出→実時間）と帰り（実時間→演出）で一致する（飛ばす区間のちょうど終わり 2.0 は、
	# 飛ぶ前の 1.0 と同じ瞬間なので除く）
	for t in [0.0, 0.5, 1.0, 2.5, 3.0, 3.25, 3.5, 4.0, 5.0, 6.0]:
		var real: float = TempoMap.real_time_at(t, 6.0, SAMPLE)
		assert_almost_eq(TempoMap.presentation_time(real, 6.0, SAMPLE), t, 0.0001, "t=%.2f" % t)
	# 飛ばす区間の中の時刻は、その区間の始まりに着く
	assert_almost_eq(TempoMap.real_time_at(1.5, 6.0, SAMPLE), 1.0, 0.0001)
	# 速める区間は、その区間の長さの割合で進む
	assert_almost_eq(TempoMap.real_time_at(3.5, 6.0, SAMPLE), 1.0 + 1.0 + 0.25, 0.0001)

func test_tween_passes_every_kept_moment_once_in_order_and_reports_jumps() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var seen: Array = []
	var jumps: Array = []
	var tween := host.create_tween()
	tween.pause()
	TempoMap.tween_timeline(tween, func(t: float): seen.append(t), 6.0, SAMPLE, func(t: float): jumps.append(t))
	var crossed := 0
	var last := -1.0
	for i in 200:
		tween.custom_step(0.05)
	for t in seen:
		assert_true(float(t) >= last - 0.0001, "the presentation time never goes back")
		if last < 2.5 and float(t) >= 2.5:
			crossed += 1
		last = float(t)
	assert_almost_eq(last, 6.0, 0.0001, "the presentation reaches its end")
	assert_eq(crossed, 1, "a moment after a skipped part is crossed exactly once")
	# 飛ばす区間は終わりで1回、速める区間（3.0〜4.0 を 0.5秒で）は RESYNC_STEP（0.1秒）ごとに、その時の演出の時刻へ音を合わせ直す
	var steps := ceili(0.5 / TempoMap.RESYNC_STEP)
	assert_eq(jumps.size(), 1 + steps, "the track is re-synced at the end of the skipped part and every step of the sped part")
	assert_almost_eq(float(jumps[0]), 2.0, 0.0001)
	for i in steps:
		assert_almost_eq(float(jumps[1 + i]), 3.0 + float(i + 1) / steps, 0.0001, "re-synced to where the presentation is")
	assert_almost_eq(float(jumps[jumps.size() - 1]), 4.0, 0.0001)
	for t in seen:
		assert_false(float(t) > 1.0001 and float(t) < 1.9999, "nothing inside the skipped part is shown")
	assert_almost_eq(TempoMap.real_length(6.0, SAMPLE), 4.5, 0.0001)

## 区間の決まり: 順番どおりで重ならない、最後の0.5秒（かばう味方が戻る）には掛からない、命中の瞬間とその後（攻撃は0.65秒の揺れ、
## 回復・強化は0.30秒）には掛からない、速める区間は元より短い実時間。
func _check_table(name: String, segments: Array, duration: float, impacts: Array, attack: bool) -> void:
	var cursor := 0.0
	for seg in segments:
		var a := float(seg[0])
		var b := float(seg[1])
		var r := float(seg[2])
		assert_true(a >= cursor and a < b, "%s: %s is in order and does not overlap" % [name, str(seg)])
		assert_true(b <= duration - 0.5 + 0.0001, "%s: %s leaves the last 0.5s" % [name, str(seg)])
		assert_true(r >= 0.0 and r < b - a, "%s: %s is shorter than the original" % [name, str(seg)])
		for hit in impacts:
			var guard_end := float(hit) + (0.65 if attack else 0.30)
			assert_false(a < guard_end and b > float(hit) - 0.05, "%s: %s keeps the impact at %.2f" % [name, str(seg), float(hit)])
		cursor = b

func test_every_boss_table_keeps_the_impacts_and_the_ending() -> void:
	for kind in GentlemanMotion.TEMPO:
		var clip: Dictionary = GentlemanMotion.clip(kind)
		_check_table("gentleman " + kind, GentlemanMotion.tempo(kind), float(clip.duration), [float(clip.impact)], not kind in ["heal", "buff"])
	_check_table("musha single", MushaMotion.tempo("single"), MushaMotion.SINGLE_DURATION, [MushaMotion.SINGLE_FIRST_HIT, MushaMotion.SINGLE_FINAL], true)
	_check_table("musha all", MushaMotion.tempo("all"), MushaMotion.ALL_DURATION, [MushaMotion.ALL_FIRST, MushaMotion.ALL_FINAL], true)
	# 全体は納刀の鍔鳴り（5.40秒、音の合図なので0.30秒）も残す
	_check_table("musha all click", MushaMotion.tempo("all"), MushaMotion.ALL_DURATION, [5.40], false)
	_check_table("musha support", MushaMotion.tempo("support"), MushaMotion.SUPPORT_DURATION, [MushaMotion.SUPPORT_RELIGHT], false)
	var awakened_all := MushaAwakenedMotion.duration("all") + MushaAwakenedFrames.ALL_HOLD
	_check_table("musha awakened all", MushaAwakenedFrames.TEMPO_ALL, awakened_all, [MushaInk.A_FLASH, MushaInk.A_SWEEP, MushaInk.A_IMPACT], true)
	_check_table("musha awakened all click", MushaAwakenedFrames.TEMPO_ALL, awakened_all, [MushaInk.A_CLICK2], false)
	for seg in MushaAwakenedFrames.TEMPO_ALL:
		assert_true(float(seg[0]) >= MushaInk.A_CLICK2 + 0.14 and float(seg[1]) <= MushaInk.A_SWEEP, "only the stillness between the click and the delayed cuts")
	for kind in AstronautTimeline.TEMPO:
		_check_table("astronaut " + kind, AstronautTimeline.tempo(kind), float(AstronautTimeline.DURATIONS[kind]), [float(AstronautTimeline.IMPACTS[kind])], true)
	# 竜の長さは rbm_dragon_presentation.gd の duration の表（ブレス 4.05・覚醒後のブレス 4.45・隕石 6.65）
	var dragon := {"breath": [4.05, DragonMotion.BREATH_HIT], "focused_breath": [4.45, DragonMotion.FOCUSED_HIT], "meteors": [6.65, DragonMotion.METEOR_HIT]}
	for kind in DragonMotion.TEMPO:
		_check_table("dragon " + kind, DragonMotion.tempo(kind), float(dragon[kind][0]), [float(dragon[kind][1])], true)
	var ghost = GhostDriver.new()
	var ghost_duration: float = ghost.duration
	ghost.free()
	var ghost_hits := {"single": GhostMotion.SINGLE_HIT, "all": GhostMotion.ALL_HIT, "heal": 2.40, "buff": 2.40}
	for kind in GhostMotion.TEMPO:
		_check_table("ghost " + kind, GhostMotion.tempo(kind), ghost_duration, [float(ghost_hits[kind])], kind in ["single", "all"])
	var knight = KnightSupport.new()
	for kind in KnightMotion.TEMPO:
		_check_table("knight " + kind, KnightMotion.tempo(kind), float(knight.duration), [float(knight.impact_time)], false)
	knight.free()
	_check_table("golem all", GolemSlam.TEMPO, GolemSlam.DURATION, [GolemSlam.HIT], true)
