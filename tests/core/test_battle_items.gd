extends GutTest
## HP/SPポーション (2026-08-25、追加仕様§1-23、"どうぐ"実装のTask D0) の
## UI層回帰テスト。回復量・所持数の増減・REWINDでの完全復元・データ駆動
## の回復率といったsimロジックはtests/core/test_boss_fight.gdで既に直接
## 検証済み——ここでは「どうぐ→対象選択→使用→効果適用→行動終了→次の
## 行動者」という新戦闘進行システムの1行動フローに、こうげき/スキル/
## 防御と全く同じ形でどうぐも乗ること（追加仕様§1-5）を、main.tscn実
## インスタンス化でしか検証できない配線として確認する。


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
	return main


func _pump_battle_animation(main: Control) -> void:
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 20000, "battle animation never settled")


func _battle_message_lines(main: Control) -> Array:
	var lines: Array = []
	for label: Label in main._battle_message_labels:
		if label.visible:
			lines.append(label.text)
	return lines


## §1-4/§28: 現在行動者→どうぐ→対象選択→使用、で実際にHPが回復し、
## 所持数が減り、行動が確定する（対象選択自体はこうげき/スキルと同じ
## targetSelectionフェーズを経由する）こと。
func test_using_hp_potion_via_the_full_ui_flow_heals_the_target_and_decrements_the_count() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1", "fixture assumption: Madoka acts first")
	var target_id := 0  # Sotiris -- a different unit than the actor
	main.sim.minions[target_id].hp = 10
	var expected_amount: int = main.sim.unit_max_hp(main.sim.minions[target_id]) * 0.3
	var counts_before: int = main.sim.battle_item_counts.get("hp_potion", -1)

	main._battle_selected_unit = 1
	main._enter_target_selection("item", "hp_potion", "ally")
	assert_eq(main._battle_phase, "targetSelection", "item use opens target selection, exactly like a skill")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.minions[target_id].hp, 10 + expected_amount)
	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), counts_before - 1)


## §3/§5: どうぐ使用は1行動を丸ごと消費し、その同じ行動者が続けて2つ目
## の行動を送ることはできない（current_actor_tokenが既に別のユニットへ
## 進んでいるため、sim側の入口ガードで弾かれる）。
func test_item_use_consumes_the_whole_turn_and_the_same_actor_cannot_chain_a_second_action() -> void:
	var main := await _start_cave_troll_fight()
	var actor_id := 1
	main.sim.minions[0].hp = 10

	main._battle_selected_unit = actor_id
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = 0
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_ne(main.sim.current_actor_token(), "ally:%d" % actor_id, "turn moved on to someone else")
	var boss_hp_before: int = main.sim.boss_hp
	var result: Dictionary = main.sim.resolve_player_action(actor_id, "attack")
	assert_true(result.is_empty(), "a stale second action from the same actor is rejected outright ({})")
	assert_eq(main.sim.boss_hp, boss_hp_before, "no damage landed from the rejected chained action")


## §4/§5: NEXTは実際のsim状態をそのまま反映し続ける——どうぐ使用専用の
## 停止・スキップは存在しない（他の3コマンドと全く同じ経路で進む）。
func test_next_progresses_normally_after_item_use() -> void:
	var main := await _start_cave_troll_fight()
	var next_before: Array = main.sim.peek_next_actors(5)

	main._battle_selected_unit = 1
	main.sim.minions[0].hp = 10
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = 0
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), next_before[0], "the actor who acted is now the current one, as NEXT predicted")


## §2/§4(例示): current_actor=円がヴァルドへHPポーションを使っても、
## 行動主体は円のまま——current_actorがヴァルドへ乗っ取られたりしない。
func test_using_an_item_on_another_ally_does_not_reassign_the_acting_unit() -> void:
	var main := await _start_cave_troll_fight()
	var actor_id := 1  # 円
	var target_id := 2  # ヴァルド
	main.sim.minions[target_id].hp = 5

	main._battle_selected_unit = actor_id
	main._enter_target_selection("item", "hp_potion", "ally")
	assert_eq(main._battle_selected_unit, actor_id, "picking a target never reassigns the acting unit")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()

	assert_eq(main._battle_selected_unit, actor_id, "confirming still leaves the actor as the one who chose")
	assert_gt(main.sim.minions[target_id].hp, 5, "the OTHER unit (Valdo) is the one who was actually healed")


## §35相当・追加仕様の実例（"サユはHPポーションを使った！"/"ヴァルドの
## HPが30回復した！"）に対応するバトルメッセージ文体を確認する。どうぐ
## 使用は味方カテゴリ・2行構成(2026-09-02)——宣言はこの行動の再生が
## 始まった瞬間に積まれ、回復が発生した後も消えずに残ったまま、回復結果
## が2行目として一緒に表示される。
func test_item_use_appends_the_expected_declaration_and_heal_messages() -> void:
	var main := await _start_cave_troll_fight()
	var actor_id := 1
	var target_id := 0
	main.sim.minions[target_id].hp = 10
	var expected_amount: int = main.sim.unit_max_hp(main.sim.minions[target_id]) * 0.3

	main._battle_selected_unit = actor_id
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()

	var actor_name: String = main._unit_display_name(main.sim.minions[actor_id])
	var item_name: String = main.locale.text(str(main.battle_item_db.get_item("hp_potion")["name_key"]))
	var target_name: String = main._unit_display_name(main.sim.minions[target_id])
	var expected_declare: String = main.locale.text("UI_BATTLE_MSG_ITEM_USE") % [actor_name, item_name]
	var expected_heal: String = main.locale.text("UI_BATTLE_MSG_HEAL") % [target_name, expected_amount]
	# 宣言は行動アニメの開始と同時に同期的に積まれる——tick無しでもう
	# 見えているはず。
	assert_has(_battle_message_lines(main), expected_declare)

	_pump_battle_animation(main)

	# 回復が発生した後も、宣言(1行目)は消えず、回復結果が2行目として
	# 一緒に残っている——味方カテゴリの2行構成(§2/§3)。
	var lines_after := _battle_message_lines(main)
	assert_has(lines_after, expected_heal)
	assert_has(lines_after, expected_declare, "the declare line stays alongside the heal result")
	assert_eq(lines_after.size(), 2, "%s" % [lines_after])


## §6/§11: 実際に回復した量(クランプ後)がメッセージへ載る——名目上の
## 30%ではなく、満タンで頭打ちになった実測値であること。
func test_item_message_shows_the_actual_clamped_amount_not_the_nominal_percentage() -> void:
	var main := await _start_cave_troll_fight()
	var actor_id := 1
	var target_id := 0
	var max_hp: int = main.sim.unit_max_hp(main.sim.minions[target_id])
	main.sim.minions[target_id].hp = max_hp - 3  # nominal 30% would overflow past max

	main._battle_selected_unit = actor_id
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.minions[target_id].hp, max_hp, "clamped to max")
	var target_name: String = main._unit_display_name(main.sim.minions[target_id])
	var expected_heal: String = main.locale.text("UI_BATTLE_MSG_HEAL") % [target_name, 3]
	assert_has(_battle_message_lines(main), expected_heal, "message shows the real 3, not the nominal amount")


## 追加修正 (2026-08-26、「満タン時でも使用可能」§3/§7): 満タン相手への
## HPポーション使用は、無言のno-opではなく「しかし%sのHPはすでに最大
## だった！」という専用の自然文を出す——「%sのHPが0回復した！」という
## 不自然な表現には絶対にならない。
func test_using_hp_potion_on_a_full_target_shows_the_already_full_message() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1
	var target_id := 0
	# fixture is already full HP right after _start_cave_troll_fight()'s heal.

	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	var target_name: String = main._unit_display_name(main.sim.minions[target_id])
	var lines := _battle_message_lines(main)
	assert_has(lines, main.locale.text("UI_BATTLE_MSG_ITEM_ALREADY_FULL_HP") % target_name)
	assert_false(lines.has(main.locale.text("UI_BATTLE_MSG_HEAL") % [target_name, 0]),
		"never falls back to the generic '0回復した' phrasing")


## SP版も同じ形。
func test_using_sp_potion_on_a_full_target_shows_the_already_full_sp_message() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1
	var target_id := 0

	main._enter_target_selection("item", "sp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	var target_name: String = main._unit_display_name(main.sim.minions[target_id])
	var lines := _battle_message_lines(main)
	assert_has(lines, main.locale.text("UI_BATTLE_MSG_ITEM_ALREADY_FULL_SP") % target_name)
	assert_false(lines.has(main.locale.text("UI_BATTLE_MSG_HEAL_SP") % [target_name, 0]))


## §6/8/9: 満タン相手への使用でも、NEXTは正しく次の行動者を予測したまま
## 進み(current_actor_tokenがpeek_next_actors[0]と一致)、REWINDで所持数
## ・HPとも戦闘開始時点へ完全に戻る——負傷相手への使用(既存テスト)とは
## 別に、満タン相手での経路も直接確認する。
func test_next_progresses_and_rewind_restores_counts_after_a_full_target_item_use() -> void:
	var main := await _start_cave_troll_fight()
	var next_before: Array = main.sim.peek_next_actors(5)
	main._battle_selected_unit = 1
	var target_id := 0
	var full_hp: int = main.sim.unit_max_hp(main.sim.minions[target_id])

	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), next_before[0], "NEXT correctly predicted who acts next")
	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), 2, "a full-target use still consumed a count")

	main._do_battle_rewind()

	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), 3, "REWIND restores the fight-start count")
	assert_eq(main.sim.minions[target_id].hp, full_hp)


## §12/§13、仕様変更 (2026-08-26、アイテムを必要としていなくても使える
## ように): 満タンのユニットも今は普通に対象候補リストへ出てくる——
## ally-target skill(ヒーリング等)と全く同じ_battle_ally_targets()を
## 使うため。戦闘不能のユニットだけは引き続き除外される(§11、蘇生不可)。
func test_full_hp_units_are_selectable_but_ko_units_are_still_excluded() -> void:
	var main := await _start_cave_troll_fight()
	# everyone starts at full HP right after _start_cave_troll_fight()'s heal.
	main.sim.minions[2].hp = 0  # KO'd

	var targets: Array = main._battle_ally_target_pool("item", "hp_potion")

	assert_true(targets.has(0), "a full-HP unit is still a valid target now")
	assert_false(targets.has(2), "a KO'd unit is never offered as a target (no revive)")


## §7/§9(checklist)、仕様変更 (2026-08-26): どうぐパネルの各エントリが、
## 実際の所持数とdata駆動の名前/説明を表示すること。enabledは残数の
## 有無だけで決まる——誰かが負傷しているかどうかに関わらず一貫して
## 使用可能。
func test_item_list_entries_reflect_real_counts_and_stay_enabled_regardless_of_who_needs_healing() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1

	main._on_battle_item()

	var by_label: Dictionary = {}
	for entry: Variant in main._battle_list_entries:
		by_label[str((entry as Dictionary)["label"])] = entry
	var hp_name: String = main.locale.text(str(main.battle_item_db.get_item("hp_potion")["name_key"]))
	assert_true(by_label.has(hp_name))
	var hp_entry := by_label[hp_name] as Dictionary
	assert_eq(str(hp_entry["cost_text"]), "×3")
	assert_true(bool(hp_entry["enabled"]), "usable even though no one currently needs healing")

	main.sim.minions[0].hp = 10
	main._on_battle_item()
	by_label.clear()
	for entry: Variant in main._battle_list_entries:
		by_label[str((entry as Dictionary)["label"])] = entry
	assert_true(bool((by_label[hp_name] as Dictionary)["enabled"]), "still usable once someone is hurt too")


## §14-17: REWINDで所持数・アイテムによる回復もチェックポイントへ完全に
## 戻ること——sim層は既にtest_boss_fight.gdで直接検証済みだが、UI経由の
## _do_battle_rewind()を通しても同じ結果になることを確認する。
func test_rewind_restores_item_counts_and_healed_hp_through_the_ui() -> void:
	var main := await _start_cave_troll_fight()
	var target_id := 0
	var full_hp: int = main.sim.unit_max_hp(main.sim.minions[target_id])
	main.sim.minions[target_id].hp = 10

	main._battle_selected_unit = 1
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)
	assert_lt(int(main.sim.battle_item_counts["hp_potion"]), 3, "sanity: a potion was actually spent")

	main._do_battle_rewind()

	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), 3, "REWIND restores the fight-start count")
	assert_eq(main.sim.minions[target_id].hp, full_hp, "REWIND restores the fight-start HP, undoing the heal")


## §18/§19/§20 UI側sanity: どうぐ実装後も既存の通常攻撃・防御が
## クラッシュせず正常に動作すること。
func test_existing_attack_and_guard_still_work_after_item_use() -> void:
	var main := await _start_cave_troll_fight()
	main.sim.minions[0].hp = 10
	main._battle_selected_unit = 1
	main._enter_target_selection("item", "hp_potion", "ally")
	main._battle_selected_ally_target = 0
	main._on_target_confirm()
	_pump_battle_animation(main)

	var boss_hp_before: int = main.sim.boss_hp
	main._set_battle_action(0, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	assert_lt(main.sim.boss_hp, boss_hp_before, "attack still lands normally after an item turn")

	main._on_battle_defend()
	_pump_battle_animation(main)
	assert_true(main.sim.guarding_units.size() > 0, "guard still works normally after an item turn")


## バグ修正 (2026-08-26、実機報告「ポーションを1個も持っていない」):
## _on_fight_button()は既にアクティブな戦闘へ戻るだけの場合sim.start_
## boss_fight()自体を呼ばず_show_boss_panel()へ直接来る——この機能より
## 前に保存されたセーブ等でアイテムIDの登録漏れがあっても、戦闘画面を
## 開き直せば必ず補充されることを、実際のUI入口(_show_boss_panel())
## 経由で確認する。
func test_reopening_the_boss_panel_backfills_a_missing_item_count() -> void:
	var main := await _start_cave_troll_fight()
	main.sim.battle_item_counts.erase("sp_potion")  # simulate an old/incomplete save
	assert_false(main.sim.battle_item_counts.has("sp_potion"))

	main._show_boss_panel()

	assert_eq(int(main.sim.battle_item_counts["sp_potion"]), 3, "reopening the boss panel backfills it")


## バグ修正 (2026-08-26、実機報告「ポーションもってても選択して使う
## ことができない」)。行自体はGodotのButton.disabled(=クリック自体を
## 無視する)にしてはならない——以前の実装は「対象なし」を行のdisabledで
## 表現していたため、所持数はあるのに「一覧の行を選ぶことすらできない」
## 状態になっていた。仕様変更 (2026-08-26) で「対象なし」自体が今は
## 起こらなくなったが(満タン相手も常に有効な対象)、"disabledな行は
## クリックできない"という回帰は今後も起こり得るため、regression guard
## として維持する。
func test_item_row_stays_selectable_and_clicking_it_selects_it() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1

	main._on_battle_item()

	var rows: VBoxContainer = main._battle_list_panel.find_child("rows", true, false)
	assert_eq(rows.get_child_count(), 2, "hp_potion + sp_potion rows")
	for child in rows.get_children():
		assert_false((child as Button).disabled,
			"a real Godot disabled Button never fires 'pressed' -- the row must stay clickable (%s)" % [
				(child as Button).text])
	# クリック(=pressedシグナル発火経由でのみ選択できることの直接確認)
	# しても選択状態が正しく反映され、説明文も読める。
	(rows.get_child(0) as Button).pressed.emit()
	assert_eq(main._battle_list_selected_index, 0)
	var effect_label: Label = main._battle_list_panel.find_child("effect", true, false)
	assert_false(effect_label.text.is_empty(), "the description is readable")


## 仕様変更 (2026-08-26): 「使えない」の唯一の残る条件は所持数0——
## 対象の有無ではもう決定ボタンは無効化されない。所持数0のアイテムだけ
## 決定が無効のままであることを確認する。
func test_confirming_an_out_of_stock_item_entry_does_nothing_and_does_not_crash() -> void:
	var main := await _start_cave_troll_fight()
	main.sim.battle_item_counts["hp_potion"] = 0
	main._battle_selected_unit = 1
	main._on_battle_item()
	(main._battle_list_panel.find_child("rows", true, false).get_child(0) as Button).pressed.emit()
	var confirm_button: Button = main._battle_list_panel.find_child("confirm", true, false)
	assert_true(confirm_button.disabled, "confirm stays disabled for an out-of-stock entry")

	main._on_battle_list_confirm()

	assert_ne(main._battle_phase, "targetSelection", "confirming a disabled entry is a no-op")
	assert_true(main._battle_list_panel.visible, "the list panel does not silently vanish either")


## 誰かが実際に負傷していれば、一覧の行を"クリック"(pressedシグナル)
## →決定、という実際の入力経路そのままで最後まで正常に使用できる。
func test_clicking_the_item_row_then_confirming_works_end_to_end_when_someone_is_hurt() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1
	main.sim.minions[0].hp = 10

	main._on_battle_item()
	(main._battle_list_panel.find_child("rows", true, false).get_child(0) as Button).pressed.emit()
	assert_eq(main._battle_list_selected_index, 0)
	var confirm_button: Button = main._battle_list_panel.find_child("confirm", true, false)
	assert_false(confirm_button.disabled, "hp_potion is now usable -- unit 0 needs healing")

	main._on_battle_list_confirm()

	assert_eq(main._battle_phase, "targetSelection")
	assert_eq(main._battle_target_kind, "ally")


## 仕様変更 (2026-08-26、ユーザー指示「アイテムを必要としていなくても
## 使えるようにして。特殊条件でポーションを使うをしなければいけない
## ボスを作る予定」)の核心のend-to-end確認: 全員フルHP/SPのままでも、
## 実際のクリック→決定→対象選択→決定という入力経路そのままで最後まで
## 使用できる——個数を消費し、行動が終了し、実際の回復量は0のまま。
func test_using_an_item_on_a_full_hp_target_still_works_end_to_end_and_consumes_a_count() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 1
	var target_id := 0
	var full_hp: int = main.sim.unit_max_hp(main.sim.minions[target_id])
	var counts_before: int = main.sim.battle_item_counts["hp_potion"]

	main._on_battle_item()
	(main._battle_list_panel.find_child("rows", true, false).get_child(0) as Button).pressed.emit()
	var confirm_button: Button = main._battle_list_panel.find_child("confirm", true, false)
	assert_false(confirm_button.disabled, "usable even though the whole party is at full HP")
	main._on_battle_list_confirm()
	assert_eq(main._battle_phase, "targetSelection")

	main._battle_selected_ally_target = target_id
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.minions[target_id].hp, full_hp, "already full -- stays full, no error")
	assert_eq(int(main.sim.battle_item_counts["hp_potion"]), counts_before - 1,
		"the use still consumed a count even though nothing needed healing")
