class_name UDArtLibrary
extends RefCounted
## Sprite lookup by naming convention: drop a PNG into assets/art/ and
## it replaces the placeholder rectangle — no code changes needed (§6).
##
## Recognized names:
##   terrain_soil.png / terrain_rock.png / terrain_wetrock.png /
##   terrain_ruinstone.png / terrain_air.png
##   minion_0.png .. minion_5.png  (variant = minion id % 6)
##   room_<room_id>.png  (e.g. room_dorm.png)
##   depot.png
##
## After adding files run the editor once or `godot --headless --import`.

const ART_DIR: String = "res://assets/art"
const MINION_VARIANTS: int = 6

var _textures: Dictionary = {}  # key -> Texture2D


static func load_default(room_ids: Array[String]) -> UDArtLibrary:
	var lib := UDArtLibrary.new()
	var keys: Array[String] = [
		"terrain_soil", "terrain_rock", "terrain_wetrock",
		"terrain_ruinstone", "terrain_air", "depot",
	]
	for i in MINION_VARIANTS:
		keys.append("minion_%d" % i)
	for room_id in room_ids:
		keys.append("room_%s" % room_id)
	for key in keys:
		var path := "%s/%s.png" % [ART_DIR, key]
		if ResourceLoader.exists(path, "Texture2D"):
			lib._textures[key] = load(path)
	return lib


func has_art(key: String) -> bool:
	return _textures.has(key)


func texture(key: String) -> Texture2D:
	return _textures.get(key, null)


func terrain_key(terrain: UD.Terrain) -> String:
	match terrain:
		UD.Terrain.SOIL:
			return "terrain_soil"
		UD.Terrain.ROCK:
			return "terrain_rock"
		UD.Terrain.WETROCK:
			return "terrain_wetrock"
		UD.Terrain.RUINSTONE:
			return "terrain_ruinstone"
		_:
			return "terrain_air"


func minion_key(minion_id: int) -> String:
	return "minion_%d" % (minion_id % MINION_VARIANTS)
