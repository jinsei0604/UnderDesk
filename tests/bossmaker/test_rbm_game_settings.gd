extends GutTest
## 設定（2026-11-08）: 全体・BGM・効果音の音量と全画面／ウィンドウ。RBMGameSettings（保存・反映）と RBMSettingsPanel（画面）。
## 全部 100% なら今までの音と同じ（0dB）。Master に出す音は SE バスへ向き、BGM は Music バスのまま。
## 本物のウィンドウは変えない（GUT の中では全画面の切り替えを反映しない）。

const TEST_FILE := "user://test_rbm_game_settings/game_settings.json"
var _saved_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()
	_remove(RBMGameSettings.file_path())

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)
	_remove(RBMGameSettings.file_path())
	_remove(TEST_FILE)
	# 音量を既定へ戻す（ほかのテストへ持ち越さない）
	var s := RBMGameSettings.new()
	s.apply_audio()
	s.free()

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _write(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TEST_FILE.get_base_dir())
	var f := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _settings() -> RBMGameSettings:
	var s := RBMGameSettings.new()
	add_child_autofree(s)
	return s

func _bus_db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))

func _bus_muted(bus: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))

func test_by_default_every_bus_stays_at_0db_like_before() -> void:
	_settings()
	for bus in ["Master", "Music", RBMGameSettings.SE_BUS]:
		assert_almost_eq(_bus_db(bus), 0.0, 0.001, bus)
		assert_false(_bus_muted(bus), bus)

func test_each_slider_moves_only_its_own_bus_and_zero_mutes() -> void:
	var s := _settings()
	s.set_volume("bgm", 0.5)
	assert_almost_eq(_bus_db("Music"), -12.04, 0.05, "50% is about -12 dB")
	assert_almost_eq(_bus_db("Master"), 0.0, 0.001)
	assert_almost_eq(_bus_db(RBMGameSettings.SE_BUS), 0.0, 0.001)
	s.set_volume("se", 0.0)
	assert_true(_bus_muted(RBMGameSettings.SE_BUS))
	assert_false(_bus_muted("Music"))
	s.set_volume("se", 1.0)
	assert_false(_bus_muted(RBMGameSettings.SE_BUS))
	s.set_volume("master", 0.0)
	assert_true(_bus_muted("Master"))

func test_the_se_bus_sends_to_master_so_the_limiter_still_applies() -> void:
	_settings()
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(RBMGameSettings.SE_BUS)), &"Master")

func test_players_on_master_go_to_the_se_bus_and_music_stays() -> void:
	_settings()
	var se := AudioStreamPlayer.new()
	add_child_autofree(se)
	assert_eq(se.bus, &"SE", "default-bus players are effects")
	var music := AudioStreamPlayer.new()
	music.bus = "Music"
	add_child_autofree(music)
	assert_eq(music.bus, &"Music")

func test_settings_are_saved_and_read_back() -> void:
	var s := _settings()
	s.set_volume("master", 0.8)
	s.set_volume("bgm", 0.25)
	s.set_fullscreen(false)
	var again := _settings()
	assert_almost_eq(float(again.volumes["master"]), 0.8, 0.001)
	assert_almost_eq(float(again.volumes["bgm"]), 0.25, 0.001)
	assert_almost_eq(float(again.volumes["se"]), 1.0, 0.001)
	assert_eq(again.fullscreen_choice, false)

func test_a_display_mode_is_not_chosen_until_the_player_picks_one() -> void:
	var s := _settings()
	assert_null(s.fullscreen_choice)
	s.set_volume("se", 0.5)
	assert_false(RBMGameSettings.read_file(RBMGameSettings.file_path()).has("fullscreen"), "changing a volume does not pin the display mode")

func test_broken_or_out_of_range_files_are_safe() -> void:
	_write("{broken")
	assert_eq(RBMGameSettings.read_file(TEST_FILE), {})
	_write(JSON.stringify({"master": 9, "bgm": -1, "se": "loud", "fullscreen": "yes"}))
	assert_eq(RBMGameSettings.read_file(TEST_FILE), {"master": 1.0, "bgm": 0.0})

func _root() -> RBMGameRoot:
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	return root

func test_the_home_button_opens_the_panel_and_sliders_save() -> void:
	var root := await _root()
	var button := root.find_child("SettingsButton", true, false) as Button
	var panel := root.find_child("SettingsPanel", true, false) as RBMSettingsPanel
	assert_not_null(button)
	assert_false(panel.visible)
	button.pressed.emit()
	assert_true(panel.visible)
	var slider := panel.find_child("SeVolumeSlider", true, false) as HSlider
	assert_almost_eq(slider.value, 1.0, 0.001)
	slider.value = 0.5
	assert_eq((panel.find_child("SeVolumePercent", true, false) as Label).text, "50%")
	assert_almost_eq(float(RBMGameSettings.read_file(RBMGameSettings.file_path())["se"]), 0.5, 0.001)
	(panel.find_child("SettingsCloseButton", true, false) as Button).pressed.emit()
	assert_false(panel.visible)

func test_the_panel_follows_the_language_both_ways() -> void:
	for boot in ["ja", "en"]:
		RBMLocale.set_locale(boot)
		var root := await _root()
		var other := "en" if boot == "ja" else "ja"
		RBMLocale.set_locale(other)
		await get_tree().process_frame
		var english := other == "en"
		assert_eq((root.find_child("SettingsButton", true, false) as Button).text, "Settings" if english else "設定")
		var panel := root.find_child("SettingsPanel", true, false)
		assert_eq((panel.find_child("SettingsTitle", true, false) as Label).text, "Settings" if english else "設定")
		assert_eq((panel.find_child("SeVolumeLabel", true, false) as Label).text, "Sound Effects Volume" if english else "効果音の音量")
		assert_eq((panel.find_child("FullscreenButton", true, false) as Button).text, "Fullscreen" if english else "全画面")
		assert_eq((panel.find_child("WindowedButton", true, false) as Button).text, "Windowed" if english else "ウィンドウ")
		assert_eq((panel.find_child("SettingsCloseButton", true, false) as Button).text, "Close" if english else "閉じる")
