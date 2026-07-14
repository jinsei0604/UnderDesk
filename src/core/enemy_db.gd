class_name UDEnemyDB
extends RefCounted
## Enemy definitions from data/enemies/*.json (§7.3: data-driven, same
## flat-Dictionary-per-file convention as UDItemDB).

var _enemies: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDEnemyDB:
	var db := UDEnemyDB.new()
	for def: Variant in defs:
		var enemy := def as Dictionary
		db._enemies[enemy["id"]] = enemy
	return db


static func load_from_dir(dir_path: String) -> UDEnemyDB:
	return UDEnemyDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_enemy(id: String) -> bool:
	return _enemies.has(id)


func get_enemy(id: String) -> Dictionary:
	assert(_enemies.has(id))
	return _enemies[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _enemies.keys():
		ids.append(id)
	ids.sort()
	return ids


func is_boss(id: String) -> bool:
	return bool(get_enemy(id).get("is_boss", false))
