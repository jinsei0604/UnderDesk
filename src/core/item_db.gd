class_name UDItemDB
extends RefCounted
## Treasure chest item definitions from data/items/*.json (§7.3).
## Flavor collectibles for now; the shop/relic systems build on these.

var _items: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDItemDB:
	var db := UDItemDB.new()
	for def: Variant in defs:
		var item := def as Dictionary
		db._items[item["id"]] = item
	return db


static func load_from_dir(dir_path: String) -> UDItemDB:
	return UDItemDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> Dictionary:
	assert(_items.has(id))
	return _items[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _items.keys():
		ids.append(id)
	ids.sort()
	return ids
