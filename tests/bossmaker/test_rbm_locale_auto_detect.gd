extends GutTest
## 初めての起動の言語の自動判定（2026-11-05 ユーザー指示）:
## 1. ゲームの中でプレイヤーが選んだ言語 → 2. Steam のゲームの言語（GetCurrentGameLanguage）→ 3. PC の言語 → 4. 英語。
## プレイヤーが選んだ言語は上書きしない（以前の版の設定 = source の無い設定も、選んだ言語として扱う）。
## 自動で決めた言語は auto として保存し、起動のたびに決め直す。ここでは本物の Steam には触れない（判定の関数と保存の形を試す）。
const Locale := preload("res://src/bossmaker/rbm_locale_manager.gd")
const TEST_FILE := "user://test_rbm_locale_auto_detect/settings.json"

var _saved_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()
	DirAccess.make_dir_recursive_absolute(TEST_FILE.get_base_dir())

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(TEST_FILE)

func _write(text: String) -> void:
	var f := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_steam_language_comes_before_the_pc_language() -> void:
	assert_eq(Locale.choose_locale("japanese", "en"), "ja")
	assert_eq(Locale.choose_locale("english", "ja"), "en")
	assert_eq(Locale.choose_locale("  Japanese ", "en"), "ja", "Steam's name is read without case or spaces")

func test_a_steam_language_other_than_japanese_or_english_is_english() -> void:
	for lang in ["french", "schinese", "german", "koreana"]:
		assert_eq(Locale.choose_locale(lang, "ja"), "en", lang)

func test_without_steam_the_pc_language_decides_and_unknown_is_english() -> void:
	assert_eq(Locale.choose_locale("", "ja"), "ja")
	assert_eq(Locale.choose_locale("", "ja_JP"), "ja")
	assert_eq(Locale.choose_locale("", "en"), "en")
	assert_eq(Locale.choose_locale("", "de"), "en")
	assert_eq(Locale.choose_locale("", ""), "en", "nothing known: English")

func test_a_language_the_player_chose_is_never_overwritten() -> void:
	var r := Locale.resolve_initial({"locale": "en", "source": "manual"}, "japanese", "ja")
	assert_eq(r, {"locale": "en", "source": "manual", "save": false})
	r = Locale.resolve_initial({"locale": "ja", "source": "manual"}, "english", "en")
	assert_eq(r, {"locale": "ja", "source": "manual", "save": false})

func test_an_automatic_choice_is_decided_again_and_saved_as_auto() -> void:
	assert_eq(Locale.resolve_initial({"locale": "ja", "source": "auto"}, "english", "ja"), {"locale": "en", "source": "auto", "save": true})
	assert_eq(Locale.resolve_initial({}, "", "ja"), {"locale": "ja", "source": "auto", "save": true}, "first launch on a Japanese PC without Steam")
	assert_eq(Locale.resolve_initial({}, "", "fr"), {"locale": "en", "source": "auto", "save": true})

func test_old_settings_without_a_source_count_as_the_players_choice() -> void:
	_write(JSON.stringify({"locale": "en"}))
	assert_eq(Locale._load_saved(TEST_FILE), {"locale": "en", "source": "manual"})
	_write(JSON.stringify({"locale": "ja", "source": "auto"}))
	assert_eq(Locale._load_saved(TEST_FILE), {"locale": "ja", "source": "auto"})
	_write("{broken")
	assert_eq(Locale._load_saved(TEST_FILE), {})
	_write(JSON.stringify({"locale": "fr", "source": "manual"}))
	assert_eq(Locale._load_saved(TEST_FILE), {}, "an unsupported language is ignored")

func test_switching_in_game_saves_the_language_as_the_players_choice() -> void:
	var other := "en" if RBMLocale.current_locale() == "ja" else "ja"
	RBMLocale.set_locale(other)
	assert_eq(RBMLocale.locale_source(), "manual")
	assert_eq(Locale._load_saved(Locale.settings_path()), {"locale": other, "source": "manual"}, "kept after a restart")
