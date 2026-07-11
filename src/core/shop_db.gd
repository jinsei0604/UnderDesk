class_name UDShopDB
extends RefCounted
## Shop goods from data/shop/*.json (§7.3): the lineup is data, so it
## can be redesigned without touching code.

var _goods: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDShopDB:
	var db := UDShopDB.new()
	for def: Variant in defs:
		var good := def as Dictionary
		db._goods[good["id"]] = good
	return db


static func load_from_dir(dir_path: String) -> UDShopDB:
	return UDShopDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_good(id: String) -> bool:
	return _goods.has(id)


func get_good(id: String) -> Dictionary:
	assert(_goods.has(id))
	return _goods[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _goods.keys():
		ids.append(id)
	ids.sort()
	return ids
