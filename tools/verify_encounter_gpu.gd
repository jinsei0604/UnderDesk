extends RefCounted
## 戦闘開始前の登場演出・勝利演出（RBMEncounterDirector、src/bossmaker/visuals/encounter/）の実GPU検証。
## 本物の RBMGameRoot を起動し、本物の操作の流れで確かめる（通信はしない: 一覧は RBMFakeBossApiAdapter、記録は受け取るだけの記録係。
## 保存先は出力フォルダの中の一時フォルダだけ）。
##   挑戦: オンライン一覧 → 行を選ぶ → 「挑戦する」 / クリアチェック: 保存したボス戦を開く → 「クリアチェック」 → 「開始」
## 確かめること（ボスごと）:
##   登場: 前の画面が閉じる層 → 戦闘が始まり登場が始まる / 登場の間はコマンド・HUD が出ない / 戦闘の状態が変わらない / 長さ /
##         終わると元の見た目（HUD・ボス・戦場の位置と大きさ・層の後片付け）でコマンドを押せる
##   勝利: 決着の命中で始まる / とどめのスローは戦場の動きだけ（Engine.time_scale は 1 のまま）/ クリアの記録は1回で、最後の行動の
##         演出が終わった瞬間（勝利演出を待たない）/ 結果パネルは演出の間は出ず、後に出る / 決着の音（victory）は鳴らない /
##         撃破ターン・クリアタイム / 戦闘の状態が変わらない / 終わると入力が戻る
##   もう一度挑戦で登場が流れ直す・途中で画面が隠れたら元へ戻る（ボスの一部）、クリアチェックの成功の記録（クリアチェックの経路）
## 引数: --bosses=slime,wolf,...（省略時は9体）--routes=challenge,clear_check（省略時は両方）--shots=1（要所の画面を保存）
##       --perf=1（実時間のフレーム時間を測る。録画しない時だけ意味がある）
const ScreenClose = preload("res://src/bossmaker/visuals/encounter/rbm_screen_close.gd")

var _gpu_verification_completed := false
var tree: SceneTree
var out := ""
var checks: Array = []
var perf_results: Array = []
var mouse := Vector2(640, 715)

const BOSSES := ["slime", "wolf", "knight", "dragon", "ghost", "golem", "musha", "astronaut", "gentleman"]
const NAMES := {"slime": "紅玉スライム", "wolf": "蒼牙の狼", "knight": "黒鉄の騎士団長", "dragon": "翠鱗の竜", "ghost": "宵闇の亡霊",
	"golem": "岩窟の番人", "musha": "朽ちた機械武者・零式", "astronaut": "月面の迷子", "gentleman": "霧の紳士"}
## 戦闘に出る味方は最大4人。5人全員が勝利の動きに出るよう、ボスごとに入れ替える。
const PARTY := {
	"slime": ["hero", "butler", "healer", "samurai"], "wolf": ["tank", "hero", "healer", "samurai"],
	"knight": ["hero", "butler", "healer", "tank"], "dragon": ["hero", "butler", "healer", "samurai"],
	"ghost": ["tank", "butler", "healer", "samurai"], "golem": ["tank", "hero", "healer", "samurai"],
	"musha": ["hero", "butler", "healer", "samurai"], "astronaut": ["hero", "tank", "healer", "butler"],
	"gentleman": ["hero", "butler", "tank", "samurai"],
}

class OfflineRecorder:
	extends RBMOnlineChallengeRecorder
	var attempts: Array[String] = []
	var clears: Array[String] = []
	func record_challenge_attempt(boss_id: String) -> Dictionary:
		attempts.append(boss_id)
		return {"ok": true, "error_kind": "", "message": "", "challenge_count": attempts.size(), "by_owner": false}
	func record_challenge_clear(boss_id: String) -> Dictionary:
		clears.append(boss_id)
		return {"ok": true, "error_kind": "", "message": "", "clear_count": clears.size(), "by_owner": false}
	# 2026-10-23: 旧版のサーバーと同じ（戦闘チケットが無い。勝ちは旧来のクリアの記録）。チケット・結果・認定の一覧も
	# 受け取るだけ（本物の通信をしない）
	func issue_battle_ticket(_boss_id: String) -> Dictionary:
		return {"ok": false, "error_kind": "http_404", "message": ""}
	func submit_battle_results(_results: Array, _next_ticket_boss_id: String = "") -> Dictionary:
		return {"ok": false, "error_kind": "http_404", "message": ""}
	func list_my_hard_awards() -> Dictionary:
		return {"ok": true, "error_kind": "", "message": "", "boss_ids": []}

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback

## 動画用（--pace=1）: 要所で少し止める（検証の判定は変えない）。
func _pace(seconds: float) -> void:
	if _arg("pace", "") != "1":
		return
	var t := 0.0
	while t < seconds:
		await tree.process_frame
		t += tree.root.get_process_delta_time()

func _check(name: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"name": name, "ok": ok, "detail": str(detail)})
	print("CHECK ", "OK  " if ok else "FAIL", " ", name, " ", detail)

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale("ja")
	var bosses: Array = Array(_arg("bosses", ",".join(BOSSES)).split(","))
	var routes: Array = Array(_arg("routes", "challenge,clear_check").split(","))
	# --no_extra=1: 動画用に、もう一度挑戦・途中で隠す確認を省く
	var extra := _arg("no_extra", "") != "1"
	for boss in bosses:
		if routes.has("challenge"):
			await _run(str(boss), "challenge", extra and str(boss) in ["golem", "gentleman"], extra and str(boss) == "dragon")
	if routes.has("clear_check"):
		for boss in ["knight", "musha"]:
			if bosses.has(boss):
				await _run(boss, "clear_check", extra and boss == "knight", false)
	var bad := checks.filter(func(c): return not c.ok).size()
	var f := FileAccess.open(out.path_join("encounter-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failed": bad, "perf": perf_results}, "  "))
	f.close()
	print("ENCOUNTER_GPU_DONE checks=", checks.size(), " failed=", bad)
	_gpu_verification_completed = true
	return 0 if bad == 0 else 1

# ---------------------------------------------------------------------------

var game: Node
var view: Control
var director: Node
var recorder: OfflineRecorder
var draft: RBMCreatorDraft

func _draft(boss: String, hp: int) -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = NAMES[boss]
	d.appearance_id = "appearance_" + boss
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	d.hp = hp
	d.atk = 120
	d.spd = 1
	d.author_name = "verify"
	d.battle_background = "night"
	d.add_skill({"name": "強襲", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	for c in PARTY[boss]:
		d.add_party_character(c)
	d.record_clear_check_success()
	d.publish()
	return d

func _boot_challenge(boss: String, hp: int) -> void:
	var stages := out.path_join("stages")
	_reset_dir(stages)
	RBMLocalStageRepository.set_stages_dir_for_testing(stages)
	draft = _draft(boss, hp)
	game = RBMGameRoot.new()
	tree.root.add_child(game)
	await _frames(12)
	(game.find_child("ChallengeModeButton", true, false) as Button).pressed.emit()
	await _frames(4)
	var challenge: Node = game.get("challenge_entry")
	view = challenge.get("_battle_view")
	recorder = OfflineRecorder.new()
	challenge.add_child(recorder)
	challenge.set("_online_recorder_instance", recorder)
	var api := RBMFakeBossApiAdapter.new()
	challenge.add_child(api)
	api.configure_list_response({"ok": true, "bosses": [{"id": "verify_boss", "boss_name": draft.boss_name, "author_name": draft.author_name,
		"creator_mode": draft.creator_mode, "appearance_id": draft.appearance_id, "published_at": "2026-10-16T12:00:00+00:00",
		"unique_challengers": 10, "unique_clearers": 1}]})
	api.configure_get_response({"ok": true, "boss": {"id": "verify_boss", "boss_name": draft.boss_name, "author_name": draft.author_name, "revision": 1,
		"payload": RBMOnlineBossPayload.build_for_publish(draft)["payload"]}})
	var online: Control = challenge.get("_online_list_view")
	online.call("set_api_adapter_for_testing", api)
	(challenge.find_child("FeaturedCategoryButton", true, false) as Button).pressed.emit()
	var rows: Control = online.get("_rows_container")
	for i in range(240):
		await tree.process_frame
		if rows.get_child_count() > 0 and rows.get_child(0).get_global_rect().size.y > 0:
			break
	await _frames(4)
	await _click(rows.get_child(0).get_global_rect().get_center())
	for i in range(240):
		await tree.process_frame
		var b := challenge.find_child("DetailChallengeButton", true, false) as Button
		if b != null and b.is_visible_in_tree() and b.get_global_rect().size.y > 0:
			break
	await _frames(6)
	director = view.get("_encounter")

func _boot_clear_check(boss: String, hp: int) -> void:
	var stages := out.path_join("stages")
	_reset_dir(stages)
	RBMLocalStageRepository.set_stages_dir_for_testing(stages)
	draft = _draft(boss, hp)
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))
	game = RBMGameRoot.new()
	tree.root.add_child(game)
	await _frames(12)
	(game.find_child("CreateModeButton", true, false) as Button).pressed.emit()
	await _frames(4)
	var creator: Node = game.get("creator_entry")
	creator.call("_on_open_stage_pressed", stage_id)
	await _frames(8)
	var main: Node = creator.get("main")
	view = main.get("_clear_check_view")
	var cc := main.find_child("ClearCheckButton", true, false) as Button
	await _click(cc.get_global_rect().get_center())
	for i in range(120):
		await tree.process_frame
		var b := view.find_child("ConfirmStartButton", true, false) as Button
		if b != null and b.is_visible_in_tree() and b.get_global_rect().size.y > 0:
			break
	await _frames(6)
	draft = view.get("draft")
	director = view.get("_encounter")

func _start_button(route: String) -> Button:
	if route == "clear_check":
		return view.find_child("ConfirmStartButton", true, false) as Button
	return game.get("challenge_entry").find_child("DetailChallengeButton", true, false) as Button

func _shutdown() -> void:
	if is_instance_valid(game):
		game.queue_free()
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await _frames(4)

# ---------------------------------------------------------------------------

func _stage() -> Control:
	return view.get("_battlefield_ally_row").get_meta("visual_stage", null) as Control

func _hud() -> Control:
	return _stage().get_meta("battle_hud", null) as Control

func _commands() -> Array:
	return view.get("_command_area").find_children("*", "Button", true, false)

func _all_disabled() -> bool:
	for b in _commands():
		if not (b as Button).disabled:
			return false
	return true

func _any_enabled() -> bool:
	for b in _commands():
		if not (b as Button).disabled and (b as Button).is_visible_in_tree():
			return true
	return false

func _state_json() -> String:
	return JSON.stringify(view.get("session").battle.presentation_state())

func _leftovers() -> Array:
	var names: Array = []
	for n in _stage().get_children():
		var s := str(n.name)
		if s.begins_with("Intro") or s.begins_with("Victory") or n is CanvasLayer:
			names.append(s)
	for n in view.get_children():
		if n is CanvasLayer:
			names.append(str(n.name))
	return names

func _shot(tag: String) -> void:
	if _arg("shots", "") != "1":
		return
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join(tag + ".png"))

## 1体分: 登場（＋必要なら途中で隠す・もう一度挑戦）→ 勝利。
func _run(boss: String, route: String, with_retry: bool, with_cancel: bool) -> void:
	var tag := "%s_%s" % [route, boss]
	if route == "clear_check":
		await _boot_clear_check(boss, 1)
	else:
		await _boot_challenge(boss, 1)
	if director == null:
		_check(tag + " 進行役がある", false)
		await _shutdown()
		return
	var outcome: Control = view.get("_outcome_area")
	var audio: Node = RBMAudio_for(view)
	# ---- 登場 ----
	await _pace(1.0)
	var button := _start_button(route)
	var click_ms := Time.get_ticks_msec()
	_click_now(button.get_global_rect().get_center())
	await _frames(2)
	_check(tag + " 前の画面が閉じる層が出る（戦闘はまだ始まらない）", ScreenClose.active_count(tree) > 0 and (route == "clear_check" or not view.visible))
	await _shot(tag + "_closing_a")
	await _frames(6)
	await _shot(tag + "_closing_b")
	var intro := {"started_ms": -1, "started": -1.0, "ended": -1.0, "state_start": "", "state_end": "", "locked": false, "hud_hidden": false, "t": 0.0}
	director.connect("intro_finished", func():
		intro.ended = intro.t
		intro.state_end = _state_json())
	await _perf_start()
	var cancelled := false
	while intro.ended < 0.0 and intro.t < 12.0:
		await tree.process_frame
		var dt := tree.root.get_process_delta_time()
		intro.t += dt
		_perf_sample()
		var p = director.get("_intro")
		if intro.started < 0.0 and is_instance_valid(p):
			intro.started = intro.t
			intro.started_ms = Time.get_ticks_msec()
			intro.state_start = _state_json()
		if intro.started >= 0.0 and not intro.locked and intro.t - intro.started > 0.5:
			intro.locked = _all_disabled() and bool(director.call("is_playing"))
			intro.hud_hidden = not _hud().visible
			await _shot(tag + "_intro_mid")
		if with_cancel and intro.started >= 0.0 and intro.t - intro.started > 2.0 and not cancelled:
			cancelled = true
			break
	if with_cancel:
		await _check_cancel(tag)
		await _shutdown()
		await _run(boss, route, with_retry, false)
		return
	var intro_perf := _perf_result()
	perf_results.append({"tag": tag + "_intro", "perf": intro_perf, "intro_started_s": snappedf(intro.started, 0.01)})
	var since_click: float = (int(intro.started_ms) - click_ms) / 1000.0
	_check(tag + " 登場が始まる（前の画面が閉じた後）", intro.started >= 0.0 and since_click > 0.25 and since_click < 3.0, "押してから %.2f 秒" % since_click)
	_check(tag + " 登場の間はコマンドを押せない", intro.locked)
	_check(tag + " 登場の間は HUD が隠れる", intro.hud_hidden)
	_check(tag + " 登場の前後で戦闘の状態が変わらない", intro.state_start != "" and intro.state_start == intro.state_end)
	var length: float = intro.ended - intro.started
	_check(tag + " 登場の長さ", length > 4.0 and length < 5.2, "%.2f 秒" % length)
	_check(tag + " 前の画面が閉じる層は外れる", ScreenClose.active_count(tree) == 0)
	# 開幕（ボスが先に動く時）の演出が終わり、コマンドを押せるまで待つ
	var waited := 0.0
	while (bool(view.call("_is_busy")) or not _any_enabled()) and waited < 15.0:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()
	await _frames(2)
	var st := _stage()
	var boss_visual: Control = st.get("_visuals")["boss"]
	_check(tag + " 登場の後: コマンドを押せる", _any_enabled())
	_check(tag + " 登場の後: HUD・ボス・戦場が元に戻る", _hud().visible and is_equal_approx(_hud().modulate.a, 1.0) and boss_visual.visible
		and st.scale == Vector2.ONE and st.position == Vector2.ZERO, "scale=%s pos=%s" % [st.scale, st.position])
	_check(tag + " 登場の後: 演出の層が残らない", _leftovers().is_empty(), _leftovers())
	await _shot(tag + "_after_intro")
	# ---- 勝利 ----
	var presenter: Node = view.get("_presenter")
	var v := {"impact": -1.0, "finished": -1.0, "won": -1.0, "won_count": 0, "result": -1.0, "outcome_hidden": true, "time_scale_ok": true,
		"slow": -1.0, "state_begin": "", "t": 0.0, "clears_before": recorder.clears.size() if recorder != null else 0}
	presenter.connect("entry_impact", func(entry: Dictionary):
		var vs: Dictionary = entry.get("visual_state", {})
		if v.impact < 0.0 and bool(vs.get("battle_over", false)):
			v.impact = v.t)
	presenter.connect("finished", func():
		if v.impact >= 0.0 and v.finished < 0.0:
			v.finished = v.t
			v.state_begin = _state_json())
	if view.has_signal("challenge_won"):
		view.connect("challenge_won", func():
			v.won_count += 1
			if v.won < 0.0:
				v.won = v.t)
	director.connect("victory_result_shown", func(): v.result = v.t)
	await _pace(0.8)
	var history_before: int = audio.get("history").size() if audio != null else 0
	# クリアチェック: 成功の記録を一度消して、決着の行動で記録される瞬間を確かめる（下書きの状態だけ。保存はしない）
	var cleared_at := -1.0
	if route == "clear_check" and draft != null:
		draft.set("_clear_check_success_snapshot", {})
	var attack := _commands()[0] as Button
	_click_now(attack.get_global_rect().get_center())
	await _perf_start()
	var shot_banner := false
	while v.result < 0.0 and v.t < 25.0:
		await tree.process_frame
		v.t += tree.root.get_process_delta_time()
		_perf_sample()
		if not is_equal_approx(Engine.time_scale, 1.0):
			v.time_scale_ok = false
		if v.impact >= 0.0 and v.slow < 0.0 and v.t - v.impact > 0.25:
			var vp = director.get("_victory")
			v.slow = float(vp.get("motion_speed")) if is_instance_valid(vp) else -2.0
		# 結果を出す前（勝利演出の間）に結果パネルが見えたら失敗
		if v.impact >= 0.0 and v.result < 0.0 and str(director.get("_victory_state")) != "shown" and outcome.visible:
			v.outcome_hidden = false
		if route == "clear_check" and cleared_at < 0.0 and draft != null and draft.has_ever_cleared():
			cleared_at = v.t
		if not shot_banner and v.finished >= 0.0 and v.t - v.finished > 3.0:
			shot_banner = true
			await _shot(tag + "_victory_banner")
	var victory_perf := _perf_result()
	perf_results.append({"tag": tag + "_victory", "perf": victory_perf, "impact_s": snappedf(v.impact, 0.01), "finished_s": snappedf(v.finished, 0.01)})
	await _frames(3)
	_check(tag + " 決着の命中で勝利演出が始まる", v.impact >= 0.0)
	_check(tag + " とどめのスローは戦場の動きだけ（ゲーム全体の時間は変えない）", v.time_scale_ok and v.slow > 0.0 and v.slow < 0.5, "命中0.25秒後の戦場の速さ %.2f" % v.slow)
	if route == "challenge":
		_check(tag + " クリアの記録は1回", v.won_count == 1 and recorder.clears.size() - int(v.clears_before) == 1, "%d 回" % v.won_count)
		_check(tag + " クリアの記録は最後の行動の演出が終わった瞬間（勝利演出を待たない）", v.won >= 0.0 and absf(v.won - v.finished) < 0.02 and v.won < v.result - 1.0,
			"記録 %.2f・演出の終わり %.2f・結果 %.2f" % [v.won, v.finished, v.result])
	else:
		_check(tag + " クリアチェックの成功は決着の行動の時に記録される（勝利演出を待たない）", cleared_at >= 0.0 and cleared_at <= v.finished + 0.02 and cleared_at < v.result - 1.0,
			"記録 %.2f・演出の終わり %.2f・結果 %.2f" % [cleared_at, v.finished, v.result])
	_check(tag + " 結果パネルは勝利演出の間は出ない", v.outcome_hidden)
	_check(tag + " 勝利演出の後に結果パネルが出る", outcome.visible, "決着から結果まで %.2f 秒" % (v.result - v.impact))
	_check(tag + " 決着の音（victory / クリアチェック成功）は鳴らない", audio == null or not _history_has(audio, history_before, ["victory", "ui_clear_check_success"]))
	var turn := int(director.get("final_turn"))
	var secs := float(director.get("clear_seconds"))
	_check(tag + " 撃破ターンとクリアタイム", turn >= 1 and secs > 0.0 and secs < 30.0, "ターン %d・%.2f 秒" % [turn, secs])
	_check(tag + " 勝利演出の前後で戦闘の状態が変わらない", v.state_begin != "" and v.state_begin == _state_json())
	_check(tag + " 勝利演出の後は入力が戻る", not bool(view.call("_is_busy")) and not _all_disabled_outcome(), "")
	_check(tag + " ゲーム全体の時間は 1 のまま", is_equal_approx(Engine.time_scale, 1.0))
	await _shot(tag + "_result")
	await _pace(1.6)
	if with_retry:
		await _check_retry(tag, route)
	await _shutdown()

func _all_disabled_outcome() -> bool:
	for b in (view.get("_outcome_area") as Control).find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return false
	return true

func RBMAudio_for(node: Node) -> Node:
	return node.get_node_or_null("RBMAudio")

func _history_has(audio: Node, from: int, keys: Array) -> bool:
	var h: Array = audio.get("history")
	for i in range(from, h.size()):
		if keys.has(str(h[i])):
			return true
	return false

## 途中で画面が隠れた時（画面を出た・アプリの別の画面へ）: すぐに元の見た目へ戻る。
func _check_cancel(tag: String) -> void:
	var st := _stage()
	view.visible = false
	await _frames(3)
	var boss_visual: Control = st.get("_visuals")["boss"]
	_check(tag + " 登場の途中で画面が隠れたら元へ戻る", not bool(director.call("is_playing")) and st.scale == Vector2.ONE and st.position == Vector2.ZERO
		and boss_visual.visible and _hud().visible and is_equal_approx(_hud().modulate.a, 1.0) and _leftovers().is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		"scale=%s leftovers=%s" % [st.scale, _leftovers()])

## 「もう一度挑戦」: 今の画面が閉じてから、もう一度登場から始まる（ターン1）。
func _check_retry(tag: String, route: String) -> void:
	var retry := view.get("_retry_button") as Button
	if retry == null or not retry.is_visible_in_tree():
		# クリアチェックの成功時は「もう一度挑戦」が無い（Creator に戻るだけ）。最初からやり直すで確かめる。
		if route == "clear_check":
			view.call("_on_restart_confirmed")
		else:
			_check(tag + " もう一度挑戦のボタン", false)
			return
	else:
		_click_now(retry.get_global_rect().get_center())
	await _frames(2)
	var closing := ScreenClose.active_count(tree) > 0
	var started := false
	var t := 0.0
	while t < 4.0:
		await tree.process_frame
		t += tree.root.get_process_delta_time()
		if is_instance_valid(director.get("_intro")):
			started = true
			break
	var turn := int(view.get("session").battle.current_turn)
	_check(tag + " もう一度挑戦: 画面が閉じてから登場が流れ直す（ターン1から）", closing and started and turn == 1, "%.2f 秒で登場・ターン %d" % [t, turn])
	var waited := 0.0
	while bool(view.call("_is_busy")) and waited < 15.0:
		await tree.process_frame
		waited += tree.root.get_process_delta_time()

# ---------------------------------------------------------------------------
# 実時間の計測（録画しない時だけ意味がある）
var _perf := {}
func _perf_start() -> void:
	_perf = {"t": Time.get_ticks_usec(), "dts": [], "draw": 0}
	await tree.process_frame

func _perf_sample() -> void:
	if _perf.is_empty():
		return
	var now := Time.get_ticks_usec()
	(_perf.dts as Array).append((now - int(_perf.t)) / 1000.0)
	_perf.t = now
	_perf.draw = maxi(int(_perf.draw), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))

func _perf_result() -> Dictionary:
	var dts: Array = _perf.get("dts", [])
	var draw := int(_perf.get("draw", 0))
	_perf = {}
	if dts.size() < 3:
		return {}
	dts = dts.slice(1)
	var total := 0.0
	var worst := 0.0
	var worst_at := 0.0
	var over20 := 0
	var over33 := 0
	var t := 0.0
	for d in dts:
		t += d
		total += d
		if d > worst:
			worst = d
			worst_at = t / 1000.0
		if d > 20.0: over20 += 1
		if d > 33.4: over33 += 1
	return {"frames": dts.size(), "avg_fps": snappedf(1000.0 * dts.size() / total, 0.1), "worst_ms": snappedf(worst, 0.1), "worst_at_s": snappedf(worst_at, 0.01),
		"over20": over20, "over33": over33, "max_draw_calls": draw}

# ---------------------------------------------------------------------------

func _reset_dir(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.make_dir_recursive_absolute(dir)

func _frames(n: int) -> void:
	for i in range(n):
		await tree.process_frame

func _motion(to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - mouse
	mouse = to
	tree.root.push_input(ev, true)

func _click(at: Vector2) -> void:
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

func _click_now(at: Vector2) -> void:
	_motion(at)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		tree.root.push_input(ev, true)
