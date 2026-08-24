extends GutTest
## Boss Action Set (新企画v1 D2、2026-08-25、§7-40) のUI層回帰テスト。
## gapのカウント方式・turn_orderへのspliceタイミング・KO/防御/どうぐの
## 扱い・REWINDでの完全リセット・決定性は、tests/core/test_boss_fight.gd
## で直接検証済み——ここでは「予兆が実際のUIパイプライン(_begin_current_
## turn→_resolve_current_enemy_turn→アニメ再生)を通してもクラッシュせず
## 正しいメッセージ・NEXT5を出す」「割り込みが実際のダメージ演出まで
## 通しで正常に動く」という、main.tscn実インスタンス化でしか検証できない
## 配線を対象にする。
##
## 実データ(cave_troll)のSPD順は次の固定シーケンス（headlessで実測・
## 確認済み）: 円(1)→ソティリス(0)→サユ(4)→司馬燿(3)→[cave_troll予兆]
## →ヴァルド(2)→円(1)→[割り込み=強攻撃]→ソティリス(0)→...


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
	assert_eq(main.sim.turn_order, ["ally:1", "ally:0", "ally:4", "ally:3", "enemy:cave_troll", "ally:2"],
		"fixture assumption: this exact real-data SPD order (headless-confirmed)")
	return main


func _pump_battle_animation(main: Control) -> void:
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 20000, "battle animation never settled")


func _act(main: Control, unit_id: int) -> void:
	main._set_battle_action(unit_id, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)


## 円→ソティリス→サユ→司馬燿の4人を消化し、cave_trollの予兆が自動的に
## 発生する直前まで進める。
func _fast_forward_to_the_telegraph(main: Control) -> void:
	_act(main, 1)
	_act(main, 0)
	_act(main, 4)
	_act(main, 3)  # cave_troll's own SPD turn auto-fires as the telegraph within this same pump


func _message_texts(main: Control) -> Array:
	var texts: Array = []
	for label: Label in main._battle_message_labels:
		if label.visible:
			texts.append(label.text)
	return texts


## 2026-09-01のバトルメッセージ全面刷新（tests/core/test_battle_message.gd
## 参照）以降、メッセージは常に1行だけで宣言→ダメージが即座に差し替わる
## ため、フルドレイン後の最終状態には宣言文がもう残っていない。宣言文
## そのものを検証したいテストは、フルに`_pump_battle_animation`する前に
## この関数で「宣言が表示された瞬間」まで細かくティックして捕まえる。
func _tick_until(main: Control, predicate: Callable) -> void:
	var guard := 0
	while not predicate.call():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 20000, "condition never became true")


## §14/§15/§35-36: cave_trollの本来のSPD順の番は、UIの通常フロー
## (_begin_current_turnの自動連鎖)を通しても即座に0ダメージの予兆へ
## なる——クラッシュせず、期待どおりの宣言文が表示される。
func test_telegraph_fires_automatically_via_the_real_ui_pipeline_and_deals_no_damage() -> void:
	var main := await _start_cave_troll_fight()
	var hp_before: Array = []
	for m in main.sim.minions:
		hp_before.append(m.hp)

	_fast_forward_to_the_telegraph(main)

	assert_eq(main.sim.current_actor_token(), "ally:2", "telegraph resolved, cursor moved on")
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected: String = main.locale.text("TROLL_ACTION_CLUB_WINDUP") % boss_name
	assert_true(_message_texts(main).has(expected), "%s" % [_message_texts(main)])
	for i in main.sim.minions.size():
		assert_eq(main.sim.minions[i].hp, hp_before[i], "telegraph deals no damage to anyone")


## §18-20/最重要: 予兆が解決した"その瞬間"から、実際のUIが読むNEXT5の
## 裏付け(sim.peek_next_actors)は既に割り込みの正しい未来位置を反映して
## いる——UI側が別に予測・再計算する経路は無い(同じ実データをそのまま
## 読むだけ)。
func test_next5_shows_the_scheduled_interrupt_immediately_after_the_telegraph() -> void:
	var main := await _start_cave_troll_fight()

	_fast_forward_to_the_telegraph(main)

	assert_eq(main.sim.peek_next_actors(5),
		["ally:1", "enemy:cave_troll", "ally:0", "ally:4", "ally:3"],
		"the interrupt is already visible in its correct future slot, 2 upcoming allies away")


## 新企画v1「Boss Action Setを実戦で成立させるフェーズ」§5: 上のテストが
## sim.peek_next_actors()の生データを直接確認したのに対し、ここでは実際に
## 画面へ描画されるNEXT5のLabelテキスト(main._battle_next_labels)自体が
## 「1 円」「2 洞窟トロル」のように正しい順位番号付きで洞窟トロルを含む
## ことを確認する——sim側のデータが正しくても、UI側の描画配線が別に
## 壊れている可能性を別途潰す。
func test_next5_ui_labels_render_the_scheduled_interrupt_right_after_the_telegraph() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_the_telegraph(main)

	var texts: Array = []
	for label: Label in main._battle_next_labels:
		if label.visible:
			texts.append(label.text)
	var boss_name: String = main._next_actor_display_name("enemy:%s" % main.sim.boss_enemy_id)
	assert_true(texts.size() >= 2, "at least two NEXT5 rows are visible right after the telegraph")
	assert_eq(texts[1], "2 %s" % boss_name,
		"the boss's spliced interrupt renders at its correct rank (2 allies away): %s" % [texts])


## §17: gap=2ぶんの味方行動(ヴァルド→円)が完了した直後、割り込みが本来の
## SPD順を追い越して次に発生し、実際にダメージ演出まで通しで動く
## （クラッシュしない）。
func test_interrupt_fires_after_exactly_two_gap_actions_and_deals_real_damage_via_the_ui() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_the_telegraph(main)
	var hp_before: Array = []
	for m in main.sim.minions:
		hp_before.append(m.hp)

	_act(main, 2)  # 1st gap ally (ヴァルド)
	assert_eq(main.sim.current_actor_token(), "ally:1", "still just the 1st gap action -- no interrupt yet")

	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var strong_name: String = main.locale.text("TROLL_ACTION_CLUB_SMASH_STRONG")
	var expected: String = main.locale.text("UI_BATTLE_MSG_BOSS_ATTACK_NAMED") % [boss_name, strong_name]
	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")  # 2nd gap ally (円)
	var has_interrupt_announce := func() -> bool:
		return _message_texts(main).has(expected)
	_tick_until(main, has_interrupt_announce)  # 単一行メッセージなので、宣言はダメージに即差し替わる前のこの瞬間しか捕まえられない
	_pump_battle_animation(main)  # 割り込み自体は自動連鎖の一部としてこの1回のpump内で最後まで解決済み -- 残りを最後まで流し切る

	assert_eq(main.sim.current_actor_token(), "ally:0", "returned to normal SPD order after the interrupt")
	assert_eq(main.sim.turn_order, ["ally:1", "ally:0", "ally:4", "ally:3", "enemy:cave_troll", "ally:2"],
		"turn_order fully restored to its original real-data shape")
	var someone_hurt := false
	for i in main.sim.minions.size():
		if main.sim.minions[i].hp < hp_before[i]:
			someone_hurt = true
	assert_true(someone_hurt, "the interrupt's strong attack actually landed on someone")


## §23-24: 予兆の時点では腕が健在でも、その後の2行動の間に破壊された
## 場合、割り込みは不発し0ダメージのままメッセージが表示される——実際の
## UIパイプラインを通しても正しく反映される。
func test_fizzle_message_appears_via_the_ui_when_the_arm_is_destroyed_during_the_gap() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_the_telegraph(main)
	assert_false(main.sim.boss_parts_destroyed.has("arm"))
	main.sim.boss_part_hp["arm"] = 0
	main.sim.boss_parts_destroyed.append("arm")  # destroyed during the 2-action gap window
	var hp_before: Array = []
	for m in main.sim.minions:
		hp_before.append(m.hp)

	_act(main, 2)  # 1st gap ally
	_act(main, 1)  # 2nd gap ally -- the (now-fizzled) interrupt auto-fires within this pump

	for i in main.sim.minions.size():
		assert_eq(main.sim.minions[i].hp, hp_before[i], "a fizzled interrupt deals no damage to anyone")
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected: String = main.locale.text("UI_BATTLE_MSG_BOSS_FIZZLE") % boss_name
	assert_true(_message_texts(main).has(expected), "%s" % [_message_texts(main)])
	assert_eq(main.sim.current_actor_token(), "ally:0", "the set still ends normally even on a fizzle")


## §26-27: 割り込み(または不発)の後、次にcave_trollのSPD順の番が巡って
## くると、また新しい予兆から始まる——実際のUI周回でも成立する。
func test_a_fresh_telegraph_begins_the_next_time_cave_trolls_normal_turn_comes_up() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_the_telegraph(main)
	_act(main, 2)
	_act(main, 1)  # interrupt resolves, back to normal order (ally:0 next)
	assert_eq(main.sim.current_actor_token(), "ally:0")

	# ソティリス→サユ→ヴァルドを消化し、cave_trollの次の本来のSPDターン
	# (今度は円ではなくこの並びで巡ってくる)まで進める。
	_act(main, 0)
	_act(main, 4)
	_act(main, 3)

	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected: String = main.locale.text("TROLL_ACTION_CLUB_WINDUP") % boss_name
	assert_true(_message_texts(main).has(expected), "a fresh telegraph, not a continuation: %s" % [_message_texts(main)])


## §19: REWIND後、進行中だったaction setの状態も含め、次の行動でNEXT5が
## 常に実データと矛盾しない（stale表示が残らない）。
func test_rewind_mid_action_set_leaves_no_stale_next5_entries() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_the_telegraph(main)
	_act(main, 2)  # 1 of 2 gap actions done -- the interrupt is spliced somewhere ahead

	main._do_battle_rewind()

	assert_eq(main.sim.current_actor_token(), "ally:1")
	assert_eq(main.sim.turn_order, ["ally:1", "ally:0", "ally:4", "ally:3", "enemy:cave_troll", "ally:2"],
		"no leftover splice artifact after REWIND")
	assert_eq(main.sim.peek_next_actors(5), ["ally:0", "ally:4", "ally:3", "enemy:cave_troll", "ally:2"],
		"NEXT5 matches the fresh, fully-reset fight-start order")


## 実機報告(2026-08-31)「右腕破壊済みなのに予兆が発生する」への対応
## (§8/§20 パターンA): 右腕が既に破壊済みの状態で洞窟トロルの通常SPD順
## の番が来ても、「洞窟トロルが棍棒を大きく振り上げた！！」は一切表示
## されず、NEXT5にも棍棒action_set由来の割り込み(予兆/強攻撃)は一切
## 挿入されない——sim.gdのユニットテスト(test_boss_fight.gd)で開始条件
## 自体は既に直接検証済みなので、ここでは実際のUIパイプライン(main.tscn
## 実インスタンス化)を通してもクラッシュせず正しく配線されていることを
## 確認する。
func test_no_telegraph_or_phantom_next5_entry_via_the_real_ui_when_the_arm_is_already_destroyed() -> void:
	var main := await _start_cave_troll_fight()
	main.sim.boss_part_hp["arm"] = 0
	main.sim.boss_parts_destroyed.append("arm")
	var base_order: Array[String] = main.sim.turn_order.duplicate()
	var hp_before: Array = []
	for m in main.sim.minions:
		hp_before.append(m.hp)

	_fast_forward_to_the_telegraph(main)  # despite the name, cave_troll's turn resolves within this pump

	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var telegraph_text: String = main.locale.text("TROLL_ACTION_CLUB_WINDUP") % boss_name
	assert_false(_message_texts(main).has(telegraph_text),
		"the club-windup telegraph never shows when the arm is already gone: %s" % [_message_texts(main)])
	assert_eq(main.sim.turn_order, base_order,
		"no interrupt was ever spliced -- NEXT5 has nothing phantom to show (§8)")
	var someone_hurt := false
	for i in main.sim.minions.size():
		if main.sim.minions[i].hp < hp_before[i]:
			someone_hurt = true
	assert_true(someone_hurt, "the boss still acted via an available alternate/flat action, not a no-op")
