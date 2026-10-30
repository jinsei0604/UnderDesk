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

## 討伐記録（RBMDefeatRecord）の持ち主: 今ログインしている Steam のアカウント（SteamID64）。分からなければ空。
## 挑戦の記録と同じ Steam の初期化（RBMSteamAuth）を使う（新しい通信はしない）。
func account_id() -> String:
	_ensure_setup()
	return _steam_auth.steam_id()

func _ensure_setup() -> void:
	if _steam_auth == null:
		_steam_auth = RBMSteamAuth.new()
		add_child(_steam_auth)
		_steam_auth.initialize()
	if _api_adapter == null:
		_api_adapter = RBMBossApiAdapter.new()
		add_child(_api_adapter)

## 2026-10-23: Steam の ticket の取得から通信の終わりまでを1本ずつ順に行う（RBMSteamAuth は同時に1枚しか ticket を
## 扱えないので、挑戦の記録・結果の送信・認定の受け取りが重なると、後の方が steam_ticket_request_failed で失敗していた）。
var _busy := false
signal _released

## 順番を待ってから Steam の ticket を取る。取れなければ順番を返し、{"ok": false, ...} を返す。
func _begin() -> Dictionary:
	_ensure_setup()
	while _busy:
		await _released
	_busy = true
	var ticket_result := await RBMSteamTicketProvider.acquire_ticket(_steam_auth)
	if not bool(ticket_result.get("ok", false)):
		_end(false)
		return {
			"ok": false,
			"error_kind": str(ticket_result.get("error_kind", "unknown")),
			"message": str(ticket_result.get("message", "")),
		}
	return ticket_result

func _end(used_ticket: bool = true) -> void:
	if used_ticket:
		_steam_auth.complete_ticket()
	_busy = false
	_released.emit()

## 戻り値: {"ok": bool, "error_kind": String, "message": String, "challenge_count": int}
## ticket取得に失敗した場合もエラーを返すだけで例外にはしない
## (呼び出し側がベストエフォートとして無視できるようにするため)。
## 2026-10-23: 応答に最初の戦闘の戦闘チケット（battle_ticket）が入る（サーバーが出せた時）。
func record_challenge_attempt(boss_id: String) -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.record_challenge_attempt(str(ticket_result.get("hex", "")), boss_id)
	_end()
	return response

## 旧来のクリアの記録（戦闘チケットの無い勝ちの討伐記録の判断にだけ使う。挑戦者数・クリア率・難関ボス討伐には数えない）。
func record_challenge_clear(boss_id: String) -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.record_challenge_clear(str(ticket_result.get("hex", "")), boss_id)
	_end()
	return response

## 2026-10-23: 次の戦闘の戦闘チケット。
func issue_battle_ticket(boss_id: String) -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.issue_battle_ticket(str(ticket_result.get("hex", "")), boss_id)
	_end()
	return response

## 2026-10-23: 決着した戦闘の結果（送信待ち）をまとめて送る。next_ticket_boss_id を渡すと次の戦闘のチケットも受け取る。
func submit_battle_results(results: Array, next_ticket_boss_id: String = "") -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.submit_battle_results(str(ticket_result.get("hex", "")), results, next_ticket_boss_id)
	_end()
	return response

## 2026-10-23: 自分が難関ボス討伐に認定されたボスの id（{"ok": true, "boss_ids": [...]}）。Steam の ticket で本人を確かめる。
func list_my_hard_awards() -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.list_my_hard_awards(str(ticket_result.get("hex", "")))
	_end()
	return response

## 2026-10-29 体験版: 異なるオンラインボスへの挑戦の使用状況（○ / 15体）。Steam の ticket で本人を確かめる。
func demo_challenge_status() -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.demo_challenge_status(str(ticket_result.get("hex", "")))
	_end()
	return response

## 「未挑戦」一覧取得もSteam ticketが必要(サーバー側で本人確認するため、
## list_bosses()と違い匿名では呼べない)。戻り値の形はlist_bosses()と同じ
## ({"ok":true,"bosses":[...]}または{"ok":false,"error_kind":...})——
## 呼び出し側(RBMOnlineBossListView)が同じレンダリング経路をそのまま使える。
func list_unchallenged_bosses(mode: String, limit: int = 20) -> Dictionary:
	var ticket_result := await _begin()
	if not bool(ticket_result.get("ok", false)):
		return ticket_result
	var response: Dictionary = await _api_adapter.list_unchallenged_bosses(str(ticket_result.get("hex", "")), mode, limit)
	_end()
	return response
