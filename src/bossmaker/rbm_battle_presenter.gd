class_name RBMBattlePresenter
extends Node

## Displays already-resolved battle events. Never advances or mutates the simulation.
## The stage owns motion timing; its impact signal commits the corresponding HUD state.
signal entry_impact(entry: Dictionary)
signal finished

var enabled: bool = DisplayServer.get_name() != "headless"
var _stage: Node
var _battle: RBMBattle
var _entries: Array[Dictionary] = []
var _cursor: int = 0
var _playing: bool = false
var _impacted: bool = false
var _finishing_entry: bool = false
var _generation: int = 0
var _display_state: Dictionary = {}

func setup(stage: Node) -> void:
	if _stage == stage:
		return
	cancel()
	if is_instance_valid(_stage):
		if _stage.has_signal("impact") and _stage.is_connected("impact", _on_stage_impact):
			_stage.disconnect("impact", _on_stage_impact)
		if _stage.has_signal("finished") and _stage.is_connected("finished", _on_stage_finished):
			_stage.disconnect("finished", _on_stage_finished)
	_stage = stage
	if is_instance_valid(_stage):
		if _stage.has_signal("impact"):
			_stage.connect("impact", _on_stage_impact)
		if _stage.has_signal("finished"):
			_stage.connect("finished", _on_stage_finished)

func can_animate() -> bool:
	return enabled and is_instance_valid(_stage) and _stage.has_method("play_entry") and _stage.has_signal("finished")

func is_playing() -> bool:
	return _playing

func display_state() -> Dictionary:
	return _display_state.duplicate(true)

func play(entries: Array, battle: RBMBattle, initial_state: Dictionary = {}) -> void:
	cancel()
	_battle = battle
	for entry in entries:
		_entries.append(entry)
	_display_state = initial_state.duplicate(true)
	if is_instance_valid(_stage) and _stage.has_method("set_state") and not initial_state.is_empty():
		_stage.call("set_state", _display_state)
	_playing = true
	_cursor = 0
	_advance(_generation)

func cancel() -> void:
	_generation += 1
	_playing = false
	_entries.clear()
	_cursor = 0
	_impacted = false
	_finishing_entry = false
	if is_instance_valid(_stage) and _stage.has_method("cancel"):
		_stage.call("cancel")

func _advance(generation: int) -> void:
	if generation != _generation or not _playing:
		return
	if _cursor >= _entries.size():
		_playing = false
		_entries.clear()
		finished.emit()
		return
	_impacted = false
	_finishing_entry = false
	var entry: Dictionary = _entries[_cursor]
	if not can_animate() or str(entry.get("action", "none")) == "none" or bool(entry.get("failed", false)):
		_on_stage_impact(entry)
		_on_stage_finished()
		return
	var skill := RBMBattleUiKit.find_skill_for_actor(entry.get("actor"), str(entry.get("skill_id", "")), _battle)
	_stage.call("play_entry", entry, skill)

func _on_stage_impact(incoming_entry: Dictionary) -> void:
	if not _playing or _impacted or _cursor >= _entries.size():
		return
	if incoming_entry != _entries[_cursor]:
		return
	_impacted = true
	var entry: Dictionary = _entries[_cursor]
	_display_state = (entry.get("visual_state", _display_state) as Dictionary).duplicate(true)
	if is_instance_valid(_stage) and _stage.has_method("set_state"):
		_stage.call("set_state", _display_state)
	entry_impact.emit(entry)

func _on_stage_finished() -> void:
	if not _playing or _finishing_entry or _cursor >= _entries.size():
		return
	# A stage without an impact marker still commits each event exactly once.
	if not _impacted:
		_on_stage_impact(_entries[_cursor])
	_finishing_entry = true
	_cursor += 1
	_advance.call_deferred(_generation)

func _exit_tree() -> void:
	cancel()

## Update existing named HUD nodes without destroying the actor playing a motion.
static func apply_status_snapshot(view: Control, state: Dictionary) -> void:
	if state.is_empty():
		return
	var party: Dictionary = state.get("party", {})
	for id_key in party:
		var unit: Dictionary = party[id_key]
		var unit_id := int(unit.get("id", id_key))
		var hp := int(unit.get("hp", 0))
		var max_hp := int(unit.get("max_hp", 1))
		var sp := int(unit.get("sp", 0))
		var max_sp := int(unit.get("max_sp", RBMConstants.NO_SP))
		var name_label := view.find_child("PartyRowName_%d" % unit_id, true, false) as Label
		if name_label != null:
			name_label.text = "%s%s" % [str(unit.get("display_name", "")), "（戦闘不能）" if hp <= 0 else ""]
		var hp_label := view.find_child("PartyRowHP_%d" % unit_id, true, false) as Label
		if hp_label != null:
			hp_label.text = "HP %d / %d" % [hp, max_hp]
		var hp_bar := view.find_child("PartyRowHPBar_%d" % unit_id, true, false) as ProgressBar
		if hp_bar != null:
			hp_bar.max_value = maxf(1.0, float(max_hp))
			hp_bar.value = hp
		var sp_label := view.find_child("PartyRowSP_%d" % unit_id, true, false) as Label
		if sp_label != null:
			sp_label.text = "SP -" if max_sp == RBMConstants.NO_SP else "SP %d / %d" % [sp, max_sp]
		var sp_bar := view.find_child("PartyRowSPBar_%d" % unit_id, true, false) as ProgressBar
		if sp_bar != null:
			sp_bar.max_value = maxf(1.0, float(max_sp))
			sp_bar.value = sp
		var card := view.find_child("PartyRow_%d" % unit_id, true, false) as Control
		if card != null:
			card.modulate = Color(1.0, 1.0, 1.0, 0.55 if hp <= 0 else 1.0)
	var boss_label := view.find_child("BossLabel", true, false) as Label
	if boss_label != null:
		var boss: Dictionary = state.get("boss", {})
		boss_label.text = "%s　（ターン%d）" % [str(boss.get("display_name", "")), int(state.get("turn", 1))]
