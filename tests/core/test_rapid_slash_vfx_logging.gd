extends GutTest
## rapid_slash v3's debug logging (2026-07-26): each expected message must
## fire exactly once per cast — regression guard for two separate reports
## on the same feature. First round ("wave_a/b/cが1個のVFXのフレーム切替に
## 見えている"): the fix was making each wave a genuinely independent
## stateful object (see main.gd's _rapid_slash_waves/_update_rapid_slash_
## waves) instead of one shared position sampled at 3 slightly different
## times. Second round ("消えたはずの大三日月が再び表示され...約1秒間貼り
## 付いています"): a wave's "active" flag was only ever set true on launch
## and never reset on arrival, so an arrived wave kept drawing forever,
## frozen at target_pos — fixed by _deactivate_rapid_wave/_start_rapid_
## impact, verified below by asserting no wave is ever "active" again once
## "RAPID impact finished" has logged.


func _run_one_rapid_slash_round() -> Control:
	var scene: PackedScene = load("res://src/ui/main.tscn")
	var main: Control = add_child_autofree(scene.instantiate())
	if not main.is_node_ready():
		await main.ready
	main.autosave_timer.stop()
	main.tick_timer.stop()

	for m in main.sim.minions:
		m.hp = main.sim.unit_max_hp(m)
		m.sp = main.sim.unit_max_sp(m)
	if not main.sim.boss_active:
		main.sim.start_boss_fight()
	# _battle_order (which _build_battle_anim_queue depends on to know who
	# actually acted) is only populated by the normal "挑む" UI flow
	# (_show_boss_panel -> _refresh_boss_panel), never by sim.start_boss_
	# fight() alone. Without this the queue silently comes back empty
	# whenever the on-disk save this scene loads happens to NOT already be
	# mid-fight (boss_active: false) — a real, reproducible flake this test
	# hit in practice, not something the rapid_slash feature itself caused.
	main._show_boss_panel()

	main._battle_pending_actions.clear()
	main._battle_pending_actions[0] = {
		"action": "skill", "skill_id": "skill_rapid_slash",
		"target_type": "enemy", "target_id": main.sim.boss_enemy_id,
	}
	for m in main.sim.minions:
		if m.id == 0:
			continue
		main._battle_pending_actions[m.id] = {
			"action": "attack", "target_type": "enemy", "target_id": main.sim.boss_enemy_id,
		}
	main._on_boss_resolve_round()
	return main


func test_rapid_slash_debug_logs_each_fire_exactly_once() -> void:
	var main := await _run_one_rapid_slash_round()
	var guard := 0
	while main._battle_anim_step >= 0 and main._battle_anim_step < main._battle_anim_queue.size():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")

	var expected := [
		"RAPID wave_a launched", "RAPID wave_a arrived", "RAPID wave_a deactivated",
		"RAPID wave_b launched", "RAPID wave_b arrived", "RAPID wave_b deactivated",
		"RAPID wave_c launched", "RAPID wave_c arrived", "RAPID wave_c deactivated",
		"RAPID all waves cleared before impact",
		"RAPID impact started", "RAPID damage fired", "RAPID impact finished",
		"RAPID VFX state reset",
	]
	for msg: String in expected:
		assert_eq(
			int(main._rapid_slash_debug_log_counts.get(msg, 0)), 1,
			"expected exactly 1 fire for: %s" % msg)


## Regression guard for the "big crescent stuck in front of the enemy for
## ~1 second" bug: once "RAPID impact finished" has logged, no wave may
## ever be "active" again — main.gd's own draw gate (in _draw_rapid_slash_
## vfx) requires active=true to draw a wave at all, so "never active again"
## is equivalent to "never drawn again" without needing an actual render
## pass (headless Godot can't render — see this file's sibling tests/
## project convention of asserting the gating STATE instead).
func test_no_wave_is_active_after_impact_finishes() -> void:
	var main := await _run_one_rapid_slash_round()
	var impact_finished := false
	var guard := 0
	while main._battle_anim_step >= 0 and main._battle_anim_step < main._battle_anim_queue.size():
		main._on_battle_anim_tick()
		guard += 1
		assert_lt(guard, 5000, "battle animation never finished")
		if int(main._rapid_slash_debug_log_counts.get("RAPID impact finished", 0)) > 0:
			impact_finished = true
		if impact_finished:
			for w: Dictionary in main._rapid_slash_waves:
				assert_false(
					bool(w.get("active", false)),
					"%s was active after impact finished" % str(w.get("label", "?")))
	assert_true(impact_finished, "impact never finished during this round")
