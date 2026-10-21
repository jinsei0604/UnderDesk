extends Node

## 書き出した版（Windows）のオンラインの実地の確認（2026-10-18、P0）。
## 検証用の書き出し（export_presets.cfg の「Windows Desktop Verify」）にだけ入る。配布版には入らない。
##
## 起動（書き出したフォルダで）:
##   MakersAndChallengers.console.exe res://tools/verify_export_online.tscn -- --report=<出力フォルダ> [--steam=1] [--ui=1]
## していること:
##   1. 接続先: どこから読んだか（配布用の公開設定か）・https・公開用の鍵か（値は書かない）
##   2. 読み取りだけの通信: list-bosses・人気・高難度・検索・ランダム・get-boss（無い ID → 404 になるか）
##      Supabase の入口（JWT の確認）を通れるかは、401 が返らないことで分かる
##   3. --steam=1: 本物の Steam の ticket で list-unchallenged-bosses（読み取りだけ。Steam の認証がサーバーで通るか）
##   4. --ui=1: 本物のゲームをタイトルから操作し、挑戦トップ → オンライン → 未挑戦 → ランダムの画面を撮る
## 書き込む通信（公開・挑戦の記録）はしない。Steam Cloud にも触れない。

var report := {"checks": [], "calls": [], "shots": [], "notes": []}
var out_dir := ""
var mouse := Vector2.ZERO

func _ready() -> void:
	out_dir = _arg("report", OS.get_user_data_dir().path_join("export_online_check"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	await _run()
	var f := FileAccess.open(out_dir.path_join("export_online_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var failed: int = (report.checks as Array).filter(func(c): return not bool(c.passed)).size()
	print("EXPORT_ONLINE_DONE checks=%d failed=%d" % [report.checks.size(), failed])
	get_tree().quit(0 if failed == 0 else 1)

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback

func _check(label: String, passed: bool, detail = "") -> void:
	report.checks.append({"label": label, "passed": passed, "detail": detail})
	print("CHECK %s %s %s" % ["PASS" if passed else "FAIL", label, str(detail)])

func _run() -> void:
	# 1. 接続先（値は記録しない）
	var url := RBMSupabaseConfig.url()
	var key := RBMSupabaseConfig.publishable_key()
	report["build"] = {
		"engine": Engine.get_version_info().string,
		"template": OS.has_feature("template"),
		"release": OS.has_feature("template_release"),
		"distribution_build": RBMSupabaseConfig.is_distribution_build(),
		"user_data_dir_name": OS.get_user_data_dir().get_file(),
		"local_dev_config_present": FileAccess.file_exists(RBMSupabaseConfig.DEFAULT_LOCAL_CONFIG_PATH),
		"public_config_present": FileAccess.file_exists(RBMSupabaseConfig.DEFAULT_PUBLIC_CONFIG_PATH),
		"env_override": not OS.get_environment(RBMSupabaseConfig.ENV_URL_KEY).is_empty(),
	}
	_check("config source is the shipped public file", RBMSupabaseConfig.source() == "public", RBMSupabaseConfig.source())
	_check("local dev config is not in the build", not FileAccess.file_exists(RBMSupabaseConfig.DEFAULT_LOCAL_CONFIG_PATH))
	_check("url is https", url.begins_with("https://"))
	_check("key is a publishable key (not secret)", RBMSupabaseConfig.is_public_key(key) and not RBMSupabaseConfig.is_secret_key(key))
	# 保存先は製品版の名前のフォルダ（開発中のエディターの Godot/app_userdata/… と分ける。2026-10-20）
	var user_dir := OS.get_user_data_dir()
	_check("user data dir is the product folder", user_dir.get_file() == "MakersAndChallengers" and not user_dir.contains("app_userdata"), user_dir.get_file())

	# 2. 読み取りだけの通信
	var api := RBMBossApiAdapter.new()
	add_child(api)
	_call("list-bosses", await api.list_bosses(5))
	_call("list-bosses mode=simple", await api.list_bosses(5, RBMCreatorDraft.CREATOR_MODE_SIMPLE))
	_call("list-popular-bosses", await api.list_popular_bosses(5))
	_call("list-hard-bosses", await api.list_hard_bosses(5))
	_call("search-bosses", await api.search_bosses("zz-export-check", 5))
	var random: Dictionary = await api.random_boss()
	_record("random-boss", random)
	# 公開ボスが0件の時は「抽選できるボスが無い」も正しい応答（通信と認証は通っている）
	_check("random-boss answered", bool(random.get("ok", false)) or str(random.get("error_kind", "")) == "not_found", "%s %s" % [random.get("http_status", ""), random.get("error_kind", "")])
	var missing: Dictionary = await api.get_boss("00000000-0000-4000-8000-000000000000")
	_record("get-boss (missing id)", missing)
	_check("get-boss passes the gateway (404, not 401)", int(missing.get("http_status", 0)) == 404, missing.get("http_status", 0))

	# 3. Steam の認証（読み取りだけ）
	if _arg("steam", "0") == "1":
		await _steam_check(api)

	# 4. 本物のゲームの画面
	if _arg("ui", "0") == "1":
		await _ui_check()

func _call(label: String, result: Dictionary) -> void:
	_record(label, result)
	_check(label + " ok", bool(result.get("ok", false)), "%s %s" % [result.get("http_status", ""), result.get("error_kind", "")])

func _record(label: String, result: Dictionary) -> void:
	var entry := {"label": label, "ok": bool(result.get("ok", false)), "http_status": result.get("http_status", null), "error_kind": str(result.get("error_kind", ""))}
	if result.has("bosses"):
		entry["bosses"] = (result.bosses as Array).size()
	# 公開した人の SteamID が応答に入っていないか（入っていたら失敗）
	entry["has_owner_steam_id"] = JSON.stringify(result).contains("owner_steam_id")
	report.calls.append(entry)
	if entry.has_owner_steam_id:
		_check(label + " does not leak owner_steam_id", false)

func _steam_check(api: RBMBossApiAdapter) -> void:
	report["steam"] = {"app_id_configured": RBMSteamConfig.is_configured()}
	var auth := RBMSteamAuth.new()
	add_child(auth)
	auth.initialize()
	await get_tree().process_frame
	report.steam["available"] = auth.is_available()
	if not auth.is_available():
		_check("steam available for the auth check", false, "Steam が使えない（AppID 未設定、または Steam 未起動）")
		return
	var ticket: Dictionary = await RBMSteamTicketProvider.acquire_ticket(auth)
	_check("steam ticket acquired", bool(ticket.get("ok", false)), ticket.get("error_kind", ""))
	if not bool(ticket.get("ok", false)):
		return
	var result: Dictionary = await api.list_unchallenged_bosses(str(ticket.hex), "", 5)
	auth.complete_ticket()
	_record("list-unchallenged-bosses (steam ticket)", result)
	_check("list-unchallenged-bosses with a real Steam ticket ok", bool(result.get("ok", false)), "%s %s" % [result.get("http_status", ""), result.get("error_kind", "")])

# ---------------------------------------------------------------------------
# 本物のゲームの画面（タイトル → 挑戦トップ → オンライン → 未挑戦 → ランダム）

var game: Node

func _ui_check() -> void:
	game = RBMGameRoot.new()
	get_tree().root.add_child(game)
	await _wait(1.8)
	# タイトル（起動の演出、TitleBootLauncher）は START のフェードが終わると自分を隠す。演出の途中の押下は無視されることが
	# あるので、隠れる（ホーム画面が出る）まで押し直す（最大12秒。2026-10-22）
	var waited := 0.0
	while waited < 12.0:
		await _click_at(Vector2(640, 420))
		await _wait(1.5)
		waited += 1.5
		if not _vis(game, "TitleBootLauncher"):
			break
	await _wait(0.6)
	report.notes.append({"title_closed": not _vis(game, "TitleBootLauncher"), "title_wait_seconds": waited})
	await _shot("x00_home")
	if not await _press(game, "ChallengeHomeMonitor"):
		return
	var ce: Node = game.get("challenge_entry")
	await _until(func(): return _vis(ce, "FeaturedCategoryButton") and not _vis(game, "ChallengeHomeMonitor"), 8.0)
	await _wait(0.8)
	await _shot("x01_challenge_hub")
	for cat in [["FeaturedCategoryButton", "x02_online"], ["NewCategoryButton", "x03_new"], ["PopularCategoryButton", "x04_popular"], ["UnchallengedCategoryButton", "x05_unchallenged"], ["RandomChallengeButton", "x06_random"]]:
		if not await _press(ce, cat[0]):
			continue
		await _wait(0.5)
		await _until(func(): return not _vis(ce, "OnlineListSkeleton"), 15.0)
		await _wait(0.8)
		await _shot(cat[1])
		var view: Node = ce.get("_online_list_view")
		var status := ""
		if view != null and view.get("_status_label") != null:
			status = str((view.get("_status_label") as Label).text)
		var rows := 0
		if view != null and view.get("_rows_container") != null:
			rows = (view.get("_rows_container") as Node).get_child_count()
		report.notes.append({"screen": cat[1], "status_text": status, "rows": rows})
		print("UI %s rows=%d status=%s" % [cat[1], rows, status])
		for n in ["OnlineListBackButton", "BackToHubButton"]:
			if _vis(ce, n):
				await _press(ce, n)
				await _until(func(): return _vis(ce, "FeaturedCategoryButton"), 5.0)
				await _wait(0.4)
				break

func _shot(name: String) -> void:
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	report.shots.append(path.get_file())

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while t < limit and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()

func _vis(root: Node, node_name: String) -> bool:
	if root == null:
		return false
	var c := root.find_child(node_name, true, false) as Control
	return c != null and c.is_visible_in_tree()

func _press(root: Node, node_name: String) -> bool:
	var c := root.find_child(node_name, true, false) as Control if root != null else null
	if c == null or not c.is_visible_in_tree():
		report.notes.append({"missing_button": node_name})
		return false
	await _click_at(c.get_global_rect().get_center())
	return true

func _click_at(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_tree().root.push_input(move, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		get_tree().root.push_input(ev, true)
		await get_tree().process_frame
