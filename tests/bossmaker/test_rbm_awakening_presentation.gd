extends GutTest

## RPG BOSS MAKER — 覚醒(Awakening)のBattle presentation層のテスト。
## test_tank_hammer_finish.gd/test_samurai_wind_finish.gdと同じ「実
## RBMBattleStage+RBMCreatorTestSessionを使い、impact/finishedの二値
## シグナル契約とシミュレーション不変を検証する」方針を踏襲する。
## 覚醒自体の発動条件・1戦闘1回・Buff/Heal適用はtest_rbm_awakening.gd
## （バトルロジック層）で既に検証済み——ここでは「覚醒の再生がstage側で
## 正しく完結するか」だけを見る。

func _session() -> RBMCreatorTestSession:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "覚醒演出テスト"
	# hero.jsonの既定atk(240)の通常攻撃1発で確実に50%以下(かつボスは生存)
	# になるよう、ボスHPを400に設定する(240/400=60%減、160/400=40%残)。
	draft.hp = 400
	draft.atk = 10
	draft.spd = 10
	draft.add_party_character("hero")
	draft.set_awakening({
		"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
		"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
		"heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0},
	})
	return RBMCreatorTestSession.new(draft.to_definition(), 1)

func _stage(session: RBMCreatorTestSession) -> RBMBattleStage:
	var result := RBMBattleStage.new()
	result.size = Vector2(1280, 720)
	result.set_meta("fullscreen_formation", true)
	add_child_autofree(result)
	result.configure(session.battle, "appearance_dragon")
	result.set_state(session.battle.presentation_state())
	return result

func _awakening_entry(session: RBMCreatorTestSession) -> Dictionary:
	var log := session.resolve_ally_action({"type": "attack"})
	for entry in log:
		if str(entry.get("action", "")) == "awakening":
			return entry
	return {}

func test_awakening_entry_plays_and_emits_impact_and_finished_exactly_once() -> void:
	var session := _session()
	var stage := _stage(session)
	var entry := _awakening_entry(session)
	assert_false(entry.is_empty(), "hero's 600-atk hit must have dropped the 1000hp boss below 50% and triggered awakening")
	var final_snapshot := session.battle.snapshot()
	var impacts: Array = []
	var finishes: Array = []
	stage.impact.connect(func(e): impacts.append(e))
	stage.finished.connect(func(): finishes.append(true))
	stage.play_entry(entry)
	assert_eq(stage._phase, "awakening")
	assert_true(stage._awakening_transform.visible)
	stage._tween.custom_step(1.0)
	await get_tree().process_frame
	assert_eq(impacts.size(), 1)
	assert_eq(finishes.size(), 1)
	assert_false(stage.is_playing())
	assert_false(stage._awakening_transform.visible)
	assert_eq(stage._awakening_transform.age, -1.0)
	assert_eq(session.battle.snapshot(), final_snapshot, "VFX playback must not change battle or RNG")

func test_cancel_mid_awakening_playback_cleans_up() -> void:
	var session := _session()
	var stage := _stage(session)
	var entry := _awakening_entry(session)
	assert_false(entry.is_empty())
	var finishes: Array = []
	stage.finished.connect(func(): finishes.append(true))
	stage.play_entry(entry)
	stage._tween.custom_step(0.2)
	stage.cancel()
	await get_tree().process_frame
	assert_false(stage.is_playing())
	assert_false(stage._awakening_transform.visible)
	assert_eq(stage._awakening_transform.age, -1.0)
	assert_eq(finishes.size(), 0, "a cancelled awakening entry must never fire finished afterward")

func test_awakening_entry_does_not_go_through_the_generic_windup_travel_chain() -> void:
	var session := _session()
	var stage := _stage(session)
	var entry := _awakening_entry(session)
	assert_false(entry.is_empty())
	stage.play_entry(entry)
	# The generic chain would have set _profile/_targets from Motions.profile();
	# the awakening path must bypass it entirely and never touch _profile.
	assert_eq(stage._profile, {})
	assert_eq(stage._targets, [])
	stage._tween.custom_step(1.0)
	await get_tree().process_frame
