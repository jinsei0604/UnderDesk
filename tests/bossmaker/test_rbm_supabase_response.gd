extends GutTest

## Supabase最小接続PoC §7/§8 — RBMSupabaseResponse.parse()の解釈ロジックを
## 実ネットワーク無しで検証する（HTTPRequestを一切使わない、response_code+
## bodyを直接渡すだけの純粋関数テスト）。

func _body(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()

func test_2xx_with_json_array_body_parses_rows() -> void:
	var result := RBMSupabaseResponse.parse(201, _body('[{"id":"abc","name":"TEST BOSS","boss_data":{"hp":1000}}]'))
	assert_true(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "")
	assert_eq(result.get("http_status", -1), 201)
	var rows: Array = result.get("rows", [])
	assert_eq(rows.size(), 1)
	assert_eq(str((rows[0] as Dictionary).get("name", "")), "TEST BOSS")

func test_2xx_with_empty_body_is_success_with_no_rows() -> void:
	var result := RBMSupabaseResponse.parse(204, _body(""))
	assert_true(result.get("ok", false))
	assert_eq((result.get("rows", []) as Array).size(), 0)

func test_4xx_is_reported_as_http_4xx_not_5xx() -> void:
	var result := RBMSupabaseResponse.parse(401, _body('{"message":"Invalid API key","code":"401"}'))
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "http_4xx")
	assert_eq(result.get("http_status", -1), 401)
	assert_eq(result.get("supabase_message", ""), "Invalid API key")
	assert_eq(result.get("supabase_code", ""), "401")

func test_5xx_is_reported_as_http_5xx_not_4xx() -> void:
	var result := RBMSupabaseResponse.parse(503, _body('{"message":"upstream error"}'))
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "http_5xx")
	assert_eq(result.get("http_status", -1), 503)
	assert_eq(result.get("supabase_message", ""), "upstream error")

func test_rls_rejection_style_4xx_extracts_supabase_message_and_code() -> void:
	var result := RBMSupabaseResponse.parse(403, _body('{"code":"42501","message":"new row violates row-level security policy"}'))
	assert_eq(result.get("error_kind", ""), "http_4xx")
	assert_eq(result.get("supabase_code", ""), "42501")
	assert_true(str(result.get("supabase_message", "")).contains("row-level security"))

func test_2xx_with_malformed_json_body_is_json_parse_failed() -> void:
	var result := RBMSupabaseResponse.parse(200, _body("{this is not valid json"))
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "json_parse_failed")

func test_error_body_that_is_not_json_does_not_crash_and_still_reports_http_status() -> void:
	var result := RBMSupabaseResponse.parse(500, _body("<html>Internal Server Error</html>"))
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "http_5xx")
	assert_eq(result.get("supabase_message", ""), "", "non-JSON error bodies must not crash the parser, just yield an empty supabase_message")

func test_network_error_has_its_own_distinct_error_kind() -> void:
	var result := RBMSupabaseResponse.network_error("DNS resolution failed")
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "network_error")
	assert_eq(result.get("http_status", -1), -1)
	assert_true(str(result.get("message", "")).contains("DNS resolution failed"))

func test_single_object_body_is_wrapped_as_a_one_row_array() -> void:
	# PostgRESTは通常配列を返すが、万一単一オブジェクトが返っても
	# rows配列として扱えるようにしておく（防御的な扱い、クラッシュ回避）。
	var result := RBMSupabaseResponse.parse(200, _body('{"id":"abc","name":"TEST BOSS"}'))
	assert_true(result.get("ok", false))
	var rows: Array = result.get("rows", [])
	assert_eq(rows.size(), 1)
	assert_eq(str((rows[0] as Dictionary).get("name", "")), "TEST BOSS")
