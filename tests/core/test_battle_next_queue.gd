extends GutTest
## Phase 5「NEXT5行動表示」の回帰テスト(2026-08-25)。current_actor_id→NEXT1→
## NEXT2→NEXT3→NEXT4→NEXT5が、実際の戦闘進行(sim.turn_order/turn_cursor)と
## 完全に一致すること、更新タイミングが行動完了後の一度だけであること、
## 下部パネル強調・頭上マーカーと同じcurrent_actor_idを共有すること、を
## UI層(main.tscn実インスタンス)で検証する。sim層のpeek_next_actors()自体の
## 純粋性・タイブレーク一致はtest_boss_fight.gdで別途検証済み。


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


func _visible_next_texts(main: Control) -> Array:
	var texts: Array = []
	for label: Label in main._battle_next_labels:
		if label.visible:
			texts.append(label.text)
	return texts


func _expected_next_texts(main: Control) -> Array:
	var upcoming: Array[String] = main.sim.peek_next_actors(main.BATTLE_NEXT_MAX_ENTRIES)
	var texts: Array = []
	for i in upcoming.size():
		texts.append("%d %s" % [i + 1, main._next_actor_display_name(upcoming[i])])
	return texts


## §16/§27-1/§27-2/§27-3: 戦闘開始直後、current_actor(円)を含まない・最大5件
## の・実際の行動順そのものがNEXTへ即座に反映されていること(§24)。
func test_next5_is_populated_at_fight_start_and_excludes_the_current_actor() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1", "fixture assumption: Madoka acts first")

	var texts := _visible_next_texts(main)

	assert_eq(texts, _expected_next_texts(main))
	assert_lte(texts.size(), 5)
	for text: String in texts:
		assert_false(text.contains("円"), "current actor Madoka must not appear in her own NEXT list")


## §27-2: 最大5件を厳格に超えないこと。
func test_next5_never_shows_more_than_five_rows() -> void:
	var main := await _start_cave_troll_fight()

	var visible_count := 0
	for label: Label in main._battle_next_labels:
		if label.visible:
			visible_count += 1
	assert_eq(main._battle_next_labels.size(), 5, "exactly 5 label slots exist")
	assert_lte(visible_count, 5)


## §27-4/§16/§17: 1行動が完全に完了しcurrent_actorが進んだ直後にだけ、
## NEXTが1つずれること(演出の途中では更新されない)。
func test_next5_shifts_by_one_after_one_full_action_completes() -> void:
	var main := await _start_cave_troll_fight()
	var before := _visible_next_texts(main)

	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), "ally:0", "cursor moved to the real next actor")
	var after := _visible_next_texts(main)
	assert_ne(after, before)
	assert_eq(after, _expected_next_texts(main),
		"still derived live from sim.peek_next_actors(), not a UI-side copy that could drift")


## §27-5/§7: 味方と敵は同じNEXTリストに混在して表示される(別列を作らない)。
func test_next5_lists_allies_and_the_enemy_together() -> void:
	var main := await _start_cave_troll_fight()

	var texts := _visible_next_texts(main)

	var enemy_name: String = main._next_actor_display_name("enemy:%s" % main.sim.boss_enemy_id)
	var found_enemy := false
	var found_ally := false
	for text: String in texts:
		if text.ends_with(enemy_name):
			found_enemy = true
		else:
			found_ally = true
	assert_true(found_enemy, "the boss's own upcoming turn appears in the same list")
	assert_true(found_ally, "at least one ally also appears in the same list")


## §27-6/§20: SPD同点の扱いはsim本体の実際の順序と完全に一致する
## (UI側の別実装ではなく、常にpeek_next_actors()を経由する)。
func test_next5_text_matches_sim_display_names_in_exact_rank_order() -> void:
	var main := await _start_cave_troll_fight()

	var upcoming: Array[String] = main.sim.peek_next_actors(5)
	var texts := _visible_next_texts(main)

	assert_eq(texts.size(), upcoming.size())
	for i in upcoming.size():
		var expected_name: String = main._next_actor_display_name(upcoming[i])
		assert_true(texts[i].begins_with("%d " % (i + 1)),
			"row %d must show its own rank number, not just a bare name list (§15)" % (i + 1))
		assert_true(texts[i].ends_with(expected_name))


## §27-7/§23: 敵の番になった瞬間も、NEXTは(敵自身を除いた)正しい次の5件を
## 表示し続ける——味方専用UIにしない。
func test_next5_is_correct_the_moment_the_enemy_becomes_the_current_actor() -> void:
	var main := await _start_cave_troll_fight()
	# UIのアニメ再生を経由せず、simだけをカーソルの1つ手前まで直接進める
	# (このプロジェクトの敵ターンは_begin_current_turn()の中でresolve+
	# アニメキュー投入まで同期的に完了するため、UIのpumpループでは"敵が
	# current_actorである瞬間"そのものを観測できない——sim側を直接操作
	# してから、UI自身のターン遷移入口を1回だけ手動で呼ぶ)。
	while main.sim.current_actor_token().begins_with("ally:"):
		var token: String = main.sim.current_actor_token()
		main.sim.resolve_player_action(int(token.substr(5)), "attack")
	assert_true(main.sim.current_actor_token().begins_with("enemy:"),
		"fixture assumption: cave_troll's turn is reachable within the ally rotation")
	var expected := _expected_next_texts(main)

	main._begin_current_turn()

	assert_eq(_visible_next_texts(main), expected,
		"NEXT was refreshed synchronously before the enemy's own turn resolution began")


## §27-8/§25: REWIND後は戦闘開始時点のturn_orderへ正しく作り直され、
## REWIND前のNEXT表示が残らないこと。
func test_next5_resets_to_the_fight_start_order_after_manual_rewind() -> void:
	var main := await _start_cave_troll_fight()
	var fight_start_next := _visible_next_texts(main)

	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	main._set_battle_action(0, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	assert_ne(_visible_next_texts(main), fight_start_next,
		"sanity: NEXT actually moved on before we rewind")

	main._do_battle_rewind()

	assert_eq(main.sim.current_actor_token(), "ally:1")
	assert_eq(_visible_next_texts(main), fight_start_next,
		"REWIND restores the exact fight-start NEXT queue, with nothing left over from before it")


## §27-9/§27-10/最重要: 下部パネル強調(current_actor_unit_id)・頭上マーカー
## の元値・NEXT1の裏付けとなるsim.peek_next_actors()は、常に同一の
## current_actor_idから導かれ、互いに矛盾しないこと。
func test_current_actor_id_is_shared_by_the_panel_highlight_marker_and_next_queue() -> void:
	var main := await _start_cave_troll_fight()

	var current_id: int = main._current_actor_unit_id()

	assert_eq(current_id, main._battle_selected_unit,
		"the overhead marker's underlying id equals the bottom-panel highlight's id")
	assert_eq(current_id, 1, "fixture assumption: Madoka(id1) acts first")
	var upcoming: Array[String] = main.sim.peek_next_actors(5)
	assert_does_not_have(upcoming, "ally:%d" % current_id,
		"the shared current_actor_id itself is excluded from its own NEXT queue")


## §26: 生存者が少なく実際の行動が5件に満たない場合、架空の枠を埋めて
## 表示しない。
func test_next5_does_not_pad_with_fake_entries_when_fewer_than_five_remain() -> void:
	var main := await _start_cave_troll_fight()
	# 円以外の味方を全滅させ、生存combatantを円/ソティリス/ボスの3体だけに絞る。
	for m in main.sim.minions:
		if m.id != 0 and m.id != 1:
			m.hp = 0
	var upcoming: Array[String] = main.sim.peek_next_actors(5)
	assert_lt(upcoming.size(), 5, "fixture assumption: fewer than 5 real upcoming actors remain")

	main._refresh_next_panel()

	var visible_count := 0
	for label: Label in main._battle_next_labels:
		if label.visible:
			visible_count += 1
	assert_eq(visible_count, upcoming.size(),
		"exactly the real remaining count is shown, never padded up to 5")


## §9: NEXT欄は下部バーの一番左側(row内の最初の子)へ配置され、既存の
## カード列・コマンド列は無改修のまま右にずれるだけであること。
func test_next_column_is_the_leftmost_child_of_the_bottom_bar_row() -> void:
	var main := await _start_cave_troll_fight()

	var row: Node = main._battle_next_column.get_parent()
	assert_eq(row.get_child(0), main._battle_next_column,
		"NEXT is the first (leftmost) child of the bottom bar's row container")


## §5: 顔アイコン等の新規アセットは使わない——NEXT列の子はタイトル+5個の
## Labelのみで、TextureRect等の画像ノードを含まない。
func test_next_column_contains_only_text_labels_no_face_icons() -> void:
	var main := await _start_cave_troll_fight()

	for child in main._battle_next_column.get_children():
		assert_true(child is Label, "NEXT column must contain only Labels, no icon/texture nodes")
