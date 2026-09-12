extends Node

## 表示言語(日本語/English)の切り替えと永続化だけを担当するグローバル
## シングルトン(project.godotの[autoload]に登録)。
##
## 重要な境界線: これは「表示設定」であり、バトルロジック・セーブデータ・
## Clear Check・battle_content_snapshot()/battle_hash・オンラインボス
## データには一切関わらない。ここで持つ状態は「現在どの言語で文字列を
## 表示するか」という1つのStringだけで、TranslationServer.set_locale()
## を呼ぶ以外の副作用を持たない。既存のuser://bossmaker/配下の保存規約
## (rbm_local_stage_repository.gdのJSON保存)に合わせ、言語設定も
## user://bossmaker/settings.jsonへ別ファイルとして保存する——ボスの
## セーブデータ(user://bossmaker/stages/<stage_id>.json)とは完全に別の
## ファイルであり、混ざることはない。

signal locale_changed(locale: String)

const SUPPORTED_LOCALES := ["ja", "en"]
const DEFAULT_LOCALE := "ja"
const _SETTINGS_DIR := "user://bossmaker"
const _SETTINGS_PATH := "user://bossmaker/settings.json"

var _locale: String = DEFAULT_LOCALE

func _ready() -> void:
	_locale = _load_saved_locale()
	TranslationServer.set_locale(_locale)

func current_locale() -> String:
	return _locale

func set_locale(locale: String) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return
	if locale == _locale:
		return
	_locale = locale
	TranslationServer.set_locale(_locale)
	_save_locale(_locale)
	locale_changed.emit(_locale)

## ホーム画面の言語ボタン用: 現在と逆の言語へ切り替える。
func toggle_locale() -> void:
	var other := "en" if _locale == "ja" else "ja"
	set_locale(other)

func _load_saved_locale() -> String:
	if not FileAccess.file_exists(_SETTINGS_PATH):
		return DEFAULT_LOCALE
	var file := FileAccess.open(_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return DEFAULT_LOCALE
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary and parsed.has("locale") and SUPPORTED_LOCALES.has(parsed["locale"]):
		return String(parsed["locale"])
	return DEFAULT_LOCALE

func _save_locale(locale: String) -> void:
	DirAccess.make_dir_recursive_absolute(_SETTINGS_DIR)
	var file := FileAccess.open(_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"locale": locale}))
	file.close()
