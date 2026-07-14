class_name UDAchievements
extends RefCounted
## Achievement tracker (§5.3: progress metrics feed platform achievements).
## Definitions are data (data/achievements/*.json); unlocks persist to
## user://. The platform backend is notified exactly once per unlock.

const SAVE_PATH: String = "user://achievements.json"

## Metrics an achievement trigger can watch (design §5.3, CLAUDE.md).
const TRIGGER_TYPES: Array[String] = ["docs", "items", "depth"]

var defs: Array = []  # [{ id, name_key, desc_key, trigger: {type, count} }]
var unlocked: Array[String] = []
var platform: UDPlatform


static func load_default(p_platform: UDPlatform) -> UDAchievements:
	var tracker := UDAchievements.from_defs(
		UDDataLoader.load_json_dir("res://data/achievements"), p_platform
	)
	if FileAccess.file_exists(SAVE_PATH):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(SAVE_PATH)
		)
		if parsed is Dictionary:
			tracker.apply_dict(parsed)
	return tracker


static func from_defs(p_defs: Array, p_platform: UDPlatform) -> UDAchievements:
	var tracker := UDAchievements.new()
	tracker.defs = p_defs
	tracker.platform = p_platform
	return tracker


## Checks every definition against the sim and unlocks what qualifies.
## Returns the ids newly unlocked this call. Pure in-memory: the caller
## saves when the result is non-empty (keeps tests off the disk).
func evaluate(sim: UDSim) -> Array[String]:
	var fresh: Array[String] = []
	for def: Variant in defs:
		var ach := def as Dictionary
		var id := str(ach["id"])
		if unlocked.has(id):
			continue
		var trigger := ach["trigger"] as Dictionary
		if _metric(sim, str(trigger["type"])) >= int(trigger["count"]):
			unlocked.append(id)
			fresh.append(id)
			platform.notify_unlock(id)
	return fresh


func _metric(sim: UDSim, type: String) -> int:
	match type:
		"docs":
			return sim.discovered_documents.size()
		"items":
			return sim.distinct_items()
		"depth":
			return sim.frontier_distance()
	return 0


func to_dict() -> Dictionary:
	return {"unlocked": unlocked.duplicate()}


func apply_dict(d: Dictionary) -> void:
	for id: Variant in d.get("unlocked", []) as Array:
		if not unlocked.has(str(id)):
			unlocked.append(str(id))


func save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("UDAchievements: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(to_dict()))
	file.close()
