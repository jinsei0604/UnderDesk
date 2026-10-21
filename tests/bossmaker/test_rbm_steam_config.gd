extends GutTest

## RBMSupabaseConfigのテストと同じ形——実ファイルには触れず、テスト専用
## パスへ差し替えて検証する。
## 2026-10-21: 正式AppID 5482410。GUT の中では、テストが明示した値（環境変数・テスト用のファイル）が無い限り
## 未設定（0）になり、開発機で起動している本物の Steam を正式 AppID で初期化しない。
## 「GUT の外（本物のゲーム）」は RBMLocalStageRepository._under_gut を一時的に 0 にして確かめ、終わったら判定し直させる。

const REGISTERED_APP_ID := 5482410

var _tmp_path := "user://test_steam_dev_appid.local.txt"

func before_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing(_tmp_path)
	_delete_tmp_file()

func after_each() -> void:
	RBMSteamConfig.set_local_dev_app_id_path_for_testing("")
	_delete_tmp_file()
	OS.set_environment("STEAM_APP_ID", "")
	# 次に聞かれた時に、起動の引数から GUT の中かを判定し直す
	RBMLocalStageRepository._under_gut = -1

func _delete_tmp_file() -> void:
	if FileAccess.file_exists(_tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_tmp_path))

func _write_tmp_file(text: String) -> void:
	var file := FileAccess.open(_tmp_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _as_if_outside_gut() -> void:
	RBMLocalStageRepository._under_gut = 0

func test_official_app_id_is_the_registered_steam_app_id() -> void:
	assert_eq(RBMSteamConfig.OFFICIAL_APP_ID, REGISTERED_APP_ID)

func test_official_app_id_constant_is_not_480() -> void:
	# 480（Valve の Spacewar）は開発の試し用。正式 AppID の定数へ書いてはならない。
	assert_ne(RBMSteamConfig.OFFICIAL_APP_ID, 480)

func test_under_gut_without_an_explicit_value_is_not_configured() -> void:
	assert_true(RBMLocalStageRepository.running_under_gut(), "sanity: GUT の中")
	assert_eq(RBMSteamConfig.app_id(), 0, "テストが本物の Steam を正式 AppID で初期化しない")
	assert_false(RBMSteamConfig.is_configured())

func test_the_game_outside_gut_uses_the_official_app_id() -> void:
	_as_if_outside_gut()
	assert_eq(RBMSteamConfig.app_id(), REGISTERED_APP_ID)
	assert_true(RBMSteamConfig.is_configured())
	assert_false(RBMSteamConfig.is_using_development_override())

func test_reads_app_id_from_the_local_dev_file() -> void:
	_write_tmp_file("480")
	assert_eq(RBMSteamConfig.app_id(), 480)
	assert_true(RBMSteamConfig.is_configured())
	assert_true(RBMSteamConfig.is_using_development_override())

func test_local_dev_file_still_wins_over_the_official_app_id_outside_gut() -> void:
	_as_if_outside_gut()
	_write_tmp_file("480")
	assert_eq(RBMSteamConfig.app_id(), 480)
	assert_true(RBMSteamConfig.is_using_development_override())

func test_ignores_local_file_with_non_integer_content() -> void:
	_write_tmp_file("not-a-number")
	assert_eq(RBMSteamConfig.app_id(), 0)
	_as_if_outside_gut()
	assert_eq(RBMSteamConfig.app_id(), REGISTERED_APP_ID)

func test_ignores_local_file_with_zero_or_negative_value() -> void:
	_write_tmp_file("0")
	assert_eq(RBMSteamConfig.app_id(), 0)
	_write_tmp_file("-5")
	assert_eq(RBMSteamConfig.app_id(), 0)
	_as_if_outside_gut()
	assert_eq(RBMSteamConfig.app_id(), REGISTERED_APP_ID)

func test_missing_local_file_is_not_a_crash() -> void:
	assert_eq(RBMSteamConfig.app_id(), 0)
	_as_if_outside_gut()
	assert_eq(RBMSteamConfig.app_id(), REGISTERED_APP_ID)

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
