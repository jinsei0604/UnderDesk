extends GutTest

## Phase 3.5 Step 4 — 戦闘UI・情報表示 第一次完成、回帰テスト。
##
## 新レイアウト（戦場／行動順＋最新戦闘情報／味方ステータス＋コマンド）・
## 味方/ボス詳細ウィンドウ（CHALLENGEの非公開情報保護を最優先で検証）・
## 行動順・スキルUI（一覧+詳細）・累積ログ（SP増減/弱点耐性倍率を出さない・
## REWINDで未来側が残らない）・「○○の番です」の削除・CHALLENGEに
## REWINDが存在しないこと、をTEST/Clear Check/CHALLENGEの3画面で直接検証
## する。

const TEST_DIR := "user://bossmaker_test_phase35_step4/stages"

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

func _definition_with_hero_and_butler() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "Step4テストボス"
	draft.hp = 999999
	draft.atk = 1
	draft.spd = 1
	draft.add_party_character("hero")
	draft.add_party_character("butler")
	return draft.to_definition()

## 弱点/耐性のログ表示検証用: ボスをICE弱点にし、butler_ice_boltで確実に
## 「弱点！」を発火させる。
func _definition_with_ice_weak_boss() -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "氷弱点ボス"
	draft.hp = 999999
	draft.atk = 1
	draft.spd = 1
	draft.weak_attributes = ["ICE"]
	draft.add_party_character("butler")
	return draft.to_definition()

func _new_main() -> RBMCreatorMain:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	await get_tree().process_frame
	return main

func _new_challenge_view() -> RBMChallengeBattleView:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	return view

# =============================================================================
# A. 存在／レイアウト
# =============================================================================

func test_new_battle_ui_pieces_exist_and_have_real_size_in_all_three_modes() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)
	var challenge_view := await _new_challenge_view()
	challenge_view.start_battle(definition)

	for view in [main._test_battle_view, main._clear_check_view, challenge_view]:
		assert_not_null(view._battlefield, "%s: battlefield must exist" % view.get_class())
		assert_not_null(view._turn_order_panel, "%s: turn order panel must exist" % view.get_class())
		assert_true(view._turn_order_panel is VBoxContainer, "%s: turn order must be a vertical list, not horizontal" % view.get_class())
		assert_not_null(view._party_rows, "%s: party status row must exist" % view.get_class())
		assert_not_null(view._command_area, "%s: command area must exist" % view.get_class())
		assert_not_null(view.find_child("LogButton", true, false), "%s: a LOG button must exist" % view.get_class())
		assert_not_null(view.find_child("LogWindowOverlay", true, false), "%s: a LOG window overlay must exist" % view.get_class())
		assert_not_null(view.find_child("AllyDetailOverlay", true, false), "%s: an ally detail overlay must exist" % view.get_class())
		assert_not_null(view.find_child("BossDetailOverlay", true, false), "%s: a boss detail overlay must exist" % view.get_class())

func test_current_actor_turn_text_is_never_shown_anywhere() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)
	var challenge_view := await _new_challenge_view()
	challenge_view.start_battle(definition)

	for view in [main._test_battle_view, main._clear_check_view, challenge_view]:
		assert_false(view.has_method("_current_actor_label"), "sanity")
		# 全Labelのtextを走査し「の番です」が一切出ないことを確認する。
		var stack: Array = [view]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is Label:
				assert_false((node as Label).text.contains("の番です"), "%s: found forbidden turn-announcement text in %s" % [view.get_class(), node.name])
			for child in node.get_children():
				stack.append(child)

## §18/§24: CHALLENGEにはREWINDが一切存在しない——REWINDボタン/一覧に相当
## するNodeが1つも無いこと、REWIND用のメソッド(rewind_to)自体が存在しない
## ことの両方を確認する。
func test_challenge_has_no_rewind_ui_or_api() -> void:
	var challenge_view := await _new_challenge_view()
	challenge_view.start_battle(_definition_with_hero_and_butler())
	assert_null(challenge_view.find_child("RewindList", true, false), "CHALLENGE must not have a rewind list")
	assert_null(challenge_view.find_child("*Rewind*", true, false), "CHALLENGE must not have any rewind-named node")
	assert_false(challenge_view.has_method("rewind_to"), "CHALLENGE battle view must not expose a rewind_to() API")

# =============================================================================
# B. 味方詳細ウィンドウ
# =============================================================================

func test_ally_detail_shows_real_stats_and_no_state_when_idle() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var butler: RBMUnit = view.session.battle.party[1]

	view.open_ally_detail(butler.id)
	assert_true((view._ally_detail_overlay["overlay"] as Control).visible, "clicking a card must open the ally detail overlay")
	assert_eq((view._ally_detail_overlay["title_label"] as Label).text, butler.display_name)
	var content: Control = view._ally_detail_overlay["content"]
	var content_text := _all_label_text(content)
	assert_true(content_text.contains("HP　%d / %d" % [butler.hp, butler.max_hp]), "HP must show real numbers: %s" % content_text)
	assert_true(content_text.contains("SP　%d / %d" % [butler.sp, butler.max_sp]), "SP must show real numbers: %s" % content_text)
	assert_true(content_text.contains("ATK　%d" % butler.atk), content_text)
	assert_true(content_text.contains("SPD　%d" % butler.spd), content_text)
	assert_true(content_text.contains("現在の状態：なし"), "no active state must show なし, not raw internal field names: %s" % content_text)

## 防御を選んだ直後、味方詳細に「防御」状態が人間可読な文字列で出ること。
func test_ally_detail_shows_defending_state_after_choosing_defend() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var butler: RBMUnit = view.session.battle.party[1]
	assert_eq(view.session.pending_ally_id(), butler.id, "sanity: butler acts first")

	_btn(view, "DefendButton").pressed.emit()
	view.open_ally_detail(butler.id)
	var content_text := _all_label_text(view._ally_detail_overlay["content"])
	assert_true(content_text.contains("防御"), "defending state must be shown in Japanese: %s" % content_text)
	assert_false(content_text.contains("is_defending"), "internal field name must never leak: %s" % content_text)

## §6: 詳細ウィンドウが開いている間、背後のコマンド操作を誤操作できない
## ようにする——overlay自身がmouse_filter=STOPで全画面を覆っていることを
## 構造的に確認する（headless環境には実マウスイベントが無いため、実際の
## クリックブロックはこの構造的事実——「全画面を覆う、かつクリックを吸収
## する」設定——によって保証されることを直接検証する）。
func test_ally_detail_overlay_blocks_background_input_structurally() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var overlay: Control = view._ally_detail_overlay["overlay"]
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP, "the overlay must consume all mouse input while open")
	assert_eq(overlay.anchor_left, 0.0)
	assert_eq(overlay.anchor_top, 0.0)
	assert_eq(overlay.anchor_right, 1.0)
	assert_eq(overlay.anchor_bottom, 1.0)
	var panel: Control = view._ally_detail_overlay["panel"]
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the inner panel must also stop clicks so they don't fall through to the overlay's own close-on-click-outside handler")
	# overlayは_command_areaより後にツリーへ追加されている（=前面に描画・
	# 入力優先）ことを兄弟インデックスで確認する。
	var command_area_index := view._command_area.get_index()
	var overlay_index := overlay.get_index()
	assert_gt(overlay_index if overlay.get_parent() == view else 999999, -1, "sanity")

func test_ally_detail_close_button_and_outside_click_both_close_it() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	view.open_ally_detail(view.session.battle.party[1].id)
	assert_true((view._ally_detail_overlay["overlay"] as Control).visible, "sanity")
	(view._ally_detail_overlay["close_button"] as Button).pressed.emit()
	assert_false((view._ally_detail_overlay["overlay"] as Control).visible, "× button must close the detail window")

	view.open_ally_detail(view.session.battle.party[1].id)
	var overlay: Control = view._ally_detail_overlay["overlay"]
	var fake_click := InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	overlay.gui_input.emit(fake_click)
	assert_false(overlay.visible, "a click that reaches the overlay itself (outside the inner panel) must close it")

func _all_label_text(root: Node) -> String:
	var parts: Array[String] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			parts.append((node as Label).text)
		for child in node.get_children():
			stack.append(child)
	return "\n".join(parts)

# =============================================================================
# C. ボス詳細ウィンドウ（非公開情報漏えいテストを優先、§5/§18）
# =============================================================================

func test_boss_detail_shows_real_values_in_test_and_clear_check() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	main._clear_check_view.open(main.draft)
	main._clear_check_view.start_battle(definition, 1)

	for view in [main._test_battle_view, main._clear_check_view]:
		view.open_boss_detail()
		var content_text := _all_label_text(view._boss_detail_overlay["content"])
		var boss: RBMUnit = view.session.battle.boss
		assert_true(content_text.contains("HP　%d / %d" % [boss.hp, boss.max_hp]), "%s: TEST/Clear Check must always show the real boss HP: %s" % [view.get_class(), content_text])
		assert_true(content_text.contains("ATK　%d" % boss.atk), content_text)
		assert_true(content_text.contains("SPD　%d" % boss.spd), content_text)
		assert_false(content_text.contains("？？？"), "%s: TEST/Clear Check is an author-facing view and must never hide anything" % view.get_class())

## 最重要: CHALLENGEで全項目を非公開にした場合、ボス詳細ウィンドウに実HPや
## 実ATK/実SPD/実弱点/実耐性が一切出ないこと（新しい詳細ウィンドウを追加
## したことによって、これまで非公開だった情報が漏れないことの直接確認）。
func test_boss_detail_hides_all_fields_when_challenge_visibility_is_fully_hidden() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "非公開ボス"
	draft.hp = 12345
	draft.atk = 678
	draft.spd = 90
	draft.weak_attributes = ["FIRE"]
	draft.resist_attributes = ["ICE"]
	draft.add_party_character("hero")
	draft.set_all_challenge_info_visible(false)
	var definition := draft.to_definition()

	var view := await _new_challenge_view()
	view.start_battle(definition, draft.challenge_info_visibility)
	view.open_boss_detail()
	var content_text := _all_label_text(view._boss_detail_overlay["content"])

	assert_false(content_text.contains("12345"), "real HP must never leak when hp visibility is hidden: %s" % content_text)
	assert_false(content_text.contains("678"), "real ATK must never leak when atk visibility is hidden: %s" % content_text)
	assert_false(content_text.contains("90"), "real SPD must never leak when spd visibility is hidden: %s" % content_text)
	assert_false(content_text.contains("炎"), "real weak attribute must never leak when hidden: %s" % content_text)
	assert_false(content_text.contains("氷"), "real resist attribute must never leak when hidden: %s" % content_text)
	assert_true(content_text.contains("？？？"), "hidden fields must show ？？？ placeholders: %s" % content_text)

## 個別項目単位（HPだけ非公開、ATK/SPDは公開）でも正しく混在表示できること。
func test_boss_detail_respects_per_field_challenge_visibility() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "部分非公開ボス"
	draft.hp = 5555
	draft.atk = 111
	draft.spd = 22
	draft.add_party_character("hero")
	draft.set_challenge_info_visible("hp", false)
	var definition := draft.to_definition()

	var view := await _new_challenge_view()
	view.start_battle(definition, draft.challenge_info_visibility)
	view.open_boss_detail()
	var content_text := _all_label_text(view._boss_detail_overlay["content"])
	assert_false(content_text.contains("5555"), "hidden HP must not leak: %s" % content_text)
	assert_true(content_text.contains("ATK　111"), "visible ATK must show its real value: %s" % content_text)
	assert_true(content_text.contains("SPD　22"), "visible SPD must show its real value: %s" % content_text)

## §2: 通常の戦場表示（_boss_label、常時表示される部分）にはボスHPを一切
## 常設しない——詳細ウィンドウでのみ確認できる。
func test_boss_hp_is_never_shown_in_the_always_visible_battlefield_label() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var boss_label_text := main._test_battle_view._boss_label.text
	assert_false(boss_label_text.contains("HP"), "the always-visible boss label must not carry a standing HP readout: %s" % boss_label_text)
	assert_true(boss_label_text.contains("ターン"), "sanity: turn number itself may still be shown constantly")

# =============================================================================
# D. 行動順
# =============================================================================

func test_turn_order_reflects_real_battle_state_not_a_naive_fixed_list() -> void:
	var definition := _definition_with_hero_and_butler()
	var start_result := RBMDefinitionLoader.start_battle(definition, 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()

	var entries := RBMBattleUiKit.turn_order_entries(battle)
	assert_eq(entries.size(), 3, "sanity: butler+hero+boss")
	assert_eq(entries[0]["display_name"], battle.party[1].display_name, "sanity: butler(spd120) is first")
	assert_eq(entries[0]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_CURRENT, "the currently pending unit must be marked current")
	assert_eq(entries[1]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_UPCOMING, "hero has not acted yet this round")
	assert_eq(entries[2]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_UPCOMING, "boss has not acted yet this round")

	battle.resolve_pending_ally_action({"type": "attack"})
	battle.advance_to_next_decision()
	entries = RBMBattleUiKit.turn_order_entries(battle)
	assert_eq(entries[0]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_ACTED, "butler must now show as already acted")
	assert_eq(entries[1]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_CURRENT, "hero must now be the pending unit")

## 同SPDタイブレーク（味方がボスより先）が行動順表示にも正しく反映される
## こと。
func test_turn_order_tie_break_favors_ally_over_boss_on_equal_spd() -> void:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = "同速ボス"
	draft.hp = 999999
	draft.atk = 1
	draft.spd = 100
	draft.add_party_character("hero")  # heroの既定spdは100（butler=120/spd比較用の共通仕様）
	var definition := draft.to_definition()
	var start_result := RBMDefinitionLoader.start_battle(definition, 1)
	var battle: RBMBattle = start_result["battle"]
	battle.advance_to_next_decision()
	var entries := RBMBattleUiKit.turn_order_entries(battle)
	assert_false(bool(entries[0]["is_boss"]), "on equal SPD, the ally must be listed before the boss")
	assert_true(bool(entries[1]["is_boss"]))

## Phase 3.5 UI統一§20でturn order行を「単なるLabel」から「PanelContainer
## （現在行動中の行だけ銅アクセント枠）＋インジケータ/名前の2つのLabelを
## 横に並べた構造」へ再構成した。この行の実際のテキストを結合して読む
## ヘルパー——行の型自体（PanelContainer化）は見た目のみの変更であり、
## 「▶で始まる／減光される」という元のテストが検証していた振る舞い自体は
## 完全に維持されている。
func _turn_order_row_text(row: Control) -> String:
	var content: Control = row.get_child(0)
	var parts: Array[String] = []
	for child in content.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "".join(parts)

func test_turn_order_panel_ui_renders_current_marker_and_dims_acted_units() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var list: Control = view._turn_order_panel.get_node("TurnOrderList")
	assert_eq(list.get_child_count(), 3, "sanity: 3 combatants")
	var first_row := list.get_child(0) as Control
	assert_true(_turn_order_row_text(first_row).begins_with("▶"), "the current unit's row must be marked with ▶: %s" % _turn_order_row_text(first_row))

	_btn(view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	var list2: Control = view._turn_order_panel.get_node("TurnOrderList")
	var butler_row := list2.get_child(0) as Control
	assert_false(_turn_order_row_text(butler_row).begins_with("▶"), "butler already acted, must no longer show ▶: %s" % _turn_order_row_text(butler_row))
	assert_lt(butler_row.modulate.a, 1.0, "an already-acted row must be visually dimmed")

# =============================================================================
# E. コマンド（スキル一覧・スキル詳細・対象キャンセル）
# =============================================================================

func test_skill_list_opens_shows_rows_with_sp_and_returns_via_back_button() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view

	assert_true(view._main_command_row.visible, "sanity: main command row starts visible")
	assert_false(view._skill_list_panel.visible, "sanity: skill list starts hidden")
	_btn(view, "OpenSkillListButton").pressed.emit()
	assert_false(view._main_command_row.visible, "opening the skill list must hide the main command row")
	assert_true(view._skill_list_panel.visible)
	var skill_button := _btn(view, "SkillButton_butler_ice_bolt")
	assert_true(skill_button.text.contains("SP 15"), "skill row must show its SP cost: %s" % skill_button.text)

	_btn(view, "SkillListBackButton").pressed.emit()
	assert_true(view._main_command_row.visible, "戻る must return to the main command row")
	assert_false(view._skill_list_panel.visible)

func test_skill_detail_shows_real_master_data_and_updates_on_hover() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	_btn(view, "OpenSkillListButton").pressed.emit()

	var bolt_button := _btn(view, "SkillButton_butler_ice_bolt")
	bolt_button.mouse_entered.emit()
	var detail_text: String = view._skill_detail_label.text
	assert_true(detail_text.contains("氷属性単体魔法"), detail_text)
	assert_true(detail_text.contains("消費SP：15"), detail_text)
	assert_true(detail_text.contains("威力："), detail_text)
	assert_true(detail_text.contains("氷"), "attribute must be shown in Japanese: %s" % detail_text)

	var storm_button := _btn(view, "SkillButton_butler_ice_storm")
	storm_button.mouse_entered.emit()
	assert_true(view._skill_detail_label.text.contains("氷属性全体魔法"), "hovering a different skill must update the detail panel")

## §17: 対象選択のキャンセルは自然にスキル選択へ戻る（メインコマンド行では
## なく）。
func test_target_picker_cancel_returns_to_skill_list_not_main_row() -> void:
	var definition := _definition_with_hero_and_butler()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var butler: RBMUnit = view.session.battle.party[1]
	butler.sp = butler.max_sp
	view.refresh()
	await get_tree().process_frame

	_btn(view, "OpenSkillListButton").pressed.emit()
	_btn(view, "SkillButton_butler_sp_gift").pressed.emit()
	assert_true(view._target_picker.visible, "sp_recover_single_no_self must open the target picker")
	assert_false(view._skill_list_panel.visible)

	_btn(view, "TargetPickerBackButton").pressed.emit()
	assert_false(view._target_picker.visible)
	assert_true(view._skill_list_panel.visible, "cancelling target selection must return to the skill list, not the main command row")
	assert_false(view._main_command_row.visible)

# =============================================================================
# F. ログ（最新戦闘情報／累積ログ）
# =============================================================================

func test_log_window_accumulates_turn_grouped_history_and_hides_internal_tokens() -> void:
	var definition := _definition_with_ice_weak_boss()
	var main := await _new_main()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view

	_btn(view, "OpenSkillListButton").pressed.emit()
	_btn(view, "SkillButton_butler_ice_bolt").pressed.emit()
	await get_tree().process_frame

	# 最新戦闘情報: 弱点！が出ること、内部トークンが出ないこと。
	var latest := view._log_label.text
	assert_true(latest.contains("弱点！"), "the ice attack against an ice-weak boss must show 弱点！: %s" % latest)
	assert_false(latest.contains("×1.2"), "the weakness multiplier itself must never be shown: %s" % latest)
	assert_false(latest.contains("SP -"), "SP deltas must never be shown in latest info: %s" % latest)

	view.open_log_window()
	var log_text := view._log_window_body_label.text
	assert_true(log_text.contains("TURN 1"), "the cumulative log must be grouped by turn: %s" % log_text)
	assert_true(log_text.contains("弱点！"), log_text)
	assert_true(log_text.contains("氷属性単体魔法"), log_text)
	for raw_token in ["damage", "×1.2", "×0.8", "SP -15", "SP+", "sp_cost", "actor:"]:
		assert_false(log_text.contains(raw_token), "the log window must never leak the raw token '%s': %s" % [raw_token, log_text])

func test_log_and_latest_info_are_cleared_on_start_and_retry() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	_btn(main._test_battle_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main._test_battle_view._log_label.text.is_empty(), "sanity")
	assert_false(main._test_battle_view._battle_log_history.is_empty(), "sanity: cumulative history has entries")

	main._test_battle_view.retry()
	assert_eq(main._test_battle_view._log_label.text, "")
	assert_true(main._test_battle_view._battle_log_history.is_empty(), "retry must also clear the cumulative log history")

	_btn(main._test_battle_view, "AttackButton").pressed.emit()
	await get_tree().process_frame
	assert_false(main._test_battle_view._battle_log_history.is_empty(), "sanity")
	assert_true(main._test_battle_view.start(definition, 2), "sanity")
	assert_eq(main._test_battle_view._log_label.text, "")
	assert_true(main._test_battle_view._battle_log_history.is_empty(), "a fresh start() must also clear the cumulative log history")

# =============================================================================
# G. REWIND（TEST/Clear Check、§18）
# =============================================================================

## 「Turn 5からTurn 3へ戻した場合、巻き戻した未来側のログが残らない」ことの
## 直接確認——累積ログに複数ターン分のentryを積んだ状態からrewindし、
## rewind先より後のturnの行が一切残っていないことを検証する。
func test_rewind_removes_future_side_log_entries_but_keeps_past_ones() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view

	# 3ターン分、両方のキャラの通常攻撃で進める（boss.atk=1でほぼ死なない
	# ダメージのため、party側は安全に何ラウンドも継続できる）。
	for i in range(6):
		if view.session.battle.battle_over:
			break
		var pending_id := view.session.pending_ally_id()
		if pending_id == -1:
			break
		view.act_attack(pending_id)
		await get_tree().process_frame

	assert_gt(view.session.battle.current_turn, 1, "sanity: multiple turns really elapsed")
	var reachable := view.session.reachable_turns()
	assert_true(reachable.size() >= 2, "sanity: at least 2 reachable turns to rewind between")
	var target_turn: int = reachable[0]

	view.rewind_to(target_turn)
	for entry in view._battle_log_history:
		assert_lt(int(entry.get("turn", 1)), target_turn, "no log entry from turn %d or later must survive a rewind to turn %d" % [int(entry.get("turn", 1)), target_turn])

	view.open_log_window()
	var log_text := view._log_window_body_label.text
	for turn in reachable:
		if turn >= target_turn and turn != reachable[0]:
			assert_false(log_text.contains("TURN %d\n" % turn) and turn >= target_turn, "sanity: no stray future TURN header")

## REWIND後、HP/SP/行動順/最新戦闘情報が復元された戦闘状態と矛盾しない
## （巻き戻し後にダメージを受ける前のHPへ戻っている等）ことを確認する。
func test_rewind_restores_consistent_hp_sp_and_turn_order_display() -> void:
	var main := await _new_main()
	var definition := _definition_with_hero_and_butler()
	assert_true(main._test_battle_view.start(definition, 1), "sanity")
	var view := main._test_battle_view
	var butler: RBMUnit = view.session.battle.party[1]

	_btn(view, "OpenSkillListButton").pressed.emit()
	_btn(view, "SkillButton_butler_ice_bolt").pressed.emit()
	await get_tree().process_frame
	var sp_after_cast := butler.sp
	assert_lt(sp_after_cast, butler.max_sp, "sanity: SP was really spent")

	assert_true(view.session.reachable_turns().has(1), "sanity")
	view.rewind_to(1)
	assert_eq(butler.sp, butler.max_sp, "REWIND must restore SP to its turn-1 value")
	assert_eq(view.session.battle.current_turn, 1)
	var entries := RBMBattleUiKit.turn_order_entries(view.session.battle)
	assert_eq(entries[0]["status"], RBMBattleUiKit.TURN_ORDER_STATUS_CURRENT, "after rewinding to turn 1, butler must be pending again")
	assert_eq(view._log_label.text, "", "the latest-info panel must not show the undone cast after rewinding past it")
