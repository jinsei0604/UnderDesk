extends GutTest
## 視認性改善（2026-08-22、実機報告「文字/ダメージが薄い」「選択中の赤
## 表示が点滅する」への対応）: この環境には実レンダラーが無くピクセル
## 単位の見た目は検証できない（既存の制約）ため、①点滅の元だった
## _anim_frame依存の値が本当に定数化されたこと、②行リストの選択色が
## 対象選択パネルと汎用スキル/どうぐ一覧とで意図どおり分離されている
## こと（一方だけ赤くなる、他方は元の青のまま）、③フォーカス/ホバー用
## のstylebox・font colorが実際に上書きされていること、④通常ダメージ
## ポップアップが白統一されたこと、を状態レベルで直接検証する。


const GATE_10_STAGE_INDEX := 10  # data/stages/020_gate10.json, cave_troll's gate


func _start_expanded_main() -> Control:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	var main: Control = add_child_autofree(scene.instantiate())
	if not main.is_node_ready():
		await main.ready
	main.autosave_timer.stop()
	main.tick_timer.stop()
	main.settings.resident_mode = false
	main._apply_window_mode()
	return main


func _start_cave_troll_fight(main: Control) -> void:
	if main.sim.boss_active:
		main.sim.flee_boss_fight()
	main.sim.stage_index = GATE_10_STAGE_INDEX
	for m in main.sim.minions:
		m.hp = main.sim.unit_max_hp(m)
		m.sp = main.sim.unit_max_sp(m)
	assert_true(main.sim.start_boss_fight())
	main._show_boss_panel()


## 旧: sin(_anim_frame*0.9)でHPバーのfill色が0.10〜1.00アルファの赤へ
## 明滅していた。新: _anim_frameの値に関わらず常に同じ濃い赤で固定。
func test_target_hp_bar_glow_is_constant_regardless_of_anim_frame() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "enemy")

	main._anim_frame = 0
	main._update_target_hp_bar_glow()
	var fill_a: StyleBoxFlat = main._boss_banner_hp_bar.get_theme_stylebox("fill")

	main._anim_frame = 37  # sin(37*0.9) is nowhere near sin(0) -- would have
	# differed drastically under the old pulsing formula.
	main._update_target_hp_bar_glow()
	var fill_b: StyleBoxFlat = main._boss_banner_hp_bar.get_theme_stylebox("fill")

	assert_eq(fill_a.bg_color, fill_b.bg_color, "no flicker across different _anim_frame values")
	assert_eq(fill_a.bg_color, main.COLOR_TARGET_CURSOR, "fully opaque, deep-red, matches the crosshair")
	assert_eq(fill_a.bg_color.a, 1.0, "fully opaque -- never faded")


## 対象選択パネルの行（enemy_target_rows）は濃い赤（COLOR_TARGET_
## SELECTED_BG）で選択状態を示す一方、汎用スキル/どうぐ一覧
## （_battle_list_panel）は無改修の従来の青のまま——今回の変更が意図せず
## 別システムへ波及していないことの直接確認。
func test_enemy_target_row_selection_is_deep_red_while_skill_list_stays_blue() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "enemy")

	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")
	var arm_target_id: String = str(main.sim.boss_enemy_id) + "#arm"
	main._on_enemy_target_row_selected(arm_target_id)

	var selected_row: Button = null
	for child in rows_container.get_children():
		if (child as Button).button_pressed:
			selected_row = child
	assert_not_null(selected_row, "the arm row is marked pressed/selected")
	var pressed_style: StyleBoxFlat = selected_row.get_theme_stylebox("pressed")
	var hover_pressed_style: StyleBoxFlat = selected_row.get_theme_stylebox("hover_pressed")
	assert_eq(pressed_style.bg_color, main.COLOR_TARGET_SELECTED_BG)
	# §4/§8 の核心バグ修正: hover_pressed を明示していなかったため、選択
	# 済みの行にマウスが乗るとGodotの既定テーマへフォールバックし、赤色
	# が消えて見えていた——pressedとhover_pressedが同じ濃い赤であること
	# を確認し、ホバーで色が変わらないことを直接証明する。
	assert_eq(hover_pressed_style.bg_color, main.COLOR_TARGET_SELECTED_BG,
		"hovering an already-selected row keeps the same deep red (the actual flicker bug)")
	assert_eq(selected_row.focus_mode, Control.FOCUS_NONE,
		"no keyboard focus ring that could visually compete with the selection color")

	# 別システム（スキル/どうぐ一覧）は無改修のまま——赤くならない。
	main._show_battle_list_panel("test", [
		{"label": "a", "enabled": true}, {"label": "b", "enabled": true},
	])
	var list_rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	var list_row: Button = list_rows.get_child(0)
	var list_pressed_style: StyleBoxFlat = list_row.get_theme_stylebox("pressed")
	assert_eq(list_pressed_style.bg_color, Color(0.16, 0.36, 0.6),
		"unrelated skill/item list keeps its original blue selection color")


## 決定するまで持続する（selected）ことと、一時的なホバーは別物として
## 扱う——別対象へ切り替えると、以前の対象の行は選択色から外れる。
func test_switching_selected_row_moves_the_highlight_not_duplicates_it() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "enemy")
	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)

	var arm_id: String = str(main.sim.boss_enemy_id) + "#arm"
	var leg_id: String = str(main.sim.boss_enemy_id) + "#leg"
	main._on_enemy_target_row_selected(arm_id)
	# _refresh_enemy_target_rows() rebuilds the row list via queue_free()
	# (deferred, takes effect at end-of-frame — same as a real play session,
	# where the next frame always elapses before the player can see/click
	# again) + fresh Buttons; awaiting a frame here lets that settle before
	# counting children, matching real usage instead of catching stale
	# not-yet-removed nodes mid-rebuild.
	await get_tree().process_frame
	var pressed_after_arm: Array[bool] = []
	for child in rows_container.get_children():
		pressed_after_arm.append((child as Button).button_pressed)
	assert_eq(pressed_after_arm.count(true), 1, "exactly one row pressed after selecting the arm")

	main._on_enemy_target_row_selected(leg_id)
	await get_tree().process_frame
	var pressed_after_leg: Array[bool] = []
	var leg_row_pressed := false
	for child in rows_container.get_children():
		var b: Button = child
		pressed_after_leg.append(b.button_pressed)
		if b.text == main._boss_part_display_name(main.enemy_db.get_enemy(main.sim.boss_enemy_id), "leg"):
			leg_row_pressed = b.button_pressed
	assert_eq(pressed_after_leg.count(true), 1, "still exactly one row pressed, never zero or two")
	assert_true(leg_row_pressed, "the highlight moved to the newly-selected leg row")


func test_damage_popup_color_is_opaque_white_for_plain_body_and_part_damage() -> void:
	var main := await _start_expanded_main()
	assert_eq(main.COLOR_DAMAGE_POPUP, Color(1.0, 1.0, 1.0))
	assert_eq(main.COLOR_DAMAGE_POPUP.a, 1.0, "not translucent")
	# COLOR_HEAL_POPUP/COLOR_PART_BREAK_POPUP stay distinct on purpose
	# (§11 "色による区別はいったんやめて" applies to plain damage only —
	# a "part destroyed" announcement and a heal are qualitatively
	# different events, not just another number).
	assert_ne(main.COLOR_HEAL_POPUP, main.COLOR_DAMAGE_POPUP)
	assert_ne(main.COLOR_PART_BREAK_POPUP, main.COLOR_DAMAGE_POPUP)


## パネル全体の見出し・案内文・スキル/対象名・部位パネルの文字色が
## 明示的に強コントラスト色へ統一されていること（以前はGodotのテーマ
## 既定色に頼っている要素が混在していた）。
func test_all_battle_panel_labels_use_the_strong_contrast_color() -> void:
	var main := await _start_expanded_main()
	assert_eq(main.COLOR_BOSS_PANEL_TEXT, Color(1.0, 1.0, 1.0))
	assert_eq(main._boss_banner_label.modulate, main.COLOR_BOSS_PANEL_TEXT)

	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "enemy")
	var title_label: Label = main._target_confirm_panel.find_child("target_title", true, false)
	var instruction_label: Label = main._target_confirm_panel.find_child(
		"target_instruction", true, false)
	var skill_label: Label = main._target_confirm_panel.find_child("skill_line", true, false)
	var target_label: Label = main._target_confirm_panel.find_child("target_line", true, false)
	assert_eq(title_label.modulate, main.COLOR_BOSS_PANEL_TEXT)
	assert_eq(instruction_label.modulate, main.COLOR_BOSS_PANEL_TEXT)
	assert_eq(skill_label.modulate, main.COLOR_BOSS_PANEL_TEXT)
	assert_eq(target_label.modulate, main.COLOR_BOSS_PANEL_TEXT)

	var arm_row: Dictionary = main._boss_part_rows["arm"]
	var name_label: Label = arm_row["name"]
	var text_label: Label = arm_row["text"]
	assert_eq(name_label.modulate, main.COLOR_BOSS_PANEL_TEXT)
	assert_eq(text_label.modulate, main.COLOR_BOSS_PANEL_TEXT)
