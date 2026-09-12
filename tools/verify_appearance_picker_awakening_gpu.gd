extends SceneTree

## GPU/Visual検証: STEP1「ボス外見一覧」画面の全体レイアウト再設計
## (画面全体を使う・ボス画像のさらなる大型化・カードクリック即決定・
## 「決定」ボタン廃止)と、既存の「覚醒可能」表示・覚醒後プレビュー切替の
## 回帰確認。
##
## RBMCreatorAppearanceCatalog.ENTRIESはGodotのconstとして実行時読み取り
## 専用のため、既存6体を覚醒対応へ書き換えることはできない(かつ、実際の
## ボスを勝手に覚醒対応へ設定することは今回の確定仕様として禁止されている)。
## そのため:
##   ・「画面全体を使ったレイアウト/大型化されたボス画像/3列×2行/
##     ドット絵品質/カードクリック即決定/戻るの挙動」は実際の6体そのままで
##     検証する。
##   ・「覚醒対応カード/バッジ・トグルの重なり有無/通常・覚醒後プレビュー
##     切替」は、実在の6 idとは衝突しないfixture id
##     ("appearance_awakening_demo")をpicker._build_card()へ直接渡して
##     検証する——正規のcatalogには一切触れない。

var report := {"errors": [], "screenshots": []}

func _fail(message: String) -> void:
	if not report["errors"].has(message):
		report["errors"].append(message)
	push_error(message)

func _find(node: Node, name: String) -> Node:
	return node.find_child(name, true, false)

var output_dir := "res://../gpu-appearance-picker"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--output" and i + 1 < args.size():
			output_dir = args[i + 1]
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if DisplayServer.get_name() == "headless":
		push_error("GPU preview requires a windowed display; --headless is not valid.")
		quit(2)
		return

	var picker := RBMCreatorAppearancePicker.new()
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(picker)
	for i in range(4): await process_frame

	# --- 検証1: 実データ(6体全て覚醒非対応) — 画面全体を使った大型化・
	# Pixel Art・3x2レイアウト・画面外はみ出し無し ---
	var grid: GridContainer = _find(picker, "AppearanceGrid")
	if grid == null or grid.columns != 3 or grid.get_child_count() != 6:
		_fail("grid must stay 3 columns x 6 cards")
	if _find(picker, "DecideButton") != null:
		_fail("DecideButton must no longer exist -- selection now confirms immediately on card click")
	var grid_rect := (grid as Control).get_global_rect()
	# 「画面左上に小さく固まっている」旧バグの再発防止——グリッド全体が
	# 画面のかなりの面積を使っていること、かつ画面外へはみ出していないこと。
	if grid_rect.size.x < 800.0 or grid_rect.size.y < 400.0:
		_fail("grid must visibly use most of the 1280x720 screen, not stay tiny in a corner (got %s)" % grid_rect.size)
	var screen_rect := Rect2(Vector2.ZERO, Vector2(1280, 720))
	if not screen_rect.encloses(grid_rect):
		_fail("grid must not overflow the visible 1280x720 screen (got %s)" % grid_rect)
	for entry in RBMCreatorAppearanceCatalog.all():
		var id := str(entry["id"])
		var card: Control = _find(picker, "Appearance_%s" % id)
		if card == null or card.custom_minimum_size.x < 300.0 or card.custom_minimum_size.y < 200.0:
			_fail("%s card must be notably larger than the previous iteration" % id)
		var area: Control = _find(picker, "AppearancePreviewArea_%s" % id)
		if area == null or area.custom_minimum_size.x <= 48.0:
			_fail("%s preview area must be larger than the old 48px icon" % id)
		if _find(picker, "AwakeningCapableBadge_%s" % id) != null:
			_fail("%s must not show the badge -- no real appearance is awakening-capable yet" % id)
		if not screen_rect.encloses((card as Control).get_global_rect()):
			_fail("%s card must not overflow the visible screen" % id)
	await process_frame
	await RenderingServer.frame_post_draw
	var shot1 := root.get_texture().get_image()
	if shot1 == null: _fail("null capture: real_picker_grid")
	else:
		shot1.save_png(output_dir + "/01_real_picker_grid_fullscreen_layout.png")
		report["screenshots"].append("01_real_picker_grid_fullscreen_layout.png")

	# --- 検証2: カードクリック即決定・「戻る」は選択を変えない ---
	var confirmed_ids: Array = []
	var cancelled_marks: Array = []
	picker.confirmed.connect(func(id): confirmed_ids.append(id))
	picker.cancelled.connect(func(): cancelled_marks.append(true))
	picker.open("appearance_slime")
	(_find(picker, "Appearance_appearance_knight") as Button).pressed.emit()
	if confirmed_ids != ["appearance_knight"]:
		_fail("clicking a card must immediately confirm that exact boss id (got %s)" % [confirmed_ids])
	confirmed_ids.clear()
	picker.open("appearance_dragon")
	(_find(picker, "BackButton") as Button).pressed.emit()
	if cancelled_marks.size() != 1:
		_fail("back button must emit cancelled exactly once")
	if not confirmed_ids.is_empty():
		_fail("back button must never emit confirmed")
	if picker._selected_id != "appearance_dragon":
		_fail("back button must not change the currently selected boss")

	# --- 検証3: fixtureカード(覚醒対応) — バッジ + トグルボタンの構造・
	# 画像/名前/バッジ/ボタンいずれとも重ならないこと ---
	picker._build_card(grid, {"id": "appearance_awakening_demo", "name": "覚醒対応デモ", "supports_awakening": true})
	# fixtureは7枚目としてグリッドの3行目(1列目)へ折り返されるため、
	# 実際の1280x720のままだと画面下端で見切れる——スクリーンショットで
	# 目視確認できるよう、この検証専用に縦を一時的に拡張する(実機の1280x720
	# レイアウト自体の判定は検証1で既に完了済みのため、ここで広げても
	# 検証結果に影響しない)。
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	await process_frame
	var demo_area: Control = _find(picker, "AppearancePreviewArea_appearance_awakening_demo")
	var badge: Label = _find(picker, "AwakeningCapableBadge_appearance_awakening_demo")
	var toggle: Button = _find(picker, "AwakenedPreviewToggle_appearance_awakening_demo")
	var demo_name: Label = _find(picker, "AppearanceName_appearance_awakening_demo")
	if badge == null: _fail("fixture card must show the 覚醒可能 badge")
	if toggle == null: _fail("fixture card must show the preview toggle button")
	elif not toggle.disabled: _fail("fixture card has no real awakened asset, so its toggle must be disabled")
	if badge != null and toggle != null:
		var badge_rect: Rect2 = badge.get_global_rect()
		var toggle_rect: Rect2 = toggle.get_global_rect()
		var area_rect: Rect2 = demo_area.get_global_rect()
		var name_rect: Rect2 = demo_name.get_global_rect()
		if badge_rect.intersects(toggle_rect):
			_fail("覚醒可能 badge and the preview toggle button must not overlap")
		if badge_rect.intersects(area_rect) or toggle_rect.intersects(area_rect):
			_fail("覚醒可能 badge / toggle button must not overlap the boss image")
		if badge_rect.intersects(name_rect) or toggle_rect.intersects(name_rect):
			_fail("覚醒可能 badge / toggle button must not overlap the boss name label")
	await process_frame
	await RenderingServer.frame_post_draw
	var shot2 := root.get_texture().get_image()
	if shot2 == null: _fail("null capture: fixture_card_badge_and_toggle")
	else:
		shot2.save_png(output_dir + "/02_fixture_card_badge_and_disabled_toggle.png")
		report["screenshots"].append("02_fixture_card_badge_and_disabled_toggle.png")

	# --- 検証4: 通常/覚醒後プレビューのラベル切替・トグルは選択確定にも
	# 画面遷移にも一切影響しない ---
	if is_instance_valid(toggle):
		if toggle.text != tr("覚醒後を見る"): _fail("initial toggle label must be 覚醒後を見る")
		confirmed_ids.clear()
		cancelled_marks.clear()
		toggle.pressed.emit()
		await process_frame
		await RenderingServer.frame_post_draw
		var shot3 := root.get_texture().get_image()
		if shot3 == null: _fail("null capture: toggled_to_awakened_preview")
		else:
			shot3.save_png(output_dir + "/03_toggled_to_awakened_preview_label.png")
			report["screenshots"].append("03_toggled_to_awakened_preview_label.png")
		if toggle.text != tr("通常時を見る"): _fail("after toggling, label must become 通常時を見る")
		if not confirmed_ids.is_empty(): _fail("pressing the preview toggle must never emit confirmed")
		if not cancelled_marks.is_empty(): _fail("pressing the preview toggle must never emit cancelled / leave the screen")
		toggle.pressed.emit()
		if toggle.text != tr("覚醒後を見る"): _fail("toggling again must return to 覚醒後を見る")

		# トグルで覚醒後画像を表示した状態のまま、カード本体(名前ラベルの
		# 親と同じcard Button)を押しても、確定されるのはあくまで元のboss id
		# であることを直接確認する。
		toggle.pressed.emit()
		var demo_card: Button = _find(picker, "Appearance_appearance_awakening_demo")
		confirmed_ids.clear()
		demo_card.pressed.emit()
		if confirmed_ids != ["appearance_awakening_demo"]:
			_fail("clicking the card body while showing the awakened preview must still confirm the plain boss id")

	# --- 検証5: 画面を開き直すと通常プレビューへ戻ることの確認 ---
	picker.open("appearance_dragon")
	if is_instance_valid(toggle) and toggle.text != tr("覚醒後を見る"):
		_fail("reopening the screen must reset the preview back to normal")

	report["case_count"] = 1
	report["passed"] = report["errors"].is_empty()
	var f := FileAccess.open(output_dir + "/appearance-picker-report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	print("APPEARANCE_PICKER_GPU_DONE passed=", report["passed"])
	quit(0 if report["passed"] else 1)
