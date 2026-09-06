extends GutTest

## RPG BOSS MAKER Phase 1 Step 4 §8/§9 — RBMCreatorTestSession (TEST BATTLE +
## Turn REWIND history management) tests.

func _random_candidate_boss() -> Dictionary:
	return {
		"boss_id": "session_boss", "boss_name": "Session Boss",
		"hp": 5000, "atk": 50, "spd": 10,
		"skills": [
			{"skill_id": "hit_a", "name": "A", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"skill_id": "hit_b", "name": "B", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_actions": [{"skill_id": "hit_a", "weight": 50}, {"skill_id": "hit_b", "weight": 50}],
	}

func _definition(party_count: int = 1) -> Dictionary:
	var ids := ["hero", "butler", "healer", "samurai"]
	var party := []
	for i in range(party_count):
		party.append({"character_id": ids[i]})
	return {"boss": _random_candidate_boss(), "party": party}

## Round 5-2: 任意のboss defを使うDefinitionを組み立てる（_definition()の
## 一般化——ambush/先行ボスなど専用fixture用）。
func _definition_with(boss: Dictionary, party_count: int = 1) -> Dictionary:
	var ids := ["hero", "butler", "healer", "samurai"]
	var party := []
	for i in range(party_count):
		party.append({"character_id": ids[i]})
	return {"boss": boss, "party": party}

## Round 5-2: turn_start_interruptで即座にダメージを与える「奇襲」を持つ、
## 最も遅い（SPD最低）ボス——通常攻撃フェーズより前に何が起きたかを明確に
## 分離して観測できる。
func _boss_with_turn_start_ambush() -> Dictionary:
	var boss := _random_candidate_boss()
	boss["skills"].append({"skill_id": "ambush", "name": "Ambush", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 2.0})
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "ambush", "timing": "turn_start_interrupt", "order": 0}]
	return boss

## 実機プレイ改善①: 旧一括resolve_turn(ally_actions)の廃止に伴い、
## かつて_defend_all()が組み立てていた「全員分の行動辞書」は不要になった
## ——このファイルのfixture(_definition())は常に単一パーティ("hero"のみ)の
## ため、「そのラウンドで入力待ちの唯一の味方」をsession.resolve_ally_action(
## {"type":"defend"})で1回解決する呼び出しが、旧_defend_all()の1ラウンド分
## と等価になる。

# ---------------------------------------------------------------------------
# start / validation gate
# ---------------------------------------------------------------------------

func test_valid_definition_starts_a_working_battle() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	assert_true(session.start_ok())
	assert_not_null(session.battle)
	assert_eq(session.reachable_turns(), [1])

func test_invalid_definition_never_starts_a_battle() -> void:
	var bad := {"boss": _random_candidate_boss(), "party": []}  # §12: empty party is invalid
	var session := RBMCreatorTestSession.new(bad, 1)
	assert_false(session.start_ok())
	assert_null(session.battle)
	assert_true(session.start_errors().size() > 0)

# ---------------------------------------------------------------------------
# per-turn history growth
# ---------------------------------------------------------------------------

func test_reachable_turns_grows_by_one_each_resolved_turn() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	assert_eq(session.reachable_turns(), [1])
	session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns(), [1, 2])
	session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns(), [1, 2, 3])

func test_history_stops_growing_once_the_battle_ends() -> void:
	var boss := _random_candidate_boss()
	boss["hp"] = 1
	var session := RBMCreatorTestSession.new({"boss": boss, "party": [{"character_id": "hero"}]}, 1)
	session.resolve_ally_action({"type": "attack"})
	assert_true(session.battle.battle_over)
	var turns_at_end := session.reachable_turns()
	session.resolve_ally_action({"type": "attack"})  # a no-op once battle_over -- resolve_pending_ally_action() itself early-returns
	assert_eq(session.reachable_turns(), turns_at_end, "no new snapshot is recorded once the battle is over")

# ---------------------------------------------------------------------------
# REWIND
# ---------------------------------------------------------------------------

func test_rewind_to_an_earlier_turn_restores_that_turns_start_state() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	# defending only halves the boss's damage, it doesn't zero it -- the sole
	# ally's own HP still drops turn over turn as the boss keeps attacking.
	var ally_hp_at_turn_1 := session.battle.party[0].hp
	for i in range(5):
		session.resolve_ally_action({"type": "defend"})
	assert_ne(session.battle.party[0].hp, ally_hp_at_turn_1, "sanity: HP actually changed over 5 turns")

	assert_true(session.rewind_to(1))
	assert_eq(session.battle.current_turn, 1)
	assert_eq(session.battle.party[0].hp, ally_hp_at_turn_1)

func test_rewind_to_an_unreached_turn_fails_and_changes_nothing() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns(), [1, 2])
	assert_false(session.rewind_to(9))
	assert_eq(session.battle.current_turn, 2, "a failed rewind must not mutate the live battle")

func test_rewind_discards_future_history_not_past_history() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	for i in range(7):
		session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns(), [1, 2, 3, 4, 5, 6, 7, 8])

	assert_true(session.rewind_to(3))
	assert_eq(session.reachable_turns(), [1, 2, 3], "turns 4-8 must be discarded; turns 1-2 must remain")

func test_advancing_after_a_rewind_records_a_new_single_timeline_not_a_branch() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	for i in range(7):
		session.resolve_ally_action({"type": "defend"})
	session.rewind_to(3)
	assert_eq(session.reachable_turns(), [1, 2, 3])

	session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns(), [1, 2, 3, 4], "advancing after a rewind appends the new turn 4 -- there is exactly one timeline")
	# the newly recorded turn-4 snapshot reflects state reached via the
	# rewound path, not any trace of the discarded original turns 4-8.
	assert_eq(session.battle.current_turn, 4)

## 実機プレイ改善①: resolve_ally_action()はActionログの配列そのものを
## 返す（旧resolve_turn()の{"log":...,"turn":...}という辞書ラッパーは無い）。
func test_rewound_then_replayed_battle_reproduces_the_same_rng_results() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	var first_run: Array = []
	for i in range(6):
		var log := session.resolve_ally_action({"type": "defend"})
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				first_run.append(entry.duplicate(true))

	assert_true(session.rewind_to(1))
	var second_run: Array = []
	for i in range(6):
		var log := session.resolve_ally_action({"type": "defend"})
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				second_run.append(entry.duplicate(true))

	assert_eq(first_run, second_run, "same rewound-to turn + same inputs must reproduce identical RNG-driven results")

func test_many_rewinds_do_not_corrupt_the_session() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	for cycle in range(20):
		for i in range(3):
			session.resolve_ally_action({"type": "defend"})
		var count := session.reachable_turns().size()
		assert_true(session.rewind_to(1), "cycle %d: rewinding to turn 1 must always succeed" % cycle)
		assert_eq(session.reachable_turns(), [1])
		assert_eq(session.battle.current_turn, 1)
		assert_true(count >= 1)
	assert_eq(session.reachable_turns(), [1])

# ---------------------------------------------------------------------------
# Round 5-2: REWIND Turnスナップショットがそのターンの「絶対的な開始」（何も
# 処理されていない純粋な境界）へ戻ることの end-to-end 確認。RBMCreatorTestSession
# はTEST BATTLE/Clear Checkの両方が無改修で共有するクラス（このファイル冒頭
# コメント参照）——ここで通す確認はそのまま両モードに適用される。
# Turn境界そのもの・逐次カーソルの直接検証はtest_rbm_battle_rewind_boundary.gd
# （RBMBattleをセッション層を経由せず直接駆動）で行う。
# ---------------------------------------------------------------------------

## §4: セッション構築の時点で既にturn_start_interrupt（奇襲）が1回発火して
## いる（advance()が自動でそこまで進めるため）。session.rewind_to()は
## restore()の直後に自身の内部advance()で次の決定点まで再進行する設計
## （UIから見て"REWINDボタンを押したら次の入力可能状態が即座に見える"ため）
## ——よって「restoreした直後の、まだ何も再処理していない中間状態」自体は
## セッション層からは観測できない（それはRBMBattle.restore()単体の責務で、
## test_rbm_battle_rewind_boundary.gdがログentry数による直接カウントも含めて
## 別途確認済み）。ここではEnd-to-endの結果——REWIND後は必ず「奇襲が
## ちょうど1回再適用された直後」の状態に戻ることを、複数回のREWINDサイクル
## （毎回、間に別の行動でHPをその値から意図的にずらしてから戻す）で確認する
## ——単に同じ呼び出しを繰り返すだけでは「たまたま同じ値になった」可能性を
## 排除できないため、サイクルごとに実際に状態を動かしてから正確に戻ることを
## 示す。
func test_session_rewind_repeatedly_undoes_and_refires_turn_start_interrupt_damage() -> void:
	var session := RBMCreatorTestSession.new(_definition_with(_boss_with_turn_start_ambush()), 1)
	var hero: RBMUnit = session.battle.party[0]
	var hp_at_true_start := hero.max_hp

	assert_lt(hero.hp, hp_at_true_start, "sanity: the turn_start_interrupt already fired once during session construction")
	var ambush_damage := hp_at_true_start - hero.hp
	assert_eq(ambush_damage, 100, "sanity: the ambush actually dealt its expected 100 damage (atk 50 x multiplier 2.0)")
	var hp_after_ambush := hero.hp

	for cycle in range(3):
		# hero (faster) acts, which lets the boss's own NORMAL ACTION PHASE
		# turn fire too (the ambush is a separate, turn_start-only interrupt)
		# -- moving HP further away from hp_after_ambush, so the next rewind's
		# return to EXACTLY hp_after_ambush is a genuine, non-trivial round trip.
		assert_true(session.is_waiting_for_ally_action(), "cycle %d sanity: hero must be pending before acting" % cycle)
		session.resolve_ally_action({"type": "attack"})
		assert_ne(hero.hp, hp_after_ambush, "cycle %d sanity: further play must have moved HP away from the post-ambush value" % cycle)

		assert_true(session.rewind_to(1), "cycle %d: rewind to turn 1 must succeed" % cycle)
		assert_eq(hero.hp, hp_after_ambush, "cycle %d: REWIND must land back at exactly the state right after the turn_start_interrupt re-fires -- the SAME amount every cycle, never accumulated or dropped" % cycle)

## §5: ボスが味方より速いケースのREWIND。TEST BATTLE/Clear Check双方が使う
## このセッションクラスを通して、先行するボスの行動そのものが正しく
## 巻き戻り・再現することを確認する。spdはBOSS_SPD_MAX(500、
## rbm_definition_loader.gd)を超えない値にする——999はDefinition
## validationで拒否される。
func test_session_rewind_undoes_a_faster_bosss_pre_ally_action_and_replay_reproduces_it() -> void:
	var boss := _random_candidate_boss()
	boss["spd"] = 500  # BOSS_SPD_MAX -- far faster than hero (spd100)
	var session := RBMCreatorTestSession.new(_definition_with(boss), 1)
	assert_true(session.start_ok(), "sanity: spd=500 (BOSS_SPD_MAX) must still be a valid Definition")
	var hero: RBMUnit = session.battle.party[0]

	assert_true(session.is_waiting_for_ally_action(), "sanity: hero must be pending, AFTER the faster boss's own pre-ally Turn 1 action")
	assert_lt(hero.hp, hero.max_hp, "sanity: the faster boss really did act before hero was ever prompted")
	var hp_after_boss_hit := hero.hp

	assert_true(session.rewind_to(1))
	assert_true(session.is_waiting_for_ally_action(), "rewind_to() must re-advance internally to the next decision point, same as a fresh session construction does")
	assert_eq(hero.hp, hp_after_boss_hit, "replaying from the restored boundary must reproduce the SAME boss action/damage")

## §6: 逐次カーソル。REWIND後に行動済みキャラの二重行動なし・キャラを
## 飛ばさない・ボスが余分に行動しない・pending allyが正しい・SPD順が正しく
## 再現されることを、多人数パーティで直接確認する。
## round_cursor()/round_turn_start_fired()という新設の読み取り専用クエリの
## 「REWIND直後は0/falseに戻る」という主張自体は、session.rewind_to()が
## restore()の直後に自身の内部advance()で次の決定点まで再進行してしまう
## ため（§4のコメント参照）、このセッション層からは直接観測できない——
## test_rbm_battle_rewind_boundary.gdがRBMBattleを直接駆動してこれを検証
## 済み。ここでは、その2つのクエリを実際に駆動する"結果"（二重行動なし・
## スキップなし・ボスの余分な行動なし・pending allyの順序が完全に一致）を
## end-to-endで確認する。
func test_session_rewind_reproduces_the_exact_ally_prompt_sequence_with_no_doubles_no_skips_and_no_extra_boss_actions() -> void:
	var session := RBMCreatorTestSession.new(_definition(4), 1)  # hero/butler/healer/samurai, all faster than the boss (spd10)
	var start_turn := session.battle.current_turn

	var prompted_first: Array = []
	var boss_actions_first := 0
	while session.battle.current_turn == start_turn and session.is_waiting_for_ally_action():
		prompted_first.append(session.pending_ally_id())
		var log := session.resolve_ally_action({"type": "attack"})
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				boss_actions_first += 1
	assert_eq(prompted_first.size(), 4, "sanity: all 4 allies must have been prompted exactly once in the original run")
	assert_eq(boss_actions_first, 1, "sanity: the boss must have acted exactly once in the original run")
	assert_eq(session.battle.current_turn, 2, "sanity: the round completed and advanced")

	assert_true(session.rewind_to(1))

	var prompted_second: Array = []
	var boss_actions_second := 0
	while session.battle.current_turn == 1 and session.is_waiting_for_ally_action():
		prompted_second.append(session.pending_ally_id())
		var log := session.resolve_ally_action({"type": "attack"})
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				boss_actions_second += 1
	assert_eq(prompted_second, prompted_first, "the exact same ally prompt sequence must reproduce after REWIND -- no doubled actions, no skipped characters, same SPD order")
	assert_eq(boss_actions_second, 1, "the boss must act exactly once again -- not zero (skipped) and not twice (duplicated)")
	assert_eq(session.battle.current_turn, 2, "the round must complete and advance identically to the original run")

# ---------------------------------------------------------------------------
# Round 5-3 (Codex再レビュー指摘対応): 上記のRound 5-2テスト群は、いずれも
# 「REWIND後、LIVEなbattleを再進行させた"結果"」を通してのみsnapshotタイミング
# の正しさを間接的に検証していた——RBMCreatorTestSession自身がhistoryへ実際に
# 保存したDictionaryの中身そのものを直接検査するテストが欠けていた、という
# 指摘への対応。
##
## ここでは手動でRBMBattle.snapshot()を呼んで作った参照用snapshotとは一切
## 比較しない——session.history[0]（RBMCreatorTestSessionが通常の構築フロー
## の中で自動的に保存した、正真正銘のTurn 1エントリ）を直接読み、その中身
## 自体が「そのTurnの処理が一切始まっていない、真の開始状態」を保持している
## ことをassertする。本番コードは一切変更していない（rbm_battle.gd/
## rbm_creator_test_session.gdとも無改修）——テストのみの追加。
# ---------------------------------------------------------------------------

## §2: turn_start_interruptケース。LIVEなbattleは既に奇襲の100ダメージを
## 反映済み（HP550）だが、session.history[0]自身は"interrupt発火前のHP650"を
## 保持していなければならない——「REWINDした後に最終的にHP550になった」と
## いう間接的な確認では捉えられない、session自身が保存したデータそのものの
## 正しさを直接証明する。
func test_session_history_turn_1_entry_directly_holds_hp_from_before_the_turn_start_interrupt_fired() -> void:
	var session := RBMCreatorTestSession.new(_definition_with(_boss_with_turn_start_ambush()), 1)
	var hero: RBMUnit = session.battle.party[0]
	var hero_unit_key := str(hero.id)

	# sanity: hero's own true starting HP, and the LIVE battle's current HP
	# (already post-interrupt, since session construction's automatic advance()
	# already ran the turn_start_interrupt once).
	assert_eq(hero.max_hp, 650, "sanity: hero's own max_hp is exactly 650")
	assert_eq(hero.hp, 550, "sanity: the LIVE battle already reflects the turn_start_interrupt's 100 damage (650 - 100)")

	# the session's OWN automatically-saved Turn 1 history entry -- read
	# directly, never re-derived via a manual RBMBattle.snapshot() call.
	assert_eq(session.history.size(), 1, "sanity: exactly one Turn (Turn 1) has been reached so far")
	var turn1_entry: Dictionary = session.history[0]
	var saved_hero_hp := int(turn1_entry["units"][hero_unit_key]["hp"])

	assert_eq(saved_hero_hp, 650, "session.history[0] itself must hold hero's HP from BEFORE the turn_start_interrupt fired (650) -- not the post-interrupt value (550) the live battle currently shows")
	assert_eq(int(turn1_entry["round_cursor"]), 0, "session.history[0] itself must have round_cursor == 0 -- nothing in Turn 1 has been processed yet")
	assert_false(bool(turn1_entry["round_turn_start_fired"]), "session.history[0] itself must have round_turn_start_fired == false -- the turn_start_interrupt has not been processed from this saved entry's own perspective")
	assert_eq(int(turn1_entry["current_turn"]), 1, "session.history[0] itself must record current_turn == 1")
	assert_false(bool(turn1_entry["battle_over"]), "session.history[0] itself must record battle_over == false")

## §3: 高速ボスケース（ボスSPD > 味方SPD）。LIVEなbattleは既にボスの先制
## 攻撃を反映済みだが、session.history[0]自身は"ボスが行動する前のHP"を
## 保持していなければならない——「高速ボスが行動した後の状態をTurn 1
## snapshotとして保存していない」ことを直接保証する。
func test_session_history_turn_1_entry_directly_holds_hp_from_before_a_faster_bosss_pre_ally_action() -> void:
	var boss := _random_candidate_boss()
	# hero's own spd is 100 (data_bossmaker/allies/hero.json) -- set the boss
	# strictly higher, at BOSS_SPD_MAX (500), matching Round 5-2's own
	# established, already-passing fixture for this exact scenario.
	boss["spd"] = 500
	var session := RBMCreatorTestSession.new(_definition_with(boss), 1)
	assert_true(session.start_ok(), "sanity: spd=500 (BOSS_SPD_MAX) must still be a valid Definition")
	var hero: RBMUnit = session.battle.party[0]
	var hero_unit_key := str(hero.id)
	var hero_max_hp := hero.max_hp

	# sanity: the LIVE battle, after session construction's automatic advance,
	# already reflects the faster boss's own pre-ally Turn 1 action.
	assert_true(session.is_waiting_for_ally_action(), "sanity: hero must be pending, AFTER the faster boss's own pre-ally Turn 1 action")
	assert_lt(hero.hp, hero_max_hp, "sanity: the LIVE battle already reflects the boss's attack (HP below max)")

	# the session's OWN automatically-saved Turn 1 history entry -- read
	# directly, never re-derived via a manual RBMBattle.snapshot() call.
	assert_eq(session.history.size(), 1, "sanity: exactly one Turn (Turn 1) has been reached so far")
	var turn1_entry: Dictionary = session.history[0]
	var saved_hero_hp := int(turn1_entry["units"][hero_unit_key]["hp"])

	assert_eq(saved_hero_hp, hero_max_hp, "session.history[0] itself must hold hero's FULL, pre-attack HP -- the faster boss's pre-ally action must NOT already be baked into the Turn 1 snapshot")
	assert_eq(int(turn1_entry["round_cursor"]), 0, "session.history[0] itself must have round_cursor == 0 -- nothing in Turn 1 has been processed yet, not even the boss's own faster action")
	assert_false(bool(turn1_entry["round_turn_start_fired"]), "session.history[0] itself must have round_turn_start_fired == false")
	assert_eq(int(turn1_entry["current_turn"]), 1)
	assert_false(bool(turn1_entry["battle_over"]))

# ---------------------------------------------------------------------------
# restart ("もう一度テスト")
# ---------------------------------------------------------------------------

func test_restart_produces_a_fresh_battle_and_resets_history() -> void:
	var session := RBMCreatorTestSession.new(_definition(), 1)
	for i in range(4):
		session.resolve_ally_action({"type": "defend"})
	assert_eq(session.reachable_turns().size(), 5)

	session.restart()
	assert_true(session.start_ok())
	assert_eq(session.reachable_turns(), [1])
	assert_eq(session.battle.current_turn, 1)
	assert_eq(session.battle.boss.hp, session.battle.boss.max_hp)
