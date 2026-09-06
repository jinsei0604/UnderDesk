extends GutTest

## RPG BOSS MAKER — 実機プレイ改善① 戦闘方式変更（SPD順に1体ずつ、即座に
## 解決する新方式）。RBMBattle.advance_to_next_decision()/
## resolve_pending_ally_action()/is_waiting_for_ally_action()/pending_ally_id()
## を直接exerciseする（UI層は別ファイルで検証）。
##
## resolve_turn()（旧・一括解決API）自体は今回のラウンドで一切変更していない
## ため、既存のtest_rbm_battle.gd/test_rbm_battle_snapshot.gd等はそのまま
## 無改修で全件パスし続ける——このファイルは新APIだけを対象とする、追加の
## テストファイル。

func _party_defs(count: int = 5) -> Array[Dictionary]:
	# hero(spd100)/butler(spd120)/healer(spd110)/samurai(spd70)/tank(spd140,SP無し)
	var ids := ["hero", "butler", "healer", "samurai", "tank"]
	var out: Array[Dictionary] = []
	for i in range(count):
		out.append(RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % ids[i]))
	return out

## SPDを自由に指定できる、単体ランダム対象への通常攻撃だけを持つボス。
func _single_target_boss(atk: int, spd: int, hp: int = 100000) -> Dictionary:
	return {
		"id": "seq_boss", "display_name": "順番確認ボス", "hp": hp, "atk": atk, "spd": spd,
		"skills": [
			{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [{"skill_id": "boss_hit", "weight": 1}],
	}

## 全体攻撃だけを持つボス（全滅テスト用）。
func _aoe_boss(atk: int, spd: int, hp: int = 100000) -> Dictionary:
	return {
		"id": "seq_aoe_boss", "display_name": "全体攻撃ボス", "hp": hp, "atk": atk, "spd": spd,
		"skills": [
			{"id": "boss_aoe", "display_name": "AoE", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [{"skill_id": "boss_aoe", "weight": 1}],
	}

## 2つの重み付き候補＋ランダム単体対象を持つボス（RNG決定論性テスト用、
## 実測でRNGを実際に消費する形）。
func _boss_with_random_candidates(spd: int = 50) -> Dictionary:
	return {
		"id": "seq_rng_boss", "display_name": "RNGボス", "hp": 5000, "atk": 30, "spd": spd,
		"skills": [
			{"id": "hit_a", "display_name": "A", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
			{"id": "hit_b", "display_name": "B", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		],
		"normal_action_candidates": [
			{"skill_id": "hit_a", "weight": 50},
			{"skill_id": "hit_b", "weight": 50},
		],
	}

const ATTACK := {"type": "attack"}
const DEFEND := {"type": "defend"}

## advance_to_next_decision()を繰り返し呼び、生存している味方の番になる
## たびにactionで即座に応答し続ける——「start_turnのラウンドが完全に終わる
## （current_turnがstart_turnから変わる）か、battle_overになるまで」だけを
## 対象とする。
##
## 単純に「while current_turn == start_turn」をループの先頭だけでチェック
## すると壊れる——advance_to_next_decision()の1回の呼び出しは、現在の
## ラウンドを完了させ、かつ続けて次ラウンドのturn_start指定行動→最初の
## 味方の番まで一気に進めてから戻ってくることがある（次ラウンドの最初の
## 味方は「入力待ち」として観測されるが、その時点でcurrent_turnは既に
## 変わっている）。そのため、各呼び出しの直後に毎回current_turnを再確認する
## 必要がある——実際にこのバグを一度実装し、テストが「1ラウンドのはずが
## 6人分行動した」という形で失敗するのを確認してから、この形へ修正した。
## Returns {"prompted": Array of ally ids actually prompted this round (in
## order), "log": Array of every log entry produced along the way, in order
## (auto-resolved boss/interrupt entries AND each ally's own action)} so a
## caller can inspect EXACTLY what happened this round, not just who acted.
func _play_round(battle: RBMBattle, start_turn: int, action: Dictionary = ATTACK) -> Dictionary:
	var prompted_ids: Array = []
	var log: Array = []
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn:
			return {"prompted": prompted_ids, "log": log}
		if not battle.is_waiting_for_ally_action():
			return {"prompted": prompted_ids, "log": log}
		prompted_ids.append(battle.pending_ally_id())
		log.append_array(battle.resolve_pending_ally_action(action))
	return {"prompted": prompted_ids, "log": log}  # 到達しない（while true内で必ずreturnする）

# ---------------------------------------------------------------------------
# 1. SPD順が味方＋ボスを横断して正しい
# ---------------------------------------------------------------------------

func test_spd_order_crosses_allies_and_boss_correctly() -> void:
	# tank140 > butler120 > boss115 > healer110 > hero100 > samurai70
	var battle := RBMBattle.new(_party_defs(), _single_target_boss(1, 115), 1)
	var observed_order: Array = []
	for id in _play_round(battle, 1)["prompted"]:
		observed_order.append("ally:%d" % id)
	# turn_order itself is the single source of truth for the intended
	# SPD-crossing sequence (already covered elsewhere); here we confirm the
	# ALLY portion of the observed sequence exactly matches turn_order's own
	# ally entries in the same relative order, and that the boss's slot sits
	# between butler and healer as expected (spd 115 between 120 and 110).
	var expected_ally_order: Array = []
	for token in battle.turn_order:
		if token != "boss":
			expected_ally_order.append(token)
	assert_eq(observed_order, expected_ally_order, "the sequence of ally-input prompts must exactly match turn_order's own ally ordering")
	assert_eq(battle.turn_order, ["ally:4", "ally:1", "boss", "ally:2", "ally:0", "ally:3"], "sanity: boss (spd115) must sit between butler(120) and healer(110)")

# ---------------------------------------------------------------------------
# 2/3/4. 最速味方の入力直後にその味方だけ行動する→次がボスなら即行動→次の味方へ
# ---------------------------------------------------------------------------

func test_fastest_ally_acts_alone_first_and_boss_auto_resolves_before_the_next_ally() -> void:
	# boss spd=125: sits between tank(140) and butler(120) -- i.e. immediately
	# after the single fastest ally (tank).
	var battle := RBMBattle.new(_party_defs(), _single_target_boss(50, 125), 1)
	assert_eq(battle.turn_order[0], "ally:4", "sanity: tank (spd140) is the fastest overall")
	assert_eq(battle.turn_order[1], "boss", "sanity: boss (spd125) is immediately after tank")

	var log := battle.advance_to_next_decision()
	assert_true(log.is_empty(), "nothing should auto-resolve before the very first (fastest) living ally's turn")
	assert_true(battle.is_waiting_for_ally_action())
	assert_eq(battle.pending_ally_id(), 4, "tank (fastest) must be the first to be asked for a command")

	# resolve ONLY tank's action -- nobody else must have acted yet.
	var tank_log := battle.resolve_pending_ally_action(ATTACK)
	assert_eq(tank_log.size(), 1)
	assert_eq(int(tank_log[0]["actor"]), 4, "only tank's own action must be logged by this single call")

	# The next call must auto-resolve the boss's own turn (no input needed)
	# and then stop again at the NEXT living ally in SPD order (butler).
	var boss_log := battle.advance_to_next_decision()
	assert_eq(boss_log.size(), 1, "the boss's turn must auto-resolve immediately, with no input requested, in the very next call")
	assert_eq(str(boss_log[0]["actor"]), "boss")
	assert_true(battle.is_waiting_for_ally_action())
	assert_eq(battle.pending_ally_id(), 1, "control must move to butler (spd120), the next-fastest ally, right after the boss's auto-resolved turn")

# ---------------------------------------------------------------------------
# 5/6. 全員が1回行動するとTurnが進む／「行動開始」操作は一切不要
# ---------------------------------------------------------------------------

func test_a_full_round_of_only_per_unit_calls_advances_the_turn_with_no_batch_submit_step() -> void:
	var battle := RBMBattle.new(_party_defs(), _single_target_boss(1, 105), 99)
	assert_eq(battle.current_turn, 1)
	# The entire round is driven purely by "wait for an ally, hand it exactly
	# ONE action, repeat" -- there is no Dictionary of all 5 party members'
	# actions ever assembled anywhere, and no single "submit" call.
	var prompted: Array = _play_round(battle, 1)["prompted"]
	assert_eq(prompted.size(), 5, "every one of the 5 living party members must have been asked for exactly one command this round")
	assert_eq(battle.current_turn, 2, "the turn must have advanced to 2 once every participant acted once")

# ---------------------------------------------------------------------------
# 7. 行動前に戦闘不能になった味方はスキップ
# ---------------------------------------------------------------------------

func test_an_ally_downed_before_their_own_turn_order_slot_is_silently_skipped() -> void:
	var battle := RBMBattle.new(_party_defs(), _single_target_boss(1, 200), 1)
	# samurai (id 3, spd70) is the SLOWEST -- down them right now, before the
	# round even starts, so their slot is reached only after everyone else.
	battle.party[3].hp = 0
	assert_true(battle.party[3].is_downed())

	var prompted_ids: Array = _play_round(battle, 1)["prompted"]

	assert_false(prompted_ids.has(3), "the already-downed samurai must never be prompted for a command")
	assert_eq(prompted_ids.size(), 4, "the 4 OTHER living party members must still each get exactly one prompt")
	assert_eq(battle.current_turn, 2, "the round must still complete and the turn must still advance, skipping the downed unit's slot entirely")

# ---------------------------------------------------------------------------
# 8/9. 途中でボス撃破／全滅なら後続行動なし
# ---------------------------------------------------------------------------

func test_defeating_the_boss_mid_round_stops_all_further_actors() -> void:
	# boss has only 1 HP and the fastest ally (tank) goes first -- tank's own
	# attack alone must end the battle before anyone else (including the
	# boss) ever gets a turn.
	var boss := _single_target_boss(1, 130, 1)
	var battle := RBMBattle.new(_party_defs(), boss, 1)
	assert_eq(battle.turn_order[0], "ally:4", "sanity: tank acts first")

	battle.advance_to_next_decision()
	assert_true(battle.is_waiting_for_ally_action())
	assert_eq(battle.pending_ally_id(), 4)
	battle.resolve_pending_ally_action(ATTACK)

	assert_true(battle.battle_over, "the boss's 1 HP must not have survived tank's attack")
	assert_eq(battle.winner, "ally")

	# nothing further must ever happen again -- no more prompts, no more log
	# entries, regardless of how many times these are called.
	assert_false(battle.is_waiting_for_ally_action())
	assert_eq(battle.pending_ally_id(), -1)
	var further_log := battle.advance_to_next_decision()
	assert_true(further_log.is_empty(), "calling advance_to_next_decision() again after victory must be a pure no-op")
	var further_action_log := battle.resolve_pending_ally_action(ATTACK)
	assert_true(further_action_log.is_empty(), "calling resolve_pending_ally_action() again after victory must be a pure no-op")

func test_party_wipe_mid_round_stops_all_further_actors() -> void:
	# a fast, lethal AoE boss (spd999) wipes the whole party before ANY ally
	# ever gets a turn this round.
	var battle := RBMBattle.new(_party_defs(), _aoe_boss(100000, 999), 1)
	assert_eq(battle.turn_order[0], "boss", "sanity: the boss is fastest")

	var log := battle.advance_to_next_decision()
	assert_true(battle.battle_over, "a lethal AoE must end the battle immediately, before any ally is ever prompted")
	assert_eq(battle.winner, "boss")
	assert_false(battle.is_waiting_for_ally_action(), "no ally must ever have been prompted -- the whole party was already wiped")
	assert_true(log.size() >= 1, "the boss's own wiping action must still be present in the returned log")

# ---------------------------------------------------------------------------
# 10. 指定Turn行動が正しい（turn_start_interrupt / replace / turn_end_interrupt）
# ---------------------------------------------------------------------------

func test_scripted_turn_start_interrupt_fires_via_the_new_api() -> void:
	var boss := _single_target_boss(10, 1)  # slowest -- so it's easy to isolate
	boss["skills"].append({"id": "scripted_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 500})
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_start_interrupt", "order": 0}]
	var battle := RBMBattle.new(_party_defs(), boss, 1)
	battle.boss.hp = 100

	var log := battle.advance_to_next_decision()
	assert_eq(str(log[0]["actor"]), "boss")
	assert_eq(str(log[0]["skill_id"]), "scripted_heal", "the turn_start_interrupt must fire before anyone (even the fastest ally) is prompted")
	assert_eq(battle.boss.hp, 600, "the scripted heal must have actually applied")
	assert_true(battle.is_waiting_for_ally_action(), "control must then move on to the fastest living ally as normal")

func test_scripted_replace_substitutes_for_the_bosss_own_normal_slot() -> void:
	var boss := _boss_with_random_candidates(1)  # slowest, so it acts last
	boss["skills"].append({"id": "scripted_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 500})
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "replace", "order": 0}]
	var battle := RBMBattle.new(_party_defs(), boss, 1)
	battle.boss.hp = 100

	# every ally DEFENDs (not attacks) so nobody touches the boss's own HP --
	# this isolates the scripted heal's effect on boss.hp precisely, without
	# needing to hand-compute the sum of 5 different allies' ATK values.
	var round_log: Array = _play_round(battle, 1, DEFEND)["log"]
	var boss_entries: Array = []
	for entry in round_log:
		if str(entry.get("actor", "")) == "boss":
			boss_entries.append(entry)
	assert_eq(boss_entries.size(), 1, "'replace' must substitute for the boss's normal slot -- exactly 1 boss log entry, not the scripted heal PLUS a separate normal hit_a/hit_b")
	assert_eq(str(boss_entries[0]["skill_id"]), "scripted_heal", "the boss's normal weighted-random pick (hit_a/hit_b) must not fire when a 'replace' scripted action exists for this turn")
	assert_eq(battle.boss.hp, 600, "the scripted heal must have actually applied (100 + 500), with no ally damage in the way since every ally defended instead of attacking")

func test_scripted_turn_end_interrupt_fires_after_the_normal_action_phase() -> void:
	var boss := _single_target_boss(10, 999)  # fastest, so its normal turn happens first
	boss["skills"].append({"id": "scripted_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 500})
	boss["scripted_actions"] = [{"turn": 1, "skill_id": "scripted_heal", "timing": "turn_end_interrupt", "order": 0}]
	var battle := RBMBattle.new(_party_defs(), boss, 1)
	battle.boss.hp = 100

	# boss (fastest) fires its own normal hit inside the VERY FIRST
	# advance_to_next_decision() call (before anyone else has acted), then
	# every ally DEFENDs (not attacks) so nobody deals extra damage to the
	# boss -- which would otherwise drop its 100 HP to 0 mid-round (well
	# before turn_end_interrupt ever gets a chance to fire), given the
	# party's real ATK totals well exceed 100.
	var round_log: Array = _play_round(battle, 1, DEFEND)["log"]
	var boss_entries: Array = []
	for entry in round_log:
		if str(entry.get("actor", "")) == "boss":
			boss_entries.append(entry)
	# Note: because the boss is also fastest overall, the very call that
	# finishes Turn 1 (firing turn_end_interrupt) auto-cascades straight into
	# Turn 2's own turn_start + the boss's OWN Turn-2 normal hit (nothing
	# stops the auto-cascade until it reaches a living ally) -- that 3rd,
	# legitimate Turn-2 entry is expected to appear too, so this asserts on
	# the first 2 entries specifically (Turn 1's own two) rather than
	# requiring the log to contain EXACTLY 2 entries in total.
	assert_true(boss_entries.size() >= 2, "the boss's own normal-phase hit, then the scripted turn_end_interrupt heal, must both be present")
	assert_eq(str(boss_entries[0]["skill_id"]), "boss_hit", "sanity: the normal action happens first (boss is fastest)")
	assert_eq(str(boss_entries[1]["skill_id"]), "scripted_heal", "the turn_end_interrupt fires only after the whole NORMAL ACTION PHASE (every living participant) has finished")

# ---------------------------------------------------------------------------
# 11. RNG決定論性維持
# ---------------------------------------------------------------------------

func test_rng_is_deterministic_across_two_independently_driven_battles_with_the_same_seed() -> void:
	var boss_def := _boss_with_random_candidates(50)
	var battle_a := RBMBattle.new(_party_defs(3), boss_def, 4242)
	var battle_b := RBMBattle.new(_party_defs(3), boss_def, 4242)

	var log_a: Array[Dictionary] = []
	var log_b: Array[Dictionary] = []
	for round_i in range(4):
		var start_turn_a := battle_a.current_turn
		while battle_a.current_turn == start_turn_a and not battle_a.battle_over:
			log_a.append_array(battle_a.advance_to_next_decision())
			if battle_a.is_waiting_for_ally_action():
				log_a.append_array(battle_a.resolve_pending_ally_action(ATTACK))
		var start_turn_b := battle_b.current_turn
		while battle_b.current_turn == start_turn_b and not battle_b.battle_over:
			log_b.append_array(battle_b.advance_to_next_decision())
			if battle_b.is_waiting_for_ally_action():
				log_b.append_array(battle_b.resolve_pending_ally_action(ATTACK))
		if battle_a.battle_over or battle_b.battle_over:
			break

	assert_true(log_a.size() >= 3, "sanity: the RNG-consuming boss must have actually acted at least a few times across 4 turns")
	assert_eq(log_a.size(), log_b.size(), "identical seed + identical input sequence must produce an identical number of log entries")
	for i in range(log_a.size()):
		assert_eq(str(log_a[i]), str(log_b[i]), "log entry %d must be byte-identical between the two independently-driven battles" % i)
	assert_eq(battle_a.boss.hp, battle_b.boss.hp, "boss HP must end up identical")
	for i in range(battle_a.party.size()):
		assert_eq(battle_a.party[i].hp, battle_b.party[i].hp, "party member %d HP must end up identical" % i)

# ---------------------------------------------------------------------------
# 防御の新仕様（ユーザー確定、遡及禁止・自分の次の行動順まで継続）
# ---------------------------------------------------------------------------

func test_defend_does_not_retroactively_reduce_a_hit_already_taken_earlier_this_round() -> void:
	# boss is FASTER than hero -- boss hits hero BEFORE hero has ever chosen
	# anything this round. hero then chooses defend on their own turn. The
	# EARLIER hit must have been full, undiminished damage (no retroactive
	# reduction), matching the user-confirmed spec's explicit prohibition.
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _single_target_boss(100, 999), 1)
	var hero: RBMUnit = battle.party[0]
	var hp_before_boss_hit := hero.hp

	battle.advance_to_next_decision()  # boss (faster) auto-resolves its hit on the only ally
	assert_true(battle.is_waiting_for_ally_action(), "sanity: control should now be with hero")
	var undefended_damage := hp_before_boss_hit - hero.hp
	assert_eq(undefended_damage, 100, "the boss's hit before hero ever acted must be full, undefended damage (ATK 100 x 1.0)")

	# hero now defends -- this must NOT retroactively change the damage
	# already dealt and already reflected in hero.hp above.
	battle.resolve_pending_ally_action(DEFEND)
	assert_eq(hp_before_boss_hit - hero.hp, undefended_damage, "choosing defend afterward must not retroactively change HP already lost to an earlier hit this same round")
	assert_true(hero.is_defending, "hero must now actually be defending, going forward")

func test_defend_reduces_damage_from_a_later_hit_in_the_same_round_after_being_declared() -> void:
	# hero is FASTER than the boss -- hero defends first, then the boss's own
	# turn (later this same round) must be reduced by that defend.
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _single_target_boss(100, 1), 1)
	var hero: RBMUnit = battle.party[0]
	battle.advance_to_next_decision()  # prime: hero (only living participant faster than the boss) becomes pending
	assert_true(battle.is_waiting_for_ally_action())
	battle.resolve_pending_ally_action(DEFEND)
	var hp_before_boss_hit := hero.hp

	battle.advance_to_next_decision()  # boss's own (slower) turn, later this round
	var defended_damage := hp_before_boss_hit - hero.hp
	assert_lt(defended_damage, 100, "a hit landing AFTER defend was declared this same round must be reduced")
	assert_eq(defended_damage, int(round(100 * (1.0 - RBMConstants.DEFEND_BASE_REDUCTION))), "must use the exact same base defend reduction rate as the existing formula")

func test_defend_persists_across_a_round_boundary_until_this_units_own_next_turn() -> void:
	# hero (spd100) defends late in Turn 1. The boss (spd999, fastest overall)
	# then acts EARLY in Turn 2 -- BEFORE hero's own Turn 2 slot has come up
	# -- and must still be reduced, since hero's own next turn hasn't arrived
	# yet (defend must survive the round boundary).
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _single_target_boss(100, 999), 1)
	var hero: RBMUnit = battle.party[0]
	battle.advance_to_next_decision()  # prime: boss (faster) auto-resolves its Turn-1 hit, then hero becomes pending
	assert_true(battle.is_waiting_for_ally_action())
	battle.resolve_pending_ally_action(DEFEND)  # hero's only slot in Turn 1
	assert_eq(battle.current_turn, 1, "sanity: Turn hasn't rolled over yet immediately after hero's own action")

	var hp_before_turn2_boss_hit := hero.hp
	battle.advance_to_next_decision()  # rolls into Turn 2, boss (fastest) immediately hits hero
	assert_eq(battle.current_turn, 2, "sanity: Turn 2 must now be in progress")
	var turn2_damage := hp_before_turn2_boss_hit - hero.hp
	assert_lt(turn2_damage, 100, "the defend declared late in Turn 1 must still reduce a hit landing in Turn 2, before hero's own Turn 2 slot has been reached")
	assert_eq(turn2_damage, int(round(100 * (1.0 - RBMConstants.DEFEND_BASE_REDUCTION))), "must be reduced by the exact same defend rate, carried across the round boundary")

## Round 5-2修正: 「入力待ち状態になった時点で、まだ新しいコマンドを選んで
## いなくても、既にis_defending==falseでなければならない」ことを、本当に
## "入力前"の瞬間で直接検査する（Codex指摘への対応——旧版はresolve_pending_
## ally_action()を呼んだ"後"にしか確認しておらず、解除がpending時点で起きた
## のかresolve時点で起きたのかを区別できていなかった）。
## 手順（ユーザー指定どおり）:
## 1. 前Turnで防御を実行
## 2. is_defending == true をsanity assert
## 3. 次Turnで本人の行動順までadvance
## 4. 本人が入力待ちになったことを確認
## 5. 新しい攻撃/スキル/防御をまだ入力していない状態でis_defending==falseを
##    assert
## 6. その後、新しいコマンドを入力して正常に進行することも確認する
func test_defend_is_cleared_the_instant_the_unit_becomes_pending_before_any_new_command_is_chosen() -> void:
	var battle := RBMBattle.new([RBMDataLoader.load_dict("res://data_bossmaker/allies/hero.json")], _single_target_boss(100, 999), 1)
	var hero: RBMUnit = battle.party[0]

	# 1. 前Turn(Turn 1)で防御を実行。
	battle.advance_to_next_decision()  # prime: boss (faster) auto-resolves its Turn-1 hit, then hero becomes pending
	battle.resolve_pending_ally_action(DEFEND)

	# 2. is_defending == true をsanity assert（防御が実際に有効になっている
	#    ことを、次のTurnへ進む前にまず確認する）。
	assert_true(hero.is_defending, "sanity: hero must actually be defending right after choosing defend")

	# 3. 次Turn(Turn 2)で本人の行動順まで advance する。
	battle.advance_to_next_decision()  # Turn 2 begins: boss hits first (still reduced by the still-active defend), THEN hero's own Turn 2 slot is reached.
	assert_eq(battle.current_turn, 2, "sanity: Turn 2 must now be in progress")

	# 4. 本人が入力待ちになったことを確認する。
	assert_true(battle.is_waiting_for_ally_action(), "sanity: hero's own Turn 2 slot must now be pending")
	assert_eq(battle.pending_ally_id(), hero.id, "sanity: hero specifically must be the one pending")

	# 5. 新しい攻撃/スキル/防御をまだ一切入力していない、この時点ですでに
	#    is_defending == false でなければならない（resolve_pending_ally_
	#    action()を一度も呼んでいない、この行より前のどこにもそれが無い
	#    ことに注目 -- これが「入力前を検査する」ことの直接的な証拠）。
	assert_false(hero.is_defending, "is_defending must ALREADY be false the instant hero becomes pending for their own Turn 2 slot -- BEFORE any new command (attack/skill/defend) has been chosen, not merely after one resolves")

	# 6. その後、新しいコマンド（攻撃）を入力して正常に進行することも確認する。
	battle.resolve_pending_ally_action(ATTACK)
	assert_false(hero.is_defending, "still false after resolving an ATTACK (not defend) -- confirms the earlier reset was not accidentally undone")

	var hp_before_turn3_boss_hit := hero.hp
	battle.advance_to_next_decision()  # rolls into Turn 3, boss hits again
	assert_eq(battle.current_turn, 3)
	var turn3_damage := hp_before_turn3_boss_hit - hero.hp
	assert_eq(turn3_damage, 100, "with no active defend anymore, a subsequent hit must land at full, undefended damage")
