extends "res://tools/verify_encounter_gpu.gd"
## 戦闘の結果・クリアチェックの開始・保存の画面（2026-10-18 採用: 戦闘の結果は案C「シネマティック」、クリアチェックと保存は
## 案A「王道RPG」）の実GPUの確認。本物のゲーム（RBMGameRoot）を起動し、本物のクリックで次の場面まで進める。
##   1. 挑戦の勝利（登場 → 戦闘 → 勝利演出 → 結果）→「挑戦一覧へ」  2. 挑戦の敗北 →「もう一度挑戦」で登場から始まる
##   3. クリアチェックの成功（開始の画面 → 戦闘 → 結果 →「最終確認へ」→ 保存 → 保存できた →「クリエイター一覧に戻る」）
##   4. クリアチェックの失敗 →「作成画面へ戻る」  5. TEST BATTLE の勝利・敗北 →「作成画面へ戻る」
## 確かめること: 見出し・文・ボタンの文、文字の切れ、ボタンが画面の中で押せる（本物のクリック）、最初のフォーカス、
## 結果の画面を出す時に止まらないか（実時間の時だけ、出てから1秒の最長のフレーム）。
## 保存は出力フォルダの中の一時フォルダ（ユーザーの保存は触らない）。通信はしない。
## 起動: Godot --path . [--write-movie <dir>/movie.avi --fixed-fps 30] res://tools/gpu_runner.tscn --
##       --tool=res://tools/verify_result_screens_gpu.gd --output=<dir> [--locale=ja|en] [--mode=simple|hardcore]
##       [--shots=1] [--video=1（説明の帯とマウスの矢印を出し、間を取る）] [--scenes=challenge_win,challenge_lose,cc_win,cc_lose,test_win,test_lose]

var creator_mode := RBMCreatorDraft.CREATOR_MODE_SIMPLE
var lang := "ja"
var video := false
var _strong := false
var _caption_layer: CanvasLayer
var _caption: Label
var _pointer: Polygon2D
var marks: Array = []
var hitches: Array = []
## 結果の画面が出たフレーム（組み立てたフレーム）とその前のフレームの長い方（ms）。
var _reveal_ms := 0.0

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	lang = _arg("locale", "ja")
	TranslationServer.set_locale(lang)
	creator_mode = RBMCreatorDraft.CREATOR_MODE_ADVANCED if _arg("mode", "simple") == "hardcore" else RBMCreatorDraft.CREATOR_MODE_SIMPLE
	video = _arg("video", "") == "1"
	_setup_caption()
	var scenes := Array(_arg("scenes", "challenge_win,challenge_lose,cc_win,cc_lose,test_win,test_lose").split(","))
	if scenes.has("challenge_win"): await _scene_challenge(true)
	if scenes.has("challenge_lose"): await _scene_challenge(false)
	if scenes.has("cc_win"): await _scene_clear_check(true)
	if scenes.has("cc_lose"): await _scene_clear_check(false)
	if scenes.has("test_win"): await _scene_test_battle(true)
	if scenes.has("test_lose"): await _scene_test_battle(false)
	_mark("end")
	var bad := checks.filter(func(c): return not c.ok).size()
	var f := FileAccess.open(out.path_join("result-screens-report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"locale": lang, "mode": creator_mode, "window": tree.root.size, "checks": checks, "failed": bad, "marks": marks, "hitches": hitches}, "  "))
	f.close()
	print("RESULT_SCREENS_GPU_DONE locale=", lang, " mode=", creator_mode, " checks=", checks.size(), " failed=", bad)
	_gpu_verification_completed = true
	return 0 if bad == 0 else 1

# ---------------------------------------------------------------------------
# 下書き・起動

## 勝つ戦闘は HP 1500（数ターン戦う）、負ける戦闘は強いボスの全体攻撃。保存済みの扱い（クリアチェック済み・公開済み）にしない。
func _draft(boss: String, hp: int) -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = NAMES[boss] if lang == "ja" else "Rusted Musha Zero"
	d.appearance_id = "appearance_" + boss
	d.set_creator_mode(creator_mode)
	d.hp = 99999 if _strong else hp
	d.atk = 9999 if _strong else 30
	d.spd = 1
	d.author_name = "mina"
	d.battle_background = "night"
	var skill := d.add_skill({"name": "強襲", "type": "attack", "target": "all" if _strong else "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	d.normal_actions_enabled = true
	d.normal_action_percentages[skill] = 100.0
	for c in PARTY[boss]:
		d.add_party_character(c)
	d.record_clear_check_success()
	d.publish()
	return d

func _boot_creator(boss: String, hp: int) -> RBMCreatorMain:
	var stages := out.path_join("stages")
	_reset_dir(stages)
	RBMLocalStageRepository.set_stages_dir_for_testing(stages)
	draft = _draft(boss, hp)
	var result := RBMLocalStageRepository.save_new(draft)
	game = RBMGameRoot.new()
	tree.root.add_child(game)
	await _frames(12)
	(game.find_child("CreateModeButton", true, false) as Button).pressed.emit()
	await _frames(4)
	var creator: Node = game.get("creator_entry")
	creator.call("_on_open_stage_pressed", str(result.get("stage_id", "")))
	await _frames(10)
	return creator.get("main") as RBMCreatorMain

# ---------------------------------------------------------------------------
# 確かめる・撮る

## 文字が切れていないか（切り取りのある文字は幅、折り返す文字は見えない行、ボタンは文の幅）。
func _check_text(tag: String, root: Node) -> void:
	var bad: Array = []
	for n in root.find_children("*", "Label", true, false):
		var l := n as Label
		if not l.is_visible_in_tree() or l.text.strip_edges().is_empty() or l.text == "▶":
			continue
		var size := l.get_theme_font_size("font_size")
		if l.clip_text:
			var w := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var box := l.size.x
			var sb := l.get_theme_stylebox("normal")
			if sb != null:
				box -= sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)
			if w > box + 1.0:
				bad.append("%s（%d > %d）" % [l.text.substr(0, 30), int(w), int(box)])
		elif l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_line_count() > l.get_visible_line_count():
			bad.append("%s（行が見えない）" % l.text.substr(0, 30))
		if not Rect2(0, 0, 1280, 720).encloses(l.get_global_rect()):
			bad.append("%s（画面の外）" % l.text.substr(0, 30))
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.text.is_empty():
			var w := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
			if w > b.size.x - 16.0:
				bad.append("%s（ボタン %d > %d）" % [b.text.substr(0, 30), int(w), int(b.size.x - 16.0)])
			if not Rect2(0, 0, 1280, 720).encloses(b.get_global_rect()):
				bad.append("%s（ボタンが画面の外）" % b.text.substr(0, 30))
	_check("%s の文字が切れない・画面の中" % tag, bad.is_empty(), ", ".join(bad))

func _shot_named(tag: String, root: Node) -> void:
	_check_text(tag, root)
	if _arg("shots", "") != "1":
		return
	var was := _caption_layer.visible
	_caption_layer.visible = false
	await tree.process_frame
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join("%s_%s_%s.png" % [lang, creator_mode, tag]))
	_caption_layer.visible = was

## 見えているボタンの文（表示の順）。
func _button_texts(panel: Control) -> Array:
	var texts: Array = []
	for c in panel.get_children():
		if c is Button and (c as Button).visible:
			texts.append((c as Button).text)
	return texts

## 結果の画面が出てからの最長のフレーム（実時間の時だけ意味がある。録画の時は記録だけ）。
func _watch_reveal(tag: String, seconds: float) -> void:
	var worst := _reveal_ms
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < seconds:
		await _step_frame()
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		t += tree.root.get_process_delta_time()
	hitches.append({"scene": tag, "worst_frame_ms": snappedf(worst, 0.1), "reveal_frame_ms": snappedf(_reveal_ms, 0.1)})
	print("REVEAL ", tag, " reveal_frame=", snappedf(_reveal_ms, 0.1), " worst_after_and_reveal=", snappedf(worst, 0.1))
	if not video and _arg("movie", "") != "1":
		_check("%s 結果の画面を出す時に止まらない（最長 %.1f ms）" % [tag, worst], worst < 50.0)

# ---------------------------------------------------------------------------
# 動画用: 説明の帯・マウスの矢印

func _setup_caption() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.layer = 90
	tree.root.add_child(_caption_layer)
	_caption = Label.new()
	_caption.position = Vector2(0, 0)
	_caption.size = Vector2(1280, 40)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", Color("ffd060"))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.7)
	_caption.add_theme_stylebox_override("normal", bg)
	_caption_layer.add_child(_caption)
	_pointer = Polygon2D.new()
	_pointer.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 16), Vector2(11, 26), Vector2(15, 24), Vector2(10, 15), Vector2(18, 15)])
	_pointer.color = Color.WHITE
	var outline := Line2D.new()
	outline.points = _pointer.polygon
	outline.closed = true
	outline.width = 1.5
	outline.default_color = Color.BLACK
	_pointer.add_child(outline)
	_caption_layer.add_child(_pointer)
	_caption_layer.visible = video

## 動画の中の場面の始まり（描いたコマの数。--fixed-fps 30 なら ÷30 で秒）。
func _mark(scene: String) -> void:
	marks.append([scene, Engine.get_frames_drawn()])
	print("SCENE_MARK ", scene, " ", Engine.get_frames_drawn())

func _say(text: String) -> void:
	_caption.text = text

func _motion(to: Vector2) -> void:
	super(to)
	if is_instance_valid(_pointer):
		_pointer.position = to

func _step_frame() -> void:
	await tree.process_frame

func _hold(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await _step_frame()
		t += tree.root.get_process_delta_time()

func _glide(to: Vector2, seconds: float) -> void:
	var from := mouse
	var t := 0.0
	while t < seconds:
		t += tree.root.get_process_delta_time()
		_motion(from.lerp(to, smoothstep(0.0, 1.0, minf(1.0, t / seconds))))
		await _step_frame()

## 本番のボタンを本物のクリックで押す（動画では矢印を動かしてから）。
func _press(b: Button, what: String) -> void:
	if b == null or not b.is_visible_in_tree():
		_check("%s のボタンが見えている" % what, false)
		return
	var at := b.get_global_rect().get_center()
	if video:
		await _glide(at, 0.5)
		await _hold(0.5)
	var fired := {"v": false}
	var on_pressed := func(): fired.v = true
	b.pressed.connect(on_pressed, CONNECT_ONE_SHOT)
	await _click(at)
	_check("%s を本物のクリックで押せる" % what, fired.v)
	if b.pressed.is_connected(on_pressed):
		b.pressed.disconnect(on_pressed)

# ---------------------------------------------------------------------------
# 戦闘を進める

func _wait_intro() -> void:
	if director == null:
		return
	var done := {"v": false}
	director.connect("intro_finished", func(): done.v = true, CONNECT_ONE_SHOT)
	var t := 0.0
	while not done.v and t < 14.0:
		await _step_frame()
		t += tree.root.get_process_delta_time()

func _busy() -> bool:
	if view.has_method("_is_busy"):
		return bool(view.call("_is_busy"))
	return bool(view.call("_is_presenting")) if view.has_method("_is_presenting") else false

## 決着まで攻撃を続け、本番の結果の画面が出るまで待つ。
func _fight_until_result() -> bool:
	var battle: RBMBattle = view.get("session").get("battle")
	var outcome: Control = view.get("_outcome_area")
	var t := 0.0
	var last := Time.get_ticks_usec()
	var delta := 0.0
	var prev_delta := 0.0
	while t < 120.0 and not (battle.battle_over and outcome.is_visible_in_tree() and not _busy()):
		if not battle.battle_over and not _busy() and _any_enabled():
			var attack := _commands()[0] as Button
			_click_now(attack.get_global_rect().get_center())
		await _step_frame()
		var now := Time.get_ticks_usec()
		prev_delta = delta
		delta = (now - last) / 1000.0
		last = now
		t += tree.root.get_process_delta_time()
	# 結果の画面は、表示になったフレームの終わりに組み立てる（そのフレームの長さが、ここで最後に測った長さ）
	_reveal_ms = maxf(delta, prev_delta)
	await _frames(2)
	return battle.winner == "ally"

## 結果の画面の共通の確かめ: 見出し・ボタンの文・ボタンが出た後のフォーカス・勝利演出の後の濃さ。
func _check_result(tag: String, headline: String, buttons: Array) -> void:
	var outcome: Control = view.get("_outcome_area")
	var label := outcome.get_node("OutcomeLabel") as Label
	var deco := outcome.get_node_or_null("ResultDecoration") as Control
	_check("%s 結果の画面の飾りがある" % tag, deco != null)
	var title := label.text
	if deco != null and deco.find_child("ResultTitle", true, false) != null:
		title = (deco.find_child("ResultTitle", true, false) as Label).text
	_check("%s 見出し %s" % [tag, headline], title == headline, title)
	_check("%s ボタン %s" % [tag, str(buttons)], _button_texts(outcome) == buttons, str(_button_texts(outcome)))
	var dialog := outcome.get_parent() as Control
	_check("%s 結果の画面が薄いまま残らない" % tag, is_equal_approx(dialog.modulate.a, 1.0) and is_equal_approx(outcome.modulate.a, 1.0), "%s/%s" % [dialog.modulate.a, outcome.modulate.a])
	var first: Button = null
	for c in outcome.get_children():
		if c is Button and (c as Button).visible:
			first = c
			break
	_check("%s 最初のフォーカスが主の操作" % tag, first != null and first.has_focus(), str(tree.root.gui_get_focus_owner()))

# ---------------------------------------------------------------------------
# 場面

func _scene_challenge(win: bool) -> void:
	_strong = not win
	var tag := "challenge_" + ("win" if win else "lose")
	_mark(tag)
	_say("挑戦の勝利：勝利演出 → 結果（案C・CLEAR）→「挑戦一覧へ」" if win else "挑戦の敗北：結果（案C・DEFEAT）→「もう一度挑戦」で登場から")
	await _boot_challenge("musha", 1500)
	if view == null:
		_check("挑戦の画面", false)
		return
	if video:
		await _hold(0.6)
	_click_now(_start_button("challenge").get_global_rect().get_center())
	await _wait_intro()
	var won := await _fight_until_result()
	_check("%s の決着" % tag, won == win)
	await _watch_reveal(tag, 1.0)
	await _hold(2.4)
	_check_result(tag, "CLEAR" if win else "DEFEAT", [tr("もう一度挑戦"), tr("挑戦一覧へ")])
	await _shot_named("battle_" + ("victory" if win else "defeat"), view.get("_outcome_area"))
	if win:
		await _press(view.get("_return_button"), tag + " 挑戦一覧へ")
		await _hold(0.8)
		_check("%s 挑戦一覧へ戻る" % tag, not view.is_visible_in_tree())
	else:
		await _press(view.get("_retry_button"), tag + " もう一度挑戦")
		var t := 0.0
		while t < 8.0 and not (director.call("is_playing") and int(view.get("session").get("battle").current_turn) == 1):
			await _step_frame()
			t += tree.root.get_process_delta_time()
		_check("%s もう一度挑戦で登場から始まる" % tag, int(view.get("session").get("battle").current_turn) == 1 and not (view.get("_outcome_area") as Control).visible)
		if video:
			await _hold(2.0)
	await _shutdown()

func _scene_clear_check(win: bool) -> void:
	_strong = not win
	var tag := "cc_" + ("win" if win else "lose")
	_mark(tag)
	_say("クリアチェック：開始（案A）→ 戦闘 → 成功 →「最終確認へ」→ 保存 → 保存できた" if win else "クリアチェックの失敗：開始（案A）→ 戦闘 → 失敗 →「作成画面へ戻る」")
	await _boot_clear_check("musha", 1500)
	if view == null:
		_check("クリアチェックの画面", false)
		return
	var main: RBMCreatorMain = (game.get("creator_entry") as Node).get("main")
	var confirm: Control = view.get("_confirm_panel")
	await _hold(2.2)
	_check("%s 開始の画面は画面全体" % tag, confirm.is_visible_in_tree() and confirm.get_global_rect() == Rect2(0, 0, 1280, 720))
	var start := view.find_child("ConfirmStartButton", true, false) as Button
	_check("%s 開始の画面の最初のフォーカスは「開始する」" % tag, start.has_focus())
	await _shot_named("cc_start", confirm)
	await _press(start, tag + " 開始する")
	await _wait_intro()
	var won := await _fight_until_result()
	_check("%s の決着" % tag, won == win)
	await _watch_reveal(tag, 1.0)
	await _hold(1.4)
	if win:
		_check_result(tag, "CLEAR!", [tr("最終確認へ（保存・公開）")])
	else:
		_check_result(tag, "FAILED…", [tr("もう一度挑戦"), tr("作成画面へ戻る")])
	var note := (view.get("_outcome_area") as Control).find_child("ResultNote", true, false) as Label
	_check("%s 一言" % tag, note != null and note.text == (tr("クリアチェックが完了しました。") if win else tr("ボスが強すぎる時は、能力（HP・ATK）か行動を見直しましょう")), note.text if note != null else "")
	await _shot_named("cc_" + ("success" if win else "failure"), view.get("_outcome_area"))
	if not win:
		await _press(view.get("_return_button"), tag + " 作成画面へ戻る")
		await _hold(0.8)
		_check("%s 最終確認の画面へ戻る" % tag, main.current_step == RBMCreatorMain.STEP_COUNT and main.get("_steps_root").visible)
		await _shutdown()
		return
	await _press(view.get("_return_button"), tag + " 最終確認へ（保存・公開）")
	await _hold(1.0)
	_check("%s 最終確認の画面へ" % tag, main.current_step == RBMCreatorMain.STEP_COUNT and main.get("_steps_root").visible)
	await _press(main.find_child("SaveButton", true, false) as Button, tag + " 保存")
	await _hold(1.6)
	var save: RBMCreatorSaveView = main.get("_save_view")
	_check("%s 保存の画面は画面全体" % tag, save.is_visible_in_tree() and save.get_global_rect() == Rect2(0, 0, 1280, 720))
	_check("%s 「ぼうけんのしょ」を出さない" % tag, not _all_texts(save).contains("ぼうけんのしょ") and not _all_texts(save).contains("Adventure Log"))
	_check("%s 保存の選び方" % tag, _button_texts(save.get("_choice_panel")) == [tr("上書き保存"), tr("新しいボスとして保存"), tr("戻る")], str(_button_texts(save.get("_choice_panel"))))
	_check("%s 保存の最初のフォーカスは上書きではない" % tag, (save.get("_back_button") as Button).has_focus())
	await _shot_named("save_choice", save)
	await _press(save.get("_overwrite_button"), tag + " 上書き保存")
	await _hold(1.6)
	_check("%s 保存できた" % tag, (save.get("_success_panel") as Control).is_visible_in_tree())
	_check("%s 保存できたの最初のフォーカス" % tag, (save.get("_success_return_button") as Button).has_focus())
	await _shot_named("save_done", save)
	await _press(save.get("_success_return_button"), tag + " クリエイター一覧に戻る")
	await _hold(0.8)
	_check("%s クリエイター一覧へ" % tag, not save.is_visible_in_tree())
	await _shutdown()

func _all_texts(root: Node) -> String:
	var parts := PackedStringArray()
	for n in root.find_children("*", "Label", true, false):
		parts.append((n as Label).text)
	return "\n".join(parts)

func _scene_test_battle(win: bool) -> void:
	_strong = not win
	var tag := "test_" + ("win" if win else "lose")
	_mark(tag)
	_say("TEST BATTLE の" + ("勝利" if win else "敗北") + "：結果（案C）→「作成画面へ戻る」")
	var main := await _boot_creator("musha", 1500)
	await _press(main.find_child("TestBattleButton", true, false) as Button, tag + " テストバトル")
	view = main.get("_test_battle_view")
	director = null
	# 戦闘画面を開いてからの3秒（結果の画面の絵を裏で作る間）に止まらないか（PERFORMANCE.md §2.1。録画の時は記録だけ）
	var worst := 0.0
	var over33 := 0
	var t := 0.0
	var last := Time.get_ticks_usec()
	while t < 3.0:
		await _step_frame()
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		over33 += 1 if ms > 33.0 else 0
		t += tree.root.get_process_delta_time()
	hitches.append({"scene": tag + "_open", "worst_frame_ms": snappedf(worst, 0.1), "over_33ms": over33})
	if not video:
		_check("%s 戦闘画面を開いてからの3秒に 33ms を超えるフレームが無い（最長 %.1f ms）" % [tag, worst], over33 == 0)
	var won := await _fight_until_result()
	_check("%s の決着" % tag, won == win)
	await _watch_reveal(tag, 1.0)
	await _hold(2.4)
	_check_result(tag, "CLEAR" if win else "DEFEAT", [tr("もう一度テスト"), tr("作成画面へ戻る")])
	await _shot_named("test_" + ("victory" if win else "defeat"), view.get("_outcome_area"))
	await _press(view.get("_return_button"), tag + " 作成画面へ戻る")
	await _hold(0.8)
	_check("%s 最終確認の画面へ戻る" % tag, main.get("_steps_root").visible)
	await _shutdown()
