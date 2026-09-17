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

func _request(url: String, method: HTTPClient.Method, body: String = "") -> Dictionary:
	_ensure_ready()
	var config_error := _config_error()
	if not config_error.is_empty():
		return config_error
	var request_error := _http_request.request(url, _headers(), method, body)
	if request_error != OK:
		return RBMSupabaseResponse.network_error("HTTPRequest.request() returned error code %d" % request_error)
	var completed: Array = await _http_request.request_completed
	return _interpret(completed)

func _interpret(completed: Array) -> Dictionary:
	var result := int(completed[0])
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
func list_bosses(limit: int = 20, mode: String = "") -> Dictionary:
	var url := _function_url("list-bosses") + "?limit=%d" % limit
	if not mode.is_empty():
		url += "&mode=%s" % mode.uri_encode()
	return await _request(url, HTTPClient.METHOD_GET)

func get_boss(id: String) -> Dictionary:
	return await _request(_function_url("get-boss") + "?id=%s" % id.uri_encode(), HTTPClient.METHOD_GET)

## Phase 5 — オンライン版「未挑戦」。ticket_hex取得済み(RBMSteamTicketProvider
## 経由)であることが前提——SteamIDはこのクラス自身ではなくサーバー側の
## SteamTicketVerifierが確定する(クライアントは一切自己申告しない)。
func record_challenge_attempt(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id}
	return await _request(_function_url("record-challenge-attempt"), HTTPClient.METHOD_POST, JSON.stringify(body))

func record_challenge_clear(ticket_hex: String, boss_id: String) -> Dictionary:
	var body := {"ticket": ticket_hex, "boss_id": boss_id}
	return await _request(_function_url("record-challenge-clear"), HTTPClient.METHOD_POST, JSON.stringify(body))

## list_bosses()と違い匿名GETではない——「誰にとっての未挑戦か」をサーバー
## 側でSteam ticketから確定させるため、ticketを渡すPOSTにする。
func list_unchallenged_bosses(ticket_hex: String, mode: String = "", limit: int = 20) -> Dictionary:
	var body := {"ticket": ticket_hex, "limit": limit}
	if not mode.is_empty():
		body["mode"] = mode
	return await _request(_function_url("list-unchallenged-bosses"), HTTPClient.METHOD_POST, JSON.stringify(body))
