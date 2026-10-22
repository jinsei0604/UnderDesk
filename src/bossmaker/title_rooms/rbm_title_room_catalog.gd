extends RefCounted
## Register only approved, implemented rooms. Selection is cached for this process;
## returning home or recreating the launcher must not draw another boss.
const ROOMS := {
	"musha": preload("res://src/bossmaker/title_rooms/musha_room.tscn"),
	"gentleman": preload("res://src/bossmaker/title_rooms/gentleman_room.tscn"),
	"astronaut": preload("res://src/bossmaker/title_rooms/astronaut_room.tscn"),
}
static var _session_room_id: String = ""

static func session_room_id() -> String:
	if _session_room_id.is_empty():
		var ids: Array = ROOMS.keys()
		var random := RandomNumberGenerator.new()
		random.randomize() # Independent of battle RNG and saved gameplay state.
		_session_room_id = str(ids[random.randi_range(0, ids.size() - 1)])
	return _session_room_id

static func create_session_room() -> Node2D:
	return ROOMS[session_room_id()].instantiate() as Node2D
