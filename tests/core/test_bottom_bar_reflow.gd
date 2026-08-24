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
## メッセージパネル自身の上端borderをゼロのままにし（バー自身の上端
## borderと隣接する側なので再度重ねると同じ3本線バグが再発する）、
## バー自身のborderだけが唯一の境界線として残ることを直接確認する。
## 下部UI微調整（2026-08-25b、§8-§11「バトルメッセージ欄の下にも境界線
## を1本追加」）: 下端borderは意図的にゼロではなくなった——「戦闘盤面│
## バトルメッセージ│ステータス」を上下1本ずつの線で区切るのが今回の
## 目的そのもの（上端はバーの境界と重複するので付けない、下端は他に
## 重複する境界が無いので単独の1本として安全に追加できる）。太さは
## バー自身の上端borderと同じ値であること、色も既存の金・黄土系border_
## colorと完全一致していることまで確認する（§11「装飾ではなく既存
## デザインと統一」）。
func test_message_panel_has_a_single_bottom_border_matching_the_bars_own_line() -> void:
	var main := await _start_cave_troll_fight()
	var bar_style: StyleBoxFlat = main._battle_bar.get_theme_stylebox("panel")
	var message_style: StyleBoxFlat = main._battle_message_panel.get_theme_stylebox("panel")
	assert_gt(bar_style.border_width_top, 0, "the bar itself keeps its single top border line")
	assert_eq(message_style.border_width_top, 0,
		"no top border on the message panel — would duplicate the bar's own top line")
	assert_eq(message_style.border_width_left, 0)
	assert_eq(message_style.border_width_right, 0)
	assert_gt(message_style.border_width_bottom, 0,
		"exactly one new line: the message panel's bottom edge")
	assert_eq(message_style.border_width_bottom, bar_style.border_width_top,
		"same thickness as the bar's existing top line, not a heavier decorative line (§11)")
	assert_eq(message_style.border_color, bar_style.border_color,
		"same gold/ochre color already used elsewhere in the UI (§9/§11)")


## §1「もう一段バーを広げる」×「円の全身が見える／少し余白が残る」の
## 両立: 対象選択(3行)＋バトルメッセージという、このプロジェクトで
## 確立済みの最悪ケースで、月夜円(unit 1)の足元がバーの上端より確実に
## 上にある（＝隠れていない）ことを直接検証する。
## バトルメッセージ側の"最悪ケース"の定義(2026-09-02、実機報告「すべて
## 1行表示は採用しない」)——味方の行動は宣言＋結果の2行構成のままなので
## (test_battle_message.gdで直接検証済み)、メッセージパネル自身にとって
## 最も高さを要求するのは"味方2行が両方とも表示されている"状態。敵1行
## (Boss Action Setの予兆等)は床(BATTLE_MESSAGE_PANEL_FLOOR_HEIGHT)に
## よって味方2行と同じ高さへ揃えられるため、どちらの内容でもこの最悪
## ケースの高さは変わらない。
func test_madoka_stays_fully_clear_of_the_bar_in_the_worst_case() -> void:
	var main := await _start_cave_troll_fight()
	var madoka_feet_y: float = main.PARTY_FORMATION_BOSS[1].y * main.size.y

	main._battle_selected_unit = 0
	main._enter_target_selection("attack", "", "enemy")
	main._append_battle_message("サユの攻撃！")
	main._append_battle_message("洞窟トロルに84ダメージ！")
	await get_tree().process_frame

	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")

	var bar_top: float = main._battle_bar.global_position.y
	assert_true(bar_top > madoka_feet_y,
		"bar top (%f) stays below Madoka's feet (%f) — she is not covered" % [bar_top, madoka_feet_y])
	var margin := bar_top - madoka_feet_y
	assert_true(margin > 1.0, "a small but real margin remains (%f px)" % margin)


## 下部固定バーとサブメニューの分離 (2026-08-27b、実機報告「NEXT5・
## ステータス・コマンドが横へ圧縮された」): スキル一覧(_battle_list_panel)
## は下部バーの`row`スロットには一切参加しない独立した上側領域——円
## (unit 1、このプロジェクトの全キャラ中最多の5スキル保有)自身の一覧を
## 開いても、下部バーの高さ・Y位置は数式上一切変化しないはず（対象選択の
## 追加行やバトルメッセージが乗っても同様）。単なる「隠れない」という
## 緩い確認ではなく、バー自体の座標がbyte-identicalのまま不変であることを
## 直接検証する——より強く、より正確にこの回帰を捉える。
func test_madokas_5_skill_list_never_moves_the_bar_at_all() -> void:
	var main := await _start_cave_troll_fight()
	# メッセージの有無はバーの高さへ意図的に(既存の確立済み挙動として)
	# 影響する——「変化しない」を検証したいのはスキル一覧の開閉だけなので、
	# メッセージ状態を先に固定してから、その前後でバーの矩形を比較する
	# （2つの独立した変数を1回の比較に混ぜない）。味方2行構成
	# (2026-09-02)の完全な状態(宣言＋結果)を固定して比較する。
	main._append_battle_message("サユの攻撃！")
	main._append_battle_message("洞窟トロルに84ダメージ！")
	await get_tree().process_frame
	var bar_rect_before: Rect2 = main._battle_bar.get_global_rect()

	main._battle_selected_unit = 1
	main._on_battle_skill()
	assert_eq(main._battle_list_entries.size(), 5, "sanity: 円 has all 5 skills listed")
	await get_tree().process_frame

	assert_eq(main._battle_bar.get_global_rect(), bar_rect_before,
		"opening 円's 5-skill list must not move the fixed bottom bar at all")


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
## next_column+cards_row+commands_column（またはtarget_confirm_panel）の
## 合計がrowの大半を占め、残りの左右marginが「既存UI程度」の妥当な範囲に
## 収まること——中央に不自然に巨大な空白帯が残っていないことの直接的な
## 証拠。
## 下部UI横幅再配分（2026-08-25）: NEXT5追加に伴いnext_columnも「使用中の
## 幅」の一部として数えるよう更新——旧assertion(cards+commandsのみ)は
## next_columnを無視していたため、cards/commandsをコマンド4個収容の
## ため縮小した今回は0.7の閾値をわずか0.17%の余裕でしか満たさない、
## 壊れやすい状態になっていた（next_columnの存在自体は正当な"使用中の
## 幅"であり空白ではないため、計算に含めないこと自体が実態とズレていた）。
func test_no_giant_dead_gap_between_cards_and_commands() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var cards_row: HBoxContainer = main._battle_bar.find_child("cards", true, false)
	var row: HBoxContainer = main._commands_column.get_parent()
	var used_width: float = (
		main._battle_next_column.size.x + cards_row.size.x + main._commands_column.size.x)
	var leftover: float = row.size.x - used_width
	# 「巨大な空白」だった旧状態（2026-08-22d以前）はcards+commandsの
	# 合計がrow幅の半分にも満たなかった——今回は7割以上を実際のコンテンツ
	# が占め、残りは既存UI程度の左右marginとして妥当な範囲であることを
	# 両方向から確認する。
	assert_true(used_width > row.size.x * 0.7,
		"next+cards+commands occupy most of the row's width (%f of %f)" % [used_width, row.size.x])
	assert_true(leftover < row.size.x * 0.3,
		"leftover margin stays modest, not a giant dead gap (%f of %f)" % [leftover, row.size.x])


## 下部UI横幅再配分（2026-08-25）: NEXT5追加で横幅が逼迫し「どうぐ」が
## 右へ見切れていた実機報告への対応。§16の4点をmain.tscn実インスタンス
## 化で直接検証する——ピクセル描画そのものはこの環境では検証できない
## ため、Containerの実測サイズ・子構成をもって代替する（このプロジェクト
## の確立済み手法）。

## §6/§8: こうげき/スキル/防御/どうぐの4つが、2×2グリッド（1行目=
## こうげき・スキル、2行目=防御・どうぐ、§6の配置図のとおり）として
## 揃っており、防御用の枠だけが欠けている状態になっていないこと。
func test_all_four_commands_exist_in_a_two_by_two_grid() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var grid: GridContainer = main._commands_column.get_child(0)
	assert_eq(grid.columns, 2)
	assert_eq(grid.get_child_count(), 4, "attack, skill, defend, item — all 4 slots present")
	assert_eq(grid.get_child(0), main._battle_attack_button, "row1 col1: こうげき")
	assert_eq(grid.get_child(1), main._battle_skill_button, "row1 col2: スキル")
	assert_eq(grid.get_child(2), main._battle_defend_button, "row2 col1: 防御")
	assert_eq(grid.get_child(3), main._battle_item_button, "row2 col2: どうぐ")


## §8: 空文字列のラベルではなく、読める大きさであること。
## Phase 6（2026-08-25）: 防御は正式実装されたため、「常時disabled」の
## 旧アサーションは撤回——押せる/押せないの条件自体は
## tests/core/test_battle_defend.gdのcurrent_actor連動テストで直接検証
## する（他3コマンドと同じ_update_battle_buttons()経由）。
func test_defend_button_has_a_readable_label_and_size() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	assert_false(main._battle_defend_button.text.is_empty())
	assert_gt(main._battle_defend_button.size.x, 20.0, "not shrunk to an unreadable sliver (§6)")
	assert_gt(main._battle_defend_button.size.y, 20.0)


## §16-7/最重要: NEXT5＋5人ステータス＋4コマンドの3ブロックの実測合計幅
## （間の固定separationを含む）が、rowが実際に受け取れる幅を超えない
## こと——「どうぐが見切れる」実機バグの直接的な回帰テスト。旧実装では
## next_column(118)+cards_row(660)+commands_column(実測natural~312、
## floor260は自然幅未満で機能していなかった)+separation(28×2)の合計
## ≈1146pxが、row側の実測幅(~1126px)を上回っていた。
func test_command_row_content_never_overflows_the_available_width() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var row: HBoxContainer = main._commands_column.get_parent()
	var separation: int = row.get_theme_constant("separation")
	var content_width: float = (
		main._battle_next_column.size.x + separation
		+ main._battle_bar.find_child("cards", true, false).size.x + separation
		+ main._commands_column.size.x)

	assert_true(content_width <= row.size.x + 0.5,
		"3 blocks + 2 gaps (%f) fit within row's actual width (%f) — nothing pushed off-screen"
			% [content_width, row.size.x])


## §9/§10: 2×2化でコマンド欄の"自然な"高さがcards_row側の高さを上回り、
## それがバー全体の新しい支配要因になっていないこと（=バーが大きく上へ
## 伸びていない、円の全身表示が引き続き維持される）。
func test_two_by_two_commands_do_not_become_the_bars_new_height_driver() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var cards_row: HBoxContainer = main._battle_bar.find_child("cards", true, false)
	var grid: GridContainer = main._commands_column.get_child(0)
	assert_true(grid.size.y <= cards_row.size.y + 0.5,
		"the 2x2 grid's own height (%f) does not exceed cards_row's (%f), so cards_row keeps driving bar height"
			% [grid.size.y, cards_row.size.y])


## 下部UI微調整（2026-08-25b）: §1-§4「右側の余白を4コマンドへ再配分、
## 4つとも同じサイズへ」の回帰テスト群。

## §3: こうげき/スキル/防御/どうぐの4つが厳密に同一サイズであること
## （旧実装は各アイコンの実アスペクト比からwidthを逆算していたため、
## 攻撃83.25px/スキル79.0px/どうぐ79.37pxとわずかにバラついていた——
## 今回は共通のcell_sizeを明示するため、ぴったり一致するはず）。
func test_all_four_command_buttons_are_exactly_the_same_size() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var sizes: Array[Vector2] = [
		main._battle_attack_button.size, main._battle_skill_button.size,
		main._battle_defend_button.size, main._battle_item_button.size]
	for s in sizes:
		assert_eq(s, sizes[0],
			"attack/skill/defend/item must be pixel-identical in size (%s)" % [sizes])


## §2/§15: 前ラウンド（NEXT5導入直後、2026-08-25a）の44pxアイコン高さ
## から、今回明確に大きくなっていること——「少し大きく」が実際に反映
## されていることの直接証拠。
func test_command_buttons_grew_from_the_previous_rounds_size() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	assert_gt(main._battle_attack_button.size.y, 44.0, "taller than 2026-08-25a's 44px icons")
	assert_gt(main._battle_attack_button.size.x, 83.25,
		"wider than 2026-08-25a's widest button (attack, 83.25px)")


## §5: NEXT欄・5人ステータス欄は今回の対象外——コマンド欄拡大の原資は
## rowの余った横幅のみで、これら2つの幅は前ラウンドから変化していない
## こと（読みやすさを圧迫していない、の直接的な裏付け）。
func test_next_column_and_cards_row_widths_are_unchanged_from_the_prior_round() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	assert_eq(main._battle_next_column.size.x, 108.0, "§5: NEXT column untouched this round")
	assert_eq(main._battle_bar.find_child("cards", true, false).size.x, 620.0,
		"§5: 5-character status row untouched this round")


## §1/§4: コマンド欄が広がった分だけ、rowの左右に残る余白（=前ラウンド
## で「使われていない余白」として報告された部分）が明確に縮小している
## こと。ゼロにはしない（§4「適切な左右marginは残してください」）ため、
## 上限側の妥当な範囲も合わせて確認する。
func test_leftover_margin_shrank_but_did_not_disappear() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var row: HBoxContainer = main._commands_column.get_parent()
	var separation: int = row.get_theme_constant("separation")
	var used_width: float = (
		main._battle_next_column.size.x + separation
		+ main._battle_bar.find_child("cards", true, false).size.x + separation
		+ main._commands_column.size.x)
	var leftover: float = row.size.x - used_width

	assert_lt(leftover, 180.0, "smaller than the prior round's ~180px leftover (§1 reassigns it)")
	assert_gt(leftover, 0.0, "still a real, positive margin — buttons are not edge-to-edge (§4)")


## §8: 防御プレースホルダーの文字列が、拡大後のセル幅からcontent_margin
## を引いた実際の描画可能幅に収まること（ピクセル描画そのものの確認は
## この環境では不可能なため、フォントメトリクスによる数値的な代替
## 証明——このプロジェクトの確立済み手法）。
func test_defend_button_label_fits_within_its_own_enlarged_cell() -> void:
	var main := await _start_cave_troll_fight()
	await get_tree().process_frame

	var button: Button = main._battle_defend_button
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var content_margin: float = button.get_theme_stylebox("normal").content_margin_left \
		+ button.get_theme_stylebox("normal").content_margin_right
	assert_lt(text_width, button.size.x - content_margin,
		"「防御」at the new font size still fits inside the button without overflowing")
