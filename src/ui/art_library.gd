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
## Frame animation: add <key>_f2.png, <key>_f3.png, ... and the sprite
## cycles through them automatically (the base file is frame 1).
##
## After adding files run the editor once or `godot --headless --import`.

const ART_DIR: String = "res://assets/art"
const MINION_VARIANTS: int = 6

var _frames: Dictionary = {}  # key -> Array[Texture2D]


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
		var frames: Array = []
		var base_path := "%s/%s.png" % [ART_DIR, key]
		if ResourceLoader.exists(base_path, "Texture2D"):
			frames.append(load(base_path))
			var frame_index := 2
			while true:
				var frame_path := "%s/%s_f%d.png" % [ART_DIR, key, frame_index]
				if not ResourceLoader.exists(frame_path, "Texture2D"):
					break
				frames.append(load(frame_path))
				frame_index += 1
		if not frames.is_empty():
			lib._frames[key] = frames
	return lib


func has_art(key: String) -> bool:
	return _frames.has(key)


func texture(key: String) -> Texture2D:
	if not _frames.has(key):
		return null
	return (_frames[key] as Array)[0]


func frame_count(key: String) -> int:
	if not _frames.has(key):
		return 0
	return (_frames[key] as Array).size()


## Returns the frame for an arbitrary animation counter (wraps around).
func frame(key: String, index: int) -> Texture2D:
	if not _frames.has(key):
		return null
	var frames := _frames[key] as Array
	return frames[posmod(index, frames.size())]


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
