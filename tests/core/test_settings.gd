extends GutTest


func test_defaults() -> void:
	var settings := UDSettings.new()
	assert_eq(settings.height_index, UD.DEFAULT_WINDOW_HEIGHT_INDEX)
	assert_true(settings.resident_mode)
	assert_eq(settings.locale_code, "ja")


func test_dict_roundtrip() -> void:
	var settings := UDSettings.new()
	settings.height_index = 2
	settings.resident_mode = false
	settings.locale_code = "en"
	var restored := UDSettings.new()
	restored.apply_dict(JSON.parse_string(JSON.stringify(settings.to_dict())))
	assert_eq(restored.height_index, 2)
	assert_false(restored.resident_mode)
	assert_eq(restored.locale_code, "en")


func test_invalid_values_clamped() -> void:
	var settings := UDSettings.new()
	settings.apply_dict({"height_index": 99, "locale_code": "xx"})
	assert_eq(settings.height_index, UD.WINDOW_HEIGHTS.size() - 1, "index clamped")
	assert_eq(settings.locale_code, "ja", "unknown locale ignored")
