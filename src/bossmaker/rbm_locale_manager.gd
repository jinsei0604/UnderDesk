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

## 言語設定のファイル。GUT（自動テスト）の中では、本物の設定に書かないよう、テスト用の置き場を使う
## （RBMLocalStageRepository.running_under_gut()。2026-10-18）。本物のゲームでは _SETTINGS_PATH。
static func settings_path() -> String:
	if RBMLocalStageRepository.running_under_gut():
		return RBMLocalStageRepository.GUT_DEFAULT_ROOT + "/settings.json"
	# 体験版は製品版と別の置き場（RBMEdition.data_root()）。製品版は今までどおり _SETTINGS_PATH。
	return _SETTINGS_PATH if not RBMEdition.is_demo() else RBMEdition.data_root() + "/settings.json"

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
	var path := settings_path()
	if not FileAccess.file_exists(path):
		return DEFAULT_LOCALE
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DEFAULT_LOCALE
	var text := file.get_as_text()
	file.close()
	# 壊れた設定は既定の言語にする（エラーを出力しない読み方）
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if parsed is Dictionary and parsed.has("locale") and SUPPORTED_LOCALES.has(parsed["locale"]):
		return String(parsed["locale"])
	return DEFAULT_LOCALE

## 書き込みは一時ファイルへ書いてから置き換える（書いている途中で終了しても、前の設定が残る。2026-10-18）。
func _save_locale(locale: String) -> void:
	RBMLocalStageRepository._atomic_write(settings_path(), JSON.stringify({"locale": locale}))
