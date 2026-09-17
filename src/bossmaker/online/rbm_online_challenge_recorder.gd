class_name RBMOnlineChallengeRecorder
extends Node

## Phase 5 — オンライン版「未挑戦」。オンラインボスへの挑戦開始/クリアの
## 記録と、未挑戦一覧の取得を行うオーケストレーション。
##
## RBMBossPublisherと同じ経路(Steam ticket取得 → Edge Function)を使うが、
## 公開/取り下げの状態機械(PublishState)とは無関係な、単純に「1回呼んで
## 結果を返すだけ」の薄い層——呼び出し側(RBMChallengeEntry)はベストエフォ
## ートで扱う想定(§7: 通信失敗/Steam利用不可でも戦闘開始/勝利処理自体は
## 止めない)。
##
## Steam ticket取得自体はRBMSteamTicketProvider(RBMBossPublisherと共有)
## に委譲する。

var _steam_auth: RBMSteamAuth
var _api_adapter: RBMBossApiAdapter

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

## 戻り値: {"ok": bool, "error_kind": String, "message": String, "challenge_count": int}
## ticket取得に失敗した場合もエラーを返すだけで例外にはしない
## (呼び出し側がベストエフォートとして無視できるようにするため)。
func record_challenge_attempt(boss_id: String) -> Dictionary:
	_ensure_setup()
	var ticket_result := await RBMSteamTicketProvider.acquire_ticket(_steam_auth)
	if not bool(ticket_result.get("ok", false)):
		return {
			"ok": false,
			"error_kind": str(ticket_result.get("error_kind", "unknown")),
			"message": str(ticket_result.get("message", "")),
		}
	var response: Dictionary = await _api_adapter.record_challenge_attempt(str(ticket_result.get("hex", "")), boss_id)
	_steam_auth.complete_ticket()
	return response

func record_challenge_clear(boss_id: String) -> Dictionary:
	_ensure_setup()
	var ticket_result := await RBMSteamTicketProvider.acquire_ticket(_steam_auth)
	if not bool(ticket_result.get("ok", false)):
		return {
			"ok": false,
			"error_kind": str(ticket_result.get("error_kind", "unknown")),
			"message": str(ticket_result.get("message", "")),
		}
	var response: Dictionary = await _api_adapter.record_challenge_clear(str(ticket_result.get("hex", "")), boss_id)
	_steam_auth.complete_ticket()
	return response

## 「未挑戦」一覧取得もSteam ticketが必要(サーバー側で本人確認するため、
## list_bosses()と違い匿名では呼べない)。戻り値の形はlist_bosses()と同じ
## ({"ok":true,"bosses":[...]}または{"ok":false,"error_kind":...})——
## 呼び出し側(RBMOnlineBossListView)が同じレンダリング経路をそのまま使える。
func list_unchallenged_bosses(mode: String, limit: int = 20) -> Dictionary:
	_ensure_setup()
	var ticket_result := await RBMSteamTicketProvider.acquire_ticket(_steam_auth)
	if not bool(ticket_result.get("ok", false)):
		return {
			"ok": false,
			"error_kind": str(ticket_result.get("error_kind", "unknown")),
			"message": str(ticket_result.get("message", "")),
		}
	var response: Dictionary = await _api_adapter.list_unchallenged_bosses(str(ticket_result.get("hex", "")), mode, limit)
	_steam_auth.complete_ticket()
	return response
