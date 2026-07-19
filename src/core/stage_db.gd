class_name UDStageDB
extends RefCounted
## Stage-band definitions from data/stages/*.json (§7.3), banded by
## stage_from/stage_to exactly like the old UDStrataDB was banded by
## depth_from/depth_to. Stages past the last defined band reuse the
## deepest one. A band with a non-empty "boss_id" is a boss gate: idle
## auto-battle halts there (see UDSim._auto_battle()).

var _bands: Array[Dictionary] = []


static func from_dicts(defs: Array) -> UDStageDB:
	var db := UDStageDB.new()
	for def: Variant in defs:
		db._bands.append(def as Dictionary)
	db._bands.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["stage_from"]) < int(b["stage_from"])
	)
	return db


static func load_from_dir(dir_path: String) -> UDStageDB:
	return UDStageDB.from_dicts(UDDataLoader.load_json_dir(dir_path))


func stage_for_index(i: int) -> Dictionary:
	assert(not _bands.is_empty())
	for band in _bands:
		if i >= int(band["stage_from"]) and i <= int(band["stage_to"]):
			return band
	return _bands[_bands.size() - 1]


func is_boss_stage(i: int) -> bool:
	return str(stage_for_index(i).get("boss_id", "")) != ""


## The most recent gate's boss at or below stage i ("" when the party
## has not reached any gate yet). Lets a cleared gate be re-challenged
## (sim.start_boss_fight) instead of the fight disappearing forever
## once won.
func last_boss_id_at_or_below(i: int) -> String:
	var found := ""
	for band in _bands:
		if int(band["stage_from"]) > i:
			break
		var boss_id := str(band.get("boss_id", ""))
		if boss_id != "":
			found = boss_id
	return found
