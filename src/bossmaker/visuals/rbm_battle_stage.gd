class_name RBMBattleStage
extends Control

## Visual playback of already resolved combat entries. This node never advances
## RBMBattle, changes a unit, selects a target, or reads/consumes battle RNG.
signal impact(entry: Dictionary)
signal finished
signal ally_clicked(unit_id: int)
signal boss_clicked

const Sound = preload("res://src/bossmaker/rbm_audio.gd")
var _sound: Node

const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")
const Motions = preload("res://src/bossmaker/visuals/rbm_motion_catalog.gd")
const ACTOR_SCRIPT := "res://src/bossmaker/visuals/rbm_character_visual.gd"
const HeroFire = preload("res://src/bossmaker/visuals/rbm_hero_fire_finish.gd")
const HeroSword = preload("res://src/bossmaker/visuals/rbm_hero_sword.gd")
const ButlerIce = preload("res://src/bossmaker/visuals/rbm_butler_ice_finish.gd")
var _hero_fire: Node2D
var _hero_finish := false
var _hero_elapsed := -1.0
var _hero_shake := Vector2.ZERO
var _butler_ice: Node2D
var _butler_finish := false
var _butler_elapsed := -1.0
var _butler_shake := Vector2.ZERO

var _battle: Variant
var _appearance_id := ""
var _visuals: Dictionary = {}
var _homes: Dictionary = {}
var _poses: Dictionary = {}
var _asset_ids: Dictionary = {}
var _party_keys: Array[String] = []
var _state: Dictionary = {}
var _entry: Dictionary = {}
var _skill: Dictionary = {}
var _profile: Dictionary = {}
var _actor := ""
var _targets: Array[String] = []
var _counters: Array[String] = []
var _guards: Array[String] = []
var _playing := false
var _phase := "idle"
var _progress := 0.0
var _tween: Tween
var _layout_pending := false
var _effects: Control
var _canvas: CanvasItem
var _motion_offset := Vector2.ZERO
var _guard_offsets: Dictionary = {}
var _counter_offsets: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(420, 230)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true

func _ready() -> void:
	_sound = Sound.for_owner(self)
	_effects = Control.new()
	_effects.name = "MotionEffects"
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects.z_index = 10
	add_child(_effects)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effects.draw.connect(_draw_effects)
	_hero_fire = HeroFire.new()
	_hero_fire.z_index = 80
	_hero_fire.visible = false
	add_child(_hero_fire)
	_butler_ice = ButlerIce.new()
	_butler_ice.z_index = 80
	_butler_ice.visible = false
	add_child(_butler_ice)
	resized.connect(_layout_actors)
	_layout_actors()

func configure(battle: Variant, appearance_id: String = "") -> void:
	if battle == null:
		cancel()
		return
	var keys: Array[String] = []
	for unit in battle.party:
		if keys.size() < 4:
			keys.append(str(unit.id))
	if _battle == battle and _appearance_id == appearance_id and keys == _party_keys and not _visuals.is_empty():
		return
	cancel()
	for visual in _visuals.values():
		if is_instance_valid(visual):
			remove_child(visual)
			visual.queue_free()
	_visuals.clear()
	_homes.clear()
	_poses.clear()
	_asset_ids.clear()
	_battle = battle
	_appearance_id = appearance_id
	_party_keys = keys
	for unit in battle.party:
		if not _party_keys.has(str(unit.id)):
			continue
		_add_actor(str(unit.id), str(unit.character_id))
	_add_actor("boss", Assets.boss_asset(appearance_id))
	_layout_actors()
	_queue_visual_redraw()

func _add_actor(key: String, asset_id: String) -> void:
	var visual: Control
	if ResourceLoader.exists(ACTOR_SCRIPT):
		var script: Script = load(ACTOR_SCRIPT)
		visual = script.new() as Control
	else:
		visual = Control.new()
	visual.name = "Actor_" + key
	visual.z_index = 1 if key == "boss" else 2
	visual.mouse_filter = Control.MOUSE_FILTER_STOP
	visual.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visual.gui_input.connect(func(event: InputEvent):
		if _playing:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if key == "boss": boss_clicked.emit()
			else: ally_clicked.emit(int(key))
	)
	add_child(visual)
	_visuals[key] = visual
	_asset_ids[key] = asset_id
	_poses[key] = 0
	if visual.has_method("setup"):
		visual.call("setup", asset_id, Assets.display_height(asset_id) if not asset_id.is_empty() else 150.0)
		if asset_id == "hero":
			var sword := HeroSword.new()
			sword.scale = Vector2.ONE * float(visual.get("_pixel_scale"))
			sword.z_index = 1
			visual.add_child(sword)

func _layout_actors() -> void:
	if _playing:
		_layout_pending = true
		return
	_layout_pending = false
	if has_meta("fullscreen_formation"):
		var positions := [Vector2(430,525),Vector2(275,490),Vector2(430,405),Vector2(275,370)]
		for index in range(_party_keys.size()):
			_place_foot(_party_keys[index],positions[index])
		_place_foot("boss",Vector2(780,474))
		_queue_visual_redraw()
		return
	var safe_size := Vector2(maxf(size.x, 420.0), maxf(size.y, 230.0))
	var spacing := minf(78.0, safe_size.x * 0.135)
	var row_width := spacing * maxf(float(_party_keys.size() - 1), 0.0)
	var first_x := safe_size.x * 0.30 - row_width * 0.5
	for index in range(_party_keys.size()):
		var key := _party_keys[index]
		_place_foot(key, Vector2(first_x + spacing * index, safe_size.y - 15.0 - (index % 2) * 5.0))
	var boss_x := safe_size.x * 0.80
	var boss_visual: Control = _visuals.get("boss")
	if is_instance_valid(boss_visual) and boss_visual.has_method("all_pose_bounds"):
		var bounds: Rect2 = boss_visual.all_pose_bounds()
		var right_extent: float = bounds.end.x - boss_visual.foot_position().x
		# Preserve the sprite's size and reserve its longest pose plus hit recoil.
		boss_x = minf(boss_x, safe_size.x - right_extent - 16.0)
	_place_foot("boss", Vector2(boss_x, safe_size.y - 45.0))
	_queue_visual_redraw()

func _place_foot(key: String, foot: Vector2) -> void:
	if not _visuals.has(key):
		return
	var visual: Control = _visuals[key]
	var local_foot := Vector2.ZERO
	if visual.has_method("foot_position"):
		local_foot = visual.call("foot_position")
	visual.position = (foot - local_foot).round()
	_homes[key] = visual.position

func set_state(snapshot: Dictionary) -> void:
	if _playing and is_instance_valid(_sound):
		var previous: Dictionary = _state.get("party", {})
		var incoming: Dictionary = snapshot.get("party", {})
		for key in incoming:
			if previous.has(key) and int(previous[key].get("hp", 0)) > 0 and int(incoming[key].get("hp", 0)) <= 0:
				_sound.play_sound("down", -4)
				break
	_state = snapshot.duplicate(true)
	for key in _visuals:
		var unit := _unit_state(str(key))
		var visual: Control = _visuals[key]
		visual.modulate.a = 0.38 if bool(unit.get("is_downed", false)) else 1.0
	if not _playing:
		_reset_actors()
	_queue_visual_redraw()

## Starts playback and returns immediately; impact and finished are the only
## sequencing contract. A cancelled entry never emits either signal afterwards.
func play_entry(entry: Dictionary, skill: Dictionary = {}) -> void:
	cancel()
	_entry = entry.duplicate(true)
	_skill = skill.duplicate(true)
	_profile = Motions.profile(_entry, _skill)
	_actor = str(_entry.get("actor", "boss"))
	if str(_profile["kind"]) == "normal" and str(_asset_ids.get(_actor, "")) in ["butler", "healer"]:
		_profile["advance"] = 0.0
	_targets = _entry_targets()
	_hero_finish = str(_entry.get("skill_id", "")) == "hero_burst_slash" and str(_asset_ids.get(_actor, "")) == "hero" and str(_profile["kind"]) == "fire_burst" and _targets.has("boss")
	if _hero_finish:
		_profile["advance"] = 0.0
	_butler_finish = str(_entry.get("skill_id", "")) == "butler_grand_ice" and str(_asset_ids.get(_actor, "")) == "butler" and str(_profile["kind"]) == "ice_grand" and _targets.has("boss")
	if _butler_finish:
		_profile["advance"] = 0.0
	_counters = _counter_targets()
	_guards.clear()
	_guard_offsets.clear()
	_counter_offsets.clear()
	if _actor == "boss" and not _entry.has("hits"):
		for key in _targets:
			var protected_id := int(_unit_state(key).get("protecting_ally_id", -1))
			if protected_id >= 0 and str(_entry.get("visual_original_target", key)) == str(protected_id) and str(protected_id) != key:
				_guards.append(key)
	for key in _guards:
		_guard_offsets[key] = _foot(str(_unit_state(key).get("protecting_ally_id", -1))) + Vector2(44, -4) - _foot(key)
	_motion_offset = Vector2(float(_profile["advance"]) * (-1.0 if _actor == "boss" else 1.0), 0)
	if str(_profile["kind"]) == "protect" and not _targets.is_empty():
		_motion_offset = _foot(_targets[0]) + Vector2(44, -4) - _foot(_actor)
	elif float(_profile["advance"]) > 0.0 and not _is_supportive() and not _targets.is_empty():
		var target_key := _targets[0]
		var target_foot := _foot(target_key) + Vector2(_guard_offsets.get(target_key, Vector2.ZERO))
		var range_offset := Vector2(_engagement_distance(), 0) if _actor == "boss" else Vector2(-_engagement_distance(), 0)
		_motion_offset = target_foot + range_offset - _foot(_actor)
	for key in _counters:
		_counter_offsets[key] = _foot("boss") + (_motion_offset if _actor == "boss" else Vector2.ZERO) - Vector2(maxf(95, _engagement_distance() - 20), 0) - _foot(key)
		_visuals[key].z_index = 4
	for key in _guards:
		_visuals[key].z_index = 4
	_playing = true
	_play_se("cast")
	_phase = "windup"
	_progress = 0.0
	_pose(_actor, int(_profile["windup_pose"]))
	_tween = create_tween()
	_tween.tween_method(_windup_progress, 0.0, 1.0, float(_profile["windup"]))
	_tween.tween_callback(_release)
	_tween.tween_method(_travel_progress, 0.0, 1.0, float(_profile["travel"]))
	_tween.tween_callback(_strike)
	if _hero_finish:
		# Keep the presenter on this entry until every finish layer has ended.
		_tween.tween_method(_hero_finish_progress, 0.0, 2.1, 2.1)
		_tween.tween_callback(_finish)
		return
	if _butler_finish:
		# Keep the presenter on this entry until every finish layer has ended.
		_tween.tween_method(_butler_finish_progress, 0.0, 2.4, 2.4)
		_tween.tween_callback(_finish)
		return
	_tween.tween_interval(0.10)
	if not _counters.is_empty():
		_tween.tween_method(_counter_progress, 0.0, 1.0, 0.20)
		_tween.tween_callback(_counter_impact)
		_tween.tween_interval(0.10)
	_tween.tween_method(_recovery_progress, 0.0, 1.0, float(_profile["recovery"]))
	_tween.tween_callback(_finish)

func cancel() -> void:
	_clear_hero_finish()
	_clear_butler_finish()
	if is_instance_valid(_sound): _sound.stop_all()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_playing = false
	_phase = "idle"
	_progress = 0.0
	_entry = {}
	_skill = {}
	_profile = {}
	_targets.clear()
	_counters.clear()
	_guards.clear()
	_reset_actors()
	_queue_visual_redraw()

func is_playing() -> bool:
	return _playing

func _queue_visual_redraw() -> void:
	queue_redraw()
	if is_instance_valid(_effects):
		_effects.queue_redraw()

func _windup_progress(value: float) -> void:
	_progress = value
	if _visuals.has(_actor):
		var visual: Control = _visuals[_actor]
		var direction := -1.0 if _actor == "boss" else 1.0
		visual.position = (Vector2(_homes[_actor]) + Vector2(-direction * 3.0 * sin(value * PI), 0)).round()
	_queue_visual_redraw()

func _release() -> void:
	_play_se("release")
	if not _guards.is_empty(): _sound.play_sound("cover_move", -5)
	_phase = "travel"
	_progress = 0.0
	_pose(_actor, int(_profile["impact_pose"]))
	for key in _guards:
		_pose(key, Motions.Pose.GUARD)

func _travel_progress(value: float) -> void:
	_progress = value
	if _visuals.has(_actor):
		var visual: Control = _visuals[_actor]
		visual.position = (Vector2(_homes[_actor]) + _motion_offset * value).round()
	for key in _guards:
		var guard_visual: Control = _visuals[key]
		guard_visual.position = (Vector2(_homes[key]) + Vector2(_guard_offsets.get(key, Vector2.ZERO)) * value).round()
	_queue_visual_redraw()
	if _hero_finish and is_instance_valid(_hero_fire):
		_hero_fire.visible = true
		_hero_fire.canvas_size = size
		_hero_fire.flight = value
		_hero_fire.launch_point = _foot(_actor) + Vector2(38, -42)
		_hero_fire.target_point = _foot("boss") + Vector2(0, -90)
		_hero_fire.queue_redraw()

func _hero_finish_progress(elapsed: float) -> void:
	_clear_hero_shake()
	_hero_fire.visible = true
	_hero_fire.age = elapsed
	_hero_fire.flight = -1.0
	_hero_fire.floor_point = _foot("boss")
	_hero_fire.canvas_size = size
	if elapsed >= 0.1 and elapsed < 0.35:
		_recovery_progress((elapsed - 0.1) / 0.25)
	elif elapsed >= 0.35:
		_pose(_actor, Motions.Pose.IDLE)
	_phase = "hero_finish"
	if elapsed < 1.42 or bool(_unit_state("boss").get("is_downed", false)):
		_pose("boss", Motions.Pose.HIT)
	else:
		_pose("boss", Motions.Pose.IDLE)
	if _hero_elapsed < 0.11 and elapsed >= 0.11: _sound.play_sound("fire_move", -4)
	if _hero_elapsed < 0.62 and elapsed >= 0.62: _sound.play_sound("fire_burst", 1)
	_hero_elapsed = elapsed
	if elapsed >= 0.74 and elapsed < 1.0:
		var force := 14.0 * (1.0 - (elapsed - 0.74) / 0.26)
		_hero_shake = (Vector2(sin(elapsed * 144), cos(elapsed * 186)) * force).snapped(Vector2(2, 2))
		for visual in _visuals.values(): visual.position += _hero_shake
		_hero_fire.position = _hero_shake
	_hero_fire.queue_redraw()

func _clear_hero_shake() -> void:
	if _hero_shake != Vector2.ZERO:
		for visual in _visuals.values():
			if is_instance_valid(visual): visual.position -= _hero_shake
	_hero_shake = Vector2.ZERO
	if is_instance_valid(_hero_fire): _hero_fire.position = Vector2.ZERO

func _clear_hero_finish() -> void:
	_clear_hero_shake()
	_hero_finish = false
	_hero_elapsed = -1.0
	if is_instance_valid(_hero_fire):
		_hero_fire.visible = false
		_hero_fire.age = -1.0
		_hero_fire.flight = -1.0

func _butler_finish_progress(elapsed: float) -> void:
	_clear_butler_shake()
	_butler_ice.visible = true
	_butler_ice.age = elapsed
	_butler_ice.floor_point = _foot("boss")
	_butler_ice.canvas_size = size
	if elapsed >= 0.1 and elapsed < 0.35:
		_recovery_progress((elapsed - 0.1) / 0.25)
	elif elapsed >= 0.35:
		_pose(_actor, Motions.Pose.IDLE)
	_phase = "butler_finish"
	if elapsed < 1.6 or bool(_unit_state("boss").get("is_downed", false)):
		_pose("boss", Motions.Pose.HIT)
	else:
		_pose("boss", Motions.Pose.IDLE)
	if _butler_elapsed < 0.72 and elapsed >= 0.72: _sound.play_sound("ice_burst", 1)
	_butler_elapsed = elapsed
	if elapsed >= 0.72 and elapsed < 0.98:
		var force := 16.0 * (1.0 - (elapsed - 0.72) / 0.26)
		_butler_shake = (Vector2(sin(elapsed * 144), cos(elapsed * 186)) * force).snapped(Vector2(2, 2))
		for visual in _visuals.values(): visual.position += _butler_shake
		_butler_ice.position = _butler_shake
	_butler_ice.queue_redraw()

func _clear_butler_shake() -> void:
	if _butler_shake != Vector2.ZERO:
		for visual in _visuals.values():
			if is_instance_valid(visual): visual.position -= _butler_shake
	_butler_shake = Vector2.ZERO
	if is_instance_valid(_butler_ice): _butler_ice.position = Vector2.ZERO

func _clear_butler_finish() -> void:
	_clear_butler_shake()
	_butler_finish = false
	_butler_elapsed = -1.0
	if is_instance_valid(_butler_ice):
		_butler_ice.visible = false
		_butler_ice.age = -1.0

func _strike() -> void:
	_play_se("impact")
	if not _guards.is_empty(): _sound.play_sound("guard_hit", -5)
	_phase = "impact"
	_progress = 0.0
	var supportive := _is_supportive()
	for key in _targets:
		if _counters.has(key):
			_pose(key, Motions.Pose.GUARD)
		elif not supportive and str(_profile["kind"]) != "failed":
			_pose(key, Motions.Pose.HIT)
			_flash(key)
	if _counters.is_empty():
		impact.emit(_entry)
	else:
		_phase = "counter"
	_queue_visual_redraw()

func _counter_progress(value: float) -> void:
	_progress = value
	if value > 0.38:
		for key in _counters:
			_pose(key, Motions.Pose.ULTIMATE_RELEASE)
			if _visuals.has(key):
				var counter_visual: Control = _visuals[key]
				counter_visual.position = (Vector2(_homes[key]) + Vector2(_counter_offsets.get(key, Vector2.ZERO)) * (value - 0.38) / 0.62).round()
	_queue_visual_redraw()

func _counter_impact() -> void:
	if not _counters.is_empty(): _sound.play_sound("wind_impact_heavy")
	_phase = "impact"
	_progress = 0.0
	_pose("boss", Motions.Pose.HIT)
	_flash("boss")
	impact.emit(_entry)
	_queue_visual_redraw()

func _recovery_progress(value: float) -> void:
	_phase = "recovery"
	_progress = value
	if _visuals.has(_actor):
		var visual: Control = _visuals[_actor]
		visual.position = (Vector2(_homes[_actor]) + _motion_offset * (1.0 - value)).round()
		if _counters.is_empty() or _actor != "boss":
			_pose(_actor, int(_profile["recover_pose"]))
	for key in _guards:
		var guard_visual: Control = _visuals[key]
		guard_visual.position = (Vector2(_homes[key]) + Vector2(_guard_offsets.get(key, Vector2.ZERO)) * (1.0 - value)).round()
	for key in _counters:
		if _visuals.has(key):
			var counter_visual: Control = _visuals[key]
			counter_visual.position = (Vector2(_homes[key]) + Vector2(_counter_offsets.get(key, Vector2.ZERO)) * (1.0 - value)).round()
	_queue_visual_redraw()

func _finish() -> void:
	_clear_hero_finish()
	_clear_butler_finish()
	_playing = false
	_phase = "idle"
	_progress = 0.0
	_targets.clear()
	_counters.clear()
	_guards.clear()
	_reset_actors()
	if _layout_pending:
		_layout_actors()
	_queue_visual_redraw()
	finished.emit()

func _reset_actors() -> void:
	for key in _visuals:
		var visual: Control = _visuals[key]
		visual.z_index = 1 if key == "boss" else 2
		if _homes.has(key):
			visual.position = _homes[key]
		var unit := _unit_state(str(key))
		var pose := Motions.Pose.IDLE
		if bool(unit.get("is_downed", false)):
			pose = Motions.Pose.HIT
		elif bool(unit.get("counter_pending", false)):
			pose = Motions.Pose.ULTIMATE_CHARGE
		elif bool(unit.get("is_defending", false)) or int(unit.get("protecting_ally_id", -1)) >= 0:
			pose = Motions.Pose.GUARD
		elif float(unit.get("next_attack_bonus_multiplier", 1.0)) > 1.0:
			pose = Motions.Pose.SUPPORT
		_pose(str(key), pose)

func _pose(key: String, index: int) -> void:
	if not _visuals.has(key):
		return
	_poses[key] = index
	var visual: Control = _visuals[key]
	if visual.has_method("set_pose"):
		visual.call("set_pose", index)

func _flash(key: String) -> void:
	if _visuals.has(key) and _visuals[key].has_method("impact_flash"):
		_visuals[key].call("impact_flash")

func _unit_state(key: String) -> Dictionary:
	if key == "boss":
		return _state.get("boss", {})
	var party: Dictionary = _state.get("party", {})
	return party.get(key, {})

func _entry_targets() -> Array[String]:
	var result: Array[String] = []
	for collection in ["hits", "healed", "recovered"]:
		if not _entry.has(collection):
			continue
		var values: Dictionary = _entry[collection]
		for key in values:
			var target_key := str(key)
			if collection == "hits" and values[key] is Dictionary:
				target_key = str(values[key].get("target", key))
			if _visuals.has(target_key) and not result.has(target_key):
				result.append(target_key)
		return result
	if _entry.has("target") or _entry.has("protecting"):
		var key := str(_entry.get("target", _entry.get("protecting", "")))
		if _visuals.has(key):
			result.append(key)
	elif str(_profile.get("kind", "")) in ["guard_boost", "iron_wall"]:
		for key in _party_keys:
			if not bool(_unit_state(key).get("is_downed", false)):
				result.append(key)
	elif _visuals.has(_actor):
		result.append(_actor)
	return result

func _counter_targets() -> Array[String]:
	var result: Array[String] = []
	if bool(_entry.get("counter", false)):
		result.append(str(_entry.get("target", "")))
	var hits: Dictionary = _entry.get("hits", {})
	for key in hits:
		var hit: Dictionary = hits[key]
		if bool(hit.get("counter", false)):
			result.append(str(hit.get("target", key)))
	return result

func _is_supportive() -> bool:
	return str(_profile.get("kind", "")) in ["fire_buff", "sp_single", "sp_all", "heal_single", "heal_all",
		"iai", "counter_stance", "protect", "guard_boost", "iron_wall", "defend", "boss_buff"]

func _foot(key: String) -> Vector2:
	if not _visuals.has(key):
		return size * 0.5
	var visual: Control = _visuals[key]
	var foot := Vector2.ZERO
	if visual.has_method("foot_position"):
		foot = visual.call("foot_position")
	return (visual.position + foot).round()

func _chest(key: String) -> Vector2:
	return _foot(key) - Vector2(0, Assets.display_height(str(_asset_ids.get(key, ""))) * 0.57)

func _engagement_distance() -> float:
	if _visuals.has("boss") and _visuals["boss"].has_method("visible_rect"):
		var bounds: Rect2 = _visuals["boss"].call("visible_rect")
		var pivot: Vector2 = _visuals["boss"].call("foot_position")
		return clampf(pivot.x - bounds.position.x + 45.0, 115.0, 210.0)
	return 115.0

## Read-only hooks for capture/regression tooling; not exposed in player UI.
func get_visual_audit() -> Dictionary:
	var actors: Dictionary = {}
	for key in _visuals:
		var visual: Control = _visuals[key]
		actors[key] = {"home": _homes.get(key, Vector2.ZERO), "position": visual.position,
			"scale": visual.scale, "feet": _foot(str(key)), "pose": int(_poses.get(key, 0))}
		if visual.has_method("visible_rect"):
			var bounds: Rect2 = visual.call("visible_rect")
			bounds.position += visual.position
			actors[key]["visible_rect"] = bounds
	return {"actors": actors, "effects_count": _targets.size() if _playing else 0,
		"playing": _playing, "phase": _phase, "stage_size": size}

func _draw() -> void:
	_canvas = self
	_draw_ground()
	_draw_state_marks()

func _draw_effects() -> void:
	_canvas = _effects
	if not _playing or _profile.is_empty():
		return
	if (_hero_finish or _butler_finish) and _phase != "windup":
		return
	var color := Motions.color_for(str(_profile["attribute"]))
	var kind := str(_profile["kind"])
	if kind == "failed":
		return
	var origin := _chest(_actor)
	if _phase == "travel":
		for key in _guards:
			var guard_point := _chest(key)
			_draw_shield(guard_point + Vector2(14, 0), Motions.color_for("GUARD"), 20.0)
			var protected_key := str(_unit_state(key).get("protecting_ally_id", -1))
			_canvas.draw_line(guard_point, _chest(protected_key), Color(0.8, 0.72, 0.48, 0.35), 2.0, false)
	if _phase == "windup":
		if float(_profile["advance"]) == 0.0 or int(_profile["windup_pose"]) >= 6:
			_draw_charge(origin, color, _progress, kind)
		return
	if _phase == "counter":
		for key in _counters:
			var source := _chest(key)
			_draw_shield(source, Motions.color_for("WIND"), 16.0)
			if _progress > 0.38:
				_draw_slash(source.lerp(_chest("boss"), (_progress - 0.38) / 0.62), Motions.color_for("WIND"), 20.0, 1.0)
		return
	for key in _targets:
		var target := _chest(key)
		var fade := 1.0 - _progress if _phase == "recovery" else 1.0
		var fx_color := Color(color, color.a * fade)
		if _is_supportive():
			_draw_support(origin, target, fx_color, kind)
		elif _phase == "travel":
			_draw_attack_travel(origin, target, fx_color, kind)
		else:
			_draw_hit(target, fx_color, kind)

func _draw_ground() -> void:
	var w := size.x
	var h := size.y
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("11171e"))
	_canvas.draw_rect(Rect2(0, h * 0.58, w, h * 0.42), Color("1a2025"))
	_canvas.draw_line(Vector2(0, h * 0.58), Vector2(w, h * 0.58), Color("2b3237"), 2.0, false)
	for index in range(9):
		var x := 16.0 + float(index) * (w / 9.0)
		var y := h - 22.0 - float(index % 3) * 16.0
		_canvas.draw_rect(Rect2(Vector2(x, y).round(), Vector2(18 + (index % 2) * 9, 2)), Color("303738"))
	for key in _visuals:
		var foot := _foot(str(key))
		_canvas.draw_rect(Rect2(foot - Vector2(22, 2), Vector2(44, 5)), Color(0.04, 0.06, 0.07, 0.68))
		if str(_asset_ids.get(key, "")).is_empty():
			# An unknown fixture appearance stays visibly unspecified.
			var center := foot - Vector2(0, 65)
			_canvas.draw_rect(Rect2(center - Vector2(30, 36), Vector2(60, 72)), Color("333b45"), false, 2.0)
			_canvas.draw_string(ThemeDB.fallback_font, center + Vector2(-16, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, 32, 24, Color("879098"))

func _draw_state_marks() -> void:
	for key in _visuals:
		var unit := _unit_state(str(key))
		if bool(unit.get("is_downed", false)):
			continue
		var point := _foot(str(key)) + Vector2(0, -4)
		if bool(unit.get("is_defending", false)):
			_draw_shield(point, Color("ccb779"), 6.0)
		elif bool(unit.get("counter_pending", false)):
			_draw_diamond(point, Color("aac68e"), 5.0)
		elif float(unit.get("next_attack_bonus_multiplier", 1.0)) > 1.0:
			_canvas.draw_line(point + Vector2(-10, 0), point + Vector2(10, 0), Color("aac68e"), 2.0, false)

func _draw_charge(center: Vector2, color: Color, progress: float, kind: String) -> void:
	var radius := lerpf(24.0, 9.0, progress)
	var count := 6 if kind in ["fire_burst", "ice_grand", "sp_all", "iron_wall"] else 4
	for index in range(count):
		var angle := float(index) * TAU / float(count)
		var point := (center + Vector2(cos(angle), sin(angle)) * radius).round()
		_canvas.draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), Color(color, 0.55 + progress * 0.45))
	if progress > 0.65:
		_draw_diamond(center, color, 4.0)

func _draw_attack_travel(origin: Vector2, target: Vector2, color: Color, kind: String) -> void:
	var point := origin.lerp(target, _progress).round()
	match kind:
		"ice_bolt":
			_draw_diamond(point, color, 10.0)
			_canvas.draw_line(point + Vector2(-18, 3), point, Color(color, 0.45), 3.0, false)
		"ice_storm", "ice_grand":
			var count := 5 if kind == "ice_grand" else 3
			for index in range(count):
				var offset := Vector2((index - (count - 1) * 0.5) * 16, -65.0 * (1.0 - _progress))
				_draw_diamond((target + offset).round(), color, 13.0 if kind == "ice_grand" else 8.0)
		"lightning":
			var points := PackedVector2Array([target + Vector2(0, -80), target + Vector2(-12, -45), target + Vector2(9, -45), target])
			_canvas.draw_polyline(points, color, 4.0, false)
		"fire_sweep", "wind_sweep":
			_draw_slash(point, color, 32.0, 1.0)
			_draw_slash(point + Vector2(-14, 12), Color(color, 0.5), 25.0, 1.0)
		"fire_burst":
			_draw_slash(point, color, 36.0, -1.0)
			_draw_diamond(point, Color("f5d590"), 10.0)
		"hammer":
			_draw_diamond(point, color, 8.0)
		"boss_all":
			_draw_attribute_projectile(origin.lerp(target, _progress), color, str(_profile["attribute"]), 16.0)
		"boss_single":
			_draw_attribute_projectile(point, color, str(_profile["attribute"]), 11.0)
		_:
			_draw_slash(point, color, 21.0 if kind == "wind_slash" else 17.0, -1.0)

func _draw_attribute_projectile(point: Vector2, color: Color, attribute: String, radius: float) -> void:
	match attribute:
		"ICE": _draw_diamond(point, color, radius)
		"LIGHTNING":
			_canvas.draw_polyline(PackedVector2Array([point + Vector2(-radius, -radius), point + Vector2(4, -3), point + Vector2(-3, 4), point + Vector2(radius, radius)]), color, 3.0, false)
		"WIND": _draw_slash(point, color, radius * 1.5, 1.0)
		"FIRE":
			_draw_diamond(point, color, radius)
			_draw_diamond(point + Vector2(0, -radius * 0.55), Color("f0c77f"), radius * 0.45)
		_:
			_draw_slash(point + Vector2(-4, 0), color, radius, -1.0)
			_draw_slash(point + Vector2(4, 0), color, radius, -1.0)

func _draw_hit(target: Vector2, color: Color, kind: String) -> void:
	var radius := (32.0 if kind in ["fire_burst", "ice_grand", "hammer"] else 20.0) * (0.8 + _progress * 0.5)
	if kind == "hammer":
		_draw_octagon(target + Vector2(0, 20), color, radius)
		for index in range(4):
			var delta := Vector2(-24 + index * 16, -18 - (index % 2) * 9) * _progress
			_canvas.draw_rect(Rect2((target + delta).round(), Vector2(5, 5)), color)
	elif kind in ["ice_bolt", "ice_storm", "ice_grand"]:
		for index in range(4):
			var angle := float(index) * PI * 0.5
			_draw_diamond(target + Vector2(cos(angle), sin(angle)) * radius, color, 5.0)
	else:
		_draw_slash(target, color, radius, -1.0)
		_draw_slash(target, Color(color, color.a * 0.65), radius * 0.7, 1.0)

func _draw_support(origin: Vector2, target: Vector2, color: Color, kind: String) -> void:
	var progress := _progress
	if _phase == "travel" and kind in ["sp_single", "sp_all"]:
		var point := origin.lerp(target, progress) + Vector2(0, -sin(progress * PI) * 22.0)
		_draw_diamond(point.round(), color, 7.0)
		return
	match kind:
		"heal_single", "heal_all":
			for index in range(3):
				var point := target + Vector2(-14 + index * 14, 16.0 - progress * 29.0 - (index % 2) * 8.0)
				_draw_cross(point.round(), color, 5.0)
		"sp_single", "sp_all":
			_draw_diamond(target + Vector2(0, -progress * 16), color, 13.0)
			_draw_octagon(target, Color(color, color.a * 0.5), 23.0)
		"protect":
			_draw_shield(target, color, 22.0)
			_canvas.draw_line(origin, target, Color(color, color.a * 0.45), 2.0, false)
		"defend":
			_draw_shield(target, color, 19.0)
		"guard_boost":
			_canvas.draw_line(target + Vector2(-22, 28), target + Vector2(22, 28), color, 4.0, false)
			for side in [-1, 1]:
				_canvas.draw_line(target + Vector2(side * 22, 28), target + Vector2(side * 22, 12), color, 4.0, false)
			_draw_shield(target, color, 13.0)
		"iron_wall":
			for column in range(3):
				var block := Rect2(target + Vector2(-28 + column * 20, -25), Vector2(17, 54))
				_canvas.draw_rect(block, Color(color, color.a * 0.12))
				_canvas.draw_rect(block, color, false, 2.0)
		"iai", "counter_stance":
			_draw_slash(target + Vector2(0, 8), color, 20.0, 0.0)
			_draw_diamond(target + Vector2(17, 8), color, 4.0)
		"fire_buff":
			for index in range(4):
				_draw_diamond(target + Vector2(-21 + index * 14, 21 - progress * 30 - (index % 2) * 10), color, 6.0)
		_:
			_draw_octagon(target, color, 21.0)
			_draw_diamond(target + Vector2(0, -26), color, 6.0)

func _draw_cross(point: Vector2, color: Color, radius: float) -> void:
	_canvas.draw_rect(Rect2(point - Vector2(radius, 2), Vector2(radius * 2, 4)), color)
	_canvas.draw_rect(Rect2(point - Vector2(2, radius), Vector2(4, radius * 2)), color)

func _draw_diamond(point: Vector2, color: Color, radius: float) -> void:
	var p := point.round()
	_canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius), p + Vector2(-radius, 0)]), color)

func _draw_slash(point: Vector2, color: Color, radius: float, slope: float) -> void:
	var p := point.round()
	var points := PackedVector2Array([p + Vector2(-radius, -radius * slope * 0.6), p + Vector2(-radius * 0.5, -radius * slope * 0.4), p, p + Vector2(radius * 0.5, radius * slope * 0.4), p + Vector2(radius, radius * slope * 0.6)])
	_canvas.draw_polyline(points, color, 4.0, false)

func _draw_octagon(point: Vector2, color: Color, radius: float) -> void:
	var points := PackedVector2Array()
	for index in range(9):
		var angle := float(index) * TAU / 8.0
		points.append((point + Vector2(cos(angle), sin(angle)) * radius).round())
	_canvas.draw_polyline(points, color, 2.0, false)

func _draw_shield(point: Vector2, color: Color, radius: float) -> void:
	var p := point.round()
	var points := PackedVector2Array([p + Vector2(-radius * 0.65, -radius), p + Vector2(radius * 0.65, -radius), p + Vector2(radius * 0.65, radius * 0.25), p + Vector2(0, radius), p + Vector2(-radius * 0.65, radius * 0.25), p + Vector2(-radius * 0.65, -radius)])
	_canvas.draw_polyline(points, color, 3.0, false)

func _play_se(phase: String) -> void:
	if not is_instance_valid(_sound): return
	var key: String = Sound.event_key(_entry, _profile, str(_asset_ids.get(_actor, "")), phase)
	if not key.is_empty(): _sound.play_sound(key, -4 if phase == "cast" else 0)
