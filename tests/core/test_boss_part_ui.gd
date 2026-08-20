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
	var rows_container: HFlowContainer = main._target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	# §2/§3: 洞窟トロル［本体］/ 右腕 / 脚 — one selectable row per entry in
	# _battle_enemy_targets(), not just the crosshair's invisible cycling.
	assert_eq(rows_container.get_child_count(), 3, "main body + arm + leg")
	var arm_target_id: String = str(main.sim.boss_enemy_id) + "#arm"
	main._on_enemy_target_row_selected(arm_target_id)
	assert_eq(main._battle_selected_target_id, arm_target_id)
	var target_line: Label = main._target_confirm_panel.find_child("target_line", true, false)
	assert_string_contains(target_line.text, "右腕")


func test_part_targeted_attack_round_animates_without_crashing_and_leaves_boss_hp_untouched() -> void:
	var main := await _start_cave_troll_fight()
	main._battle_pending_actions.clear()
	# Only unit 0 acts this round ("units without an entry simply do
	# nothing", resolve_boss_round()'s own doc comment) — deliberately not
	# every party member: a single hit can't come close to destroying the
	# arm's 180 HP, so boss_hp's "must stay untouched" assertion below
	# stays valid regardless of live party ATK numbers (a multi-unit round
	# risks the arm actually breaking mid-round and a LATER hit legitimately
	# redirecting to boss_hp per sim's own _apply_boss_damage() — correct
	# behavior, just not what this particular test is checking).
	main._battle_pending_actions[0] = {
		"action": "attack", "target_type": "enemy",
		"target_id": main.sim.boss_enemy_id, "target_part": "arm",
	}
	main._on_boss_resolve_round()
	var guard := 0
	while main._battle_anim_step >= 0 and main._battle_anim_step < main._battle_anim_queue.size():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")
	# §12: a part-targeted hit must never have touched the main body's pool.
	assert_eq(main.sim.boss_hp, 600)
	assert_lt(int(main.sim.boss_part_hp["arm"]), 180, "the arm actually took damage")
	# §4/§8: the panel's own rows (rebuilt by _finish_battle_round's trailing
	# _refresh_boss_panel) must reflect that same real, post-round value —
	# not a stale shadow left over from mid-animation.
	var arm_bar: ProgressBar = main._boss_part_rows["arm"]["bar"]
	assert_eq(int(arm_bar.value), int(main.sim.boss_part_hp["arm"]))
