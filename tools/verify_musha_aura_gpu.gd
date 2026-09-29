extends RefCounted
## 朽ちた機械武者の覚醒後の常時オーラ(戦場全体の変質)の実GPU検証(標準の本番GPU runner経由)。
##   Godot_v4.7-stable_win64.exe --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/verify_musha_aura_gpu.gd --output=<dir>
## 本番のTEST BATTLEの実戦闘画面(背景・味方・ボス・UI込み)で、覚醒後の見た目を「オーラ有り/無し」
## 同じフレームで撮り比べ、①ボス本体の色が変わらない(白い外套が埋もれない) ②味方の彩度・輝度が落ちる
## ③松明が弱まる ④画面端が暗くなる ⑤足元に墨が出る(墨の層の墨溜まりを含む) ⑥単眼が光る瞬間に戦場が沈み単眼が明るくなる
## ⑦空間圧が端で1〜3px縮む ⑧ウィンドウ拡大(1600x900)でも同じ、を実画素で確認する。さらに
## ⑨実際の覚醒演出から覚醒後待機へ繋がり、広がりが最後まで進む、を確認する。
## 表示専用: 戦闘状態は演出前後で変化しない。
const Timeline = preload("res://src/bossmaker/visuals/rbm_musha_aura_timeline.gd")
var _gpu_verification_completed := false
var _tree_override: SceneTree
var output_dir: String
var report: Dictionary = {"metrics": {}, "errors": []}
var view = null
var stage = null

func _tree() -> SceneTree: return _tree_override
func _fail(message: String) -> void:
	if not report.errors.has(message):
		report.errors.append(message)
		push_error(message)
		print("MUSHA_AURA_FAIL ", message)

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	_tree_override = tree
	output_dir = directory
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	await _run()
	if report.has("passed"): _gpu_verification_completed = true
	return 0 if report.get("passed", false) else 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name() == "headless": return
	for window in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		await _field_case(window)
	await _flow_case()
	report["passed"] = report.errors.is_empty()
	FileAccess.open(output_dir.path_join("musha-aura-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MUSHA_AURA_GPU_DONE passed=", report.passed)

func _frames(count: int) -> void:
	for i in range(count):
		await _tree().process_frame
		await RenderingServer.frame_post_draw

func _shot(tag: String) -> Image:
	var img := _tree().root.get_texture().get_image()
	if img == null:
		_fail(tag + ": no GPU image")
		return Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.save_png(output_dir.path_join(tag + ".png"))
	return img

func _definition(awakening: bool) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha Aura QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]: draft.add_party_character(id)
	var id := draft.add_skill({"name": "Musha QA", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	if awakening:
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
			"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
			"heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0}})
	return draft.to_definition()

func _open_view(awakening: bool) -> bool:
	view = RBMCreatorTestBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.setup(null)
	view.set_boss_appearance("appearance_musha")
	view.start(_definition(awakening), 20260906)
	for i in range(8): await _tree().process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage", null)
	if stage == null:
		_fail("Production View has no visual stage")
		return false
	var ticks := 0
	while view._presenter.is_playing() and ticks < 600:
		await _tree().process_frame
		ticks += 1
	stage.set_state(view.session.battle.presentation_state())
	return true

func _close_view() -> void:
	if is_instance_valid(view): view.queue_free()
	view = null
	stage = null
	await _tree().process_frame

# --- 画素の測定 ---------------------------------------------------------------

func _lum(c: Color) -> float: return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
func _sat(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	return 0.0 if hi <= 0.001 else (hi - minf(c.r, minf(c.g, c.b))) / hi

## 領域(canvas座標)の平均の明るさ・彩度。
func _mean(img: Image, rect: Rect2, factor: float) -> Dictionary:
	var x0 := clampi(int(rect.position.x * factor), 0, img.get_width() - 1)
	var y0 := clampi(int(rect.position.y * factor), 0, img.get_height() - 1)
	var x1 := clampi(int(rect.end.x * factor), x0 + 1, img.get_width())
	var y1 := clampi(int(rect.end.y * factor), y0 + 1, img.get_height())
	var lum := 0.0
	var sat := 0.0
	var red := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			lum += _lum(c)
			sat += _sat(c)
			red += c.r
			n += 1
	return {"lum": lum / maxf(n, 1), "sat": sat / maxf(n, 1), "red": red / maxf(n, 1)}

## ボスの白い外套(明るく低彩度)の画素のうち、比べる撮影で明るさがほぼ変わらない割合。
func _cloak_unchanged(before: Image, after: Image, rect: Rect2, factor: float) -> Dictionary:
	var same := 0
	var total := 0
	for y in range(int(rect.position.y * factor), int(rect.end.y * factor), 2):
		for x in range(int(rect.position.x * factor), int(rect.end.x * factor), 2):
			var a := before.get_pixel(x, y)
			if _lum(a) > 0.55 and _sat(a) < 0.5:
				total += 1
				if absf(_lum(after.get_pixel(x, y)) - _lum(a)) < 0.03: same += 1
	return {"total": total, "ratio": float(same) / maxf(total, 1)}

func _global(local: Vector2) -> Vector2:
	return stage.get_global_rect().position + local

## 墨の層(rbm_musha_ink_director)がステージへ足した表示部品の表示/非表示。撮り比べ専用で、演出の状態は変えない。
func _set_ink_layer_visible(shown: bool) -> void:
	var ink = stage.musha_ink_director()
	if ink == null: return
	for c in [ink.back, ink.mid, ink.top]:
		(c.disp as CanvasItem).visible = shown
	ink.accent.visible = shown

# --- 実戦闘画面で、オーラ有り/無しを同じ場面で比べる --------------------------------

func _field_case(window: Vector2i) -> void:
	_tree().root.size = window
	_tree().root.content_scale_size = Vector2i(1280, 720)
	_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if not await _open_view(false): return
	var f := float(window.x) / 1280.0
	var tag := "field_%d" % window.x
	view.session.battle.is_awakened = true
	stage.set_state(view.session.battle.presentation_state())
	var aura: Node2D = stage._musha_aura
	if str(stage._asset_ids["boss"]) != "musha_awakened" or not aura.visible: _fail(tag + ": not in the awakened form")
	var snapshot: Dictionary = view.session.battle.snapshot().duplicate(true)
	# 覚醒後の常時オーラ = 戦場の変質(_musha_aura) + 墨の層(足元の墨溜まり・刀から立ち上る墨)。無しの撮影では両方を隠す。
	if stage.musha_ink_director() == null: _fail(tag + ": the awakened musha has no ink layer")
	aura.visible = false
	_set_ink_layer_visible(false)
	await _frames(4)
	var off := _shot(tag + "_off")
	aura.visible = true
	aura._event_age = 0.0
	await _frames(3)
	var on_field := _shot(tag + "_on_field")
	_set_ink_layer_visible(true)
	await _frames(1)
	var on := _shot(tag + "_on")
	if aura.amount < 0.99: _fail(tag + ": the field did not reach full strength: %s" % aura.amount)
	# ① ボス本体の白い外套(明るく低彩度)の画素は、戦場の変質(色調)が掛かっても変わらない。
	var boss_rect: Rect2 = (stage._visuals["boss"] as Control).get_global_rect()
	var cloak := _cloak_unchanged(off, on_field, boss_rect, f)
	report.metrics[tag + "_boss_cloak_pixels"] = cloak.total
	report.metrics[tag + "_boss_cloak_unchanged_ratio"] = cloak.ratio
	if cloak.total < 100: _fail(tag + ": could not find the boss cloak pixels (%d)" % cloak.total)
	elif cloak.ratio < 0.97: _fail(tag + ": the boss body is being graded (unchanged %.2f)" % cloak.ratio)
	# ①' 墨の層(刀から立ち上る墨)は本体の手前にも掛かる(承認済みの見た目)が、白い外套を埋めない。
	var cloak_ink := _cloak_unchanged(off, on, boss_rect, f)
	report.metrics[tag + "_boss_cloak_unchanged_ratio_with_ink"] = cloak_ink.ratio
	if cloak_ink.total >= 100 and cloak_ink.ratio < 0.85: _fail(tag + ": the ink layer buries the boss cloak (unchanged %.2f)" % cloak_ink.ratio)
	# ② 味方: 彩度・輝度が落ちる。
	var ally_off := {"lum": 0.0, "sat": 0.0}
	var ally_on := {"lum": 0.0, "sat": 0.0}
	for key in stage._party_keys:
		var r: Rect2 = (stage._visuals[key] as Control).get_global_rect()
		var mo := _mean(off, r, f)
		var mn := _mean(on, r, f)
		ally_off.lum += mo.lum / 4.0
		ally_off.sat += mo.sat / 4.0
		ally_on.lum += mn.lum / 4.0
		ally_on.sat += mn.sat / 4.0
	report.metrics[tag + "_allies_sat_ratio"] = ally_on.sat / maxf(ally_off.sat, 0.001)
	report.metrics[tag + "_allies_lum_ratio"] = ally_on.lum / maxf(ally_off.lum, 0.001)
	if ally_on.sat > ally_off.sat * 0.85: _fail(tag + ": allies keep their colour")
	if ally_on.lum > ally_off.lum * 0.97: _fail(tag + ": allies are not dimmed")
	# ③ 松明: 炎のまわりが弱まる。
	var torch_ratios: Array = []
	for t in aura._torches:
		var tp: Vector2 = _global(t)
		var mo := _mean(off, Rect2(tp - Vector2(26, 26), Vector2(52, 52)), f)
		var mn := _mean(on, Rect2(tp - Vector2(26, 26), Vector2(52, 52)), f)
		torch_ratios.append(mn.lum / maxf(mo.lum, 0.001))
	report.metrics[tag + "_torch_lum_ratio"] = torch_ratios
	for r in torch_ratios:
		if float(r) > 0.8: _fail(tag + ": a torch is not dimmed (ratio %.2f)" % float(r))
	# ④ 画面端: 左右の縁の帯が、中央付近より強く暗い(UIパネルに隠れない縁の帯で測る)。
	var sr: Rect2 = stage.get_global_rect()
	var edge_ratios: Array = []
	for x0 in [sr.position.x, sr.end.x - 20.0]:
		var rect := Rect2(Vector2(x0, sr.position.y + sr.size.y * 0.20), Vector2(20, sr.size.y * 0.55))
		edge_ratios.append(_mean(on, rect, f).lum / maxf(_mean(off, rect, f).lum, 0.001))
	var centre := Rect2(sr.position + sr.size * Vector2(0.40, 0.30), sr.size * Vector2(0.16, 0.20))
	var centre_ratio: float = _mean(on, centre, f).lum / maxf(_mean(off, centre, f).lum, 0.001)
	report.metrics[tag + "_edge_lum_ratio"] = edge_ratios
	report.metrics[tag + "_centre_lum_ratio"] = centre_ratio
	for r in edge_ratios:
		if float(r) > centre_ratio - 0.04: _fail(tag + ": the screen edge is not inked more than the centre (%.2f vs %.2f)" % [float(r), centre_ratio])
	if centre_ratio < 0.55: _fail(tag + ": the centre is crushed (ratio %.2f)" % centre_ratio)
	# ⑤ 足元: ボスの足元が暗くなる(墨染み)。
	var foot: Vector2 = _global(aura._home_foot("boss"))
	var ink_off := _mean(off, Rect2(foot + Vector2(-90, -8), Vector2(60, 16)), f)
	var ink_on := _mean(on, Rect2(foot + Vector2(-90, -8), Vector2(60, 16)), f)
	report.metrics[tag + "_foot_ink_lum_ratio"] = ink_on.lum / maxf(ink_off.lum, 0.001)
	if ink_on.lum > ink_off.lum * 0.75: _fail(tag + ": no ink at the boss's feet")
	# ⑥ 単眼が光る瞬間: 単眼が明るくなり、戦場(味方)が一段沈む。
	aura._event_age = Timeline.event_time(Timeline.EYE_FIRST, Timeline.EYE_PERIOD, Timeline.EYE_JITTER, 11.0, 0) + 0.15
	await _frames(2)
	var pulse := _shot(tag + "_eye_pulse")
	if aura.eye < 0.5 or aura.jolt < 0.2: _fail(tag + ": the eye pulse did not fire (eye %.2f jolt %.2f)" % [aura.eye, aura.jolt])
	var eye_at: Vector2 = _global(aura._home_foot("boss") + aura.EYE_OFFSET)
	var eye_on := _mean(on, Rect2(eye_at - Vector2(5, 2), Vector2(10, 4)), f)
	var eye_pulse := _mean(pulse, Rect2(eye_at - Vector2(5, 2), Vector2(10, 4)), f)
	report.metrics[tag + "_eye_red"] = [eye_on.red, eye_pulse.red]
	if eye_pulse.red < eye_on.red + 0.02 and eye_pulse.lum < eye_on.lum + 0.02: _fail(tag + ": the eye does not brighten on the pulse")
	var ally_pulse := 0.0
	for key in stage._party_keys:
		ally_pulse += _mean(pulse, (stage._visuals[key] as Control).get_global_rect(), f).lum / 4.0
	report.metrics[tag + "_allies_pulse_lum_ratio"] = ally_pulse / maxf(ally_on.lum, 0.001)
	if ally_pulse >= ally_on.lum: _fail(tag + ": the field does not sink on the eye pulse")
	# ⑦ 空間圧: 武者から遠い左端の背景が内側(右)へ1〜3px寄る(画面揺れではない)。
	aura._event_age = Timeline.event_time(Timeline.COMPRESS_FIRST, Timeline.COMPRESS_PERIOD, Timeline.COMPRESS_JITTER, 23.0, 0) + 0.17
	await _frames(1)
	var squeezed := _shot(tag + "_compress")
	if aura.compression < 0.8: _fail(tag + ": compression did not fire (%.2f)" % aura.compression)
	var best_shift := 0
	var best_err := 1e9
	var errs: Array = []
	# 左の城壁と塔(輪郭がはっきりしていて、武者から遠い)を測る。
	var y_from := int((sr.position.y + sr.size.y * 0.22) * f)
	var y_to := int((sr.position.y + sr.size.y * 0.47) * f)
	var x_from := int((sr.position.x + 20.0) * f)
	var x_to := int((sr.position.x + 330.0) * f)
	for s in range(-4, 5):
		var err := 0.0
		var cnt := 0
		for y in range(y_from, y_to, 2):
			for x in range(x_from, x_to, 2):
				err += absf(_lum(squeezed.get_pixel(x, y)) - _lum(on.get_pixel(clampi(x + s, 0, on.get_width() - 1), y)))
				cnt += 1
		err /= maxf(cnt, 1)
		errs.append(snappedf(err, 0.0001))
		if err < best_err:
			best_err = err
			best_shift = s
	report.metrics[tag + "_compress_errs_-4..4"] = errs
	report.metrics[tag + "_compress_shift_px"] = float(best_shift) / f  # 負=武者の方へ寄る
	if best_shift > -1 or best_shift < -int(ceil(4.0 * f)): _fail(tag + ": the far-left background shifts by %d px (expected 1-3 canvas px toward the boss)" % best_shift)
	# 画面端の墨筆と斬痕(目視用の撮影)。
	aura._event_age = Timeline.event_time(Timeline.EDGE_FIRST, Timeline.EDGE_PERIOD, Timeline.EDGE_JITTER, 51.0, 0) + 1.6
	await _frames(2)
	_shot(tag + "_edge_ink")
	aura._event_age = Timeline.event_time(Timeline.SLASH_FIRST, Timeline.SLASH_PERIOD, Timeline.SLASH_JITTER, 37.0, 0) + 0.06
	await _frames(1)
	_shot(tag + "_slash")
	# 表示専用。
	if view.session.battle.snapshot() != snapshot: _fail(tag + ": the simulation changed while the field was on screen")
	await _close_view()

# --- 実際の覚醒演出 → 覚醒後待機 ---------------------------------------------------

func _flow_case() -> void:
	_tree().root.size = Vector2i(1280, 720)
	_tree().root.content_scale_size = Vector2i(1280, 720)
	if not await _open_view(true): return
	view.session.battle.boss.hp = 1000
	var before: Dictionary = {}
	var entry: Dictionary = {}
	for attempt in range(16):
		before = view.session.battle.presentation_state().duplicate(true)
		for e in view.session.resolve_ally_action({"type": "attack"}):
			if str(e.get("action", "")) == "awakening": entry = e
		if not entry.is_empty(): break
	if entry.is_empty():
		_fail("flow: no production awakening entry")
		await _close_view()
		return
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var aura: Node2D = stage._musha_aura
	var peak_amount_while_playing := 0.0
	var seen_playing := false
	var finished_at := -1
	var after_shots := [30, 120, 240]
	for frame in range(900):
		if frame == 8: view._present_batch([entry], before)
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		if stage.is_playing(): seen_playing = true
		if stage.is_playing(): peak_amount_while_playing = maxf(peak_amount_while_playing, aura.amount)
		if seen_playing and not stage.is_playing() and not view._presenter.is_playing() and finished_at < 0:
			finished_at = frame
		if finished_at >= 0 and after_shots.has(frame - finished_at):
			_shot("flow_after_%03d" % (frame - finished_at))
		if finished_at >= 0 and frame - finished_at > 250: break
	if not seen_playing: _fail("flow: the awakening never played")
	if finished_at < 0: _fail("flow: the awakening never finished")
	report.metrics["flow_amount_while_playing_peak"] = peak_amount_while_playing
	report.metrics["flow_amount_after"] = aura.amount
	if peak_amount_while_playing >= 0.99: _fail("flow: the field was already complete before the awakening finished")
	if aura.amount < 0.99: _fail("flow: the field did not finish widening (%.2f)" % aura.amount)
	if str(stage._asset_ids["boss"]) != "musha_awakened" or not aura.visible: _fail("flow: not in the awakened idle with the aura")
	if view.session.battle.snapshot() != resolved: _fail("flow: the simulation changed during the awakening")
	await _close_view()
