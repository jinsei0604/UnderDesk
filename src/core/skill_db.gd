class_name UDSkillDB
extends RefCounted
## Skill definitions from data/skills/*.json (§7.3), same flat-Dictionary-
## per-file convention as UDItemDB. A party unit's known skills are listed
## by id in its companion definition (data/companions/*.json "skills").

var _skills: Dictionary = {}  # id -> def


static func from_dicts(defs: Array) -> UDSkillDB:
	var db := UDSkillDB.new()
	for def: Variant in defs:
		var skill := def as Dictionary
		db._skills[skill["id"]] = skill
	return db


static func load_from_dir(dir_path: String) -> UDSkillDB:
	return UDSkillDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func has_skill(id: String) -> bool:
	return _skills.has(id)


func get_skill(id: String) -> Dictionary:
	assert(_skills.has(id))
	return _skills[id]


func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in _skills.keys():
		ids.append(id)
	ids.sort()
	return ids
