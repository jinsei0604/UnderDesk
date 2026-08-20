extends GutTest
## 下部UI再整理（2026-08-23b）: ①バー上端の重複した3本線→1本②円の全身
## クリアランスを保ったままバーを少し高く③カード/コマンド間の巨大な
## 空白を解消し5人を均等な幅へ再配分、の3点をmain.tscn実インスタンス化
## で直接検証する。ピクセル単位の見た目そのものはこの環境では検証
## できない（既存の制約）——ここではジオメトリ/StyleBoxの状態だけを
## 確認し、目視確認はユーザーの実機プレイに委ねる。

const GATE_10_STAGE_INDEX := 10


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
	main._show_boss_panel()
	return main


## §3/§4「上端の3本線を1本に」: 真因はバー自身の上端borderのすぐ内側で、
## バトルメッセージパネル自身の上下borderが密集して重なっていたこと——
## メッセージパネルのborderをゼロにし、バー自身のborderだけが残ることを
## 直接確認する。
func test_message_panel_has_no_border_leaving_only_the_bars_own_top_line() -> void:
	var main := await _start_cave_troll_fight()
	var bar_style: StyleBoxFlat = main._battle_bar.get_theme_stylebox("panel")
	var message_style: StyleBoxFlat = main._battle_message_panel.get_theme_stylebox("panel")
	assert_gt(bar_style.border_width_top, 0, "the bar itself keeps its single top border line")
	assert_eq(message_style.border_width_top, 0,
		"battle message panel no longer draws its own border (was a duplicate line)")
	assert_eq(message_style.border_width_bottom, 0,
		"...on every side, not just the top (its bottom border was the 3rd line)")


## §1「もう一段バーを広げる」×「円の全身が見える／少し余白が残る」の
## 両立: 対象選択(3行)＋バトルメッセージ3行という、このプロジェクトで
## 確立済みの最悪ケースで、月夜円(unit 1)の足元がバーの上端より確実に
## 上にある（＝隠れていない）ことを直接検証する。
func test_madoka_stays_fully_clear_of_the_bar_in_the_worst_case() -> void:
	var main := await _start_cave_troll_fight()
	var madoka_feet_y: float = main.PARTY_FORMATION_BOSS[1].y * main.size.y

	main._battle_selected_unit = 0
	main._enter_target_selection("attack", "", "enemy")
	main._append_battle_message("line one")
	main._append_battle_message("line two")
	main._append_battle_message("line three")
	await get_tree().process_frame

	var rows_container: HFlowContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")

	var bar_top: float = main._battle_bar.global_position.y
	assert_true(bar_top > madoka_feet_y,
		"bar top (%f) stays below Madoka's feet (%f) — she is not covered" % [bar_top, madoka_feet_y])
	var margin := bar_top - madoka_feet_y
	assert_true(margin > 1.0, "a small but real margin remains (%f px)" % margin)


## §7/§8「5人を均等な幅で少し広げる」: 手で揃えた同じ定数ではなく、
## Godotのsize_flags_horizontal=EXPAND_FILL（既定stretch_ratio=1ずつ）
## による構造的な均等分配であること——全5枚が厳密に同じ幅になること、
## かつ立ち絵撤去前(96px)より広いことを確認する。
func test_all_five_cards_end_up_equal_width_and_wider_than_before() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var widths: Array[float] = []
	for unit_id in range(5):
		var card: PanelContainer = main._battle_cards[unit_id]["panel"]
		widths.append(card.size.x)
	# GodotのEXPAND_FILL均等分配は660pxを5等分する際に割り切れず(132each
	# だが8px separation×4=32を先に引くため125.6/枚)、整数pxへ丸める過程
	# で最大1px差が出る（125/126の混在）——これは意図した"均等配分"の
	# 正常な副作用であり、実測でも許容誤差1px以内に収まることを確認する
	# （厳密な完全一致ではなく現実的な許容範囲での検証）。
	for w in widths:
		assert_almost_eq(w, widths[0], 1.5, "all 5 cards measure ~the same width (%s)" % [widths])
	assert_gt(widths[0], 100.0, "wider than the pre-round 96px fixed width")


## §5/§6/§10「巨大な空白を残さず横幅を使い切る、ただし新情報は足さない」:
## cards_row+commands_column（またはtarget_confirm_panel）の合計がrowの
## 大半を占め、残りの左右marginが「既存UI程度」の妥当な範囲に収まる
## こと——中央に不自然に巨大な空白帯が残っていないことの直接的な証拠。
func test_no_giant_dead_gap_between_cards_and_commands() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var cards_row: HBoxContainer = main._battle_bar.find_child("cards", true, false)
	var row: HBoxContainer = main._commands_column.get_parent()
	var used_width: float = cards_row.size.x + main._commands_column.size.x
	var leftover: float = row.size.x - used_width
	# 「巨大な空白」だった旧状態（2026-08-22d以前）はcards+commandsの
	# 合計がrow幅の半分にも満たなかった——今回は7割以上を実際のコンテンツ
	# が占め、残りは既存UI程度の左右marginとして妥当な範囲であることを
	# 両方向から確認する。
	assert_true(used_width > row.size.x * 0.7,
		"cards+commands occupy most of the row's width (%f of %f)" % [used_width, row.size.x])
	assert_true(leftover < row.size.x * 0.3,
		"leftover margin stays modest, not a giant dead gap (%f of %f)" % [leftover, row.size.x])
