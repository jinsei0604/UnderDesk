class_name RBMSteamAdapter
extends RefCounted

## Phase 4A-1 — 実際のGodotSteam(`Steam`シングルトン)だけに触れる薄いラッパー。
## RBMSteamAuthはこのクラスの公開メソッド/シグナルだけに依存し、`Steam.*`を
## 直接呼ばない——GUT側はheadlessでGodotSteamの実接続を伴わずにテストする
## ため、RBMFakeSteamAdapter（同じ形の公開面）へ差し替える(既存の
## RBMLocalStageRepository.set_stages_dir_for_testing()等と同じ「本体は
## 触らずテスト用に差し替える」既存方針)。
##
## `Engine.has_singleton("Steam")`で存在確認してから触る——アドオンの
## GDExtensionが何らかの理由で読み込まれていない環境でもクラッシュせず
## `has_steam() == false`を返すだけにする。
##
## Steamの実際のResultコードは`Steam.RESULT_OK`(=1、`k_EResultOK`)。

signal ticket_for_web_api_received(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: PackedByteArray)

const RESULT_OK := 1

var _connected := false

func has_steam() -> bool:
	return Engine.has_singleton("Steam")

## Steam.steamInitEx(app_id, embed_callbacks) -> {"status": int, "verbal": String}
## §GodotSteam公式ドキュメント: status 0=成功、1=その他失敗、
## 2=Steamクライアントに接続できない（起動していない等）、3=クライアントが古い。
func init_ex(app_id: int, embed_callbacks: bool) -> Dictionary:
	if not has_steam():
		return {"status": 2, "verbal": "GodotSteam singleton not present"}
	var steam: Object = Engine.get_singleton("Steam")
	var result: Dictionary = steam.steamInitEx(app_id, embed_callbacks)
	_ensure_ticket_signal_connected(steam)
	return result

## embed_callbacks=falseの間、呼び出し側が毎フレーム呼ぶ想定
## （既存のGodotSteam流儀どおり、autoload無しでこのクラスの利用者が
## _process()から呼ぶ）。
func run_callbacks() -> void:
	if not has_steam():
		return
	(Engine.get_singleton("Steam") as Object).run_callbacks()

func is_logged_on() -> bool:
	if not has_steam():
		return false
	return bool((Engine.get_singleton("Steam") as Object).loggedOn())

## SteamID64は呼び出し側(RBMSteamAuth)が文字列化する——ここではSteamが
## 返す生のint(64bit)をそのまま返す。
func get_steam_id() -> int:
	if not has_steam():
		return 0
	return int((Engine.get_singleton("Steam") as Object).getSteamID())

func get_persona_name() -> String:
	if not has_steam():
		return ""
	return str((Engine.get_singleton("Steam") as Object).getPersonaName())

## Steam.getAuthTicketForWebApi(identity) -> ticket_handle(uint32)。
## この戻り値だけではticketはまだ有効ではない——実際のticket本体は
## 後続の`ticket_for_web_api_received`シグナル(Steamの
## get_ticket_for_web_apiコールバック相当)でしか手に入らない。
func request_auth_ticket_for_web_api(identity: String) -> int:
	if not has_steam():
		return 0
	return int((Engine.get_singleton("Steam") as Object).getAuthTicketForWebApi(identity))

## Steam.cancelAuthTicket(auth_ticket)。無効なhandle(0)を渡しても
## Steam側もこのラッパーも何もしない——二重cancelしても安全。
func cancel_auth_ticket(auth_ticket: int) -> void:
	if auth_ticket == 0 or not has_steam():
		return
	(Engine.get_singleton("Steam") as Object).cancelAuthTicket(auth_ticket)

func _ensure_ticket_signal_connected(steam: Object) -> void:
	if _connected:
		return
	if steam.has_signal("get_ticket_for_web_api"):
		steam.connect("get_ticket_for_web_api", _on_get_ticket_for_web_api)
		_connected = true

func _on_get_ticket_for_web_api(auth_ticket: int, result: int, ticket_size: int, ticket_buffer: PackedByteArray) -> void:
	ticket_for_web_api_received.emit(auth_ticket, result, ticket_size, ticket_buffer)
