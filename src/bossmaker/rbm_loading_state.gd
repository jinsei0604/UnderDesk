class_name RBMLoadingState
extends RefCounted

## Phase 7 — 将来の「共通ロード表示」のためのロジック側基盤のみ。
## 見た目(overlay/spinner/「読み込み中…」表示/背景暗転/blur/アニメーション)
## は今回一切実装しない——UIから「今オンライン通信中かどうか」を共通で
## 参照できる状態管理だけを用意する(実際のUI組み込みは別タスク)。
##
## このリポジトリにはautoload/Singletonが1つも無く、utilityは全てstatic
## クラスという既存方針(RBMSupabaseConfig等)があるが、GDScriptは
## static signalを宣言できないため、「将来のUIがsignalを購読できる」
## という要件を満たすためだけの最小限の例外として、遅延生成した唯一の
## 共有インスタンス(shared())をstatic varに保持する——新しいautoload/
## プロジェクト設定は一切追加しない、参照はこのクラス自身を経由する
## だけの軽量な仕組み。
##
## 複数の通信が同時に走っても正しく管理できるよう、operation_idごとに
## 参照カウントで管理する——同じoperation_idでbegin()が2回呼ばれても、
## end()が1回呼ばれただけではloading状態を落とさない(片方の通信がまだ
## 続いている場合に備える、既存のcorrected_clear_rateのような「明示的な
## 補正」と同じ精神)。異なるoperation_id同士も独立してカウントされるため、
## 「A通信終了時にB通信中なのにis_loading()がfalseになる」という構造には
## ならない。

static var _shared: RBMLoadingState = null

## 個々のloading開始/終了。UIが特定の通信(例: 「ボス公開」)だけを
## 気にしたい場合に使う。
signal loading_started(operation_id: String)
signal loading_ended(operation_id: String)

## 全体のis_loading()が変化した瞬間だけ発火する(何か1つでも進行中なら
## true、全て終われば1度だけfalse)——将来の共通ロード表示が「何か1つでも
## 動いていればoverlayを出す」という単純な購読で足りるようにするため。
signal loading_state_changed(is_loading: bool)

## operation_id -> 現在の参照カウント(1以上)。0になったら鍵ごと削除する。
var _active_operations: Dictionary = {}

static func shared() -> RBMLoadingState:
	if _shared == null:
		_shared = RBMLoadingState.new()
	return _shared

## テスト専用: 各テストを完全に独立した状態から始められるようにする
## (RBMLocalStageRepository.set_stages_dir_for_testing()等と同じ既存の
## 「テスト用リセットフック」パターン)。
static func reset_for_testing() -> void:
	_shared = null

static func begin(operation_id: String) -> void:
	shared()._begin(operation_id)

static func end(operation_id: String) -> void:
	shared()._end(operation_id)

static func is_loading() -> bool:
	return shared()._is_loading()

## デバッグ/テスト用: 現在進行中のoperation_id一覧(参照カウント1以上の
## もの)。
static func active_operation_ids() -> Array:
	return shared()._active_operations.keys()

func _begin(operation_id: String) -> void:
	var was_loading := _is_loading()
	_active_operations[operation_id] = int(_active_operations.get(operation_id, 0)) + 1
	loading_started.emit(operation_id)
	if not was_loading:
		loading_state_changed.emit(true)

func _end(operation_id: String) -> void:
	if not _active_operations.has(operation_id):
		return
	var remaining: int = int(_active_operations[operation_id]) - 1
	if remaining <= 0:
		_active_operations.erase(operation_id)
	else:
		_active_operations[operation_id] = remaining
	loading_ended.emit(operation_id)
	if _active_operations.is_empty():
		loading_state_changed.emit(false)

func _is_loading() -> bool:
	return not _active_operations.is_empty()
