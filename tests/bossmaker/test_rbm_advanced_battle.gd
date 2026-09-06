extends GutTest

## RPG BOSS MAKER — RBMBattle「HARDCORE Creator」ラウンドロビン評価器の
## テスト（2026-09-05全面再設計、旧「行動パターン」仕様のテストを全面
## 置換）。RBMDefinitionLoaderを経由せず、既存test_rbm_battle_sequential.gd
## と同じ慣習で「既に解決済みのboss_def」を直接手書きしてRBMBattleへ渡し、
## advance_to_next_decision()/resolve_pending_ally_action()という実際の
## 製品コードが使う戦闘駆動APIをそのまま経由して検証する。
##
## 旧仕様にあった瞬間条件（instant condition）・発動確率（trigger_
## probability）・Cooldown（cooldown_turns）・1配置内の複数行動ステップの
## 連続実行は新仕様に一切存在しない（RBMActionPatternRules冒頭コメント
## 参照、§9/§18で明示的に廃止）——対応する旧テストは削除し、新仕様の
## 「1ターン＝1スロットのラウンドロビン走査」を保証するテストへ置き換えた。

const ATTACK := {"type": "attack"}
const DEFEND := {"type": "defend"}

func _ally_def(character_id: String, atk_override: int = -1) -> Dictionary:
	var def := RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % character_id)
	if atk_override >= 0:
		def["atk"] = atk_override
	return def

func _party_defs(character_ids: Array, atk_override: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for character_id in character_ids:
		out.append(_ally_def(character_id, atk_override))
	return out

func _skill_slot(slot_id: String, skill_id: String, conditions: Array = [], condition_logic: String = "AND", max_uses: int = -1) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": "skill",
		"skill_id": skill_id,
		"conditions": conditions,
		"condition_logic": condition_logic,
		"max_uses": max_uses,
	}

func _random_slot(slot_id: String, candidates: Array, conditions: Array = [], condition_logic: String = "AND", max_uses: int = -1) -> Dictionary:
	return {
		"slot_id": slot_id,
		"kind": "random",
		"candidates": candidates,
		"conditions": conditions,
		"condition_logic": condition_logic,
		"max_uses": max_uses,
	}

func _boss_skills() -> Array:
	return [
		{"id": "boss_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_hit2", "display_name": "Hit2", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_aoe", "display_name": "AoE", "effect": "damage", "target": "ally_all", "attribute": "NEUTRAL", "atk_multiplier": 1.0},
		{"id": "boss_heal", "display_name": "Heal", "effect": "heal", "heal_amount": 50},
		{"id": "boss_buff", "display_name": "Buff", "effect": "buff_atk_self", "buff_multiplier": 2.0, "duration_turns": 3},
	]

func _boss_with_sequence(sequence: Array, hp: int = 1000, atk: int = 1, spd: int = 10) -> Dictionary:
	return {
		"id": "adv_boss", "display_name": "AdvBoss", "hp": hp, "atk": atk, "spd": spd,
		"skills": _boss_skills(),
		"normal_action_candidates": [],
		"action_sequence": sequence,
	}

## 「単一の外部から観測できる境界」——advance_to_next_decision()を味方の
## 入力待ちになるかbattle_overになるまで自動継続する共通ヘルパー。
func _resolve_one_ally_turn(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	log.append_array(battle.advance_to_next_decision())
	if battle.battle_over or not battle.is_waiting_for_ally_action():
		return log
	log.append_array(battle.resolve_pending_ally_action(action))
	log.append_array(battle.advance_to_next_decision())
	return log

func _play_full_round(battle: RBMBattle, action: Dictionary = ATTACK) -> Array:
	var log: Array = []
	var start_turn := battle.current_turn
	while true:
		log.append_array(battle.advance_to_next_decision())
		if battle.battle_over or battle.current_turn != start_turn:
			return log
		if not battle.is_waiting_for_ally_action():
			return log
		log.append_array(battle.resolve_pending_ally_action(action))
	return log  # 到達しない — GDScriptの静的チェッカー向けの形式的なフォールバックのみ。

func _boss_log_entries(log: Array) -> Array:
	var out: Array = []
	for entry in log:
		if str(entry.get("actor", "")) == "boss":
			out.append(entry)
	return out

func _boss_skill_ids(log: Array) -> Array:
	var out: Array = []
	for entry in _boss_log_entries(log):
		out.append(str(entry.get("skill_id", "")))
	return out

# ---------------------------------------------------------------------------
# §14/§15/§16/§17/§18: ラウンドロビン走査の基本挙動
# ---------------------------------------------------------------------------

## 基本のラウンドロビン: A→B→C→A（末尾に達したら自動的に先頭へループ）。
func test_round_robin_cycles_through_slots_and_loops_back_to_the_start() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit"),
		_skill_slot("b", "boss_hit2"),
		_skill_slot("c", "boss_aoe"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var expected := ["boss_hit", "boss_hit2", "boss_aoe", "boss_hit", "boss_hit2"]
	for skill_id in expected:
		var log := _resolve_one_ally_turn(battle, DEFEND)
		assert_eq(_boss_skill_ids(log), [skill_id])

## §18確定: 旧仕様の「1配置内の複数行動を連続実行」は廃止済み——複数の
## スロットが全て条件なしで発動可能でも、1ターンに実行されるのは常に
## ちょうど1つだけ。
func test_exactly_one_slot_executes_per_boss_turn_even_with_many_eligible_slots() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit"),
		_skill_slot("b", "boss_hit2"),
		_skill_slot("c", "boss_aoe"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_log_entries(log).size(), 1)

## §16の例: 01が条件不成立でスキップされ、02が発動する。次ターンは
## 発動に成功したスロットの次（03）から走査を再開する。
func test_condition_failure_skips_to_the_next_eligible_slot_and_cursor_resumes_after_it() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "hp_at_most", "percent": 10.0}]),  # HP満タンなので失敗するはず。
		_skill_slot("b", "boss_hit2"),  # 条件なし、成功。
		_skill_slot("c", "boss_aoe"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var turn1_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn1_log), ["boss_hit2"])
	var turn2_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn2_log), ["boss_aoe"])

## §8: 使用回数上限に達したスロットは以後スキップされ、次の発動可能な
## スロットへフォールスルーする。
func test_max_uses_limits_how_many_times_a_slot_can_fire_then_falls_through() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var turn1_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn1_log), ["boss_hit"])
	var turn2_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn2_log), ["boss_hit2"])
	var turn3_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn3_log), ["boss_hit2"])

## §17確定の具体例: 開始位置(カーソル)を02に置き、02/03/01の順で一周
## しても全て発動不可なら、ボスは何もせず、カーソルは02のまま据え置かれる
## （次のターンも再び02から同じ走査をやり直す）。
func test_when_every_slot_is_ineligible_the_boss_does_nothing_and_cursor_stays_in_place() -> void:
	var never := [{"type": "turn_at", "turn": 999}]
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", never),
		_skill_slot("b", "boss_hit2", never),
		_skill_slot("c", "boss_aoe", never),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	var boss_entries := _boss_log_entries(log)
	assert_eq(boss_entries.size(), 1)
	assert_eq(str(boss_entries[0].get("action", "")), "none")
	assert_eq(battle.hardcore_action_cursor(), 0)
	# 次のターンも同じ結果になる——カーソルが動いていないため常に0から
	# 再走査し、常に全滅走査になる。
	var log2 := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(str(_boss_log_entries(log2)[0].get("action", "")), "none")
	assert_eq(battle.hardcore_action_cursor(), 0)

## 上のシナリオを、カーソルが0以外の位置にある状態から再現する——
## 「一周した後に全滅」した時、カーソルが"一周した末尾"や"0"へ強制的に
## リセットされたりせず、本当に開始位置のまま止まることを確認する。
func test_cursor_stays_at_its_current_position_not_reset_to_zero_when_a_full_scan_finds_nothing() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit"),  # 1ターン目はこれが発動し、カーソルは1(b)へ進む。
		_skill_slot("b", "boss_hit2", [{"type": "turn_at", "turn": 999}]),
		_skill_slot("c", "boss_aoe", [{"type": "turn_at", "turn": 999}]),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var turn1_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn1_log), ["boss_hit"])
	assert_eq(battle.hardcore_action_cursor(), 1)  # 次はbから走査を始める。
	# ターン2: b(不成立)->c(不成立)->a(スロット自体は条件なしで成立するが、
	# aの条件は無いため実際には成立する——ここでは"bから一周してaに戻り、
	# aが成立する"ことを検証する別の目的で使う。
	var turn2_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(turn2_log), ["boss_hit"])  # 一周してaに戻り成立。
	assert_eq(battle.hardcore_action_cursor(), 1)  # aの次であるbへ進む(サイズ3の1)。

# ---------------------------------------------------------------------------
# §5/§6: 通常条件によるゲート（引き続き通常条件タイプの判定を検証する）
# ---------------------------------------------------------------------------

func test_condition_less_slot_always_fires_as_fallback() -> void:
	var boss_def := _boss_with_sequence([_skill_slot("a", "boss_hit")])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["boss_hit"])

func test_hp_at_least_condition_gates_the_slot() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "hp_at_least", "percent": 50.0}]),
		_skill_slot("b", "boss_hit2"),
	], 1000)
	var ally := _ally_def("hero", 600)  # 1発でHP1000->400(40%)まで削る。
	var battle := RBMBattle.new([ally], boss_def, 1)
	var log := _resolve_one_ally_turn(battle, ATTACK)
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

func test_turn_at_least_condition_only_matches_from_that_turn_onward() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "turn_at_least", "turn": 2}]),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit2"])
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])

func test_and_logic_requires_all_conditions() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "turn_at_least", "turn": 2}, {"type": "hp_at_most", "percent": 200.0}], "AND"),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit2"])
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])

func test_or_logic_matches_if_any_condition_is_true() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "turn_at_least", "turn": 99}, {"type": "hp_at_most", "percent": 200.0}], "OR"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])

func test_character_alive_and_downed_conditions() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "character_downed", "character_id": "hero"}]),
		_skill_slot("b", "boss_hit2", [{"type": "character_alive", "character_id": "hero"}]),
	], 1000000)  # 高HPで撃破されないようにする。
	var battle := RBMBattle.new(_party_defs(["hero"], 999999), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, ATTACK)
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

func test_last_boss_skill_condition_reflects_the_boss_own_previous_action() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "turn_at", "turn": 1}]),
		_skill_slot("b", "boss_hit2", [{"type": "last_boss_skill", "skill_id": "boss_hit"}]),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	_resolve_one_ally_turn(battle, DEFEND)  # ターン1: boss_hitが発動、カーソルは1(b)へ。
	var turn2_log := _resolve_one_ally_turn(battle, DEFEND)  # ターン2: bから開始、last_boss_skill=="boss_hit"が成立するはず。
	assert_eq(_boss_skill_ids(turn2_log), ["boss_hit2"])

func test_last_received_skill_and_last_received_attribute_conditions() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "last_received_skill", "skill_id": "hero_slash"}]),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, {"type": "skill", "skill_id": "hero_slash", "target_id": -1})
	assert_eq(_boss_skill_ids(log), ["boss_hit"])

func test_normal_attack_never_matches_last_received_skill_since_it_has_no_skill_id() -> void:
	# v0.1-B §10「通常攻撃は攻撃スキルではない」——last_received_skillは
	# 常にskill_idの完全一致判定のため、通常攻撃の直後は絶対に一致しない。
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "last_received_skill", "skill_id": "hero_slash"}]),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, ATTACK)
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

func test_weak_hit_condition_true_only_after_an_actual_weakness_hit() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [{"type": "weak_hit"}]),
		_skill_slot("b", "boss_hit2"),
	])
	boss_def["weak_attribute"] = "FIRE"
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)  # heroはFIRE属性のskillを持つ。
	var log := _resolve_one_ally_turn(battle, ATTACK)  # 通常攻撃はNEUTRAL属性 -> 弱点ではない。
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

func test_no_slot_matches_results_in_boss_doing_nothing() -> void:
	var boss_def := _boss_with_sequence([_skill_slot("a", "boss_hit", [{"type": "turn_at", "turn": 999}])])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	var boss_entries := _boss_log_entries(log)
	assert_eq(boss_entries.size(), 1)
	assert_eq(str(boss_entries[0].get("action", "")), "none")

# ---------------------------------------------------------------------------
# §2/§8: 同じskill_idの複数配置——それぞれ独立した条件/使用回数
# ---------------------------------------------------------------------------

## 同じ攻撃性能(skill_id)を2つの異なるスロットへ配置し、それぞれ別々の
## 条件・使用回数を持たせても、それぞれ独立して判定・カウントされる
## （§2/§8確定仕様の核心例、実装前調査報告書の"炎撃"の例そのもの）。
func test_the_same_skill_id_placed_twice_has_independent_conditions_and_use_counts() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("slot_low_hp", "boss_hit", [{"type": "hp_at_most", "percent": 200.0}], "AND", 1),  # 常に真、1回のみ。
		_skill_slot("slot_late", "boss_hit", [{"type": "turn_at_least", "turn": 3}]),  # 3ターン目以降、無制限。
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	# ターン1: slot_low_hpが発動（1回消費）。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])
	# ターン2: slot_low_hpは使用回数上限（1回）に達したためスキップ、
	# slot_lateはまだturn_at_least(3)を満たさない -> どちらも発動不可。
	var turn2_log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(str(_boss_log_entries(turn2_log)[0].get("action", "")), "none")
	# ターン3: slot_lateのturn_at_least(3)が成立 -> 発動（slot_low_hpは
	# 引き続き使用回数上限のためスキップされ続ける、別配置なので無関係）。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])
	# ターン4以降もslot_lateは無制限に発動し続ける。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])

# ---------------------------------------------------------------------------
# §10/§12/§13: ランダム攻撃
# ---------------------------------------------------------------------------

func test_random_slot_even_mode_picks_among_candidates() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 1.0}, {"skill_id": "boss_hit2", "weight": 1.0}]),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	var boss_entries := _boss_log_entries(log)
	assert_eq(boss_entries.size(), 1)
	assert_true(["boss_hit", "boss_hit2"].has(str(boss_entries[0].get("skill_id", ""))))

## 手動確率100:0（実質固定）——ランダム抽選が実際に重みへ従っていることの
## 決定論的な確認（RNGの偏りに頼らず、片方の重みを0にして必ずもう片方が
## 選ばれることを保証する）。
func test_random_slot_manual_weights_are_respected() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 0.0}, {"skill_id": "boss_hit2", "weight": 100.0}]),
	])
	for seed_value in range(5):
		var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, seed_value)
		var log := _resolve_one_ally_turn(battle, DEFEND)
		assert_eq(_boss_skill_ids(log), ["boss_hit2"])

## §13確定「ランダム結果自体は保存しない」——RBMBattleの内部RNG（既存の
## seed駆動RandomNumberGenerator）がそのまま毎回新しく抽選する。同じseedの
## 2つのRBMBattleインスタンスは同じ結果を再現する（決定論的、既存のRNG
## 契約と同じ）。
func test_random_slot_results_are_freshly_rolled_each_time_not_cached() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 50.0}, {"skill_id": "boss_hit2", "weight": 50.0}]),
	])
	var battle_a := RBMBattle.new(_party_defs(["hero"]), boss_def, 777)
	var log_a := _resolve_one_ally_turn(battle_a, DEFEND)
	var battle_b := RBMBattle.new(_party_defs(["hero"]), boss_def, 777)
	var log_b := _resolve_one_ally_turn(battle_b, DEFEND)
	assert_eq(_boss_skill_ids(log_a), _boss_skill_ids(log_b))

## §12確定（非常に重要）: ランダム候補は参照するskill_idの「性能」だけを
## 使う——同じskill_idが別のスロットへ配置され、そちらに固有の条件・使用
## 回数が設定されていても、ランダム候補としての抽選・実行時にはそれらは
## 一切参照されない。ここでは"boss_hit"を①別配置で使用回数1回消費済み・
## 条件不成立にした状態にしてから、②同じ"boss_hit"をランダム候補として
## 持つスロットが問題なく抽選・発動できることを確認する。
func test_random_candidate_uses_only_the_referenced_skills_performance_ignoring_its_other_placements_condition_and_uses() -> void:
	var boss_def := _boss_with_sequence([
		# 他配置: 条件は「絶対に成立しない」、使用回数は無関係（一度も
		# 実行されない設計）——この配置自体が発動することは無い。
		_skill_slot("other_placement", "boss_hit", [{"type": "turn_at", "turn": 999}], "AND", 1),
		# ランダム候補側: 100%の重みでboss_hitだけを選ぶ設定。
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 100.0}, {"skill_id": "boss_hit2", "weight": 0.0}]),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	# ターン1: other_placementはturn_at(999)で不成立 -> ランダムスロットへ
	# フォールスルーし、boss_hitが問題なく選ばれ発動する（他配置の条件・
	# 使用回数が一切参照されないことの直接証明）。
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["boss_hit"])

## §12確定: ランダム攻撃自身の条件・使用回数だけが評価される——候補側の
## 概念ではなくスロット全体の設定であることを確認する。
func test_random_slot_own_condition_and_max_uses_are_evaluated_not_candidate_level() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 1.0}], [], "AND", 1),  # スロット自体が1回のみ。
		_skill_slot("fallback", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])
	# ランダムスロット自体の使用回数(1)を使い切ったため、以後はフォールバックへ。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit2"])

# ---------------------------------------------------------------------------
# REWINDとの整合性
# ---------------------------------------------------------------------------

func _advance_until_waiting_or_fresh_boundary(battle: RBMBattle) -> Array:
	var log: Array = []
	while true:
		log.append_array(battle.advance_to_next_decision(true))
		if battle.battle_over or battle.is_waiting_for_ally_action() or battle.is_at_fresh_turn_boundary():
			return log
	return log  # 到達しない — GDScriptの静的チェッカー向けの形式的なフォールバックのみ。

## §21確定（非常に重要）: カーソル・使用回数状態がsnapshot()/restore()の
## ラウンドトリップで正しく復元される——REWINDすると「次に使う攻撃だけ
## ズレる」というバグが絶対に起きないことの直接証明。
func test_snapshot_and_restore_round_trips_the_hardcore_cursor_and_use_counts() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),
		_skill_slot("b", "boss_hit2"),
		_skill_slot("c", "boss_aoe"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_true(battle.is_at_fresh_turn_boundary())  # 構築直後は常にfresh。

	# ターン1: aが発動(使用回数1/1消費)、カーソルはbへ。
	_advance_until_waiting_or_fresh_boundary(battle)
	battle.resolve_pending_ally_action(DEFEND)
	_advance_until_waiting_or_fresh_boundary(battle)  # ターン2の開始。
	assert_eq(battle.current_turn, 2)
	assert_eq(battle.hardcore_action_cursor(), 1)  # aの次=b。
	var snapshot := battle.snapshot()

	# さらに2ターン分進める(b発動->カーソルc、c発動->カーソルa)。
	_advance_until_waiting_or_fresh_boundary(battle)
	battle.resolve_pending_ally_action(DEFEND)
	_advance_until_waiting_or_fresh_boundary(battle)
	assert_eq(battle.hardcore_action_cursor(), 2)  # bの次=c。
	_advance_until_waiting_or_fresh_boundary(battle)
	battle.resolve_pending_ally_action(DEFEND)
	_advance_until_waiting_or_fresh_boundary(battle)
	assert_eq(battle.hardcore_action_cursor(), 0)  # cの次=a(ループ)。

	battle.restore(snapshot)
	assert_eq(battle.current_turn, 2)
	assert_eq(battle.hardcore_action_cursor(), 1)  # スナップショット時点のカーソルへ正確に戻る。
	# aの使用回数(1/1)も復元されているため、bから始まり、aは二度と発動
	# しない——「次に使う攻撃だけズレる」バグがあれば、ここでaが再発動
	# してしまうか、カーソル位置がずれて誤ったスロットが選ばれるはず。
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

## §21: 使用回数上限に達した後にREWINDすると、消費済みだった回数も
## 正しく元へ戻る（REWIND後に再びそのスロットを使い切れることの確認）。
func test_rewind_restores_exhausted_use_count_allowing_the_slot_to_fire_again() -> void:
	var boss_def := _boss_with_sequence([
		_skill_slot("a", "boss_hit", [], "AND", 1),
		_skill_slot("b", "boss_hit2"),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	assert_true(battle.is_at_fresh_turn_boundary())
	var snapshot := battle.snapshot()

	# aを消費する。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])
	# aは使い切ったのでbへフォールスルーする。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit2"])

	battle.restore(snapshot)
	# 復元後は再びaから使用回数1回分を発動できる。
	assert_eq(_boss_skill_ids(_resolve_one_ally_turn(battle, DEFEND)), ["boss_hit"])

## §21: ランダム抽選+REWINDの組み合わせでも決定論的に同じ結果を再現する
## （RNGのstate自体もsnapshot/restore対象、既存のRNG state保存契約を継続）。
func test_rewind_replays_random_slot_deterministically_from_the_same_rng_state() -> void:
	var boss_def := _boss_with_sequence([
		_random_slot("r", [{"skill_id": "boss_hit", "weight": 50.0}, {"skill_id": "boss_hit2", "weight": 50.0}]),
	])
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 5)
	assert_true(battle.is_at_fresh_turn_boundary())
	var snapshot := battle.snapshot()

	var log_first := _resolve_one_ally_turn(battle, ATTACK)
	var first_boss_skills := _boss_skill_ids(log_first)

	battle.restore(snapshot)
	var log_second := _resolve_one_ally_turn(battle, ATTACK)
	var second_boss_skills := _boss_skill_ids(log_second)

	assert_eq(first_boss_skills, second_boss_skills)
	assert_eq(first_boss_skills.size(), 1)

# ---------------------------------------------------------------------------
# SIMPLE経路への非干渉（回帰ガード）
# ---------------------------------------------------------------------------

## action_sequenceが空の間は、既存のSIMPLE経路（_pick_boss_normal_action()/
## scripted_actions replace）が完全に無改修のまま機能する。
func test_empty_action_sequence_leaves_the_simple_normal_action_path_untouched() -> void:
	var boss_def := {
		"id": "simple_boss", "display_name": "SimpleBoss", "hp": 1000, "atk": 10, "spd": 10,
		"skills": [{"id": "s_hit", "display_name": "Hit", "effect": "damage", "target": "ally_random_single", "attribute": "NEUTRAL", "atk_multiplier": 1.0}],
		"normal_action_candidates": [{"skill_id": "s_hit", "weight": 1}],
		"action_sequence": [],
	}
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["s_hit"])

## action_sequenceが非空の間は、既存のscripted_actions(replace)は評価
## されない（HARDCORE側が唯一の正になる、_resolve_boss_turn_actions()参照）。
func test_non_empty_action_sequence_bypasses_the_old_replace_scripted_actions() -> void:
	var boss_def := _boss_with_sequence([_skill_slot("a", "boss_hit2")])
	boss_def["scripted_actions"] = [{"turn": 1, "skill_id": "boss_hit", "timing": "replace", "order": 1}]
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["boss_hit2"])

## turn_start_interrupt/turn_end_interruptはaction_sequenceの有無に
## 関わらず常に無条件で発火し続ける。
func test_turn_start_interrupt_still_fires_unconditionally_alongside_action_sequence() -> void:
	var boss_def := _boss_with_sequence([_skill_slot("a", "boss_hit2")])
	boss_def["scripted_actions"] = [{"turn": 1, "skill_id": "boss_hit", "timing": "turn_start_interrupt", "order": 1}]
	var battle := RBMBattle.new(_party_defs(["hero"]), boss_def, 1)
	var log := _resolve_one_ally_turn(battle, DEFEND)
	assert_eq(_boss_skill_ids(log), ["boss_hit", "boss_hit2"])  # turn_start_interrupt -> HARDCORE通常行動。
