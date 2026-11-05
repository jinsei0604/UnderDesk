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
## 自動テスト（GUT）の中の言語。本物のゲームの初めての起動は、下の順で自動に決める（2026-11-05）。
const DEFAULT_LOCALE := "ja"
## 初めての起動の言語の決め方（2026-11-05 ユーザー指示）: 1. ゲームの中でプレイヤーが選んだ言語 → 2. Steam のゲームの言語
## （GetCurrentGameLanguage）→ 3. PC の言語 → 4. 分からなければ英語。日本語・英語以外の言語は英語にする。
const FALLBACK_LOCALE := "en"
## 保存する「言語を決めたのは誰か」: プレイヤーが選んだ（manual）か、自動で決めた（auto）か。
## auto の間は起動のたびに決め直す（Steam・PC の言語を変えれば次の起動から変わる）。manual は上書きしない。
## 以前の版の設定（source が無い）は、プレイヤーが選んだ言語として扱う（既存の人の設定を変えない）。
const SOURCE_MANUAL := "manual"
const SOURCE_AUTO := "auto"
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
var _source: String = SOURCE_AUTO

func _ready() -> void:
	var saved := _load_saved()
	if RBMLocalStageRepository.running_under_gut() and saved.get("source", "") != SOURCE_MANUAL:
		# 自動テストの中は Steam に触れず、今までどおりの言語（PC の言語でテストの結果が変わらないように）
		_locale = str(saved.get("locale", DEFAULT_LOCALE))
		_source = SOURCE_AUTO
	else:
		# Steam の初期化は、プレイヤーが選んだ言語が無い時だけ（選んだ言語があれば Steam・PC の言語は見ない）
		var steam_language := "" if saved.get("source", "") == SOURCE_MANUAL else _steam_game_language()
		var decided := resolve_initial(saved, steam_language, OS.get_locale_language())
		_locale = str(decided["locale"])
		_source = str(decided["source"])
		if bool(decided["save"]):
			_save_locale(_locale, _source)
	TranslationServer.set_locale(_locale)

## 起動の時の言語を決める: プレイヤーが選んだ言語（saved の source が manual）があればそれをそのまま使い保存し直さない。
## 無ければ Steam・PC の言語から決めて auto として保存する。戻り値 {locale, source, save}。
static func resolve_initial(saved: Dictionary, steam_language: String, os_language: String) -> Dictionary:
	if saved.get("source", "") == SOURCE_MANUAL and SUPPORTED_LOCALES.has(saved.get("locale", "")):
		return {"locale": str(saved["locale"]), "source": SOURCE_MANUAL, "save": false}
	return {"locale": choose_locale(steam_language, os_language), "source": SOURCE_AUTO, "save": true}

## 言語の決め方（Steam のゲームの言語 → PC の言語 → 英語）。steam_language は Steam の言語の名前（"japanese"・"english" など、
## 取れなければ空）、os_language は PC の言語のコード（"ja"・"en" など）。
static func choose_locale(steam_language: String, os_language: String) -> String:
	var steam := steam_language.strip_edges().to_lower()
	if not steam.is_empty():
		return "ja" if steam == "japanese" else FALLBACK_LOCALE
	var os_lang := os_language.strip_edges().to_lower()
	if os_lang.begins_with("ja"):
		return "ja"
	return FALLBACK_LOCALE

## Steam のゲームの言語（Steam のライブラリのゲームのプロパティで選んだ言語）。Steam が無い・起動していない・
## 初期化できない時は空。オンライン機能と同じ AppID で Steam を初期化する（同じ初期化を何度呼んでも安全。RBMSteamAuth と同じ）。
static func _steam_game_language() -> String:
	if DisplayServer.get_name() == "headless" or not Engine.has_singleton("Steam") or not RBMSteamConfig.is_configured():
		return ""
	var result := RBMSteamAdapter.new().init_ex(RBMSteamConfig.app_id(), false)
	if int(result.get("status", 1)) != 0:
		return ""
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("getCurrentGameLanguage"):
		return ""
	return str(steam.call("getCurrentGameLanguage"))

## 言語を決めたのが自動（auto）か、プレイヤー（manual）か。
func locale_source() -> String:
	return _source

func current_locale() -> String:
	return _locale

func set_locale(locale: String) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return
	if locale == _locale:
		return
	_locale = locale
	_source = SOURCE_MANUAL
	TranslationServer.set_locale(_locale)
	_save_locale(_locale, SOURCE_MANUAL)
	locale_changed.emit(_locale)

## ホーム画面の言語ボタン用: 現在と逆の言語へ切り替える。
func toggle_locale() -> void:
	var other := "en" if _locale == "ja" else "ja"
	set_locale(other)

## 保存した設定 {locale, source}。無い・壊れている時は空。source の無い以前の版の設定は manual（プレイヤーが選んだ）として読む。
static func _load_saved(path: String = "") -> Dictionary:
	if path.is_empty():
		path = settings_path()
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	# 壊れた設定は無かったことにする（エラーを出力しない読み方）
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if parsed is Dictionary and parsed.has("locale") and SUPPORTED_LOCALES.has(parsed["locale"]):
		var source := str(parsed.get("source", SOURCE_MANUAL))
		return {"locale": String(parsed["locale"]), "source": SOURCE_AUTO if source == SOURCE_AUTO else SOURCE_MANUAL}
	return {}

## 書き込みは一時ファイルへ書いてから置き換える（書いている途中で終了しても、前の設定が残る。2026-10-18）。
func _save_locale(locale: String, source: String) -> void:
	RBMLocalStageRepository._atomic_write(settings_path(), JSON.stringify({"locale": locale, "source": source}))
