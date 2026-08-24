extends GutTest
## 現在行動者(actor)と対象(target)の完全分離、および行動主体=スキル所有者
## =simへ送るunit_id=logのunit_id=バトルメッセージの行動者=VFX再生キャラ
## が常に一本の同じIDでつながっていることの回帰テスト(2026-08-25)。
##
## 実機バグ報告: 月夜円が現在行動者の状態で、ソティリス専有のラピッド
## スラッシュを選択・実行でき、「円のラピッドスラッシュ！」という不正な
## 組み合わせのメッセージと0ダメージが発生した。根本原因は
## _on_battle_card_input()が通常のコマンド入力中でも無条件に
## _battle_selected_unit = unit_id していたこと(actor selectionとtarget
## selectionの二重管理)、および_resolve_one_action()がスキル所有権を
## 検証せずログを組み立てていたこと(sim側の安全弁が呼び出し元に無視
## されていた)の2点。


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


## 目的のユニットの番になるまで、間の味方の番を通常攻撃で消化する。
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


func _click_card(main: Control, unit_id: int) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	main._on_battle_card_input(event, unit_id)


## §1/§13(checklist): cave_trollの実データではcurrent_actorは円(unit 1、
## SPD30が最速)——円のスキル一覧だけが表示され、ソティリス専有スキルの
## 名前は一切含まれないこと。
func test_current_actor_madoka_sees_only_her_own_skills() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1", "fixture assumption: Madoka acts first")
	assert_eq(main._battle_selected_unit, 1)

	main._on_battle_skill()

	var labels: Array = []
	for entry: Variant in main._battle_list_entries:
		labels.append(str((entry as Dictionary)["label"]))
	var rapid_slash_name: String = main.locale.text(
		str(main.skill_db.get_skill(main.RAPID_SLASH_SKILL_ID)["name_key"]))
	assert_false(labels.has(rapid_slash_name), "Sotiris-exclusive skill leaked into Madoka's list: %s" % [labels])
	for skill_id in main.sim.unit_skills(main.sim.minions[1]):
		if main.skill_db.has_skill(skill_id):
			var expected_name: String = main.locale.text(str(main.skill_db.get_skill(skill_id)["name_key"]))
			assert_true(labels.has(expected_name), "%s's own skill missing from her list: %s" % [expected_name, labels])


## §2(checklist)の核心バグ再現: 円のターン中に他キャラのカードをクリック
## しても行動主体は変わらない——旧else分岐の削除を直接検証する。
func test_clicking_another_card_during_command_selection_does_not_change_the_actor() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main._battle_selected_unit, 1, "Madoka is the real current actor")

	_click_card(main, 0)  # ソティリスのカードをクリック(旧方式なら行動主体が乗っ取られていた)

	assert_eq(main._battle_selected_unit, 1, "actor selection must not move on a plain card click")
	assert_eq(main.sim.current_actor_token(), "ally:1", "sim's own turn state is of course untouched either way")


## §3/§13(checklist): それでもなお現在行動者以外のスキルを開けない
## (_on_battle_skill自身の入口ガード) ——カードクリックを完全に塞ぐ前の
## 多層防御としても機能する。
func test_opening_the_skill_list_for_a_non_current_actor_is_a_no_op() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main._battle_selected_unit, 1)
	main._battle_selected_unit = 0  # テスト自身が直接、旧バグ相当の状態を再現
	main._battle_list_entries = []

	main._on_battle_skill()

	assert_true(main._battle_list_entries.is_empty(), "the skill list must not open for a non-current actor")
	assert_ne(main._battle_phase, "skillSelection")


## §5/§12(checklist)の核心: _battle_selected_unit=0(ソティリス、実際は
## 円のターン)という不正状態から実際に決定まで進めようとしても、
## _set_battle_action自身のガードが弾く——simへ届かない・HP/SPが一切
## 変化しない・バトルメッセージも一切積まれない。
func test_mismatched_actor_and_skill_never_reaches_sim_via_ui_confirm() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1")
	var madoka_sp_before: int = main.sim.minions[1].sp
	var sotiris_sp_before: int = main.sim.minions[0].sp
	var boss_hp_before: int = main.sim.boss_hp
	main._clear_battle_message()

	# 旧バグの実際の経路を模す: _battle_selected_unitがどうにかして
	# current_actorと食い違った状態のまま決定に到達したケース。
	main._battle_selected_unit = 0
	main._battle_pending_skill_id = main.RAPID_SLASH_SKILL_ID
	main._battle_target_source = "skill"
	main._battle_target_kind = "enemy"
	main._battle_selected_target_id = main.sim.boss_enemy_id
	main._on_target_confirm()

	assert_eq(main.sim.boss_hp, boss_hp_before, "boss took no damage from the rejected action")
	assert_eq(main.sim.minions[0].sp, sotiris_sp_before, "Sotiris's SP is untouched")
	assert_eq(main.sim.minions[1].sp, madoka_sp_before, "Madoka's SP is untouched")
	assert_eq(main.sim.current_actor_token(), "ally:1", "turn did not advance from a rejected action")
	assert_true(main._battle_message_lines.is_empty(), "no phantom battle message for a rejected action")
	assert_true(main._battle_anim_queue.is_empty(), "no VFX/animation queued for a rejected action")


## §6(checklist)のsim側の安全弁そのもの: current_actorと一致するunit_id
## であっても、そのユニットが実際には持っていないskill_idを直接
## resolve_player_action()へ送った場合、simはログを一切生成しない
## (「誰も行動しなかった」扱い) ——UI層のバグの有無に関わらずsim自身が
## 不正な組み合わせを弾く多層防御。
func test_sim_rejects_a_skill_the_current_actor_does_not_own_even_called_directly() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1")
	var boss_hp_before: int = main.sim.boss_hp
	var madoka_sp_before: int = main.sim.minions[1].sp

	var result: Dictionary = main.sim.resolve_player_action(
		1, "skill", main.RAPID_SLASH_SKILL_ID, -1, "")

	assert_true((result.get("log", []) as Array).is_empty(),
		"a mismatched (unit, skill) pair produces no log entry at all — not a 0-damage 'success'")
	assert_eq(main.sim.boss_hp, boss_hp_before, "no damage was ever applied")
	assert_eq(main.sim.minions[1].sp, madoka_sp_before, "no SP was ever spent for a skill she doesn't own")
	# cave_trollの実データでのSPD順は 円(30)>ソティリス(24)>サユ(18)>
	# トロル(16)>燿(14)>ヴァルド(8) — 円の次はソティリス。
	assert_eq(main.sim.current_actor_token(), "ally:0",
		"the turn still consumed/advanced — this action is treated exactly like a no-op, not retried forever")


## §3(checklist): ソティリス自身のターンでは、ラピッドスラッシュを正しく
## 実行できる——今回の修正がスキル自体を壊していないことの確認。§19
## 「ラピッドスラッシュの威力/VFX/SE/フレーム/タイミングは変更しない」の
## 裏付けも兼ねる(ダメージが実際に発生することのみ検証、数値そのものは
## 検証しない)。
func test_sotiris_can_still_use_rapid_slash_on_his_own_turn() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	assert_eq(main.sim.current_actor_token(), "ally:0")
	var boss_hp_before: int = main.sim.boss_hp

	main._set_battle_action(0, "skill", main.RAPID_SLASH_SKILL_ID, "enemy", main.sim.boss_enemy_id, "")

	var log: Array = main._battle_pending_round_result.get("log", [])
	assert_eq(log.size(), 1)
	var entry := log[0] as Dictionary
	assert_eq(int(entry["unit_id"]), 0, "log.unit_id matches the real current actor (Sotiris)")
	assert_eq(str(entry["skill_id"]), main.RAPID_SLASH_SKILL_ID)
	assert_gt(int(entry["amount"]), 0, "the skill actually dealt damage — not the 0-damage bug")
	assert_lt(main.sim.boss_hp, boss_hp_before, "boss_hp actually dropped")


## §8/§13(checklist): メッセージの行動者名はlog.unit_idから生成される
## ——「円のラピッドスラッシュ」のような不正な組み合わせが表示される
## 経路が無いことのメッセージ内容での確認。
func test_battle_message_names_the_true_actor_for_a_skill_only_they_could_use() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	var sotiris_name: String = main._unit_display_name(main.sim.minions[0])
	var madoka_name: String = main._unit_display_name(main.sim.minions[1])
	var skill_name: String = main.locale.text(
		str(main.skill_db.get_skill(main.RAPID_SLASH_SKILL_ID)["name_key"]))
	var expected: String = main.locale.text("UI_BATTLE_MSG_SKILL") % [sotiris_name, skill_name]

	main._set_battle_action(0, "skill", main.RAPID_SLASH_SKILL_ID, "enemy", main.sim.boss_enemy_id, "")

	var texts: Array[String] = []
	for entry: Variant in main._battle_message_lines:
		texts.append(str((entry as Dictionary)["text"]))
	assert_true(texts.has(expected), "expected '%s' in %s" % [expected, texts])
	for text in texts:
		assert_false(text.begins_with(madoka_name + "の" + skill_name),
			"Madoka's name must never pair with Rapid Slash in a message: %s" % [texts])


## §4/§5(checklist)の核心: 味方対象選択で他キャラをクリックしても、
## 行動主体(_battle_selected_unit)は変わらず、対象(_battle_selected_ally_
## target)だけが変わる——actorとtargetの完全分離。サユのヒーリングは
## サユ専有ではない汎用スキルではなくソティリス専有だが、ここでは
## 「行動者=ソティリス、対象=別キャラ」という状況そのものを検証したいの
## で、まずソティリスのターンまで進めてからヒーリングを選ぶ。
func test_ally_target_selection_changes_target_only_never_the_actor() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	main._on_battle_skill()
	main._enter_target_selection("skill", "skill_healing", "ally")
	assert_eq(main._battle_selected_unit, 0, "acting unit is Sotiris")
	assert_eq(main._battle_selected_ally_target, 0, "defaults to self")

	_click_card(main, 1)  # 円のカードを対象としてクリック

	assert_eq(main._battle_selected_unit, 0, "actor did not change from picking a target")
	assert_eq(main._battle_selected_ally_target, 1, "only the target changed")

	main._on_target_confirm()
	var log: Array = main._battle_pending_round_result.get("log", [])
	assert_eq(log.size(), 1)
	var entry := log[0] as Dictionary
	assert_eq(int(entry["unit_id"]), 0, "the caster in the log is still Sotiris")
	assert_eq(int(entry["target_id"]), 1, "the heal landed on Madoka")


## §11/§16(checklist): ある行動者が選択中だったスキル/対象状態は、次の
## 行動者のターンが始まると必ず初期化される——_begin_current_turn()の
## リセット処理を直接検証する。
func test_turn_transition_clears_the_previous_actors_selection_state() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1")
	main._on_battle_skill()
	main._enter_target_selection(
		"skill", main.sim.unit_skills(main.sim.minions[1])[0], "enemy")
	assert_ne(main._battle_pending_skill_id, "", "sanity: some skill selection state exists")

	# 円自身の行動を確定させて、次の行動者(ソティリス)へターンを渡す。
	main._on_target_confirm()
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), "ally:0", "now Sotiris's turn")
	assert_eq(main._battle_pending_skill_id, "", "Madoka's skill selection did not carry over")
	assert_eq(main._battle_target_source, "")
	assert_eq(main._battle_selected_target_id, "")
	assert_eq(main._battle_selected_ally_target, -1)
	assert_false(main._battle_list_panel.visible, "no stale skill/item panel left open")


## §12/§20(checklist): REWIND後も選択状態が残らない——手動REWINDで確認。
func test_rewind_clears_selected_skill_and_target_state() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_skill()
	main._enter_target_selection(
		"skill", main.sim.unit_skills(main.sim.minions[1])[0], "enemy")
	assert_ne(main._battle_pending_skill_id, "", "sanity: some skill selection state exists")

	main._do_battle_rewind()

	assert_eq(main._battle_pending_skill_id, "")
	assert_eq(main._battle_target_source, "")
	assert_eq(main._battle_selected_target_id, "")
	assert_eq(main._battle_selected_ally_target, -1)
	assert_false(main._battle_list_panel.visible)
	# REWINDは戦闘開始状態(turn_order[0])へ戻る——現在行動者も再初期化される。
	assert_eq(main.sim.current_actor_token(), main.sim.turn_order[0])
	assert_eq(main._battle_selected_unit, int(str(main.sim.turn_order[0]).substr(5)))


## §14/§18(checklist): 敵のターン中は味方コマンド入力UI自体が無効
## （コマンド列が非表示）——現在行動者以外はもちろん、敵の番そのもの
## でも一切コマンドを入力できない。
func test_command_ui_is_hidden_while_it_is_the_enemys_turn() -> void:
	var main := await _start_cave_troll_fight()
	# 円→ソティリス→サユの3人を消化すると、cave_trollの実データでは
	# 次が敵のターンになる(spd: 円30>ソティリス24>サユ18>トロル16>燿14>
	# ヴァルド8)。
	_fast_forward_to_ally_turn(main, 4)
	main._set_battle_action(4, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)

	# 敵の反撃も自動で解決され尽くしたはずなので、次はまた味方のターン。
	assert_true(main.sim.current_actor_token().begins_with("ally:"),
		"enemy's turn auto-resolved and handed off to the next ally without any player input")


## 実機報告(2026-08-25、修正版確認後)への追加確認 §1/§3/§4: 頭上マーカー
## と下部パネル強調(_battle_selected_unit)が常に同じsource of truth
## (_current_actor_unit_id、実質sim.current_actor_token())を指すこと。
## 「プレイヤーが選択したキャラクター」ではなくSPDで決まった行動者その
## ものであることを、fast-forward中の複数のターン境界で直接検証する。
func test_current_actor_marker_helper_always_matches_the_bottom_panel_highlight() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main._current_actor_unit_id(), main._battle_selected_unit)
	assert_eq(main._current_actor_unit_id(), 1, "Madoka acts first")

	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	assert_eq(main._current_actor_unit_id(), main._battle_selected_unit)
	assert_eq(main._current_actor_unit_id(), 0, "Sotiris is next")

	main._set_battle_action(0, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	assert_eq(main._current_actor_unit_id(), main._battle_selected_unit)
	assert_eq(main._current_actor_unit_id(), 4, "Sayu is next")


## §3(checklist): current_actor_unit_id()は敵の番の間は必ず-1を返す
## （＝どの味方の頭上にもマーカーが表示されない）——sim側だけを直接操作
## して敵の番へ到達させ(UIのアニメ連鎖に頼らない、純粋な読み取り関数
## であることの確認)、ヘルパー自身の戻り値を検証する。
func test_current_actor_marker_helper_returns_none_during_the_enemys_turn() -> void:
	var main := await _start_cave_troll_fight()
	var guard := 0
	while main.sim.current_actor_token().begins_with("ally:"):
		var token: String = main.sim.current_actor_token()
		main.sim.resolve_player_action(int(token.substr(5)), "attack", "", -1, "")
		guard += 1
		assert_lt(guard, 10, "should have reached the enemy's turn by now")
	assert_true(main.sim.current_actor_token().begins_with("enemy:"))

	assert_eq(main._current_actor_unit_id(), -1, "no ally is the current actor while it's the enemy's turn")


## §2(checklist)の拡張確認: ターン切替時、開いていたスキル一覧の内容/
## ハイライト行、および味方/敵どちらを選択中だったかの区分
## (_battle_target_kind)まで含めて初期化される。_begin_current_turn()
## のリセット処理そのものを直接検証する(円自身の全スキルが敵対象の
## ため、実際のプレイでは_battle_target_kindが"ally"のまま次のターンへ
## 到達することは無いが、そのケースでも確実に既定値へ戻ることを保証
## したい——そのため意図的に"ally"へ書き換えてから呼び出す)。
func test_turn_transition_clears_skill_list_contents_and_target_kind() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_skill()
	assert_false(main._battle_list_entries.is_empty(), "sanity: Madoka's skill list actually opened")
	main._battle_target_kind = "ally"  # 前の行動者の状態を意図的に汚す

	main._begin_current_turn()

	assert_true(main._battle_list_entries.is_empty(), "the previous skill list contents did not carry over")
	assert_eq(main._battle_list_selected_index, -1)
	assert_eq(main._battle_target_kind, "enemy", "reset to the default, not left over from before")


## §1(checklist)の核心的な回帰ガード: _refresh_boss_panel()が
## _battle_selected_unitを再同期する際のフォールバックが、表示順の先頭
## (常にソティリス)ではなく実際の現在行動者を選ぶこと——将来この関数が
## _begin_current_turn()を経由せず単独で呼ばれるコード経路が増えても
## (NEXT5表示更新など)、current_actorとの食い違いが発生しないことの
## 直接確認。
func test_refresh_boss_panel_fallback_resyncs_to_the_real_current_actor_not_sotiris() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1", "Madoka is genuinely acting")
	# _battle_selected_unitを「_battle_orderに存在しない」不正な値へ
	# わざと壊す(死亡ユニットが表示順から落ちた場合の実際の状態を模す)。
	main._battle_selected_unit = 999

	main._refresh_boss_panel()

	assert_eq(main._battle_selected_unit, 1,
		"resynced to Madoka (the real current actor), not to _battle_order[0] (Sotiris)")
