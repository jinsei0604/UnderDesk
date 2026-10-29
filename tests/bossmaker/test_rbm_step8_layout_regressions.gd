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
	add_child_autoqfree(root)
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

## 見た目の刷新（2026-10、ユーザーが完成イメージで承認した「案A＋案C」）: TOP画面は城の扉の背景をやめ、
## 図形だけの地の上に、左上の戻る・見出し・説明と、2枚の大きなカードを置く。ふだんは同じ幅（案A）、
## 選んだ（マウスを重ねた・キーボードで選んだ）方が広く（720px）、もう一方が狭く（408px）なる（案C）。
## 文字はすべてLabel/Buttonとして実在し（絵に焼き込まない）、2枚は重ならず、戻るは明確に小さい階層。
## マウスは本物の入力（Viewport.push_input のマウス移動）で動かし、選択・幅・光り方を確かめる
## （カードの上・カードの間の隙間・2枚の外。実際の画面での見え方は実GPU検証で確認）。
func test_creator_entry_top_screen_matches_the_approved_split_layout() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame

	var viewport := root.get_viewport_rect()
	var entry: RBMCreatorEntry = root.creator_entry
	var background: Control = entry.find_child("EntryBackground", true, false)
	var title: Label = entry.find_child("EntryTitleLabel", true, false)
	var description: Label = entry.find_child("EntryDescriptionLabel", true, false)
	var choice: RBMCreatorTopChoice = entry.find_child("EntryChoice", true, false)
	var new_button := _btn(entry, "NewBossButton")
	var edit_button := _btn(entry, "EditSavedBossButton")
	var back_button := _btn(entry, "BackToRootButton")
	var new_card := new_button as RBMCreatorTopChoice.Card
	var edit_card := edit_button as RBMCreatorTopChoice.Card

	assert_true(background is RBMMenuUi.Backdrop, "the top screen must use the drawn backdrop")
	assert_true(background.is_visible_in_tree())
	for node in entry._top_panel.find_children("*", "TextureRect", true, false):
		var texture: Texture2D = (node as TextureRect).texture
		assert_true(texture == null or not texture.resource_path.ends_with("creator_top_background.png"), "the castle door art must no longer be used")
	assert_eq(title.text, "ボス戦を作成")
	assert_eq(description.text, "新しく作るか、保存したボス戦を編集します")
	assert_eq(new_card.title_label.text, "新しいボス戦を作る")
	assert_eq(edit_card.title_label.text, "保存したボス戦を編集")
	assert_eq(new_card.cta.label.text, "作成を始める")
	assert_eq(edit_card.cta.label.text, "一覧を開く")
	assert_eq(back_button.text, "戻る")
	assert_not_null(back_button.icon, "戻る矢印は共通ピクセルアイコンで表示")
	# このテストの保存先は空なので、編集のカードは「まだありません」を出す（0件の状態）。
	assert_true((edit_button.find_child("SavedEmptyLabel", true, false) as Label).visible)
	assert_false((edit_button.find_child("SavedCountValue", true, false) as Label).visible)

	# 視線の流れ: 見出し → 2枚のカード。戻るは左上（見出しの左、カードより上）。
	assert_true(title.global_position.y + title.size.y < new_button.global_position.y, "title must precede the cards")
	assert_true(back_button.get_global_rect().end.y < new_button.global_position.y, "back must sit above the cards")
	assert_lt(back_button.global_position.x, title.global_position.x, "back must sit left of the title")

	# ふだん（どちらも選ばれていない）は同じ幅・同じ高さで左右に並び、重ならず、左右の余白も等しい。
	assert_eq(choice.selected, RBMCreatorTopChoice.NONE)
	assert_eq(new_button.size, edit_button.size)
	assert_almost_eq(new_button.global_position.y, edit_button.global_position.y, EPSILON)
	assert_lt(new_button.global_position.x, edit_button.global_position.x, "new-boss card must sit on the left")
	assert_false(new_button.get_global_rect().intersects(edit_button.get_global_rect()), "cards must not overlap")
	assert_almost_eq(new_button.global_position.x - viewport.position.x, viewport.end.x - edit_button.get_global_rect().end.x, EPSILON, "balanced side margins")
	# 主な行動（新しく作る）の帯は、ふだんから光っている。
	assert_eq(new_card.cta.lit, 1.0)
	assert_eq(edit_card.cta.lit, 0.0)

	# 戻るはカードより明確に小さい階層。
	assert_lt(back_button.size.x, new_button.size.x)
	assert_lt(back_button.size.y, new_button.size.y)
	for node in [title, description, new_button, edit_button, back_button]:
		_assert_within_viewport(node, viewport, "CREATE top %s" % node.name)
	_assert_card_text_fits(new_button)
	_assert_card_text_fits(edit_button)

	# マウスを重ねた方が広がる。0.22秒の ease-out（半分の時間で4分の3以上進む）。
	_point(new_button.get_global_rect().get_center())
	assert_eq(choice.selected, 0)
	choice._process(RBMCreatorTopChoice.DURATION / 2.0)
	assert_gt(new_button.size.x, 564.0 + (RBMCreatorTopChoice.WIDE - 564.0) * 0.75, "ease-out: most of the change happens early")
	assert_lt(new_button.size.x, RBMCreatorTopChoice.WIDE)
	choice._process(RBMCreatorTopChoice.DURATION)
	assert_eq(new_button.size.x, RBMCreatorTopChoice.WIDE)
	assert_eq(edit_button.size.x, RBMCreatorTopChoice.NARROW)
	assert_almost_eq(edit_button.get_global_rect().end.x, choice.get_global_rect().end.x, EPSILON, "the pair keeps its outer edges while resizing")
	assert_false(new_button.get_global_rect().intersects(edit_button.get_global_rect()))
	assert_eq(new_card.glow, 1.0)
	_assert_card_text_fits(new_button)
	_assert_card_text_fits(edit_button)
	# カードの間の隙間へ出ても選択はそのまま。2枚の外へ出ると元の同じ幅に戻る。
	_point(Vector2(new_button.get_global_rect().end.x + RBMCreatorTopChoice.GAP / 2.0, new_button.get_global_rect().get_center().y))
	assert_eq(choice.selected, 0, "the gap between the cards keeps the selection")
	_point(Vector2(640, 700))
	assert_eq(choice.selected, RBMCreatorTopChoice.NONE)
	choice._process(RBMCreatorTopChoice.DURATION)
	assert_eq(new_button.size, edit_button.size)

	# 編集の方を選ぶと、編集が広がって光り、新しく作るの帯は消える。
	_point(edit_button.get_global_rect().get_center())
	choice._process(RBMCreatorTopChoice.DURATION)
	assert_eq(edit_button.size.x, RBMCreatorTopChoice.WIDE)
	assert_eq(new_button.size.x, RBMCreatorTopChoice.NARROW)
	assert_eq(edit_card.cta.lit, 1.0)
	assert_eq(new_card.cta.lit, 0.0)
	_assert_card_text_fits(new_button)
	_assert_card_text_fits(edit_button)
	_point(Vector2(640, 700))
	choice._process(RBMCreatorTopChoice.DURATION)

	# キーボードで選んだカードも広がる。マウスが外へ出ても、キーボードで選んでいる間はそのまま。
	new_button.grab_focus()
	await get_tree().process_frame
	assert_true(new_button.has_focus(), "cards must accept keyboard/gamepad focus")
	assert_eq(choice.selected, 0)
	assert_not_null(new_button.get_theme_stylebox("focus"))
	_point(Vector2(640, 700))
	assert_eq(choice.selected, 0)
	new_button.release_focus()
	await get_tree().process_frame
	assert_eq(choice.selected, RBMCreatorTopChoice.NONE, "losing keyboard focus outside the cards returns to the even layout")

## カードの中の見えている文字が、カードからはみ出さず、横に切れていないこと。
func _assert_card_text_fits(card: Control) -> void:
	for label_variant in card.find_children("*", "Label", true, false):
		var label := label_variant as Label
		if not label.is_visible_in_tree():
			continue
		assert_true(card.get_global_rect().grow(EPSILON).encloses(label.get_global_rect()), "%s/%s must stay inside its card" % [card.name, label.name])
		assert_true(label.get_minimum_size().x <= label.size.x + EPSILON, "%s/%s text must not be clipped horizontally" % [card.name, label.name])

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
	wrapper.refresh()
	await get_tree().process_frame
	var advanced := wrapper._advanced_view
	var scroll := advanced._scroll_container
	assert_true(scroll is ScrollContainer)
	assert_false(scroll.is_ancestor_of(main._back_button))
	assert_false(scroll.is_ancestor_of(main._next_button))

	## 2026-10-28: 条件は「条件で分岐」のターンの行（行動の詳細）で付ける。
	_btn(advanced, "AddTurnButton").pressed.emit()
	_btn(advanced, "TurnModeButton_conditional").pressed.emit()
	_btn(advanced, "AddTurnEntryButton").pressed.emit()
	_btn(advanced, "AddChoiceCreateNewButton").pressed.emit()
	## 条件カードを十分積み、フォーム展開後のcontentを確実にviewportより高くする。
	for turn in range(1, 13):
		_btn(advanced, "AddConditionButton").pressed.emit()
		advanced._select_condition_type("turn_at")
		advanced._condition_turn_spin.value = float(turn)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(advanced._form.visible, "長いSTEP3内で共通行動フォームが展開されていること")
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "STEP3 ScrollContainerが実表示領域を持つこと")
	assert_gt(advanced._scroll_content.size.y, scroll.size.y, "長いcontentがviewportを超えて自然に下へ伸びること")
	var vbar := scroll.get_v_scroll_bar()
	assert_true(vbar.visible, "contentがviewportを超えた時に縦スクロールが有効になること")
	assert_gt(vbar.max_value, vbar.page, "最下部へ移動できる実スクロール範囲が存在すること")

	var confirm_button := _btn(advanced, "EntryConfirmButton")
	var cancel_button := _btn(advanced, "EntryCancelButton")
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
	assert_gt(step5_summary._publish_online_button.size.x, 0.0, "STEP5: オンライン公開 button must have a real rect")
	_assert_within_viewport(step5_summary._publish_online_button, viewport, "STEP5 オンライン公開 button")

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
	root.challenge_entry._open_local_published_list()  # 手元公開のボスの一覧（2026-10-17 から挑戦トップの「ボスを検索」はオンラインを探す。PX-03）
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

## 本物のマウス移動の入力を画面へ流す（画面の座標）。
func _point(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	get_tree().root.push_input(ev, true)
