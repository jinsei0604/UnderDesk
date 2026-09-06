extends GutTest

## Phase 3.5「タイトル画面UI新設 + 戦闘UIデザイン統一」— 回帰テスト。
##
## §18: 挑戦/作成ボタンの存在・遷移・1280x720内への収まり、および今回の
## Theme適用パスが既存の戦闘UI（Step 4で確定済み）の主要ノードを壊して
## いないことを直接検証する。RBMGameRootを実際にインスタンス化し、Godot
## 自身のレイアウト計算を経た本物のControl.size/global_positionのみを
## 見る——test_rbm_step8_layout_regressions.gdの_make_root()と同じ方針・
## 同じheadless環境対応（GUT実行環境はproject.godotのwindow/size設定を
## 継承しないため、RBMGameRootインスタンス化前にテストハーネス自身の
## ウィンドウを1280x720へ明示的に合わせる）。
##
## §15: _title_screen（背景2層＋_menu_panelの共通親）を切り替えることで、
## Creator/Challengeへ入った際に背景レイヤーが裏に残ったまま表示され続ける
## バグを実装時に発見・修正した——test_returning_from_*_shows_title_screen_again
## がこの修正の直接的な回帰ガード。

const TEST_DIR := "user://bossmaker_test_phase35_title_screen/stages"
const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)
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

## test_rbm_step8_layout_regressions.gd._make_root()と同一の技法・同一の
## 理由（ファイル冒頭コメント参照）。
func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

func _assert_within_viewport(node: Control, viewport: Rect2, description: String) -> void:
	var top_left := node.global_position
	var bottom_right := node.global_position + node.size
	assert_true(top_left.x >= viewport.position.x - EPSILON, "%s: left edge (%s) must be within the viewport (>= %s)" % [description, top_left.x, viewport.position.x])
	assert_true(top_left.y >= viewport.position.y - EPSILON, "%s: top edge (%s) must be within the viewport (>= %s)" % [description, top_left.y, viewport.position.y])
	assert_true(bottom_right.x <= viewport.position.x + viewport.size.x + EPSILON, "%s: right edge (%s) must be within the viewport (<= %s)" % [description, bottom_right.x, viewport.position.x + viewport.size.x])
	assert_true(bottom_right.y <= viewport.position.y + viewport.size.y + EPSILON, "%s: bottom edge (%s) must be within the viewport (<= %s)" % [description, bottom_right.y, viewport.position.y + viewport.size.y])

# =============================================================================
# §18: 挑戦/作成ボタンの存在・遷移
# =============================================================================

func test_challenge_button_exists() -> void:
	var root := await _make_root()
	var button := _btn(root, "ChallengeModeButton")
	assert_eq(button.text, "挑戦", "the primary Challenge button must read 挑戦")
	assert_true(root._title_screen.visible, "sanity: title screen starts visible")

func test_create_button_exists() -> void:
	var root := await _make_root()
	var button := _btn(root, "CreateModeButton")
	assert_eq(button.text, "作成", "the primary Create button must read 作成")

func test_challenge_button_navigates_to_challenge_entry() -> void:
	var root := await _make_root()
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	assert_false(root._title_screen.visible, "title screen must hide once 挑戦 is pressed")
	assert_true(root.challenge_entry.visible, "挑戦 must reveal challenge_entry")
	assert_false(root.creator_entry.visible, "挑戦 must not also reveal creator_entry")

func test_create_button_navigates_to_creator_entry() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	assert_false(root._title_screen.visible, "title screen must hide once 作成 is pressed")
	assert_true(root.creator_entry.visible, "作成 must reveal creator_entry")
	assert_false(root.challenge_entry.visible, "作成 must not also reveal challenge_entry")

## §15: Creator/Challengeへ入って戻ると、タイトル画面（背景2層含む）が
## 再び表示されること——_menu_panelだけを切り替えると背景レイヤーが
## sibling として裏に残ったままになる、実装時に発見したバグの回帰ガード。
func test_returning_from_creator_shows_title_screen_again() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	root._on_creator_exit_requested()
	await get_tree().process_frame
	assert_true(root._title_screen.visible, "title screen (incl. background layers) must reappear after leaving Creator")
	assert_true(root._menu_panel.visible, "menu panel must reappear after leaving Creator")
	assert_false(root.creator_entry.visible)
	assert_false(root.challenge_entry.visible)

func test_returning_from_challenge_shows_title_screen_again() -> void:
	var root := await _make_root()
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	root._on_challenge_exit_requested()
	await get_tree().process_frame
	assert_true(root._title_screen.visible, "title screen (incl. background layers) must reappear after leaving Challenge")
	assert_true(root._menu_panel.visible, "menu panel must reappear after leaving Challenge")
	assert_false(root.creator_entry.visible)
	assert_false(root.challenge_entry.visible)

# =============================================================================
# §16/§17: 1280x720内に主要UIが収まること
# =============================================================================

func test_title_screen_primary_ui_stays_within_viewport_at_1280x720() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	assert_eq(viewport.size, HEADLESS_WINDOW_SIZE, "sanity: viewport is exactly 1280x720")

	var challenge_button := _btn(root, "ChallengeModeButton")
	_assert_within_viewport(challenge_button, viewport, "挑戦 button")
	var create_button := _btn(root, "CreateModeButton")
	_assert_within_viewport(create_button, viewport, "作成 button")

	# §3: 中央は意図的に空ける——挑戦/作成は画面下部にあること
	# （上半分ではなく、viewportの垂直中央より下に位置すること）。
	var button_center_y := challenge_button.global_position.y + challenge_button.size.y * 0.5
	assert_gt(button_center_y, viewport.size.y * 0.5, "挑戦/作成 must sit in the bottom half of the screen, per §3")

# =============================================================================
# タイトル画面完成アート反映 — 完成画像の表示・旧仮タイトルの削除・
# クリック領域が画像上のボタン位置と一致すること
# =============================================================================

## §2: 完成画像がそのまま採用されていること（再エンコード/差し替え忘れの
## 回帰ガード）——パスとテクスチャの両方を確認する。
func test_title_background_uses_the_adopted_completed_image() -> void:
	var root := await _make_root()
	assert_eq(RBMGameRoot.TITLE_IMAGE_PATH, "res://assets_bossmaker/art/title_screen_makers_and_challengers.png")
	assert_not_null(root._title_background.texture, "title background must have a real texture assigned")
	assert_eq(root._title_background.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "must preserve aspect ratio, not stretch/distort (§5)")

## §2/§9: 旧・文字ベースの仮タイトル「RPG BOSS MAKER」はどこにも存在しない
## こと（完成画像自身がロゴを含むため、二重表示を防ぐ）。
func test_old_placeholder_title_label_no_longer_exists() -> void:
	var root := await _make_root()
	assert_null(root.find_child("GameRootTitleLabel", true, false), "the old placeholder title Label must be removed")

## §3: 完成画像に描かれた「挑戦」「作成」ボタン絵のちょうど上に、透明クリック
## 領域が重なっていること——RBMGameRoot自身が計算した比率アンカーの結果を、
## 実測したボタン絵の外接矩形（画像ピクセル座標）から独立に再計算し、
## 一致することを確認する(単に定数を読み返すだけの同語反復にならないよう、
## 実際のControl.get_rect()をTITLE_IMAGE_SIZE基準へ逆算して突き合わせる)。
func test_click_regions_align_with_the_button_artwork_in_the_image() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()

	var challenge_button := _btn(root, "ChallengeModeButton")
	var create_button := _btn(root, "CreateModeButton")

	# _title_screenはFULL_RECTでviewportいっぱいに広がり、STRETCH_KEEP_ASPECT_
	# CENTEREDの画像とproject.godotの基準アスペクト(1280x720)はほぼ一致する
	# ため、viewport矩形を基準にピクセル座標へ逆算してよい（RBMGameRoot._
	# apply_image_fraction_rect()と同じ前提）。
	var challenge_rect_px := Rect2(
		challenge_button.global_position.x / viewport.size.x * RBMGameRoot.TITLE_IMAGE_SIZE.x,
		challenge_button.global_position.y / viewport.size.y * RBMGameRoot.TITLE_IMAGE_SIZE.y,
		challenge_button.size.x / viewport.size.x * RBMGameRoot.TITLE_IMAGE_SIZE.x,
		challenge_button.size.y / viewport.size.y * RBMGameRoot.TITLE_IMAGE_SIZE.y
	)
	var px_epsilon := 2.0
	assert_almost_eq(challenge_rect_px.position.x, RBMGameRoot.CHALLENGE_BUTTON_PIXEL_RECT.position.x, px_epsilon)
	assert_almost_eq(challenge_rect_px.position.y, RBMGameRoot.CHALLENGE_BUTTON_PIXEL_RECT.position.y, px_epsilon)
	assert_almost_eq(challenge_rect_px.size.x, RBMGameRoot.CHALLENGE_BUTTON_PIXEL_RECT.size.x, px_epsilon)
	assert_almost_eq(challenge_rect_px.size.y, RBMGameRoot.CHALLENGE_BUTTON_PIXEL_RECT.size.y, px_epsilon)

	var create_rect_px := Rect2(
		create_button.global_position.x / viewport.size.x * RBMGameRoot.TITLE_IMAGE_SIZE.x,
		create_button.global_position.y / viewport.size.y * RBMGameRoot.TITLE_IMAGE_SIZE.y,
		create_button.size.x / viewport.size.x * RBMGameRoot.TITLE_IMAGE_SIZE.x,
		create_button.size.y / viewport.size.y * RBMGameRoot.TITLE_IMAGE_SIZE.y
	)
	assert_almost_eq(create_rect_px.position.x, RBMGameRoot.CREATE_BUTTON_PIXEL_RECT.position.x, px_epsilon)
	assert_almost_eq(create_rect_px.position.y, RBMGameRoot.CREATE_BUTTON_PIXEL_RECT.position.y, px_epsilon)
	assert_almost_eq(create_rect_px.size.x, RBMGameRoot.CREATE_BUTTON_PIXEL_RECT.size.x, px_epsilon)
	assert_almost_eq(create_rect_px.size.y, RBMGameRoot.CREATE_BUTTON_PIXEL_RECT.size.y, px_epsilon)

	# 2つのボタンが重ならないこと（測定誤差で食い違って重複配置になっていない
	# ことの直接確認）。
	assert_false(challenge_button.get_global_rect().intersects(create_button.get_global_rect()), "挑戦/作成 hit regions must not overlap")

## §4: 透明クリック領域の見た目——通常時は完全透明、Hover/Pressedはごく
## 控えめな半透明のみ（派手な発光/巨大枠/画像を隠すオーバーレイではない
## ことを、実際のTheme StyleBoxの数値で直接確認する）。
func test_hotspot_button_theme_is_transparent_at_rest_and_subtle_on_hover() -> void:
	var root := await _make_root()
	var challenge_button := _btn(root, "ChallengeModeButton")
	assert_eq(challenge_button.theme_type_variation, RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON)

	var theme := root._title_screen.theme
	assert_not_null(theme)
	var normal: StyleBoxFlat = theme.get_stylebox("normal", RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON)
	assert_almost_eq(normal.bg_color.a, 0.0, 0.001, "normal state must be fully transparent (image supplies the look)")

	var hover: StyleBoxFlat = theme.get_stylebox("hover", RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON)
	assert_gt(hover.bg_color.a, 0.0, "hover must give some feedback")
	assert_lt(hover.bg_color.a, 0.25, "hover feedback must stay subtle, not an opaque overlay hiding the artwork")

	var pressed: StyleBoxFlat = theme.get_stylebox("pressed", RBMUiTheme.VARIATION_IMAGE_HOTSPOT_BUTTON)
	assert_lt(pressed.bg_color.a, 0.3, "pressed feedback must also stay subtle")

# =============================================================================
# §9/§14: 既存の戦闘UI（Step 4）の主要ノードがTheme適用後も無傷であること
# =============================================================================

func _definition_with_hero() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "タイトルUI回帰確認用ボス"
	draft.hp = 999999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	return draft.to_definition()

func test_existing_battle_ui_main_nodes_are_preserved_after_theme_pass() -> void:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame

	var definition := _definition_with_hero()
	var view := main._test_battle_view
	assert_true(view.start(definition, 1), "sanity: battle session starts")
	await get_tree().process_frame

	assert_not_null(view.theme, "battle view root must carry the shared RBMUiTheme after this round's theme pass")
	_btn(view, "AttackButton")
	_btn(view, "OpenSkillListButton")
	_btn(view, "DefendButton")
	_btn(view, "LogButton")
	assert_not_null(view.find_child("Battlefield", true, false), "battlefield container must still exist")
	assert_not_null(view.find_child("PartyRows", true, false), "party status row must still exist")
	assert_not_null(view.find_child("TurnOrderPanel", true, false), "turn order panel must still exist")
