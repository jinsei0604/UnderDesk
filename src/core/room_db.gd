class_name UDRoomDB
extends RefCounted
## Room definitions loaded from data/rooms/*.json (§7.3: data-driven).

var _rooms: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDRoomDB:
	var db := UDRoomDB.new()
	for def: Variant in defs:
		var room := def as Dictionary
		db._rooms[room["id"]] = room
	return db


static func load_from_dir(dir_path: String) -> UDRoomDB:
	return UDRoomDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_room(id: String) -> bool:
	return _rooms.has(id)


func get_room(id: String) -> Dictionary:
	assert(_rooms.has(id))
	return _rooms[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _rooms.keys():
		ids.append(id)
	ids.sort()
	return ids
