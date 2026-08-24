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
	# rewind2_unlockedは恒久データ(実際のuser://セーブに保存される、sim.gd
	# 参照)——このヘルパーは「フレッシュな未解放状態」を前提にした複数の
	# テストで共有されるため、実際にF10で解放済みの状態のままディスクへ
	# 保存された実セーブを読み込んでいた場合でも各テストが自分の意図した
	# 前提から始められるよう、ここで明示的にfalseへ揃える（テスト自身の
	# 前提はテスト自身が制御する、というこのファイル既存の慣習
	# ——_start_cave_troll_fight()のstage_index上書きと同じ理由）。
	main.sim.rewind2_unlocked = false
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

	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
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
	# 引き伸ばしの影響を受けない`enemy_target_rows`（右側サブメニュー
	# 拡大・2026-08-28でVBoxContainerへ変更、主軸=縦方向の子なので伸縮
	# しない点は変わらない）自身の高さで直接確認する。
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
## 作られず、パネルは決定ボタンが画面内に収まる高さのままであること
## ——今回の変更が enemy_target_rows を持たない全ての既存フローに
## 影響していないことの直接的な確認。
## 右側サブメニュー拡大（2026-08-28）で案内文の可視条件を変更: 新設の
## ally_target_rows（党5人、常に非空）が選択肢そのものを示す以上、
## 同じ内容を繰り返すだけの案内文は敵/部位選択と同じ理由で隠す——これを
## 隠さないと縦方向の余白が足りず決定ボタンが画面外へ押し出される実機
## バグを作り込むところだった（実測して発見・修正済み）。
func test_battle_bar_stays_compact_and_confirm_reachable_for_an_ally_target() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main._enter_target_selection("attack", "", "ally")
	await get_tree().process_frame

	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 0, "no enemy row list for an ally-target selection")
	var ally_rows: VBoxContainer = main._target_confirm_panel.find_child(
		"ally_target_rows", true, false)
	assert_eq(ally_rows.get_child_count(), 5, "the new ally target row list is populated instead")
	var instruction_label: Label = main._target_confirm_panel.find_child(
		"target_instruction", true, false)
	assert_false(instruction_label.visible,
		"redundant now that ally_target_rows shows the choices directly")

	var confirm_button: Button = null
	var target_column: VBoxContainer = main._target_confirm_panel.get_child(0)
	var footer: HBoxContainer = target_column.get_child(target_column.get_child_count() - 1)
	confirm_button = footer.get_child(footer.get_child_count() - 1)
	var confirm_bottom: float = confirm_button.global_position.y + confirm_button.size.y
	assert_true(confirm_bottom <= float(UD.NORMAL_WINDOW_SIZE.y))


## --- REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」§5/§6/§38/§39、2026-08-28) -----
## §17と同じ理由でピクセル単位の見た目は検証できない——ここではGodotの
## Control幾何情報（位置・サイズ・visible）を直接読んで、①未解放時は
## 従来のREWIND/やめる2ボタンのままであること、②解放後はREWINDⅡが
## REWINDの直下に現れやめるがさらに下へ動的に押し出されること、③3ボタン
## いずれも常に設計空間（1152×648、content_scaleにより実ウィンドウの
## 物理サイズに関わらず一定）の内側に収まること、を確認する。


func test_rewind2_button_hidden_and_layout_unchanged_when_locked() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	assert_false(main.sim.rewind2_unlocked, "real data starts locked")

	assert_false(main._rewind2_button.visible, "§5: hidden while locked")
	assert_almost_eq(main._leave_battle_button.offset_top,
		main.LEAVE_BUTTON_TOP_WITHOUT_REWIND2, 0.01, "§5: やめる stays at its original slot")
	assert_true(main._quit_battle_button.visible)
	assert_true(main._leave_battle_button.visible)


func test_rewind2_button_appears_between_rewind_and_leave_once_unlocked() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main.sim.set_rewind2_unlocked(true)
	main._refresh_rewind2_button()

	assert_true(main._rewind2_button.visible, "§6: shown once unlocked")
	assert_eq(main._rewind2_button.text, "REWINDⅡ", "§7: exact label, no alternate spelling")
	assert_almost_eq(main._rewind2_button.offset_top, main.REWIND2_BUTTON_TOP, 0.01)
	assert_almost_eq(main._leave_battle_button.offset_top,
		main.LEAVE_BUTTON_TOP_WITH_REWIND2, 0.01, "§38: やめる is pushed below REWINDⅡ")
	# §39: all three stay within the fixed design window regardless of the
	# physical window size (content_scale keeps this space constant, see
	# the earlier tests in this file) -- REWIND is anchored above REWINDⅡ,
	# which must sit strictly below it with やめる strictly below that.
	assert_lt(main._quit_battle_button.offset_bottom, main._rewind2_button.offset_top + 0.01)
	assert_lt(main._rewind2_button.offset_bottom, main._leave_battle_button.offset_top + 0.01)
	assert_true(main._leave_battle_button.offset_bottom <= float(UD.NORMAL_WINDOW_SIZE.y),
		"§39: does not spill past the bottom of the design window")


func test_rewind2_button_disabled_after_use_but_not_before() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main.sim.set_rewind2_unlocked(true)
	main._refresh_rewind2_button()
	assert_false(main._rewind2_button.disabled, "§22: clickable while there is still something to do")

	main.sim.set_mid_checkpoint()
	main.sim.use_rewind2()
	main._refresh_rewind2_button()

	assert_true(main._rewind2_button.disabled, "§24: disabled once spent for this fight")


## §19/§20/§21/§22/§34: ボタンを押した瞬間の状態で確認文が切り替わり、
## 味方コマンド入力待ち中(commandSelection)以外では何も開かない。
func test_rewind2_button_opens_set_then_use_confirm_text_and_ignores_other_phases() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	main.sim.set_rewind2_unlocked(true)
	main._refresh_rewind2_button()
	assert_eq(main._battle_phase, "commandSelection")

	main._on_rewind2_button_pressed()
	assert_true(main._rewind2_confirm_panel.visible, "§21: opens while safely in commandSelection")
	var text_label: Label = main._rewind2_confirm_panel.find_child("text", true, false)
	assert_eq(text_label.text, main.locale.text("UI_REWIND2_SET_CONFIRM_TEXT"), "§21: not yet set")

	main._on_rewind2_confirm()
	assert_true(main.sim.mid_checkpoint_set)
	assert_false(main._rewind2_confirm_panel.visible, "confirming closes the panel")

	main._on_rewind2_button_pressed()
	assert_eq(text_label.text, main.locale.text("UI_REWIND2_USE_CONFIRM_TEXT"),
		"§22/§23: already set -- the button now means 'return', same label though (§7)")
	main._rewind2_confirm_panel.visible = false  # cancel without using it yet

	# §19/§20/§34: not a safe moment (a submenu is open) -- must be ignored.
	main._battle_phase = "targetSelection"
	main._on_rewind2_button_pressed()
	assert_false(main._rewind2_confirm_panel.visible,
		"§19/§20/§34: mid target-selection is not commandSelection, click is ignored")


## §37 実機報告「REWINDⅡのボタンがない」への対応: 正式なストーリー上の
## 解放イベントはまだ無い(§4)ため、F9(_debug_boss_loop)と同じ「本番UIには
## 一切現れないキーボードショートカット」としてF10でsim.rewind2_unlocked
## を直接トグルする——実機で今すぐ確認できるようにするための唯一の
## 現行の解放手段。
func test_f10_debug_toggle_unlocks_and_relocks_rewind2() -> void:
	var main := await _start_expanded_main()
	_start_cave_troll_fight(main)
	assert_false(main.sim.rewind2_unlocked)
	assert_false(main._rewind2_button.visible)

	main._debug_toggle_rewind2_unlocked()
	assert_true(main.sim.rewind2_unlocked, "F10 unlocks REWINDⅡ")
	assert_true(main._rewind2_button.visible, "the button appears immediately, no fight restart needed")

	main._debug_toggle_rewind2_unlocked()
	assert_false(main.sim.rewind2_unlocked, "pressing it again re-locks it")
	assert_false(main._rewind2_button.visible)
