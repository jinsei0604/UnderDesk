extends AspectRatioContainer
## UI-only playback of recordings of the existing production battle stage.
const BOSSES := ["slime", "musha", "astronaut", "ghost", "dragon"]
const AWAKENED := ["musha", "astronaut"]
const ROOT := "res://assets_bossmaker/video/boss_previews/"
var player: VideoStreamPlayer
var current_path := ""
var user_paused := false
## Open the two decoders on separate frames, after the profile's image update.
var start_delay := 1
var _pending_frames := 0

static func path_for(appearance: String, awakened: bool, kind: String) -> String:
	var boss := appearance.trim_prefix("appearance_")
	if not boss in BOSSES or not kind in ["single", "all"]:
		return ""
	if awakened and not boss in AWAKENED:
		return ""
	return ROOT + boss + ("_awakened" if awakened else "") + "_" + kind + ".ogv"

func _ready() -> void:
	ratio = 16.0 / 9.0
	stretch_mode = AspectRatioContainer.STRETCH_FIT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	player = VideoStreamPlayer.new()
	player.name = "Video"
	player.expand = true
	player.volume = 0.0
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.loop = true
	add_child(player)
	visibility_changed.connect(_sync_playback)
	set_process(false)

func configure(appearance: String, awakened: bool, kind: String) -> bool:
	var path := path_for(appearance, awakened, kind)
	if not path.is_empty() and not ResourceLoader.exists(path): path = ""
	if path != current_path:
		player.stop()
		player.stream = null
		current_path = path
		_pending_frames = start_delay if not path.is_empty() else 0
	visible = not path.is_empty()
	_sync_playback()
	return visible

func set_paused(value: bool) -> void:
	user_paused = value
	_sync_playback()

func _sync_playback() -> void:
	if not is_instance_valid(player): return
	player.paused = user_paused
	set_process(is_visible_in_tree() and _pending_frames > 0)
	if not is_visible_in_tree():
		player.stop()
		return
	if player.stream != null:
		if not player.is_playing(): player.play()
		player.paused = user_paused

func _process(_delta: float) -> void:
	_pending_frames -= 1
	if _pending_frames > 0: return
	set_process(false)
	if current_path.is_empty() or not is_visible_in_tree(): return
	player.stream = load(current_path) as VideoStream
	_sync_playback()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()
		player.stream = null
