extends RefCounted
## 挑戦トップの「あなたの討伐記録」（RBMDefeatRecord）の実GPU検証と動作の動画。
## 本物の RBMGameRoot を起動し、本物の操作の流れ（挑戦トップ → オンライン一覧 → 挑戦する → 登場 → 勝利 → 一覧へ戻る →
## 挑戦トップ）で確かめる。通信はしない（一覧は RBMFakeBossApiAdapter、記録は受け取るだけの記録係）。本物の Steam・
## Steam Cloud には触れない（偽の Steam Cloud・テスト用の保存先）。
## 確かめること: 初回クリア（HARDCORE・難関 / SIMPLE）・再クリアで増えない・再起動しても残る・アカウントの切り替え・
## 別の PC（同じアカウントの Steam Cloud）・オンラインの記録（挑戦・クリアの記録の呼び出し）は今までどおり。
## 引数: --shots=1（要所の画面を保存）--pace=1（動画用に、要所で少し止める）
var _gpu_verification_completed := false
var tree: SceneTree
var out := ""
var checks: Array = []
var mouse := Vector2(640, 715)
var game: Node
var challenge: Node
var recorder: Recorder
var api: RBMFakeBossApiAdapter
var cloud := RBMFakeSteamCloud.new()
const ACCOUNT_A := "76561198000000001"
const ACCOUNT_B := "76561198000000002"

class Recorder:
	extends RBMOnlineChallengeRecorder
	var attempts: Array[String] = []
	var clears: Array[String] = []
	func record_challenge_attempt(boss_id: String) -> Dictionary:
		attempts.append(boss_id)
		return {"ok": true, "error_kind": "", "message": "", "challenge_count": attempts.size(), "by_owner": false}
	func record_challenge_clear(boss_id: String) -> Dictionary:
		clears.append(boss_id)
		return {"ok": true, "error_kind": "", "message": "", "clear_count": clears.size(), "by_owner": false}
	func account_id() -> String:
		return ""

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback

func _check(name: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"name": name, "ok": ok, "detail": str(detail)})
	print("CHECK ", "OK  " if ok else "FAIL", " ", name, " ", detail)

func _pace(seconds: float) -> void:
	if _arg("pace", "") == "1":
		await _seconds(seconds)

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale("ja")
	var root := out.path_join("pc1")
	_reset(root)
	await _boot(root, ACCOUNT_A)
	await _pace(1.2)
	_check("最初は0件", _shown() == {"simple": 0, "hardcore": 0, "hard": 0}, _shown())
	await _shot("01_hub_start")
	# 1体目: HARDCORE・一覧のクリア率 1/40 = 2.5% → HARDCORE 1・難関 1
	await _challenge_and_win(0)
	await _back_to_hub()
	_check("HARDCORE のボスを初めてクリア（クリア率2.5%）→ HARDCORE 1・難関 1", _shown() == {"simple": 0, "hardcore": 1, "hard": 1}, _shown())
	await _shot("02_hub_after_hardcore")
	await _pace(1.5)
	# 2体目: SIMPLE・クリア率 50% → SIMPLE 1（難関は増えない）
	await _challenge_and_win(1)
	await _back_to_hub()
	_check("SIMPLE のボスを初めてクリア（クリア率50%）→ SIMPLE 1", _shown() == {"simple": 1, "hardcore": 1, "hard": 1}, _shown())
	await _pace(1.0)
	# 1体目をもう一度クリア → 増えない
	await _challenge_and_win(0)
	await _back_to_hub()
	_check("同じボスをもう一度クリアしても増えない", _shown() == {"simple": 1, "hardcore": 1, "hard": 1}, _shown())
	await _shot("03_hub_after_reclear")
	_check("オンラインの挑戦・クリアの記録の呼び出しは今までどおり（3回ずつ）", recorder.attempts.size() == 3 and recorder.clears.size() == 3,
		"挑戦 %d・クリア %d" % [recorder.attempts.size(), recorder.clears.size()])
	await _pace(1.0)
	# 再起動: ゲームを閉じて、同じ保存先・同じアカウントで起動し直す
	await _shutdown()
	await _boot(root, ACCOUNT_A)
	_check("ゲームを起動し直しても残る", _shown() == {"simple": 1, "hardcore": 1, "hard": 1}, _shown())
	await _pace(1.0)
	# アカウントの切り替え
	await _shutdown()
	await _boot(root, ACCOUNT_B)
	_check("別のアカウントは自分の記録だけ（0件）", _shown() == {"simple": 0, "hardcore": 0, "hard": 0}, _shown())
	await _shot("04_hub_other_account")
	await _pace(1.0)
	await _shutdown()
	await _boot(root, ACCOUNT_A)
	_check("元のアカウントに戻すと元の記録", _shown() == {"simple": 1, "hardcore": 1, "hard": 1}, _shown())
	await _pace(1.0)
	# 別の PC（手元の保存先が空。同じアカウントの Steam Cloud）
	await _shutdown()
	var root2 := out.path_join("pc2")
	_reset(root2)
	await _boot(root2, ACCOUNT_A)
	_check("別の PC でも同じアカウントなら Steam Cloud から同じ記録", _shown() == {"simple": 1, "hardcore": 1, "hard": 1}, _shown())
	await _shot("05_hub_other_pc")
	await _pace(1.5)
	await _shutdown()
	var bad := checks.filter(func(c): return not c.ok).size()
	var f := FileAccess.open(out.path_join("defeat-record-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failed": bad, "cloud_files": cloud.files.keys()}, "  "))
	f.close()
	print("DEFEAT_RECORD_GPU_DONE checks=", checks.size(), " failed=", bad)
	_gpu_verification_completed = true
	return 0 if bad == 0 else 1

# ---------------------------------------------------------------------------

func _draft(name: String, mode: String) -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = name
	d.appearance_id = "appearance_golem" if mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED else "appearance_slime"
	d.set_creator_mode(mode)
	d.hp = 1
	d.atk = 120
	d.spd = 1
	d.author_name = "verify"
	d.battle_background = "night"
	d.add_skill({"name": "強襲", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	for c in ["tank", "hero", "healer", "samurai"]:
		d.add_party_character(c)
	d.record_clear_check_success()
	d.publish()
	return d

var _bosses: Array = []

func _boot(root: String, account: String) -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(root.path_join("stages"))
	DirAccess.make_dir_recursive_absolute(root.path_join("stages"))
	game = RBMGameRoot.new()
	tree.root.add_child(game)
	await _frames(12)
	challenge = game.get("challenge_entry")
	recorder = Recorder.new()
	challenge.add_child(recorder)
	challenge.set("_online_recorder_instance", recorder)
	challenge.call("set_defeat_record_for_testing", RBMDefeatRecord.new(account, cloud))
	api = RBMFakeBossApiAdapter.new()
	challenge.add_child(api)
	var hard := _draft("岩窟の番人", RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	var simple := _draft("紅玉スライム", RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	_bosses = [{"id": "0d0d0d0d-0000-4000-8000-000000000001", "draft": hard, "challengers": 40, "clearers": 1},
		{"id": "0d0d0d0d-0000-4000-8000-000000000002", "draft": simple, "challengers": 10, "clearers": 5}]
	var rows: Array = []
	for b in _bosses:
		var d: RBMCreatorDraft = b.draft
		rows.append({"id": b.id, "boss_name": d.boss_name, "author_name": d.author_name, "creator_mode": d.creator_mode, "appearance_id": d.appearance_id,
			"published_at": "2026-10-16T12:00:00+00:00", "unique_challengers": b.challengers, "unique_clearers": b.clearers})
	api.configure_list_response({"ok": true, "bosses": rows})
	var online: Control = challenge.get("_online_list_view")
	online.call("set_api_adapter_for_testing", api)
	(game.find_child("ChallengeModeButton", true, false) as Button).pressed.emit()
	await _frames(6)

func _shown() -> Dictionary:
	return challenge.get("_hub_view").call("defeat_counts_shown")

func _challenge_and_win(index: int) -> void:
	var b: Dictionary = _bosses[index]
	var d: RBMCreatorDraft = b.draft
	api.configure_get_response({"ok": true, "boss": {"id": b.id, "boss_name": d.boss_name, "author_name": d.author_name, "revision": 1,
		"payload": RBMOnlineBossPayload.build_for_publish(d)["payload"]}})
	await _click_named("FeaturedCategoryButton")
	var online: Control = challenge.get("_online_list_view")
	var rows: Control = online.get("_rows_container")
	for i in range(240):
		await tree.process_frame
		if rows.get_child_count() > index and rows.get_child(index).get_global_rect().size.y > 0:
			break
	await _pace(0.5)
	await _click(rows.get_child(index).get_global_rect().get_center())
	var start: Button = null
	for i in range(240):
		await tree.process_frame
		start = challenge.find_child("DetailChallengeButton", true, false) as Button
		if start != null and start.is_visible_in_tree() and start.get_global_rect().size.y > 0 and str(online.get("_selected_id")) == str(b.id) and online.get("_selected_draft") != null:
			break
	await _pace(0.6)
	await _click(start.get_global_rect().get_center())
	var view: Control = challenge.get("_battle_view")
	# 登場が終わって、コマンドを押せるまで待つ
	for i in range(900):
		await tree.process_frame
		if view.visible and not bool(view.call("_is_busy")) and _first_command(view) != null:
			break
	await _pace(0.4)
	await _click(_first_command(view).get_global_rect().get_center())
	# 勝利演出の後、結果パネルの「一覧へ戻る」が出るまで待つ
	var back: Button = view.get("_return_button")
	for i in range(1200):
		await tree.process_frame
		if back != null and back.is_visible_in_tree() and not bool(view.call("_is_busy")):
			break
	await _pace(1.2)
	await _click(back.get_global_rect().get_center())
	await _frames(6)

func _first_command(view: Control) -> Button:
	for n in view.get("_command_area").find_children("*", "Button", true, false):
		var btn := n as Button
		if btn.is_visible_in_tree() and not btn.disabled:
			return btn
	return null

func _back_to_hub() -> void:
	# オンライン一覧の「挑戦ハブ」で挑戦トップへ
	var online: Control = challenge.get("_online_list_view")
	var back := online.find_child("OnlineListBackButton", true, false) as Button
	for i in range(60):
		if back != null and back.is_visible_in_tree():
			break
		await tree.process_frame
	await _pace(0.5)
	await _click(back.get_global_rect().get_center())
	await _frames(6)

func _click_named(node_name: String) -> void:
	var b := game.find_child(node_name, true, false) as Button
	await _click(b.get_global_rect().get_center())

func _shot(tag: String) -> void:
	if _arg("shots", "") != "1":
		return
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join(tag + ".png"))

func _shutdown() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await _frames(4)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _reset(dir: String) -> void:
	_remove_recursive(dir)
	DirAccess.make_dir_recursive_absolute(dir)

func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

func _frames(n: int) -> void:
	for i in range(n):
		await tree.process_frame

func _seconds(s: float) -> void:
	var t := 0.0
	while t < s:
		await tree.process_frame
		t += tree.root.get_process_delta_time()

func _motion(to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - mouse
	mouse = to
	tree.root.push_input(ev, true)

func _click(at: Vector2) -> void:
	var from := mouse
	if _arg("pace", "") == "1":
		for i in range(10):
			_motion(from.lerp(at, smoothstep(0.0, 1.0, float(i + 1) / 10.0)).round())
			await tree.process_frame
	_motion(at)
	await tree.process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		tree.root.push_input(ev, true)
		await _frames(2)
