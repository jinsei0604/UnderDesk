extends GutTest

## Supabase最小接続PoC §7/§8 — RBMSupabaseClientのうち、実ネットワークを
## 一切使わずに検証できる部分（設定未完了時のエラー種別の区別、
## ヘッダの組み立て）だけを対象にする。実際のHTTP往復自体は
## tools/supabase_poc/verify_connection.gd（手動実行、実Supabaseが必要）で
## 確認する——このテストファイルはCIや通常のgdir一括実行でネットワーク
## 有無に左右されないことを保証する。

const TEST_CONFIG_PATH := "user://bossmaker_test_supabase_client/config.env"

func before_each() -> void:
	RBMSupabaseConfig.set_local_config_path_for_testing(TEST_CONFIG_PATH)
	_remove_test_file()

func after_each() -> void:
	_remove_test_file()
	RBMSupabaseConfig.set_local_config_path_for_testing("")

func _remove_test_file() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	var dir_path := TEST_CONFIG_PATH.get_base_dir()
	if DirAccess.dir_exists_absolute(dir_path):
		DirAccess.remove_absolute(dir_path)

func _write_test_file(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_CONFIG_PATH.get_base_dir())
	var file := FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _new_client() -> RBMSupabaseClient:
	var client := RBMSupabaseClient.new()
	add_child_autofree(client)
	return client

func test_missing_url_is_reported_as_not_configured_url() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty():
		pending("this machine already has SUPABASE_URL set in its real environment; skipping")
		return
	var client := _new_client()
	var result: Dictionary = await client.insert_test_boss("TEST BOSS", {})
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "not_configured_url")

func test_missing_key_is_reported_as_not_configured_key_distinctly_from_missing_url() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping")
		return
	_write_test_file("SUPABASE_URL=https://example-project.supabase.co\n")
	var client := _new_client()
	var result: Dictionary = await client.fetch_test_bosses()
	assert_false(result.get("ok", false))
	assert_eq(result.get("error_kind", ""), "not_configured_key", "must be distinguishable from not_configured_url")

## §6: Publishable keyは"apikey"ヘッダのみへ載せ、"Authorization: Bearer"へは
## 重ねて載せない（2026年時点のSupabase公式ガイド"Migrating to publishable
## and secret API keys"の明示指示——匿名アクセス時にAuthorizationへも同じ
## 値を載せると、SupabaseがそれをJWTとして解釈しようとして拒否される）。
func test_headers_use_apikey_only_and_never_send_authorization_bearer() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping")
		return
	_write_test_file("SUPABASE_URL=https://example-project.supabase.co\nSUPABASE_PUBLISHABLE_KEY=sb_publishable_dummy_value_for_test\n")
	var client := _new_client()
	var headers: PackedStringArray = client._headers()
	var has_apikey := false
	var has_authorization := false
	for header in headers:
		if str(header).begins_with("apikey:"):
			has_apikey = true
			assert_true(str(header).contains("sb_publishable_dummy_value_for_test"))
		if str(header).to_lower().begins_with("authorization:"):
			has_authorization = true
	assert_true(has_apikey, "apikey header must be present")
	assert_false(has_authorization, "Authorization header must NOT be sent for anonymous publishable-key access")

func test_headers_include_json_content_type() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping")
		return
	_write_test_file("SUPABASE_URL=https://example-project.supabase.co\nSUPABASE_PUBLISHABLE_KEY=sb_publishable_dummy_value_for_test\n")
	var client := _new_client()
	var headers: PackedStringArray = client._headers()
	var has_json_content_type := false
	for header in headers:
		if str(header).to_lower() == "content-type: application/json":
			has_json_content_type = true
	assert_true(has_json_content_type)
