extends GutTest
## バトルメッセージ（新企画v1仕様書, 2026-08-22b→2026-09-02）。
## 2026-08-22b: 複数行動者ぶんを蓄積する"ログ"方式から「現在行動している
## 1キャラクター/敵の内容だけを表示する」方式へ。
## 2026-09-01: 一旦「1ターン内でも複数行を積み上げない、常に1行だけを
## 差し替える」方式へ全面転換したが、2026-09-02の実機報告「すべて1行
## 表示は採用しない」により再修正: **味方の行動(宣言＋結果)は従来どおり
## 2行、敵側(通常行動/予兆/Action Set/特殊反応/不発/状態変化)だけ1行**
## という非対称仕様に確定した(§1-§19)。カテゴリ("ally"/"enemy")は
## main._battle_message_categoryという1つの変数で明示的に管理され(§16)、
## _append_battle_message()がカテゴリの切り替わりを検知した瞬間だけ前の
## 内容を丸ごと消す(§6/§19)——同じカテゴリが連続する場合(例: 味方→次の
## 味方)は各呼び出し元の明示的な_clear_battle_message()が引き続き必要。
## 部位破壊→特殊反応のように「味方2行→敵1行」へ切り替えたい場合は
## _battle_message_deferred(§15/§18)による遅延差し替えを使う——両者が
## 同時に存在することは無い(§7)。


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


## 新戦闘進行システム v1 (2026-08-24)向けの共通テストヘルパー: 誰の番かは
## SPD順(sim.turn_order)で決まる——目的の状態へ到達するには実際にターン
## を進める必要がある。

## _battle_anim_step が -1 に戻るまでティックを回す——味方の番になった
## 瞬間は-1のまま止まる（プレイヤー入力待ち）が、敵の番が来た場合は
## _begin_current_turn()が自動でそのまま次の再生を始める（連鎖）ため、
## このループは「本当に入力待ちに戻るか、戦闘そのものが終わるまで」を
## 正しく待つ。
func _pump_battle_animation(main: Control) -> void:
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 20000, "battle animation never settled")


## 目的のユニットの番になるまで、間の味方の番を通常攻撃で消化する
## （敵の番はresolve自体が自動なので、明示的な処理は不要——_pump_battle_
## animationの連鎖に任せる）。目的のユニットの番になった時点で止まり、
## そのユニット自身の行動はまだ実行しない。
func _fast_forward_to_ally_turn(main: Control, unit_id: int) -> void:
	var guard := 0
	while main.sim.current_actor_token() != "ally:%d" % unit_id:
		var token: String = main.sim.current_actor_token()
		assert_true(token.begins_with("ally:"),
			"expected another ally's turn while fast-forwarding, got '%s'" % token)
		main._set_battle_action(
			int(token.substr(5)), "attack", "", "enemy", main.sim.boss_enemy_id, "")
		_pump_battle_animation(main)
		guard += 1
		assert_lt(guard, 10, "fast-forward looped too many times heading to unit %d's turn" % unit_id)


## sim.turn_order内で最初の"enemy:"の直後にある味方のunit_id。
func _ally_id_right_after_the_enemy(main: Control) -> int:
	var enemy_index := -1
	for i in main.sim.turn_order.size():
		if str(main.sim.turn_order[i]).begins_with("enemy:"):
			enemy_index = i
			break
	assert_ne(enemy_index, -1, "fixture always has an enemy in turn_order")
	var after_token := str(main.sim.turn_order[posmod(enemy_index + 1, main.sim.turn_order.size())])
	assert_true(after_token.begins_with("ally:"))
	return int(after_token.substr(5))


func _message_texts(main: Control) -> Array[String]:
	var texts: Array[String] = []
	for entry: Variant in main._battle_message_lines:
		texts.append(str((entry as Dictionary)["text"]))
	return texts


## 敵の反撃/割り込みが味方の行動の後に続いて前のメッセージを消してしまう
## ケースがあるため、多くのテストは"ラウンド全体の完走"ではなく"目的の
## 文章が現れた瞬間"で観測を止める必要がある。
func _tick_until(main: Control, predicate: Callable) -> void:
	var guard := 0
	while not predicate.call():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "condition never became true")


## §1-§3の核心: 味方の通常攻撃は「宣言」→(命中の瞬間)「結果」の2行が
## 同時に画面へ残る——旧「1行だけに差し替わる」設計とは正反対の主張。
func test_ally_normal_attack_shows_two_lines_declare_then_damage() -> void:
	var main := await _start_cave_troll_fight()
	var token: String = main.sim.current_actor_token()
	assert_true(token.begins_with("ally:"))
	var unit_id := int(token.substr(5))
	var actor_name: String = main._unit_display_name(main.sim.minions[unit_id])
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % actor_name

	main._set_battle_action(unit_id, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	# 宣言はresolve直後、行動アニメの開始と同時に同期的に積まれる。
	assert_eq(_message_texts(main), [expected_announce], "declare line appears alone, synchronously")
	assert_eq(main._battle_message_category, "ally")

	# ダメージ量は実際のATK/DEF計算に依存するため固定値で決め打ちせず、
	# フォーマット（"%sに%dダメージ！"）へ一致するかで判定する。
	var has_damage_line := func() -> bool:
		for text in _message_texts(main):
			if text.begins_with(boss_name + "に") and text.ends_with("ダメージ！"):
				return true
		return false
	_tick_until(main, has_damage_line)

	var texts := _message_texts(main)
	assert_eq(texts.size(), 2, "declare + damage coexist as the ally's 2-line block: %s" % [texts])
	assert_eq(texts[0], expected_announce, "declare stays as line 1")
	assert_true(texts[1].begins_with(boss_name + "に") and texts[1].ends_with("ダメージ！"),
		"damage as line 2: %s" % [texts])


## §4の核心: スキル使用も味方2行——宣言(技名込み)＋結果。
func test_ally_skill_use_shows_two_lines_declare_then_damage() -> void:
	var main := await _start_cave_troll_fight()
	# skill_rapid_slashはソティリス（unit 0、PROTAGONIST_SKILLS）専有——
	# 円が先に番を持つ実データのため、まずunit 0の番まで進める。
	_fast_forward_to_ally_turn(main, 0)
	var sotiris_name: String = main._unit_display_name(main.sim.minions[0])
	var skill_name: String = main.locale.text(
		str(main.skill_db.get_skill(main.RAPID_SLASH_SKILL_ID)["name_key"]))
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_SKILL") % [sotiris_name, skill_name]
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))

	main._set_battle_action(0, "skill", main.RAPID_SLASH_SKILL_ID, "enemy", main.sim.boss_enemy_id, "")
	assert_eq(_message_texts(main), [expected_announce])

	var has_damage_line := func() -> bool:
		for text in _message_texts(main):
			if text.begins_with(boss_name + "に") and text.ends_with("ダメージ！"):
				return true
		return false
	_tick_until(main, has_damage_line)

	var texts := _message_texts(main)
	assert_eq(texts.size(), 2, "%s" % [texts])
	assert_eq(texts[0], expected_announce)


## §2/§4の核心: 回復(ally-target skill)も味方2行——宣言＋「HPがX回復
## した！」。このコードベースではskill_healingはソティリス専有(unit 0)。
func test_ally_heal_shows_two_lines_declare_then_heal_result() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	main.sim.minions[1].hp = 1  # damaged so the actual heal amount is > 0 and gets appended
	var sotiris_name: String = main._unit_display_name(main.sim.minions[0])
	var skill_name: String = main.locale.text(
		str(main.skill_db.get_skill(main.HEALING_SKILL_ID)["name_key"]))
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_SKILL") % [sotiris_name, skill_name]

	main._set_battle_action(0, "skill", main.HEALING_SKILL_ID, "ally", "1", "")
	assert_eq(_message_texts(main), [expected_announce])

	var has_heal_line := func() -> bool:
		for text in _message_texts(main):
			if text.ends_with("回復した！"):
				return true
		return false
	_tick_until(main, has_heal_line)

	var texts := _message_texts(main)
	assert_eq(texts.size(), 2, "%s" % [texts])
	assert_eq(texts[0], expected_announce)


## §3/§18の核心: 部位破壊は基本の味方2行構成のまま(宣言＋「破壊した！」)
## ——その後、敵の特殊反応が発火した"その瞬間"、味方2行は跡形もなく消え、
## 敵の1行だけに完全に切り替わる（§6/§7「3行同時表示にはしない」）。
func test_part_destruction_keeps_ally_two_lines_then_special_reaction_replaces_them_with_one_enemy_line() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	main.sim.boss_part_hp["arm"] = 1  # 1発で確実に破壊できるようセットアップ
	var actor_name: String = main._unit_display_name(main.sim.minions[0])
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var arm_name: String = main._boss_part_display_name(main.enemy_db.get_enemy("cave_troll"), "arm")
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % actor_name
	var expected_destroyed: String = main.locale.text("UI_BATTLE_MSG_PART_DESTROYED") % [boss_name, arm_name]
	var expected_demo: String = main.locale.text("UI_BATTLE_MSG_DEMO_TROLL_ENRAGED")

	main._set_battle_action(0, "attack", "", "enemy", main.sim.boss_enemy_id, "arm")
	assert_true(main.sim.boss_parts_destroyed.has("arm"), "sim-side: the arm is actually destroyed")

	# ① 破壊ラインが実際に画面へ現れる時点で、宣言(1行目)もまだ残っている
	# ——味方2行構成のまま(§3)。特殊反応はまだ予約されただけで発火前。
	var has_destroyed_line := func() -> bool:
		return _message_texts(main).has(expected_destroyed)
	_tick_until(main, has_destroyed_line)
	var texts_at_destroyed := _message_texts(main)
	assert_eq(texts_at_destroyed, [expected_announce, expected_destroyed], "%s" % [texts_at_destroyed])
	assert_eq(main._battle_message_category, "ally")
	assert_false(main._battle_message_deferred.is_empty(), "a chained reaction is queued")

	# ② 遅延が満期になった瞬間、味方2行は跡形もなく消え、敵の特殊反応
	# 1行だけに完全に切り替わる。
	var has_demo_line := func() -> bool:
		return _message_texts(main).has(expected_demo)
	_tick_until(main, has_demo_line)
	var texts_at_demo := _message_texts(main)
	assert_eq(texts_at_demo, [expected_demo],
		"the ally 2 lines are gone, only the single enemy line remains: %s" % [texts_at_demo])
	assert_eq(main._battle_message_category, "enemy")
	assert_true(main._battle_message_deferred.is_empty(), "the queue is consumed after firing")
	# §9: kind="special" が実際に付与されていること（表示上の強調に使う）。
	assert_eq(str((main._battle_message_lines[0] as Dictionary)["kind"]), "special")


## §5/§6/§8/§17の核心: Boss Action Setの予兆は敵カテゴリ・1行——直前の
## 味方2人ぶんの行動内容が残っていても、予兆が発生した瞬間に跡形もなく
## 消える。フォントも味方より明確に大きい(§10)。
func test_boss_action_set_telegraph_is_a_single_enemy_line_and_clears_prior_ally_lines() -> void:
	var main := await _start_cave_troll_fight()
	# fast-forward中にcave_trollの通常SPD番(=Action Setの予兆)も自動的に
	# 解決される(_pump_battle_animationの連鎖)ため、ここへ到達した時点で
	# 予兆はもう発生済み——直前の味方2人ぶんの2行がclear()されたうえで
	# 予兆自身の1行に置き換わっている状態を直接観測する。
	var next_after_enemy := _ally_id_right_after_the_enemy(main)
	_fast_forward_to_ally_turn(main, next_after_enemy)

	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected_announce: String = main.locale.text("TROLL_ACTION_CLUB_WINDUP") % boss_name
	var texts := _message_texts(main)
	assert_eq(texts, [expected_announce], "exactly the telegraph, alone -- no leftover ally lines: %s" % [texts])
	assert_eq(main._battle_message_category, "enemy")
	# 予兆はダメージを一切与えない——誰の頭上にも「ダメージを受けた！」
	# 行が出ない。
	for text in texts:
		assert_false(text.ends_with("ダメージを受けた！"), "telegraph must never deal damage: %s" % text)

	var label: Label = main._battle_message_labels[0]
	assert_eq(label.get_theme_font_size("font_size"), main.BATTLE_MESSAGE_ENEMY_FONT_SIZE,
		"§10: Boss Action Setの予兆は敵側の大きなフォントを使う")


## §8/§19の核心: 敵1行表示の直後、次の味方が行動すると敵の1行は跡形も
## なく消え、その味方自身の新しい2行（宣言→結果）に切り替わる。
func test_next_ally_turn_after_an_enemy_line_starts_a_fresh_two_line_block() -> void:
	var main := await _start_cave_troll_fight()
	var next_after_enemy := _ally_id_right_after_the_enemy(main)
	_fast_forward_to_ally_turn(main, next_after_enemy)
	assert_eq(main._battle_message_category, "enemy", "fixture assumption: the telegraph is currently showing")

	var actor_name: String = main._unit_display_name(main.sim.minions[next_after_enemy])
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % actor_name

	main._set_battle_action(next_after_enemy, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	var texts_right_after_declare := _message_texts(main)
	assert_eq(texts_right_after_declare, [expected_announce],
		"the telegraph line is fully gone: %s" % [texts_right_after_declare])
	assert_eq(main._battle_message_category, "ally")

	var has_damage_line := func() -> bool:
		for text in _message_texts(main):
			if text.begins_with(boss_name + "に") and text.ends_with("ダメージ！"):
				return true
		return false
	_tick_until(main, has_damage_line)
	assert_eq(_message_texts(main).size(), 2)


## §7/§9の核心: どの瞬間を切り取っても、同時に存在するのは最大2行まで
## ——味方の宣言＋結果2行と敵の1行が同時に3行になることは決して無い。
## 味方の攻撃→(SPD次第で自動連鎖する)敵の反撃、という1ラウンド全体を
## 毎tick監視する。
func test_at_most_two_lines_ever_coexist_across_a_full_round() -> void:
	var main := await _start_cave_troll_fight()
	var token: String = main.sim.current_actor_token()
	assert_true(token.begins_with("ally:"))
	main._set_battle_action(int(token.substr(5)), "attack", "", "enemy", main.sim.boss_enemy_id, "")
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		assert_true(main._battle_message_lines.size() <= 2,
			"never more than 2 lines at once: %s" % [_message_texts(main)])
		guard += 1
		assert_lt(guard, 20000, "battle animation never settled")


func test_manual_rewind_clears_message_and_shows_only_the_divider() -> void:
	var main := await _start_cave_troll_fight()
	main._append_battle_message("leftover from before REWIND")
	main._append_battle_message("2nd leftover line")
	main._do_battle_rewind()

	assert_eq(main._battle_message_lines.size(), 1, "cleared down to just the divider")
	var entry: Dictionary = main._battle_message_lines[0]
	assert_eq(str(entry["text"]), main.locale.text("UI_BATTLE_MSG_REWIND_DIVIDER"))
	assert_eq(str(entry["kind"]), "special")
	assert_eq(main._battle_message_category, "enemy",
		"the divider is a standalone system line, treated as the enemy/1-line category")


## Boss Action Set (D2、2026-08-25) 導入後: cave_trollの実際にダメージを
## 与える攻撃(強攻撃)は、予兆(0ダメージ)の直後ではなく、味方が2行動を
## 消化した後に割り込むターンとして発生する(§10-17)。腕は誰も破壊して
## いないため強攻撃は不発せず確実に実ダメージを与える。
func _fast_forward_to_the_ally_turn_right_before_the_boss_action_set_interrupt(main: Control) -> int:
	var first_gap_ally := _ally_id_right_after_the_enemy(main)  # telegraph直後、割り込み前
	_fast_forward_to_ally_turn(main, first_gap_ally)
	main._set_battle_action(first_gap_ally, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	var token: String = main.sim.current_actor_token()
	assert_true(token.begins_with("ally:"), "expected the 2nd gap ally's turn, got '%s'" % token)
	return int(token.substr(5))


func test_auto_rewind_on_party_wipe_also_shows_the_divider() -> void:
	var main := await _start_cave_troll_fight()
	main._append_battle_message("leftover from before the wipe")
	# 新戦闘進行システムv1では「誰の番か」は実際にターンを進めないと
	# 変えられない（HPを直接いじって飛ばすことはできない）——敵の直前の
	# 味方の番まで進め、その行動者自身だけ生かして他全員を0にしてから
	# 行動させる。その行動自体は自分を傷つけないので、続く敵ターンへの
	# 連鎖の中で_boss_target()がその1人だけを確実に選び、全滅→自動
	# REWINDが起きる。
	var survivor_id := _fast_forward_to_the_ally_turn_right_before_the_boss_action_set_interrupt(main)
	for m in main.sim.minions:
		m.hp = 1 if m.id == survivor_id else 0
	main._set_battle_action(survivor_id, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)

	assert_true(main.sim.boss_active, "REWIND restarts the same fight, it does not end it")
	for m in main.sim.minions:
		assert_eq(m.hp, main.sim.unit_max_hp(m), "party fully healed — proof the wipe actually auto-rewound")
	var texts := _message_texts(main)
	assert_true(texts.has(main.locale.text("UI_BATTLE_MSG_REWIND_DIVIDER")), "%s" % [texts])
	assert_false(texts.has("leftover from before the wipe"), "the stale pre-wipe entry did not survive")
	assert_eq(main._battle_message_category, "enemy")


## §11「既存のboss_intelとは別システム」——バトルメッセージへ何を出しても
## boss_intel（永続データ）は一切変化しない。
func test_battle_message_never_writes_to_boss_intel() -> void:
	var main := await _start_cave_troll_fight()
	var intel_before: Dictionary = main.sim.boss_intel.duplicate(true)
	main._append_battle_message("some arbitrary future special-boss message", "special", "enemy")
	main._append_battle_message("another one")
	assert_eq(main.sim.boss_intel, intel_before, "boss_intel untouched by battle-message activity")


## §16の構造保証: カテゴリは_battle_message_categoryという1つの変数で
## 明示的に管理される——行数を数えて判定しない(§16「文章数だけ見て判断
## するような曖昧な実装は避ける」)。味方は2行までFIFOで積み上がり、敵は
## 常に最新の1行だけに置き換わる。カテゴリが切り替わった瞬間、前の内容は
## (呼び出し側が事前にclear()していなくても)_append_battle_message自身の
## 判定で丸ごと消える。
func test_append_caps_per_category_and_auto_clears_on_category_switch() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.BATTLE_MESSAGE_ALLY_MAX_LINES, 2)
	assert_eq(main.BATTLE_MESSAGE_ENEMY_MAX_LINES, 1)
	assert_eq(main._battle_message_labels.size(), main.BATTLE_MESSAGE_LABEL_COUNT,
		"exactly enough Label nodes for the taller (ally, 2-line) category, built once")

	main._clear_battle_message()
	main._append_battle_message("ally line 1")
	main._append_battle_message("ally line 2")
	assert_eq(_message_texts(main), ["ally line 1", "ally line 2"])
	main._append_battle_message("ally line 3")
	assert_eq(_message_texts(main), ["ally line 2", "ally line 3"],
		"a 3rd ally append evicts the oldest, capped at 2")
	assert_eq(main._battle_message_category, "ally")

	# 敵カテゴリへ切り替わった瞬間、上の味方2行は自動的に一掃される
	# （呼び出し側は事前にclear()していない）。
	main._append_battle_message("enemy line 1", "normal", "enemy")
	assert_eq(_message_texts(main), ["enemy line 1"], "switching category auto-clears the previous content")
	assert_eq(main._battle_message_category, "enemy")
	main._append_battle_message("enemy line 2", "normal", "enemy")
	assert_eq(_message_texts(main), ["enemy line 2"], "enemy category always caps at 1 (replace)")

	# 味方へ戻ると、同じくカテゴリ切り替えとして自動的に一掃される。
	main._append_battle_message("ally again")
	assert_eq(_message_texts(main), ["ally again"])
	assert_eq(main._battle_message_category, "ally")


func test_clear_battle_message_empties_lines_and_hides_all_labels() -> void:
	var main := await _start_cave_troll_fight()
	main._append_battle_message("something")
	main._append_battle_message("something else")
	main._clear_battle_message()

	assert_true(main._battle_message_lines.is_empty())
	assert_eq(main._battle_message_category, "")
	for label in main._battle_message_labels:
		assert_false(label.visible)
		assert_eq(label.text, "")


## §8/§9/§10/§11/§12/§13/§14/§19 の直接的な回帰ガード(2026-09-02、
## headlessジオメトリ確認——ピクセル単位の見た目はこの環境では検証
## できない、既存の制約): 味方2行は19pt・敵1行は26ptの明確に大きい
## フォント、バー高さは大幅に高くなっていない、円(Madoka)の足元との
## 安全マージンが確保されている、敵1行は(2個目のLabelがvisible=falseの
## 間も)パネル内で縦方向中央寄せになる、をそれぞれ実測する。
func test_ally_two_line_and_enemy_one_line_geometry() -> void:
	var main := await _start_cave_troll_fight()
	var madoka_feet_y: float = main.PARTY_FORMATION_BOSS[1].y * main.size.y

	main._append_battle_message("サユの攻撃！")
	main._append_battle_message("洞窟トロルの右腕に30ダメージ！")
	await get_tree().process_frame

	assert_true(main._battle_message_labels[0].visible)
	assert_true(main._battle_message_labels[1].visible)
	assert_eq(main._battle_message_labels[0].get_theme_font_size("font_size"), main.BATTLE_MESSAGE_ALLY_FONT_SIZE)
	assert_true(main.BATTLE_MESSAGE_ALLY_FONT_SIZE >= 19 and main.BATTLE_MESSAGE_ALLY_FONT_SIZE <= 21,
		"§11: 19〜21pt程度の範囲")

	var bar_rect_ally: Rect2 = main._battle_bar.get_global_rect()
	assert_lt(bar_rect_ally.size.y, 200.0, "§9: バー高さを大幅に高くしない")
	assert_true(bar_rect_ally.position.y > madoka_feet_y,
		"§19: character board stays clear of the bar (%f vs %f)" % [bar_rect_ally.position.y, madoka_feet_y])

	main._append_battle_message("洞窟トロルが棍棒を大きく振り上げた！！", "normal", "enemy")
	await get_tree().process_frame

	assert_true(main._battle_message_labels[0].visible)
	assert_false(main._battle_message_labels[1].visible, "敵1行では2個目のLabelは非表示")
	assert_eq(main._battle_message_labels[0].get_theme_font_size("font_size"), main.BATTLE_MESSAGE_ENEMY_FONT_SIZE)
	assert_true(main.BATTLE_MESSAGE_ENEMY_FONT_SIZE >= 24 and main.BATTLE_MESSAGE_ENEMY_FONT_SIZE <= 28,
		"§11: 24〜28pt程度の範囲")
	assert_gt(main.BATTLE_MESSAGE_ENEMY_FONT_SIZE, main.BATTLE_MESSAGE_ALLY_FONT_SIZE,
		"§10: 敵1行は味方2行より明確に大きい")

	# §13: 敵1行はバーの中で縦方向中央寄せ——ラベル矩形の上下の余白が
	# ほぼ均等になっていること(column.alignment=CENTERの直接検証)。
	var label_rect: Rect2 = main._battle_message_labels[0].get_global_rect()
	var panel_rect: Rect2 = main._battle_message_panel.get_global_rect()
	var top_gap := label_rect.position.y - panel_rect.position.y
	var bottom_gap := panel_rect.end.y - label_rect.end.y
	assert_almost_eq(top_gap, bottom_gap, 1.5,
		"the single enemy line sits vertically centered within the message panel")

	var bar_rect_enemy: Rect2 = main._battle_bar.get_global_rect()
	assert_eq(bar_rect_enemy.size.y, bar_rect_ally.size.y,
		"§12: 味方2行/敵1行どちらでもバー高さは(床のおかげで)同一")
	assert_true(bar_rect_enemy.position.y > madoka_feet_y)
