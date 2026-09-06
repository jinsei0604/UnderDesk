class_name RBMChallengeSession
extends RefCounted

## Phase 1 Step 7 §21〜§31 — CHALLENGE専用の戦闘セッション。
##
## §63の必須調査結果（完了報告§9で詳述）: RBMCreatorTestSession
## （TEST BATTLE + Turn REWIND、Step 4で確定済み・再設計禁止——src/bossmaker/README.md
## 「Step 4」節参照）をそのまま流用するのではなく、意図的に別クラスとして
## 新設した。理由: RBMCreatorTestSessionの本体機能はREWIND履歴管理
## （history配列/rewind_to()/reachable_turns()）であり、これはCHALLENGEには
## 一切不要かつ§24で「REWIND APIを挑戦者操作として公開しない」と明示禁止
## されている。技術的にはRBMCreatorTestSessionを流用してもrewind_to()等を
## 呼ばなければ実害はないが、①REWINDのpublic APIを持つオブジェクトを
## CHALLENGE UI層へそのまま握らせる設計はその禁止の趣旨に反する、②
## RBMCreatorTestSession自体はStep 4で確定済み・再設計禁止（§0）のため、
## 共通基底クラスへ抽出するような構造変更もしていない——重複するのは
## Definitionからの戦闘構築とrestart()という15行程度の小さなロジックのみで、
## 「クラス名にCreatorと付いているという理由だけで安易に流用しない」
## 「責務がCHALLENGEにも適切なら再利用可。不適切なら最小限の共通化を検討。
## 大規模リファクタは禁止」という指示（§63）の両方をこの判断で満たしている
## と判断した。
##
## このクラスにhistory配列・rewind_to()・reachable_turns()は存在しない。

var battle: RBMBattle
var _definition: Dictionary
var _seed: int
var _last_start_result: Dictionary = {}

## §22/§23: definitionは呼び出し元（RBMChallengeEntry）が既に
## RBMDefinitionLoader.resolve()で検証済みのものを渡す想定——それでも
## start_battle()自身が再度resolve()を経由して構築するため（RBMDefinitionLoader.start_battle()
## がそうしているのと同じ、TEST BATTLE/Clear Checkの既存の作法）、CHALLENGE
## だけが検証をバイパスする経路は存在しない。rng_seedは常にランダム
## （挑戦者が任意に固定できる概念はTEST BATTLE/Clear Checkのテスト専用引数
## とは違いCHALLENGEには存在しないため、テスト用途以外では-1のまま）。
func _init(definition: Dictionary, rng_seed: int = -1) -> void:
	_definition = definition.duplicate(true)
	_seed = rng_seed if rng_seed >= 0 else randi()
	_start_fresh()

func start_ok() -> bool:
	return bool(_last_start_result.get("ok", false))

func start_errors() -> Array:
	return _last_start_result.get("errors", [])

func _start_fresh() -> void:
	_last_start_result = RBMDefinitionLoader.start_battle(_definition, _seed)
	battle = _last_start_result.get("battle") if start_ok() else null
	# 実機プレイ改善①: RBMCreatorTestSessionと同じ理由で、構築直後に一度
	# advance()を呼び、turn_start指定行動・味方より先に行動するボスがいれば
	# それを自動解決してから、最初の生存する味方の入力を待つ状態にする
	# （履歴を持たないためRBMCreatorTestSessionのようなsnapshot記録は不要）。
	if battle != null:
		advance()

## §27/§28: 「最初からやり直す」確定時の実処理。同じDefinition・新しい乱数
## seed・Turn 1・初期HP/SP・一時状態初期化——すべてRBMBattle.new()を新しい
## seedで呼び直すだけで満たされる（RBMBattleのコンストラクタ自体が全状態を
## ゼロから構築するため、履歴初期化のような追加処理は不要——このクラスは
## そもそも履歴を持たない）。§32/§34「結果画面からのもう一度挑戦」も同じ
## メソッドを確認なしで呼ぶだけ（呼び出し元のUI層側の違いであり、セッション
## 側の処理は完全に同一）。
func restart() -> void:
	_seed = randi()
	_start_fresh()

# ---------------------------------------------------------------------------
# 実機プレイ改善①「戦闘方式を後期UNDERDESK方式へ統一」— RBMCreatorTestSession
# と同一の新方式駆動API（このクラスに履歴/REWINDが無い点だけが違う——§24で
# 明示禁止されている「REWIND APIを挑戦者操作として公開しない」に変わりはない）。
# 旧resolve_turn(ally_actions)は完全に削除した。
# ---------------------------------------------------------------------------

func advance() -> Array[Dictionary]:
	return [] if battle == null else battle.advance_to_next_decision()

func is_waiting_for_ally_action() -> bool:
	return battle != null and battle.is_waiting_for_ally_action()

func pending_ally_id() -> int:
	return -1 if battle == null else battle.pending_ally_id()

func resolve_ally_action(action: Dictionary) -> Array[Dictionary]:
	if battle == null:
		return []
	var log := battle.resolve_pending_ally_action(action)
	log.append_array(advance())
	return log
