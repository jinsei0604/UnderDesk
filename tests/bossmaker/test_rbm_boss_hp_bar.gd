extends GutTest
## ボスの HP バー（rbm_boss_hp_bar.gd）: 値・最大値・覚醒・非公開、戦闘画面での置き場所、命中の瞬間との同期（カウンター・REWIND を含む）。
## 表示専用で、戦闘の状態を変えないことも確かめる。

const BossHpBar = preload("res://src/bossmaker/rbm_boss_hp_bar.gd")

func _definition(party: Array = ["hero"], boss_target := "single") -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "HPバーの確認"
	draft.hp = 5000
	draft.atk = 30
	draft.spd = 1
	for id in party:
		draft.add_party_character(id)
	var skill_id := draft.add_skill({"name": "攻撃", "type": "attack", "target": boss_target, "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill_id] = 100.0
	return draft.to_definition()

func _bar() -> Control:
	var bar: Control = BossHpBar.new()
	bar.size = Vector2(608, 58)
	add_child_autofree(bar)
	return bar

func test_values_awakening_and_max_changes() -> void:
	var bar := _bar()
	bar.apply_state({"hp": 3000, "max_hp": 4000}, false, true)
	var a: Dictionary = bar.audit()
	assert_eq([a["hp"], a["max_hp"], a["awakened"], a["hp_visible"]], [3000, 4000, false, true])
	assert_almost_eq(float(a["shown"]), 0.75, 0.0001)
	assert_eq(bar.display_text(), "HP 3,000 / 4,000", "3桁ごとに区切る（案C）")
	bar.apply_state({"hp": 4500, "max_hp": 6000}, true, true, true)
	a = bar.audit()
	assert_eq([a["hp"], a["max_hp"], a["awakened"]], [4500, 6000, true], "awakening can change the maximum")
	assert_almost_eq(float(a["shown"]), 0.75, 0.0001, "without a window (tests) the value is set at once")
	bar.apply_state({"hp": -20, "max_hp": 0}, true, true)
	a = bar.audit()
	assert_eq([a["hp"], a["max_hp"]], [0, 1], "never below 0, never a zero maximum")
	bar.apply_state({}, false, true)
	assert_eq(bar.audit()["hp"], 0, "an empty state changes nothing")

func test_hidden_hp_shows_no_amount() -> void:
	var bar := _bar()
	bar.apply_state({"hp": 1234, "max_hp": 4000}, false, false)
	assert_false(bar.audit()["hp_visible"])
	assert_eq(bar.display_text(), tr("HP　%s") % tr("？？？"), "same words as the boss detail when HP is private")
	assert_false(bar.display_text().contains("1234"))
	assert_false(bar.display_text().contains("4000"))

func test_the_battle_screen_places_the_bar_under_the_boss_name() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.size = Vector2(1280, 720)
	await get_tree().process_frame
	view.start_battle(_definition(), RBMBattleUiKit.ALL_VISIBLE, "appearance_dragon")
	await get_tree().process_frame
	await get_tree().process_frame
	var bar := view.find_child("BossHpBar", true, false) as BossHpBar
	assert_not_null(bar, "the fullscreen battle HUD has a boss HP bar")
	assert_eq(bar.get_parent().name, "BattleHUD")
	# 案C（2026-10-23）: 左上のボスの欄の中。上に「BOSS」、名前と同じ行の右に数値、下に細いバー。
	assert_eq(Rect2(bar.position, bar.size), Rect2(32, 18, 608, 58), "inside the boss panel; clear of the boss, its attacks and the turn order")
	var panel := view.find_child("BossPanel", true, false) as Control
	assert_true(Rect2(panel.position, panel.size).encloses(Rect2(bar.position, bar.size)), "the bar sits inside the boss panel")
	var boss: RBMUnit = view.session.battle.boss
	assert_eq([bar.audit()["hp"], bar.audit()["max_hp"]], [boss.hp, boss.max_hp])
	var label := view.find_child("BossLabel", true, false) as Control
	var name_rect := Rect2(label.position, label.size)
	var bar_rect: Rect2 = bar.bar_rect()
	bar_rect.position += bar.position
	assert_false(name_rect.intersects(bar_rect), "the name and the bar do not overlap")
	assert_lte(name_rect.end.x, bar.position.x + bar.text_left(), "the name stops before the HP numbers")
	assert_gte(name_rect.position.y, bar.position.y + 14.0, "the name is below the BOSS caption")
	var hidden := RBMBattleUiKit.ALL_VISIBLE.duplicate()
	hidden["hp"] = false
	view.start_battle(_definition(), hidden, "appearance_dragon")
	await get_tree().process_frame
	assert_false(bar.audit()["hp_visible"], "a challenge with private HP keeps it private on the bar")

func test_the_bar_moves_at_the_impact_and_never_shows_future_damage() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 3)
	var before := session.battle.presentation_state()
	var hud := Control.new()
	add_child_autofree(hud)
	var bar := _bar()
	bar.name = "BossHpBar"
	bar.reparent(hud)
	RBMBattlePresenter.apply_status_snapshot(hud, before)
	var log := session.resolve_ally_action({"type": "attack"})
	var final_sim := session.battle.snapshot()
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	add_child_autofree(stage)
	stage.configure(session.battle, "")
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	var seen: Array = []
	presenter.entry_impact.connect(func(entry: Dictionary):
		RBMBattlePresenter.apply_status_snapshot(hud, entry["visual_state"], true)
		seen.append(int(bar.audit()["hp"])))
	presenter.play(log, session.battle, before)
	assert_eq(bar.audit()["hp"], int(before["boss"]["hp"]), "before the hit lands the bar shows the old HP")
	for i in range(400):
		if not presenter.is_playing():
			break
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.03)
		await get_tree().process_frame
	assert_eq(seen.size(), log.size())
	assert_eq(seen[0], int(log[0]["visual_state"]["boss"]["hp"]), "the ally's hit moves the boss bar at its impact")
	assert_eq(session.battle.snapshot(), final_sim, "display only")

func test_the_counter_moves_the_boss_bar_only_when_the_counter_lands() -> void:
	var session := RBMCreatorTestSession.new(_definition(["hero", "samurai"], "all"), 7)
	var before := session.battle.presentation_state()
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
			else:
				before = entry["visual_state"]
	assert_false(boss_entry.is_empty(), "sanity")
	var hud := Control.new()
	add_child_autofree(hud)
	var bar := _bar()
	bar.name = "BossHpBar"
	bar.reparent(hud)
	RBMBattlePresenter.apply_status_snapshot(hud, before)
	var stage := RBMBattleStage.new()
	stage.size = Vector2(1280, 720)
	stage.set_meta("fullscreen_formation", true)
	add_child_autofree(stage)
	stage.configure(session.battle, "")
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	presenter.enabled = true
	presenter.setup(stage)
	# 関数の中から書き換えるので、入れ物（Dictionary）に入れる
	var got := {"hits": -1, "counter": -1}
	presenter.entry_hits_landed.connect(func(_e: Dictionary, state: Dictionary):
		RBMBattlePresenter.apply_status_snapshot(hud, state, true)
		got["hits"] = int(bar.audit()["hp"]))
	presenter.entry_impact.connect(func(entry: Dictionary):
		RBMBattlePresenter.apply_status_snapshot(hud, entry["visual_state"], true)
		got["counter"] = int(bar.audit()["hp"]))
	presenter.play([boss_entry], session.battle, before)
	for i in range(400):
		if int(got["counter"]) >= 0:
			break
		if stage._tween != null and stage._tween.is_valid():
			stage._tween.custom_step(0.02)
		await get_tree().process_frame
	assert_eq(got["hits"], int(before["boss"]["hp"]), "when the boss's attack lands, the boss bar does not move yet")
	assert_eq(got["counter"], int(boss_entry["visual_state"]["boss"]["hp"]), "the reflected damage moves it when the counter lands")
	assert_lt(int(got["counter"]), int(got["hits"]))

func test_an_instant_update_replaces_a_moving_bar() -> void:
	var bar := _bar()
	bar.apply_state({"hp": 4000, "max_hp": 4000}, false, true)
	# 画面のある実行と同じに動かした状態を作ってから、すぐ入れる更新（REWIND・作り直し）で上書きする
	bar._from = 1.0
	bar._target = 0.25
	bar._ease = 0.05
	bar._chip_age = 0.1
	bar.set_process(true)
	bar.apply_state({"hp": 3600, "max_hp": 4000}, false, true)
	var a: Dictionary = bar.audit()
	assert_almost_eq(float(a["shown"]), 0.9, 0.0001)
	assert_almost_eq(float(a["chip"]), 0.9, 0.0001)
	assert_false(a["animating"], "the old motion is gone")
	for i in range(10):
		await get_tree().process_frame
	assert_almost_eq(float(bar.audit()["shown"]), 0.9, 0.0001, "and does not come back")

## 演出の後の画面の更新で同じ値がもう一度来ても、減っている途中・減った分が縮む途中の動きは止めない（減った分が急に消えない）。
func test_the_same_value_again_keeps_the_motion() -> void:
	var bar := _bar()
	bar.apply_state({"hp": 4000, "max_hp": 4000}, false, true)
	bar.apply_state({"hp": 3000, "max_hp": 4000}, false, true)
	# 画面のある実行と同じに、減った分が残っている状態を作る
	bar._chip = 1.0
	bar._chip_start = 1.0
	bar._chip_age = 0.1
	bar.set_process(true)
	bar.apply_state({"hp": 3000, "max_hp": 4000}, false, true)
	var a: Dictionary = bar.audit()
	assert_true(a["animating"], "the chip keeps shrinking")
	assert_almost_eq(float(a["chip"]), 1.0, 0.0001)
	assert_almost_eq(float(a["shown"]), 0.75, 0.0001)
