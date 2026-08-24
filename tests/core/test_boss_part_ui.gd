extends GutTest
## 新企画v1仕様書 v2 §17 (2026-08-21 playtest-fix round): a real playthrough
## on cave_troll found the part-destruction mechanic entirely unreachable
## through the UI — no visible way to pick a body part as a target, and the
## HP readout was too small/dim to reason about. These tests exercise the
## rebuilt boss-HP panel and target-row picker against the REAL main.tscn
## scene (same instantiate-a-real-scene-inside-GUT pattern already proven
## by test_rapid_slash_vfx_logging.gd, which this file borrows its helper
## structure from) rather than a synthetic sim-only fixture, so they catch
## anything the sim-layer tests in test_boss_fight.gd structurally can't:
## whether the new widgets actually get built/populated, and whether a
## part-targeted hit survives the real animation pipeline without a
## crash.

const GATE_10_STAGE_INDEX := 10  # data/stages/020_gate10.json, cave_troll's gate


func _start_cave_troll_fight() -> Control:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	var main: Control = add_child_autofree(scene.instantiate())
	if not main.is_node_ready():
		await main.ready
	main.autosave_timer.stop()
	main.tick_timer.stop()
	if main.sim.boss_active:
		main.sim.flee_boss_fight()
	main.sim.stage_index = GATE_10_STAGE_INDEX
	for m in main.sim.minions:
		m.hp = main.sim.unit_max_hp(m)
		m.sp = main.sim.unit_max_sp(m)
	assert_true(main.sim.start_boss_fight())
	assert_eq(main.sim.boss_enemy_id, "cave_troll")
	# Same reason test_rapid_slash_vfx_logging.gd calls this: _battle_order
	# (which the animation queue builder depends on) is only populated by
	# the real "挑む" UI flow (_show_boss_panel -> _refresh_boss_panel),
	# never by sim.start_boss_fight() alone.
	main._show_boss_panel()
	return main


func test_boss_parts_column_shows_both_parts_with_readable_values() -> void:
	var main := await _start_cave_troll_fight()
	assert_true(main._boss_parts_column.visible)
	assert_eq(main._boss_part_rows.size(), 2, "arm + leg")
	assert_true(main._boss_part_rows.has("arm"))
	assert_true(main._boss_part_rows.has("leg"))
	var arm_bar: ProgressBar = main._boss_part_rows["arm"]["bar"]
	var arm_text: Label = main._boss_part_rows["arm"]["text"]
	assert_eq(int(arm_bar.max_value), 180)
	assert_eq(int(arm_bar.value), 180)
	# §5: the player-facing name must be localized ("右腕"), never the raw
	# internal id ("arm") the first prototype showed directly.
	var arm_name: Label = main._boss_part_rows["arm"]["name"]
	assert_ne(arm_name.text, "arm")
	assert_eq(arm_text.text, "180/180")
	assert_eq(main._boss_body_hp_label.text, "600/600")


func test_enemy_target_rows_list_body_and_both_parts_and_track_selection() -> void:
	var main := await _start_cave_troll_fight()
	main._enter_target_selection("attack", "", "enemy")
	var rows_container: VBoxContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	# §2/§3: 洞窟トロル［本体］/ 右腕 / 脚 — one selectable row per entry in
	# _battle_enemy_targets(), not just the crosshair's invisible cycling.
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")
	var arm_target_id: String = str(main.sim.boss_enemy_id) + "#arm"
	main._on_enemy_target_row_selected(arm_target_id)
	assert_eq(main._battle_selected_target_id, arm_target_id)
	var target_line: Label = main._target_confirm_panel.find_child("target_line", true, false)
	assert_string_contains(target_line.text, "右腕")


## 新戦闘進行システム v1 (2026-08-24): 誰の番かはSPD順で決まる——unit 0の
## 番まで、間の味方の番を通常攻撃（本体狙い、target_part=""）で消化して
## から、unit 0自身にだけ腕を狙わせる。他ユニットは腕へ一切触れないので
## 「a single hit can't come close to destroying the arm's 180 HP」という
## 前提（boss_hp未変化の検証）は元の設計どおり成立する。
func _fast_forward_to_ally_turn(main: Control, unit_id: int) -> void:
	var guard := 0
	while main.sim.current_actor_token() != "ally:%d" % unit_id:
		var token: String = main.sim.current_actor_token()
		assert_true(token.begins_with("ally:"))
		main._set_battle_action(
			int(token.substr(5)), "attack", "", "enemy", main.sim.boss_enemy_id, "")
		var pump_guard := 0
		while main._battle_anim_step >= 0:
			main._on_battle_anim_tick()
			pump_guard += 1
			assert_lt(pump_guard, 5000, "battle animation never settled")
		guard += 1
		assert_lt(guard, 10, "fast-forward looped too many times")


func test_part_targeted_attack_round_animates_without_crashing_and_leaves_boss_hp_untouched() -> void:
	var main := await _start_cave_troll_fight()
	_fast_forward_to_ally_turn(main, 0)
	# 円がunit 0より先に番を持つ実データのため、fast-forward中に円自身の
	# 通常攻撃（本体狙い）がboss_hpを正当に削っている——このテストが検証
	# したいのは「その後のunit 0自身の"腕"狙いの一撃が本体HPへ波及しない
	# こと」だけなので、600固定ではなくunit 0の行動直前の実値を基準にする。
	var boss_hp_before_this_hit: int = main.sim.boss_hp
	main._set_battle_action(0, "attack", "", "enemy", main.sim.boss_enemy_id, "arm")
	var guard := 0
	while main._battle_anim_step >= 0:
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")
	# §12: a part-targeted hit must never have touched the main body's pool.
	assert_eq(main.sim.boss_hp, boss_hp_before_this_hit)
	assert_lt(int(main.sim.boss_part_hp["arm"]), 180, "the arm actually took damage")
	# §4/§8: the panel's own rows (rebuilt by _finish_battle_round's trailing
	# _refresh_boss_panel) must reflect that same real, post-round value —
	# not a stale shadow left over from mid-animation.
	var arm_bar: ProgressBar = main._boss_part_rows["arm"]["bar"]
	assert_eq(int(arm_bar.value), int(main.sim.boss_part_hp["arm"]))
