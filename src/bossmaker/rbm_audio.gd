extends Node
## Presentation-only audio. No battle references, RNG, timers, or saved state.
const Catalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const MAX_VOICES := 8
var muted := false
var history: Array[String] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _cursor_time := -1000

static func for_owner(node: Node) -> Node:
	var existing := node.get_node_or_null("RBMAudio")
	if existing != null:
		return existing
	var audio: Node = load("res://src/bossmaker/rbm_audio.gd").new()
	audio.name = "RBMAudio"
	node.add_child(audio)
	return audio

static func cue(node: Node, key: String) -> void:
	for_owner(node).play_sound(key)

func _ready() -> void:
	for i in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	if get_parent() is CanvasItem:
		get_parent().visibility_changed.connect(func():
			if not get_parent().is_visible_in_tree(): stop_all()
		)

func play_sound(key: String, gain_db: float = 0.0) -> void:
	if not Catalog.FILES.has(key):
		return
	history.append(key)
	if history.size() > 64: history.pop_front()
	if muted or not is_inside_tree() or _players.is_empty(): return
	if not _cache.has(key): _cache[key] = load(Catalog.FILES[key])
	var player := _players[_next]
	_next = (_next + 1) % MAX_VOICES
	player.stop()
	player.stream = _cache[key]
	player.volume_db = -9.0 + gain_db
	player.play()

func stop_all() -> void:
	for player in _players: player.stop()

static func attribute_key(attribute: String, part: String) -> String:
	return attribute.to_lower() + "_" + part

## Return at most one principal cue per phase, including AoE.
static func event_key(entry: Dictionary, profile: Dictionary, actor_asset: String, phase: String) -> String:
	var kind := str(profile.get("kind", "failed"))
	if kind == "failed" or bool(entry.get("failed", false)): return ""
	var attr := str(profile.get("attribute", "NEUTRAL"))
	var supports := {"heal_single":"heal_hp", "heal_all":"heal_hp", "sp_single":"heal_sp", "sp_all":"heal_sp", "fire_buff":"buff_atk", "boss_buff":"buff_atk", "iai":"guard_set", "counter_stance":"guard_set", "protect":"guard_set", "guard_boost":"guard_set", "iron_wall":"guard_set", "defend":"guard_set"}
	if supports.has(kind):
		if phase == "impact": return supports[kind]
		if phase == "cast" and kind in ["fire_buff", "iai", "counter_stance"]: return attribute_key(attr, "cast")
		if phase == "release" and kind == "protect": return "cover_move"
		return ""
	if kind in ["normal", "hammer"] or attr == "NEUTRAL":
		if phase == "release":
			if str(entry.get("actor", "")) == "boss": return "boss_move_heavy"
			if actor_asset == "healer": return "neutral_staff_tap"
			return "neutral_blunt_swing" if actor_asset in ["tank", "butler"] else "neutral_sword_swing"
		if phase == "impact":
			if str(entry.get("actor", "")) == "boss": return "boss_impact_mass"
			return "neutral_impact_heavy" if actor_asset == "tank" else "neutral_impact_light"
		return ""
	if phase == "cast": return attribute_key(attr, "cast")
	if phase == "release": return attribute_key(attr, "swing" if kind in ["fire_slash", "fire_sweep", "fire_burst", "wind_slash", "wind_sweep"] else "move")
	if phase == "impact":
		var heavy := kind in ["fire_burst", "ice_grand", "boss_single", "boss_all", "fire_sweep", "ice_storm", "wind_sweep"]
		return attribute_key(attr, "impact_heavy" if heavy else "impact_light")
	return ""

func bind_ui(root: Node) -> void:
	for child in root.get_children(): bind_ui(child)
	if not root.has_meta("rbm_audio_bound") and root is BaseButton:
		root.set_meta("rbm_audio_bound", true)
		root.mouse_entered.connect(_hover.bind(root))
		root.focus_entered.connect(_hover.bind(root))
		root.button_down.connect(_button.bind(root))
		if root is OptionButton:
			root.item_selected.connect(func(_i): play_sound("ui_tab"))

func _hover(button: BaseButton) -> void:
	if not button.is_visible_in_tree() or button.disabled: return
	var now := Time.get_ticks_msec()
	if now - _cursor_time < 80: return
	_cursor_time = now
	play_sound("ui_cursor")

func _button(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree(): return
	var label: String = button.text if button is Button else str(button.name)
	play_sound("ui_cancel" if label.contains("戻") or label.contains("キャンセル") or label.contains("終了") else "ui_confirm")


