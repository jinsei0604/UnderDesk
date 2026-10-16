extends RefCounted
## 戦闘テンポの計測（2026-10-16）: 全ボスの全種類の行動（単体・全体・回復・強化、覚醒、覚醒後の4種類）について、
## 本物の挑戦の戦闘画面（RBMChallengeBattleView）で、味方が「防御」を押してから、ボスの行動の演出が始まる・命中する・
## 終わる・味方がコマンドを押せるようになるまでを、実時間で測る。押せるようになった後も3秒見て、音・ボスの動きが
## いつ終わるか（操作を返した後も続いていないか）を記録する。
## 戦闘の状態・乱数・保存データは変えない（定義はこのツールの中で作り、保存しない。入力は本物のボタンを押す）。
## 実行: godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_battle_tempo_gpu.gd --output=<dir>
## 引数: --bosses=slime,wolf,...（省略時は9体）--kinds=single,all,heal,buff（省略時は4種類）--variants=base,awakened
##       --visual=1（画面の動きの量も毎フレーム測る。画面の読み出しで遅くなるので --fixed-fps 60 と一緒に使う）
##       --shots=N（--visual=1 の時、2巡目のボスの行動の間、N フレームごとに画面を <output>/shots/<技>/ へ保存する。一覧画像用）
##       --fps=N（録画用。--fixed-fps N --write-movie と一緒に使い、時刻をフレーム数÷N で測る。2巡目のボスの行動の始まりと
##       操作できるようになったフレームの番号を "REC <技> start=<番号> operable=<番号>" の行に出す）
##       --cases=<技>,...（slime_single・gentleman_awakened_all のような名前で、測る技を絞る）
##       --sync=1（通しの音の同期: ボスの行動の間、毎フレーム演出の時刻と、鳴っている長い音（2.5秒より長い音）の再生位置を記録し、
##       その差（音−演出）の揺れを出す。区間を飛ばした時に音の位置を合わせ直せていなければ、飛ばした秒数だけ差が変わる）
## 結果: <output>/battle-tempo.json と、表 battle-tempo.md
const BOSSES := ["slime", "wolf", "knight", "dragon", "ghost", "golem", "musha", "astronaut", "gentleman"]
const AWAKENED := ["dragon", "musha", "astronaut", "gentleman"]
const KINDS := ["single", "all", "heal", "buff"]
const SKILLS := {
	"single": {"skill_id": "tempo_single", "name": "単体", "type": "attack", "target": "single", "attribute": "ICE", "atk_multiplier": 1.0},
	"all": {"skill_id": "tempo_all", "name": "全体", "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 0.8},
	"heal": {"skill_id": "tempo_heal", "name": "回復", "type": "self_heal", "heal_amount": 300},
	"buff": {"skill_id": "tempo_buff", "name": "強化", "type": "atk_self_buff", "buff_multiplier": 1.5, "duration_turns": 2},
}

var _gpu_verification_completed := false
var tree: SceneTree
var out := ""
var rows: Array = []
var visual := false
var shots := 0
var fps := 0
var sync := false
var _shot_dir := ""

func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback

## 時刻（秒）。--visual=1 は --fixed-fps 60 と一緒に使い、画面の読み出しで実時間が延びても、ゲームの時刻（フレーム数÷60）で測る
func _now() -> float:
	if visual:
		return Engine.get_process_frames() / 60.0
	if fps > 0:
		return Engine.get_process_frames() / float(fps)
	return Time.get_ticks_usec() / 1000000.0

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	TranslationServer.set_locale("ja")
	visual = _arg("visual", "") == "1"
	shots = int(_arg("shots", "0")) if visual else 0
	fps = int(_arg("fps", "0"))
	sync = _arg("sync", "") == "1"
	var cases: Array = Array(_arg("cases", "").split(",", false))
	var bosses: Array = Array(_arg("bosses", ",".join(BOSSES)).split(","))
	var kinds: Array = Array(_arg("kinds", ",".join(KINDS)).split(","))
	var variants: Array = Array(_arg("variants", "base,awakened").split(","))
	for boss in bosses:
		for variant in variants:
			if variant == "awakened" and not AWAKENED.has(boss):
				continue
			for kind in kinds:
				if not cases.is_empty() and not cases.has("%s%s_%s" % [boss, "_awakened" if variant == "awakened" else "", kind]):
					continue
				await _run_case(str(boss), str(kind), variant == "awakened")
	var f := FileAccess.open(out.path_join("battle-tempo.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"visual": visual, "fixed_fps": Engine.max_fps, "rows": rows}, "  "))
	f.close()
	_write_table()
	print("BATTLE_TEMPO_DONE rows=", rows.size())
	_gpu_verification_completed = true
	return 0

# ---------------------------------------------------------------------------

var view: RBMChallengeBattleView
var stage: Control
var presenter: Node
var _events: Array = []
var _opening: Dictionary = {}

func _definition(kind: String, awakened: bool) -> Dictionary:
	var definition: Dictionary = RBMDataLoader.load_dict("res://data_bossmaker/definitions/test_definition_a.json")
	var roster := ["hero", "butler", "healer", "tank"]
	definition["party"] = []
	for id in roster:
		var skill_ids: Array = []
		for skill in RBMDataLoader.load_dict("res://data_bossmaker/allies/" + id + ".json").get("skills", []):
			skill_ids.append(skill["id"])
		definition["party"].append({"character_id": id, "allowed_skill_ids": skill_ids})
	var skill: Dictionary = (SKILLS[kind] as Dictionary).duplicate(true)
	definition["boss"]["skills"] = [skill]
	definition["boss"]["normal_actions"] = [{"skill_id": skill["skill_id"], "weight": 1}]
	definition["boss"]["scripted_actions"] = []
	definition["boss"].erase("action_sequence")
	definition["boss"]["hp"] = 99999
	definition["boss"]["atk"] = 10
	definition["boss"]["spd"] = 1
	if awakened:
		# 条件なしの覚醒（最初の確かめで覚醒する）。強化・回復は付けない（ボスの行動の時間だけを測るため）。
		definition["boss"]["awakening"] = {"conditions": [], "condition_logic": "AND"}
	else:
		definition["boss"].erase("awakening")
	return definition

func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame

func _open(boss: String, kind: String, awakened: bool) -> void:
	_shot_dir = ""
	view = RBMChallengeBattleView.new()
	tree.root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.battle_background = "night"
	var definition := _definition(kind, awakened)
	view.set_boss_appearance("appearance_" + boss)
	await _frames(2)
	# 本物の流れと同じく、戦闘を始める前の画面で素材を読み始め、読み終えてから始める（確認画面にいる間に読み終える場合）
	view.prepare_presentations(definition, "appearance_" + boss, "night")
	stage = view._battlefield_ally_row.get_meta("visual_stage", null) as Control
	for i in 600:
		await tree.process_frame
		var warm = stage.get("_presentation_warmup")
		if i > 30 and (warm == null or bool(warm.call("is_ready"))):
			break
	stage.impact.connect(func(entry): _events.append({"t": _now(), "type": "impact", "who": _who(entry)}))
	stage.finished.connect(func(): _events.append({"t": _now(), "type": "finished"}))
	# 戦闘の開始（条件なしの覚醒は、ここで最初のターンの始めに起きる）も同じ方法で測る
	_opening = await _measure(func(): view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_" + boss), 1.0)

func _close() -> void:
	if is_instance_valid(view):
		view.queue_free()
	view = null
	await _frames(6)

func _who(entry: Dictionary) -> String:
	return "%s:%s:%s" % [str(entry.get("actor", "")), str(entry.get("action", "")), str(entry.get("skill_id", ""))]

func _operable() -> bool:
	if view == null or view.session == null or view.session.battle == null or view.session.battle.battle_over:
		return false
	var b := view.find_child("DefendButton", true, false) as Button
	return b != null and b.is_visible_in_tree() and not b.disabled and not view._is_busy()

func _wait_operable(limit: float) -> bool:
	var t0 := _now()
	while _now() - t0 < limit:
		if _operable():
			return true
		await tree.process_frame
	return false

## 再生中の効果音（BGM 以外）があるか
func _sound_playing() -> bool:
	for n in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		var p := n as AudioStreamPlayer
		if p.playing and p.bus != "BGM":
			return true
	for n in tree.root.find_children("*", "AudioStreamPlayer2D", true, false):
		if (n as AudioStreamPlayer2D).playing:
			return true
	return false

## 鳴っている長い音（通しの音）の再生位置。入れ替えの途中で2つ鳴っている時は、大きく鳴っている方（消えていく方は除く）。無ければ -1。
func _track_position() -> float:
	var best: AudioStreamPlayer = null
	for n in stage.find_children("*", "AudioStreamPlayer", true, false):
		var p := n as AudioStreamPlayer
		if p.playing and p.stream != null and p.stream.get_length() > 2.5 and (best == null or p.volume_db > best.volume_db):
			best = p
	return best.get_playback_position() if best != null else -1.0

## 鳴っている音（ファイル名と再生位置）
func _playing_sounds() -> Array:
	var out: Array = []
	for n in stage.find_children("*", "AudioStreamPlayer", true, false):
		var p := n as AudioStreamPlayer
		if p.playing and p.stream != null:
			out.append([str(p.stream.resource_path).get_file(), snappedf(p.get_playback_position(), 0.01)])
	return out

func _boss_at_rest() -> bool:
	var audit: Dictionary = stage.call("get_visual_audit")
	var boss: Dictionary = (audit.get("actors", {}) as Dictionary).get("boss", {})
	if boss.is_empty():
		return true
	return Vector2(boss.get("position", Vector2.ZERO)).distance_to(Vector2(boss.get("home", Vector2.ZERO))) <= 0.5

func _boss_acted(entries: Array) -> bool:
	for e in entries:
		if str(e.who).begins_with("boss:"):
			return true
	return false

## 画面の動きの量（縮小した画面の前のフレームとの差の平均、0〜255）
var _prev_small: PackedByteArray = PackedByteArray()
func _motion_energy() -> float:
	var img := tree.root.get_texture().get_image()
	img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var e := 0.0
	if _prev_small.size() == data.size():
		var sum := 0
		for i in range(0, data.size(), 3):
			sum += absi(data[i] - _prev_small[i]) + absi(data[i + 1] - _prev_small[i + 1]) + absi(data[i + 2] - _prev_small[i + 2])
		e = float(sum) / float(data.size())
	_prev_small = data
	return e

## 1回分: 味方の入力（防御のボタンを押す）→ 押せるようになる、を測る。押せるようになった後も observe 秒見る。
func _measure_round(observe: float) -> Dictionary:
	return await _measure(func(): (view.find_child("DefendButton", true, false) as Button).pressed.emit(), observe)

func _measure(action: Callable, observe: float) -> Dictionary:
	_events.clear()
	var frames: Array = []
	var entries: Array = []
	var t_click := _now()
	action.call()
	var t_operable := -1.0
	var last_entry_key := ""
	var last_t := t_click
	var max_frame := 0.0
	var over33 := 0
	_prev_small = PackedByteArray()
	while true:
		await tree.process_frame
		if visual:
			await RenderingServer.frame_post_draw
		var t := _now()
		var dt := t - last_t
		last_t = t
		var playing: bool = stage.call("is_playing")
		var entry: Dictionary = stage.get("_entry")
		var key := _who(entry) if playing and not entry.is_empty() else ""
		if key != "" and key != last_entry_key:
			entries.append({"who": key, "start": t - dt})
		last_entry_key = key
		var fr := {"t": t, "dt": dt, "f": Engine.get_frames_drawn(), "phase": str(stage.get("_phase")), "sound": _sound_playing(), "boss_rest": _boss_at_rest()}
		if sync:
			var p = stage.get("_skill_presentation")
			fr["age"] = float(p.get("age")) if is_instance_valid(p) and p.get("age") != null else -1.0
			fr["audio"] = _track_position()
			fr["sounds"] = _playing_sounds()
		if visual and _boss_acted(entries):
			fr["energy"] = _motion_energy()
			if shots > 0 and not _shot_dir.is_empty() and (t_operable < 0.0 or t - t_operable < 0.6) and Engine.get_process_frames() % shots == 0:
				var img := tree.root.get_texture().get_image()
				img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
				var boss_start := 0.0
				for e in entries:
					if str(e.who).begins_with("boss:"):
						boss_start = float(e.start)
						break
				img.save_png(_shot_dir.path_join("t%05.2f.png" % (t - boss_start)))
		frames.append(fr)
		if t_operable < 0.0:
			max_frame = maxf(max_frame, dt)
			if dt > 0.0334:
				over33 += 1
			if _operable():
				t_operable = t
		elif t - t_operable >= (observe if _boss_acted(entries) else 0.0):
			break
		if t - t_click > 40.0:
			break
	return {"t_click": t_click, "t_operable": t_operable, "entries": entries, "events": _events.duplicate(), "frames": frames,
		"max_frame_ms": max_frame * 1000.0, "over33": over33}

## ボスの行動1つの時刻をまとめる（攻撃開始・命中・演出の終わり・押せる・音の終わり・ボスが戻った時刻、すべて攻撃開始からの秒）
func _summarize(r: Dictionary, boss_action: String) -> Dictionary:
	var start := -1.0
	for e in r.entries:
		if str(e.who).begins_with("boss:" + boss_action):
			start = float(e.start)
			break
	if start < 0.0:
		return {"found": false}
	var impact := -1.0
	var finished := -1.0
	var boss_seen := false
	for ev in r.events:
		if ev.type == "impact" and str(ev.get("who", "")).begins_with("boss:" + boss_action) and impact < 0.0:
			impact = float(ev.t)
			boss_seen = true
		elif ev.type == "finished" and boss_seen and finished < 0.0 and float(ev.t) >= start:
			finished = float(ev.t)
	var operable := float(r.t_operable)
	var sound_end := -1.0
	var rest := -1.0
	var waiting := 0.0
	var energy_end := -1.0
	var idle_energy: Array = []
	for fr in r.frames:
		var t := float(fr.t)
		if t < start:
			if fr.has("energy"):
				idle_energy.append(float(fr.energy))
			continue
		if fr.sound:
			sound_end = t
		if not fr.boss_rest:
			rest = t
		if str(fr.phase) == "waiting":
			waiting += float(fr.dt)
	if visual:
		# 落ち着いた時の画面の動き（押せるようになって1秒後から）を基準に、それを明らかに超える最後の時刻
		var calm: Array = []
		for fr in r.frames:
			if float(fr.t) > operable + 1.0 and fr.has("energy"):
				calm.append(float(fr.energy))
		calm.sort()
		var base := float(calm[int(calm.size() * 0.9)]) if not calm.is_empty() else 0.0
		for fr in r.frames:
			if float(fr.t) >= start and fr.has("energy") and float(fr.energy) > base * 1.5 + 0.6:
				energy_end = float(fr.t)
	# 一番長いフレーム（攻撃開始から押せるようになった直後まで）と、その時刻（攻撃開始から）
	var worst := 0.0
	var worst_at := -1.0
	for fr in r.frames:
		var t := float(fr.t)
		if t >= start and (operable < 0.0 or t <= operable + 0.1) and float(fr.dt) > worst:
			worst = float(fr.dt)
			worst_at = t - start
	# 画面の動きの量の推移（攻撃開始からの秒・量、0.05秒ごとの最大）。止まった「間」を探すため
	var curve: Array = []
	if visual:
		var bucket := -1
		for fr in r.frames:
			if not fr.has("energy") or float(fr.t) < start:
				continue
			var b := int((float(fr.t) - start) / 0.05)
			if b != bucket:
				curve.append([snappedf(b * 0.05, 0.01), 0.0])
				bucket = b
			curve[curve.size() - 1][1] = maxf(float(curve[curve.size() - 1][1]), snappedf(float(fr.energy), 0.01))
	# 通しの音の同期（--sync=1）: 差（音−演出）の最初の値と、最も離れた値
	var sync_info := {}
	if sync:
		var offs: Array = []
		for fr in r.frames:
			if float(fr.t) >= start and float(fr.get("age", -1.0)) > 0.15 and float(fr.get("audio", -1.0)) >= 0.0:
				offs.append([snappedf(float(fr.age), 0.01), snappedf(float(fr.audio) - float(fr.age), 0.001)])
		if not offs.is_empty():
			var first := float(offs[0][1])
			var drift := 0.0
			var drift_at := 0.0
			for o in offs:
				if absf(float(o[1]) - first) > absf(drift):
					drift = float(o[1]) - first
					drift_at = float(o[0])
			sync_info = {"first_offset": first, "max_drift": snappedf(drift, 0.001), "drift_at_age": drift_at, "samples": offs.size(), "curve": offs}
		# 鳴っていた音ごとの、演出の時刻での始まりと終わり
		var spans := {}
		for fr in r.frames:
			if float(fr.t) < start or float(fr.get("age", -1.0)) < 0.0:
				continue
			for snd in fr.get("sounds", []):
				var k := str(snd[0])
				if not spans.has(k):
					spans[k] = [float(fr.age), float(fr.age)]
				spans[k][1] = float(fr.age)
		sync_info["sound_spans"] = spans
	var next_entries: Array = []
	for e in r.entries:
		if float(e.start) > start and not str(e.who).begins_with("boss:" + boss_action):
			next_entries.append({"who": e.who, "at": snappedf(float(e.start) - start, 0.01)})
	return {"found": true,
		"impact_s": snappedf(impact - start, 0.01) if impact >= 0.0 else -1.0,
		"finished_s": snappedf(finished - start, 0.01) if finished >= 0.0 else -1.0,
		"operable_s": snappedf(operable - start, 0.01) if operable >= 0.0 else -1.0,
		"finished_to_operable_s": snappedf(operable - finished, 0.01) if operable >= 0.0 and finished >= 0.0 else -1.0,
		"click_to_start_s": snappedf(start - float(r.t_click), 0.01),
		"sound_end_s": snappedf(sound_end - start, 0.01) if sound_end >= 0.0 else -1.0,
		"boss_back_home_s": snappedf(rest - start, 0.01) if rest >= 0.0 else 0.0,
		"motion_end_s": snappedf(energy_end - start, 0.01) if energy_end >= 0.0 else -1.0,
		"waiting_s": snappedf(waiting, 0.01),
		"max_frame_ms": snappedf(float(r.max_frame_ms), 0.1), "over33": int(r.over33),
		"worst_ms": snappedf(worst * 1000.0, 0.1), "worst_at_s": snappedf(worst_at, 0.01),
		"after_boss": next_entries, "energy_curve": curve, "sync": sync_info}

func _run_case(boss: String, kind: String, awakened: bool) -> void:
	await _open(boss, kind, awakened)
	var tag := "%s%s_%s" % [boss, "_awakened" if awakened else "", kind]
	var row := {"boss": boss, "awakened": awakened, "kind": kind, "tag": tag}
	for e in _opening.get("entries", []):
		if str(e.who).begins_with("boss:awakening"):
			row["awakening"] = _summarize(_opening, "awakening")
	# 1巡目（覚醒する時は覚醒もここ）と2巡目（素材も読み終えた、いつもの状態）
	for round in 2:
		var round_rows: Array = []
		var boss_done := false
		var guard := 0
		while not boss_done and guard < 8:
			guard += 1
			if not _operable():
				if not await _wait_operable(30.0):
					break
			_shot_dir = ""
			if round == 1 and shots > 0:
				_shot_dir = out.path_join("shots").path_join(tag)
				DirAccess.make_dir_recursive_absolute(_shot_dir)
			var r := await _measure_round(3.0 if round == 1 else 1.0)
			var acted := false
			for e in r.entries:
				if str(e.who).begins_with("boss:skill"):
					acted = true
				if str(e.who).begins_with("boss:awakening"):
					row["awakening"] = _summarize(r, "awakening")
			if acted:
				boss_done = true
				var s := _summarize(r, "skill")
				row["round%d" % (round + 1)] = s
				if round == 1:
					row["_frames"] = r.frames if visual else []
					if fps > 0 and bool(s.get("found", false)):
						var start_t := float(r.t_click) + float(s.click_to_start_s)
						var f_start := -1
						var f_op := -1
						for fr in r.frames:
							if f_start < 0 and float(fr.t) >= start_t:
								f_start = int(fr.f)
							if f_op < 0 and float(r.t_operable) >= 0.0 and float(fr.t) >= float(r.t_operable):
								f_op = int(fr.f)
						print("REC %s start=%d operable=%d click=%d" % [tag, f_start, f_op, int(r.frames[0].f) - 1])
	var shown: Dictionary = (row.get("round2", {}) as Dictionary).duplicate()
	shown.erase("energy_curve")
	if shown.has("sync") and not (shown.sync as Dictionary).is_empty():
		var sy: Dictionary = (shown.sync as Dictionary).duplicate()
		sy.erase("curve")
		shown["sync"] = sy
	print("TEMPO ", tag, " ", JSON.stringify(shown))
	if row.has("awakening"):
		var aw: Dictionary = (row["awakening"] as Dictionary).duplicate()
		aw.erase("energy_curve")
		print("TEMPO ", tag, " awakening ", JSON.stringify(aw))
	row.erase("_frames")
	rows.append(row)
	await _close()

func _write_table() -> void:
	var lines: Array[String] = ["| 技 | 攻撃開始→命中 | →演出の終わり | 終わり→操作可能 | 攻撃開始→操作可能 | 音の終わり | 画面の動きの終わり | ボスが戻る | 待ち(素材) | 最長フレーム（時刻） |", "|---|---|---|---|---|---|---|---|---|---|"]
	for row in rows:
		for key in ["awakening", "round2"]:
			if not row.has(key) or not bool((row[key] as Dictionary).get("found", false)):
				continue
			var s: Dictionary = row[key]
			var name := str(row.tag) if key == "round2" else str(row.boss) + "_覚醒"
			lines.append("| %s | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.0fms（%.2f） |" % [name, s.impact_s, s.finished_s, s.finished_to_operable_s, s.operable_s, s.sound_end_s, s.motion_end_s, s.boss_back_home_s, s.waiting_s, s.worst_ms, s.worst_at_s])
	var f := FileAccess.open(out.path_join("battle-tempo.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
