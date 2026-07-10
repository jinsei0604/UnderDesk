class_name UDStrataDB
extends RefCounted
## Stratum definitions loaded from data/strata/*.json (§7.3: data-driven).
## Depths below the deepest defined stratum reuse the deepest one.

var _strata: Array[Dictionary] = []


static func from_dicts(defs: Array) -> UDStrataDB:
	var db := UDStrataDB.new()
	for def: Variant in defs:
		db._strata.append(def as Dictionary)
	db._strata.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["depth_from"]) < int(b["depth_from"])
	)
	return db


static func load_from_dir(dir_path: String) -> UDStrataDB:
	return UDStrataDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func stratum_for_depth(y: int) -> Dictionary:
	assert(not _strata.is_empty())
	for stratum in _strata:
		if y >= int(stratum["depth_from"]) and y <= int(stratum["depth_to"]):
			return stratum
	return _strata[_strata.size() - 1]


func terrain_for_depth(y: int) -> UD.Terrain:
	if y == 0:
		return UD.Terrain.AIR
	var name: String = stratum_for_depth(y)["terrain"]
	return UD.TERRAIN_BY_NAME[name] as UD.Terrain


func hardness_for_depth(y: int) -> int:
	return int(stratum_for_depth(y)["hardness"])


func yield_for_depth(y: int) -> String:
	return stratum_for_depth(y)["yield"]
