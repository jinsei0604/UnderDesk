extends RefCounted
## Approved v8 full-body drawings and timestamps. Never uses combat state or RNG.
const ROOT := "res://assets_bossmaker/battle/gentleman/"
static var _data: Dictionary = {}
static var _textures: Dictionary = {}

static func clip(kind: String) -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"motion.json"))
	return _data["clips"][kind]

static func frame_index(data: Dictionary, t: float) -> int:
	return clampi(int(t*60.0),0,data.frames.size()-1)

static func frame(kind: String, t: float) -> String:
	var data := clip(kind)
	return str(data.frames[frame_index(data,t)])

static func texture(name: String) -> Texture2D:
	if not _textures.has(name): _textures[name] = load(ROOT+"motion_frames/"+name+".png")
	return _textures[name] as Texture2D

static func muzzle(kind: String, t: float, hand: String) -> Vector2:
	var data := clip(kind)
	if data.has("muzzles"):
		var points: Dictionary = data.muzzles[frame_index(data,t)]
		if points.has(hand): return Vector2(float(points[hand][0]),float(points[hand][1]))
	return Vector2(-44,-72) if kind=="single" else Vector2(-34,-59)
