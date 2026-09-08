extends GutTest

## RPG BOSS MAKER Phase 1 Step 8 最終最小修正 §2 — レイアウト回帰テスト。
##
## ピクセル完全一致やスクリーンショットとの比較は行わない——「実際のControl
## のサイズがほぼ0になり内容が事実上見えない」「STEP内容とナビゲーション
## 領域が致命的に重なる」「RBMGameRoot自身のサイズがviewportからズレて
## すべてのUIが実際のウィンドウ外へはみ出す」というクラスの回帰を確実に
## 検出することが目的。RBMGameRootを実際にインスタンス化し、Godot自身の
## レイアウト計算（Container/NOTIFICATION_SORT_CHILDREN等、実UIノード経由）
## を経て得た本物のControl.size/position/global_positionだけを検証する。
##
## Step 8 最終最小修正 §2の指摘: 従来のテストは「size > 0」「ある値より大きい」
## という緩い下限判定のみだったため、RBMGameRoot.sizeが2560x1440（1280x720
## の倍化バグ）になっていてもPASSしてしまっていた——今回は①RBMGameRoot.size
## 自体をviewportサイズと厳密一致で検証②各Controlの実rectがviewport範囲内に
## 収まっていることを明示的に検証、の2点を追加し、旧バグ（サイズ倍化）が
## 戻っても確実にFAILするようにした。
##
## headless GUT実行環境固有の制約: `--headless -s res://addons/gut/gut_cmdln.gd`
## で動くこのテストランナーの実ウィンドウは、project.godot自身のwindow/size
## 設定（1280x720）を継承しない（実測ではGUT側の既定サイズ、64x64程度）。
## RBMGameRoot._ready()自身は自身のposition/sizeをget_viewport_rect().size
## （window/stretch/mode="canvas_items"適用後の論理デザイン解像度）へ同期
## するが、この値自体がGUTのテスト実行環境では1280x720にならない（project.
## godotのwindow/size設定に基づく実際の製品起動を経ないため）——そのため
## ここではRBMGameRootインスタンス生成前にこのテストハーネス自身のウィンドウ
## サイズを1280x720へ明示的に合わせておき、RBMGameRoot._ready()自身の同期
## ロジック（本物の生産コード）がノード生成の時点で正しい値を拾えるように
## する。これはRBMGameRoot自身の生産コードの回避策ではなく、GUTのテスト
## 実行環境がproject.godotの実際のウィンドウサイズを再現しないことに対する、
## このテストファイル内で完結する対応。
const TEST_DIR := "user://bossmaker_test_step8_layout/stages"
const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)

## §1: 720px高のウィンドウでSTEP/確認画面のコンテンツ領域が実際に大きな
## 面積を確保できているかの汎用フロア。今回のバグでは、ここがほぼ0になって
## いた（bareなControlが親のサイズを継承せず、EXPAND_FILL/ScrollContainerが
## 伝播先の実サイズを持てなかったため）。
const MIN_LARGE_AREA_HEIGHT := 200.0

## Control.global_position/sizeの浮動小数点誤差を吸収するための許容誤差。
const EPSILON := 0.5

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

## CHALLENGE UI再設計: 一覧カード(RBMChallengeUiKit.build_boss_card())は
## Buttonではなくgui_input経由でクリックを検知するPanelContainerのため、
## _btn()では模擬できない——test_rbm_phase35_step4_battle_ui.gdが既に
## 確立している「合成InputEventMouseButtonをgui_inputへ直接emitする」
## 手法をそのまま踏襲する。
func _click_card(card: Control) -> void:
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	card.gui_input.emit(fake_click)

## §2「主要な入力欄のrectがviewport内」: 左上・右下の両方がviewport矩形の
## 範囲内に収まっていることを確認する（単なる非0サイズより厳密）。
func _assert_within_viewport(node: Control, viewport: Rect2, description: String) -> void:
	var top_left := node.global_position
	var bottom_right := node.global_position + node.size
	assert_true(top_left.x >= viewport.position.x - EPSILON, "%s: left edge (%s) must be within the viewport (>= %s)" % [description, top_left.x, viewport.position.x])
	assert_true(top_left.y >= viewport.position.y - EPSILON, "%s: top edge (%s) must be within the viewport (>= %s)" % [description, top_left.y, viewport.position.y])
	assert_true(bottom_right.x <= viewport.position.x + viewport.size.x + EPSILON, "%s: right edge (%s) must be within the viewport (<= %s)" % [description, bottom_right.x, viewport.position.x + viewport.size.x])
	assert_true(bottom_right.y <= viewport.position.y + viewport.size.y + EPSILON, "%s: bottom edge (%s) must be within the viewport (<= %s)" % [description, bottom_right.y, viewport.position.y + viewport.size.y])

## RBMGameRootを実際にインスタンス化する前に、このheadlessテストハーネス
## 自身のウィンドウをget_viewport_rect()経由で1280x720として見えるように
## しておく（ファイル冒頭コメント参照）。
func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

## 実際のCREATE実Buttonフロー経由でRBMCreatorMainへ到達する——STEP各画面が
## RBMGameRoot→RBMCreatorEntry→RBMCreatorMainという実アンカーチェーンの
## 末端に実際に存在する状態を再現する（直接main.gd等を単独インスタンス化
## するのではなく、Step 8で結合した実ノードツリーをそのまま使う）。
## UI改善②: 「新しいボス戦を作る」は今やCreatorへ直接入らず、SIMPLE/
## ADVANCEDの作成方法選択パネルをまず経由する——このヘルパーはレイアウト
## 回帰テストの土台のため、実際にどちらのモードで作るかは重要ではない
## （シンプルを選ぶ、既存のNewBossButtonクリックの直後にもう1クリック
## 追加するだけ）。
func _new_creator_main() -> RBMCreatorMain:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return root.creator_entry.main

# ---------------------------------------------------------------------------
# Rootサイズ (Step 8 最終最小修正 §1/§2)
# ---------------------------------------------------------------------------

## §2「Rootサイズ」: RBMGameRoot.size==viewport size、かつこのheadless
## テスト環境では厳密にsize.x==1280/size.y==720であることを検証する——
## 「> 200」のような下限判定ではなく厳密一致にすることで、旧倍化バグ
## （2560x1440）を確実に検出する。
func test_game_root_size_matches_viewport_exactly() -> void:
	var root := await _make_root()
	assert_eq(root.size, root.get_viewport_rect().size, "RBMGameRoot.size must exactly equal get_viewport_rect().size (not merely be non-zero)")
	assert_eq(root.size.x, HEADLESS_WINDOW_SIZE.x, "RBMGameRoot.size.x must be exactly 1280, not e.g. 2560 (the old doubling bug)")
	assert_eq(root.size.y, HEADLESS_WINDOW_SIZE.y, "RBMGameRoot.size.y must be exactly 720, not e.g. 1440 (the old doubling bug)")
	assert_eq(root.creator_entry.size, root.size, "creator_entry must receive the exact same size via its own FULL_RECT anchor to root")
	assert_eq(root.challenge_entry.size, root.size, "challenge_entry must receive the exact same size via its own FULL_RECT anchor to root")

## 背景アート実装（2026-09-04）: TOP画面を実背景画像＋Godot UI（Label/
## Button）へ作り直した後の回帰テスト。背景は実際のゲーム背景として
## 使用し、デザインリファレンス画像は絵として貼り付けていないこと
## （タイトル・説明・ボタン文言がLabel/Buttonのtextとして実在すること）、
## 2つのメインボタンが扉を覆わず下側〜床付近に左右対称で並ぶこと、戻る
## ボタンが明確に小さい階層であること、Hover/フォーカス/押下フィード
## バックが仕様どおりであることを検証する。
func test_creator_entry_top_screen_uses_real_background_and_matches_reference_layout() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame

	var viewport := root.get_viewport_rect()
	var background: TextureRect = root.creator_entry.find_child("EntryBackground", true, false)
	var title: Label = root.creator_entry.find_child("EntryTitleLabel", true, false)
	var underline: Control = root.creator_entry.find_child("EntryTitleUnderline", true, false)
	var description: Label = root.creator_entry.find_child("EntryDescriptionLabel", true, false)
	var button_row: HBoxContainer = root.creator_entry.find_child("EntryMainButtonRow", true, false)
	var new_button := _btn(root.creator_entry, "NewBossButton")
	var edit_button := _btn(root.creator_entry, "EditSavedBossButton")
	var back_button := _btn(root.creator_entry, "BackToRootButton")
	var new_surface: RBMCreatorEntry.MethodChoiceSurface = new_button.find_child("MainButtonSurface", true, false)
	var new_label: Label = new_button.find_child("MainButtonLabel", true, false)
	var edit_label: Label = edit_button.find_child("MainButtonLabel", true, false)

	assert_true(background.visible, "the real door background must be visible on the CREATE top screen")
	assert_not_null(background.texture, "the background must load an actual image asset, not a placeholder")
	assert_eq(title.text, "ボス戦を作成")
	assert_eq(description.text, "新しいボス戦を作るか、保存したボス戦を編集してください。")
	assert_eq(title.get_theme_color("font_color"), RBMCreatorEntry.ENTRY_COLOR_TITLE)
	assert_eq(description.get_theme_color("font_color"), RBMCreatorEntry.ENTRY_COLOR_DESCRIPTION)
	assert_not_null(underline, "title must keep its thin gold rule/diamond ornament")
	assert_eq(new_label.text, "新しいボス戦を作る")
	assert_eq(edit_label.text, "保存したボス戦を編集")
	assert_eq(back_button.text, "戻る")
	assert_not_null(back_button.icon, "戻る矢印は共通ピクセルアイコンで表示")

	# タイトル→(区切り線)→説明→(扉)→2つの選択肢、という視線の流れ。
	assert_true(title.global_position.y + title.size.y <= underline.global_position.y + EPSILON, "title must precede its underline")
	assert_true(underline.global_position.y + underline.size.y <= description.global_position.y + EPSILON, "underline must precede the description")
	assert_true(description.global_position.y + description.size.y < new_button.global_position.y, "description must sit above the main buttons")
	assert_true(new_button.global_position.y + new_button.size.y < back_button.global_position.y, "back must be a subordinate action below the main buttons")

	# 2つのメインボタンは同じ行を共有し、左右対称（同サイズ・同高さ）で
	# 重ならない。
	assert_eq(new_button.get_parent(), button_row, "main buttons must share one horizontal row")
	assert_eq(edit_button.get_parent(), button_row, "main buttons must share one horizontal row")
	assert_eq(new_button.size, RBMCreatorEntry.ENTRY_MAIN_BUTTON_SIZE)
	assert_eq(edit_button.size, RBMCreatorEntry.ENTRY_MAIN_BUTTON_SIZE)
	assert_almost_eq(new_button.global_position.y, edit_button.global_position.y, EPSILON, "main buttons must share the same vertical position")
	assert_lt(new_button.global_position.x, edit_button.global_position.x, "new-boss button must sit on the left")
	assert_false(new_button.get_global_rect().intersects(edit_button.get_global_rect()), "main buttons must not overlap")
	# 完成イメージどおり中央の扉を完全に覆わない——ボタン行は画面の下半分
	# （扉の下側〜床付近）に収まっていること。
	assert_gt(new_button.global_position.y, viewport.size.y * 0.5, "main buttons must sit in the lower half of the screen, below the door")

	# 戻るボタンはメインボタンより明確に小さい階層。
	assert_lt(back_button.size.x, RBMCreatorEntry.ENTRY_MAIN_BUTTON_SIZE.x, "back button must be clearly smaller than the main buttons")
	assert_lt(back_button.size.y, RBMCreatorEntry.ENTRY_MAIN_BUTTON_SIZE.y, "back button must be clearly smaller than the main buttons")

	_assert_within_viewport(title, viewport, "CREATE entry title")
	_assert_within_viewport(description, viewport, "CREATE entry description")
	_assert_within_viewport(new_button, viewport, "CREATE new-boss button")
	_assert_within_viewport(edit_button, viewport, "CREATE edit-saved button")
	_assert_within_viewport(back_button, viewport, "CREATE back button")
	for label in [title, description, new_label, edit_label]:
		assert_true(label.get_minimum_size().x <= label.size.x + EPSILON, "%s text must not be clipped horizontally" % label.name)

	# Hover: 金枠・紺の地・文字がそれぞれ明るくなり、120ms（既存の
	# MethodChoiceSurface補間）で落ち着く。ネオン発光や拡大は行わない
	# ——mouse_entered.emit()はheadless環境では実カーソル位置を動かさない
	# ためButton.is_hovered()が真にならず、refreshラムダが正しく反応しない
	# （実マウス入力を必要とする）。実際に画面へマウスが乗った時と同じ
	# set_state()呼び出しを直接検証することで、この補間・配色ロジック
	# そのものを確認する。
	assert_eq(new_surface.amount, 0.0)
	assert_false(new_surface.pressed)
	new_surface.set_state(true, false)
	new_surface._process(0.2)
	assert_eq(new_surface.amount, 1.0, "hover surface must finish its ~120ms interpolation")
	assert_eq(new_label.get_theme_color("font_color"), RBMCreatorEntry.METHOD_IVORY_LIGHT, "hover must brighten the label text")
	new_surface.set_state(false, false)
	new_surface._process(0.2)
	assert_eq(new_surface.amount, 0.0)
	assert_eq(new_label.get_theme_color("font_color"), RBMCreatorEntry.METHOD_IVORY, "leaving hover must restore the resting label color")

	new_button.grab_focus()
	await get_tree().process_frame
	assert_true(new_button.has_focus(), "main button must accept keyboard/gamepad focus")
	new_surface._process(0.2)
	assert_eq(new_surface.amount, 1.0, "focus must emphasize the button like hover")
	new_button.release_focus()
	new_surface.set_state(false, false)

	# 押下: 背景が暗くなるフィードバック（MethodChoiceSurface.pressed →
	# METHOD_INK_PRESSED地）。
	new_button.button_down.emit()
	assert_true(new_surface.pressed, "pressed main button must switch to its dark pressed treatment")
	new_button.button_up.emit()
	assert_false(new_surface.pressed)

# ---------------------------------------------------------------------------
# Creator STEP1〜5 (STEP6=最終確認は内部構造が異なるため別テストで確認する
# ——Creator UI再設計で旧STEP3「ボススキル作成」を廃止・7→6 STEPへ移行した
# ため、この範囲・以下の個別フィールド確認も新しいSTEP番号へ合わせてある。
# §3)
# ---------------------------------------------------------------------------

func test_creator_step_1_through_5_have_real_nonzero_layout_and_no_fatal_overlap() -> void:
	var main := await _new_creator_main()
	assert_eq(main.current_step, 1, "sanity")
	var viewport: Rect2 = main.get_viewport_rect()
	var viewport_bottom: float = viewport.position.y + viewport.size.y

	for step in range(1, RBMCreatorMain.STEP_COUNT):
		main.go_to_step(step)
		await get_tree().process_frame
		await get_tree().process_frame

		assert_gt(main._steps_root.size.y, MIN_LARGE_AREA_HEIGHT, "STEP %d: _steps_root must receive real vertical space from root_column, not collapse to ~0" % step)

		var view: Control = main._step_views[step - 1]
		assert_true(view.visible, "STEP %d must be the one currently showing" % step)
		assert_gt(view.size.y, MIN_LARGE_AREA_HEIGHT, "STEP %d: the visible STEP view itself must also receive real space from _steps_root" % step)

		var column: Control = view.get_child(0)
		assert_gt(column.size.x, 0.0, "STEP %d: its content column must have a real, non-zero width" % step)
		assert_gt(column.size.y, 0.0, "STEP %d: its content column must have a real, non-zero height" % step)

		# §1: STEP content area and the bottom nav row (戻る/最終確認へ戻る/
		# 次へ) must not fatally overlap -- the visible field content must end
		# above where the nav row begins. This is exactly the class of bug
		# this round fixes (nav_row used to render right after the status
		# label, directly on top of the STEP content below it).
		var content_bottom := column.global_position.y + column.size.y
		var nav_top := main._back_button.global_position.y
		assert_lt(content_bottom, nav_top, "STEP %d: visible field content must end above where BACK/最終確認へ戻る/NEXT navigation starts" % step)

		# §2: BACK/NEXT/Creator退出ボタンの下端がviewport内に収まっていること
		# ——旧倍化バグ（root=2560x1440）ではviewportの実表示範囲(1280x720)を
		# 超えてこれらのボタンが配置され、実際には画面外へはみ出して見えなく
		# なる。単なる非0サイズ判定では検出できなかったクラスの回帰。
		var back_bottom := main._back_button.global_position.y + main._back_button.size.y
		assert_true(back_bottom <= viewport_bottom + EPSILON, "STEP %d: BACK button bottom (%s) must be within the viewport bottom (%s)" % [step, back_bottom, viewport_bottom])
		var next_bottom := main._next_button.global_position.y + main._next_button.size.y
		assert_true(next_bottom <= viewport_bottom + EPSILON, "STEP %d: NEXT button bottom (%s) must be within the viewport bottom (%s)" % [step, next_bottom, viewport_bottom])
		var exit_bottom := main._exit_button.global_position.y + main._exit_button.size.y
		assert_true(exit_bottom <= viewport_bottom + EPSILON, "STEP %d: Creator exit button bottom (%s) must be within the viewport bottom (%s)" % [step, exit_bottom, viewport_bottom])

		assert_gt(main._next_button.size.x, 0.0, "STEP %d: 次へ button must have a real, non-zero rect" % step)
		assert_gt(main._next_button.size.y, 0.0, "STEP %d: 次へ button must have a real, non-zero rect" % step)

	# §2 相当（既存のSTEP1〜4フィールドラベル修正の直接的な回帰確認）: 主要な
	# 入力欄/ボタン自身も実際に有効なrectを持ち、かつviewport内に収まって
	# いることを、各STEPの実フィールドで確認する。
	var step1: RBMCreatorStep1Basic = main._step_views[0]
	main.go_to_step(1)
	await get_tree().process_frame
	assert_gt(step1._name_edit.size.x, 0.0, "STEP1: boss name input must have a real rect")
	_assert_within_viewport(step1._name_edit, viewport, "STEP1 boss name input")
	assert_gt(step1._appearance_button.size.x, 0.0, "STEP1: appearance button must have a real rect")
	_assert_within_viewport(step1._appearance_button, viewport, "STEP1 appearance button")

	var step2: RBMCreatorStep2Stats = main._step_views[1]
	main.go_to_step(2)
	await get_tree().process_frame
	assert_gt(step2._hp_slider.size.x, 0.0, "STEP2: HP slider must have a real rect")
	_assert_within_viewport(step2._hp_slider, viewport, "STEP2 HP slider")
	assert_gt(step2._atk_slider.size.x, 0.0, "STEP2: ATK slider must have a real rect")
	_assert_within_viewport(step2._atk_slider, viewport, "STEP2 ATK slider")
	assert_gt(step2._spd_slider.size.x, 0.0, "STEP2: SPD slider must have a real rect")
	_assert_within_viewport(step2._spd_slider, viewport, "STEP2 SPD slider")

	## Creator UI再設計: 旧STEP3（ボススキル作成、廃止済み）の代わりに、
	## 新STEP3「行動」（SIMPLE側の通常行動作成、この画面が今その役割を
	## 吸収している）の実表示領域を確認する。旧STEP4だった「均等にする」
	## ボタン確認と対象が同じ画面になったため、ここへ統合した。
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	main.go_to_step(3)
	await get_tree().process_frame
	assert_gt(step3._add_normal_button.size.x, 0.0, "STEP3: 通常行動を作る button must have a real rect")
	_assert_within_viewport(step3._add_normal_button, viewport, "STEP3 通常行動を作る button")
	assert_gt(step3._equalize_button.size.x, 0.0, "STEP3: equalize button must have a real rect")
	_assert_within_viewport(step3._equalize_button, viewport, "STEP3 equalize button")

	## §14カードUI化: 旧「全キャラクター常時グリッド」の_gridは廃止され、
	## 常時表示なのは「＋キャラクターを追加」ボタン（パーティが空でも必ず
	## 存在する）になった。
	var step4: RBMCreatorStep5Party = main._step_views[3]
	main.go_to_step(4)
	await get_tree().process_frame
	assert_gt(step4._add_button.size.x, 0.0, "STEP4: add-character button must have a real rect")
	_assert_within_viewport(step4._add_button, viewport, "STEP4 add-character button")

	## Creator UI改修（STEP4統合、2026-09-05）§15カードUI化の後継: 旧・独立
	## STEP「使用可能スキル」の「全キャラすべてON」ボタン(_all_on_button)は
	## とうに廃止済みで、パーティが空の間は空状態ラベルが常時表示される
	## ——この機能は新STEP4の「選択キャラクター設定」パネル自身
	## （_selected_empty_label）へ統合された。
	assert_gt(step4._selected_empty_label.size.x, 0.0, "STEP4: selected-character empty-state label must have a real rect")
	_assert_within_viewport(step4._selected_empty_label, viewport, "STEP4 selected-character empty-state label")

## 実機確認後の最終UI修正: STEP3の中央編集領域だけがスクロールし、長い
## HARDCORE編集内容の最下部へ到達できること。RBMActionEditorFormを展開した
## 状態で、フォームの実rectが後続の確定/キャンセル行へ重ならないことも
## Godot自身が計算したglobal rectで直接確認する。
##
## Creator UI全面再設計(2026-09-05)対応: 旧「1パターンに条件/複数行動/
## 追加ルールを積む」構成は撤去された——新設計での相当物として「新しく
## 攻撃を作る」画面(skill_slot_view)で発動条件を多数積み、同じ「段階開示後の
## VBoxレイアウトが自然に下へ伸びる」シナリオを再現する（旧テストと同じ
## §1「STEP内の長いコンテンツがスクロール範囲を正しく持つ」「フォームと
## 確定/キャンセル行が重ならない」「中央のスクロールが戻る/次への固定
## 位置に影響しない」という回帰観点自体は不変）。
func test_step3_long_action_editor_scrolls_to_bottom_without_overlapping_form_or_fixed_navigation() -> void:
	var main := await _new_creator_main()
	var wrapper: RBMCreatorStep4 = main._step_views[2]
	main.go_to_step(3)
	await get_tree().process_frame

	assert_true(wrapper._simple_view._scroll_container is ScrollContainer, "SIMPLE側もSTEP3共通方針の縦ScrollContainerを持つこと")
	assert_false(wrapper._simple_view._scroll_container.is_ancestor_of(main._back_button), "戻る/次へはスクロール領域の外側に固定すること")

	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.draft.action_sequence.clear()
	wrapper.refresh()
	await get_tree().process_frame
	var advanced := wrapper._advanced_view
	var scroll := advanced._scroll_container
	assert_true(scroll is ScrollContainer)
	assert_false(scroll.is_ancestor_of(main._back_button))
	assert_false(scroll.is_ancestor_of(main._next_button))

	_btn(advanced, "AddSlotButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	## 条件カードを十分積み、フォーム展開後のcontentを確実にviewportより高くする。
	for turn in range(1, 13):
		_btn(advanced, "AddConditionButton").pressed.emit()
		advanced._condition_type_option.select(RBMActionPatternRules.NORMAL_CONDITION_TYPES.find("turn_at"))
		advanced._on_condition_type_selected(advanced._condition_type_option.selected)
		advanced._condition_turn_spin.value = float(turn)
		_btn(advanced, "ConfirmConditionButton").pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(advanced._form.visible, "長いSTEP3内で共通行動フォームが展開されていること")
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "STEP3 ScrollContainerが実表示領域を持つこと")
	assert_gt(advanced._scroll_content.size.y, scroll.size.y, "長いcontentがviewportを超えて自然に下へ伸びること")
	var vbar := scroll.get_v_scroll_bar()
	assert_true(vbar.visible, "contentがviewportを超えた時に縦スクロールが有効になること")
	assert_gt(vbar.max_value, vbar.page, "最下部へ移動できる実スクロール範囲が存在すること")

	var confirm_button := _btn(advanced, "SkillSlotConfirmButton")
	var cancel_button := _btn(advanced, "SkillSlotCancelButton")
	var form_bottom := advanced._form.global_position.y + advanced._form.size.y
	assert_true(form_bottom <= confirm_button.global_position.y + EPSILON, "行動フォームの下端が確定/キャンセル行へ重ならないこと")
	assert_false(advanced._form.get_global_rect().intersects(confirm_button.get_global_rect()), "行動フォームと確定ボタンのRectが交差しないこと")
	assert_false(advanced._form.get_global_rect().intersects(cancel_button.get_global_rect()), "行動フォームとキャンセルボタンのRectが交差しないこと")

	var nav_y_before := main._back_button.global_position.y
	scroll.scroll_vertical = int(ceil(vbar.max_value))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(scroll.scroll_vertical, 0, "実際に縦スクロール位置が移動すること")
	var scroll_top := scroll.global_position.y
	var scroll_bottom := scroll.global_position.y + scroll.size.y
	assert_true(confirm_button.global_position.y >= scroll_top - EPSILON, "最下部へスクロールすると確定ボタンへアクセスできること")
	assert_true(confirm_button.global_position.y + confirm_button.size.y <= scroll_bottom + EPSILON, "確定ボタン全体がScrollContainer内へ表示されること")
	assert_eq(main._back_button.global_position.y, nav_y_before, "中央をスクロールしても戻る/次への固定位置は動かないこと")

# ---------------------------------------------------------------------------
# Creator STEP5 最終確認画面 (§3、旧STEP7。Creator UI改修2026-09-05で
# 6→5 STEPへ再統合され、TEST BATTLE/CLEAR CHECKボタンはそれぞれ「動作確認」
# 「CLEAR CHECK」セクションとしてスクロール領域"内"に配置されるようになった
# ——固定の下部バー（戻る/保存/公開）だけがスクロール領域の外側にある、
# という新しい構造を検証する。)
# ---------------------------------------------------------------------------

func test_step5_summary_confirm_content_has_real_display_area_and_does_not_overlap_bottom_bar() -> void:
	var main := await _new_creator_main()
	var viewport: Rect2 = main.get_viewport_rect()
	var viewport_bottom: float = viewport.position.y + viewport.size.y

	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	await get_tree().process_frame
	await get_tree().process_frame

	var step5_summary: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	assert_true(step5_summary.visible)

	var scroll: Control = step5_summary._content.get_parent()
	assert_true(scroll is ScrollContainer, "sanity: _content's parent must be the confirm screen's ScrollContainer")
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "STEP5: the confirm-content ScrollContainer must have real display area, not collapse to ~0 (this was the 'ほぼ表示されていません' bug)")
	assert_gt(step5_summary._content.get_child_count(), 0, "STEP5: confirm content must actually contain sections (作成内容/挑戦設定/動作確認/CLEAR CHECK)")

	# §19: 下部バー（戻る/保存/公開）はScrollContainerの下端「以降」に配置
	# されること——ScrollContainerの中身が長くても、下部バー自体はスクロール
	# の外側＝ScrollContainer自身の下端よりさらに下に固定表示される。
	var bottom_bar: Control = step5_summary._save_button.get_parent()
	var scroll_bottom := scroll.global_position.y + scroll.size.y
	assert_true(bottom_bar.global_position.y >= scroll_bottom - EPSILON, "STEP5: bottom bar top (%s) must be at/after the ScrollContainer's own bottom edge (%s)" % [bottom_bar.global_position.y, scroll_bottom])

	# 下部バーの下端、および戻る/保存/公開の各ボタンがviewport内に収まって
	# いること。
	var bottom_bar_bottom := bottom_bar.global_position.y + bottom_bar.size.y
	assert_true(bottom_bar_bottom <= viewport_bottom + EPSILON, "STEP5: bottom bar bottom (%s) must be within the viewport bottom (%s)" % [bottom_bar_bottom, viewport_bottom])
	assert_gt(step5_summary._save_button.size.x, 0.0, "STEP5: 保存 button must have a real rect")
	_assert_within_viewport(step5_summary._save_button, viewport, "STEP5 保存 button")
	assert_gt(step5_summary._publish_button.size.x, 0.0, "STEP5: 公開 button must have a real rect")
	_assert_within_viewport(step5_summary._publish_button, viewport, "STEP5 公開 button")

	# §19: TEST BATTLE/CLEAR CHECKは「動作確認」「CLEAR CHECK」セクションと
	# してスクロール可能な_content内に実在すること（旧: 固定下部バー内）。
	assert_true(scroll.is_ancestor_of(step5_summary._test_battle_button), "STEP5: TEST BATTLE button must live inside the scrollable content, not the fixed bottom bar")
	assert_true(scroll.is_ancestor_of(step5_summary._clear_check_button), "STEP5: CLEAR CHECK button must live inside the scrollable content, not the fixed bottom bar")
	assert_gt(step5_summary._test_battle_button.size.x, 0.0, "STEP5: TEST BATTLE button must have a real rect")
	assert_gt(step5_summary._clear_check_button.size.x, 0.0, "STEP5: CLEAR CHECK button must have a real rect")

# ---------------------------------------------------------------------------
# CHALLENGE 挑戦確認画面 (§4 — 「Phase 1完成阻害問題」として指摘された画面)
# ---------------------------------------------------------------------------

func test_challenge_confirm_screen_has_real_display_area_and_does_not_overlap_buttons() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	var viewport_bottom: float = viewport.position.y + viewport.size.y

	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "レイアウト確認用ボス"
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")

	# STEP各画面自身のウィジェット配線・保存フローUI自体は既存フェーズ/
	# 本ラウンドの他のE2E/回帰テストで別途検証済みのため、ここでは「CHALLENGE
	# 確認画面へ実際に到達させる」ための最短経路として直接保存APIを呼ぶ
	# （このテストの目的はレイアウトのみ）。
	var save_result := main.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)), "sanity: a minimally-valid draft must save successfully")
	# Creator UI改修（2026-09-05）§24〜§27（公開機能）: 保存しただけでは
	# CHALLENGEに表示されないため、このレイアウト確認テストがCHALLENGE確認
	# 画面へ到達するには公開まで必要——このテストの目的はレイアウトのみの
	# ため、直接APIによる最短経路のまま公開まで済ませる。
	main.draft.record_clear_check_success()
	assert_true(main.press_publish().get("ok", false), "sanity: publish must have succeeded")

	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame

	assert_eq(root.challenge_entry._list_rows.get_child_count(), 1, "sanity: the just-saved stage must appear in the CHALLENGE list")
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row)
	await get_tree().process_frame
	await get_tree().process_frame

	var confirm: RBMChallengeConfirmView = root.challenge_entry._confirm_view
	assert_true(confirm.visible)

	var scroll: Control = confirm._content.get_parent()
	assert_true(scroll is ScrollContainer, "sanity: _content's parent must be the CHALLENGE confirm screen's ScrollContainer")
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "CHALLENGE confirm: the content ScrollContainer must have real display area, not collapse to ~0 (the blocking 'ボス/パーティ情報が表示されない' bug)")

	assert_gt(confirm._boss_name_label.size.x, 0.0, "CHALLENGE confirm: boss name label must have a real rect")
	assert_true(confirm._boss_name_label.text.contains("レイアウト確認用ボス"), "sanity: the confirm content is really populated, not just present-but-empty")
	assert_gt(confirm._boss_skills_section.get_child_count(), 0, "CHALLENGE confirm: boss skills section must actually contain content")
	assert_gt(confirm._party_section.get_child_count(), 0, "CHALLENGE confirm: party section must actually contain content")

	# CHALLENGE UI再設計 §17: 独立した確認ステップという概念自体が廃止され、
	# 「戻る」の概念も変わった（旧ConfirmBackButtonは退役、共通一覧画面の
	# ヘッダの「← 挑戦ハブ」が代わりを担う）ため、ここでは残った唯一の
	# ボタン「このボスに挑戦」(ChallengeStartButton)だけを検証する。
	var start_button := confirm.find_child("ChallengeStartButton", true, false) as Button
	assert_not_null(start_button)
	assert_null(confirm.find_child("ConfirmBackButton", true, false), "the old standalone-confirm-step back button must no longer exist")
	assert_gt(start_button.size.x, 0.0, "CHALLENGE confirm: 挑戦する button must have a real rect")
	_assert_within_viewport(start_button, viewport, "CHALLENGE confirm 挑戦する button")

	# §4: ボタンはScrollContainerの下端「以降」に配置されること（STEP7と
	# 同じ修正——旧: button row上端 > ScrollContainer上端、という不十分な
	# 判定を修正）。ボタンの下端もviewport内に収まっていること。
	var scroll_bottom := scroll.global_position.y + scroll.size.y
	assert_true(start_button.global_position.y >= scroll_bottom - EPSILON, "CHALLENGE confirm: button top (%s) must be at/after the ScrollContainer's own bottom edge (%s), not merely after its top" % [start_button.global_position.y, scroll_bottom])
	var start_button_bottom := start_button.global_position.y + start_button.size.y
	assert_true(start_button_bottom <= viewport_bottom + EPSILON, "CHALLENGE confirm: button bottom (%s) must be within the viewport bottom (%s)" % [start_button_bottom, viewport_bottom])
