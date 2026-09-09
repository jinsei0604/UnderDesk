extends GutTest

## RBMSupabaseConfigのテストと同じ形——実ファイルには触れず、テスト専用
## パスへ差し替えて検証する。

var _tmp_path := "user://test_steam_dev_appid.local.txt"

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_path)
	_delete_tmp_file()

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	_delete_tmp_file()
	OS.set_environment("STEAM_APP_ID", "")

func _delete_tmp_file() -> void:
	if FileAccess.file_exists(_tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_path))

func _write_tmp_file(text: String) -> void:
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func test_unset_everywhere_resolves_to_official_app_id_and_not_configured() -> void:
	assert_eq(RBMSteamConfig.app_id(), RBMSteamConfig.OFFICIAL_APP_ID)
	assert_false(RBMSteamConfig.is_configured())

func test_official_app_id_constant_is_not_480() -> void:
	# 正式AppIDがまだ発行されていないため、この定数へ480を書いてはならない。
	assert_ne(RBMSteamConfig.OFFICIAL_APP_ID, 480)

func test_reads_app_id_from_the_local_dev_file() -> void:
	_write_tmp_file("480")
	assert_eq(RBMSteamConfig.app_id(), 480)
	assert_true(RBMSteamConfig.is_configured())
	assert_true(RBMSteamConfig.is_using_development_override())

func test_ignores_local_file_with_non_integer_content() -> void:
	_write_tmp_file("not-a-number")
	assert_eq(RBMSteamConfig.app_id(), RBMSteamConfig.OFFICIAL_APP_ID)

func test_ignores_local_file_with_zero_or_negative_value() -> void:
	_write_tmp_file("0")
	assert_eq(RBMSteamConfig.app_id(), RBMSteamConfig.OFFICIAL_APP_ID)
	_write_tmp_file("-5")
	assert_eq(RBMSteamConfig.app_id(), RBMSteamConfig.OFFICIAL_APP_ID)

func test_missing_local_file_resolves_to_official_app_id_not_a_crash() -> void:
	assert_eq(RBMSteamConfig.app_id(), RBMSteamConfig.OFFICIAL_APP_ID)

func test_environment_variable_takes_priority_over_local_file() -> void:
	_write_tmp_file("480")
	OS.set_environment("STEAM_APP_ID", "999")
	assert_eq(RBMSteamConfig.app_id(), 999)
	OS.set_environment("STEAM_APP_ID", "")

func test_environment_variable_with_invalid_value_falls_back_to_local_file() -> void:
	_write_tmp_file("480")
	OS.set_environment("STEAM_APP_ID", "not-an-int")
	assert_eq(RBMSteamConfig.app_id(), 480)
	OS.set_environment("STEAM_APP_ID", "")
