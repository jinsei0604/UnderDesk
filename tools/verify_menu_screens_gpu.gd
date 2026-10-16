extends RefCounted
## 挑戦ハブ・ボス戦作成の入口・作成方法の選択・保存したボス戦の一覧（2026-10 刷新）の実GPU検証。
## 本物の RBMGameRoot を起動し、実際の画面遷移・マウス（Viewport.push_input のマウス移動・クリック・ホイール）・
## キーボード（Tab・矢印・Enter・文字入力）で操作して、静止画・動画・はみ出し/重なりの点検・処理時間を残す。
## 保存データは --output の中の一時フォルダの見本だけ（実プレイヤーの user:// の保存・設定には触れない）。
## 通信（オンライン一覧）は使わない。
##
## 起動（README の GPU runner）:
##   Godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_menu_screens_gpu.gd --output=<dir> [--locale=ja|en] [--phase=shots|video_creator|video_list|video_hub|perf]
##   動画は --write-movie <file>.ogv --fixed-fps 30 を付けて video_* を、処理時間は録画なしの実時間で perf を使う。

var _gpu_verification_completed := false
var tree: SceneTree
var out := ""
var locale := "ja"
var game: RBMGameRoot
var evidence := {"shots": [], "checks": [], "errors": [], "notes": [], "metrics": {}}
var cursor: Control
var layer: CanvasLayer
var mouse := Vector2(640, 700)

## 見本: [ボス名, 外見, モード, HP, 状態(draft/playable/clear_checked), 公開, 作者メッセージ, 覚醒, 最終更新(秒前)]
const SAMPLES := [
	["朽ちた機械武者・零式", "appearance_musha", "advanced", 4800, "clear_checked", true, "居合の構えに入ったら守りを固めること。", true, 600],
	["月面の迷子", "appearance_astronaut", "simple", 2600, "clear_checked", false, "重力の波は全体攻撃。回復を温存しよう。", false, 7200],
	["赤スライムの王", "appearance_slime", "simple", 1200, "playable", false, "", false, 86400],
	["黒炎竜ヴァルグ", "appearance_dragon", "advanced", 9000, "clear_checked", true, "覚醒後のブレスは2回連続で来る。", true, 172800],
	["霧の紳士", "appearance_gentleman", "advanced", 5200, "draft", false, "", true, 259200],
	["石の番人", "appearance_golem", "simple", 3000, "playable", false, "", false, 400000],
	["夜の騎士団長", "appearance_knight", "simple", 2400, "draft", false, "", false, 800000],
	["月夜の狼", "appearance_wolf", "simple", 1800, "playable", false, "", false, 2000000],
	["", "", "simple", 1, "draft", false, "", false, 40000000],
]

func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return fallback

func run_gpu_verification(scene_tree: SceneTree, directory: String) -> int:
	tree = scene_tree
	out = directory
	DirAccess.make_dir_recursive_absolute(out)
	locale = _arg("locale", "ja")
	# 表示言語だけを切り替える（RBMLocale.set_locale は設定ファイルへ保存するので使わない）。
	TranslationServer.set_locale(locale)
	var phase := _arg("phase", "shots")
	var stages := out.path_join("sample_stages")
	_reset_dir(stages)
	_save_samples(stages, SAMPLES)
	match phase:
		"shots":
			await _phase_shots()
		"video_creator":
			await _phase_video_creator()
		"video_list":
			await _phase_video_list()
		"video_hub":
			await _phase_video_hub()
		"perf":
			await _phase_perf()
	if is_instance_valid(game):
		game.queue_free()
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	var report := out.path_join("report_%s_%s.json" % [phase, locale])
	var f := FileAccess.open(report, FileAccess.WRITE)
	f.store_string(JSON.stringify(evidence, "\t"))
	f.close()
	print("MENU_SCREENS_DONE phase=%s locale=%s checks=%d errors=%d" % [phase, locale, evidence.checks.size(), evidence.errors.size()])
	_gpu_verification_completed = true
	return 0 if evidence.errors.is_empty() else 1

# ---------------------------------------------------------------------------
# 見本データ（一時フォルダだけ）

func _reset_dir(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for sub in DirAccess.get_directories_at(dir):
			_reset_dir(dir.path_join(sub))
			DirAccess.remove_absolute(dir.path_join(sub))
		for file_name in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.make_dir_recursive_absolute(dir)

func _sample_draft(row: Array) -> RBMCreatorDraft:
	var d := RBMCreatorDraft.new()
	d.boss_name = row[0]
	d.appearance_id = row[1]
	d.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED if row[2] == "advanced" else RBMCreatorDraft.CREATOR_MODE_SIMPLE)
	d.hp = row[3]
	d.atk = 120
	d.spd = 60
	d.author_name = "jinsei"
	if str(row[4]) != "draft":
		d.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
		for c in ["hero", "butler", "healer", "samurai"]:
			d.add_party_character(c)
	if not str(row[6]).is_empty():
		d.set_author_notes(row[6])
	# 覚醒は戦闘の内容の一部なので、クリアチェックの記録より前に設定する（後から変えると記録が無効になる）。
	if bool(row[7]) and d.supports_awakening():
		d.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 50.0}], "condition_logic": "AND"})
	if str(row[4]) == "clear_checked":
		d.record_clear_check_success()
	if bool(row[5]):
		d.publish()
	return d

func _save_samples(dir: String, rows: Array) -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(dir)
	var now := int(Time.get_unix_time_from_system())
	for row in rows:
		var result := RBMLocalStageRepository.save_new(_sample_draft(row))
		var path := dir.path_join("%s.json" % str(result.get("stage_id", "")))
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		data["updated_unix_time"] = now - int(row[8])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()

# ---------------------------------------------------------------------------
# 入力（本物の入力イベントを Viewport へ流す）と疑似カーソル

class FakeCursor:
	extends Control
	var down := false
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(24, 28)
	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 20), Vector2(5, 15), Vector2(9, 24), Vector2(12, 23), Vector2(8, 14), Vector2(15, 14)])
		var s := 0.85 if down else 1.0
		var scaled := PackedVector2Array()
		for p in pts:
			scaled.append(p * s)
		draw_colored_polygon(scaled, Color.WHITE)
		var outline := scaled.duplicate()
		outline.append(scaled[0])
		draw_polyline(outline, Color(0, 0, 0, 0.9), 1.5)

func _cursor_setup() -> void:
	layer = CanvasLayer.new()
	layer.layer = 100
	tree.root.add_child(layer)
	cursor = FakeCursor.new()
	layer.add_child(cursor)
	cursor.position = mouse

func _motion(to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - mouse
	mouse = to
	tree.root.push_input(ev, true)
	if cursor != null:
		cursor.position = to

func _frames(n: int) -> void:
	for i in range(n):
		await tree.process_frame

func _hold(seconds: float) -> void:
	await _frames(maxi(1, int(seconds * 30.0)))

func _move(to: Vector2, seconds: float = 0.5) -> void:
	var from := mouse
	var n := maxi(1, int(seconds * 30.0))
	for i in range(n):
		var t := float(i + 1) / n
		t = t * t * (3.0 - 2.0 * t)
		_motion(from.lerp(to, t))
		await tree.process_frame

func _click(at: Vector2 = Vector2(-1, -1)) -> void:
	if at.x >= 0:
		_motion(at)
		await tree.process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = mouse
		ev.global_position = mouse
		tree.root.push_input(ev, true)
		if cursor != null:
			(cursor as FakeCursor).down = pressed
			cursor.queue_redraw()
		await _frames(3)

func _wheel(at: Vector2, down: bool, steps: int) -> void:
	_motion(at)
	for i in range(steps):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
			ev.pressed = pressed
			ev.factor = 1.0
			ev.position = at
			ev.global_position = at
			tree.root.push_input(ev, true)
		await _frames(2)

func _key(keycode: Key, shift: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		ev.shift_pressed = shift
		tree.root.push_input(ev)
	await _frames(2)

func _type(text: String, per_char_frames: int = 3) -> void:
	for i in range(text.length()):
		var ev := InputEventKey.new()
		ev.unicode = text.unicode_at(i)
		ev.pressed = true
		tree.root.push_input(ev)
		var up := InputEventKey.new()
		up.unicode = text.unicode_at(i)
		up.pressed = false
		tree.root.push_input(up)
		await _frames(per_char_frames)

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _find(node: Node, node_name: String) -> Control:
	var found := node.find_child(node_name, true, false) as Control
	_check(found != null, "exists: %s" % node_name)
	return found

# ---------------------------------------------------------------------------
# 記録・点検

func _check(ok: bool, label: String) -> void:
	evidence.checks.append({"label": label, "passed": ok})
	if not ok:
		evidence.errors.append(label)
		push_warning("CHECK FAILED: " + label)

func _note(text: String) -> void:
	evidence.notes.append(text)
	print("NOTE ", text)

func _shot(shot_name: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var win := DisplayServer.window_get_size()
	var file_name := "%s_%s_%dx%d.png" % [shot_name, locale, win.x, win.y]
	tree.root.get_texture().get_image().save_png(out.path_join(file_name))
	evidence.shots.append(file_name)
	print("SHOT ", file_name)

## 見えている文字・ボタンが、画面（1280×720）からはみ出していないか、文字が横に切れていないか、
## 同じ親のボタン同士が重なっていないかを点検する。スクロールの外に隠れている行は対象外。
func _audit(screen: Control, screen_name: String) -> void:
	var view := Rect2(0, 0, 1280, 720)
	var clip_rects: Array = []
	for node in screen.find_children("*", "ScrollContainer", true, false):
		if (node as Control).is_visible_in_tree():
			clip_rects.append(node)
	var issues := 0
	for node in screen.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or not (c is Label or c is Button or c is LineEdit):
			continue
		var hidden_by_scroll := false
		for scroll in clip_rects:
			if (scroll as Control).is_ancestor_of(c) and not (scroll as Control).get_global_rect().grow(4).encloses(c.get_global_rect()):
				hidden_by_scroll = true
		if hidden_by_scroll:
			continue
		var rect := c.get_global_rect()
		if not view.grow(0.5).encloses(rect):
			issues += 1
			_check(false, "%s: %s is outside the screen %s" % [screen_name, c.get_path(), rect])
		if c is Label:
			var l := c as Label
			if l.text.is_empty() or l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			if l.get_minimum_size().x > l.size.x + 0.5:
				issues += 1
				_check(false, "%s: label %s is clipped (%s > %s) '%s'" % [screen_name, l.get_path(), l.get_minimum_size().x, l.size.x, l.text])
		elif c is Button:
			var b := c as Button
			if b.get_combined_minimum_size().x > b.size.x + 0.5 or b.get_combined_minimum_size().y > b.size.y + 0.5:
				issues += 1
				_check(false, "%s: button %s is smaller than its content" % [screen_name, b.get_path()])
			for other in b.get_parent().get_children():
				if other != b and other is Button and (other as Control).is_visible_in_tree() and b.get_index() < other.get_index():
					if rect.intersects((other as Control).get_global_rect()):
						issues += 1
						_check(false, "%s: %s overlaps %s" % [screen_name, b.name, other.name])
	_check(issues == 0, "%s: no clipped/outside/overlapping UI" % screen_name)

func _boot_game() -> void:
	game = RBMGameRoot.new()
	tree.root.add_child(game)
	await _frames(20)

func _open_creator() -> RBMCreatorEntry:
	(game.find_child("CreateModeButton", true, false) as Button).pressed.emit()
	await _frames(6)
	return game.creator_entry

func _open_hub() -> RBMChallengeHubView:
	(game.find_child("ChallengeModeButton", true, false) as Button).pressed.emit()
	await _frames(6)
	return game.challenge_entry._hub_view

func _back_to_title_from_creator(entry: RBMCreatorEntry) -> void:
	entry._show_top()
	(entry.find_child("BackToRootButton", true, false) as Button).pressed.emit()
	await _frames(6)

# ---------------------------------------------------------------------------
# 静止画と点検

func _phase_shots() -> void:
	await _boot_game()
	var entry := await _open_creator()
	var choice: RBMCreatorTopChoice = entry._top_choice
	var new_card := choice.new_card
	var edit_card := choice.edit_card

	# ② ボス戦作成トップ: どちらも選んでいない／マウスで新しく作る／編集／隙間／外へ出る
	_motion(Vector2(640, 700))
	await _frames(10)
	_check(choice.selected == RBMCreatorTopChoice.NONE, "top: starts with no selection")
	_check((edit_card.find_child("SavedCountValue", true, false) as Label).is_visible_in_tree() and (edit_card.find_child("SavedCountValue", true, false) as Label).text == str(SAMPLES.size()), "top: the edit card shows the saved count")
	_check(new_card.size == edit_card.size, "top: even widths at rest")
	_audit(entry, "top_none")
	await _shot("2_top_none")
	await _move(_center(new_card), 0.3)
	await _hold(0.4)
	_check(new_card.is_hovered(), "top: real mouse hover reaches the new card")
	_check(choice.selected == 0 and is_equal_approx(new_card.size.x, RBMCreatorTopChoice.WIDE), "top: hovering new widens it to 720")
	_audit(entry, "top_new")
	await _shot("2_top_new")
	await _move(_center(edit_card), 0.3)
	await _hold(0.4)
	_check(choice.selected == 1 and is_equal_approx(edit_card.size.x, RBMCreatorTopChoice.WIDE), "top: hovering edit widens it to 720")
	_audit(entry, "top_edit")
	await _shot("2_top_edit")
	var gap := Vector2(new_card.get_global_rect().end.x + RBMCreatorTopChoice.GAP / 2.0, _center(edit_card).y)
	await _move(gap, 0.2)
	await _hold(0.3)
	_check(choice.selected == 1, "top: the gap keeps the selection")
	await _move(Vector2(640, 700), 0.3)
	await _hold(0.4)
	_check(choice.selected == RBMCreatorTopChoice.NONE, "top: leaving both cards returns to the even layout")

	# キーボード: 何も選ばれていない状態から Tab で操作対象が入るか、矢印で左右に移れるか
	await _key(KEY_TAB)
	var owner := tree.root.gui_get_focus_owner()
	_note("top: first Tab focuses %s" % (owner.name if owner != null else "<nothing>"))
	if owner != new_card:
		new_card.grab_focus()
		await _frames(2)
	await _hold(0.4)
	_check(new_card.has_focus() and choice.selected == 0, "top: keyboard focus selects the new card")
	await _shot("2_top_keyboard_new")
	await _key(KEY_RIGHT)
	await _hold(0.4)
	_check(edit_card.has_focus() and choice.selected == 1, "top: right arrow moves to the edit card and widens it")
	await _shot("2_top_keyboard_edit")
	await _key(KEY_UP)
	owner = tree.root.gui_get_focus_owner()
	_note("top: up arrow from the edit card focuses %s" % (owner.name if owner != null else "<nothing>"))
	new_card.grab_focus()
	await _frames(2)
	await _key(KEY_ENTER)
	await _frames(6)
	_check(entry._mode_choice_panel.visible, "top: Enter on the new card opens the mode choice")

	# ③ 作成方法の選択
	await _hold(0.2)
	_motion(Vector2(640, 700))
	await _frames(4)
	_audit(entry, "mode_choice")
	await _shot("3_mode_none")
	var simple: Button = _find(entry, "ChooseSimpleModeButton")
	var hardcore: Button = _find(entry, "ChooseAdvancedModeButton")
	await _move(_center(hardcore), 0.3)
	await _hold(0.3)
	_check(hardcore.is_hovered(), "mode: real mouse hover reaches HARDCORE")
	await _shot("3_mode_hover_hardcore")
	_motion(Vector2(640, 700))
	simple.grab_focus()
	await _hold(0.3)
	await _shot("3_mode_focus_simple")
	await _key(KEY_RIGHT)
	_check(hardcore.has_focus(), "mode: right arrow moves SIMPLE -> HARDCORE")
	(_find(entry, "ModeChoiceBackButton") as Button).grab_focus()
	await _key(KEY_ENTER)
	await _frames(4)
	_check(entry._top_panel.visible, "mode: back (Enter) returns to the top")

	# ④ 保存したボス戦の一覧
	await _click(_center(edit_card))
	await _frames(6)
	_check(entry._list_panel.visible, "list: clicking the edit card opens the list")
	_check(_shown(entry) == SAMPLES.size(), "list: all samples are listed")
	_motion(Vector2(640, 715))
	await _frames(4)
	_audit(entry, "list_none")
	await _shot("4_list_none")
	var second := entry._list_rows.get_child(1) as RBMSavedBossCard
	await _click(await _card_point(entry, second))
	_check(second.is_selected(), "list: clicking a card selects it")
	_check(entry._saved_detail.find_child("DetailEditButton", true, false) != null, "list: detail shows 編集する")
	_motion(Vector2(640, 715))
	await _frames(4)
	_audit(entry, "list_selected")
	await _shot("4_list_selected")
	var first := entry._list_rows.get_child(0) as RBMSavedBossCard
	await _click(await _card_point(entry, first))
	_motion(Vector2(640, 715))
	await _shot("4_list_selected_awakening")
	await _wheel(_center(entry.find_child("SavedListPanel", true, false)), true, 12)
	_check(entry._list_scroll.scroll_vertical > 0, "list: mouse wheel scrolls the list")
	_motion(Vector2(640, 715))
	await _shot("4_list_scrolled")
	var last := entry._list_rows.get_child(entry._list_rows.get_child_count() - 1) as RBMSavedBossCard
	await _click(await _card_point(entry, last))
	_motion(Vector2(640, 715))
	await _shot("4_list_selected_unnamed")
	# 検索（本物の文字入力）
	await _click(_center(entry._name_search_field))
	await _type("竜")
	await _frames(4)
	_check(_shown(entry) == 1, "list: typing a name filters the list")
	_motion(Vector2(640, 715))
	await _shot("4_list_search_name")
	await _type("zzz")
	await _frames(4)
	_check((entry.find_child("SavedListNoMatch", true, false) as Control).visible, "list: no-match message shows")
	_audit(entry, "list_nomatch")
	await _shot("4_list_nomatch")
	await _click(_center(entry.find_child("SavedListClearSearchButton", true, false)))
	_check(_shown(entry) == SAMPLES.size() and entry._name_search_field.text.is_empty(), "list: 検索をクリア restores the list")
	var target_id := (entry._list_rows.get_child(2) as RBMSavedBossCard).stage_id
	await _click(_center(entry._id_search_field))
	await _type(target_id, 1)
	await _frames(4)
	_check(_shown(entry) == 1 and (entry._list_rows.get_child(0) as RBMSavedBossCard).stage_id == target_id, "list: exact stage ID search")
	_motion(Vector2(640, 715))
	await _shot("4_list_search_id")
	await _type("", 1)
	entry._id_search_field.text = ""
	entry._refresh_list()
	await _frames(2)
	# 削除の確認（キャンセルのみ。実際の削除は動画と自動テストで確認）
	await _click(await _card_point(entry, entry._list_rows.get_child(3)))
	await _click(_center(entry._saved_detail.find_child("DetailDeleteButton", true, false)))
	_check(entry._delete_confirm_panel.visible, "list: 削除 opens the confirmation")
	_check((entry.find_child("DeleteCancelButton", true, false) as Button).has_focus(), "list: the dialog starts on キャンセル")
	_motion(Vector2(640, 715))
	_audit(entry._delete_confirm_panel, "delete_dialog")
	await _shot("4_list_delete_dialog")
	await _key(KEY_TAB)
	_check((entry.find_child("DeleteConfirmButton", true, false) as Button).has_focus(), "list: Tab moves within the dialog only")
	await _key(KEY_TAB)
	_check((entry.find_child("DeleteCancelButton", true, false) as Button).has_focus(), "list: Tab wraps back to キャンセル")
	await _key(KEY_ENTER)
	_check(not entry._delete_confirm_panel.visible and _shown(entry) == SAMPLES.size(), "list: Enter on キャンセル closes without deleting")
	# 開けないボス戦（ファイルが消えた）
	var gone := entry._list_rows.get_child(4) as RBMSavedBossCard
	await _click(await _card_point(entry, gone))
	var gone_path := RBMLocalStageRepository.stages_dir().path_join("%s.json" % gone.stage_id)
	var backup := FileAccess.get_file_as_string(gone_path)
	DirAccess.remove_absolute(gone_path)
	await _click(_center(entry._saved_detail.find_child("DetailEditButton", true, false)))
	_check(entry._list_panel.visible and entry._saved_detail.find_child("DetailError", true, false) != null, "list: a vanished file shows the open error and stays on the list")
	_motion(Vector2(640, 715))
	await _shot("4_list_open_error")
	var restore := FileAccess.open(gone_path, FileAccess.WRITE)
	restore.store_string(backup)
	restore.close()
	# 読み込めないファイル
	var broken := FileAccess.open(RBMLocalStageRepository.stages_dir().path_join("9999999999.json"), FileAccess.WRITE)
	broken.store_string("{ broken")
	broken.close()
	entry._show_list()
	await _frames(4)
	_check((entry.find_child("SavedUnreadableWarning", true, false) as Control).visible, "list: unreadable files are reported")
	_audit(entry, "list_unreadable")
	await _shot("4_list_unreadable")
	DirAccess.remove_absolute(RBMLocalStageRepository.stages_dir().path_join("9999999999.json"))
	# 「編集する」で本物の Creator が開く
	await _click(await _card_point(entry, entry._list_rows.get_child(0)))
	await _click(_center(entry._saved_detail.find_child("DetailEditButton", true, false)))
	await _frames(10)
	_check(entry.main.visible and entry.main.current_stage_id == (entry._list_rows.get_child(0) as RBMSavedBossCard).stage_id, "list: 編集する opens the real Creator on that stage")
	await _shot("4_list_edit_opened_creator")
	entry.main.press_exit_creator()
	await _frames(6)

	# 0件
	var empty_dir := out.path_join("empty_stages")
	_reset_dir(empty_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing(empty_dir)
	entry._show_top()
	_motion(Vector2(640, 715))
	await _frames(6)
	_audit(entry, "top_empty")
	await _shot("2_top_empty")
	choice.select(1, true)
	await _shot("2_top_empty_edit")
	choice.select(RBMCreatorTopChoice.NONE, true)
	entry._show_list()
	_audit(entry, "list_empty")
	await _shot("4_list_empty")
	RBMLocalStageRepository.set_stages_dir_for_testing(out.path_join("sample_stages"))

	# ① 挑戦ハブ
	await _back_to_title_from_creator(entry)
	var hub := await _open_hub()
	_motion(Vector2(640, 715))
	await _frames(6)
	_audit(hub, "hub")
	await _shot("1_hub_none")
	var hub_simple: Button = _find(hub, "SimpleCategoryButton")
	await _move(_center(hub_simple), 0.3)
	await _hold(0.2)
	_check(hub_simple.is_hovered(), "hub: real mouse hover reaches SIMPLE")
	await _shot("1_hub_hover_simple")
	await _move(_center(_find(hub, "PopularCategoryButton")), 0.3)
	await _hold(0.2)
	await _shot("1_hub_hover_tile")
	_motion(Vector2(640, 715))
	await _key(KEY_TAB)
	owner = tree.root.gui_get_focus_owner()
	_note("hub: first Tab focuses %s" % (owner.name if owner != null else "<nothing>"))
	_find(hub, "NewCategoryButton").grab_focus()
	await _hold(0.2)
	await _shot("1_hub_focus_tile")
	await _key(KEY_UP)
	owner = tree.root.gui_get_focus_owner()
	_note("hub: up from 新着 focuses %s" % (owner.name if owner != null else "<nothing>"))

	# ほかのウィンドウの大きさ（論理 1280×720 を保ったまま、表示の大きさだけ変える）
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		for size in [Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1024, 768)]:
			tree.root.size = size
			await _frames(10)
			await _shot("1_hub_resized")
			_check(_find(hub, "BackToRootButton").get_global_rect().position.x > 1.0, "hub: back stays inside at %s" % size)
		var hub_back: Button = _find(hub, "BackToRootButton")
		hub_back.pressed.emit()
		await _frames(4)
		entry = await _open_creator()
		for size in [Vector2i(1366, 768), Vector2i(1024, 768)]:
			tree.root.size = size
			await _frames(10)
			await _shot("2_top_resized")
			entry._show_list()
			await _click(await _card_point(entry, entry._list_rows.get_child(1)))
			_motion(Vector2(640, 715))
			await _shot("4_list_resized")
			entry._show_top()
		tree.root.size = Vector2i(1280, 720)
		await _frames(6)

# ---------------------------------------------------------------------------
# 動画（--write-movie と --fixed-fps 30 で録る）

func _phase_video_creator() -> void:
	await _boot_game()
	var entry := await _open_creator()
	_cursor_setup()
	_motion(Vector2(640, 700))
	await _hold(1.2)
	var choice := entry._top_choice
	await _move(_center(choice.new_card) + Vector2(-60, 0), 0.6)
	await _hold(1.4)
	await _move(_center(choice.edit_card), 0.7)
	await _hold(1.4)
	await _move(Vector2(choice.new_card.get_global_rect().end.x + 12, 420), 0.4)
	await _hold(0.8)
	await _move(Vector2(640, 700), 0.5)
	await _hold(1.0)
	# キーボードでも同じように選べる
	choice.new_card.grab_focus()
	await _hold(1.0)
	await _key(KEY_RIGHT)
	await _hold(1.0)
	await _key(KEY_LEFT)
	await _hold(0.8)
	choice.new_card.release_focus()
	await _move(_center(choice.new_card), 0.6)
	await _hold(0.5)
	await _click()
	await _hold(1.0)
	var simple: Button = entry.find_child("ChooseSimpleModeButton", true, false)
	var hardcore: Button = entry.find_child("ChooseAdvancedModeButton", true, false)
	await _move(_center(simple), 0.6)
	await _hold(1.0)
	await _move(_center(hardcore), 0.6)
	await _hold(1.0)
	await _move(_center(entry.find_child("ModeChoiceBackButton", true, false)), 0.7)
	await _hold(0.4)
	await _click()
	await _hold(0.8)
	await _move(_center(choice.edit_card), 0.7)
	await _hold(0.8)
	await _click()
	await _hold(1.2)

func _phase_video_list() -> void:
	await _boot_game()
	var entry := await _open_creator()
	_cursor_setup()
	_motion(Vector2(640, 700))
	await _hold(0.8)
	await _move(_center(entry._top_choice.edit_card), 0.7)
	await _hold(0.6)
	await _click()
	await _hold(1.2)
	# 一覧 → カードを選ぶ → 別のカード → スクロール
	await _move(await _card_point(entry, entry._list_rows.get_child(0)), 0.6)
	await _click()
	await _hold(1.4)
	await _move(await _card_point(entry, entry._list_rows.get_child(3)), 0.6)
	await _click()
	await _hold(1.4)
	await _wheel(_center(entry.find_child("SavedListPanel", true, false)), true, 10)
	await _hold(0.8)
	await _wheel(_center(entry.find_child("SavedListPanel", true, false)), false, 10)
	await _hold(0.4)
	# 名前で検索 → 一致なし → 検索をクリア
	await _move(_center(entry._name_search_field), 0.7)
	await _click()
	await _type("竜", 8)
	await _hold(1.2)
	await _type("x", 8)
	await _hold(1.4)
	await _move(_center(entry.find_child("SavedListClearSearchButton", true, false)), 0.7)
	await _click()
	await _hold(1.0)
	# ステージIDで検索 → 選ぶ → 「削除」→ キャンセル → 「削除」→ 削除する（一時フォルダの見本だけ）
	var target := entry._list_rows.get_child(entry._list_rows.get_child_count() - 2) as RBMSavedBossCard
	var target_id := target.stage_id
	await _move(_center(entry._id_search_field), 0.7)
	await _click()
	await _type(target_id, 3)
	await _hold(1.0)
	await _move(await _card_point(entry, entry._list_rows.get_child(0)), 0.6)
	await _click()
	await _hold(1.2)
	await _move(_center(entry._saved_detail.find_child("DetailDeleteButton", true, false)), 0.8)
	await _click()
	await _hold(1.4)
	await _move(_center(entry.find_child("DeleteCancelButton", true, false)), 0.6)
	await _click()
	await _hold(0.8)
	_check(RBMLocalStageRepository.exists(target_id), "video: cancel keeps the stage")
	await _move(_center(entry._saved_detail.find_child("DetailDeleteButton", true, false)), 0.6)
	await _click()
	await _hold(1.0)
	await _move(_center(entry.find_child("DeleteConfirmButton", true, false)), 0.6)
	await _hold(0.4)
	await _click()
	await _hold(1.2)
	_check(not RBMLocalStageRepository.exists(target_id), "video: 削除する deleted the sample stage (temporary folder only)")
	await _move(entry._id_search_field.get_global_rect().end - Vector2(16, 20), 0.6)
	entry._id_search_field.text = ""
	entry._refresh_list()
	await _hold(1.0)
	# 編集する → 本物の Creator が開く
	await _move(await _card_point(entry, entry._list_rows.get_child(0)), 0.6)
	await _click()
	await _hold(1.0)
	await _move(_center(entry._saved_detail.find_child("DetailEditButton", true, false)), 0.7)
	await _hold(0.3)
	await _click()
	await _hold(2.0)
	_check(entry.main.visible, "video: 編集する opened the Creator")

func _phase_video_hub() -> void:
	await _boot_game()
	var hub := await _open_hub()
	_cursor_setup()
	_motion(Vector2(640, 700))
	await _hold(1.0)
	for key in ["SimpleCategoryButton", "HardcoreCategoryButton", "FeaturedCategoryButton", "NewCategoryButton", "UnchallengedCategoryButton", "PopularCategoryButton", "HighDifficultyCategoryButton", "SearchBossButton", "RandomChallengeButton"]:
		await _move(_center(hub.find_child(key, true, false)), 0.45)
		await _hold(0.5)
	await _move(Vector2(640, 700), 0.5)
	(hub.find_child("SimpleCategoryButton", true, false) as Button).grab_focus()
	await _hold(0.6)
	for k in [KEY_RIGHT, KEY_DOWN, KEY_RIGHT, KEY_RIGHT, KEY_DOWN]:
		await _key(k)
		await _hold(0.5)

# ---------------------------------------------------------------------------
# 処理時間（録画なしの実時間で測る。測っている間は画面の読み出し・保存・print をしない）

func _frame_stats(seconds: float) -> Dictionary:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	var end := last + int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() < end:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.remove_at(0)
	var total := 0.0
	var worst := 0.0
	var over20 := 0
	var over33 := 0
	for t in times:
		total += t
		worst = maxf(worst, t)
		if t > 20.0:
			over20 += 1
		if t > 33.0:
			over33 += 1
	return {"frames": times.size(), "avg_ms": snappedf(total / maxf(1, times.size()), 0.01), "fps": snappedf(1000.0 / maxf(0.001, total / maxf(1, times.size())), 0.1), "worst_ms": snappedf(worst, 0.01), "over_20ms": over20, "over_33ms": over33, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}

func _phase_perf() -> void:
	# 保存件数が多い時の一覧の作り直しも測る（見本を60件まで増やす）
	var many: Array = []
	for i in range(60):
		var row: Array = (SAMPLES[i % (SAMPLES.size() - 1)] as Array).duplicate()
		row[0] = "%s %02d" % [row[0], i]
		row[8] = 1000 + i * 3600
		many.append(row)
	var stages := out.path_join("sample_stages_60")
	_reset_dir(stages)
	_save_samples(stages, many)
	await _boot_game()
	var entry := await _open_creator()
	var m: Dictionary = evidence.metrics
	for run in range(2):
		var t0 := Time.get_ticks_usec()
		entry._show_list()
		var t1 := Time.get_ticks_usec()
		entry._show_top()
		var t2 := Time.get_ticks_usec()
		m["show_list_60_ms_run%d" % run] = (t1 - t0) / 1000.0
		m["show_top_counts_60_ms_run%d" % run] = (t2 - t1) / 1000.0
		await _frames(5)
	_motion(Vector2(640, 700))
	m["top_idle"] = await _frame_stats(3.0)
	# 選ぶカードを0.4秒ごとに切り替え続けている間（切り替えは別の流れで進め、こちらは測るだけ）
	_drive_switching(entry._top_choice, 3.0)
	m["top_switching"] = await _frame_stats(3.0)
	entry._show_mode_choice()
	m["mode_choice_idle"] = await _frame_stats(2.0)
	entry._show_list()
	await _frames(3)
	var t3 := Time.get_ticks_usec()
	(entry._list_rows.get_child(1) as RBMSavedBossCard).pressed.emit()
	m["select_card_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	t3 = Time.get_ticks_usec()
	(entry._list_rows.get_child(2) as RBMSavedBossCard).pressed.emit()
	m["select_another_card_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	# 内訳: 保存データの一覧の読み込みだけ・一覧の行の用意・検索の1文字分
	t3 = Time.get_ticks_usec()
	RBMLocalStageRepository.list()
	m["repository_list_60_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	t3 = Time.get_ticks_usec()
	entry._saved_entries()
	m["saved_entries_60_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	t3 = Time.get_ticks_usec()
	entry._name_search_field.text = "竜"
	entry._name_search_field.text_changed.emit("竜")
	m["search_keystroke_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	t3 = Time.get_ticks_usec()
	entry._name_search_field.text = ""
	entry._name_search_field.text_changed.emit("")
	m["search_clear_keystroke_60_rows_ms"] = (Time.get_ticks_usec() - t3) / 1000.0
	await _frames(3)
	m["list_idle"] = await _frame_stats(2.0)
	_drive_scrolling(entry.find_child("SavedListPanel", true, false), 2.0)
	m["list_scrolling"] = await _frame_stats(2.0)
	# 比較: 入力を流さず、スクロール位置を毎フレーム直接動かす（入力の流し込みによる計測の揺れかを見分ける）
	_drive_scroll_direct(entry._list_scroll, 2.0)
	m["list_scrolling_direct"] = await _frame_stats(2.0)
	await _back_to_title_from_creator(entry)
	var t4 := Time.get_ticks_usec()
	var hub := await _open_hub()
	m["open_hub_ms_including_6_frames"] = (Time.get_ticks_usec() - t4) / 1000.0
	m["hub_idle"] = await _frame_stats(2.0)
	_check(hub.visible, "perf: hub opened")
	print("PERF ", JSON.stringify(m))

func _drive_switching(choice: RBMCreatorTopChoice, seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	var flip := 0
	while Time.get_ticks_usec() < end:
		_motion(_center(choice.new_card if flip % 2 == 0 else choice.edit_card))
		flip += 1
		await _frames(12)

func _drive_scrolling(panel: Control, seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	var i := 0
	while Time.get_ticks_usec() < end:
		await _wheel(_center(panel), (i / 10) % 2 == 0, 1)
		i += 1

## 一覧のカードを（必要なら一覧をスクロールして）見える位置へ出し、その中心を返す。
func _card_point(entry: RBMCreatorEntry, card: Node) -> Vector2:
	entry._list_scroll.ensure_control_visible(card as Control)
	await _frames(3)
	return _center(card as Control)

## 一覧に表示中の行の数（検索で隠れたカードは数えない）。
func _shown(entry: RBMCreatorEntry) -> int:
	var n := 0
	for child in entry._list_rows.get_children():
		if (child as Control).visible:
			n += 1
	return n

func _drive_scroll_direct(scroll: ScrollContainer, seconds: float) -> void:
	var end := Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	var step := 24
	while Time.get_ticks_usec() < end:
		scroll.scroll_vertical += step
		if scroll.scroll_vertical <= 0 or scroll.scroll_vertical >= int(scroll.get_v_scroll_bar().max_value - scroll.size.y) - 1:
			step = -step
		await tree.process_frame
