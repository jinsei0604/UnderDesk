extends GutTest

## Creator内(STEP1〜5、SIMPLE/HARDCORE STEP3の各サブ画面、条件エディタ、覚醒設定)
## に不要な横スクロールが無いことの回帰テスト。
##
## 「横スクロールバーを隠す」ではなく「子コンテンツの最小幅が表示幅を押し広げ
## ない」ことを検証する: 各ScrollContainerについて①horizontal_scroll_modeが
## DISABLED ②子の最小幅が表示幅以内 ③横のスクロール範囲が0、を確認する。
## 縦スクロールは維持されていること(縦に長くなった時だけ使える)も確認する。
## 実GPUでの全画面監査はtools/audit_creator_horizontal_scroll_gpu.gd。

const LONG_NAME := "とても長い名前の行動あいうえおかきくけこ"
const LONG_BOSS_NAME := "とても長い名前のボスあいうえおかきくけこさしすせそたちつてと"

func after_each() -> void:
	await get_tree().process_frame

## 上中央モニターの初期化(_init_battle)は完了前に解放するとエラーになるため、
## 完了を待ってから停止する(test_rbm_window_close_unsaved_confirm.gdと同じ)。
func _make_root(mode: String) -> RBMGameRoot:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	if mode == "advanced":
		root.creator_entry._on_choose_advanced_mode_pressed()
	else:
		root.creator_entry._on_choose_simple_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = LONG_BOSS_NAME
	main.draft.hp = 2000
	main.draft.atk = 100
	main.draft.spd = 50
	main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_skill({"name": LONG_NAME, "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 1.5})
	for character_id in ["hero", "butler", "samurai", "healer"]:
		main.draft.add_party_character(character_id)
	main._refresh()
	await _frames()
	return root

func _frames(n: int = 3) -> void:
	for i in range(n):
		await get_tree().process_frame

func _press(node: Node, button_name: String) -> void:
	var b := node.find_child(button_name, true, false) as Button
	assert_not_null(b, "expected %s" % button_name)
	if b != null:
		b.pressed.emit()
	await _frames()

func _scrolls(root: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	for node in root.find_children("*", "ScrollContainer", true, false):
		if (node as ScrollContainer).is_visible_in_tree():
			found.append(node as ScrollContainer)
	return found

## 可視のScrollContainerすべてで、横スクロールが無効かつ子が表示幅に収まる。
func _assert_fits(root: RBMGameRoot, label: String) -> void:
	await _frames(2)
	var scrolls := _scrolls(root.creator_entry)
	assert_gt(scrolls.size(), 0, "%s: sanity, a visible scroll container exists" % label)
	for scroll in scrolls:
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s: %s must not allow horizontal scrolling" % [label, scroll.name])
		# horizontal_scroll_mode=DISABLEDのScrollContainerは、子の最小幅が大きいと
		# 自身の最小幅ごと広がって親の領域からはみ出す(scroll.size自体が膨らむ)
		# ため、scroll.sizeではなく「親が与えている利用可能幅」と比較する。
		var available := (scroll.get_parent() as Control).size.x
		var child := scroll.get_child(0) as Control
		assert_lte(scroll.size.x, available + 0.5, "%s: %s is %.0f wide but only %.0f is available (content min %.0f)" % [label, scroll.name, scroll.size.x, available, child.get_combined_minimum_size().x])
		assert_lte(child.get_combined_minimum_size().x, available + 0.5, "%s: %s content min width %.0f exceeds the available width %.0f" % [label, scroll.name, child.get_combined_minimum_size().x, available])
		var hbar := scroll.get_h_scroll_bar()
		assert_lte(hbar.max_value - hbar.page, 0.5, "%s: %s has a horizontal scroll range" % [label, scroll.name])
		assert_false(hbar.visible, "%s: %s shows a horizontal scrollbar" % [label, scroll.name])
	# 画面外(x>1280)へはみ出す可視Controlが無い(スクロール/クリップの内側は除く)。
	for node in root.creator_entry.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.size.x <= 0.0 or c.size.y <= 0.0:
			continue
		if _inside_scroll_or_clip(c):
			continue
		assert_lte(c.get_global_rect().end.x, 1280.0 + 1.0, "%s: %s extends past the right edge" % [label, c.name])

func _inside_scroll_or_clip(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			return true
		p = p.get_parent()
	return false

func _advanced(main: RBMCreatorMain) -> RBMCreatorStep4ActionPatterns:
	return (main._step_views[2] as RBMCreatorStep4)._advanced_view

## カード（ターン・行動・既存の行動）を押す（2026-10-28 の HARDCORE の画面はカードを押して開く）。
func _click(node: Node, card_name: String) -> void:
	var card := node.find_child(card_name, true, false) as Control
	assert_not_null(card, "expected card %s" % card_name)
	if card != null:
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		card.gui_input.emit(release)
	await _frames()

## 長い名前の行動で、確定・使用率で抽選・条件で分岐のターンを1つずつ入れる。
func _add_turns_with_long_names(main: RBMCreatorMain) -> void:
	var ids := []
	for skill in main.draft.skills:
		ids.append(str(skill.get("skill_id", "")))
	main.draft.add_turn_action({"mode": "fixed", "entries": [{"skill_id": ids[1]}]})
	main.draft.add_turn_action({"mode": "random", "entries": [{"skill_id": ids[0], "weight": 50.0}, {"skill_id": ids[1], "weight": 50.0}]})
	main.draft.add_turn_action({"mode": "conditional", "entries": [{"skill_id": ids[1], "conditions": [{"type": "last_boss_skill", "skill_id": ids[1]}, {"type": "hp_between", "percent_min": 10.0, "percent_max": 60.0}], "condition_logic": "OR"}], "else_skill_id": ids[1]})

# ---------------------------------------------------------------------------
# STEP1〜5(SIMPLE/HARDCORE、長いボス名)
# ---------------------------------------------------------------------------

func test_steps_1_to_5_fit_in_both_modes_with_long_names() -> void:
	for mode in ["advanced", "simple"]:
		var root := await _make_root(mode)
		var main: RBMCreatorMain = root.creator_entry.main
		for step in [1, 2, 3, 4, 5]:
			main.go_to_step(step)
			await _frames()
			await _assert_fits(root, "%s STEP%d" % [mode, step])
		root.free()
		await _frames(1)

## 2026-10-17 STEP4 刷新（案C）: 編成の4つの枠と5人の仲間の札が、中央の欄の幅に収まる（横スクロール無し）。
func test_step4_formation_and_bench_share_the_width_without_a_horizontal_scroll() -> void:
	var root := await _make_root("advanced")
	var main: RBMCreatorMain = root.creator_entry.main
	main.go_to_step(main.party_step())
	await _frames()
	var party := main._step_views[3] as RBMCreatorStep5Party
	var canvas := party.find_child("PartyStepCanvas", true, false) as Control
	var area := canvas.get_global_rect()
	assert_eq(main.draft.party_character_ids.size(), 4, "sanity: 4人の編成")
	for i in range(4):
		var slot := party.find_child("FormationSlot_%d" % i, true, false) as Control
		assert_not_null(slot)
		assert_gte(slot.get_global_rect().position.x, area.position.x - 0.5, "slot %d starts inside the visible area" % i)
		assert_lte(slot.get_global_rect().end.x, area.end.x + 0.5, "slot %d ends inside the visible area" % i)
	for id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		var tile := party.find_child("SelectCharacterButton_%s" % id, true, false) as Control
		assert_not_null(tile)
		assert_lte(tile.get_global_rect().end.x, area.end.x + 0.5, "bench %s ends inside the visible area" % id)
	await _press(party, "StatusEditButton")
	await _press(party, "PerformanceTabButton")
	await _assert_fits(root, "party performance tab")
	await _press(party, "SkillsTabButton")
	await _press(party, "EditPartySkillsButton_hero")
	await _assert_fits(root, "party skills edit")

# ---------------------------------------------------------------------------
# HARDCORE STEP3
# ---------------------------------------------------------------------------

func test_advanced_step3_forms_fit_for_every_action_type() -> void:
	var root := await _make_root("advanced")
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.appearance_id = "appearance_dragon"  # 覚醒を追加できる外見
	main.go_to_step(3)
	await _frames()
	var adv := _advanced(main)
	await _assert_fits(root, "list (empty)")
	_add_turns_with_long_names(main)
	main.draft.add_scripted_action(3, str(main.draft.skills[1].get("skill_id", "")), "turn_start_interrupt")
	adv.refresh()
	await _assert_fits(root, "list")

	await _press(adv, "AddTurnButton")
	await _press(adv, "AddTurnEntryButton")
	await _press(adv, "AddChoiceCreateNewButton")
	adv._form._name_edit.text = LONG_NAME
	for type_id in RBMActionEditorForm.TYPE_IDS:
		if type_id == RBMActionEditorForm.AWAKENING:
			continue  # 新しく作る行動は覚醒にならない（覚醒は覚醒の見出しから作る）
		adv._form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(type_id))
		adv._form._on_type_selected(adv._form._type_option.selected)
		await _frames()
		await _assert_fits(root, "new form %s" % type_id)
	await _press(adv, "EntryCancelButton")
	await _press(adv, "TurnCancelButton")
	# 覚醒: 自己強化+HP回復の両ブロックを開いた最も横幅を使う状態。
	await _press(adv, "AddAwakeningButton")
	await _press(adv._form, "AwakeningAddBuffButton")
	await _press(adv._form, "AwakeningAddHealButton")
	await _assert_fits(root, "awakening buff+heal")

func test_advanced_step3_every_condition_type_fits_including_long_names() -> void:
	var root := await _make_root("advanced")
	var main: RBMCreatorMain = root.creator_entry.main
	main.go_to_step(3)
	await _frames()
	var adv := _advanced(main)
	await _press(adv, "AddTurnButton")
	await _press(adv, "TurnModeButton_conditional")
	await _press(adv, "AddTurnEntryButton")
	await _press(adv, "AddChoiceCreateNewButton")
	adv._form._name_edit.text = LONG_NAME
	await _press(adv, "AddConditionButton")
	for condition_type in RBMActionPatternRules.NORMAL_ACTION_UI_CONDITION_TYPES:
		adv._select_condition_type(condition_type)
		await _assert_fits(root, "condition %s" % condition_type)
	# 一番長いカテゴリ名（特定キャラクターの状態）とキャラクター名の条件行を積む。
	adv._select_condition_type("character_downed")
	adv._condition_character_option.select(1)
	adv._condition_character_option.item_selected.emit(1)
	for i in range(3):
		await _press(adv, "AddConditionButton")
	await _assert_fits(root, "stacked conditions")
	# ターンの設定へ戻ると、長い条件文の行のカードが並ぶ。
	await _press(adv, "EntryConfirmButton")
	await _assert_fits(root, "conditional turn with long rows")

func test_advanced_step3_awakening_conditions_and_edit_screens_fit() -> void:
	var root := await _make_root("advanced")
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.appearance_id = "appearance_dragon"
	main.go_to_step(3)
	await _frames()
	var adv := _advanced(main)
	adv.refresh()
	await _press(adv, "AddAwakeningButton")
	await _press(adv._form, "AwakeningAddHealButton")
	await _press(adv, "AddConditionButton")
	for condition_type in RBMActionPatternRules.AWAKENING_UI_CONDITION_TYPES:
		adv._select_condition_type(condition_type)
		await _assert_fits(root, "awakening condition %s" % condition_type)
	await _press(adv, "EntryConfirmButton")
	await _click(adv, "AwakeningCardButton")
	await _assert_fits(root, "awakening edit")
	await _press(adv, "EntryCancelButton")

	# 長い名前の行動のターン・行動の詳細・性能の編集、使用率で抽選する候補。
	_add_turns_with_long_names(main)
	adv.refresh()
	await _click(adv, "TurnCard_0")
	await _assert_fits(root, "turn with a long name")
	await _click(adv, "TurnEntryCard_0")
	await _assert_fits(root, "action detail with a long name")
	await _press(adv, "EntryEditPerformanceButton")
	await _assert_fits(root, "edit performance")
	await _press(adv, "CancelActionButton")
	await _press(adv, "EntryCancelButton")
	await _press(adv, "TurnCancelButton")
	await _click(adv, "TurnCard_1")
	await _assert_fits(root, "random turn with a long name")
	await _click(adv, "TurnEntryCard_1")
	await _assert_fits(root, "random candidate detail")
	await _press(adv, "EntryCancelButton")
	await _press(adv, "TurnCancelButton")
	await _click(adv, "TurnCard_2")
	await _assert_fits(root, "conditional turn with long rows")

# ---------------------------------------------------------------------------
# SIMPLE STEP3
# ---------------------------------------------------------------------------

func test_simple_step3_form_fits() -> void:
	var root := await _make_root("simple")
	var main: RBMCreatorMain = root.creator_entry.main
	main.go_to_step(3)
	await _frames()
	await _assert_fits(root, "simple list")
	var simple: RBMCreatorStep4Actions = (main._step_views[2] as RBMCreatorStep4)._simple_view
	await _press(simple, "AddNormalActionButton")
	simple._form._name_edit.text = LONG_NAME
	for type_id in RBMActionEditorForm.TYPE_IDS:
		if type_id == RBMActionEditorForm.AWAKENING:
			continue
		simple._form._type_option.select(RBMActionEditorForm.TYPE_IDS.find(type_id))
		simple._form._on_type_selected(simple._form._type_option.selected)
		await _assert_fits(root, "simple new form %s" % type_id)

# ---------------------------------------------------------------------------
# 縦スクロールは維持(縦に長くなった時だけ使え、横には動かない)
# ---------------------------------------------------------------------------

func test_vertical_scroll_is_kept_and_horizontal_never_moves() -> void:
	var root := await _make_root("advanced")
	var main: RBMCreatorMain = root.creator_entry.main
	main.go_to_step(3)
	await _frames()
	var adv := _advanced(main)
	var scroll: ScrollContainer = adv._scroll_container
	assert_ne(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "vertical scrolling stays available")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)

	await _press(adv, "AddTurnButton")
	await _press(adv, "TurnModeButton_conditional")
	await _press(adv, "AddTurnEntryButton")
	await _press(adv, "AddChoiceCreateNewButton")
	for i in range(12):
		await _press(adv, "AddConditionButton")
	await _assert_fits(root, "12 conditions")
	var vbar := scroll.get_v_scroll_bar()
	assert_gt(vbar.max_value - vbar.page, 0.5, "content taller than the viewport scrolls vertically")

	scroll.scroll_horizontal = 500
	await _frames()
	assert_eq(scroll.scroll_horizontal, 0, "horizontal scrolling (wheel/shift+wheel/drag) never moves the content")
	scroll.scroll_vertical = 100
	await _frames()
	assert_gt(scroll.scroll_vertical, 0, "vertical scrolling still works")

