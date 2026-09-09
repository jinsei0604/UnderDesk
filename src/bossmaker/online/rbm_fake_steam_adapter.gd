class_name RBMFakeSteamAdapter
extends RBMSteamAdapter

## Phase 4A-1 — RBMSteamAdapterを継承し、全メソッドを実GodotSteamへ
## 一切触れない偽実装で上書きするテスト専用クラス。RBMSteamAuthの
## set_adapter_for_testing(adapter: RBMSteamAdapter)へそのまま渡せる
## ようにするため、別クラスではなく継承にしてある(GDScriptの静的型
## チェック上、無関係なクラスでは代入できないため)。
##
## GUTはheadlessで実行されるため、これがSteam関連の自動テストの唯一の
## 土台になる(ユーザー確定方針: 「GodotSteamそのものをheadless testで
## 利用できない場合は、Steam adapter/interfaceを分離してfake実装で
## テストする」)。
##
## テスト側が`configure_*`でシナリオを設定し、`fire_ticket_response()`を
## 明示的に呼ぶまでシグナルは発火しない——コールバック到着前後の状態
## 遷移を厳密にテストできるようにするため。

var _fake_has_steam := true
var _init_result: Dictionary = {"status": 0, "verbal": "OK"}
var _logged_on := false
var _steam_id := 0
var _persona_name := ""
var _next_ticket_handle := 1
var _last_issued_handle := 0
var _last_requested_identity := ""
var _run_callbacks_count := 0
var _cancelled_handles: Array[int] = []

func configure_unavailable() -> void:
	_fake_has_steam = false

func configure_available(init_status: int = 0, init_verbal: String = "OK") -> void:
	_fake_has_steam = true
	_init_result = {"status": init_status, "verbal": init_verbal}

func configure_logged_on(logged_on: bool, steam_id: int = 0, persona_name: String = "") -> void:
	_logged_on = logged_on
	_steam_id = steam_id
	_persona_name = persona_name

func run_callbacks_count() -> int:
	return _run_callbacks_count

func has_steam() -> bool:
	return _fake_has_steam

func init_ex(_app_id: int, _embed_callbacks: bool) -> Dictionary:
	if not _fake_has_steam:
		return {"status": 2, "verbal": "Steam client is not running"}
	return _init_result.duplicate()

func run_callbacks() -> void:
	_run_callbacks_count += 1

func is_logged_on() -> bool:
	return _fake_has_steam and _logged_on

func get_steam_id() -> int:
	return _steam_id if _fake_has_steam else 0

func get_persona_name() -> String:
	return _persona_name if _fake_has_steam else ""

func request_auth_ticket_for_web_api(identity: String) -> int:
	if not _fake_has_steam:
		return 0
	_last_requested_identity = identity
	var handle := _next_ticket_handle
	_next_ticket_handle += 1
	_last_issued_handle = handle
	return handle

func cancel_auth_ticket(auth_ticket: int) -> void:
	if auth_ticket == 0:
		return
	_cancelled_handles.append(auth_ticket)

## テストが最後に発行したhandle値・identity文字列を参照するための
## 公開アクセサ(内部フィールドへ直接触れさせない)。
func last_issued_handle() -> int:
	return _last_issued_handle

func last_requested_identity() -> String:
	return _last_requested_identity

func cancelled_handles() -> Array[int]:
	return _cancelled_handles.duplicate()

## テストがcallbackの到着を明示的にシミュレートする
## (継承したticket_for_web_api_receivedシグナルをそのまま使う)。
func fire_ticket_response(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: PackedByteArray) -> void:
	ticket_for_web_api_received.emit(auth_ticket, result, ticket_size, ticket_buffer)
