class_name UDLocale
extends RefCounted
## Minimal key->text lookup from locale/<lang>.csv ("key,text" with quoting).
## Kept hand-rolled for now so headless tests need no import step.

var _texts: Dictionary = {}


static func load_locale(lang: String) -> UDLocale:
	var locale := UDLocale.new()
	var path := "res://locale/%s.csv" % lang
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("UDLocale: cannot open %s" % path)
		return locale
	var header := true
	while not file.eof_reached():
		var row := file.get_csv_line()
		if header:
			header = false
			continue
		if row.size() >= 2 and row[0] != "":
			locale._texts[row[0]] = row[1]
	file.close()
	return locale


func text(key: String) -> String:
	return _texts.get(key, key)
