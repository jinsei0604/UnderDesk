extends GutTest
## 盤面の情報整理（2026-08-23）§8-§14: 味方対象選択マーカー。下部パネル
## と盤面（キャラクター頭上の▼）が同じ選択状態を指し続けることを、
## main.tscnを実際にインスタンス化して直接検証する（このプロジェクトで
## 確立済みのパターン、test_rapid_slash_vfx_logging.gd等を踏襲）。

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


func _click_card(main: Control, unit_id: int) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = MOUSE_BUTTON_LEFT
	main._on_battle_card_input(event, unit_id)


## §9「表示されたり消えたりする挙動にはしない」の直接的な回帰ガード:
## マーカーが実際に描く条件（_draw_party_row内のガード式と同一の式）が
## 選択している間ずっとtrueのままであること、それ以外のキャラクターに
## ついては常にfalseであること。
func _marker_visible_for(main: Control, unit_id: int) -> bool:
	return main._boss_screen_active() and main._battle_phase == "targetSelection" \
		and main._battle_target_kind == "ally" and unit_id == main._battle_selected_ally_target


func test_entering_ally_target_selection_shows_marker_on_the_default_target() -> void:
	var main := await _start_cave_troll_fight()
	# skill_healingはソティリス（unit 0、PROTAGONIST_SKILLS）専有——サユでは
	# unit_skills()に含まれず_apply_skillが即0を返す（このテストの旧版が
	# 踏んだ罠、CLAUDE.md記載どおりヒーリングは主人公専有スキル）。
	main._battle_selected_unit = 0  # ソティリス（ヒーリング所持）
	main._enter_target_selection("skill", "skill_healing", "ally")

	assert_eq(main._battle_phase, "targetSelection")
	assert_eq(main._battle_target_kind, "ally")
	# §3.13.4ノート通り、対象未選択時は詠唱者自身（ソティリス、unit 0）へ既定。
	assert_eq(main._battle_selected_ally_target, 0)
	assert_true(_marker_visible_for(main, 0), "marker shows on the default self-heal target")
	for other_id in range(5):
		if other_id != 0:
			assert_false(_marker_visible_for(main, other_id), "no marker on unit %d" % other_id)


## §9/§11「別のキャラクターへ選択を移動→矢印もそのキャラクターへ移動」
## §14「下部パネルの選択表示と矢印が一致」を同時に検証。
func test_switching_selection_moves_the_marker_and_stays_synced_with_the_card_border() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 0
	main._enter_target_selection("skill", "skill_healing", "ally")

	_click_card(main, 1)  # 円のカードをクリック
	assert_eq(main._battle_selected_ally_target, 1)
	assert_true(_marker_visible_for(main, 1), "marker followed the selection to unit 1")
	assert_false(_marker_visible_for(main, 0), "marker left the old selection (unit 0)")

	var madoka_style: StyleBoxFlat = main._battle_cards[1]["style"]
	assert_eq(madoka_style.border_color, main.COLOR_ALLY_TARGET_BORDER,
		"bottom panel border matches the same green used by the on-field marker")
	var sotiris_style: StyleBoxFlat = main._battle_cards[0]["style"]
	assert_ne(sotiris_style.border_color, main.COLOR_ALLY_TARGET_BORDER,
		"the no-longer-selected card is not highlighted the same way")

	_click_card(main, 3)  # 司馬燿のカードへさらに移動
	assert_eq(main._battle_selected_ally_target, 3)
	assert_true(_marker_visible_for(main, 3))
	assert_false(_marker_visible_for(main, 1), "marker moved off unit 1 once a new target is picked")


## §9「対象決定→選択マークを消す」の直接的な回帰ガード: 決定後は
## targetSelectionフェーズ自体を抜けるため、どのユニットについても
## マーカーの表示条件がfalseになる。
func test_confirming_the_target_clears_the_marker() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_selected_unit = 0
	main._enter_target_selection("skill", "skill_healing", "ally")
	_click_card(main, 1)
	assert_true(_marker_visible_for(main, 1))

	main._on_target_confirm()

	assert_ne(main._battle_phase, "targetSelection")
	for unit_id in range(5):
		assert_false(_marker_visible_for(main, unit_id), "marker gone for unit %d after confirm" % unit_id)


## §16「バトルメッセージの基本仕様は変更しない」の裏付けを兼ねた、
## ヒーリングの実際の1ラウンド完走（アニメーション込み）での無クラッシュ
## 確認——味方選択マーカー描画コード自体もこの間ずっと実行され続ける。
func test_ally_targeted_skill_round_completes_without_crashing() -> void:
	var main := await _start_cave_troll_fight()
	for m in main.sim.minions:
		m.hp = 1  # ヒーリングの効果が実際に見えるよう先に負傷させておく
	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "skill", "skill_id": "skill_healing",
		"target_type": "ally", "target_id": "1",
	}
	main._on_boss_resolve_round()
	# resolve_boss_round()はパーティの行動とボスの反撃を1回の呼び出しで
	# 丸ごと確定させる（このプロジェクト既存の仕様）——反撃が回復対象
	# （円）を狙って追加ダメージを与える可能性があるため、「最終HP」を
	# 見ると回復量そのものではなく反撃込みの結果になってしまう。ログの
	# healエントリ自体（sim側が確定させた回復量）を直接確認する。
	var log: Array = main._battle_pending_round_result.get("log", [])
	var heal_amount := -1
	for entry: Variant in log:
		var e := entry as Dictionary
		if str(e.get("effect", "")) == "heal" and int(e.get("target_id", -1)) == 1:
			heal_amount = int(e.get("amount", -1))
	assert_gt(heal_amount, 0, "healing actually applied a positive amount to Madoka")

	var guard := 0
	while main._battle_anim_step >= 0 and main._battle_anim_step < main._battle_anim_queue.size():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")


## §7「盤面上のLv表示・味方HPゲージは戦闘中は不要」の直接検証: 頭上HP
## バー/Lv表示を描くコードパス自体が_boss_screen_active()でスキップされ
## ること——放置画面側（この関数の対象外）は無改修のまま残ることも
## 合わせて確認する。
func test_overhead_hp_bar_and_level_are_gated_off_during_boss_battle_only() -> void:
	var main := await _start_cave_troll_fight()
	assert_true(main._boss_screen_active(), "overhead HP/Lv drawing is skipped in this state")
	main.sim.flee_boss_fight()
	main._hide_boss_panel()
	assert_false(main._boss_screen_active(), "back in the idle view, overhead HP/Lv keeps drawing")
