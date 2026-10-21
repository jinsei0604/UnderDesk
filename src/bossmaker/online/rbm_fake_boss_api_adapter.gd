class_name RBMFakeBossApiAdapter
extends RBMBossApiAdapter

## Phase 4C/4D/4E — RBMBossApiAdapterと同じ公開面を持つテスト専用の偽実装。
## 実HTTPには一切触れない(RBMFakeSteamAdapterと同じ既存パターン)。
## テストが`configure_*`で応答をあらかじめ用意し、呼ばれた引数を記録する。

var _publish_response: Dictionary = {"ok": true, "boss_id": "fake-boss-id", "revision": 1}
var _unpublish_response: Dictionary = {"ok": true}
var _list_response: Dictionary = {"ok": true, "bosses": []}
var _get_response: Dictionary = {"ok": true, "boss": {}}
## 既定の応答は今のサーバーと同じ形（by_owner: 記録した本人がボスの作者か。2026-10-22。ここでは作者ではない人の挑戦）
var _record_attempt_response: Dictionary = {"ok": true, "challenge_count": 1, "by_owner": false}
var _record_clear_response: Dictionary = {"ok": true, "clear_count": 1, "by_owner": false}
## 2026-10-23: 難関の認定の一覧（今のサーバーと同じ形）
var _list_my_hard_awards_response: Dictionary = {"ok": true, "boss_ids": []}
var list_my_hard_awards_calls := 0
## 2026-10-23: 戦闘チケットの偽のサーバー（本物の submit_boss_battle_result と同じ決まり: 1チケット1結果・同じ結果の
## 送り直しは duplicate・別の結果は used・知らないチケット・ボス違いは invalid・期限切れは expired）。
## tickets_enabled = false（既定）は旧版のサーバー（挑戦の記録の応答にチケットが無く、チケット・結果の関数が無い = 404）。
## 今のサーバーを試すテストは true にする。数えた結果の応答の by_owner・hard_awarded・first_clear_rate は、
## configure_record_clear_response() の値を使う（勝ちの時。負けは by_owner だけ）。
var tickets_enabled := false
## チケットを出さない理由（"" なら出す。rate_limited・daily_limit・not_found）。
var ticket_refusal := ""
## true の間、チケット・結果の通信は届かない（network_error。通信断）。
var network_down := false
## true にすると、次の結果の送信は「サーバーでは数えたが応答が届かなかった」にする（1回だけ）。
var lose_next_submit_response := false
var server_tickets: Dictionary = {}
var counted_results: Array[Dictionary] = []
var submit_calls: Array[Dictionary] = []
var issue_ticket_calls: Array[String] = []
var _ticket_serial := 0
var _list_unchallenged_response: Dictionary = {"ok": true, "bosses": []}
var _list_popular_response: Dictionary = {"ok": true, "bosses": []}
var _list_hard_response: Dictionary = {"ok": true, "bosses": []}
## ページ送りのテスト用(2026-10): cursorごとのlist_bosses()の応答(""=先頭ページ)。
## ここに無いcursorはconfigure_list_response()の応答を返す。
var _list_responses_by_cursor: Dictionary = {}
## list_bosses()が応答を返すまで待つフレーム数(取得中の二重押下などを試すため)。0なら即座に返す。
var list_delay_frames := 0
## get_boss()が応答を返すまで待つフレーム数(詳細の取得中の表示・選び直しを試すため)。0なら即座に返す。
var get_delay_frames := 0

var publish_calls: Array[Dictionary] = []
var unpublish_calls: Array[Dictionary] = []
var list_calls: Array[Dictionary] = []
var get_calls: Array[String] = []
var record_attempt_calls: Array[Dictionary] = []
var record_clear_calls: Array[Dictionary] = []
var list_unchallenged_calls: Array[Dictionary] = []
var list_popular_calls: Array[Dictionary] = []
var list_hard_calls: Array[Dictionary] = []
## 検索・ランダム（2026-10-17 PX-03）。検索は検索語ごと・cursorごとの応答（無ければ _search_response）。
var _search_response: Dictionary = {"ok": true, "bosses": []}
var _search_responses: Dictionary = {}
var _random_responses: Array[Dictionary] = []
var _random_response: Dictionary = {"ok": true, "bosses": []}
var search_calls: Array[Dictionary] = []
var random_calls: Array[Dictionary] = []
## search_bosses()・random_boss()が応答を返すまで待つフレーム数。
var search_delay_frames := 0

func _ready() -> void:
	pass # 実HTTPRequestは作らない。

func configure_publish_response(response: Dictionary) -> void:
	_publish_response = response

func configure_unpublish_response(response: Dictionary) -> void:
	_unpublish_response = response

func configure_list_response(response: Dictionary) -> void:
	_list_response = response

func configure_list_pages(responses_by_cursor: Dictionary) -> void:
	_list_responses_by_cursor = responses_by_cursor.duplicate(true)

func configure_get_response(response: Dictionary) -> void:
	_get_response = response

func configure_record_attempt_response(response: Dictionary) -> void:
	_record_attempt_response = response

func configure_record_clear_response(response: Dictionary) -> void:
	_record_clear_response = response


func configure_list_my_hard_awards_response(response: Dictionary) -> void:
	_list_my_hard_awards_response = response

func configure_list_unchallenged_response(response: Dictionary) -> void:
	_list_unchallenged_response = response

func configure_list_popular_response(response: Dictionary) -> void:
	_list_popular_response = response

func configure_list_hard_response(response: Dictionary) -> void:
	_list_hard_response = response

func publish(ticket_hex: String, payload: Dictionary, boss_id: String = "") -> Dictionary:
	publish_calls.append({"ticket": ticket_hex, "payload": payload, "boss_id": boss_id})
	return _publish_response.duplicate(true)

func unpublish(ticket_hex: String, boss_id: String) -> Dictionary:
	unpublish_calls.append({"ticket": ticket_hex, "boss_id": boss_id})
	return _unpublish_response.duplicate(true)

func list_bosses(limit: int = 20, mode: String = "", cursor: String = "") -> Dictionary:
	list_calls.append({"limit": limit, "mode": mode, "cursor": cursor})
	for i in range(list_delay_frames):
		await get_tree().process_frame
	if _list_responses_by_cursor.has(cursor):
		return (_list_responses_by_cursor[cursor] as Dictionary).duplicate(true)
	return _list_response.duplicate(true)

func get_boss(id: String) -> Dictionary:
	get_calls.append(id)
	for i in range(get_delay_frames):
		await get_tree().process_frame
	return _get_response.duplicate(true)

func record_challenge_attempt(ticket_hex: String, boss_id: String) -> Dictionary:
	record_attempt_calls.append({"ticket": ticket_hex, "boss_id": boss_id})
	var response := _record_attempt_response.duplicate(true)
	if tickets_enabled and bool(response.get("ok", false)):
		var issued := _new_ticket(boss_id)
		if bool(issued.ok):
			response["battle_ticket"] = issued.battle_ticket
			response["ticket_expires_at"] = issued.expires_at
		else:
			response["ticket_status"] = issued.error_kind
	return response

func record_challenge_clear(ticket_hex: String, boss_id: String) -> Dictionary:
	record_clear_calls.append({"ticket": ticket_hex, "boss_id": boss_id})
	return _record_clear_response.duplicate(true)

func issue_battle_ticket(_ticket_hex: String, boss_id: String) -> Dictionary:
	issue_ticket_calls.append(boss_id)
	if network_down:
		return RBMSupabaseResponse.network_error("offline")
	if not tickets_enabled:
		return {"ok": false, "error_kind": "http_404", "message": "not found", "http_status": 404}
	return _new_ticket(boss_id)

func submit_battle_results(_ticket_hex: String, results: Array, next_ticket_boss_id: String = "") -> Dictionary:
	submit_calls.append({"results": results.duplicate(true), "next_ticket_boss_id": next_ticket_boss_id})
	if network_down:
		return RBMSupabaseResponse.network_error("offline")
	if not tickets_enabled:
		return {"ok": false, "error_kind": "http_404", "message": "not found", "http_status": 404}
	var out: Array = []
	for r in results:
		out.append(_submit_one(r))
	var response := {"ok": true, "results": out}
	if not next_ticket_boss_id.is_empty():
		var issued := _new_ticket(next_ticket_boss_id)
		if bool(issued.ok):
			response["next_battle_ticket"] = issued.battle_ticket
			response["next_ticket_expires_at"] = issued.expires_at
		else:
			response["next_ticket_status"] = issued.error_kind
	if lose_next_submit_response:
		lose_next_submit_response = false
		return RBMSupabaseResponse.network_error("the response was lost")
	return response

## サーバーが出したチケットを期限切れにする（30日を過ぎた時）。
func expire_ticket(battle_ticket: String) -> void:
	if server_tickets.has(battle_ticket):
		server_tickets[battle_ticket].expired = true

func _new_ticket(boss_id: String) -> Dictionary:
	if not ticket_refusal.is_empty():
		return {"ok": false, "error_kind": ticket_refusal, "message": "refused", "http_status": 429}
	_ticket_serial += 1
	var ticket := "00000000-0000-4000-8000-%012d" % _ticket_serial
	server_tickets[ticket] = {"boss_id": boss_id, "result_id": "", "outcome": "", "expired": false}
	return {"ok": true, "battle_ticket": ticket, "expires_at": "2026-11-22T00:00:00Z"}

func _submit_one(r: Dictionary) -> Dictionary:
	var rid := str(r.get("result_id", ""))
	var outcome := str(r.get("outcome", ""))
	var t: Variant = server_tickets.get(str(r.get("battle_ticket", "")), null)
	if t == null or str(t.boss_id) != str(r.get("boss_id", "")) or (outcome != "clear" and outcome != "loss") or rid.is_empty():
		return {"result_id": rid, "status": "invalid"}
	if not str(t.result_id).is_empty():
		if str(t.result_id) == rid and str(t.outcome) == outcome:
			return _counted(rid, "duplicate", outcome)
		return {"result_id": rid, "status": "used"}
	if bool(t.expired):
		return {"result_id": rid, "status": "expired"}
	for other in server_tickets.values():
		if str(other.result_id) == rid:
			return {"result_id": rid, "status": "used"}
	t.result_id = rid
	t.outcome = outcome
	counted_results.append({"boss_id": str(t.boss_id), "result_id": rid, "outcome": outcome})
	return _counted(rid, "counted", outcome)

func _counted(rid: String, status: String, outcome: String) -> Dictionary:
	var row := {"result_id": rid, "status": status, "by_owner": bool(_record_clear_response.get("by_owner", false))}
	if outcome == "clear":
		row["hard_awarded"] = _record_clear_response.get("hard_awarded", false)
		row["first_clear_rate"] = _record_clear_response.get("first_clear_rate", null)
	else:
		row["hard_awarded"] = false
		row["first_clear_rate"] = null
	return row

func list_my_hard_awards(_ticket_hex: String) -> Dictionary:
	list_my_hard_awards_calls += 1
	return _list_my_hard_awards_response.duplicate(true)

func list_unchallenged_bosses(ticket_hex: String, mode: String = "", limit: int = 20) -> Dictionary:
	list_unchallenged_calls.append({"ticket": ticket_hex, "mode": mode, "limit": limit})
	return _list_unchallenged_response.duplicate(true)

func list_popular_bosses(limit: int = 20, mode: String = "") -> Dictionary:
	list_popular_calls.append({"limit": limit, "mode": mode})
	return _list_popular_response.duplicate(true)

func list_hard_bosses(limit: int = 20, mode: String = "") -> Dictionary:
	list_hard_calls.append({"limit": limit, "mode": mode})
	return _list_hard_response.duplicate(true)

func configure_search_response(response: Dictionary) -> void:
	_search_response = response

## key は「検索語」または「検索語|cursor」。
func configure_search_responses(responses: Dictionary) -> void:
	_search_responses = responses.duplicate(true)

## random_boss() の応答を呼ばれた順に返す（使い切ったら configure_random_response() の応答）。
func configure_random_sequence(responses: Array[Dictionary]) -> void:
	_random_responses = responses.duplicate(true)

func configure_random_response(response: Dictionary) -> void:
	_random_response = response

func search_bosses(query: String, limit: int = 20, mode: String = "", cursor: String = "") -> Dictionary:
	search_calls.append({"query": query, "limit": limit, "mode": mode, "cursor": cursor})
	for i in range(search_delay_frames):
		await get_tree().process_frame
	var key := query if cursor.is_empty() else "%s|%s" % [query, cursor]
	if _search_responses.has(key):
		return (_search_responses[key] as Dictionary).duplicate(true)
	return _search_response.duplicate(true)

func random_boss(mode: String = "", exclude_id: String = "") -> Dictionary:
	random_calls.append({"mode": mode, "exclude": exclude_id})
	for i in range(search_delay_frames):
		await get_tree().process_frame
	if not _random_responses.is_empty():
		return _random_responses.pop_front()
	return _random_response.duplicate(true)
