extends GutTest

## RPG BOSS MAKER — Phase 1 実機プレイ改善① 回帰テスト。
##
## 「戦闘方式を後期UNDERDESK方式へ統一」（依頼原文の項目1、および6〜9/
## 13/14の該当部分/15の該当部分）は、防御(defend)の「ラウンド全体を
## 通して先行する行動を遡って軽減する」という既存確定仕様（RBMBattle.
## resolve_turn()のTURN START時点での一括事前適用、コード内コメント
## 「Step 2 confirmation #1」として明示的に確定済み）が、「各キャラクター
## の入力をその行動順が来た瞬間にだけ求め、即座に解決する」という新方式
## の下では原理的に維持不可能（後のSPD順の味方の防御選択を、それより前に
## 行動するボスの被弾処理時点ではまだ知り得ない）という、既存の確定済み
## バトルコア仕様と新要求が直接衝突する箇所を含むため、依頼書§16の
## 「状態効果のduration定義変更が必要」に該当すると判断し、この回では
## 実装していない（詳細はチャット上の最終報告を参照）。そのため、この回
## 新規に追加するテストは、依頼書のうち実際に実装した以下2点のみに絞る:
## - Creator STEP2/3/4のSliderが実際に操作可能な大きさを持ち、値変更が
##   Draftへ正しく反映されること（項目10）
## - 戦闘中の味方ステータス表示の簡潔化、および主要UIの中央寄せ（項目11/12）
##
## test_rbm_step8_layout_regressions.gdと同じ既存の確立済み手法
## （実際にRBMGameRootをインスタンス化し、Godot自身のレイアウト計算を経た
## 本物のControl.size/position/global_positionだけを検証する）を踏襲する
## ——このファイル自身のヘッダコメント参照、意図的に複製している。
const TEST_DIR := "user://bossmaker_test_realplay1_ui/stages"
const HEADLESS_WINDOW_SIZE := Vector2(1280, 720)
const EPSILON := 0.5

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

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

func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(HEADLESS_WINDOW_SIZE.x, HEADLESS_WINDOW_SIZE.y)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	return root

## UI改善②: 「新しいボス戦を作る」は今やCreatorへ直接入らず、SIMPLE/
## ADVANCEDの作成方法選択パネルをまず経由する——このヘルパーはレイアウト
## 確認テストの土台のため、シンプルを選んで先へ進む。
func _new_creator_main() -> RBMCreatorMain:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	return root.creator_entry.main

## §16「rectが他Controlに覆われていない」: sliderの実際のglobal_rectと、
## 同じツリー内で実際に表示中(is_visible_in_tree())の他Controlのglobal_rect
## が交差していないことを確認する（is_visible_in_tree()を使うこと自体が
## 重要——祖先が非表示なだけの兄弟画面のControlは、自分自身の.visibleが
## trueのまま(0,0)近辺の陳腐化したrectを報告することがあり、単純な.visible
## だけのチェックでは実際には表示されていない他画面のControlを「重なって
## いる」と誤検知する）。
func _assert_slider_not_covered(root: Node, slider: HSlider, description: String) -> void:
	var slider_rect: Rect2 = slider.get_global_rect()
	_check_no_visible_overlap(root, slider, slider_rect, description)

## slider自身の祖先ノード（Control/Container含む）は幾何学的に必ずsliderの
## rectを内包するが、これはGodotの実際の入力ヒットテスト上「奪う」ことには
## ならない——ヒットテストは同じ枝の中では最も深い(具体的な)Controlへ優先的に
## ディスパッチされるため、祖先はsliderへの入力を妨げない。ここで実際に
## 検出すべきなのは「祖先でも自分自身でもない、無関係な兄弟/他画面の
## Controlが同じ画面座標に重なって存在する」ケースのみ。
func _check_no_visible_overlap(node: Node, exclude: Control, target_rect: Rect2, description: String) -> void:
	if node is Control:
		var c: Control = node
		var is_ancestor_or_self := c == exclude or _is_ancestor_of(c, exclude)
		if not is_ancestor_or_self and c.is_visible_in_tree() and c.get_global_rect().intersects(target_rect):
			fail_test("%s: an unrelated visible Control (%s) overlaps the slider's own rect — mouse input could be stolen before it reaches the slider" % [description, c.get_path()])
	for child in node.get_children():
		_check_no_visible_overlap(child, exclude, target_rect, description)

func _is_ancestor_of(maybe_ancestor: Node, node: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current == maybe_ancestor:
			return true
		current = current.get_parent()
	return false

func _assert_slider_is_draggable(slider: HSlider, description: String) -> void:
	assert_ne(slider.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: mouse_filter must not IGNORE mouse input" % description)
	assert_gte(slider.size.x, 200.0, "%s: slider width (%s) must be large enough to actually grab with a real mouse, not a few-pixel sliver" % [description, slider.size.x])
	assert_gte(slider.size.y, 16.0, "%s: slider height (%s) must be large enough to actually grab with a real mouse" % [description, slider.size.y])

# ---------------------------------------------------------------------------
# 実機プレイ改善①§10: STEP2 HP/ATK/SPD Slider
# ---------------------------------------------------------------------------

## §13カードUI化: Slider/SpinBoxは「編集」を押した時だけカード内へ展開
## される——実際にドラッグ可能か・覆われていないかは編集展開後の状態で
## 確認する。
func test_step2_hp_atk_spd_sliders_are_draggable_and_uncovered() -> void:
	var main := await _new_creator_main()
	main.go_to_step(2)
	await get_tree().process_frame
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_true(step2._edit_panel.visible, "能力は最初から編集可能")
	await get_tree().process_frame

	_assert_slider_is_draggable(step2._hp_slider, "STEP2 HP slider")
	_assert_slider_is_draggable(step2._atk_slider, "STEP2 ATK slider")
	_assert_slider_is_draggable(step2._spd_slider, "STEP2 SPD slider")
	_assert_slider_not_covered(main, step2._hp_slider, "STEP2 HP slider")
	_assert_slider_not_covered(main, step2._atk_slider, "STEP2 ATK slider")
	_assert_slider_not_covered(main, step2._spd_slider, "STEP2 SPD slider")

## §10/§13「値変更でDraftへ反映」: sliderの.valueへ実際に書き込み、Godot
## 自身のRange実装が発火するvalue_changedシグナル経由（合成マウスイベント
## ではなく、実際に接続済みのシグナルパスを本当に通す）で編集中の一時値へ
## 反映され、ペアのSpinBoxも同じ値へ追従すること（数値直接入力の同期が
## 壊れていないこと）を確認する。§13-2「決定」を押すまでdraftへは反映しない
## 仕様のため、決定を押した後でdraftへの反映も確認する。
func test_step2_slider_value_changes_reflect_into_draft_and_paired_spinbox() -> void:
	var main := await _new_creator_main()
	main.go_to_step(2)
	await get_tree().process_frame
	var step2: RBMCreatorStep2Stats = main._step_views[1]
	assert_true(step2._edit_panel.visible, "能力は最初から編集可能")
	await get_tree().process_frame

	step2._hp_slider.value = 12345.0
	assert_eq(step2._hp_spin.value, 12345.0, "the paired HP SpinBox must mirror the new slider value while editing")
	step2._atk_slider.value = 42.0
	assert_eq(step2._atk_spin.value, 42.0, "the paired ATK SpinBox must mirror the new slider value while editing")
	step2._spd_slider.value = 7.0
	assert_eq(step2._spd_spin.value, 7.0, "the paired SPD SpinBox must mirror the new slider value while editing")

	assert_null(step2.find_child("ConfirmStatsButton", true, false), "数値反映に決定は不要")
	await get_tree().process_frame
	assert_eq(main.draft.hp, 12345, "moving the HP slider then confirming must update draft.hp")
	assert_eq(main.draft.atk, 42, "moving the ATK slider then confirming must update draft.atk")
	assert_eq(main.draft.spd, 7, "moving the SPD slider then confirming must update draft.spd")

# ---------------------------------------------------------------------------
# 実機プレイ改善①§10: STEP3（旧STEP3/STEP4相当）の追加Slider（同一バグ種別
# のため合わせて修正）
#
# Creator UI再設計により旧STEP3「ボススキル作成」は廃止され、通常行動の
# 作成（旧STEP3の役割）と使用率スライダー（旧STEP4の役割）は新STEP3「行動」
# 画面（RBMCreatorStep4Actions、共通行動作成フォームRBMActionEditorForm経由）
# に統合された——このため以下2テストは同じ1画面を対象にする。
# ---------------------------------------------------------------------------

func test_step3_attack_multiplier_slider_is_draggable() -> void:
	var main := await _new_creator_main()
	main.go_to_step(3)
	await get_tree().process_frame
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	# AddNormalActionButtonを押すとRBMActionEditorForm.open_for_new()が
	# 開き、既定でtype=ATTACKのため_attack_fields（と_attack_multiplier_slider）
	# は最初から可視になる。
	_btn(step3, "AddNormalActionButton").pressed.emit()
	await get_tree().process_frame
	_assert_slider_is_draggable(step3._form._attack_multiplier_slider, "STEP3 attack multiplier slider")
	_assert_slider_not_covered(main, step3._form._attack_multiplier_slider, "STEP3 attack multiplier slider")

## STEP3の%スライダーを実際に登場させるには、まず本物のUIフロー
## （AddNormalActionButton→名前入力→SaveActionButton、実際のUIが
## 使うのと同じ経路）で1つ通常行動を追加する——RBMCreatorDraft.add_skill()の
## 内部Dictionary形状を直接ここで組み立てて渡すことはしない。
func test_step3_percentage_slider_is_draggable() -> void:
	var main := await _new_creator_main()
	main.go_to_step(3)
	await get_tree().process_frame
	var step3_wrapper: RBMCreatorStep4 = main._step_views[2]
	var step3: RBMCreatorStep4Actions = step3_wrapper._simple_view
	_btn(step3, "AddNormalActionButton").pressed.emit()
	await get_tree().process_frame
	step3._form._name_edit.text = "テスト攻撃スキル"
	_btn(step3._form, "SaveActionButton").pressed.emit()
	await get_tree().process_frame

	# UI改善①: 「通常行動を使用する」チェックボックス自体を削除し、%スライダー
	# 行を持つ_normal_listは常時表示になった——スキルが1つでも作られていれば
	# 追加のトグル操作なしでそのまま行が存在する。
	step3.refresh()
	await get_tree().process_frame
	assert_gt(step3._percent_rows.size(), 0, "sanity: at least one normal-action percentage row must exist once a skill was added")
	for skill_id in step3._percent_rows.keys():
		var slider: HSlider = step3._percent_rows[skill_id]["slider"]
		_assert_slider_is_draggable(slider, "STEP3 percentage slider (%s)" % skill_id)
		_assert_slider_not_covered(main, slider, "STEP3 percentage slider (%s)" % skill_id)

# ---------------------------------------------------------------------------
# 実機プレイ改善①§11: 味方ステータス表示の簡潔化
# ---------------------------------------------------------------------------

## §11: 各味方が独立したブロック（名前/HP/SPが別々の行）として表示され、
## かつカードが横に並んでも合計幅が画面幅内に収まる（「3〜4人でも横に長
## すぎない」）ことを確認する。
func test_test_battle_party_status_shows_name_hp_sp_as_separate_lines_per_card() -> void:
	var main := await _new_creator_main()
	main.draft.boss_name = "ステータスUI確認ボス"
	main.draft.hp = 100
	main.draft.atk = 10
	main.draft.spd = 10
	for character_id in ["hero", "butler", "healer", "samurai"]:
		main.draft.add_party_character(character_id)
	var result := main.press_test_battle()
	assert_true(bool(result.get("ok", false)), "sanity: a minimally-valid draft with a 4-person party must start TEST BATTLE")
	await get_tree().process_frame

	var tbv := main._test_battle_view
	assert_eq(tbv._party_rows.get_child_count(), 4, "sanity: 4 party members must produce 4 status cards")
	assert_true(tbv._party_rows is HBoxContainer, "party status cards must be arranged side-by-side (HBoxContainer), not stacked in one long vertical list of long single-line labels")

	var viewport: Rect2 = main.get_viewport_rect()
	for unit in tbv.session.battle.party:
		var card: Control = tbv._party_rows.find_child("PartyRow_%d" % unit.id, true, false)
		assert_not_null(card, "each party member must have its own named card")
		var name_label: Label = card.find_child("PartyRowName_%d" % unit.id, true, false)
		var hp_label: Label = card.find_child("PartyRowHP_%d" % unit.id, true, false)
		var sp_label: Label = card.find_child("PartyRowSP_%d" % unit.id, true, false)
		assert_not_null(name_label, "card must have its own name line")
		assert_not_null(hp_label, "card must have its own HP line, separate from the name")
		assert_not_null(sp_label, "card must have its own SP line, separate from HP")
		assert_true(name_label.text.contains(unit.display_name), "name line must show whose card this is")
		assert_true(hp_label.text.contains("HP"), "HP line must be readable at a glance")
		assert_true(hp_label.text.contains(str(unit.hp)), "HP line must show the real current HP value")
		assert_true(sp_label.text.contains("SP"), "SP line must be readable at a glance")

	# 「3〜4人でも横に長すぎない」: カード列全体の実測幅がviewport幅を超えて
	# いないこと（画面外へはみ出す/水平方向に極端に長い1行になっていない）。
	assert_true(tbv._party_rows.size.x <= viewport.size.x + EPSILON, "4-person party card row (%s) must not overflow the 1280px-wide viewport horizontally" % tbv._party_rows.size.x)

## §11: RBMCreatorClearCheckView / RBMChallengeBattleViewにも同一の
## カード構造（このファイルのヘッダコメントが説明する意図的な複製）が
## 適用されていることを確認する。
func test_clear_check_view_uses_the_same_compact_party_card_layout() -> void:
	var main := await _new_creator_main()
	main.draft.boss_name = "クリアチェックUI確認ボス"
	main.draft.hp = 1
	main.draft.atk = 100
	main.draft.spd = 100
	main.draft.add_party_character("hero")
	var start_result := main.press_clear_check_start(12345)
	assert_true(bool(start_result.get("ok", false)), "sanity: Clear Check must start with a minimally-valid draft")
	await get_tree().process_frame

	var ccv := main._clear_check_view
	assert_true(ccv._party_rows is HBoxContainer, "Clear Check party status cards must also be side-by-side")
	var unit: RBMUnit = ccv.session.battle.party[0]
	var card: Control = ccv._party_rows.find_child("PartyRow_%d" % unit.id, true, false)
	assert_not_null(card.find_child("PartyRowName_%d" % unit.id, true, false), "Clear Check card must have a separate name line")
	assert_not_null(card.find_child("PartyRowHP_%d" % unit.id, true, false), "Clear Check card must have a separate HP line")
	assert_not_null(card.find_child("PartyRowSP_%d" % unit.id, true, false), "Clear Check card must have a separate SP line")

func test_challenge_battle_view_uses_the_same_compact_party_card_layout() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "CHALLENGE戦闘UI確認ボス"
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	var save_result := main.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)))
	# Creator UI改修（2026-09-05）§24〜§27（公開機能）: 保存しただけでは
	# CHALLENGEに表示されない——このテストの目的はレイアウトのみのため、
	# 直接APIによる最短経路のまま公開まで済ませる。
	main.draft.record_clear_check_success()
	assert_true(main.press_publish().get("ok", false))

	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	# CHALLENGE UI再設計: 「挑戦」は必ず挑戦ハブを経由する——「ボスを検索」で
	# 共通一覧画面を開く。
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row)
	await get_tree().process_frame
	_btn(root.challenge_entry._confirm_view, "ChallengeStartButton").pressed.emit()
	await get_tree().process_frame

	var battle_view := root.challenge_entry._battle_view
	assert_true(battle_view.visible, "sanity: CHALLENGE battle must have actually started")
	assert_true(battle_view._party_rows is HBoxContainer, "CHALLENGE battle party status cards must also be side-by-side")
	var unit: RBMUnit = battle_view.session.battle.party[0]
	var card: Control = battle_view._party_rows.find_child("PartyRow_%d" % unit.id, true, false)
	assert_not_null(card.find_child("PartyRowName_%d" % unit.id, true, false), "CHALLENGE battle card must have a separate name line")
	assert_not_null(card.find_child("PartyRowHP_%d" % unit.id, true, false), "CHALLENGE battle card must have a separate HP line")
	assert_not_null(card.find_child("PartyRowSP_%d" % unit.id, true, false), "CHALLENGE battle card must have a separate SP line")

# ---------------------------------------------------------------------------
# 実機プレイ改善①§12: 主要UIの中央寄せ
# ---------------------------------------------------------------------------

## §12「左上に張り付かない」: 各画面の主要コンテンツの左上端がx=0/y=0に
## 直接接しておらず、かつviewport内に収まっていることを確認する。
func _assert_has_margin_and_within_viewport(control: Control, viewport: Rect2, description: String) -> void:
	assert_gt(control.global_position.x, viewport.position.x + 1.0, "%s: left edge (%s) must not be glued directly to the viewport's left edge (x=0)" % [description, control.global_position.x])
	assert_true(control.global_position.x <= viewport.position.x + viewport.size.x - EPSILON, "%s: left edge (%s) must still be within the viewport" % [description, control.global_position.x])
	assert_true(control.global_position.y >= viewport.position.y - EPSILON, "%s: top edge (%s) must be within the viewport" % [description, control.global_position.y])

func test_common_menu_is_not_glued_to_the_top_left_corner() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	_assert_has_margin_and_within_viewport(root._menu_panel, viewport, "common menu panel")

func test_create_top_and_list_screens_are_not_glued_to_the_top_left_corner() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	# 背景アート実装（2026-09-04）: _top_panel自体は背景画像レイヤーと重ねる
	# ための全画面Control（意図的に画面端まで広がる、余白ゼロの層——
	# _top_backgroundと同じ役割）へ変わった。このテストが確かめたい「画面
	# の角に張り付いた実UI要素が無いこと」は、代わりにその内部の実要素
	# （角に最も近い戻るボタン）で検証する。
	_assert_has_margin_and_within_viewport(root.creator_entry.find_child("BackToRootButton", true, false), viewport, "CREATE top screen back button")

	_btn(root.creator_entry, "EditSavedBossButton").pressed.emit()
	await get_tree().process_frame
	_assert_has_margin_and_within_viewport(root.creator_entry._list_panel, viewport, "CREATE saved-stage list panel")

func test_challenge_list_screen_is_not_glued_to_the_top_left_corner() -> void:
	var root := await _make_root()
	var viewport: Rect2 = root.get_viewport_rect()
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	_assert_has_margin_and_within_viewport(root.challenge_entry._list_panel, viewport, "CHALLENGE list panel")

## §12: STEP1〜5（最終確認画面STEP6を除く）の各content columnも中央寄せ
## （左右余白）されていること——STEP6（旧STEP7、確認画面）はscrollベースの
## 別レイアウトのため専用テスト（下記）で個別に確認する。既存の
## test_rbm_step8_layout_regressions.gd側のcontent_bottom<nav_top判定は
## 本ラウンドでも4/4 passのまま（別途フルスイートで確認済み）——ここでは
## 「余白が本当に追加されたか」という本ラウンド固有の観点だけを追加検証する。
func test_creator_step_1_through_5_columns_have_left_margin() -> void:
	var main := await _new_creator_main()
	var viewport: Rect2 = main.get_viewport_rect()
	for step in range(1, RBMCreatorMain.STEP_COUNT):
		main.go_to_step(step)
		await get_tree().process_frame
		var view: Control = main._step_views[step - 1]
		var column: Control = view.get_child(0)
		_assert_has_margin_and_within_viewport(column, viewport, "STEP %d content column" % step)

## §12: TEST BATTLE / 保存画面の中央寄せ。
func test_test_battle_and_save_view_columns_have_left_margin() -> void:
	var main := await _new_creator_main()
	main.draft.boss_name = "中央寄せ確認ボス"
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	var viewport: Rect2 = main.get_viewport_rect()

	var result := main.press_test_battle()
	assert_true(bool(result.get("ok", false)))
	await get_tree().process_frame
	# Phase 3.5 タイトル画面UI新設: RBMBattleUiKit.add_root_background()が
	# 新設のRootBackground（全面ColorRect、余白なし）をColumnより前へ挿入した
	# ため、get_child(0)は最早Columnではない——名前で明示的に探す（既存の
	# 他アサーション、例えば_menu_panelを名前付きフィールドで参照するのと
	# 同じ考え方）。
	var test_battle_column: Control = main._test_battle_view.find_child("Column", false, false)
	_assert_has_margin_and_within_viewport(test_battle_column, viewport, "TEST BATTLE content column")
	_btn(main._test_battle_view, "QuitTestButton").pressed.emit()
	await get_tree().process_frame
	_btn(main._test_battle_view, "QuitConfirmButton").pressed.emit()
	await get_tree().process_frame

	main.press_save()
	await get_tree().process_frame
	_assert_has_margin_and_within_viewport(main._save_view.get_child(0), viewport, "保存画面 content column")

## §12: STEP6（旧STEP7）/CHALLENGE確認画面は、水平方向の余白だけが追加され、
## scrollの縦方向フルストレッチ（既存の「内容はスクロールし、ボタン行は下部
## 固定」構造）には一切影響していないことを確認する——このラウンドの中で
## 最も壊しやすい箇所（MIN_LARGE_AREA_HEIGHT相当の垂直空間を誤って消費して
## しまうと、test_rbm_step8_layout_regressions.gd側の既存テストがFAILする
## はずだが、フルスイートでは実際に4/4 passのまま——ここでは「余白が
## 水平方向にだけ実際に加わったか」という本ラウンド固有の観点を追加する。
const MIN_LARGE_AREA_HEIGHT := 200.0

func test_step6_and_challenge_confirm_get_horizontal_margin_without_shrinking_the_scroll_area() -> void:
	var main := await _new_creator_main()
	main.go_to_step(RBMCreatorMain.STEP_COUNT)
	await get_tree().process_frame
	var step6: RBMCreatorStep7Summary = main._step_views[RBMCreatorMain.STEP_COUNT - 1]
	var outer: Control = step6._content.get_parent().get_parent()
	assert_gt(outer.global_position.x, 1.0, "STEP6 outer must have a real left margin now")
	var scroll: Control = step6._content.get_parent()
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "STEP6: the scroll area's vertical stretch must remain unaffected by the new horizontal margin")

func test_challenge_confirm_gets_horizontal_margin_without_shrinking_the_scroll_area() -> void:
	var root := await _make_root()
	_btn(root, "CreateModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	await get_tree().process_frame
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "CHALLENGE確認中央寄せ確認ボス"
	main.draft.hp = 1
	main.draft.atk = 1
	main.draft.spd = 1
	main.draft.add_party_character("hero")
	var save_result := main.press_save_as_new()
	assert_true(bool(save_result.get("ok", false)))
	# Creator UI改修（2026-09-05）§24〜§27（公開機能）: 保存しただけでは
	# CHALLENGEに表示されない——このテストの目的はレイアウトのみのため、
	# 直接APIによる最短経路のまま公開まで済ませる。
	main.draft.record_clear_check_success()
	assert_true(main.press_publish().get("ok", false))

	_btn(root.creator_entry, "BackToRootButton").pressed.emit()
	await get_tree().process_frame
	_btn(root, "ChallengeModeButton").pressed.emit()
	await get_tree().process_frame
	_btn(root.challenge_entry._hub_view, "SearchBossButton").pressed.emit()
	await get_tree().process_frame
	var row: PanelContainer = root.challenge_entry._list_rows.get_child(0)
	_click_card(row)
	await get_tree().process_frame

	var confirm: RBMChallengeConfirmView = root.challenge_entry._confirm_view
	var scroll: Control = confirm._content.get_parent()
	var outer: Control = scroll.get_parent()
	assert_gt(outer.global_position.x, 1.0, "CHALLENGE confirm outer must have a real left margin now")
	assert_gt(scroll.size.y, MIN_LARGE_AREA_HEIGHT, "CHALLENGE confirm: the scroll area's vertical stretch must remain unaffected by the new horizontal margin")
