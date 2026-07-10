class_name UDDocumentDB
extends RefCounted
## Document metadata from data/documents/*.json. Body text lives in
## locale CSVs, keeping scenario writing separate from code (§5.3, §7.3).

var _docs: Dictionary = {}  # id -> { id, title_key, body_key }


static func from_dicts(defs: Array) -> UDDocumentDB:
	var db := UDDocumentDB.new()
	for def: Variant in defs:
		var doc := def as Dictionary
		db._docs[doc["id"]] = doc
	return db


static func load_from_dir(dir_path: String) -> UDDocumentDB:
	return UDDocumentDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_doc(id: String) -> bool:
	return _docs.has(id)


func get_doc(id: String) -> Dictionary:
	assert(_docs.has(id))
	return _docs[id]


func count() -> int:
	return _docs.size()
