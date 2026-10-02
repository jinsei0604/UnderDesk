extends GutTest

## Phase 3.5「タイトル画面UI新設 + 戦闘UIデザイン統一」— 回帰テスト。
##
## 現在のタイトル画面(ホーム画面、2026-09-18〜): 背景は3モニター枠を含む完成画像
## (title_screen_home_monitors.png)。ユーザーは左下「挑戦」／右下「ボス作成」の
## ホームモニター(ChallengeHomeMonitor/CreatorHomeMonitor)をクリックして挑戦/作成へ
## 進む。ChallengeModeButton/CreateModeButtonは非表示の論理ボタンで、モニターの
## activatedがその.pressedを発火させて既存の遷移へつなぐ(RBMGameRoot._build_ui()参照)。
## モニターの位置・矩形・クリック範囲・起動演出はtest_rbm_home_monitor_transition.gdが
## 確かめるため、ここでは重複して持たない。旧Phase 3.5の「背景にボタン絵が描き込まれ、
## 透明なクリック領域を重ねる」方式は廃止された(その方式専用の検証は削除済み)。
##
## §18: 挑戦/作成の論理ボタンの存在・遷移、見えている主要タイトルUIの1280x720内への
## 収まり、および今回のTheme適用パスが既存の戦闘UI（Step 4で確定済み）の主要ノードを壊して
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

## 確かめる対象は、ユーザーが実際に見る主要タイトルUI(左下/右下のホームモニターと
## 上中央の戦闘モニター)。非表示の論理ボタン(ChallengeModeButton/CreateModeButton)は
## 画面に出ないので対象にしない。
func test_title_screen_primary_ui_stays_within_viewport_at_1280x720() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	assert_eq(viewport.size, HEADLESS_WINDOW_SIZE, "sanity: viewport is exactly 1280x720")

	var challenge_monitor := _visible_control(root, "ChallengeHomeMonitor")
	_assert_within_viewport(challenge_monitor, viewport, "挑戦 home monitor")
	var creator_monitor := _visible_control(root, "CreatorHomeMonitor")
	_assert_within_viewport(creator_monitor, viewport, "ボス作成 home monitor")
	var top_monitor := _visible_control(root, "TopMonitorBattlePreview")
	_assert_within_viewport(top_monitor, viewport, "top-center battle monitor")

	# §3: 中央は意図的に空ける——挑戦/作成は画面下部にあること
	# （上半分ではなく、viewportの垂直中央より下に位置すること）。今は左下/右下の
	# ホームモニターがその挑戦/作成にあたる。
	for monitor in [challenge_monitor, creator_monitor]:
		var center_y: float = monitor.global_position.y + monitor.size.y * 0.5
		assert_gt(center_y, viewport.size.y * 0.5, "%s must sit in the bottom half of the screen, per §3" % monitor.name)

func _visible_control(node: Node, control_name: String) -> Control:
	var found := node.find_child(control_name, true, false) as Control
	assert_not_null(found, "expected a Control named %s under %s" % [control_name, node])
	if found != null:
		assert_true(found.is_visible_in_tree(), "%s must be visible on the title screen" % control_name)
	return found

# =============================================================================
# タイトル画面完成アート反映 — 完成画像の表示・旧仮タイトルの削除
# =============================================================================

## §2: 完成画像がそのまま採用されていること（再エンコード/差し替え忘れの
## 回帰ガード）——パスとテクスチャの両方を確認する。今の正式背景は3モニター枠を含む
## ホーム画面の完成画像(2026-09-18に旧title_screen_makers_and_challengers.pngから置き換え)。
func test_title_background_uses_the_adopted_completed_image() -> void:
	var root := await _make_root()
	assert_eq(RBMGameRoot.TITLE_IMAGE_PATH, "res://assets_bossmaker/art/title_screen_home_monitors.png")
	assert_not_null(root._title_background.texture, "title background must have a real texture assigned")
	assert_eq(root._title_background.texture.resource_path, RBMGameRoot.TITLE_IMAGE_PATH, "the assigned texture is the adopted home-monitor image itself")
	assert_eq(root._title_background.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "must preserve aspect ratio, not stretch/distort (§5)")

## §2/§9: 旧・文字ベースの仮タイトル「RPG BOSS MAKER」はどこにも存在しない
## こと（完成画像自身がロゴを含むため、二重表示を防ぐ）。
func test_old_placeholder_title_label_no_longer_exists() -> void:
	var root := await _make_root()
	assert_null(root.find_child("GameRootTitleLabel", true, false), "the old placeholder title Label must be removed")

# 旧「背景のボタン絵とクリック領域の一致」「透明ホットスポットの見た目」の検証は、
# 背景にボタン絵が描き込まれた旧デザイン専用だったため削除した(2026-10)。今はホーム
# モニター自体がクリック領域で、その位置・矩形・クリック範囲は
# test_rbm_home_monitor_transition.gd が確かめている。

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
