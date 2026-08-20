extends GutTest
## バトルメッセージ（新企画v1仕様書, 2026-08-22b改訂: 実機報告「ログが
## 戦闘画面を覆う」を受けて、複数行動者ぶんを蓄積する"ログ"方式から
## 「現在行動している1キャラクター/敵の内容だけを表示する」方式へ設計
## 転換）。中心となる新しい振る舞い——**新しい行動者のターンが始まる
## 瞬間に前の行動者の文章を完全に消す**——を最優先で直接検証する。
## それ以外のメッセージ内容生成（宣言/ダメージ/部位破壊/回復/敵反撃/
## REWIND/boss_intel非汚染）は前回のtest_battle_log.gdから引き継ぎ、
## 定数・関数名の変更に合わせて更新した。


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


## _stop_battle_anim() (called from _finish_battle_round, which this loop
## runs to) wipes _battle_pending_round_result back to {} once playback
## ends — a deliberate cleanup, not a bug — so this returns a snapshot
## taken right after resolve, before that cleanup can race a caller that
## wants to inspect the round's raw result (e.g. which ally a boss
## counter actually targeted) after the animation finishes.
func _run_round_to_completion(main: Control) -> Dictionary:
	main._on_boss_resolve_round()
	var result: Dictionary = (main._battle_pending_round_result as Dictionary).duplicate(true)
	var guard := 0
	while main._battle_anim_step >= 0 and main._battle_anim_step < main._battle_anim_queue.size():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")
	return result


func _message_texts(main: Control) -> Array[String]:
	var texts: Array[String] = []
	for entry: Variant in main._battle_message_lines:
		texts.append(str((entry as Dictionary)["text"]))
	return texts


## 新しい「現在行動者だけ」設計そのもの（意図した挙動）により、敵の
## 反撃が必ず味方の行動の後に続いて前のメッセージを消してしまう——
## そのため多くのテストは"ラウンド全体の完走"ではなく"目的の文章が
## 現れた瞬間"で観測を止める必要がある。
func _tick_until(main: Control, predicate: Callable) -> void:
	var guard := 0
	while not predicate.call():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "condition never became true")


## §2/§19-1〜4の核心: 2人目の行動者のターンが始まった瞬間、1人目の
## 文章は画面から完全に消える——複数行動者ぶんの蓄積は絶対にしない。
func test_new_actor_turn_clears_the_previous_actors_messages() -> void:
	var main := await _start_cave_troll_fight()
	assert_gt(main._battle_order.size(), 1, "at least 2 living units to sequence through")
	var first_unit: int = main._battle_order[0]
	var second_unit: int = main._battle_order[1]
	main._battle_pending_actions.clear()
	main._battle_pending_actions[first_unit] = {
		"action": "attack", "target_type": "enemy", "target_id": main.sim.boss_enemy_id,
	}
	main._battle_pending_actions[second_unit] = {
		"action": "attack", "target_type": "enemy", "target_id": main.sim.boss_enemy_id,
	}
	main._on_boss_resolve_round()

	var first_name: String = main._unit_display_name(main.sim.minions[first_unit])
	var second_name: String = main._unit_display_name(main.sim.minions[second_unit])
	var first_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % first_name
	var second_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % second_name

	# 1人目の宣言が現れる瞬間まで進める。
	var guard := 0
	while not _message_texts(main).has(first_announce):
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "first actor's announce line never appeared")
	assert_false(_message_texts(main).has(second_announce), "2nd actor hasn't started yet")

	# 2人目の宣言が現れるまでさらに進める——この瞬間、1人目の文章は
	# 跡形もなく消えている必要がある。
	guard = 0
	while not _message_texts(main).has(second_announce):
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "second actor's announce line never appeared")
	var texts_after_second_starts := _message_texts(main)
	assert_false(texts_after_second_starts.has(first_announce),
		"1st actor's announce did not survive into the 2nd actor's turn: %s" % [texts_after_second_starts])
	for text in texts_after_second_starts:
		assert_false(text.begins_with(first_name), "no leftover %s-specific line: %s" % [first_name, [text]])
	# 敵の反撃は味方の行動の後に必ず続く（新しい「現在行動者だけ」設計
	# そのもの）ため、ここでラウンド全体を完走させると今度は2人目の
	# メッセージも敵のターン開始で消える——それも意図どおりの挙動なので
	# （このケース自体は下のtest_boss_counter_attack_*で別途検証済み）、
	# ここでは「2人目のターンが1人目を完全に上書きした」ことの確認まで
	# で止める。


func test_normal_attack_appends_announce_then_damage_line() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "attack", "target_type": "enemy", "target_id": main.sim.boss_enemy_id,
	}
	var sotiris_name: String = main._unit_display_name(main.sim.minions[0])
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))

	main._on_boss_resolve_round()
	# 宣言はresolve直後、行動アニメの開始と同時に同期的に積まれる
	# （_advance_battle_anim_step内）ので、tick無しでもう見えているはず。
	var texts_at_announce := _message_texts(main)
	var expected_announce: String = main.locale.text("UI_BATTLE_MSG_ATTACK") % sotiris_name
	assert_eq(texts_at_announce, [expected_announce])

	# ダメージ量は実際のATK/DEF計算に依存するため固定値で決め打ちせず、
	# フォーマット（"%sに%dダメージ！"）へ一致するかで判定する（sim側の
	# バランス計算には一切触れていないので、実数を検算する必要も無い）。
	# 敵の反撃が必ず後から続いてこの行を消してしまう前に、命中の瞬間で
	# 観測を止める——「ラウンド全体の完走」ではない。
	var has_damage_line := func() -> bool:
		for text in _message_texts(main):
			if text.begins_with(boss_name + "に") and text.ends_with("ダメージ！"):
				return true
		return false
	_tick_until(main, has_damage_line)

	var texts := _message_texts(main)
	# この時点ではまだソティリスのターン中——宣言→ダメージの2行だけが
	# その順番で残っている（宣言が先に積まれているので必ずindex 0）。
	assert_eq(texts.size(), 2)
	assert_eq(texts[0], expected_announce, "announce line comes before the damage line: %s" % [texts])


func test_skill_use_announce_line_includes_skill_name() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "skill", "skill_id": main.RAPID_SLASH_SKILL_ID,
		"target_type": "enemy", "target_id": main.sim.boss_enemy_id,
	}
	var sotiris_name: String = main._unit_display_name(main.sim.minions[0])
	var skill_name: String = main.locale.text(
		str(main.skill_db.get_skill(main.RAPID_SLASH_SKILL_ID)["name_key"]))
	var expected: String = main.locale.text("UI_BATTLE_MSG_SKILL") % [sotiris_name, skill_name]

	# 宣言はresolve直後、行動アニメの開始と同時に同期的に積まれる
	# （_advance_battle_anim_step内）——敵の反撃で消される前にtick無しで
	# 確認できる。
	main._on_boss_resolve_round()
	assert_eq(_message_texts(main), [expected])


func test_part_targeted_attack_appends_part_damage_line() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "attack", "target_type": "enemy",
		"target_id": main.sim.boss_enemy_id, "target_part": "arm",
	}
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var arm_name: String = main._boss_part_display_name(main.enemy_db.get_enemy("cave_troll"), "arm")

	main._on_boss_resolve_round()
	# 敵の反撃が必ず後から続いてこの行を消してしまう前に、命中の瞬間で
	# 観測を止める。
	var has_part_damage_line := func() -> bool:
		for text in _message_texts(main):
			if text.begins_with("%sの%sに" % [boss_name, arm_name]) and text.ends_with("ダメージ！"):
				return true
		return false
	_tick_until(main, has_part_damage_line)


## §12/§13の「洞窟トロルが怒りに震えている！！」動作確認も兼ねる: 部位
## 破壊ラインと、特殊メッセージ機構のデモ発火が両方とも同じ行動者の
## メッセージへ一緒に積まれることを確認する。
func test_part_destruction_appends_destroyed_and_demo_special_lines() -> void:
	var main := await _start_cave_troll_fight()
	main.sim.boss_part_hp["arm"] = 1  # 1発で確実に破壊できるようセットアップ
	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "attack", "target_type": "enemy",
		"target_id": main.sim.boss_enemy_id, "target_part": "arm",
	}
	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var arm_name: String = main._boss_part_display_name(main.enemy_db.get_enemy("cave_troll"), "arm")
	var expected_destroyed: String = main.locale.text("UI_BATTLE_MSG_PART_DESTROYED") % [boss_name, arm_name]
	var expected_demo: String = main.locale.text("UI_BATTLE_MSG_DEMO_TROLL_ENRAGED")

	main._on_boss_resolve_round()
	assert_true(main.sim.boss_parts_destroyed.has("arm"), "sim-side: the arm is actually destroyed")
	# 敵の反撃が必ず後から続いてこれらの行を消してしまう前に、デモ特殊
	# ライン（部位破壊ラインと同一のhitイベントで、それより後に積まれる）
	# が現れた瞬間で観測を止める。
	var has_demo_line := func() -> bool:
		return _message_texts(main).has(expected_demo)
	_tick_until(main, has_demo_line)

	var texts := _message_texts(main)
	assert_true(texts.has(expected_destroyed), "expected '%s' in %s" % [expected_destroyed, texts])
	assert_true(texts.has(expected_demo), "expected demo special line '%s' in %s" % [expected_demo, texts])
	# §9: kind="special" が実際に付与されていること（表示上の強調に使う）。
	var demo_kind := ""
	for entry: Variant in main._battle_message_lines:
		if str((entry as Dictionary)["text"]) == expected_demo:
			demo_kind = str((entry as Dictionary)["kind"])
	assert_eq(demo_kind, "special")
	# §12: 部位のHPを1に細工したので1発で即破壊——「ダメージ」行を経由
	# せず「宣言」→「部位破壊」→「デモ特殊」の3行だけが積まれ、3行の
	# 上限（BATTLE_MESSAGE_MAX_LINES）にちょうど収まる（何も押し出され
	# ない）。
	assert_eq(texts.size(), main.BATTLE_MESSAGE_MAX_LINES)
	assert_eq(texts[0], main.locale.text("UI_BATTLE_MSG_ATTACK") % main._unit_display_name(main.sim.minions[0]))


func test_boss_counter_attack_appends_announce_and_ally_damage_lines() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_pending_actions.clear()  # 誰も行動しなくても敵の反撃は発生する
	var result := _run_round_to_completion(main)

	var boss_name: String = main.locale.text(str(main.enemy_db.get_enemy("cave_troll")["name_key"]))
	var club_smash_name: String = main.locale.text("TROLL_ACTION_CLUB_SMASH")
	var expected_announce: String = (
		main.locale.text("UI_BATTLE_MSG_BOSS_ATTACK_NAMED") % [boss_name, club_smash_name])
	var texts := _message_texts(main)
	# arm がまだ健在な間は club_smash が確実に選ばれる（requires_part_
	# intact:"arm" 以外に候補が無い、data/enemies/cave_troll.json参照）。
	assert_true(texts.has(expected_announce), "expected '%s' in %s" % [expected_announce, texts])
	# _battle_ally_hit_unit（UIの再生専用のtransient state）や、_finish_
	# battle_round後にクリアされ済みのmain._battle_pending_round_result
	# ではなく、_run_round_to_completionが解決直後にスナップショットした
	# 値（sim.gdの生データ、安定した値）から「誰が狙われたか」を読む。
	var boss_counter: Dictionary = result.get("boss_counter", {})
	var target_unit_id := int(boss_counter.get("target_unit_id", -1))
	assert_ne(target_unit_id, -1, "sim actually resolved a counter target")
	var target_name: String = main._unit_display_name(main.sim.minions[target_unit_id])
	var expected_damage: String = main.locale.text("UI_BATTLE_MSG_DAMAGE_ALLY") % [
		target_name, int(boss_counter.get("amount", -1)),
	]
	assert_true(texts.has(expected_damage), "expected '%s' in %s" % [expected_damage, texts])
	# 誰も行動していない round なので、残っているのは敵ターンの2行だけ。
	assert_eq(texts.size(), 2)


func test_manual_rewind_clears_message_and_shows_only_the_divider() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_message_lines.append({"text": "leftover from before REWIND", "kind": "normal"})
	main._do_battle_rewind()

	assert_eq(main._battle_message_lines.size(), 1, "cleared down to just the divider")
	var entry: Dictionary = main._battle_message_lines[0]
	assert_eq(str(entry["text"]), main.locale.text("UI_BATTLE_MSG_REWIND_DIVIDER"))
	assert_eq(str(entry["kind"]), "special")


func test_auto_rewind_on_party_wipe_also_shows_the_divider() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_message_lines.append({"text": "leftover from before the wipe", "kind": "normal"})
	# 全滅を確実に起こす: 敵の反撃は生存者の中から1人だけを狙う——全員を
	# HP1にしても他4人が生き残ったままなので全滅にはならない。最後の
	# 1人だけを残し(HP1、反撃で確実に倒れる)、他は先に0にしておくこと
	# で、_boss_target()の対象がその1人しかあり得ない状態にする。
	for m in main.sim.minions:
		m.hp = 0
	main.sim.minions[0].hp = 1
	main._battle_pending_actions.clear()
	var result := _run_round_to_completion(main)

	assert_true(result.get("rewound", false), "sim actually auto-rewound")
	var texts := _message_texts(main)
	assert_true(texts.has(main.locale.text("UI_BATTLE_MSG_REWIND_DIVIDER")), "%s" % [texts])
	assert_false(texts.has("leftover from before the wipe"), "the stale pre-wipe entry did not survive")


## §11「既存のboss_intelとは別システム」——バトルメッセージへ何を出しても
## boss_intel（永続データ）は一切変化しない。
func test_battle_message_never_writes_to_boss_intel() -> void:
	var main := await _start_cave_troll_fight()
	var intel_before: Dictionary = main.sim.boss_intel.duplicate(true)
	main._append_battle_message("some arbitrary future special-boss message", "special")
	main._append_battle_message("another one", "normal")
	assert_eq(main.sim.boss_intel, intel_before, "boss_intel untouched by battle-message activity")


## §3「1キャラクターの行動については2〜3行程度使って構わない」——同一
## ターン内でBATTLE_MESSAGE_MAX_LINESを超えると古いものから消える(FIFO)。
func test_battle_message_caps_lines_within_a_turn_and_drops_the_oldest_first() -> void:
	var main := await _start_cave_troll_fight()
	main._clear_battle_message()
	for i in range(main.BATTLE_MESSAGE_MAX_LINES + 2):
		main._append_battle_message("line %d" % i)
	assert_eq(main._battle_message_lines.size(), main.BATTLE_MESSAGE_MAX_LINES)
	var texts := _message_texts(main)
	assert_eq(texts[0], "line 2", "the oldest 2 lines were pushed out")
	assert_eq(texts[texts.size() - 1], "line %d" % (main.BATTLE_MESSAGE_MAX_LINES + 1), "newest stays at the end")
	# ラベル側もエントリ数と一致していること（表示に反映されている確認）。
	var visible_labels := 0
	for label in main._battle_message_labels:
		if label.visible:
			visible_labels += 1
	assert_eq(visible_labels, main.BATTLE_MESSAGE_MAX_LINES)


func test_clear_battle_message_empties_lines_and_hides_all_labels() -> void:
	var main := await _start_cave_troll_fight()
	main._append_battle_message("something")
	main._append_battle_message("something else")
	main._clear_battle_message()

	assert_true(main._battle_message_lines.is_empty())
	for label in main._battle_message_labels:
		assert_false(label.visible)
		assert_eq(label.text, "")
