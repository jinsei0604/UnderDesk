class_name RBMBossApiAdapter
extends Node

## Phase 4C/4D/4E — Supabase Edge Functions(publish-boss/list-bosses/
## get-boss/unpublish-boss)への実HTTPアクセスだけを行う薄いラッパー。
## RBMBossPublisher/RBMBossBrowserはこのクラスの公開メソッドだけに依存し、
## HTTPRequestへ直接触れない——GUTはRBMFakeBossApiAdapterへ差し替えて
## headlessでテストする(RBMSteamAdapter/RBMFakeSteamAdapterと同じ
## 既存パターン)。
##
## レスポンス解釈は既存のRBMSupabaseResponse(PostgREST向けに作られた
## 2xx/4xx/5xx/JSON解析失敗/ネットワークエラーの分類)をそのまま再利用する
## ——Edge Functionのレスポンス本文は単一のJSONオブジェクトなので、
## rows[0]として1件だけ取り出す。
##
## 呼び出し側がこのNodeをシーンツリーへ追加する既存の軽量Nodeの流儀
## (RBMSupabaseClient/RBMSteamAuthと同じ)。

var _http_request: HTTPRequest

func _ready() -> void:
	if _http_request == null:
		_http_request = HTTPRequest.new()
		_http_request.name = "BossApiHttpRequest"
		add_child(_http_request)

func _ensure_ready() -> void:
	if _http_request == null:
		_ready()

## 呼び出し側(RBMSteamConfig等)がURL/publishable keyの設定確認を既に
## 行っている前提——ここでは未設定時のエラーだけ返す。
func _config_error() -> Dictionary:
	if RBMSupabaseConfig.url().is_empty():
		return RBMSupabaseResponse.network_error(tr("SUPABASE_URLが設定されていません。"))
	if RBMSupabaseConfig.publishable_key().is_empty():
		return RBMSupabaseResponse.network_error(tr("SUPABASE_PUBLISHABLE_KEYが設定されていません。"))
	return {}

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: %s" % RBMSupabaseConfig.publishable_key(),
		"Authorization: Bearer %s" % RBMSupabaseConfig.publishable_key(),
		"Content-Type: application/json",
	])

func _function_url(name: String) -> String:
	return "%s/functions/v1/%s" % [RBMSupabaseConfig.url(), name]

## 1回の通信を待つ上限（秒）。返らない通信で画面が読み込み中のまま止まらないように（2026-10-17、PX-04）。
const REQUEST_TIMEOUT_SECONDS := 12.0

## 通信ごとに専用の HTTPRequest を作る（同時に複数の通信ができる。以前は1つの HTTPRequest を共有していたので、
## 返らない通信が1本あると、後の通信がすべて止まっていた。PX-04）。待ち時間の上限を超えたら network_error で返る。
## 送る内容・受け取った後の解釈（_interpret()）は変えない。
func _request(url: String, method: HTTPClient.Method, body: String = "") -> Dictionary:
	_ensure_ready()
	var config_error := _config_error()
	if not config_error.is_empty():
		return config_error
	# 体験版（RBMEdition）: サーバーへ体験版であることを伝える（一覧の ?edition=demo と、本文の "edition"）。
	# サーバーは Steam のチケットのアプリで本人の版を確かめ、体験版の範囲・上限をかける。製品版は何も足さない。
	if RBMEdition.is_demo():
		if method == HTTPClient.METHOD_GET:
			url += ("&" if url.contains("?") else "?") + "edition=%s" % RBMEdition.DEMO_EDITION
		elif not body.is_empty():
			var parsed_body = JSON.parse_string(body)
			if parsed_body is Dictionary:
				parsed_body["edition"] = RBMEdition.DEMO_EDITION
				body = JSON.stringify(parsed_body)
	var http := HTTPRequest.new()
	http.name = "BossApiRequest"
	http.timeout = REQUEST_TIMEOUT_SECONDS
	add_child(http)
	var request_error := http.request(url, _headers(), method, body)
	if request_error != OK:
		http.queue_free()
		return RBMSupabaseResponse.network_error("HTTPRequest.request() returned error code %d" % request_error)
	var completed: Array = await http.request_completed
	http.queue_free()
	return _limit_to_edition(_interpret(completed))

## 体験版: 一覧・ランキング・検索・ランダムの行を体験版で挑戦できるボス（SIMPLE・体験版の4体）だけにし、
## 範囲外のボスの詳細（get-boss）は開かない。サーバー側でも同じ範囲に絞る（まだ古いサーバーでも正しく出るよう、ここでも絞る）。
static func _limit_to_edition(response: Dictionary) -> Dictionary:
	if not RBMEdition.is_demo() or not bool(response.get("ok", false)):
		return response
	if response.get("bosses") is Array:
		var kept: Array = []
		for row in response["bosses"]:
			if row is Dictionary and RBMEdition.allows_online_boss(str(row.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), str(row.get("appearance_id", ""))):
				kept.append(row)
		response["bosses"] = kept
	if response.get("boss") is Dictionary and (response["boss"] as Dictionary).get("payload") is Dictionary:
		var fields = ((response["boss"] as Dictionary)["payload"] as Dictionary).get("draft_fields", {})
		if fields is Dictionary and not RBMEdition.allows_online_boss(str(fields.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), str(fields.get("appearance_id", ""))):
			return {"ok": false, "error_kind": "demo_unavailable", "message": "This boss is not available in the trial version."}
	return response

func _interpret(completed: Array) -> Dictionary:
	var result := int(completed[0])
	if result == HTTPRequest.RESULT_TIMEOUT:
		return RBMSupabaseResponse.network_error("timeout (%.0f s)" % REQUEST_TIMEOUT_SECONDS)
	if result != HTTPRequest.RESULT_SUCCESS:
		return RBMSupabaseResponse.network_error("HTTPRequest result code %d" % result)
	var response_code := int(completed[1])
	var body: PackedByteArray = completed[3]
	var parsed := RBMSupabaseResponse.parse(response_code, body)
	if not bool(parsed.get("ok", false)):
		return parsed
	var rows: Array = parsed.get("rows", [])
	if rows.is_empty() or not (rows[0] is Dictionary):
		return RBMSupabaseResponse.network_error("Edge Function returned an unexpected empty/non-object body")
	var row: Dictionary = rows[0]
	row["http_status"] = response_code
	return row

func publish(ticket_hex: String, payload: Dictionary, boss_id: String = "") -> Dictionary:
	var body := {"ticket": ticket_hex, "payload": payload}
	if not boss_id.is_empty():
		body["boss_id"] = boss_id
	return await _request(_function_url("publish-boss"), HTTPClient.METHOD_POST, JSON.stringify(body))

func unpublish(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id}
	return await _request(_function_url("unpublish-boss"), HTTPClient.METHOD_POST, JSON.stringify(body))

## mode: ""(絞り込みなし) / RBMCreatorDraft.CREATOR_MODE_SIMPLE / CREATOR_MODE_ADVANCED。
## 挑戦ハブ SIMPLE/HARDCORE連携(2026-09) — list-bossesは
## payload.draft_fields.creator_modeをサーバー側で抽出済みのcreator_mode
## フィールドを返す。フィルタ自体もサーバー側(list-bosses)で行う——
## クライアントは受け取った結果をそのまま表示するだけでよい。
## cursor(2026-10): 前のページの応答のnext_cursorを渡すと、その続きのページを返す
## (空なら最新の先頭ページ)。応答のhas_more/next_cursorで続きの有無が分かる。
func list_bosses(limit: int = 20, mode: String = "", cursor: String = "") -> Dictionary:
	var url := _function_url("list-bosses") + "?limit=%d" % limit
	if not mode.is_empty():
		url += "&mode=%s" % mode.uri_encode()
	if not cursor.is_empty():
		url += "&cursor=%s" % cursor.uri_encode()
	return await _request(url, HTTPClient.METHOD_GET)

func get_boss(id: String) -> Dictionary:
	return await _request(_function_url("get-boss") + "?id=%s" % id.uri_encode(), HTTPClient.METHOD_GET)

## Phase 5 — オンライン版「未挑戦」。ticket_hex取得済み(RBMSteamTicketProvider
## 経由)であることが前提——SteamIDはこのクラス自身ではなくサーバー側の
## SteamTicketVerifierが確定する(クライアントは一切自己申告しない)。
## 2026-10-23: 最初の戦闘の戦闘チケットも頼む（応答の battle_ticket。出せなければ ticket_status に理由）。
func record_challenge_attempt(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id, "want_battle_ticket": true}
	return await _request(_function_url("record-challenge-attempt"), HTTPClient.METHOD_POST, JSON.stringify(body))

## 旧来のクリアの記録（clear_count を足して by_owner を返すだけ。挑戦者数・クリア率・難関ボス討伐には数えない）。
## 2026-10-23 から、戦闘チケットの無い勝ち（通信できずに始めた戦闘など）の討伐記録の判断にだけ使う。
func record_challenge_clear(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id}
	return await _request(_function_url("record-challenge-clear"), HTTPClient.METHOD_POST, JSON.stringify(body))

## 2026-10-23: 次の戦闘の戦闘チケット（{"ok": true, "battle_ticket", "expires_at"}。上限なら error_kind が rate_limited など）。
func issue_battle_ticket(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id}
	return await _request(_function_url("issue-battle-ticket"), HTTPClient.METHOD_POST, JSON.stringify(body))

## 2026-10-23: 決着した戦闘の結果（送信待ちの最大20件、[{boss_id, battle_ticket, result_id, outcome}]）をまとめて送る。
## 応答: {"ok": true, "results": [{result_id, status, by_owner, hard_awarded, first_clear_rate}], "next_battle_ticket"?}。
## next_ticket_boss_id を渡すと、次の戦闘のチケットも同じ応答で受け取る。
func submit_battle_results(ticket_hex: String, results: Array, next_ticket_boss_id: String = "") -> Dictionary:
	var body := {"ticket": ticket_hex, "results": results}
	if not next_ticket_boss_id.is_empty():
		body["next_ticket_boss_id"] = next_ticket_boss_id
	return await _request(_function_url("submit-battle-result"), HTTPClient.METHOD_POST, JSON.stringify(body))

## 2026-10-23: 自分が難関ボス討伐に認定されたボスの id（{"ok": true, "boss_ids": [...]}）。認定はサーバー（DB）が決める。
## 2026-10-29 体験版: 異なるオンラインボスへの挑戦の使用状況（{"ok": true, "limited": true, "used", "limit",
## "challenged_boss_ids"}。製品版のチケットなら limited: false）。本人はサーバーが Steam の ticket で確かめる。
func demo_challenge_status(ticket_hex: String) -> Dictionary:
	return await _request(_function_url("demo-challenge-status"), HTTPClient.METHOD_POST, JSON.stringify({"ticket": ticket_hex}))

func list_my_hard_awards(ticket_hex: String) -> Dictionary:
	return await _request(_function_url("list-my-hard-awards"), HTTPClient.METHOD_POST, JSON.stringify({"ticket": ticket_hex}))

## list_bosses()と違い匿名GETではない——「誰にとっての未挑戦か」をサーバー
## 側でSteam ticketから確定させるため、ticketを渡すPOSTにする。
func list_unchallenged_bosses(ticket_hex: String, mode: String = "", limit: int = 20) -> Dictionary:
	var body := {"ticket": ticket_hex, "limit": limit}
	if not mode.is_empty():
		body["mode"] = mode
	return await _request(_function_url("list-unchallenged-bosses"), HTTPClient.METHOD_POST, JSON.stringify(body))

## Phase 6 — 「人気」/「高難度」。ランキング自体は特定のSteamユーザーに
## 紐づかない集計値のため、list_bosses()と同じ匿名GETでよい(ticket不要)
## ——challenge履歴の読み取り自体はサーバー側(service_role)でのみ行う。
func list_popular_bosses(limit: int = 20, mode: String = "") -> Dictionary:
	var url := _function_url("list-popular-bosses") + "?limit=%d" % limit
	if not mode.is_empty():
		url += "&mode=%s" % mode.uri_encode()
	return await _request(url, HTTPClient.METHOD_GET)

func list_hard_bosses(limit: int = 20, mode: String = "") -> Dictionary:
	var url := _function_url("list-hard-bosses") + "?limit=%d" % limit
	if not mode.is_empty():
		url += "&mode=%s" % mode.uri_encode()
	return await _request(url, HTTPClient.METHOD_GET)

## 公開ボスの検索（2026-10-17 PX-03、search-bosses）。query: ボス名・作者名の一部、または公開ID（RBMPublicBossId）。
## 応答は list_bosses() と同じ形（bosses・has_more・next_cursor）。続きは cursor で読む。
func search_bosses(query: String, limit: int = 20, mode: String = "", cursor: String = "") -> Dictionary:
	var url := _function_url("search-bosses") + "?q=%s&limit=%d" % [query.uri_encode(), limit]
	if not mode.is_empty():
		url += "&mode=%s" % mode.uri_encode()
	if not cursor.is_empty():
		url += "&cursor=%s" % cursor.uri_encode()
	return await _request(url, HTTPClient.METHOD_GET)

## ランダム挑戦（2026-10-17 PX-03、random-boss）。mode のボス全体（空ならすべて）から1件。exclude_id は今出しているボス
## （それ以外から選ぶ。ほかに無ければ同じボス）。応答の bosses は0件か1件。
func random_boss(mode: String = "", exclude_id: String = "") -> Dictionary:
	var params: Array[String] = []
	if not mode.is_empty():
		params.append("mode=%s" % mode.uri_encode())
	if not exclude_id.is_empty():
		params.append("exclude=%s" % exclude_id.uri_encode())
	var url := _function_url("random-boss")
	if not params.is_empty():
		url += "?" + "&".join(params)
	return await _request(url, HTTPClient.METHOD_GET)
