extends GutTest

## 配布版の Supabase の接続先（2026-10-18、P0）の回帰テスト。
## - 配布版（書き出した版）だけが、配布用の公開設定ファイル（res://supabase_public.env）を読む
## - エディター・GUT では今までどおり読まない（テストが本物の Supabase へ出ていかない）
## - 開発者の環境変数・ローカル設定ファイルが先（今までの開発の動き）
## - 秘密の鍵（sb_secret_…・service_role の JWT）は、どこから来ても使わない
## - 書き出しの設定（export_presets.cfg）が、公開設定を入れ、ローカルの設定・Steam の開発用 ID・テストを入れない
## 本物の鍵の値はこのファイルに書かない（ダミーだけ）。本物のファイルは「形」だけ確かめる。

const TEST_DIR := "user://bossmaker_test_supabase_public"
const LOCAL := TEST_DIR + "/local.env"
const PUBLIC := TEST_DIR + "/public.env"

func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	RBMSupabaseConfig.set_local_config_path_for_testing(LOCAL)
	RBMSupabaseConfig.set_public_config_path_for_testing(PUBLIC)

func after_each() -> void:
	RBMSupabaseConfig.set_local_config_path_for_testing("")
	RBMSupabaseConfig.set_public_config_path_for_testing("")
	RBMSupabaseConfig.set_distribution_build_for_testing(-1)
	for f in [LOCAL, PUBLIC]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(TEST_DIR)

func _write(path: String, url: String, key: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("# test\nSUPABASE_URL=%s\nSUPABASE_PUBLISHABLE_KEY=%s\n" % [url, key])
	f.close()

func _env_is_clean() -> bool:
	return OS.get_environment("SUPABASE_URL").is_empty() and OS.get_environment("SUPABASE_PUBLISHABLE_KEY").is_empty()

## role だけを持つ JWT の形（署名はダミー）
func _jwt(role: String) -> String:
	var b64 := func(s: String) -> String:
		return Marshalls.utf8_to_base64(s).replace("+", "-").replace("/", "_").replace("=", "")
	return "%s.%s.%s" % [b64.call("{\"alg\":\"HS256\",\"typ\":\"JWT\"}"), b64.call("{\"iss\":\"supabase\",\"role\":\"%s\"}" % role), "signature"]

func test_the_distribution_build_reads_the_public_config() -> void:
	if not _env_is_clean():
		pending("SUPABASE_* is set in this machine's environment")
		return
	_write(PUBLIC, "https://example-public.supabase.co", "sb_publishable_dummy_public")
	RBMSupabaseConfig.set_distribution_build_for_testing(1)
	assert_true(RBMSupabaseConfig.is_configured(), "ローカル設定ファイルが無い配布版でも、接続先がある")
	assert_eq(RBMSupabaseConfig.url(), "https://example-public.supabase.co")
	assert_eq(RBMSupabaseConfig.publishable_key(), "sb_publishable_dummy_public")
	assert_eq(RBMSupabaseConfig.source(), "public")

func test_the_editor_and_tests_never_read_the_public_config() -> void:
	if not _env_is_clean():
		pending("SUPABASE_* is set in this machine's environment")
		return
	_write(PUBLIC, "https://example-public.supabase.co", "sb_publishable_dummy_public")
	RBMSupabaseConfig.set_distribution_build_for_testing(0)
	assert_false(RBMSupabaseConfig.is_configured(), "エディター・GUT では今までどおり「設定なし」")
	assert_eq(RBMSupabaseConfig.source(), "")
	RBMSupabaseConfig.set_distribution_build_for_testing(-1)
	assert_false(RBMSupabaseConfig.is_distribution_build(), "GUT はエクスポートテンプレートではない")
	assert_false(RBMSupabaseConfig.is_configured())

func test_the_developers_local_file_still_comes_first() -> void:
	if not _env_is_clean():
		pending("SUPABASE_* is set in this machine's environment")
		return
	_write(LOCAL, "https://example-local.supabase.co", "sb_publishable_dummy_local")
	_write(PUBLIC, "https://example-public.supabase.co", "sb_publishable_dummy_public")
	RBMSupabaseConfig.set_distribution_build_for_testing(1)
	assert_eq(RBMSupabaseConfig.url(), "https://example-local.supabase.co")
	assert_eq(RBMSupabaseConfig.source(), "local")

func test_secret_keys_are_never_used_from_any_source() -> void:
	if not _env_is_clean():
		pending("SUPABASE_* is set in this machine's environment")
		return
	RBMSupabaseConfig.set_distribution_build_for_testing(1)
	for secret in ["sb_secret_dummy_value", _jwt("service_role")]:
		_write(PUBLIC, "https://example-public.supabase.co", secret)
		assert_eq(RBMSupabaseConfig.publishable_key(), "", "配布用の設定の秘密の鍵は使わない")
		assert_false(RBMSupabaseConfig.is_configured())
		DirAccess.remove_absolute(PUBLIC)
		_write(LOCAL, "https://example-local.supabase.co", secret)
		assert_eq(RBMSupabaseConfig.publishable_key(), "", "ローカル設定の秘密の鍵も使わない")
		DirAccess.remove_absolute(LOCAL)

func test_only_publishable_https_values_may_be_shipped() -> void:
	assert_eq(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", "sb_publishable_abc"), "")
	assert_eq(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", _jwt("anon")), "", "古い形式の anon の JWT も公開用")
	assert_ne(RBMSupabaseConfig.public_values_problem("http://x.supabase.co", "sb_publishable_abc"), "", "https でない")
	assert_ne(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", "sb_secret_abc"), "", "秘密の鍵")
	assert_ne(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", _jwt("service_role")), "", "service_role の JWT")
	assert_ne(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", "something-else"), "", "種類の分からない鍵")
	assert_ne(RBMSupabaseConfig.public_values_problem("", "sb_publishable_abc"), "")
	assert_ne(RBMSupabaseConfig.public_values_problem("https://x.supabase.co", "sb_publishable_"), "", "中身の無い鍵")
	assert_true(RBMSupabaseConfig.is_secret_key("sb_secret_abc"))
	assert_false(RBMSupabaseConfig.is_secret_key("sb_publishable_abc"))
	assert_false(RBMSupabaseConfig.is_secret_key(_jwt("anon")))

## 2026-10-20: 実ファイルは Git で管理しない（書き出しの時に写しの中で作る）。作業ツリーに置かれていても commit されない
func test_the_public_config_file_is_never_committed() -> void:
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	var lines := Array(ignore.replace("\r", "").split("\n"))
	assert_true(lines.has("supabase_public.env"), ".gitignore に配布用の公開設定がある")
	assert_true(lines.has("supabase_poc.local.env"), "開発用のローカル設定も今までどおり")

func test_a_public_config_file_left_in_the_tree_holds_only_a_publishable_key() -> void:
	RBMSupabaseConfig.set_public_config_path_for_testing("")
	var path := RBMSupabaseConfig.DEFAULT_PUBLIC_CONFIG_PATH
	if not FileAccess.file_exists(path):
		pass_test("作業ツリーには無い（書き出しの時に写しの中で作る。これが通常）")
		return
	var values := RBMSupabaseConfig._read_file(path)
	assert_eq(values.keys().size(), 2, "URL と公開用の鍵の2つだけ")
	var url := str(values.get("SUPABASE_URL", ""))
	var key := str(values.get("SUPABASE_PUBLISHABLE_KEY", ""))
	assert_eq(RBMSupabaseConfig.public_values_problem(url, key), "", "https の URL と公開用の鍵（値はテストの出力に出さない）")
	assert_false(RBMSupabaseConfig.is_secret_key(key))

func test_the_export_preset_ships_the_public_config_and_nothing_local() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK, "書き出しの設定がある")
	var found_release := false
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if str(cfg.get_value(section, "platform", "")) != "Windows Desktop":
			continue
		var include := str(cfg.get_value(section, "include_filter", ""))
		var exclude := str(cfg.get_value(section, "exclude_filter", ""))
		assert_true(include.contains("supabase_public.env"), "%s: 公開設定を入れる" % section)
		for must_exclude in ["supabase_poc.local.env", "steam_dev_appid.local.txt", "steam_appid.txt", "tests/*", "prototypes/*", "supabase/*", "addons/gut/*"]:
			assert_true(exclude.contains(must_exclude), "%s: %s を入れない" % [section, must_exclude])
		if str(cfg.get_value(section, "name", "")) == "Windows Desktop":
			found_release = true
			assert_true(exclude.contains("tools/*"), "配布版には検証の道具も入れない")
	assert_true(found_release, "配布用の Windows の設定がある")
