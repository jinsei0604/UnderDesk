class_name UDSaveManager
extends RefCounted
## JSON save with generation backups (§7.2: resident apps meet force-kills).

const SAVE_PATH: String = "user://save.json"


static func save_game(sim: UDSim) -> void:
	_rotate_backups()
	var payload := {
		"saved_unix_time": int(Time.get_unix_time_from_system()),
		"sim": sim.to_dict(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("UDSaveManager: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload))
	file.close()


## Returns the saved payload, or {} when no save exists or it is corrupt.
static func load_game() -> Dictionary:
	for path in _candidate_paths():
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary and (parsed as Dictionary).has("sim"):
			return parsed
		push_warning("UDSaveManager: corrupt save %s, trying older backup" % path)
	return {}


static func _candidate_paths() -> Array[String]:
	var paths: Array[String] = [SAVE_PATH]
	for generation in range(1, UD.SAVE_BACKUP_GENERATIONS + 1):
		paths.append(_backup_path(generation))
	return paths


static func _backup_path(generation: int) -> String:
	return "user://save.bak%d.json" % generation


static func _rotate_backups() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for generation in range(UD.SAVE_BACKUP_GENERATIONS, 1, -1):
		var older := _backup_path(generation)
		var newer := _backup_path(generation - 1)
		if dir.file_exists(newer.get_file()):
			dir.rename(newer.get_file(), older.get_file())
	if dir.file_exists(SAVE_PATH.get_file()):
		dir.rename(SAVE_PATH.get_file(), _backup_path(1).get_file())
