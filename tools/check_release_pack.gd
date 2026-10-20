extends SceneTree

## 書き出した pck の中身を確かめる（2026-10-18、P0）。書き出しの後に、エディター（同じ版）で pck を読んで動かす:
##   Godot_v4.7.2-stable_win64_console.exe --headless --main-pack <書き出し>/MakersAndChallengers.pck \
##       -s <リポジトリ>/tools/check_release_pack.gd -- --report=<出力.json>
## 確かめること: 配布用の公開設定が入っている（https・公開用の鍵だけ）、ローカルの設定・Steam の開発用 ID・
## テスト・検証の道具・資料が入っていない、ゲームの起動に要るものが入っている。値は出力しない。

const REQUIRED := ["supabase_public.env", "project.binary", "src/bossmaker/rbm_game_root.tscn", "localization/ui_strings.en.translation"]
const FORBIDDEN_FILES := ["supabase_poc.local.env", "supabase_poc.local.env.example", "steam_dev_appid.local.txt", "steam_appid.txt", "export_presets.cfg"]
const FORBIDDEN_DIRS := ["tests", "prototypes", "supabase", "docs", "addons/gut"]

var files: Array[String] = []

func _initialize() -> void:
	_walk("res://")
	var problems: Array[String] = []
	for r in REQUIRED:
		if not _has(r):
			problems.append("missing: " + r)
	for f in FORBIDDEN_FILES:
		if _has(f):
			problems.append("must not ship: " + f)
	for d in FORBIDDEN_DIRS:
		for f in files:
			if f.begins_with(d + "/"):
				problems.append("must not ship: " + d + "/ (" + f + ")")
				break
	var tools_in_pack := files.filter(func(f): return f.begins_with("tools/"))
	var values := RBMSupabaseConfig._read_file(RBMSupabaseConfig.DEFAULT_PUBLIC_CONFIG_PATH)
	var public_problem := RBMSupabaseConfig.public_values_problem(str(values.get("SUPABASE_URL", "")), str(values.get("SUPABASE_PUBLISHABLE_KEY", "")))
	if not public_problem.is_empty():
		problems.append("public config: " + public_problem)
	if values.keys().size() != 2:
		problems.append("public config must hold exactly 2 keys")
	var report := {
		"files": files.size(),
		"tools_files": tools_in_pack,
		"public_config_ok": public_problem.is_empty() and values.keys().size() == 2,
		"problems": problems,
		"engine": Engine.get_version_info().string,
	}
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--report="):
			out = a.substr(9)
	if not out.is_empty():
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string(JSON.stringify(report, "\t"))
		fa.close()
	print("PACK_CHECK files=%d tools=%d public_config_ok=%s problems=%d" % [files.size(), tools_in_pack.size(), report.public_config_ok, problems.size()])
	for p in problems:
		printerr("PACK_PROBLEM ", p)
	quit(0 if problems.is_empty() else 1)

func _has(rel: String) -> bool:
	return files.has(rel) or files.has(rel + ".remap")

func _walk(dir: String) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d == ".godot":
			continue
		_walk(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		files.append(dir.path_join(f).trim_prefix("res://"))
