class_name RBMCreatorTestSession
extends RefCounted

## Phase 1 Step 4 §8/§9 — TEST BATTLE + Turn REWIND session.
##
## RBMBattle itself only provides the generic snapshot()/restore() primitive
## (§9-4) and has no opinion about history at all. THIS class owns everything
## §9-5 assigns to the "Creator TEST側": per-turn snapshots, the reachable-turn
## list, REWIND target selection, and future-history discard on rewind. It is
## deliberately the ONLY place in this project that calls
## RBMBattle.snapshot()/restore() — Phase 1 Step 5's Clear Check
## (RBMCreatorClearCheckView) reuses this exact class UNMODIFIED for its own
## battle+REWIND session (confirmed: REWIND is explicitly usable during Clear
## Check, unlimited uses, no effect on pass/fail — see src/bossmaker/README.md's
## "Step 5" section). Normal Challenge is the one thing that is confirmed to
## never construct one of these — its players do not get REWIND at all
## (§9-12/Step 5 §34).
##
## §12: TEST BATTLE start always goes through RBMDefinitionLoader.start_battle()
## on the Creator's generated Definition — there is no private shortcut that
## bypasses Definition validation.

## history[i] is the snapshot for Turn (i+1)'s own TRUE start -- i.e.
## reachable_turns()[i] == i + 1。実機プレイ改善① Round 5-2修正: 「Turn
## (i+1)の開始」とは、そのTurnのturn_start_interruptもボスの先制行動も一切
## 実行されていない、純粋な境界状態（RBMBattle.is_at_fresh_turn_boundary()
## がtrueを返す瞬間）を指す——advance()（下記）がこの瞬間を必ず先に
## snapshot()してから、実際の処理（turn_start指定行動・全員より速いボスの
## 1手等）を進める。REWINDでこのTurnへ戻ると、その処理は一切実行されて
## いない状態になり、再度進めれば同じRNG状態から同じ結果（turn_start_
## interruptの再発火を含む）を再現する。
var history: Array[Dictionary] = []
var battle: RBMBattle

var _definition: Dictionary
var _seed: int
var _last_start_result: Dictionary = {}

func _init(definition: Dictionary, rng_seed: int = -1) -> void:
	_definition = definition.duplicate(true)
	_seed = rng_seed if rng_seed >= 0 else randi()
	_start_fresh()

func start_ok() -> bool:
	return bool(_last_start_result.get("ok", false))

## Human-unreadable Definition-validation error strings (§12: "内部validation
## 文字列をそのまま露出する必要はありませんが、原因を特定できること" — the UI
## layer is responsible for translating these into a readable message; this
## class just exposes the raw list so nothing is silently swallowed).
func start_errors() -> Array:
	return _last_start_result.get("errors", [])

func _start_fresh() -> void:
	_last_start_result = RBMDefinitionLoader.start_battle(_definition, _seed)
	if start_ok():
		battle = _last_start_result["battle"]
		# 実機プレイ改善① Round 5-2修正: 構築直後のRBMBattleは既に
		# is_at_fresh_turn_boundary()==true（Turn 1・何も処理されていない）
		# の状態にある——advance()自身がこの瞬間をTurn 1のスナップショットと
		# して正しく記録してから、実際の処理（turn_start指定行動・全員より
		# 速いボスの1手等）を進める。手動でbattle.snapshot()を追加で呼ぶ
		# 必要はもう無い（advance()に一本化した）。
		history = []
		advance()
	else:
		battle = null
		history = []

## §8-3 "もう一度テスト": a brand new battle from the SAME Creator Definition,
## history reset to just Turn 1's start again.
func restart() -> void:
	_seed = randi()
	_start_fresh()

# ---------------------------------------------------------------------------
# 実機プレイ改善①「戦闘方式を後期UNDERDESK方式へ統一」— 新方式の唯一の
# 駆動口。呼び出し側（UI）はbattleへ直接アクセスして駆動しない——REWINDの
# snapshot()タイミングをこのセッションだけが正しく制御できるようにするため。
# 旧resolve_turn(ally_actions)（丸ごと1ラウンド分を一括で受け取り即座に
# 全員分解決するAPI）はこのクラスから完全に削除した——TEST BATTLE/
# Clear Checkのどちらも、もうこの方式を一切使わない。
# ---------------------------------------------------------------------------

## 現在入力を必要とせず自動で解決できる分（ボスの番・指定行動・戦闘不能
## スキップ・ラウンド繰り上げ）をすべて進め、生存する味方の入力が必要に
## なるかbattle_overになるまで進める。
##
## Round 5-2修正: 「1回の呼び出しが複数のTurn境界を一気にまたいでしまう
## 場合でも、横切った各境界を漏れなく正しいタイミング（そのTurnの処理が
## 一切始まっていない、純粋な境界状態）でsnapshot()する」よう、
## battle.advance_to_next_decision(true)（stop_before_turn_processing）を
## ループで繰り返し呼ぶ設計へ全面的に作り直した——境界に到達するたび
## snapshot()してから処理を再開し、battle_overかis_waiting_for_ally_action()
## になって初めて呼び出し元へ制御を返す。
## skip_initial_snapshot: rewind_to()専用。REWIND直後は「今まさに戻った、
## その境界」自体は既にhistory内に存在する（重複記録を防ぐため、最初の
## 1回だけスナップショットをスキップする——それ以降、この呼び出しの中で
## 新たに横切る境界は通常どおり記録する）。
func advance(skip_initial_snapshot: bool = false) -> Array[Dictionary]:
	if battle == null:
		return []
	var log: Array[Dictionary] = []
	var first := true
	while true:
		if battle.is_at_fresh_turn_boundary() and not (first and skip_initial_snapshot):
			history.append(battle.snapshot())
		first = false
		var step_log := battle.advance_to_next_decision(true)
		log.append_array(step_log)
		if battle.battle_over or battle.is_waiting_for_ally_action():
			return log
		# それ以外: advance_to_next_decision()は新しいTurn境界を横切った
		# 直後で一時停止しただけ——ループしてその境界をsnapshot()してから
		# 処理を続ける。
	return log

func is_waiting_for_ally_action() -> bool:
	return battle != null and battle.is_waiting_for_ally_action()

func pending_ally_id() -> int:
	return -1 if battle == null else battle.pending_ally_id()

## 現在入力待ちの味方の行動を即座に解決し、続けてauto-cascade分
## （ボスの番等）もこの呼び出しの中で一緒に進める——呼び出し側が別途
## advance()を呼び直す必要はない。戻り値はその両方を合わせたログ全体。
func resolve_ally_action(action: Dictionary) -> Array[Dictionary]:
	if battle == null:
		return []
	var log := battle.resolve_pending_ally_action(action)
	log.append_array(advance())
	return log

## Every turn number REWIND can currently jump to (§9-2: every turn ever
## reached, not just the current one).
func reachable_turns() -> Array[int]:
	var out: Array[int] = []
	for i in range(history.size()):
		out.append(i + 1)
	return out

## §9-2/§9-10: restores Turn `turn`'s TRUE start-of-turn (nothing processed
## yet) snapshot, then discards every LATER turn's snapshot (never earlier
## ones) — a single, ever-growing-or-truncating timeline, never a branch.
## Returns false (no-op) for an unreached turn number.
##
## Round 5-2修正: battle.restore()した直後のRBMBattleは
## is_at_fresh_turn_boundary()==true（そのTurnの処理が一切始まっていない）
## の状態にある——これはUI/呼び出し側がまだ何の入力もできない、宙ぶらりんの
## 状態なので、_start_fresh()と全く同じ理由でadvance()を呼び、そのTurnの
## turn_start_interrupt・全員より速いボスの1手等を自動的に処理してから
## 次の入力待ち（またはbattle_over）へ進める。skip_initial_snapshot=trueで
## 呼ぶのは、「今戻ったばかりのこの境界」自体が既にhistory[index]として
## 存在しており、advance()がもう一度同じ境界を検出して重複記録しないように
## するため（それ以降、この呼び出しの中で新たに横切る境界があれば通常どおり
## 記録される）。
func rewind_to(turn: int) -> bool:
	var index := turn - 1
	if index < 0 or index >= history.size():
		return false
	battle.restore(history[index])
	history.resize(index + 1)
	advance(true)
	return true
