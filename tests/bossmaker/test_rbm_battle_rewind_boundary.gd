extends GutTest

## RPG BOSS MAKER — 実機プレイ改善① Round 5-2「REWIND Turnスナップショット」
## 回帰テスト。RBMBattle.snapshot()/restore()を、新しい逐次戦闘API
## （advance_to_next_decision()/resolve_pending_ally_action()）で駆動した
## 状態に対して直接exerciseする——test_rbm_battle_snapshot.gdは旧resolve_turn()
## （一括API）だけを対象としており、このファイルが検証する「Turn境界の
## snapshotタイミング」バグ（Codex指摘）は再現できない。
##
## Codexが指摘したバグ: 従来はsnapshot()を「advance_to_next_decision()が
## 生存する味方の入力を求めるまで自動解決した"後"」に取得していたため、
## turn_start_interruptやそのTurnより速いボスの先制行動が既に適用された
## 状態がsnapshotされていた——REWINDしても「そのTurnの絶対的な開始」には
## 戻れなかった。RBMBattle.is_at_fresh_turn_boundary()（新設）と
## advance_to_next_decision(stop_before_turn_processing=true)（新設）が、
## この境界を呼び出し側から正しく検出・snapshot()できるようにする。
##
## このファイルはRBMBattleを直接（セッション層を経由せず）駆動し、
## round_cursor()/round_turn_start_fired()という新設の読み取り専用クエリで
## 逐次カーソル状態そのものを直接検証する。セッション層（RBMCreatorTestSession.
## rewind_to()、TEST BATTLE/Clear Checkが共有）を通した end-to-end の確認は
## test_rbm_creator_test_session.gdに追加した。

func _single_target_boss(atk: int, spd: int, hp: int = 100000) -> Dictionary:
	return {
		"id": "boundary_boss", "display_name": "境界確認ボス", "hp": hp, "atk": atk, "spd": spd,
		"skills": [
			{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [{"skill_id": "boss_hit", "weight": 1}],
	}

## turn_start_interruptで即座にダメージを与える「奇襲」を持つ、最も遅い
## （SPD最低）ボス——通常攻撃フェーズより前に何が起きたかを、味方のSPDに
## 関わらず明確に分離して観測できる。
func _boss_with_turn_start_ambush() -> Dictionary:
	var boss := _single_target_boss(10, 1)
	boss["skills"].append({"id": "ambush", "display_name": "Ambush", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 10.0})
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "ambush", "timing": "turn_start_interrupt", "order": 0}]
	return boss

func _party_defs(count: int = 5) -> Array[Dictionary]:
	var ids := ["hero", "butler", "healer", "samurai", "tank"]
	var out: Array[Dictionary] = []
	for i in range(count):
		out.append(RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % ids[i]))
	return out

const ATTACK := {"type": "attack"}

# ---------------------------------------------------------------------------
# 3/4. is_at_fresh_turn_boundary()の時点でsnapshot()すれば、turn_start_
# interruptより前へ戻れる。単なる最終HP一致ではなく、実際に「Turn 1の
# turn_start_interruptが初回1回・REWIND後の再実行でもう1回」発火したことを
# ログのentry数で直接確認する。
# ---------------------------------------------------------------------------

func test_snapshot_at_fresh_turn_boundary_captures_state_before_turn_start_interrupt_fires() -> void:
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _boss_with_turn_start_ambush(), 1)
	var hero: RBMUnit = battle.party[0]
	var hp_at_true_start := hero.hp

	assert_true(battle.is_at_fresh_turn_boundary(), "sanity: a brand-new battle sits exactly at Turn 1's true, unprocessed start")
	assert_eq(battle.round_cursor(), 0)
	assert_false(battle.round_turn_start_fired())
	var snap := battle.snapshot()

	battle.advance_to_next_decision()  # turn_start_interrupt (ambush) fires, then hero becomes pending
	assert_true(battle.is_waiting_for_ally_action(), "sanity: hero must now be pending")
	assert_lt(hero.hp, hp_at_true_start, "sanity: the ambush actually dealt damage")
	var hp_after_ambush := hero.hp

	battle.restore(snap)
	assert_eq(hero.hp, hp_at_true_start, "restoring the pristine-boundary snapshot must undo the ambush's damage entirely -- it must not have already applied")
	assert_true(battle.is_at_fresh_turn_boundary(), "restore must land exactly back at the pristine boundary, not mid-processing")
	assert_eq(battle.round_cursor(), 0, "restore must reset the cursor to exactly 0")
	assert_false(battle.round_turn_start_fired(), "restore must reset turn_start_fired to false")
	assert_false(battle.is_waiting_for_ally_action(), "nobody may be pending yet -- turn_start hasn't even been processed from this restored state")

	battle.advance_to_next_decision()  # re-process from the pristine boundary
	assert_eq(hero.hp, hp_after_ambush, "re-advancing from the restored pristine boundary must re-apply the SAME turn_start_interrupt damage")

func test_turn_start_interrupt_fires_exactly_once_per_run_verified_by_log_entry_count_not_merely_final_hp() -> void:
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _boss_with_turn_start_ambush(), 1)
	var snap := battle.snapshot()

	var first_log := battle.advance_to_next_decision()
	var first_count := 0
	for entry in first_log:
		if str(entry.get("actor", "")) == "boss" and str(entry.get("skill_id", "")) == "ambush":
			first_count += 1
	assert_eq(first_count, 1, "the turn_start_interrupt must fire exactly once on the original run (not zero, not merged/duplicated)")

	battle.restore(snap)
	var second_log := battle.advance_to_next_decision()
	var second_count := 0
	for entry in second_log:
		if str(entry.get("actor", "")) == "boss" and str(entry.get("skill_id", "")) == "ambush":
			second_count += 1
	assert_eq(second_count, 1, "the turn_start_interrupt must fire exactly once again after REWIND -- neither dropped nor duplicated")

# ---------------------------------------------------------------------------
# 5. 先行ボス行動REWIND: ボスが味方より速いケース。
# ---------------------------------------------------------------------------

func test_rewinding_to_turn_1_undoes_a_faster_bosss_pre_ally_action_and_replay_reproduces_it() -> void:
	# boss spd 999 (fastest overall) vs hero spd 100 -- the boss always acts
	# BEFORE hero's own Turn 1 slot is ever reached.
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _single_target_boss(100, 999), 1)
	var hero: RBMUnit = battle.party[0]
	var hp_at_true_start := hero.hp
	assert_true(battle.is_at_fresh_turn_boundary())
	var snap := battle.snapshot()

	battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action(), "sanity: hero must now be pending, AFTER the boss's own pre-emptive hit")
	assert_lt(hero.hp, hp_at_true_start, "sanity: the boss's faster action already landed before hero was ever prompted")
	var hp_after_boss_hit := hero.hp

	battle.restore(snap)
	assert_eq(hero.hp, hp_at_true_start, "REWIND must undo the boss's pre-ally action entirely -- hero must be back to full HP")
	assert_false(battle.is_waiting_for_ally_action(), "nobody may be pending yet -- the boss hasn't acted from this restored state's perspective")

	battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action())
	assert_eq(hero.hp, hp_after_boss_hit, "replaying from the restored boundary must reproduce the SAME boss action/damage under the same RNG state")

# ---------------------------------------------------------------------------
# 6. 逐次カーソル: REWIND後に二重行動なし・スキップなし・ボスの余分な行動
# なし・pending allyが正しい・SPD順が正しく再現される（多人数パーティ）。
# ---------------------------------------------------------------------------

func test_round_cursor_and_pending_ally_are_exactly_reproduced_after_a_rewind_with_a_multi_ally_party() -> void:
	# tank140 > butler120 > boss115 > healer110 > hero100 > samurai70
	var battle := RBMBattle.new(_party_defs(), _single_target_boss(1, 115), 1)
	var snap := battle.snapshot()
	assert_eq(battle.round_cursor(), 0)
	assert_false(battle.round_turn_start_fired())

	# drive the round partway (tank, then butler) before rewinding, so the
	# cursor genuinely has somewhere non-zero to reset FROM.
	battle.advance_to_next_decision()
	assert_eq(battle.pending_ally_id(), 4, "sanity: tank (fastest) first")
	battle.resolve_pending_ally_action(ATTACK)
	battle.advance_to_next_decision()
	assert_eq(battle.pending_ally_id(), 1, "sanity: butler next")
	assert_gt(battle.round_cursor(), 0, "sanity: the cursor really did advance before the rewind")

	battle.restore(snap)
	assert_eq(battle.round_cursor(), 0, "REWIND must reset the sequential cursor to exactly 0 -- the pristine start of the round")
	assert_false(battle.round_turn_start_fired(), "REWIND must reset turn_start_fired to false -- nothing processed yet")
	assert_false(battle.is_waiting_for_ally_action())

	# replay the WHOLE round from the restored boundary and confirm every
	# ally is prompted exactly once, in the exact same SPD order, with no
	# doubles, no skips, and the boss acting exactly once (not zero, not
	# twice).
	var prompted: Array = []
	var boss_action_count := 0
	while true:
		var log := battle.advance_to_next_decision()
		for entry in log:
			if str(entry.get("actor", "")) == "boss":
				boss_action_count += 1
		if battle.battle_over or battle.current_turn != 1:
			break
		if not battle.is_waiting_for_ally_action():
			break
		prompted.append(battle.pending_ally_id())
		battle.resolve_pending_ally_action(ATTACK)
	assert_eq(prompted, [4, 1, 2, 0, 3], "every ally must be prompted exactly once, in the exact SPD order (tank,butler,healer,hero,samurai), after a REWIND to the round's true start -- no doubled actions, no skipped characters")
	assert_eq(boss_action_count, 1, "the boss must act exactly once across the replayed round -- not zero (skipped) and not twice (duplicated)")
	assert_eq(battle.current_turn, 2, "the round must complete normally and advance to Turn 2 after the replay")

# ---------------------------------------------------------------------------
# 7. RNG: 同じsnapshot RNG stateから再開する既存仕様の維持を、この境界修正
# 後の新しいsnapshotタイミングに対しても直接確認する（ランダム候補を持つ
# ボスで、対象選択も含めて完全に再現されること）。
# ---------------------------------------------------------------------------

func _boss_with_random_candidates(spd: int = 999) -> Dictionary:
	return {
		"id": "boundary_rng_boss", "display_name": "境界RNGボス", "hp": 100000, "atk": 30, "spd": spd,
		"skills": [
			{"id": "hit_a", "display_name": "A", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "hit_b", "display_name": "B", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [
			{"skill_id": "hit_a", "weight": 50},
			{"skill_id": "hit_b", "weight": 50},
		],
	}

func test_rng_reproduces_boss_skill_pick_and_target_after_a_rewind_at_the_fresh_turn_boundary() -> void:
	# boss (fastest, spd999) acts before ANY ally this round -- both its skill
	# pick (hit_a/hit_b) and its random single-target choice consume RNG
	# before the fresh-turn-boundary snapshot's replay point.
	var battle := RBMBattle.new(_party_defs(3), _boss_with_random_candidates(), 7)
	var snap := battle.snapshot()

	battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action(), "sanity: control reached an ally after the boss's own Turn 1 pick")

	var first_hps: Array = []
	for unit in battle.party:
		first_hps.append(unit.hp)

	battle.restore(snap)
	assert_true(battle.is_at_fresh_turn_boundary())
	battle.advance_to_next_decision()

	var second_hps: Array = []
	for unit in battle.party:
		second_hps.append(unit.hp)
	assert_eq(first_hps, second_hps, "REWIND to the fresh turn boundary + replay must reproduce the exact same RNG-driven skill pick AND random target selection")
