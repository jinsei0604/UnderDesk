extends GutTest

## Supabase最小接続PoC §7/§8 — RBMSupabaseConfigの解決ロジック（環境変数
## 優先、ローカル設定ファイルへのフォールバック、未設定時の空文字列）を
## 実ネットワーク・実.envファイルへ一切触れずに検証する。
##
## §9セキュリティ確認: このテストファイル自身にも実在のSupabase資格情報を
## 一切書かない——すべてダミー値・テスト専用の一時ファイルのみを使う。

const TEST_CONFIG_PATH := "user://bossmaker_test_supabase/config.env"

func before_each() -> void:
	RBMSupabaseConfig.set_local_config_path_for_testing(TEST_CONFIG_PATH)
	_clear_env()
	_remove_test_file()

func after_each() -> void:
	_clear_env()
	_remove_test_file()
	RBMSupabaseConfig.set_local_config_path_for_testing("")

func _clear_env() -> void:
	# GDScriptにはOS.set_environment()の取り消し(unset)手段が無いため、
	# このプロセス自体に実行時点でSUPABASE_URL/SUPABASE_PUBLISHABLE_KEYが
	# 実際に設定されていないことを前提とする（CI/開発機にこれらの環境変数
	# が既に設定されている場合、環境変数優先のテストは自然に成立する一方、
	# 「ファイルのみで解決される」系のテストが誤って環境変数の値を拾って
	# しまう可能性がある——該当テストはsanityとして早期にスキップする）。
	pass

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

func test_missing_url_and_key_are_both_empty_and_not_configured() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping the no-config case")
		return
	assert_eq(RBMSupabaseConfig.url(), "")
	assert_eq(RBMSupabaseConfig.publishable_key(), "")
	assert_false(RBMSupabaseConfig.is_configured())

func test_reads_url_and_key_from_the_local_config_file() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping the file-only case")
		return
	_write_test_file("SUPABASE_URL=https://example-project.supabase.co\nSUPABASE_PUBLISHABLE_KEY=sb_publishable_dummy_value_for_test\n")
	assert_eq(RBMSupabaseConfig.url(), "https://example-project.supabase.co")
	assert_eq(RBMSupabaseConfig.publishable_key(), "sb_publishable_dummy_value_for_test")
	assert_true(RBMSupabaseConfig.is_configured())

func test_ignores_blank_lines_and_comment_lines_in_the_local_config_file() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty():
		pending("this machine already has SUPABASE_URL set in its real environment; skipping")
		return
	_write_test_file("# comment line\n\nSUPABASE_URL=https://commented.supabase.co\n# another comment\n")
	assert_eq(RBMSupabaseConfig.url(), "https://commented.supabase.co")

func test_missing_local_config_file_resolves_to_empty_string_not_a_crash() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty():
		pending("this machine already has SUPABASE_URL set in its real environment; skipping")
		return
	assert_false(FileAccess.file_exists(TEST_CONFIG_PATH), "sanity: file must not exist for this test")
	assert_eq(RBMSupabaseConfig.url(), "")

## §8: URL未設定とkey未設定を個別に区別できること——is_configured()自体は
## 「どちらか片方でも欠けていればfalse」という単純な集約だが、
## RBMSupabaseClient._config_error()がこの2つを別々に判定できるよう、
## url()/publishable_key()がそれぞれ独立して正しい値を返すことを確認する。
func test_url_and_key_are_resolved_independently() -> void:
	if not OS.get_environment("SUPABASE_URL").is_empty() or not OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty():
		pending("this machine already has SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY set in its real environment; skipping")
		return
	_write_test_file("SUPABASE_URL=https://only-url-set.supabase.co\n")
	assert_eq(RBMSupabaseConfig.url(), "https://only-url-set.supabase.co")
	assert_eq(RBMSupabaseConfig.publishable_key(), "", "key must still be empty when only the URL line is present")
	assert_false(RBMSupabaseConfig.is_configured())
