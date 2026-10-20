extends SceneTree

## 配布用の公開設定ファイル（res://supabase_public.env）を作る・確かめる（2026-10-18、P0）。
## 配布版はローカル設定ファイル（supabase_poc.local.env）を持たないので、この1つのファイルから
## Project URL と Publishable key を読む（RBMSupabaseConfig）。
##
## 作る:   Godot --headless --path . -s res://tools/make_supabase_public_config.gd
##         環境変数（SUPABASE_URL・SUPABASE_PUBLISHABLE_KEY）か、ローカル設定ファイルの値を検査して書く。
## 確かめる: Godot --headless --path . -s res://tools/make_supabase_public_config.gd -- --check
##         今のファイルが「https の URL ＋ 公開用の鍵」だけであることを確かめる（書き出しの前に）。
##
## 秘密の鍵（sb_secret_…・service_role）は、書かない・通さない。値は画面にもログにも出さない。

func _initialize() -> void:
	var check_only := OS.get_cmdline_user_args().has("--check")
	var code := _check() if check_only else _make()
	quit(code)

func _make() -> int:
	var url := OS.get_environment(RBMSupabaseConfig.ENV_URL_KEY)
	var key := OS.get_environment(RBMSupabaseConfig.ENV_KEY_KEY)
	var from := "env"
	if url.is_empty() or key.is_empty():
		var local := RBMSupabaseConfig._read_local_file()
		url = str(local.get(RBMSupabaseConfig.ENV_URL_KEY, ""))
		key = str(local.get(RBMSupabaseConfig.ENV_KEY_KEY, ""))
		from = "local"
	var problem := RBMSupabaseConfig.public_values_problem(url, key)
	if not problem.is_empty():
		printerr("PUBLIC_CONFIG_REFUSED (", from, "): ", problem)
		return 1
	var text := "# 配布用の公開設定（tools/make_supabase_public_config.gd が書いた）。\n" \
		+ "# 配布版（書き出した版）だけが読む。Project URL と Publishable key だけ。\n" \
		+ "# 秘密の鍵（Secret key・service_role）は絶対に書かない。\n" \
		+ "%s=%s\n%s=%s\n" % [RBMSupabaseConfig.ENV_URL_KEY, url, RBMSupabaseConfig.ENV_KEY_KEY, key]
	var path := RBMSupabaseConfig.public_config_path()
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		printerr("PUBLIC_CONFIG_WRITE_FAILED ", FileAccess.get_open_error())
		return 1
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		printerr("PUBLIC_CONFIG_WRITE_FAILED rename")
		return 1
	print("PUBLIC_CONFIG_WRITTEN from=", from, " path=", path)
	return _check()

func _check() -> int:
	var path := RBMSupabaseConfig.public_config_path()
	if not FileAccess.file_exists(path):
		printerr("PUBLIC_CONFIG_MISSING ", path)
		return 1
	var values := RBMSupabaseConfig._read_file(path)
	var extra: Array = []
	for k in values.keys():
		if k != RBMSupabaseConfig.ENV_URL_KEY and k != RBMSupabaseConfig.ENV_KEY_KEY:
			extra.append(k)
	if not extra.is_empty():
		printerr("PUBLIC_CONFIG_HAS_EXTRA_KEYS ", extra)
		return 1
	var problem := RBMSupabaseConfig.public_values_problem(str(values.get(RBMSupabaseConfig.ENV_URL_KEY, "")), str(values.get(RBMSupabaseConfig.ENV_KEY_KEY, "")))
	if not problem.is_empty():
		printerr("PUBLIC_CONFIG_INVALID ", problem)
		return 1
	print("PUBLIC_CONFIG_OK path=", path, " keys=2 publishable=true https=true")
	return 0
