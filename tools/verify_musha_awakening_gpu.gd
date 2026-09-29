extends RefCounted
## 朽ちた機械武者の覚醒演出・覚醒後の単体/全体・持続オーラの実GPU検証(標準の本番
## GPU runner経由)。
##   Godot_v4.7-stable_win64.exe --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/verify_musha_awakening_gpu.gd --output=<dir>
## 本番のTEST BATTLE/CLEAR CHECK/CHALLENGEの実戦闘で、①覚醒エントリが専用演出で再生され
## 外見が覚醒後へ切り替わる ②覚醒後の単体/全体が属性ごとに専用演出で再生される
## ③impactが確定エントリで1回だけ ④完成トラック1回のみ ⑤終了後に本体/位置が戻り
## 覚醒状態と持続オーラは残る ⑥シミュレーションが変化しない ⑦着弾の瞬間は墨の層(着弾の閃光)が全画面の戦闘画面の
## UI欄の上にも実際に見え(UI欄の画素が明るくなる)、攻撃が終わるとUI欄が前に戻る ⑧全体攻撃の白い画面(見えない速さの抜刀)の
## 間はUI欄も白くなり、白が引いた直後にはUI欄が元の明るさへ戻る、を確認する。
const Awakening = preload("res://src/bossmaker/visuals/rbm_musha_awakening.gd")
const Ink = preload("res://src/bossmaker/visuals/rbm_musha_ink_director.gd")
const Attack = preload("res://src/bossmaker/visuals/rbm_musha_awakened_presentation.gd")
const Palette = preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")
const SHOT_TIMES := {
	"awakening": [0.5, 1.6, 2.6, 3.4, 4.0, 4.6, 4.95, 5.4, 6.2, 6.8],
	"single": [0.5, 1.0, 1.5, 2.2, 2.5, 3.0],
	"aoe": [0.8, 1.6, 3.2, 4.7, 4.95, 5.6, 6.6],
}
var _gpu_verification_completed := false
var _tree_override: SceneTree
var output_dir: String
var report: Dictionary = {"cases": [], "errors": [], "metrics": {}}
var view = null
var stage = null

func _tree() -> SceneTree: return _tree_override
func _fail(message: String) -> void:
	if not report.errors.has(message):
		report.errors.append(message)
		push_error(message)
		print("MUSHA_AWK_FAIL ", message)

func run_gpu_verification(tree: SceneTree, directory: String) -> int:
	_tree_override = tree
	output_dir = directory
	report["renderer"] = RenderingServer.get_current_rendering_method()
	report["adapter"] = RenderingServer.get_video_adapter_name()
	await _run()
	if report.has("passed") and report.has("case_count"): _gpu_verification_completed = true
	return 0 if report.get("passed", false) else 1

func _run() -> void:
	_tree().root.size = Vector2i(1280, 720)
	_tree().root.content_scale_size = Vector2i(1280, 720)
	_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(output_dir)
	if DisplayServer.get_name() == "headless": return
	for mode in ["test", "clear_check", "challenge"]:
		await _case(mode, "awakening", "NEUTRAL")
	for attribute in Palette.COLORS:
		for kind in ["single", "aoe"]: await _case("test", kind, attribute)
	for mode in ["clear_check", "challenge"]:
		for kind in ["single", "aoe"]: await _case(mode, kind, "FIRE")
	await _case("test", "single", "ICE", true)
	await _case("test", "aoe", "FIRE", true)
	report["case_count"] = report.cases.size()
	report["passed"] = report.errors.is_empty()
	FileAccess.open(output_dir.path_join("musha-awakening-report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MUSHA_AWK_GPU_DONE passed=", report.passed, " cases=", report.case_count)

## いまの画面の、矩形(ステージ=画面の座標)の平均の明るさ。
func _mean_lum(rect: Rect2) -> float:
	var img := _tree().root.get_texture().get_image()
	if img == null or rect.size.x < 1.0: return 0.0
	var f := float(img.get_width()) / 1280.0
	var lum := 0.0
	var n := 0
	for y in range(int(rect.position.y * f), int(rect.end.y * f), 3):
		for x in range(int(rect.position.x * f), int(rect.end.x * f), 3):
			var c := img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
			lum += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			n += 1
	return lum / maxf(n, 1)

func _save(tag: String) -> void:
	var img := _tree().root.get_texture().get_image()
	if img == null: _fail(tag + ": no GPU image")
	else: img.save_png(output_dir.path_join(tag + ".png"))

func _definition(kind: String, attribute: String, counter: bool) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = "appearance_musha"
	draft.boss_name = "Musha Awakening QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	var ids: Array = ["samurai"] if counter and kind == "single" else (["samurai", "hero", "healer", "butler"] if counter else ["hero", "butler", "healer", "samurai"])
	for id in ids: draft.add_party_character(id)
	var spec := {"name": "Musha QA", "type": "attack", "target": "all" if kind == "aoe" else "single", "attribute": attribute, "atk_multiplier": 1.0}
	var id := draft.add_skill(spec)
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	if kind == "awakening":
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND",
			"buff": {"buff_multiplier": 1.5, "duration_turns": 3},
			"heal": {"heal_mode": "fixed", "heal_fixed_amount": 100, "heal_percent": 0.0}})
	return draft.to_definition()

func _check_restored(tag: String, awakened: bool) -> void:
	if not stage._visuals["boss"].visible: _fail(tag + ": boss visibility not restored")
	if stage.is_playing() or is_instance_valid(stage._skill_presentation): _fail(tag + ": presentation cleanup")
	if str(stage._asset_ids["boss"]) != ("musha_awakened" if awakened else "musha"): _fail(tag + ": wrong form " + str(stage._asset_ids["boss"]))
	if awakened and not stage._musha_aura.visible: _fail(tag + ": aura missing after the effect")
	if not awakened and stage._musha_aura.visible: _fail(tag + ": aura visible in the normal form")
	for key in stage._homes:
		if stage._visuals[key].position != stage._homes[key]: _fail(tag + ": position not restored: " + key)

func _case(mode: String, kind: String, attribute: String, counter: bool = false) -> void:
	var definition := _definition(kind, attribute, counter)
	if not await _open_view(mode, definition): return
	var awakening_case := kind == "awakening"
	view.session.battle.boss.hp = 1000 if awakening_case else 1500
	if not awakening_case: view.session.battle.is_awakened = true
	var before: Dictionary = {}
	var entry: Dictionary = {}
	var samurai_id := 0 if counter else 3  # 反撃ケースは侍を先頭(id 0)にした編成
	for attempt in range(16):
		before = view.session.battle.presentation_state().duplicate(true)
		var action: Dictionary = {"type": "skill", "skill_id": "samurai_counter"} if counter and view.session.pending_ally_id() == samurai_id else ({"type": "attack"} if awakening_case else {"type": "defend"})
		for e in view.session.resolve_ally_action(action):
			if awakening_case:
				if str(e.get("action", "")) == "awakening": entry = e
			elif str(e.get("actor")) == "boss": entry = e
		if not entry.is_empty(): break
	var tag := mode + "_" + kind + "_" + attribute + ("_counter" if counter else "")
	if entry.is_empty():
		_fail(tag + ": no production entry")
		await _close_view()
		return
	var resolved: Dictionary = view.session.battle.snapshot().duplicate(true)
	var counters := int(entry.get("counter", false))
	for hit in entry.get("hits", {}).values(): counters += int(hit.get("counter", false))
	if counter and counters != 1: _fail(tag + ": real counter missing")
	if kind == "aoe" and entry.get("hits", {}).size() != 4: _fail(tag + ": expected four targets")
	stage.set_state(before)
	RBMBattlePresenter.apply_status_snapshot(view, before)
	var seen: Array = []
	stage.impact.connect(func(e): seen.append(e))
	stage._sound.history.clear()
	var observed := false
	var switched := false
	var shots: Array = SHOT_TIMES[kind].duplicate()
	var take_shots := mode == "test" and not counter and (awakening_case or attribute in ["FIRE", "ICE"])
	# ⑦ UI欄(最も大きい欄 = 下のステータス欄)の明るさを、攻撃の前と着弾の瞬間で比べる
	var ink = stage.musha_ink_director()
	var hud_rects: Array = ink._collect_hud_rects() if ink != null else []
	var hud_rect: Rect2 = hud_rects[0] if not hud_rects.is_empty() else Rect2()
	var impact_at: float = Ink.S_CUT if kind == "single" else Ink.A_IMPACT
	var hud_before := -1.0
	var hud_checked := awakening_case or counter
	# ⑧ 全体の白い画面: 白の最中と、白が引いた直後
	var flash_stage := 0 if kind == "aoe" and not counter else 2
	if not awakening_case and hud_rects.is_empty(): _fail(tag + ": the battle HUD is not handed to the stage")
	for frame in range(1600 if counter else 800):
		if frame == 7 and not hud_checked: hud_before = _mean_lum(hud_rect)
		if frame == 8: view._present_batch([entry], before)
		var driver = stage._skill_presentation
		if is_instance_valid(driver):
			var right_driver: bool = (driver is Awakening) if awakening_case else (driver is Attack)
			if not right_driver: _fail(tag + ": wrong driver")
			else:
				observed = true
				if awakening_case and str(stage._asset_ids["boss"]) == "musha_awakened": switched = true
				if not awakening_case and kind == "single" and driver._attribute != attribute: _fail(tag + ": wrong attribute input")
				if take_shots and not shots.is_empty() and driver.age >= float(shots[0]):
					_save(tag + "_t%03d" % int(float(shots[0]) * 100.0))
					shots.pop_front()
		await _tree().process_frame
		await RenderingServer.frame_post_draw
		var drv = stage._skill_presentation
		if flash_stage == 0 and is_instance_valid(drv) and float(drv.age) >= Ink.A_FLASH + 0.3:
			flash_stage = 1
			var hud_white := _mean_lum(hud_rect)
			report.metrics[tag + "_hud_lum_white_screen"] = [hud_before, hud_white, float(drv.age) - Ink.A_FLASH]
			if hud_white < 0.7: _fail(tag + ": the white screen does not cover the battle HUD (%.3f)" % hud_white)
			if take_shots: _save(tag + "_white_screen_over_hud")
		elif flash_stage == 1 and is_instance_valid(drv) and float(drv.age) >= Ink.A_FLASH_END + 0.2:
			flash_stage = 2
			var hud_back := _mean_lum(hud_rect)
			report.metrics[tag + "_hud_lum_after_white_screen"] = [hud_before, hud_back, float(drv.age) - Ink.A_FLASH_END]
			if (ink.hud_over[2] as Sprite2D).visible: _fail(tag + ": the ink stays over the battle HUD after the white screen")
			if absf(hud_back - hud_before) > 0.05: _fail(tag + ": the battle HUD does not return right after the white screen (%.3f -> %.3f)" % [hud_before, hud_back])
		if not hud_checked and is_instance_valid(drv) and float(drv.age) >= impact_at - 0.15:
			hud_checked = true
			# 着弾の閃光は0.12秒しかないので、実時間のコマの揺れに左右されないよう、演出の時計を止めて
			# ちょうど着弾+0.03秒まで進め、そのコマを描かせてから測る(測った後は実時間の再生へ戻す)
			stage._tween.pause()
			stage._tween.custom_step(maxf(0.0, impact_at + 0.03 - float(drv.age)))
			await _tree().process_frame
			await RenderingServer.frame_post_draw
			var hud_at := _mean_lum(hud_rect)
			var shown: bool = ink.hud_over.size() == 3 and (ink.hud_over[2] as Sprite2D).visible
			report.metrics[tag + "_hud_lum_before_impact"] = [hud_before, hud_at, float(drv.age) - impact_at]
			if not shown: _fail(tag + ": the ink layer is not shown over the battle HUD at the impact")
			if hud_at < hud_before * 1.8: _fail(tag + ": the impact flash does not reach over the battle HUD (%.3f -> %.3f)" % [hud_before, hud_at])
			if take_shots: _save(tag + "_impact_over_hud")
			stage._tween.play()
		if observed and not stage.is_playing() and not view._presenter.is_playing(): break
	if not observed: _fail(tag + ": dedicated presentation never observed")
	if not awakening_case and not counter and not hud_checked: _fail(tag + ": the impact moment was never sampled")
	if flash_stage != 2: _fail(tag + ": the white screen was never sampled")
	if ink != null:
		for s in ink.hud_over:
			if (s as Sprite2D).visible: _fail(tag + ": the ink stays over the battle HUD after the attack")
	if awakening_case:
		if not switched: _fail(tag + ": appearance never switched to the awakened form")
		if seen.size() != 1: _fail(tag + ": awakening impact events = %d" % seen.size())
	elif seen.size() != 1 or seen[0] != entry: _fail(tag + ": impact contract (%d events)" % seen.size())
	var audio: Array = stage._sound.history.duplicate()
	var track: String = {"awakening": "musha_awakening", "single": "musha_awakened_single", "aoe": "musha_awakened_aoe"}[kind]
	if audio.count(track) != 1: _fail(tag + ": completed track must play exactly once: " + str(audio))
	if not counter:
		for key in audio:
			if str(key) != track: _fail(tag + ": extra SE layered over the completed track: " + str(key))
	_check_restored(tag, true)
	if not awakening_case and view.session.battle.snapshot() != resolved: _fail(tag + ": simulation changed during playback")
	report.cases.append({"mode": mode, "kind": kind, "attribute": attribute, "audio_history": audio, "counter_count": counters, "impact_events": seen.size(), "aura_after": stage._musha_aura.visible})
	print("MUSHA_AWK_CASE ", tag, " audio=", audio, " aura=", stage._musha_aura.visible)
	await _close_view()

func _open_view(mode: String, definition: Dictionary) -> bool:
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	_tree().root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge": view.setup(null)
	view.set_boss_appearance("appearance_musha")
	if mode == "test": view.start(definition, 20260906)
	elif mode == "clear_check": view.start_battle(definition, 20260906)
	else: view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, "appearance_musha")
	for i in range(8): await _tree().process_frame
	stage = view._battlefield_ally_row.get_meta("visual_stage", null)
	if stage == null or not stage.has_method("get_visual_audit"):
		_fail("Production View has no auditable visual stage: " + mode)
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
