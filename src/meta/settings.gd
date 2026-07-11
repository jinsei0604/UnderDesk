class_name UDSettings
extends RefCounted
## User preferences persisted to user://settings.json.

const SETTINGS_PATH: String = "user://settings.json"

var height_index: int = UD.DEFAULT_WINDOW_HEIGHT_INDEX
var resident_mode: bool = true
var locale_code: String = "ja"
## Flips once the first-run hints have finished; they never show again.
var tutorial_seen: bool = false


static func load_settings() -> UDSettings:
	var settings := UDSettings.new()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return settings
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if parsed is Dictionary:
		settings.apply_dict(parsed)
	return settings


func save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("UDSettings: cannot write %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(to_dict()))
	file.close()


func to_dict() -> Dictionary:
	return {
		"height_index": height_index,
		"resident_mode": resident_mode,
		"locale_code": locale_code,
		"tutorial_seen": tutorial_seen,
	}


func apply_dict(d: Dictionary) -> void:
	height_index = clampi(int(d.get("height_index", height_index)), 0, UD.WINDOW_HEIGHTS.size() - 1)
	resident_mode = bool(d.get("resident_mode", resident_mode))
	var lang := str(d.get("locale_code", locale_code))
	if lang in UD.SUPPORTED_LOCALES:
		locale_code = lang
	tutorial_seen = bool(d.get("tutorial_seen", tutorial_seen))
