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


## Narrative chapter (0..4, matching the delivered chapter_bg_<n>_* art
## sets) a stage index belongs to. Optional field, defaults to 0 so the
## existing shallow/gate10/deeper bands (all chapter-0 content) need no
## edits.
func chapter_for_index(i: int) -> int:
	return int(stage_for_index(i).get("chapter", 0))


## The stage_from of the earliest band sharing this chapter, so the
## seg1/seg2/normal backdrop cycle runs continuously across a whole
## chapter even when it is split into several bands (gate stages,
## trash-pool changes) rather than resetting at each band boundary.
func chapter_origin_index(i: int) -> int:
	var chapter := chapter_for_index(i)
	for band in _bands:
		if int(band.get("chapter", 0)) == chapter:
			return int(band["stage_from"])
	return 1


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
