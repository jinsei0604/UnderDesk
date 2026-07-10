class_name UDDataLoader
extends RefCounted
## Loads JSON content files from a directory, sorted by filename for
## deterministic ordering.


static func load_json_dir(dir_path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("UDDataLoader: cannot open %s" % dir_path)
		return result
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		var text := FileAccess.get_file_as_string(dir_path.path_join(file_name))
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null:
			push_error("UDDataLoader: invalid JSON in %s" % file_name)
			continue
		result.append(parsed)
	return result
