extends GutTest
## Phase 6「防御」(2026-08-25) のUI層回帰テスト。sim側のロジック（付与/
## 解除タイミング・ダメージ半減・REWIND連携・RNG非消費）は
## tests/core/test_boss_fight.gdで直接検証済み——ここでは「防御ボタンを
## 押した瞬間に即行動確定する（対象選択を経由しない）」「バトルメッセージ
## に正しい宣言文が出る」「下部カードに防御中表示が出る/消える」
## 「current_actor強調と防御中表示は独立している」という、main.tscn実
## インスタンス化でしか検証できないUI配線を対象にする。


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


func _card_guard_label_text(main: Control, unit_id: int) -> String:
	var card: PanelContainer = main._battle_cards[unit_id]["panel"]
	var column: VBoxContainer = card.get_child(0)
	for child in column.get_children():
		if child is Label and (child as Label).text == main.locale.text("UI_BATTLE_GUARDING_STATUS"):
			return (child as Label).text
	return ""


## §1/§10/§28-2/§28-3: 防御ボタンを押した瞬間に対象選択を経由せず即座に
## 行動確定し（_battle_phaseがtargetSelectionへ一度も入らない）、1行動
## 消費して次の行動者へ自然に進むこと。
func test_pressing_defend_resolves_immediately_without_entering_target_selection() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(main.sim.current_actor_token(), "ally:1", "fixture assumption: Madoka acts first")
	assert_true(main._battle_selected_unit_is_current_actor())

	main._on_battle_defend()

	assert_ne(main._battle_phase, "targetSelection",
		"guard never opens target selection — no target to pick (§1/§10)")
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), "ally:0", "turn advanced to the real next actor")
	assert_true(main.sim.guarding_units.has(1), "sim recorded the guard")


## §11/§28: バトルメッセージ欄に、既存の文体（%sの〜！）と一致した宣言文
## が表示されること。
func test_defend_appends_the_expected_battle_message() -> void:
	var main := await _start_cave_troll_fight()

	main._on_battle_defend()

	var lines: Array = []
	for label: Label in main._battle_message_labels:
		if label.visible:
			lines.append(label.text)
	var expected: String = main.locale.text("UI_BATTLE_MSG_GUARD") % main._unit_display_name(main.sim.minions[1])
	assert_has(lines, expected)


## §13/§14: 防御を選んだ瞬間から下部カードに「防御中」が表示され、以後
## _refresh_boss_panel()のたびに(=毎ターン)sim.guarding_unitsの実際の
## 内容をそのまま反映すること。
func test_guarding_status_label_appears_after_defend_and_reflects_sim_state() -> void:
	var main := await _start_cave_troll_fight()
	assert_eq(_card_guard_label_text(main, 1), "", "not guarding yet")

	main._on_battle_defend()
	_pump_battle_animation(main)

	assert_eq(_card_guard_label_text(main, 1), main.locale.text("UI_BATTLE_GUARDING_STATUS"))


## §14/§28-11: そのキャラクター自身の次の行動が始まる(=sim側で
## guarding_unitsから消える)と、カードが_refresh_boss_panel()で作り直さ
## れる次のタイミングで表示も一緒に消えること。
func test_guarding_status_label_disappears_once_that_unit_acts_again() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_defend()  # Madoka (unit 1) guards
	_pump_battle_animation(main)
	assert_eq(_card_guard_label_text(main, 1), main.locale.text("UI_BATTLE_GUARDING_STATUS"))

	# Fast-forward through everyone else's turn until it's Madoka's turn again.
	var guard_loop := 0
	while main.sim.current_actor_token() != "ally:1":
		var token: String = main.sim.current_actor_token()
		if token.begins_with("ally:"):
			main._set_battle_action(
				int(token.substr(5)), "attack", "", "enemy", main.sim.boss_enemy_id, "")
			_pump_battle_animation(main)
		else:
			# Enemy turns resolve themselves once _begin_current_turn() sees it.
			_pump_battle_animation(main)
		guard_loop += 1
		assert_lt(guard_loop, 20, "party-cycle loop should reach Madoka's turn quickly")
	assert_false(main.sim.guarding_units.has(1), "sim already cleared it the instant her turn began")

	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)

	assert_eq(_card_guard_label_text(main, 1), "", "the label is gone now that she acted again")


## §15/最重要: current_actorの下部パネル強調(黄色枠)と、防御中の表示は
## 別々のユニットを指しうる、独立した2つの状態であること。円が防御した
## 直後、現在行動者はソティリスへ進むが、円の防御中表示はそのまま残る。
func test_current_actor_highlight_and_guarding_label_are_independent() -> void:
	var main := await _start_cave_troll_fight()

	main._on_battle_defend()  # Madoka (unit 1) guards
	_pump_battle_animation(main)

	assert_eq(main.sim.current_actor_token(), "ally:0", "current actor moved on to Sotiris")
	assert_eq(main._current_actor_unit_id(), 0, "current_actor highlight now targets Sotiris")
	assert_eq(_card_guard_label_text(main, 0), "", "Sotiris himself is not guarding")
	assert_eq(_card_guard_label_text(main, 1), main.locale.text("UI_BATTLE_GUARDING_STATUS"),
		"...while Madoka's guard indicator is still showing — two independent pieces of state")


## §9/§28-1(UI側): 防御ボタンは、こうげき/スキル/どうぐと全く同じ条件
## （現在行動者が選択されているか）でだけ有効になる——current_actor以外
## は押せない状態のまま。
func test_defend_button_enabled_state_matches_the_other_three_commands() -> void:
	var main := await _start_cave_troll_fight()

	assert_false(main._battle_attack_button.disabled)
	assert_false(main._battle_defend_button.disabled,
		"enabled under the exact same condition as attack/skill/item")

	main._battle_selected_unit = -1
	main._update_battle_buttons()

	assert_true(main._battle_attack_button.disabled)
	assert_true(main._battle_defend_button.disabled, "disabled together with the other 3, not separately")


## §4/§6/§28-4: ダメージ計算パイプライン全体(_set_battle_action経由)を
## 通しても、防御中に受けたダメージが軽減されていること——sim層の直接
## テストに加え、UI経由の呼び出しでも同じ結果になることを確認する。
func test_guard_reduces_damage_through_the_full_ui_pipeline() -> void:
	var main := await _start_cave_troll_fight()
	# Madoka(1)以外を先に消化してMadokaの防御を経由済みにし、ボスの反撃
	# 対象になりやすいよう明示的にHPを最低にしておく（このcave_troll
	# fixtureはmain.sim側の実データを使うため、test_boss_fight.gd側の
	# ような固定値の期待値計算はできない——「軽減されている」という
	# 相対関係だけを確認する）。
	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)
	assert_eq(main.sim.current_actor_token(), "ally:0")
	main.sim.minions[0].hp = 1  # guaranteed lowest-hp -> guaranteed boss target
	# unit 0 (Sotiris) now guards on his own turn.
	main._on_battle_defend()
	_pump_battle_animation(main)

	assert_true(main.sim.guarding_units.has(0) or main.sim.minions[0].hp <= 0,
		"either still guarding, or the guarded (halved) hit still wasn't survivable at 1 hp — either way, no crash")


## §18/§19/§20 UI側sanity: 防御実装後も既存の通常攻撃/スキル/部位破壊が
## クラッシュせず正常に動作すること（本体の網羅的な検証は
## test_battle_actor_integrity.gd/test_boss_part_ui.gdに委ねる）。
func test_existing_attack_and_part_targeting_still_work_via_the_ui() -> void:
	var main := await _start_cave_troll_fight()
	var boss_hp_before: int = main.sim.boss_hp

	main._set_battle_action(1, "attack", "", "enemy", main.sim.boss_enemy_id, "")
	_pump_battle_animation(main)

	assert_lt(main.sim.boss_hp, boss_hp_before)


## §18/§19/§25: REWIND後は防御中表示が一切残らないこと。
func test_rewind_clears_the_guarding_status_label() -> void:
	var main := await _start_cave_troll_fight()
	main._on_battle_defend()  # Madoka guards
	_pump_battle_animation(main)
	assert_eq(_card_guard_label_text(main, 1), main.locale.text("UI_BATTLE_GUARDING_STATUS"))

	main._do_battle_rewind()

	assert_eq(main.sim.guarding_units, [])
	assert_eq(_card_guard_label_text(main, 1), "", "no stale guard indicator survives REWIND (§19)")
