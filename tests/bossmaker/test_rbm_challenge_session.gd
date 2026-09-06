extends GutTest

## RPG BOSS MAKER Phase 1 Step 7 — RBMChallengeSession単体テスト。
## §21〜§28: RBMBattle/RBMDefinitionLoaderへ正しく委譲すること、REWIND関連の
## public APIが一切存在しないこと、restart()が新しいseed・Turn 1・初期状態を
## 生成することを確認する。

func _valid_definition() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "テストボス"
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft.to_definition()

func _invalid_definition() -> Dictionary:
	return {"boss": {}, "party": []}

# ---------------------------------------------------------------------------
# §22/§23: 起動 — RBMDefinitionLoaderへ委譲するだけで独自の近道は無い
# ---------------------------------------------------------------------------

func test_valid_definition_starts_a_real_battle() -> void:
	var session := RBMChallengeSession.new(_valid_definition())
	assert_true(session.start_ok())
	assert_not_null(session.battle)
	assert_eq(session.battle.current_turn, 1)
	assert_false(session.battle.battle_over)

func test_invalid_definition_fails_without_crashing_and_battle_stays_null() -> void:
	var session := RBMChallengeSession.new(_invalid_definition())
	assert_false(session.start_ok())
	assert_null(session.battle)
	assert_false(session.start_errors().is_empty(), "the raw RBMDefinitionLoader.resolve() error strings must be exposed for the caller to translate")

## §23: definitionが呼び出し元から渡された後、内部で複製される（呼び出し元が
## 後から辞書を書き換えても、既に構築済みのセッションの戦闘内容は変わらない）。
func test_definition_is_captured_by_value_not_by_reference() -> void:
	var definition := _valid_definition()
	var session := RBMChallengeSession.new(definition)
	assert_true(session.start_ok())
	definition["boss"]["hp"] = 999999
	# セッション自体が既にconstructした戦闘（boss.hp）は、後からdefinitionを
	# 書き換えても影響を受けない——construction後の再読み込み経路が無いことの
	# 直接証明。
	assert_ne(session.battle.boss.max_hp, 999999)

# ---------------------------------------------------------------------------
# §24: REWINDのpublic APIが一切存在しないこと
# ---------------------------------------------------------------------------

func test_session_exposes_no_rewind_api() -> void:
	var session := RBMChallengeSession.new(_valid_definition())
	assert_false(session.has_method("rewind_to"), "RBMChallengeSession must never expose REWIND to a challenger")
	assert_false(session.has_method("reachable_turns"), "RBMChallengeSession must never expose REWIND to a challenger")
	assert_null(session.get("history"), "RBMChallengeSession must not maintain per-turn history at all")

# ---------------------------------------------------------------------------
# 実機プレイ改善①: 旧一括resolve_turn(ally_actions)は廃止された——
# resolve_ally_action(action)が現在入力待ちの味方の行動を即座に解決し、続く
# ボスの番等の自動解決分もまとめて返す。返り値は本物の戦闘ログエントリの
# 配列そのもの（旧{"log":...,"turn":...}という辞書ラッパーは無くなった）。
# ---------------------------------------------------------------------------

func test_resolve_ally_action_delegates_to_the_real_battle_and_advances_state() -> void:
	var session := RBMChallengeSession.new(_valid_definition(), 1)
	assert_true(session.is_waiting_for_ally_action(), "sanity: hero(spd 100)はboss(spd 50)より速いため、構築直後から入力待ちになる")
	var log := session.resolve_ally_action({"type": "attack"})
	assert_false(log.is_empty(), "resolving the pending ally's action must return the real battle's own log entries")
	assert_lt(session.battle.boss.hp, session.battle.boss.max_hp, "the real RBMBattle damage formula must actually have applied")

# ---------------------------------------------------------------------------
# §27/§28/§32/§34: restart() — 同じDefinition・新しいseed・Turn 1・初期状態
# ---------------------------------------------------------------------------

func test_restart_resets_to_turn_1_and_full_hp_after_taking_damage() -> void:
	var session := RBMChallengeSession.new(_valid_definition(), 1)
	for i in range(20):
		if session.battle.battle_over:
			break
		session.resolve_ally_action({"type": "attack"})
	assert_gt(session.battle.current_turn, 1)

	session.restart()
	assert_eq(session.battle.current_turn, 1)
	assert_false(session.battle.battle_over)
	assert_eq(session.battle.boss.hp, session.battle.boss.max_hp)
	for unit in session.battle.party:
		assert_eq(unit.hp, unit.max_hp)

## §27/§28: 「同じDefinition」——restart()前後でboss_name/hp/atk/spd等の
## 設定内容自体は変わらないこと（restart()が別のDefinitionへすり替わって
## いないことの確認）。
func test_restart_keeps_the_same_definition_content() -> void:
	var session := RBMChallengeSession.new(_valid_definition(), 1)
	var boss_name_before := session.battle.boss.display_name
	var max_hp_before := session.battle.boss.max_hp
	session.restart()
	assert_eq(session.battle.boss.display_name, boss_name_before)
	assert_eq(session.battle.boss.max_hp, max_hp_before)

## §27: 「新しい乱数seed」——毎回同じseedへ固定されているわけではないこと
## （厳密な非決定性の証明は難しいため、内部_seedが実際に変化することを
## 間接的に確認する意味で、少なくとも複数回restart()してもクラッシュせず
## 常に有効な戦闘が再構築されることを確認する）。
func test_restart_can_be_called_repeatedly_without_error() -> void:
	var session := RBMChallengeSession.new(_valid_definition())
	for i in range(5):
		session.restart()
		assert_true(session.start_ok())
		assert_eq(session.battle.current_turn, 1)

# ---------------------------------------------------------------------------
# Codex最終レビュー指摘対応 §9/§10 — restart()の新seed・状態完全初期化
# ---------------------------------------------------------------------------

## §9: restart()が実際に新しい乱数seedを生成することを、RBMBattle.rng.seed
## から直接確認する（「新しい戦闘が始まる」という間接的な確認だけでは
## 不十分という指摘への対応）。
func test_restart_generates_a_new_rng_seed() -> void:
	var session := RBMChallengeSession.new(_valid_definition(), 12345)
	var seed_before := session.battle.rng.seed
	session.restart()
	var seed_after := session.battle.rng.seed
	assert_ne(seed_before, seed_after, "restart() must generate a fresh random seed, never reuse the previous one")

## §10: 実際にターンを進めHP/SPを変化させてからrestart()し、Turn 1・初期HP・
## 初期SP・一時状態の初期化・新seed・同じDefinition内容へ完全に初期化される
## ことを直接確認する。restart()は毎回new RBMBattle()（新しいRBMUnit
## インスタンス群を含む）を構築する設計のため、一時効果(timed_effects)や
## 防御姿勢(is_defending)も新しいオブジェクトへは一切引き継がれない
## ——これも直接assertする。
func test_restart_fully_resets_turn_hp_sp_and_temporary_state_with_a_new_seed_and_same_definition() -> void:
	var session := RBMChallengeSession.new(_valid_definition(), 999)
	var seed_before := session.battle.rng.seed
	var boss_max_hp := session.battle.boss.max_hp
	var hero_max_hp := session.battle.party[0].max_hp
	# restart()が復元すべき「真の初期SP」——これはこの後の一時的な操作より
	# 前に取得する必要がある。
	var hero_true_starting_sp := session.battle.party[0].sp
	var boss_name := session.battle.boss.display_name

	# heroは実測で既に満タンSPから開始しており（実機確認: NORMAL_ATTACK_SP_GAINが
	# mini(max_sp, sp+gain)で頭打ちになり、通常攻撃だけではSPの変化を
	# 実際に起こせなかった）、「SP変化」を本当に exercise するため、攻撃前に
	# 意図的に少し減らしてから通常攻撃のSP_GAINで実際に動くことを確認する。
	# restart()後に比較する基準はこの人為的な操作より前に取得した
	# hero_true_starting_sp（真の初期値）であり、この一時的な減算値ではない。
	var sp_before_attack := hero_true_starting_sp
	if session.battle.party[0].has_sp_resource():
		session.battle.party[0].sp = maxi(0, session.battle.party[0].sp - 5)
		sp_before_attack = session.battle.party[0].sp

	# 実際にターンを進め、HP/SPを変化させる（最低限: Turn進行・HP減少・
	# SP変化のうちSPはhas_sp_resource()な場合のみ実際に変わる）。
	session.resolve_ally_action({"type": "attack"})
	assert_gt(session.battle.current_turn, 1, "sanity: turn actually advanced")
	assert_lt(session.battle.boss.hp, boss_max_hp, "sanity: boss took real damage from a real attack")
	if session.battle.party[0].has_sp_resource():
		assert_ne(session.battle.party[0].sp, sp_before_attack, "sanity: SP actually changed from a real attack (NORMAL_ATTACK_SP_GAIN)")

	# restart()が一時状態を本当に消去することを検証できるよう、再起動直前の
	# 実Unitを明示的に非初期状態へする。共有APIで持続効果を登録し、防御姿勢も
	# そのUnit自身へ設定する。
	RBMConstants.set_timed_effect(session.battle.party[0].timed_effects, "restart_reset_probe", session.battle.current_turn, 3, 1.5)
	session.battle.party[0].is_defending = true
	assert_false(session.battle.party[0].timed_effects.is_empty(), "sanity: a temporary effect must exist before restart")
	assert_true(session.battle.party[0].is_defending, "sanity: defending must be active before restart")

	session.restart()

	assert_eq(session.battle.current_turn, 1, "restart must reset to Turn 1")
	assert_false(session.battle.battle_over, "restart must reset battle_over")
	assert_eq(session.battle.boss.hp, boss_max_hp, "restart must reset boss HP to max")
	assert_eq(session.battle.party[0].hp, hero_max_hp, "restart must reset party HP to max")
	assert_eq(session.battle.party[0].sp, hero_true_starting_sp, "restart must reset party SP to its true original starting value")
	assert_true(session.battle.party[0].timed_effects.is_empty(), "restart must clear any temporary effect state")
	assert_false(session.battle.party[0].is_defending, "restart must clear any temporary posture state")
	assert_ne(session.battle.rng.seed, seed_before, "restart must use a new seed")
	assert_eq(session.battle.boss.display_name, boss_name, "restart must keep using the SAME Definition's content")
	assert_eq(session.battle.boss.max_hp, boss_max_hp, "restart must keep using the SAME Definition's content")
