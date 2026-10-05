extends GutTest

## Creator STEP4（攻略パーティ）が下部の帯（戻る/次へ/作成を終了）に重ならないことの
## 回帰テスト。
##
## 以前はSTEP4の縦並びが上端だけ固定で下へ伸び、タブ領域（320px固定）と合わせて
## ステップ表示領域（1280x720で高さ約540px）を超えていた。表示領域ははみ出しを
## 切り取らないため、キャラクター追加欄・性能調整・スキル編集で下部の帯の上や画面外
## に描かれていた。今はSTEP4全体を縦スクロールで包み、タブ領域は残りの高さ（最小
## 160px）を使う。通常時は全体は動かず、追加欄を開いた時など収まらない時だけ全体が
## 縦にスクロールする。横スクロールは無し。使用可能スキルタブの操作ボタン（編集 /
## 決定・キャンセル）はどのスクロールにも入れず、タブ領域の下に常に表示する。

const PARTY := ["hero", "butler", "samurai", "healer"]

func after_each() -> void:
	await get_tree().process_frame

## 上中央モニターの初期化(_init_battle)は完了前に解放するとエラーになるため、
## 完了を待ってから停止する(test_rbm_creator_no_horizontal_scroll.gdと同じ)。
func _make_root() -> RBMGameRoot:
	get_tree().root.size = Vector2i(1280, 720)
	var root := RBMGameRoot.new()
	add_child_autoqfree(root)
	await get_tree().process_frame
	await get_tree().process_frame
	var ticks := 0
	while not root._top_monitor_battle._initialized and ticks < 300:
		await get_tree().process_frame
		ticks += 1
	root._top_monitor_battle.stop_loop()
	return root

func _open_step4(root: RBMGameRoot, mode: String, party_ids: Array) -> RBMCreatorStep5Party:
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	if mode == "advanced":
		root.creator_entry._on_choose_advanced_mode_pressed()
	else:
		root.creator_entry._on_choose_simple_mode_pressed()
	var main: RBMCreatorMain = root.creator_entry.main
	main.draft.boss_name = "帯の確認"
	for id in party_ids:
		main.draft.add_party_character(id)
	main._refresh()
	main.go_to_step(4)
	await _frames(3)
	var party: RBMCreatorStep5Party = main._step_views[3]
	party.select_character(str(party_ids[0]))
	await _frames(2)
	return party

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _main(root: RBMGameRoot) -> RBMCreatorMain:
	return root.creator_entry.main

func _page(party: RBMCreatorStep5Party) -> ScrollContainer:
	return party.find_child("PartyStepScroll", true, false) as ScrollContainer

func _tab(party: RBMCreatorStep5Party) -> ScrollContainer:
	return party.find_child("SelectedCharacterTabScroll", true, false) as ScrollContainer

func _range(scroll: ScrollContainer) -> float:
	var bar := scroll.get_v_scroll_bar()
	return max(0.0, bar.max_value - bar.page)

func _press(node: Node, button_name: String) -> void:
	var button := node.find_child(button_name, true, false) as Button
	assert_not_null(button, "expected %s" % button_name)
	button.pressed.emit()
	await _frames(2)

func _footer_rect(main: RBMCreatorMain) -> Rect2:
	return main._nav_row.get_global_rect().merge(main._exit_button.get_global_rect())

## 表示中のSTEP4の部品のうち、実際に見える部分（祖先のScrollContainerで切り取った
## 範囲）が下部の帯へ入り込んでいるものの名前。
func _controls_drawn_over_footer(party: RBMCreatorStep5Party, footer: Rect2) -> Array:
	var over := []
	for node in party.find_children("*", "Control", true, false):
		var c := node as Control
		if not c.is_visible_in_tree() or c.size.x <= 0.0 or c.size.y <= 0.0:
			continue
		var visible := c.get_global_rect()
		var ancestor := c.get_parent()
		while ancestor != null and ancestor != party:
			if ancestor is ScrollContainer:
				visible = visible.intersection((ancestor as Control).get_global_rect())
			ancestor = ancestor.get_parent()
		if visible.size.y > 0.5 and visible.intersects(footer):
			over.append(str(c.name))
	return over

func _assert_above_footer(party: RBMCreatorStep5Party, main: RBMCreatorMain, label: String) -> void:
	var footer := _footer_rect(main)
	assert_true(_page(party).get_global_rect().end.y <= footer.position.y + 0.5, "%s: STEP4は下部の帯より上で終わること" % label)
	assert_true(_page(party).clip_contents, "%s: STEP4のはみ出しは帯の上に描かれないこと" % label)
	assert_eq(_controls_drawn_over_footer(party, footer), [], "%s: 表示中の部品が下部の帯へ入り込まないこと" % label)
	for scroll in party.find_children("*", "ScrollContainer", true, false):
		assert_eq((scroll as ScrollContainer).scroll_horizontal, 0, "%s: 横には動かないこと" % label)
	assert_eq(_page(party).horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s: 横スクロールは無し" % label)

func _actions_bar(party: RBMCreatorStep5Party) -> Control:
	return party.find_child("SkillsTabActionsBar", true, false) as Control

## タブ領域の高さ。使用可能スキルタブでは一覧(スクロール)・間の余白・下の操作ボタン行を
## 合わせた高さ(ボタン行はSTEP4の下端に固定のため、画面上の距離ではなく各部の高さの和)。
func _tab_area_height(party: RBMCreatorStep5Party) -> float:
	if _actions_bar(party).is_visible_in_tree():
		return _tab(party).size.y + RBMCreatorStep5Party.CONTENT_BOTTOM_MARGIN_PX + (party.find_child("SkillsTabActions", true, false) as Control).size.y
	return _tab(party).size.y

## 操作ボタンがどのScrollContainerにも入っておらず、最初から全体が見え、下部の帯より上にあること。
func _assert_action_always_visible(party: RBMCreatorStep5Party, main: RBMCreatorMain, button_name: String, label: String) -> void:
	var button := party.find_child(button_name, true, false) as Control
	assert_not_null(button, "%s: %s" % [label, button_name])
	if button == null:
		return
	assert_true(button.is_visible_in_tree(), "%s: %sが表示されていること" % [label, button_name])
	var ancestor := button.get_parent()
	while ancestor != null and ancestor != party:
		assert_false(ancestor is ScrollContainer, "%s: %sはスクロールの中に入れないこと" % [label, button_name])
		ancestor = ancestor.get_parent()
	var rect := button.get_global_rect()
	assert_true(party.get_global_rect().encloses(rect), "%s: %sの全体がSTEP4内に見えること" % [label, button_name])
	assert_true(rect.end.y <= _footer_rect(main).position.y + 0.5, "%s: %sは下部の帯より上にあること" % [label, button_name])

func test_normal_state_fits_without_scrolling_the_whole_step() -> void:
	var root := await _make_root()
	for mode in ["simple", "advanced"]:
		var party := await _open_step4(root, mode, PARTY)
		_assert_above_footer(party, _main(root), mode)
		assert_eq(_range(_page(party)), 0.0, "%s: 通常時はSTEP4全体を縦にスクロールさせないこと" % mode)
		assert_true(_tab_area_height(party) >= RBMCreatorStep5Party.TAB_SCROLL_MIN_HEIGHT_PX - 0.5, "%s: タブ領域(一覧+操作ボタン)は最小の高さを保つこと" % mode)
		_assert_action_always_visible(party, _main(root), "EditPartySkillsButton_hero", "%s 通常" % mode)
		await _press(party, "PerformanceTabButton")
		_assert_above_footer(party, _main(root), "%s 性能調整" % mode)
		assert_false(_actions_bar(party).is_visible_in_tree(), "%s: 性能調整タブには使用可能スキルの操作ボタン行を出さないこと" % mode)
		assert_true(_tab(party).size.y >= RBMCreatorStep5Party.TAB_SCROLL_MIN_HEIGHT_PX - 0.5, "%s: 性能調整のタブ領域は最小の高さを保つこと" % mode)
		assert_eq(_range(_page(party)), 0.0, "%s: 性能調整は内側だけがスクロールすること" % mode)
		assert_gt(_range(_tab(party)), 0.0, "%s: 長い性能調整は内側でスクロールできること" % mode)
		await _press(party, "SkillsTabButton")

func test_add_candidates_panel_scrolls_the_whole_step_instead_of_covering_the_footer() -> void:
	var root := await _make_root()
	for mode in ["simple", "advanced"]:
		var party := await _open_step4(root, mode, ["hero", "butler", "samurai"])
		await _press(party, "AddCharacterButton")
		assert_true(party._add_candidates_panel.visible)
		_assert_above_footer(party, _main(root), "%s 追加欄" % mode)
		var page := _page(party)
		assert_gt(_range(page), 0.0, "%s: 収まらない時はSTEP4全体を縦にスクロールできること" % mode)
		assert_true(_tab_area_height(party) >= RBMCreatorStep5Party.TAB_SCROLL_MIN_HEIGHT_PX - 0.5, "%s: 追加欄を開いてもタブ領域は最小の高さを保つこと" % mode)
		assert_true(page.get_global_rect().encloses((party.find_child("ConfirmAddCandidatesButton", true, false) as Control).get_global_rect()), "%s: 追加欄の決定ボタンは最初から見えること" % mode)
		assert_eq(page.scroll_vertical, 0)
		_assert_action_always_visible(party, _main(root), "EditPartySkillsButton_hero", "%s 追加欄" % mode)
		page.scroll_vertical = int(ceil(page.get_v_scroll_bar().max_value))
		await _frames(2)
		assert_gt(page.scroll_vertical, 0)
		assert_true(page.get_global_rect().encloses(_tab(party).get_global_rect()), "%s: 下までスクロールするとタブ領域全体が見えること" % mode)
		_assert_above_footer(party, _main(root), "%s 追加欄(最下部)" % mode)
		await _press(party, "CancelAddCandidatesButton")

## スキル編集: 決定/キャンセルは入った直後から見え、一覧だけがその上でスクロールし、
## 一覧を最後までスクロールしてもボタンは動かない。
func test_skills_edit_buttons_are_shown_from_the_start_and_only_the_list_scrolls() -> void:
	var root := await _make_root()
	for mode in ["simple", "advanced"]:
		var party := await _open_step4(root, mode, PARTY)
		await _press(party, "EditPartySkillsButton_hero")
		var tab := _tab(party)
		assert_eq(_range(_page(party)), 0.0, "%s: 決定/キャンセルを見るためにSTEP4全体をスクロールしないこと" % mode)
		var before := {}
		for button_name in ["ConfirmPartySkillsButton_hero", "CancelPartySkillsButton_hero"]:
			_assert_action_always_visible(party, _main(root), button_name, "%s スキル編集(直後)" % mode)
			before[button_name] = (party.find_child(button_name, true, false) as Control).get_global_rect()
		assert_gt(_range(tab), 0.0, "%s: 長いスキル一覧は一覧部分だけがスクロールできること" % mode)
		var last_check: Control = null
		for node in party._tab_content.find_children("SkillCheck_hero_*", "", true, false):
			if last_check == null or (node as Control).get_global_rect().end.y > last_check.get_global_rect().end.y:
				last_check = node as Control
		assert_not_null(last_check)
		tab.scroll_vertical = int(ceil(tab.get_v_scroll_bar().max_value))
		await _frames(2)
		assert_gt(tab.scroll_vertical, 0)
		assert_true(tab.get_global_rect().encloses(last_check.get_global_rect()), "%s: 最後のスキルまで一覧のスクロールで届くこと" % mode)
		for button_name in before:
			assert_eq((party.find_child(button_name, true, false) as Control).get_global_rect(), before[button_name], "%s: %sは一覧をスクロールしても同じ位置に表示されたままであること" % [mode, button_name])
		_assert_above_footer(party, _main(root), "%s スキル編集" % mode)
		await _press(party, "CancelPartySkillsButton_hero")

## ハンマー使い+CUSTOMのようにパーティカードが高く、STEP4全体のスクロールが必要な時も、
## 編集ボタンは全体をスクロールしないまま最初から全部見えること。
func test_tall_party_cards_keep_the_edit_button_visible_without_scrolling_the_whole_step() -> void:
	var root := await _make_root()
	var main := _main(root)
	root._show_only(root.creator_entry)
	root.creator_entry.enter_create()
	root.creator_entry._on_new_pressed()
	root.creator_entry._on_choose_advanced_mode_pressed()
	main = _main(root)
	for id in ["hero", "butler", "tank", "healer"]:
		main.draft.add_party_character(id)
		main.draft.set_ally_stat_override(id, "hp", 1500)
	main._refresh()
	main.go_to_step(4)
	await _frames(3)
	var party: RBMCreatorStep5Party = main._step_views[3]
	party.select_character("hero")
	await _frames(2)
	assert_gt(_range(_page(party)), 0.0, "sanity: tall cards make the whole STEP4 scrollable")
	assert_eq(_page(party).scroll_vertical, 0)
	_assert_action_always_visible(party, main, "EditPartySkillsButton_hero", "HARDCORE ハンマー使い+CUSTOM")
	_assert_above_footer(party, main, "HARDCORE ハンマー使い+CUSTOM")

func _wheel(down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.factor = 1.0
	return event

## タブ領域のホイール1刻みは以前の320px時と同程度の40px。端では動かさない(受け取らず
## 外側のSTEP4全体へ渡す)。
func test_tab_wheel_moves_40px_per_notch_and_stops_at_the_ends() -> void:
	var root := await _make_root()
	var party := await _open_step4(root, "advanced", PARTY)
	await _press(party, "PerformanceTabButton")
	var tab := _tab(party)
	var bottom := int(_range(tab))
	assert_gt(bottom, 80, "sanity: the HARDCORE performance tab is long")
	assert_eq(RBMCreatorStep5Party.TAB_SCROLL_WHEEL_STEP_PX, 40.0)
	tab.scroll_vertical = 0
	party._on_tab_scroll_gui_input(_wheel(true), tab)
	assert_eq(tab.scroll_vertical, 40, "1刻みで40px下へ")
	party._on_tab_scroll_gui_input(_wheel(true), tab)
	assert_eq(tab.scroll_vertical, 80)
	party._on_tab_scroll_gui_input(_wheel(false), tab)
	assert_eq(tab.scroll_vertical, 40, "1刻みで40px上へ")
	tab.scroll_vertical = bottom - 10
	party._on_tab_scroll_gui_input(_wheel(true), tab)
	assert_eq(tab.scroll_vertical, bottom, "最下部を越えない")
	party._on_tab_scroll_gui_input(_wheel(true), tab)
	assert_eq(tab.scroll_vertical, bottom, "最下部ではそれ以上動かない(外側へ渡す)")
	tab.scroll_vertical = 0
	party._on_tab_scroll_gui_input(_wheel(false), tab)
	assert_eq(tab.scroll_vertical, 0, "最上部ではそれ以上動かない(外側へ渡す)")
