class_name RBMSteamConfig
extends RefCounted

## Phase 4A-1 — Steam AppIDの読み込み専用クラス。static funcのみ
## （RBMSupabaseConfigと同じ既存方針をそのまま踏襲）。
##
## 値の解決優先順位:
##   1. 環境変数（STEAM_APP_ID、CI/自動テストでの上書きを想定）
##   2. ローカル開発設定ファイル（res://steam_dev_appid.local.txt、
##      .gitignore対象、実行ファイルと同じ場所に置くSteamworks公式の
##      steam_appid.txt規約とは別に、Godot側で明示的にsteamInitEx()へ
##      渡す値をこのファイル1つで管理する）
##   3. どちらにも無ければOFFICIAL_APP_ID（Phase 4A-1時点では0=未設定）
##
## §重要: Makers & Challengers正式AppIDが発行されたら、OFFICIAL_APP_ID
## を1箇所書き換えるだけで済む設計。480（ValveのSpacewar開発確認用ID）は
## この定数へ絶対に書かない——480は steam_dev_appid.local.txt という
## コミット対象外のファイルにのみ置く、開発者ローカルの一時値。
const OFFICIAL_APP_ID := 0

const ENV_APP_ID_KEY := "STEAM_APP_ID"
const DEFAULT_LOCAL_DEV_APP_ID_PATH := "res://steam_dev_appid.local.txt"

## RBMSupabaseConfigと同じテスト用フック。
static var _local_dev_app_id_path_override: String = ""

static func local_dev_app_id_path() -> String:
	return _local_dev_app_id_path_override if not _local_dev_app_id_path_override.is_empty() else DEFAULT_LOCAL_DEV_APP_ID_PATH

static func set_local_dev_app_id_path_for_testing(path: String) -> void:
	_local_dev_app_id_path_override = path

## 実際にsteamInitEx()等へ渡すAppID。0は「未設定」を意味し、呼び出し側
## （RBMSteamAuth）はこれをnot_configuredとして扱う。
static func app_id() -> int:
	var from_env := OS.get_environment(ENV_APP_ID_KEY)
	if not from_env.is_empty() and from_env.is_valid_int():
		var env_value := int(from_env)
		if env_value > 0:
			return env_value

	var from_local := _read_local_dev_app_id()
	if from_local > 0:
		return from_local

	return OFFICIAL_APP_ID

static func is_configured() -> bool:
	return app_id() > 0

## 現在解決されているAppIDが、正式値(OFFICIAL_APP_ID、Phase 4A-1時点では
## 未設定=0)ではなく、開発用の一時値（環境変数またはローカルファイル）
## から来ているかどうか——ログ・UI表示で「これは開発用AppIDです」と
## 明示するために使う。
static func is_using_development_override() -> bool:
	return is_configured() and app_id() != OFFICIAL_APP_ID

static func _read_local_dev_app_id() -> int:
	var path := local_dev_app_id_path()
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var text := file.get_as_text().strip_edges()
	if text.is_empty() or not text.is_valid_int():
		return 0
	return int(text)
