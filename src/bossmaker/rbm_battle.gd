class_name RBMBattle
extends RefCounted

## RPG BOSS MAKER (working title) — standalone Phase 1 battle core.
##
## Deliberately independent of UDSim (see src/bossmaker/README.md): no DEF stat,
## no REWIND, no parts, no items, no leveling. UI-agnostic — this class has no
## dependency on any Control/Node and can be driven entirely from a script or a
## test. A future Creator/UI would call resolve_turn() exactly the way the tests
## in tests/bossmaker/ do.
##
## Turn structure (v0.1-B §11): each call to resolve_turn() is one whole
## "戦闘全体ターン" — TURN START (reset per-turn postures) → [割り込み型・ターン開始時
## 指定行動] → NORMAL ACTION PHASE (every living combatant acts once, in a fixed
## SPD-sorted order; the boss's own slot may be replaced by one or more
## 置換型 指定行動) → [割り込み型・ターン終了時 指定行動] → TURN END (turn-scoped
## state, e.g. counter stance, clears).
##
## 指定行動 (Step 3 修正指示 §6, and 最終修正指示 §1): boss_def["scripted_actions"]
## is an Array of {"turn":int, "skill_id":String,
## "timing":"replace"|"turn_start_interrupt"|"turn_end_interrupt", "order":int}.
## "replace" substitutes for the boss's single NORMAL ACTION PHASE turn (in
## place of _pick_boss_normal_action()) — critically, ALL replace-timing
## entries scheduled for the current turn fire, in ascending "order", not just
## the lowest-order one; when at least one exists the boss's ordinary
## weighted-random normal action does not additionally fire that turn. The two
## "interrupt" timings are SPD-ignoring EXTRA boss actions in addition to the
## normal turn, and (like "replace") ALL entries sharing that (turn,timing)
## fire, in ascending "order". This is the minimal addition needed to close
## the gap Step 2 deliberately left as a future seam — no other battle-logic
## path changes as a result (an empty/absent scripted_actions list makes both
## new resolve_turn() loops a no-op and leaves the original single-pick normal
## action path untouched).
##
## 実機プレイ改善①「戦闘方式を後期UNDERDESK方式へ統一」 — resolve_turn()
## (上記、丸ごと1ラウンド分のally_actions Dictionaryを一括で受け取り即座に
## 全員分解決する)自体はこのラウンドで一切変更していない——504件の既存
## テストが直接この完全同期・一括解決の契約に依存しているため、無改修の
## まま維持する（動作は一切変わらない）。
##
## 新方式（advance_to_next_decision()/resolve_pending_ally_action()、下記）
## は、それとは別の、追加のエントリポイントとして実装した——実際の製品UI
## （TEST BATTLE/Clear Check/CHALLENGE戦闘のすべて）は今後この新APIだけを
## 使う。中身は"1ラウンドをSPD順に1スロットずつ、必要な時だけ入力を待って
## 即座に解決する"という、resolve_turn()と全く同じ規則（TURN START→
## [turn_start_interrupt]→NORMAL ACTION PHASE→[turn_end_interrupt]→TURN END
## →次ラウンドへ）を「1回の呼び出しで全部やる」のではなく「途中で何度でも
## 呼び出しを中断・再開できる」形に分解したもの。ダメージ計算・スキル効果・
## ボスAI・指定行動・勝敗判定はすべて既存のprivateヘルパー
## （_resolve_ally_action/_resolve_boss_turn_actions/_apply_boss_skill/
## _scripted_actions_for/_resolve_scripted_boss_action/_check_battle_over等）
## をそのまま呼ぶだけで、re-implementeしていない。
##
## 唯一、防御(defend)だけは新旧で挙動が異なる（ユーザー確定仕様、実機プレイ
## 改善①再開時の指示）:
## - 旧resolve_turn(): TURN START時点で、その回に選択された防御をラウンド
##   全体に対して一括で事前適用する（Step 2 confirmation #1、遡って軽減する）
##   ——無改修のまま維持。
## - 新advance_to_next_decision()系: 防御は「自分の行動順で防御を選択し、
##   その行動を実行した瞬間」から有効になり、「そのキャラクター自身の次の
##   行動順が来るまで」（ラウンド境界をまたいで）継続する。遡及適用は禁止
##   （それより前に同ラウンド内で既に受けた攻撃へは一切影響しない）。
## Round 5-2修正: 解除タイミングをresolve_pending_ally_action()（新しい
## コマンドを解決する直前）からadvance_to_next_decision()自身（そのキャラの
## SPD行動順に到達し、"pending ally"として入力待ち状態にする、まさにその
## 瞬間）へ移した——「本人の次の行動順へ到達→前回の防御をfalseへ→pending
## allyにする→UIに表示→プレイヤーが新コマンドを選ぶ」という順序を、
## is_waiting_for_ally_action()がtrueを返す時点で既にis_defending==false
## になっている、という形で正確に実装するため。つまり入力待ち状態になった
## 瞬間の時点で、まだ何も新しいコマンドを選んでいなくても、既に防御は解除
## 済みである。_resolve_ally_action()の"defend"ケース自体の
## `unit.is_defending = true`は無改修（旧resolve_turn()経路では冗長・無害、
## 新経路では防御を選んだ場合の唯一の設定箇所）。
## かばう(protecting_ally_id)・カウンター(counter_pending_this_turn/
## active_counter_skill)の意味は今回変更していない——ユーザーが明示的に
## 変更を求めたのは防御のみのため、両者とも旧来どおり「ラウンド境界で
## 一括リセット」のまま。
##
## REWINDとの関係（Round 5-2で修正）: snapshot()/restore()は_round_cursor/
## _round_turn_start_firedを含む全状態を保存・復元する。呼び出し側
## （RBMCreatorTestSession/RBMChallengeSession）は「スナップショットは常に
## そのTurnの処理が一切始まっていない、純粋な境界状態（is_at_fresh_turn_
## boundary()がtrueを返す瞬間——turn_start指定行動もボスの先制行動も一切
## 実行されていない、_round_cursor==0かつ_round_turn_start_fired==false）
## でのみ取得する」という規律を守る。advance_to_next_decision()に新設した
## stop_before_turn_processing引数は、ラウンドが繰り上がった直後（そのTurnの
## 処理へ入る直前）を追加の一時停止点として使えるようにする——これにより、
## 1回の外部呼び出し（例: 味方の入力を解決した直後の自動継続）が複数のTurn
## 境界を一気にまたいで処理してしまう場合でも、呼び出し側は横切った各境界
## ごとに正しいタイミングでsnapshot()できる（RBMCreatorTestSession.advance()
## 参照）。「Turn Nへ REWIND」は、そのTurnのturn_start_interruptより前・
## ボスAI行動より前・味方行動より前・SPD進行より前の、Turn Nが絶対的に
## 何も処理されていない状態へ完全に戻り、同じRNG stateから再実行すれば
## turn_start_interruptを含め同じ結果を再現する。

var party: Array[RBMUnit] = []
var boss: RBMUnit
var boss_def: Dictionary = {}

## Party-wide duration effects (防御強化 / 鉄壁). Same shape as RBMUnit.timed_effects.
var party_timed_effects: Dictionary = {}

## Computed once at construction (SPD never changes mid-battle in Phase 1 — no
## SPD buffs/debuffs exist) and then simply cycled every turn.
var turn_order: Array[String] = []

var current_turn: int = 1
var battle_over: bool = false
var winner: String = ""

## 新方式（advance_to_next_decision()/resolve_pending_ally_action()）専用の
## ラウンド内カーソル。resolve_turn()（旧・一括解決）は一切参照しない。
## _round_cursor: turn_orderの何番目のスロットまで処理済みか。
## _round_turn_start_fired: このラウンドのturn_start_interruptを既に処理
## 済みか（未処理ならadvance_to_next_decision()が最初にこれを片付ける）。
var _round_cursor: int = 0
var _round_turn_start_fired: bool = false

## =============================================================================
## HARDCORE Creator「攻撃（action_sequence）」— ボスAI評価用の履歴・実行時状態。
## boss_def["action_sequence"]が空ならこれらは一切参照されない（既存SIMPLE
## 経路は完全に無改修のまま、_resolve_boss_turn_actions()の分岐参照）。
##
## 2026-09-05全面再設計: 旧「行動パターン」（優先度順に評価される複数条件・
## 複数行動ステップ・発動確率・Cooldown・瞬間条件を持つ"パターン"）を廃止
## し、「行動する順番に並んだ攻撃スロット」を毎ターン1つだけ実行するラウンド
## ロビン方式へ全面移行した。瞬間条件（〜になった瞬間、対応するイベント
## キュー・瞬間発動後の2択）は新仕様に一切存在しない（RBMActionPatternRules
## 冒頭コメント参照——瞬間条件は旧「行動パターン」固有の機能で、行動パターン
## 自体が廃止されたため、対応するキュー処理（_instant_event_queue等）も
## 完全に削除した）。発動確率・Cooldownも廃止（使用回数のみ配置スロット
## 単位で残す）。
## =============================================================================
##
## 条件判定用の「直近の状態」履歴。_boss_has_acted/_boss_has_been_hitは
## 「まだ一度も発生していない」を明示的に区別するガード——例えば戦闘開始
## 直後（1ターン目、ボスがまだ一度も攻撃を受けていない）は、"weak_hit"
## （弱点を突かれた）条件は"まだ何も受けていないからfalse"であるべきで、
## _boss_last_hit_was_weakの初期値がfalseなのと区別がつかなくなることを
## 防ぐ。
var _boss_has_acted: bool = false
var _boss_last_used_skill_id: String = ""
var _boss_has_been_hit: bool = false
var _boss_last_received_skill_id: String = ""  # 通常攻撃を受けた直後は""のまま（v0.1-B §10「通常攻撃は攻撃スキルではない」に整合）。
var _boss_last_received_attribute: RBMConstants.Attribute = RBMConstants.Attribute.NEUTRAL
var _boss_last_hit_was_weak: bool = false

## HARDCORE新方式: action_sequenceの中で「次にスキャンを開始する位置」。
## 毎ターン、この位置から配列を最大size()回だけ走査し、最初に発動可能
## （条件成立かつ使用回数上限未到達）なスロットを見つけたら、そのスロット
## だけを実行してカーソルを(そのスロットのindex+1)へ進める。一周して1つも
## 発動可能なスロットが無ければこのターンは何もせず、カーソルは据え置く
## （_resolve_hardcore_boss_turn()参照）。戦闘開始時は必ず0（先頭）から
## 開始する。ボス定義（Definition/保存JSON）には一切保存しない——戦闘
## セッション内でのみ意味を持つ実行時状態。
var _boss_action_cursor: int = 0
## 配置スロット固有の使用回数状態。slot_id(String) -> int（累計使用回数）。
## 旧pattern_use_countsと同じ「戦闘セッション開始時に必ず空のまま初期化
## される、ボス定義には保存しない実行時状態」という位置づけを踏襲する
## ——同じskill_idを複数の配置スロットで再利用しても、slot_idで個別に
## キー付けされるためそれぞれ独立してカウントされる（§8確定仕様）。
var _slot_use_counts: Dictionary = {}

var rng: RandomNumberGenerator

func _init(ally_defs: Array[Dictionary], p_boss_def: Dictionary, rng_seed: int = 0) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var next_id := 0
	for def in ally_defs:
		party.append(RBMDataLoader.unit_from_ally_def(def, next_id))
		next_id += 1
	boss_def = p_boss_def
	boss = RBMDataLoader.unit_from_boss_def(p_boss_def)
	turn_order = _compute_turn_order()

## v0.1-B §10 (confirmed): SPD descending; equal SPD favors an ally over the boss;
## no random tie-break. Allies never share SPD with each other in the fixed
## roster, so the only realistic tie is "one ally vs the boss".
func _compute_turn_order() -> Array[String]:
	var entries: Array[Dictionary] = []
	for unit in party:
		entries.append({"token": "ally:%d" % unit.id, "spd": unit.spd, "is_ally": true, "tiebreak": unit.id})
	entries.append({"token": "boss", "spd": boss.spd, "is_ally": false, "tiebreak": 0})
	entries.sort_custom(_entry_is_before)
	var order: Array[String] = []
	for entry in entries:
		order.append(str(entry["token"]))
	return order

func _entry_is_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["spd"]) != int(b["spd"]):
		return int(a["spd"]) > int(b["spd"])
	if bool(a["is_ally"]) != bool(b["is_ally"]):
		return bool(a["is_ally"])
	return int(a["tiebreak"]) < int(b["tiebreak"])

## Phase 3.5 Step 4 §10/§18: 表示専用のturnタグ付けヘルパー。entryへ
## "turn":current_turn を追加するだけで、既存のどのフィールドも変更しない
## ——ダメージ計算・SP・対象判定・勝敗判定には一切影響しない、純粋な追加
## メタデータ（Step 3の"action_voided"マーカーと同じ性質の変更）。
## UI層（累積ログ/最新戦闘情報）が、1回の呼び出しがラウンド境界を
## またいだ場合でも各行を正しいターン番号へ分類し、REWINDで戻った先より
## 後のターンのログ行だけを正確に除去できるようにするための唯一の判断
## 材料。current_turnを読むタイミングは常に「そのentryがまさに生成された
## 瞬間」——advance_to_next_decision()はラウンド繰り上げのたびcurrent_turn
## を増分するため、繰り上げ前に追加されたentryは古いターン番号を、繰り上げ
## 後に追加されたentryは新しいターン番号を、それぞれ正しく受け取る。

## Presentation metadata only: detached values, no RNG or battle-state writes.
## A resolved batch may contain multiple boss actions; each impact needs its own HUD state.
func presentation_state() -> Dictionary:
	var allies := {}
	for unit in party:
		allies[str(unit.id)] = _presentation_unit_state(unit)
	return {
		"turn": current_turn, "battle_over": battle_over, "winner": winner,
		"boss": _presentation_unit_state(boss), "party": allies,
		"party_timed_effects": party_timed_effects.duplicate(true),
	}

func _presentation_unit_state(unit: RBMUnit) -> Dictionary:
	return {
		"id": unit.id, "character_id": unit.character_id, "display_name": unit.display_name,
		"hp": unit.hp, "max_hp": unit.max_hp, "sp": unit.sp, "max_sp": unit.max_sp,
		"is_downed": unit.is_downed(), "is_defending": unit.is_defending,
		"counter_pending": unit.counter_pending_this_turn,
		"protecting_ally_id": unit.protecting_ally_id,
		"next_attack_bonus_multiplier": unit.next_attack_bonus_multiplier,
		"timed_effects": unit.timed_effects.duplicate(true),
	}


func _log_entry(entry: Dictionary) -> Dictionary:
	entry["turn"] = current_turn
	entry["visual_state"] = presentation_state()
	return entry

func _unit_by_id(id: int) -> RBMUnit:
	for unit in party:
		if unit.id == id:
			return unit
	return null

func _unit_for_token(token: String) -> RBMUnit:
	if token == "boss":
		return boss
	return _unit_by_id(int(token.substr(5)))

func _living_allies() -> Array[RBMUnit]:
	var out: Array[RBMUnit] = []
	for unit in party:
		if not unit.is_downed():
			out.append(unit)
	return out

func _find_skill(unit: RBMUnit, skill_id: String) -> Dictionary:
	for skill in unit.skills:
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}

func _check_battle_over() -> void:
	if battle_over:
		return
	if boss.is_downed():
		battle_over = true
		winner = "ally"
		return
	if _living_allies().is_empty():
		battle_over = true
		winner = "boss"

## Turn REWIND (Step 4 §9, per the prior technical investigation's 案B):
## RBMBattle provides only the generic capture/restore primitive here — it has
## no opinion about how many snapshots exist, when they're taken, or what
## "REWIND" means to a player. That policy belongs entirely to the caller
## (Creator TEST BATTLE's own history manager); this class doesn't even know
## such a caller exists. §9-6 requires snapshotting immediately before each
## resolve_turn() call for that turn's own "TURN N開始時点" (so a restore lands
## before that turn's turn_start_interrupt has fired) — resolve_turn() itself
## needed no change to make this true, since it is a single synchronous call
## with no other code path mutating state in between (see the technical
## investigation's 調査5).
##
## Captures every field enumerated in the technical investigation's 調査1 as
## mutable Phase 1 battle state. Dictionary/Array-valued fields are always
## duplicate(true)'d on the way in and out, so a snapshot can never alias live
## battle state (§9-8) — advancing the battle after taking a snapshot must
## never retroactively change that snapshot, and restoring from one must never
## let the live battle and the stored snapshot end up sharing the same nested
## Dictionary.
func snapshot() -> Dictionary:
	var units := {}
	units["boss"] = _snapshot_unit(boss)
	for unit in party:
		units[str(unit.id)] = _snapshot_unit(unit)
	return {
		"current_turn": current_turn,
		"battle_over": battle_over,
		"winner": winner,
		"rng_state": rng.state,
		"party_timed_effects": party_timed_effects.duplicate(true),
		"units": units,
		# 実機プレイ改善①: 新方式(advance_to_next_decision())専用のラウンド内
		# カーソル。呼び出し側は常にラウンド境界でのみsnapshot()する規律の
		# もと、これらは常に(0, false)のはずだが、primitive自体の
		# 自己完結性のため防御的に含める（上のクラス冒頭コメント参照）。
		"round_cursor": _round_cursor,
		"round_turn_start_fired": _round_turn_start_fired,
		# HARDCORE AIの履歴・実行時状態もREWINDの対象——巻き戻したら使用回数・
		# 現在位置カーソル・「前回」系の履歴も、その時点の状態へ正しく戻ら
		# なければならない（REWINDが「ボス定義には保存しないが、戦闘セッション
		# 内では他のHP/SP等と全く同じ扱いの一時状態」を巻き戻す、という一貫
		# した契約——§21確定「REWINDすると次に使う攻撃だけズレる、という
		# 不具合を絶対に残さない」）。
		"boss_has_acted": _boss_has_acted,
		"boss_last_used_skill_id": _boss_last_used_skill_id,
		"boss_has_been_hit": _boss_has_been_hit,
		"boss_last_received_skill_id": _boss_last_received_skill_id,
		"boss_last_received_attribute": int(_boss_last_received_attribute),
		"boss_last_hit_was_weak": _boss_last_hit_was_weak,
		"boss_action_cursor": _boss_action_cursor,
		"slot_use_counts": _slot_use_counts.duplicate(true),
	}

func _snapshot_unit(unit: RBMUnit) -> Dictionary:
	return {
		"hp": unit.hp,
		"sp": unit.sp,
		"is_defending": unit.is_defending,
		"timed_effects": unit.timed_effects.duplicate(true),
		"next_attack_bonus_multiplier": unit.next_attack_bonus_multiplier,
		"counter_pending_this_turn": unit.counter_pending_this_turn,
		# Stored as just the id and re-resolved against unit.skills on restore
		# (rather than duplicating the whole skill Dictionary) -- skills are
		# immutable template data shared by reference throughout the battle,
		# so there is nothing to deep-copy, and this avoids ever aliasing a
		# skill Dictionary between a snapshot and the live unit.
		"active_counter_skill_id": str(unit.active_counter_skill.get("id", "")),
		"protecting_ally_id": unit.protecting_ally_id,
	}

## Restores every field snapshot() captured, writing IN PLACE onto the
## existing party/boss RBMUnit objects (never reconstructing them) so any
## outside reference to a specific unit stays valid across a REWIND.
func restore(state: Dictionary) -> void:
	current_turn = int(state["current_turn"])
	battle_over = bool(state["battle_over"])
	winner = str(state["winner"])
	rng.state = int(state["rng_state"])
	party_timed_effects = (state["party_timed_effects"] as Dictionary).duplicate(true)
	var units: Dictionary = state["units"]
	_restore_unit(boss, units["boss"])
	for unit in party:
		_restore_unit(unit, units[str(unit.id)])
	# 実機プレイ改善①: 新方式専用のラウンド内カーソル。d.get(key,default)で
	# 読むのは、このprimitive自体は将来ラウンド境界以外でsnapshot()される
	# 呼び出しがあっても状態が壊れないための防御であり、旧形式の永続化
	# データとの互換目的ではない（REWINDスナップショットはセッション内の
	# メモリ上履歴のみで、ディスクへ永続化されることは無い）。
	_round_cursor = int(state.get("round_cursor", 0))
	_round_turn_start_fired = bool(state.get("round_turn_start_fired", false))
	# d.get(key,default)で読む理由はround_cursor等と同じ（鉄則3、HARDCORE AI
	# を一切使わない戦闘のsnapshot()にはそもそもこれらのキーが意味を持たない
	# 値のまま含まれるだけで、欠けていても安全なデフォルトへフォールバック
	# する）。
	_boss_has_acted = bool(state.get("boss_has_acted", false))
	_boss_last_used_skill_id = str(state.get("boss_last_used_skill_id", ""))
	_boss_has_been_hit = bool(state.get("boss_has_been_hit", false))
	_boss_last_received_skill_id = str(state.get("boss_last_received_skill_id", ""))
	_boss_last_received_attribute = int(state.get("boss_last_received_attribute", RBMConstants.Attribute.NEUTRAL)) as RBMConstants.Attribute
	_boss_last_hit_was_weak = bool(state.get("boss_last_hit_was_weak", false))
	_boss_action_cursor = int(state.get("boss_action_cursor", 0))
	_slot_use_counts = (state.get("slot_use_counts", {}) as Dictionary).duplicate(true)

func _restore_unit(unit: RBMUnit, data: Dictionary) -> void:
	unit.hp = int(data["hp"])
	unit.sp = int(data["sp"])
	unit.is_defending = bool(data["is_defending"])
	unit.timed_effects = (data["timed_effects"] as Dictionary).duplicate(true)
	unit.next_attack_bonus_multiplier = float(data["next_attack_bonus_multiplier"])
	unit.counter_pending_this_turn = bool(data["counter_pending_this_turn"])
	var counter_skill_id := str(data.get("active_counter_skill_id", ""))
	unit.active_counter_skill = _find_skill(unit, counter_skill_id) if counter_skill_id != "" else {}
	unit.protecting_ally_id = int(data["protecting_ally_id"])

## ⚠️ LEGACY API — Codex最終差分レビュー⑪により明示: このメソッドは
## HARDCORE Creatorのボス行動選択（_resolve_boss_turn_actions()経由の
## boss_def["action_sequence"]評価）も含め、ボスAI周りの実際の判定ロジック
## そのものは新方式（advance_to_next_decision()/resolve_pending_ally_action()）
## と完全に共有している（このクラス冒頭コメント参照——共有ヘルパー経由）。
## 現在、実プロダクトコード（TEST BATTLE/Clear Check/CHALLENGE）はこのAPIを
## 一切使用せず新方式のみを使う。既存の504件超の素のバトルコアテストが
## この一括解決契約に直接依存しているため無改修のまま残しているだけで、
## 新規の製品コードからは絶対に呼び出さないこと。HARDCORE Creatorの仕様を
## 保証するテスト（tests/bossmaker/test_rbm_advanced_*.gd）は、このAPIを
## 一切使わず全てadvance_to_next_decision()/resolve_pending_ally_action()を
## 使う。
##
## ally_actions: Dictionary[String unit_id -> Dictionary action]. A missing entry,
## or one with an unrecognized "type", is NOT a implicit attack (Step 2 fix #3) —
## it resolves as an explicit no-op failure ("unspecified_action" / "invalid_action")
## so a broken caller can never silently deal damage it never asked for.
## action shapes: {"type":"attack"} / {"type":"defend"} /
##                {"type":"skill","skill_id":String,"target_id":int}
func resolve_turn(ally_actions: Dictionary) -> Dictionary:
	var log: Array[Dictionary] = []
	if battle_over:
		return {"log": log, "battle_over": true, "winner": winner, "turn": current_turn}

	# The turn number this call is resolving — captured before any mutation, and
	# returned as-is regardless of whether current_turn advances afterward (Step 2
	# fix #5: "turn" always means "the turn just resolved", never the next one).
	var resolved_turn := current_turn

	# TURN START — reset per-turn postures, then pre-apply "防御" (only) for the
	# WHOLE turn: it is a locked-in base command, not resolved lazily at the acting
	# unit's own turn-order slot, so a low-SPD defender still reduces an
	# earlier-acting boss's damage that same turn (Step 2 confirmation #1).
	# かばう (a skill, not a base command) is deliberately NOT pre-applied here —
	# it only takes effect once the tank's own action actually resolves below
	# (Step 2 fix #2).
	for unit in party:
		unit.is_defending = false
		unit.protecting_ally_id = -1
	for id_key in ally_actions.keys():
		var action: Dictionary = ally_actions[id_key]
		var unit := _unit_by_id(int(id_key))
		if unit == null or unit.is_downed():
			continue
		if str(action.get("type", "")) == "defend":
			unit.is_defending = true

	# 割り込み型・ターン開始時 指定行動 — fires after 防御 postures are already
	# locked in above (so it still benefits from "defend reduces damage from
	# the very first hit this turn"), SPD-ignoring, and does NOT replace the
	# boss's own NORMAL ACTION PHASE turn below.
	for scripted in _scripted_actions_for(resolved_turn, "turn_start_interrupt"):
		if battle_over:
			break
		log.append(_log_entry(_resolve_scripted_boss_action(scripted)))
		_check_battle_over()

	# NORMAL ACTION PHASE
	for token in turn_order:
		if battle_over:
			break
		var acting := _unit_for_token(token)
		if acting == null or acting.is_downed():
			continue
		if acting.is_ally:
			var id_key := str(acting.id)
			if not ally_actions.has(id_key):
				log.append(_log_entry({"actor": acting.id, "action": "none", "failed": true, "reason": "unspecified_action"}))
			else:
				log.append(_log_entry(_resolve_ally_action(acting, ally_actions[id_key])))
		else:
			# May append more than one entry: Step 3 最終修正指示 §1 -- every
			# 置換型 scripted action configured for this turn fires (not just
			# the first), and none of them additionally triggers the boss's
			# ordinary normal action.
			for entry in _resolve_boss_turn_actions(acting):
				log.append(_log_entry(entry))
		_check_battle_over()

	# 割り込み型・ターン終了時 指定行動 — an SPD-ignoring EXTRA boss action, after
	# every living combatant (including the boss's own NORMAL ACTION PHASE turn)
	# has acted this turn, but before turn-scoped state clears below.
	for scripted in _scripted_actions_for(resolved_turn, "turn_end_interrupt"):
		if battle_over:
			break
		log.append(_log_entry(_resolve_scripted_boss_action(scripted)))
		_check_battle_over()

	# TURN END — every turn-scoped posture clears here, regardless of whether it
	# ever triggered, so state is fully at rest between resolve_turn() calls
	# (Step 2 fix #4).
	for unit in party:
		unit.counter_pending_this_turn = false
		unit.active_counter_skill = {}
		unit.is_defending = false
		unit.protecting_ally_id = -1

	if not battle_over:
		current_turn += 1

	return {"log": log, "battle_over": battle_over, "winner": winner, "turn": resolved_turn}

# =============================================================================
# 実機プレイ改善①「戦闘方式を後期UNDERDESK方式へ統一」— SPD順に1体ずつ、
# 即座に解決する新方式のエントリポイント。resolve_turn()（上記）とは別の、
# 追加のAPI（クラス冒頭のコメント参照）。
# =============================================================================

## 現在のラウンドで、入力を必要とせず自動で解決できるスロット
## （turn_start指定行動・戦闘不能な参加者のスキップ・ボスの番）をすべて
## 連続して解決し、次のいずれかで停止する:
##   (a) battle_overがtrueになった
##   (b) 生存している味方の番になった（呼び出し側がresolve_pending_ally_
##       action()でその行動を渡すまで、それ以上は進めない）
##   (c) stop_before_turn_processing==trueの時だけ: ラウンドが繰り上がり、
##       次のTurnの処理が一切始まっていない、純粋な境界状態に達した
##       （Round 5-2で追加。呼び出し側がこの瞬間にsnapshot()を取れるように
##       するための追加の一時停止点——REWINDが正しい位置に戻るために必須。
##       is_at_fresh_turn_boundary()参照）。
## 停止した後にもう一度呼んでも安全（その時点で何もすることが無ければ
## 即座に空配列を返す）。ラウンドの最後のスロットまで処理し終えたら、
## turn_end指定行動→ラウンド境界の後始末（かばう/カウンターのリセットのみ
## ——防御は対象外、クラス冒頭コメント参照）→Turnを進める→（(c)で停止しな
## ければ）次ラウンドのturn_start指定行動、と自動的に連続して処理し続ける
## （生存している味方が1人でもいる限り、そのラウンド内で必ずその味方の番に
## 行き当たるため、無限にラウンドをまたぎ続けることはない）。
## 戻り値は、この呼び出しの中で自動解決されたスロットぶんのログをすべて
## 順番どおりに含む配列（何も自動解決しなければ空配列）。
func advance_to_next_decision(stop_before_turn_processing: bool = false) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	while true:
		if battle_over:
			return log

		if not _round_turn_start_fired:
			# TURN START: かばうのみラウンド境界でリセット（防御は対象外
			# ——このTurnで実際にそのキャラクター自身の番になった瞬間に
			# 個別にリセットする、下記参照）。
			for unit in party:
				unit.protecting_ally_id = -1
			for scripted in _scripted_actions_for(current_turn, "turn_start_interrupt"):
				log.append(_log_entry(_resolve_scripted_boss_action(scripted)))
				_check_battle_over()
				if battle_over:
					return log
			_round_turn_start_fired = true

		if _round_cursor < turn_order.size():
			var token: String = turn_order[_round_cursor]
			var acting := _unit_for_token(token)
			if acting == null or acting.is_downed():
				_round_cursor += 1
				continue
			if acting.is_ally:
				# Round 5-2修正: 「本人の次のSPD行動順へ到達→前回のis_defending
				# をfalse→pending allyにする」の順序どおり、入力待ち状態へ
				# なる、まさにこの瞬間に防御を解除する——新しいコマンドを
				# 選ぶより前に、既にfalseになっていなければならない
				# （resolve_pending_ally_action()側では二度と触らない）。
				acting.is_defending = false
				return log  # 生存している味方の番 — 入力待ちで停止する。
			for entry in _resolve_boss_turn_actions(acting):
				log.append(_log_entry(entry))
			_round_cursor += 1
			_check_battle_over()
			if battle_over:
				return log
			continue

		# このラウンドの全スロットを処理し終えた — TURN END → 次ラウンドへ。
		for scripted in _scripted_actions_for(current_turn, "turn_end_interrupt"):
			log.append(_log_entry(_resolve_scripted_boss_action(scripted)))
			_check_battle_over()
			if battle_over:
				return log
		for unit in party:
			unit.counter_pending_this_turn = false
			unit.active_counter_skill = {}
			unit.protecting_ally_id = -1
		current_turn += 1
		_round_cursor = 0
		_round_turn_start_fired = false
		if stop_before_turn_processing:
			return log  # 次Turnの純粋な境界状態 — 呼び出し側がここでsnapshot()できる。
		# ループの先頭へ戻り、次ラウンドのturn_start指定行動から続ける。
	return log  # 到達しない（while trueの内部で必ずreturnする）— GDScriptの
	            # 静的チェッカー向けの形式的なフォールバックのみ。

## advance_to_next_decision()が「生存している味方の番」で停止しているかどうか。
func is_waiting_for_ally_action() -> bool:
	if battle_over or not _round_turn_start_fired or _round_cursor >= turn_order.size():
		return false
	var acting := _unit_for_token(turn_order[_round_cursor])
	return acting != null and acting.is_ally and not acting.is_downed()

## is_waiting_for_ally_action()がtrueの間だけ意味を持つ、入力待ちの味方のid。
## それ以外は-1。
func pending_ally_id() -> int:
	if not is_waiting_for_ally_action():
		return -1
	return _unit_for_token(turn_order[_round_cursor]).id

## Round 5-2新設: 現在のTurnの処理が一切始まっていない、純粋な境界状態
## （turn_start指定行動もボスの先制行動も一切実行されていない）かどうか。
## REWINDスナップショットは必ずこの状態でのみ取得する（RBMCreatorTestSession.
## advance()参照）——このクエリ自体は読み取り専用で、状態を一切変更しない。
func is_at_fresh_turn_boundary() -> bool:
	return not battle_over and not _round_turn_start_fired and _round_cursor == 0

## Round 5-2新設: 新方式のラウンド内カーソル状態を外部から直接検証できる
## ようにする、読み取り専用の公開クエリ（内部フィールド自体の意味・書き込み
## ロジックは無改修）。REWINDテストが「行動済みキャラの二重行動なし・キャラ
## を飛ばさない・ボスが余分に行動しない」ことをカーソル値そのものから直接
## 確認できるようにするための最小限の追加。
func round_cursor() -> int:
	return _round_cursor

func round_turn_start_fired() -> bool:
	return _round_turn_start_fired

## HARDCORE Creator「攻撃（action_sequence）」の現在位置カーソルを外部から
## 直接検証できるようにする、読み取り専用の公開クエリ（round_cursor()と
## 同じ位置づけ——テストが「§17: 一周して発動可能なスロットが無ければ
## カーソルは据え置かれる」ことをカーソル値そのものから直接確認できる
## ようにするための最小限の追加）。
func hardcore_action_cursor() -> int:
	return _boss_action_cursor

## is_waiting_for_ally_action()がtrueの時だけ呼べる。現在入力待ちの味方の
## 行動を即座に解決し、HP/SP/状態をその場で反映してからカーソルを1つ進める。
## 呼び出し側は、この直後にもう一度advance_to_next_decision()を呼んで
## 続きを進めること（ボスの番・次ラウンドへの繰り上げ等を自動で処理する）。
## Round 5-2修正: is_defending==falseへのリセットは、もうここでは行わない
## ——このキャラクターが入力待ちになった瞬間（advance_to_next_decision()の
## 該当箇所）で既に完了している必要があるため、そちらへ移した。ここでは
## 単に、既にfalseになっている（か、defendが選ばれれば直後にtrueへ戻る）
## is_defendingを前提として、新しい行動をそのまま解決するだけでよい。
##
## Phase 3.5 Step 3 §3の修正: 戻ってきたエントリが"action_voided":true
## （_resolve_ally_action()/_resolve_ally_skill()が、SP/対象等の検証で
## 何も状態を変更せずに早期returnした4箇所——invalid_action/unknown_skill/
## invalid_target/insufficient_sp——にのみ立つマーカー。既存の"failed"は
## ログ表示用の意味のまま無改修）の場合、「行動は成立しなかった＝まだこの
## キャラクターの番」として_round_cursorを進めない。同じ味方が再度
## is_waiting_for_ally_action()の対象のまま残るため、呼び出し側
## （RBMCreatorTestSession/RBMChallengeSession）は無改修でそのまま動作する
## ——次にadvance_to_next_decision()を呼んでも新しい境界は横切らず、
## 同じ味方の入力待ちへすぐ戻るだけ。
func resolve_pending_ally_action(action: Dictionary) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	if not is_waiting_for_ally_action():
		return log
	var acting := _unit_for_token(turn_order[_round_cursor])
	var entry := _resolve_ally_action(acting, action)
	log.append(_log_entry(entry))
	if bool(entry.get("action_voided", false)):
		return log
	_round_cursor += 1
	_check_battle_over()
	return log

## Step 2 fix #3: an unrecognized action "type" must never be treated as an attack.
func _resolve_ally_action(unit: RBMUnit, action: Dictionary) -> Dictionary:
	var action_type := str(action.get("type", ""))
	match action_type:
		"attack":
			return _resolve_normal_attack(unit)
		"defend":
			# 実機プレイ改善①: 旧resolve_turn()経路ではTURN STARTで既に
			# is_defending=trueへ設定済み（この行は冗長・無害）。新
			# advance_to_next_decision()系ではここが唯一の設定箇所——Round 5-2
			# 修正により、このキャラクター自身が入力待ちになった瞬間
			# （advance_to_next_decision()側）で前回のis_defendingは既に
			# falseへ戻されている。ここで防御が選ばれれば、それを再びtrue
			# にする。
			unit.is_defending = true
			return {"actor": unit.id, "action": "defend"}
		"skill":
			return _resolve_ally_skill(unit, str(action.get("skill_id", "")), int(action.get("target_id", -1)))
		_:
			# Phase 3.5 Step 3 §3: 何も状態を変更していない早期return——
			# resolve_pending_ally_action()がaction_voided:trueを見て
			# _round_cursorを進めないための唯一の判断材料。
			return {"actor": unit.id, "action": "none", "failed": true, "reason": "invalid_action", "raw_type": action_type, "action_voided": true}

## v0.1-B §7: 無属性・ATK×1.0・SP消費0・使用でSP+10（最大SP超えない）。
## v0.1-B §10: 通常攻撃は「攻撃スキル」ではない — 居合の対象外。
func _resolve_normal_attack(unit: RBMUnit) -> Dictionary:
	var result := {"actor": unit.id, "action": "attack"}
	var amount := _compute_and_apply_damage(unit, boss, RBMConstants.NORMAL_ATTACK_ATK_MULTIPLIER, RBMConstants.Attribute.NEUTRAL, false)
	result["target"] = "boss"
	result["amount"] = amount
	if unit.has_sp_resource():
		unit.sp = mini(unit.max_sp, unit.sp + RBMConstants.NORMAL_ATTACK_SP_GAIN)
	_check_battle_over()
	return result

func _resolve_ally_skill(unit: RBMUnit, skill_id: String, target_id: int) -> Dictionary:
	var skill := _find_skill(unit, skill_id)
	var result := {"actor": unit.id, "action": "skill", "skill_id": skill_id}
	# Phase 3.5 Step 3 §3: これ以降の3つの早期returnはいずれも、この関数が
	# まだ一切party/boss/unitの状態を変更していない時点で発生する——
	# resolve_pending_ally_action()が"action_voided":trueを見て手番を消費
	# しない判断材料として使う唯一のマーカー（既存の"failed"/"reason"は
	# ログ表示用の意味のまま無改修）。
	if skill.is_empty():
		result["failed"] = true
		result["reason"] = "unknown_skill"
		result["action_voided"] = true
		return result

	var effect := str(skill.get("effect", ""))

	# Step 2 fix #7: validate the target BEFORE spending SP. A since-downed
	# target means the whole action is 不発 (void) — no SP cost, no redirect.
	var validation := _validate_skill_target(unit, skill, effect, target_id)
	if not bool(validation.get("valid", true)):
		result["failed"] = true
		result["reason"] = str(validation.get("reason", "invalid_target"))
		result["action_voided"] = true
		return result

	var cost := int(skill.get("sp_cost", 0))
	if unit.has_sp_resource():
		if unit.sp < cost:
			result["failed"] = true
			result["reason"] = "insufficient_sp"
			result["action_voided"] = true
			return result
		unit.sp -= cost

	match effect:
		"damage":
			var atk_mult := float(skill.get("atk_multiplier", 1.0))
			var attribute := RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
			result["target"] = "boss"
			result["amount"] = _compute_and_apply_damage(unit, boss, atk_mult, attribute, true, skill_id)
		"heal":
			_resolve_heal_skill(unit, skill, target_id, result)
		"sp_recover_single_no_self":
			_resolve_sp_recover_single(unit, skill, target_id, result)
		"sp_recover_all_no_self":
			_resolve_sp_recover_all(unit, skill, result)
		"buff_atk_self":
			var mult := float(skill.get("buff_multiplier", 1.0))
			var duration := int(skill.get("duration_turns", 1))
			RBMConstants.set_timed_effect(unit.timed_effects, "atk_buff", current_turn, duration, mult)
		"buff_next_attack":
			unit.next_attack_bonus_multiplier = float(skill.get("buff_multiplier", 2.0))
		"counter_stance":
			unit.counter_pending_this_turn = true
			unit.active_counter_skill = skill
		"guard_boost":
			var duration := int(skill.get("duration_turns", 1))
			var rate := float(skill.get("new_rate", RBMConstants.DEFEND_BOOSTED_REDUCTION))
			RBMConstants.set_timed_effect(party_timed_effects, "guard_boost", current_turn, duration, rate)
		"party_damage_reduction":
			var duration := int(skill.get("duration_turns", 1))
			var rate := float(skill.get("reduction_rate", RBMConstants.IRON_WALL_REDUCTION))
			RBMConstants.set_timed_effect(party_timed_effects, "iron_wall", current_turn, duration, rate)
		"guard_redirect":
			# Step 2 fix #2: かばう only takes effect here, at the tank's own
			# action resolution — never pre-applied at TURN START.
			unit.protecting_ally_id = target_id
			result["protecting"] = target_id
		_:
			pass

	_check_battle_over()
	return result

## Step 2 fix #7: returns whether `skill`'s target is currently valid, checked
## BEFORE any SP is spent. Effects with no meaningful external target (self/
## party-wide effects) are always valid. TOCTOU is not a concern — nothing
## mutates state between this check and the actual application in the same
## synchronous call.
func _validate_skill_target(caster: RBMUnit, skill: Dictionary, effect: String, target_id: int) -> Dictionary:
	match effect:
		"damage":
			if boss.is_downed():
				return {"valid": false, "reason": "target_downed"}
		"heal":
			match str(skill.get("target", "ally_chosen")):
				"ally_chosen", "ally_chosen_no_self":
					var no_self := str(skill.get("target", "")) == "ally_chosen_no_self"
					var target := _unit_by_id(target_id)
					if target == null or target.is_downed() or (no_self and target_id == caster.id):
						return {"valid": false, "reason": "invalid_target"}
				_:
					pass  # "ally_all" always has some valid subset, even if empty.
		"sp_recover_single_no_self":
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed() or target_id == caster.id or not target.has_sp_resource():
				return {"valid": false, "reason": "invalid_target"}
		"guard_redirect":
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed():
				return {"valid": false, "reason": "invalid_target"}
		_:
			pass
	return {"valid": true}

## Phase 3.5 Step 3 §2: 唯一の公開クエリ——UI層（TEST/Clear Check/CHALLENGE
## いずれも）が対象選択候補を絞り込む際、この関数だけを呼ぶ。判定内容は
## _validate_skill_target()をそのまま呼ぶだけで、UI側に判定条件を複製・
## 再実装させない（「Battle側の対象判定を正とする」という確定仕様の直接的な
## 実装）。読み取り専用——一切の状態を変更しない。無効なcaster_id/skill_idは
## 安全にfalseを返す（そのスキルの候補には決して現れない）。
func is_valid_skill_target(caster_id: int, skill_id: String, target_id: int) -> bool:
	var caster := _unit_by_id(caster_id)
	if caster == null:
		return false
	var skill := _find_skill(caster, skill_id)
	if skill.is_empty():
		return false
	var effect := str(skill.get("effect", ""))
	return bool(_validate_skill_target(caster, skill, effect, target_id).get("valid", true))

func _resolve_heal_skill(caster: RBMUnit, skill: Dictionary, target_id: int, result: Dictionary) -> void:
	var amount := int(skill.get("heal_amount", 0))
	match str(skill.get("target", "ally_chosen")):
		"ally_chosen", "ally_chosen_no_self":
			var no_self := str(skill.get("target", "")) == "ally_chosen_no_self"
			var target := _unit_by_id(target_id)
			if target == null or target.is_downed() or (no_self and target_id == caster.id):
				result["failed"] = true
				result["reason"] = "invalid_target"
			else:
				result["target"] = target.id
				result["amount"] = target.heal(amount)
		"ally_all":
			var healed := {}
			for unit in party:
				if not unit.is_downed():
					healed[unit.id] = unit.heal(amount)
			result["healed"] = healed
		_:
			pass

func _resolve_sp_recover_single(caster: RBMUnit, skill: Dictionary, target_id: int, result: Dictionary) -> void:
	var amount := int(skill.get("sp_amount", 0))
	var target := _unit_by_id(target_id)
	if target == null or target.is_downed() or target_id == caster.id or not target.has_sp_resource():
		result["failed"] = true
		result["reason"] = "invalid_target"
		return
	var before := target.sp
	target.sp = mini(target.max_sp, target.sp + amount)
	result["target"] = target.id
	result["amount"] = target.sp - before

func _resolve_sp_recover_all(caster: RBMUnit, skill: Dictionary, result: Dictionary) -> void:
	var amount := int(skill.get("sp_amount", 0))
	var recovered := {}
	for unit in party:
		if unit.id != caster.id and not unit.is_downed() and unit.has_sp_resource():
			var before := unit.sp
			unit.sp = mini(unit.max_sp, unit.sp + amount)
			recovered[unit.id] = unit.sp - before
	result["recovered"] = recovered

func _pick_boss_normal_action() -> Dictionary:
	var candidates: Array = boss_def.get("normal_action_candidates", [])
	if candidates.is_empty():
		return {}
	return _find_skill(boss, _pick_weighted_skill_id(candidates))

## Phase 2で抽出した共有の累積重み走査（元は_pick_boss_normal_action()に
## インライン実装されていたもの、挙動は一切変更していない——candidates
## 空の早期returnとtotal_weight<=0.0の時にRNGを一切消費しない特殊ケースを
## 含め、既存のRNG消費パターンをそのまま保つ）。HARDCORE Creatorのランダム
## 攻撃スロット（kind=="random"）評価も、この同じ関数を再利用することで、
## SIMPLE→HARDCORE変換（RBMCreatorDraft._auto_populate_action_sequence_
## from_simple()、normal_action_percentagesを条件なしのランダム攻撃
## スロットへ複製）の前後でRNG消費列・選択結果が完全に一致することを
## 保証する（確定A「切替直後の戦闘内容が変化しない」の実装上の要）。
## 戻り値はskill_id（空文字列はcandidatesが空だった場合のみ）。
func _pick_weighted_skill_id(candidates: Array) -> String:
	if candidates.is_empty():
		return ""
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += float(candidate.get("weight", 1.0))
	if total_weight <= 0.0:
		return str(candidates[0].get("skill_id", ""))
	var roll := rng.randf() * total_weight
	var cumulative := 0.0
	for candidate in candidates:
		cumulative += float(candidate.get("weight", 1.0))
		if roll < cumulative:
			return str(candidate.get("skill_id", ""))
	return str(candidates[-1].get("skill_id", ""))

## v0.1-B §5 (指定行動) / Step 3 最終修正指示 §1: EVERY 置換型 scripted action
## configured for this exact turn fires, in ascending "order" — not just the
## lowest-order one — and when at least one exists, the boss's ordinary
## weighted-random normal action does NOT additionally fire that turn. With
## no 置換型 scripted for this turn, behavior is byte-for-byte the original
## Step 2 path (a single weighted-random pick).
## HARDCORE Creator確定: boss_def["action_sequence"]が空でない間は、そのボスの
## NORMAL ACTION PHASEにおける行動選択の唯一の正はHARDCORE評価器
## （_resolve_hardcore_boss_turn()、ラウンドロビン方式で1ターン1スロットを
## 実行する）になる——旧SIMPLEのreplace指定行動・normal_action_percentages
## はどちらも評価されない。これはSIMPLE→HARDCORE変換時（RBMCreatorDraft.
## _auto_populate_action_sequence_from_simple()）に変換元のreplace指定行動が
## action_sequenceへ複製済み・normal_action_percentagesも条件なしの
## フォールバックスロットへ複製済みであるため、「HARDCORE経路が唯一の正に
## なる」としても切替直後の実際の選択結果は変化しない（旧replace側を評価し
## 続けると、著者がHARDCORE側で編集した内容が旧scripted_actionsの陰に隠れて
## 反映されない「隠れた優先」状態になってしまうため、意図的にこちらを
## 優先させる設計）。
## turn_start_interrupt/turn_end_interruptはこの分岐と無関係——確定どおり
## 常に無条件で個別に発火し続ける（advance_to_next_decision()/resolve_turn()
## 自身の既存ループ、この関数の外）。
func _resolve_boss_turn_actions(unit: RBMUnit) -> Array[Dictionary]:
	var action_sequence: Array = boss_def.get("action_sequence", [])
	if not action_sequence.is_empty():
		return _resolve_hardcore_boss_turn(action_sequence)
	var replacements := _scripted_actions_for(current_turn, "replace")
	if not replacements.is_empty():
		var results: Array[Dictionary] = []
		for scripted in replacements:
			if battle_over:
				break
			results.append(_resolve_scripted_boss_action(scripted))
		return results
	var skill := _pick_boss_normal_action()
	if skill.is_empty():
		return [{"actor": "boss", "action": "none"}]
	return [_apply_boss_skill(unit, skill)]

## Applies one already-chosen boss skill and logs the result. Shared by the
## boss's ordinary NORMAL ACTION PHASE turn (via _resolve_boss_turn_actions,
## which may substitute one or more 置換型 指定行動 for the normal pick) and by
## _resolve_scripted_boss_action (割り込み型 指定行動) — both need identical
## かばう/カウンター/属性/軽減 handling, so this is the single shared body.
func _apply_boss_skill(unit: RBMUnit, skill: Dictionary) -> Dictionary:
	var result := {"actor": "boss", "action": "skill", "skill_id": str(skill.get("id", ""))}
	# Codex最終差分レビュー⑤の修正（現在も継続して有効）: ボスが実際に
	# スキルを使用する全経路が最終的に必ずこの共有関数を通る（このファイルで
	# 唯一の"skillを適用する"実装）ため、_boss_has_acted/_boss_last_used_
	# skill_idの更新はここへ一元化してある——経路を問わず一律に履歴が
	# 更新される。呼び出し元（_resolve_boss_turn_actions()のSIMPLEフォール
	# バック分岐、_resolve_scripted_boss_action()、_resolve_hardcore_boss_
	# turn()）はいずれも事前に_find_skill()/_pick_boss_normal_action()で
	# スキルが実在することを確認してからしかこの関数を呼ばない——skill_idの
	# 解決に失敗した（存在しない）ケースは呼び出し元がこの関数へ到達する前に
	# 個別に処理済みのため、ここでの更新が「実行に失敗したスキルを記録
	# する」ことには当たらない。
	_boss_has_acted = true
	_boss_last_used_skill_id = str(skill.get("id", ""))
	match str(skill.get("effect", "")):
		"damage":
			var atk_mult := float(skill.get("atk_multiplier", 1.0))
			var attribute := RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
			if str(skill.get("target", "ally_random_single")) == "ally_all":
				# Required fix #1: かばう must never apply to an all-target attack.
				var hits := {}
				for ally in party:
					if not ally.is_downed():
						hits[ally.id] = _apply_boss_hit_to_ally(ally, atk_mult, attribute, false)
				result["hits"] = hits
			else:
				var living := _living_allies()
				if living.is_empty():
					result["failed"] = true
				else:
					var target: RBMUnit = living[rng.randi_range(0, living.size() - 1)]
					var hit := _apply_boss_hit_to_ally(target, atk_mult, attribute, true)
					for key in hit.keys():
						result[key] = hit[key]
		"heal":
			result["amount"] = unit.heal(int(skill.get("heal_amount", 0)))
		"buff_atk_self":
			var mult := float(skill.get("buff_multiplier", 1.0))
			var duration := int(skill.get("duration_turns", 1))
			RBMConstants.set_timed_effect(unit.timed_effects, "atk_buff", current_turn, duration, mult)
		_:
			pass
	_check_battle_over()
	return result

## Returns every scripted 指定行動 configured for `turn`+`timing`, ordered by
## its author-specified "order" (ascending; ties keep JSON declaration order,
## since Array.sort_custom in Godot is not required to be stable, but for
## Phase 1's small fixed lists this is not a meaningfully observable gap).
func _scripted_actions_for(turn: int, timing: String) -> Array[Dictionary]:
	var all_scripted: Array = boss_def.get("scripted_actions", [])
	var matches: Array[Dictionary] = []
	for entry_variant in all_scripted:
		var entry: Dictionary = entry_variant
		if int(entry.get("turn", -1)) == turn and str(entry.get("timing", "")) == timing:
			matches.append(entry)
	matches.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return matches

func _resolve_scripted_boss_action(scripted: Dictionary) -> Dictionary:
	var skill := _find_skill(boss, str(scripted.get("skill_id", "")))
	if skill.is_empty():
		return {"actor": "boss", "action": "none", "failed": true, "reason": "unknown_skill"}
	return _apply_boss_skill(boss, skill)

## Resolves one boss attack landing on `target` — applying かばう redirection
## (single-target attacks only, per required fix #1: `allow_redirect` must be
## false for an "ally_all" hit) and カウンター interception (unrestricted — the
## spec never limits counter to single-target attacks). v0.1-B §7, §10, §16.
## Returns a partial log dict to be merged into the caller's result.
func _apply_boss_hit_to_ally(target: RBMUnit, atk_mult: float, attribute: RBMConstants.Attribute, allow_redirect: bool) -> Dictionary:
	var actual_target := target
	if allow_redirect:
		for unit in party:
			if unit.protecting_ally_id == target.id and not unit.is_downed():
				actual_target = unit
				break

	if actual_target.counter_pending_this_turn:
		actual_target.counter_pending_this_turn = false
		var counter_skill := actual_target.active_counter_skill
		actual_target.active_counter_skill = {}
		var counter_attribute := RBMConstants.attribute_from_name(str(counter_skill.get("attribute", "NEUTRAL")))
		var counter_mult := float(counter_skill.get("atk_multiplier", 1.0))
		# Phase 2: 反撃で返るダメージも「ボスが受けた攻撃」の一種として
		# last_received_skill/last_received_attribute/weak_hit条件の履歴
		# 対象に含める（counter_skillのidをsource_skill_idとして渡す——
		# プレイヤーが実際にそのスキルでボスへ反射ダメージを与えている以上、
		# 「ボスが前回受けたスキル」条件が自然に反応すべきという判断。
		# §6.6/§7に「通常のダメージ源だけ」という限定は無い）。
		var reflected := _compute_and_apply_damage(actual_target, boss, counter_mult, counter_attribute, true, str(counter_skill.get("id", "")))
		# Required fix #6: the incoming hit that the counter blocked is explicitly
		# logged as amount=0, distinct from the (separate, real) reflected damage.
		return {"blocked": true, "counter": true, "target": actual_target.id, "amount": 0, "reflected": reflected, "visual_original_target": target.id}

	var amount := _compute_and_apply_damage(boss, actual_target, atk_mult, attribute, false)
	return {"amount": amount, "target": actual_target.id, "visual_original_target": target.id}

## The single damage formula for both directions (v0.1-B §6, §7):
##   ATK × スキル倍率 × 属性補正 × (居合ボーナス, if applicable) × ダメージ軽減
## No intermediate rounding; the final result alone is rounded, and 0 is a valid
## result (no UnderDesk-style max(1, ...) floor).
##
## Phase 2で追加したsource_skill_id引数（既定""=通常攻撃・ボス→味方方向の
## 呼び出し等、意味を持たない場合）: ボスが攻撃を受けた側（target==boss）の
## 時だけ「前回受けたスキル/属性」の履歴更新（_record_boss_hit_history）に
## 渡される——ボスが攻撃する側の呼び出しでは無視される（読み取られない）。
## v0.1-B §10「通常攻撃は攻撃スキルではない」と整合させ、通常攻撃の直後は
## 「前回受けたスキル」条件が""（＝どのスキルidとも一致しない）として扱われ、
## 常に不一致になる設計を維持する。
func _compute_and_apply_damage(attacker: RBMUnit, target: RBMUnit, skill_multiplier: float, attack_attribute: RBMConstants.Attribute, is_attack_skill_use: bool, source_skill_id: String = "") -> int:
	var atk_buff := float(RBMConstants.timed_effect_value(attacker.timed_effects, "atk_buff", current_turn, 1.0))
	var base_atk := float(attacker.atk) * atk_buff
	var attribute_mult := RBMConstants.attribute_multiplier_for_lists(attack_attribute, target.weak_attributes, target.resist_attributes)
	var bonus_mult := 1.0
	if is_attack_skill_use and attacker.next_attack_bonus_multiplier != 1.0:
		bonus_mult = attacker.next_attack_bonus_multiplier
		attacker.next_attack_bonus_multiplier = 1.0
	var reduction_mult := _damage_reduction_multiplier(target)
	var final_amount := RBMBattle.compute_damage_amount(base_atk, skill_multiplier, attribute_mult, bonus_mult, reduction_mult)

	target.hp = maxi(0, target.hp - final_amount)
	if target.is_downed():
		target.clear_on_downed()

	if not target.is_ally:
		_record_boss_hit_history(source_skill_id, attack_attribute, is_equal_approx(attribute_mult, RBMConstants.ATTRIBUTE_MULTIPLIER_WEAK))

	return final_amount

## Pure arithmetic core of the damage formula above — no side effects, no
## dependency on a live battle/unit. Extracted (Step 4 §3-4/§7-4) so Creator
## damage-preview code can call the EXACT SAME formula the real battle uses,
## rather than a hand-duplicated copy that could silently drift from it.
## bonus_multiplier/reduction_multiplier should be 1.0 when the caller has
## nothing meaningful to say about 居合/防御 (e.g. a Creator preview, which has
## no live battle-turn context for those).
static func compute_damage_amount(atk: float, skill_multiplier: float, attribute_multiplier: float, bonus_multiplier: float, reduction_multiplier: float) -> int:
	return int(round(atk * skill_multiplier * attribute_multiplier * bonus_multiplier * reduction_multiplier))

## v0.1-B §7/§16: multiple reduction sources stack multiplicatively. Only applies
## when the target is an ally — the boss has no defend/軽減 mechanics in Phase 1.
func _damage_reduction_multiplier(target: RBMUnit) -> float:
	if not target.is_ally:
		return 1.0
	var mult := 1.0
	if target.is_defending:
		var rate := RBMConstants.DEFEND_BASE_REDUCTION
		if RBMConstants.timed_effect_active(party_timed_effects, "guard_boost", current_turn):
			rate = float(RBMConstants.timed_effect_value(party_timed_effects, "guard_boost", current_turn, RBMConstants.DEFEND_BOOSTED_REDUCTION))
		mult *= (1.0 - rate)
	if RBMConstants.timed_effect_active(party_timed_effects, "iron_wall", current_turn):
		var iron_rate := float(RBMConstants.timed_effect_value(party_timed_effects, "iron_wall", current_turn, RBMConstants.IRON_WALL_REDUCTION))
		mult *= (1.0 - iron_rate)
	return mult

# =============================================================================
# HARDCORE Creator「攻撃（action_sequence）」の評価器。
# boss_def["action_sequence"]が空ならこのセクションの関数は一切呼ばれない
# （_resolve_boss_turn_actions()の分岐参照）。
#
# 2026-09-05全面再設計: 旧「行動パターン」の優先度フォールバック評価器
# （_select_normal_action_pattern/_execute_action_pattern/瞬間条件イベント
# キュー一式）を廃止し、行動する順番に並んだ「攻撃スロット」を毎ターン
# 1つだけ実行するラウンドロビン評価器へ全面移行した。
# =============================================================================

func _boss_hp_percent() -> float:
	if boss.max_hp <= 0:
		return 0.0
	return float(boss.hp) / float(boss.max_hp) * 100.0

func _unit_by_character_id(character_id: String) -> RBMUnit:
	for unit in party:
		if unit.character_id == character_id:
			return unit
	return null

## §14/§15/§16/§17/§18確定仕様の本体。現在位置カーソル(_boss_action_cursor)
## から最大size()回だけaction_sequenceを走査し、最初に発動可能（条件成立
## かつ使用回数上限未到達）なスロットを見つけたら、そのスロットだけを実行
## してターンを終える——優先度フォールバックという概念はもう無く、「1ターン
## に実行するのは常にちょうど1スロット」（§18で明示的に旧・複数行動の
## 連続実行を廃止）。
## §17確定: 一周して1つも発動可能なスロットが無ければ、このターンは何も
## せず（"none"を返す）、カーソルは据え置く（次のターンもこの同じ位置から
## 再走査する）。
## §15確定: カーソルは「実際に実行に成功したスロットの次」へ進める——
## スキップされたスロット数によって別計算をしない（そのスロット自身の
## 配列位置+1をsize()で割った余りへ単純に設定するだけ）。
func _resolve_hardcore_boss_turn(action_sequence: Array) -> Array[Dictionary]:
	var slot_count := action_sequence.size()
	for offset in range(slot_count):
		var index := (_boss_action_cursor + offset) % slot_count
		var slot: Dictionary = action_sequence[index]
		if not _action_slot_is_eligible(slot):
			continue
		var skill_id := _resolve_action_slot_skill_id(slot)
		var skill := _find_skill(boss, skill_id)
		if skill.is_empty():
			continue  # 参照先スキルが存在しない防御的フォールバック——次のスロットへ。
		_mark_action_slot_used(slot)
		_boss_action_cursor = (index + 1) % slot_count
		return [_apply_boss_skill(boss, skill)]
	return [{"actor": "boss", "action": "none"}]

## §16確定仕様の発動可否ゲート: 条件成立かつ使用回数上限未到達。旧仕様に
## あった発動確率・Cooldownは§9で完全に廃止したため、この2条件だけで判定
## する。
func _action_slot_is_eligible(slot: Dictionary) -> bool:
	var max_uses := int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES))
	if max_uses != RBMActionPatternRules.UNLIMITED_USES:
		var slot_id := str(slot.get("slot_id", ""))
		if int(_slot_use_counts.get(slot_id, 0)) >= max_uses:
			return false
	return _evaluate_condition_group(slot)

## kind=="skill"ならそのまま、kind=="random"なら候補からその場で1つ抽選
## する（_pick_weighted_skill_id()、_pick_boss_normal_action()と共有、
## §13「ランダム結果自体は保存しない、その場で抽選するだけ」）。
func _resolve_action_slot_skill_id(slot: Dictionary) -> String:
	if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
		return _pick_weighted_skill_id(slot.get("candidates", []))
	return str(slot.get("skill_id", ""))

## §8確定: 使用回数の状態管理キーはskill_idではなくslot_id（配置固有ID）
## ——同じ攻撃性能を複数箇所へ配置しても、それぞれ独立してカウントされる。
func _mark_action_slot_used(slot: Dictionary) -> void:
	var slot_id := str(slot.get("slot_id", ""))
	_slot_use_counts[slot_id] = int(_slot_use_counts.get(slot_id, 0)) + 1

## 条件グループ全体（単一のAND/ORのみ、ネストなし）の評価。旧仕様にあった
## 瞬間条件（active_events引数、edge-trigger判定）は新仕様に一切存在しない
## ため、この関数は現在のライブ状態だけを問い合わせる単純な形へ縮小した。
func _evaluate_condition_group(slot: Dictionary) -> bool:
	var conditions: Array = slot.get("conditions", [])
	if conditions.is_empty():
		return true  # 条件なしの攻撃は常に発動可能。
	var logic := str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC))
	if logic == "OR":
		for condition_variant in conditions:
			if _evaluate_condition(condition_variant):
				return true
		return false
	for condition_variant in conditions:
		if not _evaluate_condition(condition_variant):
			return false
	return true

## 単一条件の評価。現在のライブ状態をそのまま問い合わせる（旧仕様にあった
## 瞬間条件のedge-trigger判定は削除済み、RBMActionPatternRules冒頭コメント
## 参照）。
func _evaluate_condition(condition: Dictionary) -> bool:
	var condition_type := str(condition.get("type", ""))
	match condition_type:
		"hp_at_most":
			return _boss_hp_percent() <= float(condition.get("percent", 0.0))
		"hp_at_least":
			return _boss_hp_percent() >= float(condition.get("percent", 0.0))
		"hp_between":
			var pct := _boss_hp_percent()
			return pct >= float(condition.get("percent_min", 0.0)) and pct <= float(condition.get("percent_max", 100.0))
		"turn_at":
			return current_turn == int(condition.get("turn", -1))
		"turn_at_least":
			return current_turn >= int(condition.get("turn", 1))
		"turn_at_most":
			return current_turn <= int(condition.get("turn", 1))
		"turn_every_n":
			var n := int(condition.get("n", 0))
			return n > 0 and current_turn % n == 0
		"turn_between":
			return current_turn >= int(condition.get("turn_min", 1)) and current_turn <= int(condition.get("turn_max", 1))
		"allies_at_most":
			return _living_allies().size() <= int(condition.get("count", 0))
		"allies_at_least":
			return _living_allies().size() >= int(condition.get("count", 0))
		"allies_exactly":
			return _living_allies().size() == int(condition.get("count", 0))
		"character_alive":
			var alive_unit := _unit_by_character_id(str(condition.get("character_id", "")))
			return alive_unit != null and not alive_unit.is_downed()
		"character_downed":
			var downed_unit := _unit_by_character_id(str(condition.get("character_id", "")))
			return downed_unit != null and downed_unit.is_downed()
		"last_boss_skill":
			return _boss_has_acted and _boss_last_used_skill_id == str(condition.get("skill_id", ""))
		"last_received_skill":
			return _boss_has_been_hit and _boss_last_received_skill_id == str(condition.get("skill_id", ""))
		"last_received_attribute":
			return _boss_has_been_hit and _boss_last_received_attribute == RBMConstants.attribute_from_name(str(condition.get("attribute", "NEUTRAL")))
		"weak_hit":
			return _boss_has_been_hit and _boss_last_hit_was_weak
		_:
			return false

## ボスが攻撃を受けた時の「前回受けた」系履歴の更新（_compute_and_apply_
## damage()から、target==bossの時だけ呼ばれる）。last_received_skill/
## last_received_attribute/weak_hit条件が参照する履歴を更新するだけの
## 関数——旧・瞬間条件検出（instant event queue）は新HARDCORE仕様
## （action_sequence）に瞬間条件という概念が存在しないため完全に削除した
## （RBMActionPatternRules冒頭コメント参照）。
func _record_boss_hit_history(source_skill_id: String, attack_attribute: RBMConstants.Attribute, was_weak: bool) -> void:
	_boss_has_been_hit = true
	_boss_last_received_skill_id = source_skill_id
	_boss_last_received_attribute = attack_attribute
	_boss_last_hit_was_weak = was_weak
