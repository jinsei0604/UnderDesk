class_name RBMBossPublisher
extends Node

## Phase 4C — Makerのオンライン公開オーケストレーション。
##
## 経路(ユーザー確定仕様、§4C-3):
##   online payload生成 → Steam ticket取得 → Edge Function → Steam認証
##   → DB保存
##
## Clear Checkゲート・snapshot一致確認はRBMOnlineBossPayload.
## build_for_publish()内で既に行われる(§4C-1/§4C-2)——ここでは二重実装
## しない。正式Steam認証(Phase 4A-2)が無い間は、RBMSteamAuthが
## is_available()==falseを返すか、Edge Function側がnot_configuredを
## 返すため、実公開が成功扱いになることはない(ユーザー確定仕様
## 「本番Steam認証が使えない状態では、実公開を成功扱いにしない」)。
##
## テストはRBMFakeSteamAdapter + RBMFakeBossApiAdapterへ差し替えて、
## 正式AppIDが無くても全経路をheadlessで検証できる(§4C-4)。

enum PublishState { IDLE, REQUESTING_TICKET, UPLOADING, SUCCEEDED, FAILED }

signal state_changed(new_state: PublishState)
signal publish_succeeded(boss_id: String, revision: int)
signal publish_failed(error_kind: String, message: String)

var _steam_auth: RBMSteamAuth
var _api_adapter: RBMBossApiAdapter
var _state: PublishState = PublishState.IDLE
var _last_error_kind := ""
var _last_error_message := ""
var _last_boss_id := ""

func set_steam_auth_for_testing(auth: RBMSteamAuth) -> void:
	_steam_auth = auth

func set_api_adapter_for_testing(adapter: RBMBossApiAdapter) -> void:
	_api_adapter = adapter

func _ensure_setup() -> void:
	if _steam_auth == null:
		_steam_auth = RBMSteamAuth.new()
		add_child(_steam_auth)
		_steam_auth.initialize()
	if _api_adapter == null:
		_api_adapter = RBMBossApiAdapter.new()
		add_child(_api_adapter)

func current_state() -> PublishState:
	return _state

func last_error_kind() -> String:
	return _last_error_kind

func last_error_message() -> String:
	return _last_error_message

func last_boss_id() -> String:
	return _last_boss_id

## 連打・二重投稿の防止(§4E-4のクライアント側の一枚目——DB側のidempotency_key
## と合わせた二段構え)。既に進行中なら無視してfalseを返す。
func publish(draft: RBMCreatorDraft, boss_id: String = "") -> bool:
	_ensure_setup()
	if _state == PublishState.REQUESTING_TICKET or _state == PublishState.UPLOADING:
		return false

	var built := RBMOnlineBossPayload.build_for_publish(draft)
	if not bool(built.get("ok", false)):
		_fail(str(built.get("error", "unknown")), "Clear Checkを再確認してください。")
		return false
	var payload: Dictionary = built["payload"]

	if not _steam_auth.is_available():
		_fail("steam_unavailable", "Steamが利用できません。Steamを起動してログインしてください。")
		return false
	if not _steam_auth.is_logged_on():
		_fail("steam_not_logged_on", "Steamにログインしていません。")
		return false

	_set_state(PublishState.REQUESTING_TICKET)
	if not _steam_auth.request_web_api_ticket():
		_fail("steam_ticket_request_failed", _steam_auth.failure_reason())
		return false

	var ticket_result := await _await_ticket_result()
	if not bool(ticket_result.get("ok", false)):
		_fail("steam_ticket_failed", str(ticket_result.get("reason", "")))
		return false

	_set_state(PublishState.UPLOADING)
	var response: Dictionary = await _api_adapter.publish(str(ticket_result.get("hex", "")), payload, boss_id)
	_steam_auth.complete_ticket()

	if bool(response.get("ok", false)):
		_last_boss_id = str(response.get("boss_id", boss_id))
		_set_state(PublishState.SUCCEEDED)
		publish_succeeded.emit(_last_boss_id, int(response.get("revision", 0)))
		return true

	_fail(str(response.get("error_kind", "unknown")), str(response.get("message", "")))
	return false

func _await_ticket_result() -> Dictionary:
	# `while true` never falls through on its own (no break), but GDScript's
	# static analyzer still wants an explicit return after the loop.
	while true:
		var state: RBMSteamAuth.AuthState = _steam_auth.current_auth_state()
		if state == RBMSteamAuth.AuthState.READY:
			return {"ok": true, "hex": _steam_auth.consume_ticket_hex()}
		if state == RBMSteamAuth.AuthState.FAILED or state == RBMSteamAuth.AuthState.CANCELLED:
			return {"ok": false, "reason": _steam_auth.failure_reason()}
		await _steam_auth.state_changed
	return {"ok": false, "reason": "unreachable"}

func _fail(error_kind: String, message: String) -> void:
	_last_error_kind = error_kind
	_last_error_message = message
	_set_state(PublishState.FAILED)
	publish_failed.emit(error_kind, message)

func _set_state(new_state: PublishState) -> void:
	_state = new_state
	state_changed.emit(new_state)
