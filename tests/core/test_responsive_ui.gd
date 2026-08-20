extends GutTest
## レスポンシブUI基盤（2026-08-21、実機報告「ウィンドウを小さくすると
## 部位選択欄が見切れる／全画面にするとUIが相対的に小さく見える」への
## 対応）: この環境には実レンダラーが無くピクセル単位の見た目は検証
## できない（このプロジェクト全体で確立済みの制約）ため、①Godotの
## Window.content_scale設定が意図どおり適用/非適用されること、②実
## ウィンドウの物理サイズが変わっても main.gd の設計空間サイズ
## （size、_view_rect()が使う値）が常に一定に保たれること（＝画面の
## どんな物理サイズでもGodot自身が一様拡縮＋レターボックスで吸収する
## という土台が機能していること）、③対象選択パネルが部位行数ぶんの
## 高さへ実際に自動で伸び、決定ボタンが常に画面内に収まること、を
## ロジック/ジオメトリのレベルで直接検証する。


const GATE_10_STAGE_INDEX := 10  # data/stages/020_gate10.json, cave_troll's gate


func _start_expanded_main() -> Control:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	var main: Control = add_child_autofree(scene.instantiate())
	if not main.is_node_ready():
		await main.ready
	main.autosave_timer.stop()
	main.tick_timer.stop()
	# _ready() already calls _apply_window_mode() once using whatever
	# settings.resident_mode happened to load as; force expanded mode
	# explicitly rather than depending on that default.
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
	assert_eq(main.sim.boss_enemy_id, "cave_troll")
	main._show_boss_panel()


func test_expanded_window_applies_canvas_items_content_scale_pinned_to_normal_window_size() -> void:
	var main := await _start_expanded_main()
	var window := main.get_window()
	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_KEEP)
	assert_eq(window.content_scale_size, UD.NORMAL_WINDOW_SIZE)


func test_resident_mode_disables_content_scale() -> void:
	var main := await _start_expanded_main()
	main._collapse()
	assert_eq(main.get_window().content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED)
	# Switching back to expanded must re-arm it (toggling back and forth
	# during a real play session must not leave stretch permanently off).
	main._expand()
	assert_eq(main.get_window().content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)


## 根本原因B（全画面/小ウィンドウでUIサイズが不適切）の直接的な証拠:
## OSウィンドウの物理pxをどれだけ小さく/大きくしても、main.gd自身が
## 参照する設計空間サイズ（Control.size、_view_rect()の入力）は常に
## UD.NORMAL_WINDOW_SIZEのまま——個々のControlのfixed offsetやフォント
## サイズを一切変更しなくても、見切れも相対的な縮小も構造的に起こり
##得ないことを示す。
func test_design_space_size_stays_pinned_regardless_of_physical_window_size() -> void:
	var main := await _start_expanded_main()
	var window := main.get_window()

	window.size = Vector2i(640, 360)  # 小さいウィンドウを模擬
	await get_tree().process_frame
	assert_eq(main.size, Vector2(UD.NORMAL_WINDOW_SIZE), "small window: design size unchanged")
	# _view_rect()（戦闘UI全体が依存する中心的なrect計算）自体も、pinned
	# された設計空間サイズから導出されるぶんには常に同じ値になる——
	# 物理ウィンドウが小さくなってもこの計算自体は破綻しない。
	var view_at_small: Rect2 = main._view_rect()

	window.size = Vector2i(2560, 1440)  # 大きい/全画面相当を模擬
	await get_tree().process_frame
	assert_eq(main.size, Vector2(UD.NORMAL_WINDOW_SIZE), "large window: design size unchanged")
	var view_at_large: Rect2 = main._view_rect()
	assert_eq(view_at_small.size, view_at_large.size,
		"view_rect is identical across wildly different physical window sizes")

	window.size = UD.NORMAL_WINDOW_SIZE  # 元へ戻す
	await get_tree().process_frame
	assert_eq(main.size, Vector2(UD.NORMAL_WINDOW_SIZE))


## 根本原因A（対象選択パネルの固定高オーバーフロー）の直接的な証拠:
## cave_troll（本体+右腕+脚の3対象）でtarget selectionへ入ると、行
## リストは旧来の固定168pxでは収まらない高さを要求する——barが実際に
## それに合わせて伸び、決定/もどるボタンが常にウィンドウ内（画面外に
## 押し出されていない）ことを検証する。
func test_battle_bar_grows_to_fit_all_target_rows_without_clipping_the_confirm_button() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "enemy")
	await get_tree().process_frame

	var rows_container: HFlowContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")

	# grow_vertical=BEGIN による自動拡張の直接確認: 「旧来の固定168px」
	# という決め打ちの数値との比較は、下部操作バー圧縮（2026-08-22c）
	# で3行分がその168pxよりずっと小さく収まるよう意図的に縮小した
	# ことで意味を失った（超えないことがむしろ正しい）——代わりに
	# ボスバナー側と同じ「行が0件/3件で実測サイズが確かに違う」という
	# 証拠ベースの確認へ差し替えた。
	# 下部操作バー再調整（2026-08-22d）で再度差し替え: カード列（左側の
	# キャラクター情報欄）を少し大きく戻した結果、`cards_row`の方が
	# `_target_confirm_panel`より常に高くなり、`row`（＝`_battle_bar`）
	# 全体の高さの決定要因になった——`_target_confirm_panel`自体は
	# HBoxContainerの交差軸（縦）でrowの高さいっぱいへ引き伸ばされる
	# ため、部位行が3件→0件に減っても`_target_confirm_panel.size.y`
	# すら変化しない（実測で確認済み、`_battle_bar`のケースと同じ理由の
	# 見かけ上の頭打ち——バグではなく意図したトレードオフの結果）。
	# 「行数に応じて自動的に高さを決め直す」という主張自体は、この
	# 引き伸ばしの影響を受けない`enemy_target_rows`（HFlowContainer、
	# VBoxContainerの主軸=縦方向の子なので伸縮しない）自身の高さで
	# 直接確認する。
	var rows_height_with_3: float = rows_container.size.y
	for child in rows_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	var rows_height_with_0: float = rows_container.size.y
	assert_lt(rows_height_with_0, rows_height_with_3,
		"enemy target row list shrinks when there are fewer rows to show (%f vs %f)"
		% [rows_height_with_0, rows_height_with_3])

	# target_footer's 決定 button has no explicit .name — it's the last
	# child of target_column's last child (the footer HBoxContainer).
	var target_column: VBoxContainer = main._target_confirm_panel.get_child(0)
	var footer: HBoxContainer = target_column.get_child(target_column.get_child_count() - 1)
	var confirm_button: Button = footer.get_child(footer.get_child_count() - 1)
	assert_true(confirm_button.text == main.locale.text("UI_BOSS_CONFIRM"))

	# 決定ボタンの下端が、設計空間の高さ（UD.NORMAL_WINDOW_SIZE.y）を
	# 超えて画面外へ押し出されていないこと——これが今回のバグ報告その
	# もの（見切れて攻撃できない）に対する直接的な回帰ガード。
	var confirm_bottom: float = confirm_button.global_position.y + confirm_button.size.y
	assert_true(confirm_bottom <= float(UD.NORMAL_WINDOW_SIZE.y),
		"confirm button bottom (%f) stays within the design canvas height (%d)"
		% [confirm_bottom, UD.NORMAL_WINDOW_SIZE.y])

	# 上部のボスHPバナー（§9, 同じ理由で"部位数が増えても見切れない"
	# ことが要求される）も同じgrow_vertical=ENDパターンへ切り替え済み。
	# cave_trollの部位2個は旧来の固定130px枠に実は収まっていた（何px
	# 分か余裕があった）ため、「決め打ちの数値と比較する」形では auto-
	# growが実際に機能していることを証明できない——代わりに、行が
	# 0件のとき（将来ありうる部位無しボス）と2件のときで実測サイズが
	# 確かに違う（＝内容に連動して伸縮している）ことを直接確認する。
	await get_tree().process_frame
	var banner_height_with_2_parts: float = main._boss_banner.size.y
	for child in main._boss_parts_column.get_children():
		child.queue_free()
	await get_tree().process_frame
	var banner_height_with_0_parts: float = main._boss_banner.size.y
	assert_lt(banner_height_with_0_parts, banner_height_with_2_parts,
		"boss banner shrinks when there are fewer part rows to show (%f vs %f)"
		% [banner_height_with_0_parts, banner_height_with_2_parts])
	var banner_bottom: float = main._boss_banner.global_position.y + banner_height_with_2_parts
	assert_true(banner_bottom < float(UD.NORMAL_WINDOW_SIZE.y) * 0.5,
		"boss banner (at its taller, 2-part size) stays within the top half of the design canvas")

	# 案内文（instruction）が行リストと重複しないよう隠れていること
	# （§5, 縦スペースの再利用）。
	var instruction_label: Label = main._target_confirm_panel.find_child(
		"target_instruction", true, false)
	assert_false(instruction_label.visible, "instruction line hides once row list is shown")


## 味方対象（回復など）の場合の後方互換確認: 敵側の行リストは一切
## 作られず、案内文は表示されたまま、パネルは今まで通りコンパクトな
## ままであること——今回の変更が enemy_target_rows を持たない全ての
## 既存フローに影響していないことの直接的な確認。
func test_battle_bar_stays_compact_and_confirm_reachable_for_an_ally_target() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "ally")
	await get_tree().process_frame

	var rows_container: HFlowContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 0, "no enemy row list for an ally-target selection")
	var instruction_label: Label = main._target_confirm_panel.find_child(
		"target_instruction", true, false)
	assert_true(instruction_label.visible)

	var confirm_button: Button = null
	var target_column: VBoxContainer = main._target_confirm_panel.get_child(0)
	var footer: HBoxContainer = target_column.get_child(target_column.get_child_count() - 1)
	confirm_button = footer.get_child(footer.get_child_count() - 1)
	var confirm_bottom: float = confirm_button.global_position.y + confirm_button.size.y
	assert_true(confirm_bottom <= float(UD.NORMAL_WINDOW_SIZE.y))
