class_name RBMSupabaseClient
extends Node

## Supabase最小接続PoC §6/§7/§8 — GodotからSupabase Data API(PostgREST)へ
## HTTP通信する最小クライアント。依存ライブラリを追加せず、Godot標準の
## HTTPRequestノードのみを使う。
##
## 接続確認専用テーブル(boss_connection_tests)専用——本番bossesテーブルへ
## の一般的なCRUDクライアントではない（§3、意図的に分離）。
##
## 使い方（呼び出し側がこのNodeをシーンツリーへ追加する必要がある——
## HTTPRequestは自分がツリーに入っていないと動作しない、既存の
## RBMChallengeBattleView等と同じ「呼び出し側がadd_childする軽量Node」の
## 流儀で、新しいautoload/シングルトンは導入しない）:
##
##   var client := RBMSupabaseClient.new()
##   add_child(client)
##   var insert_result := await client.insert_test_boss("TEST BOSS", {...})
##   var fetch_result := await client.fetch_test_bosses()
##
## 認証ヘッダ（§6「古い情報を推測せず公式仕様を確認する」、2026年時点の
## Supabase公式ガイド"Migrating to publishable and secret API keys"より）:
## Publishable keyは"apikey"ヘッダのみへ載せる——"Authorization: Bearer
## <publishable key>"へも重ねて載せると、SupabaseがそれをJWTとして解釈
## しようとして"Invalid JWT"エラーになる（匿名アクセス時はAuthorization
## ヘッダ自体を省略するのが正しい）。旧来の anon key 時代の「apikeyと
## Authorization Bearerの両方に同じ値を載せる」という広く見られた実装例は、
## publishable keyについては踏襲しない。

const TABLE_NAME := "boss_connection_tests"

var _http_request: HTTPRequest

func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "SupabasePocHttpRequest"
	add_child(_http_request)

## §7①②③: "TEST BOSS"をSupabaseへPOSTする。nameとboss_dataは呼び出し側が
## 渡す（PoCなので固定文言をこのクラス自身に持たせない）。
func insert_test_boss(name: String, boss_data: Dictionary) -> Dictionary:
	var config_error := _config_error()
	if not config_error.is_empty():
		return config_error

	var url := "%s/rest/v1/%s" % [RBMSupabaseConfig.url(), TABLE_NAME]
	var headers := _headers()
	# Prefer: return=representation — 挿入した行をそのままレスポンス本文で
	# 受け取る（§7④「取得結果にTEST BOSSが存在することを確認」を、INSERTの
	# 応答だけでも即座に検証できるようにするため）。
	headers.append("Prefer: return=representation")
	var payload := JSON.stringify({"name": name, "boss_data": boss_data})

	var request_error := _http_request.request(url, headers, HTTPClient.METHOD_POST, payload)
	if request_error != OK:
		return RBMSupabaseResponse.network_error("HTTPRequest.request() returned error code %d" % request_error)

	var completed: Array = await _http_request.request_completed
	return _interpret(completed)

## §7④⑤⑥: 保存済みのテスト用ボスを全件取得する。
func fetch_test_bosses() -> Dictionary:
	var config_error := _config_error()
	if not config_error.is_empty():
		return config_error

	var url := "%s/rest/v1/%s?select=*&order=created_at.desc" % [RBMSupabaseConfig.url(), TABLE_NAME]
	var headers := _headers()

	var request_error := _http_request.request(url, headers, HTTPClient.METHOD_GET)
	if request_error != OK:
		return RBMSupabaseResponse.network_error("HTTPRequest.request() returned error code %d" % request_error)

	var completed: Array = await _http_request.request_completed
	return _interpret(completed)

## §8: URL未設定/Publishable key未設定を個別に区別できるエラーを返す
## （どちらも未設定の場合はURL側を先に報告する）。設定済みなら空Dictionary。
func _config_error() -> Dictionary:
	if RBMSupabaseConfig.url().is_empty():
		return {
			"ok": false, "error_kind": "not_configured_url", "http_status": -1,
			"message": "SUPABASE_URLが設定されていません（環境変数、または supabase_poc.local.env）。",
			"supabase_message": "", "supabase_code": "", "rows": [],
		}
	if RBMSupabaseConfig.publishable_key().is_empty():
		return {
			"ok": false, "error_kind": "not_configured_key", "http_status": -1,
			"message": "SUPABASE_PUBLISHABLE_KEYが設定されていません（環境変数、または supabase_poc.local.env）。",
			"supabase_message": "", "supabase_code": "", "rows": [],
		}
	return {}

func _headers() -> PackedStringArray:
	# §8「Publishable keyそのものをログへ出力しない」——このヘッダ配列自体は
	# デバッグ出力に一切渡さない（呼び出し側のprint()は_interpret()が返す
	# Dictionaryのmessage/error_kind等だけを見る設計、keyの値そのものを
	# 含む変数をprintする経路がそもそも存在しない）。
	return PackedStringArray([
		"apikey: %s" % RBMSupabaseConfig.publishable_key(),
		"Content-Type: application/json",
	])

## HTTPRequest.request_completed の4引数 [result, response_code, headers, body]
## を、ネットワーク層の失敗(result != OK、DNS失敗等)とHTTPレベルの応答
## (response_code)とで分けて解釈する。
func _interpret(completed: Array) -> Dictionary:
	var result := int(completed[0])
	if result != HTTPRequest.RESULT_SUCCESS:
		return RBMSupabaseResponse.network_error("HTTPRequest result code %d (%s)" % [result, _result_name(result)])
	var response_code := int(completed[1])
	var body: PackedByteArray = completed[3]
	return RBMSupabaseResponse.parse(response_code, body)

func _result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "CONNECTION_ERROR"
		HTTPRequest.RESULT_TIMEOUT:
			return "TIMEOUT"
		_:
			return "ERROR_%d" % result
