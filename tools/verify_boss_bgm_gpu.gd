extends "res://tools/verify_encounter_gpu.gd"
## ボス専用BGM（rbm_boss_bgm.gd・rbm_battle_bgm.gd）の実GPU検証（2026-10-17、最初は朽ちた機械武者）。本物のゲームの本物の操作で確かめる。
## 通信はしない（オンライン一覧は RBMFakeBossApiAdapter、記録は受け取るだけ。保存は出力フォルダの中の一時フォルダだけ）。
## ホーム画面（BGM が鳴らないこと）→ 挑戦の一覧 → 「挑戦する」→ 登場 → 攻撃を続ける → 覚醒 → とどめ → 勝利 → 結果。
## 1コマごとに、鳴っている曲・音量・再生位置を記録し、切り替わりの時刻を確かめる。--write-movie と一緒に使うと音入りの動画になる。
## 新しいボスの曲を足した時は --boss=<boss_id> で同じ確認をする（覚醒の無いボスは --awaken=0）。
## 起動: Godot --path . [--write-movie <dir>/movie.avi --fixed-fps 30] res://tools/gpu_runner.tscn --
##       --tool=res://tools/verify_boss_bgm_gpu.gd --output=<dir> [--boss=musha] [--awaken=1] [--route=challenge|clear_check] [--pace=1] [--shots=1]
##       [--hp=2400]（ボスの HP。曲を長く聞く動画では大きくする）[--awaken_percent=60]（覚醒する HP の割合）

var normal_path := ""
var awakened_path := ""
var awaken := true

var timeline: Array = []
var events: Array = []
var clock := 0.0
var _last := ""
var stage_audio: Node
var awakening_se_heard := false
var awakening_started := -1.0

## 土台（verify_encounter_gpu.gd）と同じ下書きに、覚醒（ボスのHPが6割以下）を足す。クリアチェックの記録・公開は最後に行う。
func _draft(boss: String, hp: int) -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = NAMES[boss]
	d.appearance_id = "appearance_" + boss
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	d.hp = hp
	d.atk = 30
	d.spd = 1
	d.author_name = "verify"
	d.battle_background = "night"
	d.add_skill({"name": "強襲", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	for c in PARTY[boss]:
		d.add_party_character(c)
	if awaken:
		d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": float(_arg("awaken_percent", "60"))}], "condition_logic": "AND", "buff": {}, "heal": {}})
	d.record_clear_check_success()
	d.publish()
	return d

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale("ja")
	var route := _arg("route", "challenge")
	var boss := _arg("boss", "musha")
	awaken = _arg("awaken", "1") == "1"
	normal_path = RBMBossBgm.path_for(boss, false)
	awakened_path = RBMBossBgm.path_for(boss, true)
	if normal_path.is_empty():
		_check(boss + " の曲がある（assets_bossmaker/audio/bgm/%s/）" % boss, false)
	else:
		await _run_bgm(route, boss)
	var bad := checks.filter(func(c): return not c.ok).size()
	var f := FileAccess.open(out.path_join("bgm-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "failed": bad, "events": events, "timeline": timeline}, "  "))
	f.close()
	print("BOSS_BGM_GPU_DONE checks=", checks.size(), " failed=", bad)
	_gpu_verification_completed = true
	return 0 if bad == 0 else 1

## 画面の中のすべての BGM（戦闘の画面ごとに1つ）。
func _all_bgm() -> Array:
	return tree.root.find_children("*", "RBMBattleBgm", true, false)

func _playing_players() -> int:
	var n := 0
	for b in _all_bgm():
		var p: AudioStreamPlayer = (b as RBMBattleBgm).player
		if p != null and p.playing and not p.stream_paused:
			n += 1
	return n

func _bgm() -> RBMBattleBgm:
	return view.get_node_or_null(RBMBattleBgm.NODE_NAME) as RBMBattleBgm

## 1コマ進めて、鳴っている曲を記録する。
func _tick() -> void:
	await tree.process_frame
	clock += tree.root.get_process_delta_time()
	var bgm := _bgm() if is_instance_valid(view) else null
	var track := ""
	var db := -80.0
	var pos := 0.0
	if bgm != null and bgm.player != null and bgm.player.playing and not bgm.player.stream_paused:
		track = bgm.current_track().get_file()
		db = bgm.player.volume_db
		pos = bgm.player.get_playback_position()
	timeline.append([snappedf(clock, 0.001), track, snappedf(db, 0.1), snappedf(pos, 0.01), _playing_players(), Engine.get_process_frames()])
	if awakening_started >= 0.0 and not awakening_se_heard and is_instance_valid(stage_audio):
		for key in (stage_audio.get("history") as Array):
			if str(key).ends_with("_awakening"):
				awakening_se_heard = true
	if track != _last:
		_event("track", track if not track.is_empty() else "(無音)")
		_last = track

## 土台の待ち（動画用の _pace・_frames）も、この道具の時計と記録に数える（数えないと動画と時刻がずれる）。
func _pace(seconds: float) -> void:
	if _arg("pace", "") == "1":
		await _wait(seconds)

func _frames(n: int) -> void:
	for i in range(n):
		await _tick()

func _event(kind: String, detail: Variant = "") -> void:
	events.append({"t": snappedf(clock, 0.001), "kind": kind, "detail": str(detail)})
	print("BGM_EVENT %.3f %s %s" % [clock, kind, detail])

func _wait(seconds: float) -> void:
	var end := clock + seconds
	while clock < end:
		await _tick()

func _first(kind: String, after: float = -1.0) -> float:
	for e in events:
		if e.kind == kind and float(e.t) > after:
			return float(e.t)
	return -1.0

func _position_at(t: float) -> float:
	var best := -1.0
	for row in timeline:
		if float(row[0]) > t:
			break
		best = float(row[3])
	return best

## その時刻の記録のコマの番号（無ければ -1）。
func _frame_at(t: float) -> int:
	for row in timeline:
		if float(row[0]) >= t - 0.0005 and (row as Array).size() > 5:
			return int(row[5])
	return -1

## from〜to の間で一番長かったコマ（ms）。
func _longest_frame_ms(from: float, to: float) -> int:
	var longest := 0.0
	var prev := -1.0
	for row in timeline:
		var t := float(row[0])
		if t > to + 0.0005:
			break
		if prev >= 0.0 and t >= from:
			longest = maxf(longest, t - prev)
		prev = t
	return int(round(longest * 1000.0))

func _track_at(t: float) -> String:
	var best := ""
	for row in timeline:
		if float(row[0]) > t:
			break
		best = str(row[1])
	return best

## ホーム画面では BGM を鳴らさない（2026-11-04 に今のホーム画面に合わせて書き直し）。
## 2026-10-28 からのホーム画面は「挑戦」「ボス作成」の2つのモニターに絵のカード（RBMHomeCardArt）を重ねたもので、
## 前のホーム画面のモニターにあった戦闘のプレビューは無い。そのため次の3つを確かめる:
##   1. 今のホーム画面（2つのモニターと2枚のカードの絵）が出ている
##   2. モニター・カードの中に戦闘の部品（BGM の部品）が無い（ホーム画面の絵が BGM を鳴らす経路が無い）
##   3. 裏で待っている戦闘の画面（挑戦・TEST BATTLE・クリアチェック）の BGM は、戦闘を始めるまで鳴らない。
##      どのボスにも曲がある状態にして確かめる（その戦闘の画面の BGM の部品の表だけを差し替える。本番の表は変えない）。
func _check_home_monitor() -> void:
	var home := RBMGameRoot.new()
	tree.root.add_child(home)
	var monitors: Array = []
	var arts: Array = []
	for i in range(240):
		await _tick()
		monitors = home.find_children("*", "RBMHomeMonitorPanel", true, false)
		arts = home.find_children("*", "RBMHomeCardArt", true, false)
		if monitors.size() >= 2 and arts.size() >= 2:
			break
	var names := []
	for m in monitors:
		names.append(str((m as Node).name))
	_check("ホーム画面: 今のホーム画面（「挑戦」「ボス作成」のモニターと絵のカード）が出ている",
		names.has("ChallengeHomeMonitor") and names.has("CreatorHomeMonitor") and arts.size() == 2, "モニター %s・カード %d 枚" % [names, arts.size()])
	var inside := 0
	for m in monitors:
		inside += (m as Node).find_children("*", "RBMBattleBgm", true, false).size()
	_check("ホーム画面: モニター・カードの中に戦闘の BGM の部品が無い", inside == 0, "%d 個" % inside)
	var waiting := home.find_children("*", "RBMBattleBgm", true, false)
	var every_boss := {}
	for id in RBMVisualAssets.APPEARANCES.values():
		every_boss[str(id)] = {"normal": "musha/musha_normal.ogg"}
	for b in waiting:
		(b as RBMBattleBgm).table = every_boss
		(b as RBMBattleBgm).set("_paths_boss", "-")
	var heard := 0
	var tracks := 0
	var t := 0.0
	while t < 6.0:
		await _tick()
		t += tree.root.get_process_delta_time()
		heard = maxi(heard, _playing_players())
		for b in waiting:
			if not (b as RBMBattleBgm).current_track().is_empty():
				tracks += 1
	_check("ホーム画面: 裏の戦闘の画面の BGM は、戦闘を始めるまで鳴らない（どのボスにも曲がある状態で6秒）",
		not waiting.is_empty() and heard == 0 and tracks == 0, "戦闘の画面の BGM %d 個・鳴った再生器 %d" % [waiting.size(), heard])
	home.queue_free()
	await _frames(6)

func _run_bgm(route: String, boss: String) -> void:
	var tag := boss + "_" + route
	await _check_home_monitor()
	var hp := int(_arg("hp", "2400"))
	if route == "clear_check":
		await _boot_clear_check(boss, hp)
	else:
		await _boot_challenge(boss, hp)
	if director == null or view == null:
		_check(tag + " 戦闘の画面がある", false)
		return
	_check(tag + " 戦闘の画面に BGM が付いている", _bgm() != null)
	await _wait(1.0)
	_check(tag + " 戦闘の前（一覧・ホーム画面）では BGM は鳴らない", _playing_players() == 0, "%d 個" % _playing_players())
	var presenter_ready := false
	stage_audio = _stage().get_node_or_null("RBMAudio")
	# ---- 登場 ----
	# 一覧の読み込みが遅い時に備えて、開始のボタンが出るまで待つ（最大10秒）
	var start := _start_button(route)
	var waited := 0.0
	while (start == null or not start.is_visible_in_tree()) and waited < 10.0:
		await _tick()
		waited += tree.root.get_process_delta_time()
		start = _start_button(route)
	if start == null or not start.is_visible_in_tree():
		_check(tag + " 開始のボタンが出る", false)
		await _shutdown()
		return
	_event("click", "挑戦する" if route == "challenge" else "開始")
	_click_now(start.get_global_rect().get_center())
	var intro := {"start": -1.0, "end": -1.0}
	director.connect("intro_finished", func(): intro.end = clock)
	while intro.end < 0.0 and clock < 30.0:
		await _tick()
		if intro.start < 0.0 and is_instance_valid(director.get("_intro")):
			intro.start = clock
			_event("intro_start")
	_event("intro_end")
	_check(tag + " 登場演出の間は BGM を鳴らさない", intro.start >= 0.0 and _track_at(intro.end - 0.05) == "", "登場 %.2f〜%.2f 秒" % [intro.start, intro.end])
	await _wait(0.2)
	var normal_at := _first("track", intro.end - 0.01)
	_check(tag + " 登場が終わったら覚醒前の曲が鳴る", _track_at(clock) == normal_path.get_file() and normal_at >= intro.end - 0.01 and normal_at - intro.end < 0.15,
		"登場の終わりから %.2f 秒" % (normal_at - intro.end))
	# ---- 攻撃を続ける ----
	var presenter: Node = view.get("_presenter")
	var marks := {"awaken_start": -1.0, "awaken_impact": -1.0, "awaken_impact_frame": -1, "final_impact": -1.0, "result": -1.0}
	presenter.connect("entry_started", func(e: Dictionary):
		if str(e.get("action", "")) == "awakening" and marks.awaken_start < 0.0:
			marks.awaken_start = clock
			awakening_started = clock
			_event("awakening_presentation_start"))
	presenter.connect("entry_impact", func(e: Dictionary):
		var vs: Dictionary = e.get("visual_state", {})
		if str(e.get("action", "")) == "awakening" and marks.awaken_impact < 0.0:
			marks.awaken_impact = clock
			marks.awaken_impact_frame = Engine.get_process_frames()
			_event("awakening_presentation_end")
		if bool(vs.get("battle_over", false)) and marks.final_impact < 0.0:
			marks.final_impact = clock
			_event("final_impact", vs.get("winner", "")))
	director.connect("victory_result_shown", func():
		marks.result = clock
		_event("result_shown"))
	await _pace(5.0)
	var battle: RBMBattle = view.get("session").get("battle")
	var attacks := 0
	while marks.result < 0.0 and clock < 900.0:
		# コマンドを押せるまで待つ
		while (bool(view.call("_is_busy")) or not _any_enabled()) and marks.result < 0.0 and clock < 900.0:
			await _tick()
		if marks.result >= 0.0 or battle.battle_over:
			while marks.result < 0.0 and clock < 900.0:
				await _tick()
			break
		if marks.awaken_impact >= 0.0 and not presenter_ready:
			# 覚醒後の曲を少し聞かせる（動画用）
			presenter_ready = true
			await _pace(6.0)
		var attack := _commands()[0] as Button
		_click_now(attack.get_global_rect().get_center())
		attacks += 1
		await _tick()
	await _wait(1.5)
	_event("end")
	# ---- 判定 ----
	if not awaken:
		_check(tag + " とどめまで覚醒前の曲", _track_at(marks.final_impact - 0.05) == normal_path.get_file())
	else:
		_check_awakening(tag, marks)
	_check_end(tag, marks)
	await _shot(tag + "_result")
	await _shutdown()
	await _wait(0.5)
	_check(tag + " 戦闘の画面を出たら鳴らない", _playing_players() == 0)

func _check_awakening(tag: String, marks: Dictionary) -> void:
	_check(tag + " 覚醒が起きた", marks.awaken_start >= 0.0 and marks.awaken_impact > marks.awaken_start,
		"演出 %.2f〜%.2f 秒（%.2f 秒）" % [marks.awaken_start, marks.awaken_impact, marks.awaken_impact - marks.awaken_start])
	_check(tag + " 覚醒の演出が始まるまでは覚醒前の曲", _track_at(marks.awaken_start - 0.05) == normal_path.get_file())
	var silent_at := _first("track", marks.awaken_start - 0.01)
	_check(tag + " 覚醒の演出が始まったら曲を消す（%.1f 秒で）" % RBMBattleBgm.FADE_AWAKENING,
		silent_at > 0.0 and silent_at - marks.awaken_start <= RBMBattleBgm.FADE_AWAKENING + 0.1 and _track_at(silent_at) == "", "%.2f 秒で無音" % (silent_at - marks.awaken_start))
	_check(tag + " 覚醒の演出の間は曲が鳴らない", _track_at(marks.awaken_impact - 0.05) == "")
	var awakened_at := _first("track", marks.awaken_impact - 0.01)
	var head := _position_at(awakened_at)
	# 2026-11-04: 秒ではなくコマで判定する。覚醒の表示（presenter の entry_impact）はコマ N の途中で届き、BGM はそれを
	# 受けて同じか次のコマ（N+1）で覚醒後の曲を鳴らし始める。この道具はコマの初めに鳴っているかを見るので、見えるのは
	# 遅くとも N+2 のコマ。覚醒の表示を作るコマは重く（武者で 77〜84ms）、秒で測ると、同じ「次のコマで鳴った」が
	# 0.10〜0.12 秒と揺れていた（2026-11-04 調査）。秒と、その間で一番長かったコマも記録に出す。
	var frames_after := _frame_at(awakened_at) - int(marks.awaken_impact_frame)
	_check(tag + " 覚醒が表示されたら、次のコマで覚醒後の曲が頭から鳴る", _track_at(awakened_at) == awakened_path.get_file() and marks.awaken_impact_frame >= 0 and frames_after <= 2 and head < 0.2,
		"演出の終わりから %d コマ（%.2f 秒・一番長いコマ %d ms）・曲の %.2f 秒目から" % [frames_after, awakened_at - marks.awaken_impact, _longest_frame_ms(marks.awaken_impact, awakened_at), head])
	_check(tag + " 覚醒後はとどめまで覚醒後の曲", _track_at(marks.final_impact - 0.05) == awakened_path.get_file())
	_check(tag + " 覚醒の効果音（%s_awakening）は今までどおり鳴る" % tag.get_slice("_", 0), awakening_se_heard)

func _check_end(tag: String, marks: Dictionary) -> void:
	var end_silent := _first("track", marks.final_impact - 0.01)
	_check(tag + " とどめの命中で曲を消す（%.1f 秒で）" % RBMBattleBgm.FADE_END, end_silent > 0.0 and end_silent - marks.final_impact <= RBMBattleBgm.FADE_END + 0.1
		and _track_at(end_silent) == "", "%.2f 秒で無音" % (end_silent - marks.final_impact))
	_check(tag + " 勝利演出の後に結果が出る", marks.result > marks.final_impact and marks.final_impact >= 0.0, "とどめ %.2f・結果 %.2f 秒" % [marks.final_impact, marks.result])
	_check(tag + " 勝利演出・結果の間は鳴らない", _track_at(marks.result) == "" and _track_at(clock) == "")
	var max_players := 0
	for row in timeline:
		max_players = maxi(max_players, int(row[4]))
	_check(tag + " 2曲が同時に鳴らない（鳴っている再生器は最大1つ）", max_players <= 1, "最大 %d" % max_players)
	_check(tag + " ゲーム全体の時間は 1 のまま", is_equal_approx(Engine.time_scale, 1.0))
