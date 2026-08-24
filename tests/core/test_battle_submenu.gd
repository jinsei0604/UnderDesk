extends GutTest
## 下部固定バーとサブメニューの分離 (2026-08-27/2026-08-27b、ユーザー
## 指示「スキル選択→敵/部位選択」「どうぐ→ポーション選択→味方対象選択」
## 「もどるで正しい1つ前の状態へ戻る」の3点まとめての整理、§29/§17の
## テストチェックリスト) のUI層回帰テスト。
##
## 根本原因（元々のバグ）: スキル/どうぐ一覧(_battle_list_panel)だけは
## 画面右側に独立して浮くPRESET_RIGHT_WIDEの別領域だった一方、
## _commands_column（通常4コマンド）・_target_confirm_panel（敵/部位・
## 味方対象選択）はbar内の同じ`row`スロットを共有していた——これが
## 「それぞれ違う位置にある」というユーザー報告そのもの。加えて
## _on_battle_item()は_battle_phaseも両パネルのvisibleも一切更新しておら
## ず、兄弟関数の_on_battle_skill()だけがこれを行っていた——「どうぐ→
## ポーション→味方対象選択→もどる」で戻れなくなっていたのは、target_
## confirm_panelがvisible=trueのまま放置され、同じ`row`スロットへどうぐ
## 一覧が正しく再表示されない（または重なる）状態になっていたため。
##
## 修正の第1版（2026-08-27）: _battle_list_panelを`row`へ再配置し単一の
## 同期入口を新設したが、これによりNEXT5/5人ステータス/4コマンドが
## サブメニューの参加/離脱のたびに横へズレる新しい実機バグを生んだ
## （row.alignment=CENTERの中央寄せ計算が、参加する子の合計幅が変わる
## たびにNEXT5・カード列・コマンド列自体の位置を揺らしていた）。
##
## 最終修正（2026-08-27b）: 下部バーの`row`は常にNEXT5・5人ステータス・
## _commands_column（常にvisible=true、二度と切り替えない）だけの完全
## 固定領域に戻し、_target_confirm_panel/_battle_list_panelは`row`から
## 完全に切り離した独立した最上位Control（以前スキル一覧が表示されて
## いたのと全く同じPRESET_RIGHT_WIDEの矩形を共有）へ——_battle_phaseの
## 5値（commandSelection/skillSelection/itemSelection/targetSelection/
## executing）を読む単一の同期入口_sync_battle_submenu_visibility()は
## そのまま維持しつつ、対象は_battle_list_panel/_target_confirm_panelの
## 2つだけに縮小した。


const GATE_10_STAGE_INDEX := 10  # data/stages/020_gate10.json, cave_troll's gate


func _start_cave_troll_fight() -> Control:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	var main: Control = add_child_autofree(scene.instantiate())
	if not main.is_node_ready():
		await main.ready
	main.autosave_timer.stop()
	main.tick_timer.stop()
	main.settings.resident_mode = false
	main._apply_window_mode()
	if main.sim.boss_active:
		main.sim.flee_boss_fight()
	main.sim.stage_index = GATE_10_STAGE_INDEX
	for m in main.sim.minions:
		m.hp = main.sim.unit_max_hp(m)
		m.sp = main.sim.unit_max_sp(m)
	assert_true(main.sim.start_boss_fight())
	assert_eq(main.sim.boss_enemy_id, "cave_troll")
	main._show_boss_panel()
	assert_eq(main.sim.current_actor_token(), "ally:1", "fixture assumption: 円(Madoka) acts first")
	return main


func _pump_battle_animation(main: Control) -> void:
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 20000, "battle animation never settled")


func _fast_forward_to_ally_turn(main: Control, unit_id: int) -> void:
	var guard := 0
	while main.sim.current_actor_token() != "ally:%d" % unit_id:
		var token: String = main.sim.current_actor_token()
		assert_true(token.begins_with("ally:"), "expected another ally's turn, got '%s'" % token)
		main._set_battle_action(
			int(token.substr(5)), "attack", "", "enemy", main.sim.boss_enemy_id, "")
		_pump_battle_animation(main)
		guard += 1
		assert_lt(guard, 10, "fast-forward looped too many times heading to unit %d's turn" % unit_id)


## 下部固定バーとサブメニューの分離 (2026-08-27b): _commands_column
## （下部固定バー側）は常にvisible=true——サブメニュー(スキル一覧/
## どうぐ一覧/対象選択、下部バーとは無関係の独立した上側領域)がどちらか
## 一方だけvisible=trueであり、それが期待した_battle_phaseと一致する
## ことを一括で確認する。
func _assert_submenu_state(main: Control, expected_phase: String) -> void:
	assert_eq(main._battle_phase, expected_phase, "phase")
	assert_true(main._commands_column.visible,
		"the fixed bottom bar's commands never hide, regardless of submenu state")
	assert_eq(main._battle_list_panel.visible,
		expected_phase == "skillSelection" or expected_phase == "itemSelection",
		"battle_list_panel visibility")
	assert_eq(main._target_confirm_panel.visible, expected_phase == "targetSelection",
		"target_confirm_panel visibility")


## §29-1: 通常→こうげき→敵対象。
func test_command_to_attack_opens_enemy_target_selection() -> void:
	var main := await _start_cave_troll_fight()
	_assert_submenu_state(main, "commandSelection")

	main._on_battle_attack()

	_assert_submenu_state(main, "targetSelection")
	assert_eq(main._battle_target_kind, "enemy")
	assert_eq(main._battle_target_source, "attack")


## §29-2: 敵対象→もどる→通常。
func test_enemy_target_back_returns_to_command_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_attack()

	main._on_target_back()

	_assert_submenu_state(main, "commandSelection")
	assert_eq(main._battle_selected_target_id, "", "§20: cancelled target selection is discarded")


## §29-3: 通常→スキル→スキル一覧。
func test_command_to_skill_opens_skill_list() -> void:
	var main := await _start_cave_troll_fight()

	main._on_battle_skill()

	_assert_submenu_state(main, "skillSelection")
	assert_false(main._battle_list_entries.is_empty(), "円 has skills to list")


## §29-4/5: スキル→敵対象、敵対象→もどる→スキル一覧。
func test_skill_to_enemy_target_and_back_returns_to_skill_list() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_skill()
	var skill_id: String = main.sim.unit_skills(main.sim.minions[1])[0]

	main._enter_target_selection("skill", skill_id, "enemy")
	_assert_submenu_state(main, "targetSelection")
	assert_eq(main._battle_target_source, "skill")

	main._on_target_back()

	_assert_submenu_state(main, "skillSelection")
	assert_eq(main._battle_selected_target_id, "", "§20: cancelled target selection is discarded")


## §29-6: 通常→どうぐ→ポーション一覧。実機バグの真因だった経路。
func test_command_to_item_opens_item_list() -> void:
	var main := await _start_cave_troll_fight()

	main._on_battle_item()

	_assert_submenu_state(main, "itemSelection")
	assert_eq(main._battle_list_entries.size(), 2, "hp_potion + sp_potion")


## §29-7: HPポーション→味方対象。
func test_hp_potion_opens_ally_target_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()

	main._enter_target_selection("item", "hp_potion", "ally")

	_assert_submenu_state(main, "targetSelection")
	assert_eq(main._battle_target_kind, "ally")
	assert_eq(main._battle_target_source, "item")
	assert_eq(main._battle_pending_skill_id, "hp_potion")


## §29-8: SPポーション→味方対象。
func test_sp_potion_opens_ally_target_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()

	main._enter_target_selection("item", "sp_potion", "ally")

	_assert_submenu_state(main, "targetSelection")
	assert_eq(main._battle_pending_skill_id, "sp_potion")


## §29-9(最重要、今回の実機バグそのもの): 味方対象→もどる→ポーション一覧。
func test_ally_target_back_from_a_potion_returns_to_the_item_list_not_stuck() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()
	main._enter_target_selection("item", "hp_potion", "ally")
	assert_true(main._target_confirm_panel.visible, "sanity: target selection is actually open")

	main._on_target_back()

	_assert_submenu_state(main, "itemSelection")
	assert_false(main._target_confirm_panel.visible,
		"the old bug: target_confirm_panel stayed visible, overlapping the reopened item list")
	assert_eq(main._battle_selected_ally_target, -1, "§20: cancelled target selection is discarded")
	# 一覧が実際に再構築され、クリックできる状態であること（disabledの
	# まま固まって二度と選べなくなっていないことの直接確認）。
	# _show_battle_list_panel()の再構築はqueue_free()（次フレームまで
	# 実際には子から外れない）を使うため、実プレイと同じく1フレーム待って
	# から数える（このプロジェクト既存の確立済み手法）。
	await get_tree().process_frame
	var rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	assert_eq(rows.get_child_count(), 2, "hp_potion + sp_potion rows are still there")
	for row in rows.get_children():
		assert_false((row as Button).disabled)


## §29-10: ポーション一覧→もどる→通常。
func test_item_list_back_returns_to_command_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()

	main._on_battle_list_back()

	_assert_submenu_state(main, "commandSelection")


## §29-11: 回復スキル→味方対象→もどる→スキル一覧。
func test_healing_skill_target_back_returns_to_skill_list() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)  # ソティリス(ヒーリング所有者)のターンまで進める
	main._on_battle_skill()

	main._enter_target_selection("skill", "skill_healing", "ally")
	_assert_submenu_state(main, "targetSelection")
	assert_eq(main._battle_target_kind, "ally")

	main._on_target_back()

	_assert_submenu_state(main, "skillSelection")
	assert_eq(main._battle_selected_ally_target, -1, "§20: cancelled target selection is discarded")


## §29-12: actorがtarget選択で変化しない。
func test_actor_never_changes_while_selecting_an_item_target() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()
	main._enter_target_selection("item", "hp_potion", "ally")

	main._battle_selected_ally_target = 2  # ヴァルドを対象として選ぶ

	assert_eq(main._battle_selected_unit, 1, "acting unit stays 円 -- only the target changed")
	assert_eq(main.sim.current_actor_token(), "ally:1")


## §29-13: target状態がキャンセル時に正しく破棄され、次に開いたとき
## 勝手に復元されない。
func test_cancelled_target_state_is_discarded_and_not_reused_next_time() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_attack()
	main._on_enemy_target_row_selected(main.sim.boss_enemy_id + "#arm")
	assert_eq(main._battle_selected_target_id, main.sim.boss_enemy_id + "#arm")

	main._on_target_back()
	assert_eq(main._battle_selected_target_id, "", "discarded on cancel")

	main._on_battle_attack()
	assert_eq(main._battle_selected_target_id, main.sim.boss_enemy_id,
		"defaults fresh to the main body, not the previously-cancelled #arm")


## §29-14/15/16/17: 決定後に行動が正常に実行され、ポーション残数が減り、
## 1行動を消費し、NEXTが正常に進む。
func test_confirming_a_potion_use_executes_normally_and_next_progresses() -> void:
	var main := await _start_cave_troll_fight()
	var next_before: Array = main.sim.peek_next_actors(5)
	var target_id := 0
	main.sim.minions[target_id].hp = 10
	var counts_before: int = main.sim.battle_item_counts["hp_potion"]

	main._on_battle_item()
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_gt(main.sim.minions[target_id].hp, 10, "§14: healed for real")
	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), counts_before - 1, "§15: count decremented")
	assert_eq(main.sim.current_actor_token(), next_before[0],
		"§16/§17: one action consumed, NEXT progressed correctly")


## §29-18: 防御が壊れていない。
func test_defend_still_works_and_returns_to_command_selection() -> void:
	var main := await _start_cave_troll_fight()

	main._on_battle_defend()
	assert_ne(main._battle_phase, "targetSelection", "guard never opens target selection")
	_pump_battle_animation(main)

	assert_true(main.sim.guarding_units.has(1), "sim recorded the guard")
	_assert_submenu_state(main, "commandSelection")


## §29-19: 部位選択が壊れていない。
func test_body_part_targeting_still_works_through_the_unified_submenu() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_attack()

	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")
	main._on_enemy_target_row_selected(main.sim.boss_enemy_id + "#arm")
	main._on_target_confirm()
	# _battle_pending_round_resultは_finish_battle_round()（アニメ再生完了
	# 後）で{}へクリアされる（_stop_battle_anim()経由）ため、まだクリア
	# される前——_on_target_confirm()が同期的にセットした直後——に読む
	# （このプロジェクト既存の確立済み手法、test_battle_actor_integrity.gd
	# 参照）。
	var log: Array = main._battle_pending_round_result.get("log", [])
	assert_eq(log.size(), 1)
	assert_eq(str((log[0] as Dictionary).get("target_part", "")), "arm")
	_pump_battle_animation(main)


## §29-20: REWINDが壊れていない。
func test_rewind_still_works_and_resets_the_submenu_to_command_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_item()
	main._enter_target_selection("item", "hp_potion", "ally")

	main._do_battle_rewind()

	_assert_submenu_state(main, "commandSelection")
	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), 3)


func _capture_bar_layout(main: Control) -> Dictionary:
	return {
		"next": main._battle_next_column.get_global_rect(),
		"cards": (main._battle_bar.find_child("cards", true, false) as Control).get_global_rect(),
		"commands": main._commands_column.get_global_rect(),
		"bar": main._battle_bar.get_global_rect(),
	}


func _assert_bar_layout_matches(main: Control, before: Dictionary, label: String) -> void:
	assert_eq(main._battle_next_column.get_global_rect(), before["next"], "%s: NEXT5 moved" % label)
	assert_eq((main._battle_bar.find_child("cards", true, false) as Control).get_global_rect(),
		before["cards"], "%s: 5-character status row moved" % label)
	assert_eq(main._commands_column.get_global_rect(), before["commands"],
		"%s: 4-command area moved" % label)
	assert_eq(main._battle_bar.get_global_rect(), before["bar"], "%s: the bar itself moved" % label)


## §10/§11/§17(最重要): サブメニュー(スキル一覧→敵/部位対象選択→もどる、
## どうぐ一覧→味方対象選択→もどる)をどれだけ切り替えても、下部固定バー
## 自体(NEXT5・5人ステータス・4コマンド)のグローバル位置・幅は一切変化
## しない——サブメニューが下部バーの`row`スロットを共有していたことに
## よる横シフトの直接的な回帰テスト。
func test_bottom_bar_position_never_moves_across_any_submenu_transition() -> void:
	var main := await _start_cave_troll_fight()
	var before := _capture_bar_layout(main)

	# §17-2/3: スキル一覧を開く。
	main._on_battle_skill()
	_assert_bar_layout_matches(main, before, "after opening the skill list")

	# §17-4/5: 部位選択へ切り替える。
	var skill_id: String = main.sim.unit_skills(main.sim.minions[1])[0]
	main._enter_target_selection("skill", skill_id, "enemy")
	_assert_bar_layout_matches(main, before, "after switching to enemy target selection")

	main._on_target_back()
	_assert_bar_layout_matches(main, before, "after backing out to the skill list")
	main._on_battle_list_back()
	_assert_bar_layout_matches(main, before, "after backing out to command selection")

	# §17-6/7: どうぐ一覧を開く。
	main._on_battle_item()
	_assert_bar_layout_matches(main, before, "after opening the item list")

	# §17-8/9: 味方対象選択へ切り替える。
	main._enter_target_selection("item", "hp_potion", "ally")
	_assert_bar_layout_matches(main, before, "after switching to ally target selection")

	# §17-10: もどるで正しく戻る。
	main._on_target_back()
	_assert_bar_layout_matches(main, before, "after backing out of ally target selection")
	_assert_submenu_state(main, "itemSelection")


## 右側サブメニュー領域の拡大 (2026-08-28、実機報告「大きなパネルなのに
## 上部の一部しか使っていない」§19) の回帰テスト一式。位置・戦闘ロジック
## は今回変更していないため、既存のREWIND/防御/部位破壊/actor-target分離
## 系テストは全て無改修のまま——ここでは新設・拡大したUI要素だけを狙う。


## §6/§12: 新設の味方対象行リスト——5人全員が1行ずつ並び、既定選択
## （詠唱者自身）の行だけが選択状態になっていること。
func test_ally_target_rows_lists_all_five_with_the_default_selection_highlighted() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 0  # ソティリス（ヒーリング所持）
	main._enter_target_selection("skill", "skill_healing", "ally")

	var rows: VBoxContainer = main._target_confirm_panel.find_child("ally_target_rows", true, false)
	assert_eq(rows.get_child_count(), 5, "one row per living ally")
	var pressed_count := 0
	for i in rows.get_child_count():
		var row := rows.get_child(i) as Button
		if row.button_pressed:
			pressed_count += 1
			assert_eq(row.text, main._unit_display_name(main.sim.minions[0]),
				"the pressed row is the default self-heal target (unit 0)")
	assert_eq(pressed_count, 1, "exactly one row selected, not zero or two")

	# 敵/部位選択専用の行リストはこの間ずっと空のまま——味方対象選択中に
	# 両方のリストが同時に埋まることはない。
	var enemy_rows: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(enemy_rows.get_child_count(), 0, "enemy/part rows stay empty during ally targeting")


## §6/§12/既存の同期(_update_card_selection): 行をクリックすると、
## 下部カードの緑枠・パネルの対象名表示・選択状態が既存の"カードを
## クリックして選ぶ"導線(_on_battle_card_input)と同じ結果になること
## ——新しい行リストは同じ状態変数への、もう一つの入口に過ぎない。
func test_clicking_an_ally_target_row_moves_selection_same_as_clicking_the_card() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 0
	main._enter_target_selection("skill", "skill_healing", "ally")

	var rows: VBoxContainer = main._target_confirm_panel.find_child("ally_target_rows", true, false)
	var target_row: Button = null
	for i in rows.get_child_count():
		var row := rows.get_child(i) as Button
		if row.text == main._unit_display_name(main.sim.minions[2]):
			target_row = row
	assert_not_null(target_row, "a row exists for unit 2")
	target_row.pressed.emit()

	assert_eq(main._battle_selected_ally_target, 2)
	var target_line: Label = main._target_confirm_panel.find_child("target_line", true, false)
	assert_string_contains(target_line.text, main._unit_display_name(main.sim.minions[2]))
	var card_style: StyleBoxFlat = main._battle_cards[2]["style"]
	assert_eq(card_style.border_color, main.COLOR_ALLY_TARGET_BORDER,
		"row selection updates the board's green marker via _update_card_selection, unchanged")


## §2/§20「新しいスペースを作るのではなく、今ある余白を使う」の直接的な
## 回帰ガード: 拡大後の行・footerボタンが、拡大前の小さな寸法（旧13pt
## 前後・content_margin4〜6・高さ指定なし）よりはっきり大きいこと。絶対
## px値の目視確認はこの環境では不可能（既存の制約）——ここでは「確実に
## 前より大きい」ことだけを数値で裏付ける。
## 2026-08-30ラウンドで48.0px→30.0pxへ閾値を緩和: サブメニュー全体を
## ボスバナー(実測131px)より下へ移動しつつ4スキル同時表示を満たすため
## SUBMENU_ROW_MIN_HEIGHTを48→36・SUBMENU_FOOTER_MIN_HEIGHTを48→34へ
## それぞれ圧縮した（ユーザー明示許可、§4「今より少しコンパクト」§6
## 「行の高さ...を少しだけ縮小」）——このテスト自身の閾値(48.0)は前ラウンド
## の"comfortably tall"という判断値でしかなく仕様上の絶対要件ではないため、
## 新しい実測値(36.0/34.0)をどちらも安全に上回る30.0へ更新（旧・小さすぎた
## 時代の20px前後よりは明確に大きいままであることを保証する下限）。
func test_target_confirm_panel_rows_and_footer_grew_noticeably_larger() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_attack()

	var enemy_rows: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(enemy_rows.get_child_count(), 3, "main body + arm + leg")
	var part_row := enemy_rows.get_child(0) as Button
	assert_gte(part_row.get_theme_font_size("font_size"), 18,
		"part/body target rows read at a glance, not squinted at")
	assert_gte(part_row.custom_minimum_size.y, 30.0, "clickable area is comfortably tall")

	var target_column: VBoxContainer = main._target_confirm_panel.get_child(0)
	var footer: HBoxContainer = target_column.get_child(target_column.get_child_count() - 1)
	var confirm_button := footer.get_child(footer.get_child_count() - 1) as Button
	assert_gte(confirm_button.get_theme_font_size("font_size"), 18, "決定 reads clearly")
	assert_gte(confirm_button.custom_minimum_size.y, 30.0, "決定 is easy to hit with the mouse")


## 同じ拡大ルールがスキル一覧・どうぐ一覧にも及んでいること(§7/§8/§15)。
func test_skill_and_item_list_rows_also_grew_and_share_the_same_sizing() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1  # 円(5スキル所持)
	main._on_battle_skill()
	var skill_rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	assert_eq(skill_rows.get_child_count(), 5)
	var skill_row := skill_rows.get_child(0) as Button
	assert_eq(skill_row.get_theme_font_size("font_size"), main.SUBMENU_ROW_FONT_SIZE)
	assert_almost_eq(skill_row.custom_minimum_size.y, main.SUBMENU_ROW_MIN_HEIGHT, 0.01)

	# _battle_selected_unitは1(円)のまま——_on_battle_item()はcurrent_actor
	# 一致ガードを持つため(_battle_selected_unit_is_current_actor())、
	# fixtureが保証する現在の行動者(unit 1)以外へ書き換えると早期returnし
	# て一覧が更新されない。_show_battle_list_panel()内のqueue_free()は
	# この呼び出し自体の直後に1フレーム待たないと反映されない（このテスト
	# 自身が最初に踏んだ罠——待つ位置がこの呼び出しの前ではなく後である
	# 必要がある、実装のバグではない）。
	main._on_battle_item()
	await get_tree().process_frame
	var item_rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	assert_gt(item_rows.get_child_count(), 0)
	var item_row := item_rows.get_child(0) as Button
	# §8「名前と残数を一目で確認できる配置」: cost_text(×N)が行の文字列に
	# 含まれたままであること。
	assert_string_contains(item_row.text, "×")
	assert_eq(item_row.get_theme_font_size("font_size"), main.SUBMENU_ROW_FONT_SIZE,
		"item rows use the exact same shared font size as skill rows (§15)")


## パネル過大化バグの回帰ガード(2026-08-29、§8): 見た目の非重複だけでなく
## Controlのクリック領域そのものが重ならないことを、実際のget_global_rect()
## 同士のintersects()で直接検証する。下部固定バーはx全幅を覆うため、
## y方向で重ならなければ(サブメニューはx=732..1140の右側領域なので)矩形
## としても重ならない——ここでは4コマンド・5人カード・NEXT5の3つの代表
## 矩形＋バー全体を対象に、3つの実測ワーストケース（部位3択・味方5択・
## スキル5個）それぞれで確認する。
## 2026-08-30ラウンド追加: ボスHP/部位HP UI(_boss_banner)との非重複も
## 同じ仕組みへ相乗り——実機報告「サブメニュー上端がボスHP UIへ食い込む」
## の直接的な回帰ガード（当時はcave_trollの部位2段表示時の実測下端131px
## に対し、旧offset_top=70が明らかにその内側にあった）。_boss_banner
## もx範囲[220,932]がサブメニューのx範囲[732,1140]と重なるため、この
## intersects()方式がそのまま正しく機能する。
func _assert_no_click_region_overlap(main: Control, submenu_panel: Control) -> void:
	assert_true(submenu_panel.visible, "submenu panel under test must actually be showing")
	var submenu_rect: Rect2 = submenu_panel.get_global_rect()
	var bar_rect: Rect2 = main._battle_bar.get_global_rect()
	assert_false(submenu_rect.intersects(bar_rect),
		"submenu panel rect must not overlap the fixed bottom bar rect")
	var banner_rect: Rect2 = main._boss_banner.get_global_rect()
	assert_false(submenu_rect.intersects(banner_rect),
		"submenu panel rect must not overlap the boss HP/part banner rect")
	var targets := {
		"attack": main._battle_attack_button,
		"skill": main._battle_skill_button,
		"defend": main._battle_defend_button,
		"item": main._battle_item_button,
		"cards": main._battle_bar.find_child("cards", true, false),
		"next": main._battle_next_column,
	}
	for label in targets:
		var node: Control = targets[label]
		assert_not_null(node, "expected bottom-bar node '%s' to exist" % label)
		var overlap: bool = submenu_rect.intersects(node.get_global_rect())
		assert_false(overlap, "submenu panel must not overlap bottom-bar '%s'" % label)


func test_target_confirm_panel_never_overlaps_bottom_bar_click_regions_for_parts() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_attack()  # cave_troll: body + arm + leg = 3 rows, worst enemy case
	_assert_no_click_region_overlap(main, main._target_confirm_panel)


func test_target_confirm_panel_never_overlaps_bottom_bar_click_regions_for_allies() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 0
	main._enter_target_selection("skill", "skill_healing", "ally")  # all 5 allies listed
	_assert_no_click_region_overlap(main, main._target_confirm_panel)


func test_battle_list_panel_never_overlaps_bottom_bar_click_regions_for_five_skills() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1  # 円、必殺技含む5スキル所持=最多ケース
	main._on_battle_skill()
	_assert_no_click_region_overlap(main, main._battle_list_panel)


## 2026-08-30ラウンド追加、§5/§10「標準4スキルはスクロールなしで全部
## 表示」の直接的な回帰ガード: ソティリス(ラピッドスラッシュ/ヒーリング/
## ソウルブレイク/必殺：エオスバースト、4スキル=標準ケース)でrows_scroll
## (ScrollContainer)のcustom_minimum_sizeが、実際に描画された4行分の
## 自然サイズ以上であること——これが満たされないと4行目を見るのに内部
## スクロールが必要になってしまう(2026-08-30に実際に一度踏んだ不具合:
## rows_scrollのサイズ計算式がSUBMENU_ROW_MIN_HEIGHTという"床"の値を
## そのまま使っていたが、実際のボタンはfont+content_marginの都合で床より
## 自然に大きく描画されるため、床の値だけで計算すると実際の行より小さい
## スクロール領域を確保してしまっていた)。長いスキル名「必殺：
## エオスバースト」が含まれる行も他の3行と同じ高さで問題なく収まって
## いることも合わせて確認する。
func test_sotiris_four_standard_skills_all_visible_without_scrolling() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	main._battle_selected_unit = 0
	main._on_battle_skill()

	var rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	assert_eq(rows.get_child_count(), 4,
		"ラピッドスラッシュ/ヒーリング/ソウルブレイク/必殺：エオスバースト")
	var rows_scroll: ScrollContainer = main._battle_list_panel.find_child("rows_scroll", true, false)
	assert_true(rows_scroll.size.y >= rows.size.y - 0.5,
		"4行全部がスクロール領域に収まる（内部スクロール不要）: scroll=%f rows=%f"
		% [rows_scroll.size.y, rows.size.y])

	var eos_burst_row: Button = null
	for child in rows.get_children():
		var b := child as Button
		if b.text.begins_with("必殺：エオスバースト"):
			eos_burst_row = b
	assert_not_null(eos_burst_row, "必殺：エオスバースト row must exist and not be truncated away")
	assert_almost_eq(eos_burst_row.custom_minimum_size.y, main.SUBMENU_ROW_MIN_HEIGHT, 0.01,
		"long skill name gets the exact same row height as the others")


func test_target_confirm_panel_and_battle_list_panel_moved_down_below_boss_banner() -> void:
	var main := await _start_cave_troll_fight()
	main._refresh_boss_parts_column()
	await get_tree().process_frame
	var banner_bottom: float = main._boss_banner.global_position.y + main._boss_banner.size.y

	main._on_battle_attack()
	assert_almost_eq(main._target_confirm_panel.global_position.y, main.SUBMENU_PANEL_TOP_OFFSET, 0.01)
	assert_gt(main._target_confirm_panel.global_position.y, banner_bottom,
		"submenu top must sit below the boss banner's worst-case bottom, not overlap it")
	main._on_target_back()

	main._on_battle_skill()
	assert_almost_eq(main._battle_list_panel.global_position.y, main.SUBMENU_PANEL_TOP_OFFSET, 0.01)
	assert_gt(main._battle_list_panel.global_position.y, banner_bottom)
